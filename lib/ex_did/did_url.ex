defmodule ExDid.DIDURL do
  @moduledoc """
  Parsed DID URL components.
  """

  alias ExDid.DID
  alias ExDid.Error

  @enforce_keys [:did, :method, :method_specific_id]
  defstruct did: nil,
            method: nil,
            method_specific_id: nil,
            params: [],
            path: nil,
            query: nil,
            fragment: nil

  @typedoc "A DID URL parameter."
  @type param :: %{name: String.t(), value: String.t() | nil}

  @typedoc "Typed DID URL."
  @type t :: %__MODULE__{
          did: DID.t(),
          method: String.t(),
          method_specific_id: String.t(),
          params: [param()],
          path: String.t() | nil,
          query: String.t() | nil,
          fragment: String.t() | nil
        }

  @method_specific_id_regex ~r/\A(?:(?:[A-Za-z0-9._-]|%[0-9A-Fa-f]{2})+:)*(?:[A-Za-z0-9._-]|%[0-9A-Fa-f]{2})+\z/
  @param_regex ~r/\A([A-Za-z0-9._:%-]+)(?:=([A-Za-z0-9._:%-]*))?\z/

  @doc """
  Parses a DID or DID URL.
  """
  @spec parse(String.t()) :: {:ok, t()} | {:error, Error.t()}
  def parse("did:" <> rest = value) when is_binary(rest) do
    with {:ok, remainder, fragment} <- split_once(rest, "#"),
         {:ok, remainder, query} <- split_once(remainder, "?"),
         {:ok, method, method_remainder} <- split_method(remainder, value),
         {:ok, before_path, path} <- split_path(method_remainder, value),
         {:ok, method_specific_id, parsed_params} <- split_params(before_path, value),
         true <- Regex.match?(@method_specific_id_regex, method_specific_id) do
      did = %DID{
        value: build_did(method, method_specific_id),
        method: method,
        method_specific_id: method_specific_id
      }

      {:ok,
       %__MODULE__{
         did: did,
         method: method,
         method_specific_id: method_specific_id,
         params: parsed_params,
         path: path,
         query: query,
         fragment: fragment
       }}
    else
      false ->
        {:error, Error.invalid_did(value)}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def parse(value), do: {:error, Error.invalid_did(inspect(value))}

  @doc """
  Applies validation-mode normalization.
  """
  @spec normalize(t(), ExDid.validation_mode()) :: {:ok, t()} | {:error, Error.t()}
  def normalize(%__MODULE__{} = did_url, :strict), do: {:ok, did_url}

  def normalize(%__MODULE__{} = did_url, :compat) do
    normalized =
      update_in(did_url.params, fn params ->
        Enum.uniq_by(params, & &1.name)
      end)

    {:ok, normalized}
  end

  @doc """
  Ensures the DID URL is a bare DID.
  """
  @spec ensure_bare(t()) :: :ok | {:error, Error.t()}
  def ensure_bare(%__MODULE__{params: [], path: nil, query: nil, fragment: nil}), do: :ok

  def ensure_bare(%__MODULE__{did: %DID{value: value}}),
    do: {:error, Error.invalid_did(value, %{reason: :did_url_components_not_allowed})}

  @doc """
  Returns the bare DID string.
  """
  @spec did_string(t()) :: String.t()
  def did_string(%__MODULE__{did: %DID{value: value}}), do: value

  @doc """
  Returns a canonical fragment reference for the DID URL.
  """
  @spec fragment_reference(t()) :: String.t() | nil
  def fragment_reference(%__MODULE__{fragment: nil}), do: nil

  def fragment_reference(%__MODULE__{did: %DID{value: did}, fragment: fragment}),
    do: did <> "#" <> fragment

  defp split_once(value, marker) do
    case String.split(value, marker, parts: 2) do
      [left, right] -> {:ok, left, blank_to_nil(right)}
      [left] -> {:ok, left, nil}
    end
  end

  defp split_method(value, original) do
    case String.split(value, ":", parts: 2) do
      [method, remainder] when remainder != "" ->
        if String.match?(method, ~r/\A[a-z0-9]+\z/) do
          {:ok, method, remainder}
        else
          {:error, Error.invalid_did(original)}
        end

      _ ->
        {:error, Error.invalid_did(original)}
    end
  end

  defp split_path(value, original) do
    case String.split(value, "/", parts: 2) do
      [before_path, path] when path != "" -> {:ok, before_path, "/" <> path}
      [before_path] -> {:ok, before_path, nil}
      _ -> {:error, Error.invalid_did_url(original)}
    end
  end

  defp split_params(value, original) do
    case String.split(value, ";", trim: false) do
      [method_specific_id | params] when method_specific_id != "" ->
        with {:ok, parsed_params} <- parse_params(params, original) do
          {:ok, method_specific_id, parsed_params}
        end

      _ ->
        {:error, Error.invalid_did(original)}
    end
  end

  defp parse_params([], _original), do: {:ok, []}

  defp parse_params(params, original) do
    params
    |> Enum.reduce_while({:ok, []}, fn segment, {:ok, acc} ->
      case Regex.run(@param_regex, segment, capture: :all_but_first) do
        [name, value] ->
          {:cont, {:ok, acc ++ [%{name: name, value: blank_to_nil(value)}]}}

        [name] ->
          {:cont, {:ok, acc ++ [%{name: name, value: nil}]}}

        _ ->
          {:halt, {:error, Error.invalid_did_url(original)}}
      end
    end)
  end

  defp build_did(method, method_specific_id), do: "did:#{method}:#{method_specific_id}"

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value
end
