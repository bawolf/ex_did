defmodule ExDid.Representation do
  @moduledoc false

  alias ExDid.Error

  @json "application/did+json"
  @json_ld "application/did+ld+json"

  @spec negotiate(map(), String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def negotiate(document, requested_content_type)
      when is_map(document) and is_binary(requested_content_type) do
    case requested_content_type do
      @json ->
        {:ok, @json}

      @json_ld ->
        if Map.has_key?(document, "@context") do
          {:ok, @json_ld}
        else
          {:error, Error.representation_not_supported(requested_content_type)}
        end

      "application/json" ->
        {:ok, @json}

      other ->
        {:error, Error.representation_not_supported(other)}
    end
  end
end
