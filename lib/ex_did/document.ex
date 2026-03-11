defmodule ExDid.Document do
  @moduledoc false

  alias ExDid.DIDURL
  alias ExDid.Error
  alias ExDid.KeyMulticodec

  @relationship_keys [
    "authentication",
    "assertionMethod",
    "keyAgreement",
    "capabilityInvocation",
    "capabilityDelegation"
  ]

  @spec verification_methods(map()) :: [map()]
  def verification_methods(document) when is_map(document) do
    List.wrap(Map.get(document, "verificationMethod", [])) ++
      List.wrap(Map.get(document, "publicKey", []))
  end

  @spec verification_method_jwks(map()) :: [map()]
  def verification_method_jwks(document) when is_map(document) do
    document
    |> verification_methods()
    |> Enum.flat_map(fn
      %{"publicKeyJwk" => %{} = jwk} ->
        [jwk]

      %{"publicKeyMultibase" => multibase} when is_binary(multibase) ->
        case KeyMulticodec.public_jwk(multibase) do
          {:ok, jwk} -> [jwk]
          {:error, _reason} -> []
        end

      _ ->
        []
    end)
  end

  @spec dereference(map(), DIDURL.t()) :: {:ok, map()} | {:error, Error.t()}
  def dereference(document, %DIDURL{} = did_url) do
    cond do
      did_url.path ->
        dereference_service_path(document, did_url)

      did_url.query ->
        dereference_service_query(document, did_url)

      did_url.params != [] ->
        {:error,
         Error.unsupported_operation(
           "DID URL parameters are not supported during dereferencing",
           %{
             params: did_url.params
           }
         )}

      did_url.fragment ->
        dereference_fragment(document, did_url)

      true ->
        {:ok, document}
    end
  end

  @spec validate(map(), String.t(), ExDid.validation_mode()) :: :ok | {:error, Error.t()}
  def validate(document, did, validation) when is_map(document) do
    with :ok <- validate_id(document, did),
         :ok <- validate_resource_ids(document, did),
         :ok <- validate_unique_ids(document, did),
         :ok <- validate_relationships(document, did),
         :ok <- validate_services(document, validation) do
      :ok
    end
  end

  defp validate_id(document, did) do
    if Map.get(document, "id") == did do
      :ok
    else
      {:error, Error.invalid_did_document(did, %{reason: :id_mismatch})}
    end
  end

  defp validate_resource_ids(document, did) do
    valid? =
      document
      |> gather_indexable_resources()
      |> Enum.all?(fn
        %{"id" => id} when is_binary(id) -> valid_resource_id?(id, did)
        %{} -> false
        _ -> false
      end)

    if valid? do
      :ok
    else
      {:error, Error.invalid_did_document(did, %{reason: :invalid_resource_id})}
    end
  end

  defp validate_unique_ids(document, did) do
    ids =
      document
      |> gather_indexable_resources()
      |> Enum.flat_map(fn
        %{"id" => id} when is_binary(id) -> [canonical_id(id, did)]
        _ -> []
      end)

    if Enum.uniq(ids) == ids do
      :ok
    else
      {:error, Error.invalid_did_document(did, %{reason: :duplicate_ids})}
    end
  end

  defp validate_relationships(document, did) do
    known_ids =
      document
      |> gather_indexable_resources()
      |> Enum.flat_map(fn
        %{"id" => id} when is_binary(id) -> [canonical_id(id, did)]
        _ -> []
      end)
      |> MapSet.new()

    if Enum.all?(@relationship_keys, &relationship_valid?(document, &1, known_ids, did)) do
      :ok
    else
      {:error, Error.invalid_did_document(did, %{reason: :dangling_relationship_reference})}
    end
  end

  defp validate_services(document, :compat) do
    service = Map.get(document, "service")

    cond do
      is_nil(service) ->
        :ok

      is_map(service) ->
        :ok

      is_list(service) ->
        validate_service_entries(service)

      true ->
        {:error,
         Error.invalid_did_document(Map.get(document, "id"), %{reason: :invalid_service_shape})}
    end
  end

  defp validate_services(document, :strict) do
    service = Map.get(document, "service")

    cond do
      is_nil(service) ->
        :ok

      is_list(service) ->
        validate_service_entries(service)

      true ->
        {:error,
         Error.invalid_did_document(Map.get(document, "id"), %{reason: :invalid_service_shape})}
    end
  end

  defp validate_service_entries(entries) do
    if Enum.all?(entries, &valid_service_entry?/1) do
      :ok
    else
      {:error, Error.invalid_did_document("service", %{reason: :invalid_service_entry})}
    end
  end

  defp valid_service_entry?(%{"id" => id, "type" => type, "serviceEndpoint" => endpoint})
       when is_binary(id) and is_binary(type) and
              (is_binary(endpoint) or is_map(endpoint) or is_list(endpoint)),
       do: true

  defp valid_service_entry?(_), do: false

  defp dereference_fragment(document, did_url) do
    reference = DIDURL.fragment_reference(did_url)
    did = DIDURL.did_string(did_url)

    document
    |> gather_indexable_resources()
    |> Enum.find_value(fn resource ->
      if resource_id_matches?(resource, reference, did), do: resource, else: nil
    end)
    |> case do
      nil -> {:error, Error.not_found(reference, "DID URL did not dereference to a resource")}
      resource -> {:ok, resource}
    end
  end

  defp dereference_service_path(document, did_url) do
    case service_selection(document, did_url) do
      {:ok, service} ->
        {:ok,
         %{
           "id" => canonical_id(service["id"], DIDURL.did_string(did_url)),
           "serviceEndpoint" => service["serviceEndpoint"],
           "path" => did_url.path
         }}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp dereference_service_query(document, did_url) do
    case service_selection(document, did_url) do
      {:ok, service} ->
        {:ok,
         %{
           "id" => canonical_id(service["id"], DIDURL.did_string(did_url)),
           "serviceEndpoint" => service["serviceEndpoint"],
           "query" => did_url.query
         }}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  defp service_selection(document, did_url) do
    service_name =
      did_url.params
      |> Enum.find_value(fn
        %{name: "service", value: value} -> value
        _ -> nil
      end)

    services = List.wrap(Map.get(document, "service", []))

    case Enum.find(services, fn %{"id" => id} ->
           String.trim_leading(id, "#") == service_name
         end) do
      nil ->
        {:error, Error.not_found(DIDURL.did_string(did_url), "No matching service was found")}

      service ->
        {:ok, service}
    end
  end

  defp relationship_valid?(document, key, known_ids, did) do
    document
    |> Map.get(key, [])
    |> List.wrap()
    |> Enum.all?(fn
      ref when is_binary(ref) -> MapSet.member?(known_ids, canonical_id(ref, did))
      %{"id" => id} when is_binary(id) -> MapSet.member?(known_ids, canonical_id(id, did))
      _ -> false
    end)
  end

  defp gather_indexable_resources(document) do
    services = List.wrap(Map.get(document, "service", []))

    relationship_resources =
      @relationship_keys
      |> Enum.flat_map(fn key ->
        document
        |> Map.get(key, [])
        |> List.wrap()
        |> Enum.filter(&is_map/1)
      end)

    [document | verification_methods(document) ++ relationship_resources ++ services]
  end

  defp resource_id_matches?(%{"id" => id}, reference, did) when is_binary(id) do
    canonical_id(id, did) == canonical_id(reference, did)
  end

  defp resource_id_matches?(_, _, _), do: false

  defp canonical_id("#" <> fragment, did), do: did <> "#" <> fragment
  defp canonical_id(id, _did), do: id

  defp valid_resource_id?("#" <> fragment, _did),
    do: fragment != "" and not String.contains?(fragment, "/")

  defp valid_resource_id?(id, _did) when is_binary(id) do
    case URI.parse(id) do
      %URI{scheme: scheme} when is_binary(scheme) and scheme != "" -> true
      _ -> false
    end
  end
end
