defmodule ExDid.MethodRegistry do
  @moduledoc """
  DID method registry.
  """

  alias ExDid.Error

  @methods %{
    "web" => ExDid.Method.Web,
    "key" => ExDid.Method.Key,
    "jwk" => ExDid.Method.Jwk
  }

  @doc """
  Returns the default method registry.
  """
  @spec default() :: %{optional(String.t()) => module()}
  def default, do: @methods

  @doc """
  Validates a method registry shape.
  """
  @spec validate(map()) :: :ok | {:error, Error.t()}
  def validate(method_registry) when is_map(method_registry) do
    if Enum.all?(method_registry, fn
         {method, module} when is_binary(method) and is_atom(module) -> true
         _ -> false
       end) do
      :ok
    else
      {:error,
       Error.invalid_did("options", %{
         reason: "method_registry must use string keys and module values"
       })}
    end
  end

  def validate(_),
    do: {:error, Error.invalid_did("options", %{reason: "method_registry must be a map"})}

  @doc """
  Fetches a method module by DID method name.
  """
  @spec fetch(map(), String.t()) :: {:ok, module()} | {:error, Error.t()}
  def fetch(method_registry, method) when is_map(method_registry) and is_binary(method) do
    case Map.fetch(method_registry, method) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, Error.method_not_supported(method)}
    end
  end
end
