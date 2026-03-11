defmodule ExDid.Fetcher do
  @moduledoc false

  @callback fetch_json(String.t(), keyword()) :: {:ok, map(), map()} | {:error, String.t(), map()}

  @accept "application/did+ld+json, application/did+json, application/json"

  @spec fetch_json(String.t(), keyword()) :: {:ok, map(), map()} | {:error, String.t(), map()}
  def fetch_json(url, opts \\ []) do
    accept = Keyword.get(opts, :accept, @accept)

    req =
      Req.new(
        url: url,
        headers: [{"accept", accept}],
        max_redirects: Keyword.get(opts, :max_redirects, 2),
        receive_timeout: Keyword.get(opts, :receive_timeout, 5_000)
      )

    case Req.get(req) do
      {:ok, %Req.Response{status: status, body: body, headers: headers}}
      when status in 200..299 and is_map(body) ->
        {:ok, body,
         %{
           status: status,
           content_type: header_value(headers, "content-type"),
           etag: header_value(headers, "etag"),
           last_modified: header_value(headers, "last-modified")
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error, "HTTP #{status}", %{status: status}}

      {:error, reason} ->
        {:error, Exception.message(reason), %{}}
    end
  rescue
    error -> {:error, Exception.message(error), %{}}
  end

  defmodule Function do
    @moduledoc false

    @spec fetch_json(String.t(), {module(), function()}) ::
            {:ok, map(), map()} | {:error, String.t(), map()}
    def fetch_json(url, {__MODULE__, fun}) do
      case fun.(url) do
        {:ok, document} -> {:ok, document, %{}}
        {:ok, document, metadata} -> {:ok, document, metadata}
        {:error, reason} -> {:error, to_string(reason), %{}}
        {:error, reason, metadata} -> {:error, to_string(reason), metadata}
      end
    end
  end

  defp header_value(headers, key) do
    headers
    |> Enum.find_value(fn {header, value} -> if String.downcase(header) == key, do: value end)
  end
end
