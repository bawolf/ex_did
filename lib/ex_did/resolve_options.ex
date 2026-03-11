defmodule ExDid.ResolveOptions do
  @moduledoc """
  Validated public options for DID operations.
  """

  alias ExDid.Error

  @enforce_keys [:validation, :transport, :method_registry]
  defstruct validation: :strict,
            transport: ExDid.Fetcher,
            transport_options: [],
            representation: "application/did+json",
            method_registry: ExDid.MethodRegistry.default()

  @typedoc "Validated operation options."
  @type t :: %__MODULE__{
          validation: ExDid.validation_mode(),
          transport: module() | tuple(),
          transport_options: keyword(),
          representation: String.t(),
          method_registry: %{optional(String.t()) => module()}
        }

  @schema [
    validation: [type: {:in, [:strict, :compat]}, default: :strict],
    transport: [type: :atom, default: ExDid.Fetcher],
    transport_options: [type: :keyword_list, default: []],
    representation: [type: :string, default: "application/did+json"],
    accept: [type: :string, required: false],
    method_registry: [type: :any, default: ExDid.MethodRegistry.default()],
    fetch_json: [type: :any, required: false]
  ]

  @doc """
  Validates public options.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.t()}
  def new(opts) when is_list(opts) do
    case NimbleOptions.validate(opts, @schema) do
      {:ok, validated} ->
        validated =
          case Keyword.get(opts, :fetch_json) do
            nil ->
              validated

            fetch_fun when is_function(fetch_fun, 1) ->
              Keyword.put(validated, :transport, {ExDid.Fetcher.Function, fetch_fun})

            _ ->
              validated
          end

        representation =
          Keyword.get(validated, :accept, Keyword.fetch!(validated, :representation))

        with :ok <- ExDid.MethodRegistry.validate(Keyword.fetch!(validated, :method_registry)) do
          {:ok,
           %__MODULE__{
             validation: Keyword.fetch!(validated, :validation),
             transport: Keyword.fetch!(validated, :transport),
             transport_options: Keyword.fetch!(validated, :transport_options),
             representation: representation,
             method_registry: Keyword.fetch!(validated, :method_registry)
           }}
        end

      {:error, exception} ->
        {:error, Error.invalid_did("options", %{reason: Exception.message(exception)})}
    end
  end
end
