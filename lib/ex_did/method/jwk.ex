defmodule ExDid.Method.Jwk do
  @moduledoc """
  Deterministic local `did:jwk` resolver.
  """

  @behaviour ExDid.Method

  alias ExDid.DIDURL
  alias ExDid.DereferencingResult
  alias ExDid.Document
  alias ExDid.Error
  alias ExDid.Representation
  alias ExDid.RepresentationResult
  alias ExDid.ResolveOptions
  alias ExDid.ResolutionResult

  @impl true
  @spec resolve(DIDURL.t(), ResolveOptions.t()) :: ResolutionResult.t()
  def resolve(%DIDURL{} = did_url, %ResolveOptions{} = options) do
    did = DIDURL.did_string(did_url)

    with {:ok, jwk} <- decode_jwk(did_url),
         {:ok, public_jwk} <- sanitize_jwk(jwk, options.validation, did),
         {:ok, document} <- build_document(did, public_jwk, options.validation),
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
      DereferencingResult.ok(
        decorate_resource(resource),
        %{did_document: did_url.did.value},
        %{"contentType" => "application/did+json"}
      )
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
       Error.unsupported_operation("did:jwk does not resolve to an HTTPS URL", %{did: did.value})}

  @doc """
  Returns the canonical verification method identifier for a `did:jwk` DID.
  """
  @spec verification_method_id(DIDURL.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def verification_method_id(%DIDURL{} = did_url) do
    with {:ok, _jwk} <- decode_jwk(did_url) do
      {:ok, DIDURL.did_string(did_url) <> "#0"}
    end
  end

  defp decode_jwk(%DIDURL{method_specific_id: encoded} = did_url) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, jwk} when is_map(jwk) ->
            {:ok, jwk}

          _ ->
            {:error, Error.invalid_did(DIDURL.did_string(did_url), %{reason: :invalid_jwk_json})}
        end

      :error ->
        {:error, Error.invalid_did(DIDURL.did_string(did_url), %{reason: :invalid_base64url})}
    end
  end

  defp sanitize_jwk(%{"d" => _}, :strict, did),
    do: {:error, Error.invalid_did(did, %{reason: :private_jwk_not_allowed})}

  defp sanitize_jwk(jwk, validation, did) when validation in [:strict, :compat] do
    public_jwk =
      jwk
      |> Map.drop(["d", "p", "q", "dp", "dq", "qi", "oth", "k"])

    if valid_public_jwk?(public_jwk) do
      {:ok, public_jwk}
    else
      {:error, Error.invalid_did(did, %{reason: :invalid_public_jwk})}
    end
  end

  defp valid_public_jwk?(%{"kty" => "OKP", "crv" => crv, "x" => x})
       when crv in ["Ed25519", "X25519"] and is_binary(x),
       do: true

  defp valid_public_jwk?(%{"kty" => "EC", "crv" => crv, "x" => x, "y" => y})
       when crv in ["P-256", "P-384", "P-521", "secp256k1"] and is_binary(x) and is_binary(y),
       do: true

  defp valid_public_jwk?(%{"kty" => "RSA", "n" => n, "e" => e})
       when is_binary(n) and is_binary(e),
       do: true

  defp valid_public_jwk?(_), do: false

  defp build_document(did, public_jwk, validation) when validation in [:strict, :compat] do
    method_id = did <> "#0"

    relationships =
      case public_jwk do
        %{"kty" => "OKP", "crv" => "X25519"} ->
          %{"keyAgreement" => [method_id]}

        _ ->
          %{
            "authentication" => [method_id],
            "assertionMethod" => [method_id],
            "capabilityInvocation" => [method_id],
            "capabilityDelegation" => [method_id]
          }
      end

    {:ok,
     Map.merge(
       %{
         "@context" => [
           "https://www.w3.org/ns/did/v1",
           "https://w3id.org/security/jwk/v1"
         ],
         "id" => did,
         "verificationMethod" => [
           %{
             "id" => method_id,
             "type" => "JsonWebKey",
             "controller" => did,
             "publicKeyJwk" => public_jwk
           }
         ]
       },
       relationships
     )}
  end

  defp decorate_resource(%{} = resource),
    do: Map.put_new(resource, "@context", "https://w3id.org/security/jwk/v1")
end
