defmodule ExDid.Method do
  @moduledoc """
  DID method behavior.
  """

  alias ExDid.DIDURL
  alias ExDid.Error
  alias ExDid.ResolveOptions

  @callback resolve(DIDURL.t(), ResolveOptions.t()) :: ExDid.ResolutionResult.t()
  @callback resolve_representation(DIDURL.t(), ResolveOptions.t()) ::
              ExDid.RepresentationResult.t()
  @callback dereference(DIDURL.t(), ResolveOptions.t()) :: ExDid.DereferencingResult.t()
  @callback resolve_url(DIDURL.t()) :: {:ok, String.t()} | {:error, Error.t()}
end
