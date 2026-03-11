defmodule ExDid.Error do
  @moduledoc """
  Typed DID error details.
  """

  @enforce_keys [:code, :message]
  defstruct code: nil, message: nil, details: %{}, did: nil, did_url: nil

  @typedoc "Resolver error code."
  @type code ::
          :invalid_did
          | :invalid_did_url
          | :invalid_did_document
          | :method_not_supported
          | :not_found
          | :representation_not_supported
          | :unsupported_operation

  @typedoc "Typed DID error."
  @type t :: %__MODULE__{
          code: code(),
          message: String.t(),
          details: map(),
          did: String.t() | nil,
          did_url: String.t() | nil
        }

  @doc """
  Builds an invalid DID error.
  """
  @spec invalid_did(String.t(), map()) :: t()
  def invalid_did(value, details \\ %{}),
    do: %__MODULE__{
      code: :invalid_did,
      message: "Invalid DID identifier",
      did: value,
      details: details
    }

  @doc """
  Builds an invalid DID URL error.
  """
  @spec invalid_did_url(String.t(), map()) :: t()
  def invalid_did_url(value, details \\ %{}),
    do: %__MODULE__{
      code: :invalid_did_url,
      message: "Invalid DID URL",
      did_url: value,
      details: details
    }

  @doc """
  Builds an invalid DID document error.
  """
  @spec invalid_did_document(String.t(), map()) :: t()
  def invalid_did_document(did, details \\ %{}),
    do: %__MODULE__{
      code: :invalid_did_document,
      message: "Invalid DID document",
      did: did,
      details: details
    }

  @doc """
  Builds a method-not-supported error.
  """
  @spec method_not_supported(String.t()) :: t()
  def method_not_supported(method),
    do: %__MODULE__{
      code: :method_not_supported,
      message: "DID method is not supported",
      details: %{method: method}
    }

  @doc """
  Builds a not-found error.
  """
  @spec not_found(String.t() | nil, String.t(), map()) :: t()
  def not_found(subject, message, details \\ %{}),
    do: %__MODULE__{code: :not_found, message: message, did_url: subject, details: details}

  @doc """
  Builds an unsupported operation error.
  """
  @spec unsupported_operation(String.t(), map()) :: t()
  def unsupported_operation(message, details \\ %{}),
    do: %__MODULE__{code: :unsupported_operation, message: message, details: details}

  @doc """
  Builds a representation-not-supported error.
  """
  @spec representation_not_supported(String.t()) :: t()
  def representation_not_supported(value),
    do: %__MODULE__{
      code: :representation_not_supported,
      message: "Requested representation is not supported",
      did: value
    }

  @doc """
  Builds a transport-backed error.
  """
  @spec transport(String.t(), String.t(), map()) :: t()
  def transport(did, message, details \\ %{}),
    do: %__MODULE__{code: :not_found, message: message, did: did, details: details}
end
