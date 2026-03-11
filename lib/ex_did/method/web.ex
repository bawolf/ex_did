defmodule ExDid.Method.Web do
  @moduledoc """
  `did:web` resolver.
  """

  @behaviour ExDid.Method

  alias ExDid.DIDURL
  alias ExDid.DereferencingResult
  alias ExDid.Document
  alias ExDid.Error
  alias ExDid.Fetcher
  alias ExDid.RepresentationResult
  alias ExDid.Representation
  alias ExDid.ResolveOptions
  alias ExDid.ResolutionResult

  @well_known_path "/.well-known/did.json"

  @doc """
  Resolves a `did:web` DID.
  """
  @impl true
  @spec resolve(DIDURL.t(), ResolveOptions.t()) :: ResolutionResult.t()
  def resolve(%DIDURL{} = did_url, %ResolveOptions{} = options) do
    did = DIDURL.did_string(did_url)

    with {:ok, url} <- resolve_url(did_url),
         {:ok, document, fetch_metadata} <- fetch_json(url, options),
         :ok <- validate_response_content_type(fetch_metadata, options.validation, did),
         :ok <-
           Document.validate(
             normalize_document(document, options.validation),
             did,
             options.validation
           ) do
      document = normalize_document(document, options.validation)

      ResolutionResult.ok(
        document,
        %{"sourceUrl" => url},
        %{
          "contentType" =>
            content_type(
              document,
              fetch_metadata["content-type"] || fetch_metadata[:content_type]
            ),
          "retrieved" =>
            DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
          "fetched" => stringify_keys(fetch_metadata)
        }
      )
    else
      {:error, %Error{} = error} ->
        ResolutionResult.error(error)
    end
  end

  @doc """
  Builds a canonical `did:web` identifier from a host and optional path segments.
  """
  @spec did(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, Error.t()}
  def did(host, path_segments \\ [])

  def did(host, path_segments) when is_binary(host) and is_list(path_segments) do
    with :ok <- validate_host(host),
         :ok <- validate_path_segments(path_segments) do
      encoded_host = host |> String.split(":") |> Enum.map_join("%3A", & &1)

      encoded_segments =
        Enum.map(path_segments, fn segment ->
          if String.contains?(segment, ":") do
            URI.encode(segment, &(&1 != ?:))
          else
            URI.encode(segment)
          end
        end)

      {:ok, Enum.join(["did:web", encoded_host | encoded_segments], ":")}
    end
  end

  def did(host, _path_segments), do: {:error, Error.invalid_did("did:web:" <> to_string(host))}

  @doc """
  Resolves the JSON representation for a `did:web` DID.
  """
  @impl true
  @spec resolve_representation(DIDURL.t(), ResolveOptions.t()) :: RepresentationResult.t()
  def resolve_representation(%DIDURL{} = did_url, %ResolveOptions{} = options) do
    result = resolve(did_url, options)

    case result.did_document do
      %{} = document ->
        requested_content_type =
          if options.representation == "application/did+json" do
            Map.get(result.did_resolution_metadata, "contentType", options.representation)
          else
            options.representation
          end

        with {:ok, content_type} <- Representation.negotiate(document, requested_content_type) do
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
        RepresentationResult.error(%Error{
          code: error_code(result.did_resolution_metadata["error"]),
          message: result.did_resolution_metadata["message"],
          details: Map.get(result.did_resolution_metadata, "details", %{})
        })
    end
  end

  @doc """
  Dereferences a `did:web` DID URL.
  """
  @impl true
  @spec dereference(DIDURL.t(), ResolveOptions.t()) :: DereferencingResult.t()
  def dereference(%DIDURL{} = did_url, %ResolveOptions{} = options) do
    result = resolve(%{did_url | params: [], path: nil, query: nil, fragment: nil}, options)

    with %{} = document <- result.did_document,
         {:ok, content_stream} <- Document.dereference(document, did_url) do
      DereferencingResult.ok(
        decorate_resource(content_stream, document),
        %{did_document: did_url.did.value},
        %{
          "contentType" => dereferenced_content_type(decorate_resource(content_stream, document))
        }
      )
    else
      {:error, %Error{} = error} ->
        DereferencingResult.error(error)

      nil ->
        DereferencingResult.error(
          Error.not_found(
            did_url.did.value,
            Map.get(result.did_resolution_metadata, "message", "DID URL not found")
          )
        )
    end
  end

  @doc """
  Maps a `did:web` DID to its document URL.
  """
  @impl true
  @spec resolve_url(DIDURL.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def resolve_url(%DIDURL{method_specific_id: method_specific_id})
      when byte_size(method_specific_id) > 0 do
    with {:ok, [host | path_segments]} <- decode_parts(method_specific_id),
         :ok <- validate_host(host),
         :ok <- validate_path_segments(path_segments) do
      {:ok, build_url(host, path_segments)}
    else
      {:error, %Error{} = error} -> {:error, error}
      _ -> {:error, Error.invalid_did("did:web:" <> method_specific_id)}
    end
  end

  def resolve_url(%DIDURL{did: did}), do: {:error, Error.invalid_did(did.value)}

  defp fetch_json(
         url,
         %ResolveOptions{
           transport: {ExDid.Fetcher.Function, _} = transport,
           transport_options: opts
         }
       ),
       do: Fetcher.Function.fetch_json(url, transport) |> normalize_fetch_result(url, opts)

  defp fetch_json(url, %ResolveOptions{transport: transport, transport_options: opts}),
    do: transport.fetch_json(url, opts) |> normalize_fetch_result(url, opts)

  defp normalize_fetch_result({:ok, document, metadata}, _url, _opts),
    do: {:ok, document, metadata}

  defp normalize_fetch_result({:error, reason, metadata}, url, _opts),
    do:
      {:error,
       Error.transport(
         url,
         "DID must resolve to a valid HTTPS JSON document: #{reason}",
         metadata
       )}

  defp normalize_document(document, :compat) do
    case Map.get(document, "service") do
      %{} = service -> Map.put(document, "service", [service])
      _ -> document
    end
  end

  defp normalize_document(document, :strict), do: document

  defp content_type(%{"@context" => _}, nil), do: "application/did+ld+json"
  defp content_type(_document, nil), do: "application/did+json"
  defp content_type(_document, header), do: header

  defp validate_response_content_type(metadata, validation, did) do
    media_type =
      metadata
      |> Map.get("content-type", Map.get(metadata, :content_type))
      |> normalized_media_type()

    valid? =
      case {validation, media_type} do
        {_, nil} -> true
        {:strict, "application/did+json"} -> true
        {:strict, "application/did+ld+json"} -> true
        {:compat, "application/json"} -> true
        {:compat, "application/did+json"} -> true
        {:compat, "application/did+ld+json"} -> true
        _ -> false
      end

    if valid? do
      :ok
    else
      {:error,
       Error.invalid_did_document(did, %{
         reason: :unexpected_content_type,
         content_type: media_type
       })}
    end
  end

  defp decode_parts(method_specific_id) do
    parts =
      method_specific_id
      |> String.split(":")
      |> Enum.map(&URI.decode/1)

    case parts do
      [] -> {:error, Error.invalid_did("did:web:" <> method_specific_id)}
      ["" | _] -> {:error, Error.invalid_did("did:web:" <> method_specific_id)}
      [_ | _] = decoded -> {:ok, decoded}
    end
  rescue
    ArgumentError -> {:error, Error.invalid_did("did:web:" <> method_specific_id)}
  end

  defp validate_host(host) do
    uri = URI.parse("https://" <> host)

    cond do
      is_nil(uri.host) or uri.host == "" -> {:error, Error.invalid_did("did:web:" <> host)}
      uri.path not in [nil, ""] -> {:error, Error.invalid_did("did:web:" <> host)}
      uri.query -> {:error, Error.invalid_did("did:web:" <> host)}
      uri.fragment -> {:error, Error.invalid_did("did:web:" <> host)}
      uri.userinfo -> {:error, Error.invalid_did("did:web:" <> host)}
      true -> :ok
    end
  end

  defp validate_path_segments(path_segments) do
    if Enum.all?(path_segments, &(is_binary(&1) and &1 != "")) do
      :ok
    else
      {:error, Error.invalid_did("did:web:path")}
    end
  end

  defp build_url(host, []), do: "https://#{host}#{@well_known_path}"

  defp build_url(host, path_segments),
    do: "https://#{host}/#{Enum.join(path_segments, "/")}/did.json"

  defp stringify_keys(metadata) when is_map(metadata),
    do: Map.new(metadata, fn {key, value} -> {to_string(key), value} end)

  defp normalized_media_type(nil), do: nil

  defp normalized_media_type(header) when is_binary(header) do
    header
    |> String.split(";", parts: 2)
    |> List.first()
    |> String.trim()
    |> String.downcase()
  end

  defp dereferenced_content_type(%{"@context" => _}), do: "application/did+ld+json"
  defp dereferenced_content_type(%{}), do: "application/did+json"
  defp dereferenced_content_type(_), do: "text/plain"

  defp decorate_resource(resource, document) when resource == document, do: resource

  defp decorate_resource(%{} = resource, %{"@context" => context}),
    do: Map.put_new(resource, "@context", context)

  defp decorate_resource(resource, _document), do: resource

  defp error_code("invalidDid"), do: :invalid_did
  defp error_code("invalidDidDocument"), do: :invalid_did_document
  defp error_code("invalidDidUrl"), do: :invalid_did_url
  defp error_code("methodNotSupported"), do: :method_not_supported
  defp error_code("notFound"), do: :not_found
  defp error_code("representationNotSupported"), do: :representation_not_supported
  defp error_code(_), do: :unsupported_operation
end
