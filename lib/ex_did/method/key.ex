defmodule ExDid.Method.Key do
  @moduledoc """
  Deterministic local `did:key` resolver.
  """

  @behaviour ExDid.Method

  alias ExDid.Base58Btc
  alias ExDid.DIDURL
  alias ExDid.DereferencingResult
  alias ExDid.Document
  alias ExDid.Error
  alias ExDid.Representation
  alias ExDid.KeyMulticodec
  alias ExDid.RepresentationResult
  alias ExDid.ResolveOptions
  alias ExDid.ResolutionResult

  @impl true
  @spec resolve(DIDURL.t(), ResolveOptions.t()) :: ResolutionResult.t()
  def resolve(%DIDURL{} = did_url, %ResolveOptions{} = options) do
    did = DIDURL.did_string(did_url)

    with {:ok, descriptor} <- descriptor(did_url),
         document <- build_document(did, descriptor, options.validation),
         :ok <- Document.validate(document, did, options.validation) do
      ResolutionResult.ok(
        document,
        %{"source" => "local"},
        %{"contentType" => "application/did+json", "retrieved" => "local"}
      )
    else
      {:error, %Error{} = error} -> ResolutionResult.error(error)
    end
  end

  @impl true
  @spec resolve_representation(DIDURL.t(), ResolveOptions.t()) :: RepresentationResult.t()
  def resolve_representation(%DIDURL{} = did_url, %ResolveOptions{} = options) do
    result = resolve(did_url, options)

    case result.did_document do
      %{} = document ->
        with {:ok, content_type} <- Representation.negotiate(document, options.representation) do
          RepresentationResult.ok(
            Jason.encode!(document),
            content_type,
            result.did_document_metadata,
            Map.put(result.did_resolution_metadata, "contentType", content_type)
          )
        else
          {:error, %Error{} = error} ->
            RepresentationResult.error(error)
        end

      nil ->
        RepresentationResult.error(Error.invalid_did(did_url.did.value))
    end
  end

  @impl true
  @spec dereference(DIDURL.t(), ResolveOptions.t()) :: DereferencingResult.t()
  def dereference(%DIDURL{} = did_url, %ResolveOptions{} = options) do
    result = resolve(%{did_url | params: [], path: nil, query: nil, fragment: nil}, options)

    with %{} = document <- result.did_document,
         {:ok, resource} <- Document.dereference(document, did_url) do
      DereferencingResult.ok(decorate_resource(resource), %{did_document: did_url.did.value}, %{
        "contentType" => "application/did+json"
      })
    else
      {:error, %Error{} = error} ->
        DereferencingResult.error(error)

      nil ->
        DereferencingResult.error(
          Error.not_found(did_url.did.value, "DID URL did not dereference to a resource")
        )
    end
  end

  @impl true
  @spec resolve_url(DIDURL.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def resolve_url(%DIDURL{did: did}),
    do:
      {:error,
       Error.unsupported_operation("did:key does not resolve to an HTTPS URL", %{did: did.value})}

  @doc """
  Returns the canonical verification method identifier for a `did:key` DID.
  """
  @spec verification_method_id(DIDURL.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def verification_method_id(%DIDURL{} = did_url) do
    with {:ok, descriptor} <- descriptor(did_url) do
      {:ok, DIDURL.did_string(did_url) <> "#" <> descriptor.fingerprint}
    end
  end

  defp descriptor(%DIDURL{method_specific_id: fingerprint} = did_url) do
    with {:ok, multibase_bytes} <- Base58Btc.decode(fingerprint),
         {:ok, descriptor} <- KeyMulticodec.decode(multibase_bytes) do
      {:ok,
       Map.put(descriptor, :fingerprint, fingerprint) |> Map.put(:did, DIDURL.did_string(did_url))}
    else
      {:error, :invalid_multibase} ->
        {:error, Error.invalid_did(DIDURL.did_string(did_url), %{reason: :invalid_multibase})}

      {:error, :invalid_base58} ->
        {:error, Error.invalid_did(DIDURL.did_string(did_url), %{reason: :invalid_base58})}

      {:error, :unsupported_multicodec} ->
        {:error,
         Error.invalid_did(DIDURL.did_string(did_url), %{reason: :unsupported_multicodec})}
    end
  end

  defp build_document(did, descriptor, :strict) do
    method_id = did <> "#" <> descriptor.fingerprint

    relationships =
      case descriptor.key_type do
        :x25519 ->
          %{
            "keyAgreement" => [
              multikey_resource(method_id, did, descriptor.fingerprint)
            ]
          }

        :ed25519 ->
          case KeyMulticodec.derive_x25519_multibase(descriptor.public_key_bytes) do
            {:ok, key_agreement_fingerprint} ->
              %{
                "verificationMethod" => [
                  multikey_resource(method_id, did, descriptor.fingerprint)
                ],
                "authentication" => [method_id],
                "assertionMethod" => [method_id],
                "capabilityInvocation" => [method_id],
                "capabilityDelegation" => [method_id],
                "keyAgreement" => [
                  multikey_resource(
                    did <> "#" <> key_agreement_fingerprint,
                    did,
                    key_agreement_fingerprint
                  )
                ]
              }

            {:error, _reason} ->
              %{
                "verificationMethod" => [
                  multikey_resource(method_id, did, descriptor.fingerprint)
                ],
                "authentication" => [method_id],
                "assertionMethod" => [method_id],
                "capabilityInvocation" => [method_id],
                "capabilityDelegation" => [method_id]
              }
          end

        _ ->
          %{
            "verificationMethod" => [
              multikey_resource(method_id, did, descriptor.fingerprint)
            ],
            "authentication" => [method_id],
            "assertionMethod" => [method_id],
            "capabilityInvocation" => [method_id],
            "capabilityDelegation" => [method_id]
          }
      end

    Map.merge(
      base_document(did, relationships, ["https://w3id.org/security/multikey/v1"]),
      relationships
    )
  end

  defp build_document(did, descriptor, :compat) do
    method_id = did <> "#" <> descriptor.fingerprint

    relationships =
      case descriptor.key_type do
        :x25519 ->
          %{
            "keyAgreement" => [
              legacy_x25519_resource(method_id, did, descriptor.fingerprint)
            ]
          }

        :ed25519 ->
          case KeyMulticodec.derive_x25519_multibase(descriptor.public_key_bytes) do
            {:ok, key_agreement_fingerprint} ->
              %{
                "verificationMethod" => [
                  legacy_ed25519_resource(method_id, did, descriptor.fingerprint)
                ],
                "authentication" => [method_id],
                "assertionMethod" => [method_id],
                "capabilityInvocation" => [method_id],
                "capabilityDelegation" => [method_id],
                "keyAgreement" => [
                  legacy_x25519_resource(
                    did <> "#" <> key_agreement_fingerprint,
                    did,
                    key_agreement_fingerprint
                  )
                ]
              }

            {:error, _reason} ->
              %{
                "verificationMethod" => [
                  legacy_ed25519_resource(method_id, did, descriptor.fingerprint)
                ],
                "authentication" => [method_id],
                "assertionMethod" => [method_id],
                "capabilityInvocation" => [method_id],
                "capabilityDelegation" => [method_id]
              }
          end

        _ ->
          %{
            "verificationMethod" => [
              multikey_resource(method_id, did, descriptor.fingerprint)
            ],
            "authentication" => [method_id],
            "assertionMethod" => [method_id],
            "capabilityInvocation" => [method_id],
            "capabilityDelegation" => [method_id]
          }
      end

    contexts =
      case descriptor.key_type do
        :ed25519 -> ["https://w3id.org/security/suites/ed25519-2020/v1"]
        :x25519 -> []
        _ -> ["https://w3id.org/security/multikey/v1"]
      end

    Map.merge(base_document(did, relationships, contexts), relationships)
  end

  defp base_document(did, relationships, contexts) do
    document = %{
      "@context" =>
        ([
           "https://www.w3.org/ns/did/v1"
         ] ++ contexts ++ key_agreement_contexts(relationships))
        |> Enum.uniq(),
      "id" => did
    }

    case Map.get(relationships, "verificationMethod") do
      methods when is_list(methods) and methods != [] ->
        Map.put(document, "verificationMethod", methods)

      _ ->
        document
    end
  end

  defp legacy_ed25519_resource(id, did, fingerprint) do
    %{
      "id" => id,
      "type" => "Ed25519VerificationKey2020",
      "controller" => did,
      "publicKeyMultibase" => fingerprint
    }
  end

  defp multikey_resource(id, did, fingerprint) do
    %{
      "id" => id,
      "type" => "Multikey",
      "controller" => did,
      "publicKeyMultibase" => fingerprint
    }
  end

  defp legacy_x25519_resource(id, did, fingerprint) do
    %{
      "id" => id,
      "type" => "X25519KeyAgreementKey2020",
      "controller" => did,
      "publicKeyMultibase" => fingerprint
    }
  end

  defp decorate_resource(%{"type" => type} = resource) do
    case verification_method_context(type) do
      nil -> resource
      context -> Map.put(resource, "@context", context)
    end
  end

  defp decorate_resource(resource), do: resource

  defp verification_method_context("Ed25519VerificationKey2020"),
    do: "https://w3id.org/security/suites/ed25519-2020/v1"

  defp verification_method_context("X25519KeyAgreementKey2020"),
    do: "https://w3id.org/security/suites/x25519-2020/v1"

  defp verification_method_context("Multikey"),
    do: "https://w3id.org/security/multikey/v1"

  defp verification_method_context(_), do: nil

  defp key_agreement_contexts(%{"keyAgreement" => [%{"type" => "X25519KeyAgreementKey2020"} | _]}),
    do: ["https://w3id.org/security/suites/x25519-2020/v1"]

  defp key_agreement_contexts(%{"keyAgreement" => [%{"type" => "Multikey"} | _]}),
    do: ["https://w3id.org/security/multikey/v1"]

  defp key_agreement_contexts(_), do: []
end
