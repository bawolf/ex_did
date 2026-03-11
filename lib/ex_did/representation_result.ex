defmodule ExDid.RepresentationResult do
  @moduledoc """
  DID representation resolution result.
  """

  alias ExDid.Error
  alias ExDid.Metadata

  @enforce_keys [:content_stream, :content_type, :did_document_metadata, :did_resolution_metadata]
  defstruct content_stream: nil,
            content_type: nil,
            did_document_metadata: %{},
            did_resolution_metadata: %{}

  @typedoc "Structured representation result."
  @type t :: %__MODULE__{
          content_stream: binary() | nil,
          content_type: String.t() | nil,
          did_document_metadata: map(),
          did_resolution_metadata: map()
        }

  @doc """
  Builds a successful representation result.
  """
  @spec ok(binary(), String.t(), map(), map()) :: t()
  def ok(
        content_stream,
        content_type,
        did_document_metadata \\ %{},
        did_resolution_metadata \\ %{}
      ) do
    %__MODULE__{
      content_stream: content_stream,
      content_type: content_type,
      did_document_metadata: did_document_metadata,
      did_resolution_metadata: did_resolution_metadata
    }
  end

  @doc """
  Builds an error representation result.
  """
  @spec error(Error.t()) :: t()
  def error(%Error{} = error) do
    %__MODULE__{
      content_stream: nil,
      content_type: nil,
      did_document_metadata: %{},
      did_resolution_metadata: Metadata.error(error)
    }
  end
end
