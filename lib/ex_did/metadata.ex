defmodule ExDid.Metadata do
  @moduledoc false

  alias ExDid.Error

  @spec error(Error.t()) :: map()
  def error(%Error{} = error) do
    %{
      "error" => error_code(error.code),
      "message" => error.message,
      "details" => error.details
    }
  end

  @spec error_code(Error.code()) :: String.t()
  def error_code(:invalid_did), do: "invalidDid"
  def error_code(:invalid_did_document), do: "invalidDidDocument"
  def error_code(:invalid_did_url), do: "invalidDidUrl"
  def error_code(:method_not_supported), do: "methodNotSupported"
  def error_code(:not_found), do: "notFound"
  def error_code(:representation_not_supported), do: "representationNotSupported"
  def error_code(:unsupported_operation), do: "unsupportedOperation"
end
