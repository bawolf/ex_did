defmodule ExDid.DereferencingResult do
  @moduledoc """
  DID URL dereferencing result.
  """

  alias ExDid.Error
  alias ExDid.Metadata

  @enforce_keys [:content_stream, :content_metadata, :dereferencing_metadata]
  defstruct content_stream: nil, content_metadata: %{}, dereferencing_metadata: %{}

  @typedoc "Structured dereferencing result."
  @type t :: %__MODULE__{
          content_stream: map() | binary() | nil,
          content_metadata: map(),
          dereferencing_metadata: map()
        }

  @doc """
  Builds a successful dereferencing result.
  """
  @spec ok(map() | binary(), map(), map()) :: t()
  def ok(content_stream, content_metadata \\ %{}, dereferencing_metadata \\ %{}) do
    %__MODULE__{
      content_stream: content_stream,
      content_metadata: content_metadata,
      dereferencing_metadata: dereferencing_metadata
    }
  end

  @doc """
  Builds an error dereferencing result.
  """
  @spec error(Error.t()) :: t()
  def error(%Error{} = error) do
    %__MODULE__{
      content_stream: nil,
      content_metadata: %{},
      dereferencing_metadata: Metadata.error(error)
    }
  end
end
