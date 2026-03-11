defmodule ExDid.ResolutionResult do
  @moduledoc """
  DID resolution result.
  """

  alias ExDid.Error
  alias ExDid.Metadata

  @enforce_keys [:did_document, :did_document_metadata, :did_resolution_metadata]
  defstruct did_document: nil, did_document_metadata: %{}, did_resolution_metadata: %{}

  @typedoc "Structured resolution result."
  @type t :: %__MODULE__{
          did_document: map() | nil,
          did_document_metadata: map(),
          did_resolution_metadata: map()
        }

  @doc """
  Builds a successful resolution result.
  """
  @spec ok(map(), map(), map()) :: t()
  def ok(document, document_metadata \\ %{}, resolution_metadata \\ %{}) do
    %__MODULE__{
      did_document: document,
      did_document_metadata: document_metadata,
      did_resolution_metadata: resolution_metadata
    }
  end

  @doc """
  Builds an error resolution result.
  """
  @spec error(Error.t()) :: t()
  def error(%Error{} = error) do
    %__MODULE__{
      did_document: nil,
      did_document_metadata: %{},
      did_resolution_metadata: Metadata.error(error)
    }
  end
end
