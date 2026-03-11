defmodule ExDid do
  @moduledoc """
  DID resolution facade.

  `ex_did` exposes a method-agnostic DID parsing, resolution, representation,
  and dereferencing API with strict validation by default.

  The normal runtime and test path is pure Elixir. Upstream JavaScript and Rust
  resolver tooling is only used by maintainers when refreshing committed parity
  fixtures.

  `ex_did` is intentionally scoped to DID concerns only. VC, VP, JWT, JWS,
  Data Integrity, and proof workflows belong in sibling libraries.

  ## Examples

      iex> ExDid.method("did:web:example.com")
      "web"

      iex> {:ok, did} = ExDid.did_web("example.com", ["users", "alice"])
      iex> did
      "did:web:example.com:users:alice"

      iex> {:ok, verification_method} =
      ...>   ExDid.verification_method_id("did:jwk:eyJrdHkiOiJPS1AiLCJjcnYiOiJFZDI1NTE5IiwieCI6IlZDcG8yTE1MaG42aVdrdThNS3ZTTGcyWkFvQy1ubE95UFZRYU8zRnhWZVEifQ")
      iex> verification_method
      "did:jwk:eyJrdHkiOiJPS1AiLCJjcnYiOiJFZDI1NTE5IiwieCI6IlZDcG8yTE1MaG42aVdrdThNS3ZTTGcyWkFvQy1ubE95UFZRYU8zRnhWZVEifQ#0"
  """

  alias ExDid.DIDURL
  alias ExDid.DereferencingResult
  alias ExDid.Error
  alias ExDid.MethodRegistry
  alias ExDid.RepresentationResult
  alias ExDid.ResolveOptions
  alias ExDid.ResolutionResult

  @typedoc "Normalized DID document map."
  @type did_document :: map()

  @typedoc "Parsed DID or DID URL."
  @type parsed_did :: DIDURL.t()

  @typedoc "Resolution result."
  @type resolution_result :: ResolutionResult.t()

  @typedoc "Representation result."
  @type representation_result :: RepresentationResult.t()

  @typedoc "Dereferencing result."
  @type dereferencing_result :: DereferencingResult.t()

  @typedoc "Validation mode."
  @type validation_mode :: :strict | :compat

  @doc """
  Returns the DID method for a valid DID or DID URL.
  """
  @spec method(String.t()) :: String.t() | nil
  def method(value) when is_binary(value) do
    case parse(value) do
      {:ok, %DIDURL{method: method}} -> method
      {:error, _reason} -> nil
    end
  end

  def method(_), do: nil

  @doc """
  Builds a canonical `did:web` identifier from a host and optional path segments.

  This is intended for application code that needs a stable `did:web`
  constructor without reimplementing percent-encoding rules.
  """
  @spec did_web(String.t(), [String.t()]) :: {:ok, String.t()} | {:error, Error.t()}
  def did_web(host, path_segments \\ [])

  def did_web(host, path_segments) when is_binary(host) and is_list(path_segments),
    do: ExDid.Method.Web.did(host, path_segments)

  def did_web(host, _path_segments), do: {:error, Error.invalid_did(inspect(host))}

  @doc """
  Parses a DID or DID URL into a typed struct.
  """
  @spec parse(String.t(), keyword()) :: {:ok, parsed_did()} | {:error, Error.t()}
  def parse(value, opts \\ [])

  def parse(value, opts) when is_binary(value) do
    with {:ok, options} <- ResolveOptions.new(opts),
         {:ok, did_url} <- DIDURL.parse(value) do
      DIDURL.normalize(did_url, options.validation)
    end
  end

  def parse(value, _opts), do: {:error, Error.invalid_did(inspect(value))}

  @doc """
  Resolves a DID to a DID document.
  """
  @spec resolve(String.t(), keyword()) :: resolution_result()
  def resolve(value, opts \\ [])

  def resolve(value, opts) when is_binary(value) do
    with {:ok, options} <- ResolveOptions.new(opts),
         {:ok, did_url} <- DIDURL.parse(value),
         :ok <- DIDURL.ensure_bare(did_url),
         {:ok, method_module} <- MethodRegistry.fetch(options.method_registry, did_url.method) do
      method_module.resolve(did_url, options)
    else
      {:error, %Error{} = error} ->
        ResolutionResult.error(error)
    end
  end

  def resolve(value, _opts), do: ResolutionResult.error(Error.invalid_did(inspect(value)))

  @doc """
  Resolves a DID to a concrete representation.
  """
  @spec resolve_representation(String.t(), keyword()) :: representation_result()
  def resolve_representation(value, opts \\ [])

  def resolve_representation(value, opts) when is_binary(value) do
    with {:ok, options} <- ResolveOptions.new(opts),
         {:ok, did_url} <- DIDURL.parse(value),
         :ok <- DIDURL.ensure_bare(did_url),
         {:ok, method_module} <- MethodRegistry.fetch(options.method_registry, did_url.method) do
      method_module.resolve_representation(did_url, options)
    else
      {:error, %Error{} = error} ->
        RepresentationResult.error(error)
    end
  end

  def resolve_representation(value, _opts),
    do: RepresentationResult.error(Error.invalid_did(inspect(value)))

  @doc """
  Dereferences a DID URL.
  """
  @spec dereference(String.t(), keyword()) :: dereferencing_result()
  def dereference(value, opts \\ [])

  def dereference(value, opts) when is_binary(value) do
    with {:ok, options} <- ResolveOptions.new(opts),
         {:ok, did_url} <- DIDURL.parse(value),
         {:ok, method_module} <- MethodRegistry.fetch(options.method_registry, did_url.method) do
      method_module.dereference(did_url, options)
    else
      {:error, %Error{} = error} ->
        DereferencingResult.error(error)
    end
  end

  def dereference(value, _opts),
    do: DereferencingResult.error(Error.invalid_did(inspect(value)))

  @doc """
  Maps a `did:web` DID to its document URL.
  """
  @spec resolve_url(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def resolve_url(value) when is_binary(value) do
    with {:ok, did_url} <- DIDURL.parse(value),
         :ok <- DIDURL.ensure_bare(did_url),
         {:ok, method_module} <- MethodRegistry.fetch(MethodRegistry.default(), did_url.method) do
      method_module.resolve_url(did_url)
    end
  end

  def resolve_url(value), do: {:error, Error.invalid_did(inspect(value))}

  @doc """
  Returns the canonical verification method identifier for methods that define one.

  This is primarily useful for locally resolvable methods such as `did:key` and
  `did:jwk`, where callers often need a stable verification method id but should
  not guess the fragment format themselves.
  """
  @spec verification_method_id(String.t()) :: {:ok, String.t()} | {:error, Error.t()}
  def verification_method_id(value) when is_binary(value) do
    with {:ok, did_url} <- DIDURL.parse(value),
         :ok <- DIDURL.ensure_bare(did_url) do
      case did_url.method do
        "key" ->
          ExDid.Method.Key.verification_method_id(did_url)

        "jwk" ->
          ExDid.Method.Jwk.verification_method_id(did_url)

        _ ->
          {:error,
           Error.unsupported_operation(
             "DID method does not define a canonical verification method id",
             %{did: value}
           )}
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  def verification_method_id(value), do: {:error, Error.invalid_did(inspect(value))}

  @doc """
  Returns verification methods including legacy `publicKey` entries.
  """
  @spec verification_methods(map()) :: [map()]
  def verification_methods(document) when is_map(document),
    do: ExDid.Document.verification_methods(document)
end
