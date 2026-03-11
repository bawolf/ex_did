# ex_did

[![Hex.pm](https://img.shields.io/hexpm/v/ex_did.svg)](https://hex.pm/packages/ex_did)
[![Hex Docs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/ex_did)
[![CI](https://github.com/bawolf/ex_did/actions/workflows/ci.yml/badge.svg)](https://github.com/bawolf/ex_did/actions/workflows/ci.yml)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/bawolf/ex_did/blob/main/LICENSE)

`ex_did` is a typed DID resolution library for Elixir.

Quick links: [Hex package](https://hex.pm/packages/ex_did) | [Hex docs](https://hexdocs.pm/ex_did) | [Changelog](https://github.com/bawolf/ex_did/blob/main/CHANGELOG.md) | [Fixture policy](https://github.com/bawolf/ex_did/blob/main/FIXTURE_POLICY.md) | [CI](https://github.com/bawolf/ex_did/actions/workflows/ci.yml)

The library exposes a method-agnostic API for DID parsing, DID resolution, DID
representation resolution, DID URL dereferencing, and a small number of
method-specific helper functions that remove common string-building mistakes.

## Status

Current support:

- typed DID / DID URL parsing
- typed result structs for resolve, representation, and dereference operations
- method registry with first-class `did:web`, `did:key`, and `did:jwk`
- strict validation by default with opt-in `validation: :compat`
- deterministic local resolution for `did:key` and `did:jwk`
- `did:web` URL mapping, fetching, validation, and dereferencing
- verification method extraction across current and legacy shapes

Not implemented yet:

- additional DID methods
- fully refreshed upstream JS parity corpus from the maintainer recorder
- more advanced HTTP caching policy for `did:web`
- broader DID document normalization rules beyond the current strict/compat set

## Installation

Add `ex_did` to your dependencies:

```elixir
def deps do
  [
    {:ex_did, "~> 0.1.0"},
    {:jose, "~> 1.11"}
  ]
end
```

## Usage

Normal `ex_did` usage does not require JavaScript, `pnpm`, or network access.
Those are maintainer-only dependencies for rebuilding upstream parity fixtures.

Parse a DID or DID URL:

```elixir
{:ok, did_url} = ExDid.parse("did:web:example.com#key-1")
did_url.method
# => "web"
```

Resolve a DID:

```elixir
result = ExDid.resolve("did:key:z6MkeXCES4onVW4up9Qgz1KRnZsKmGufcaZxF6Zpv2w5QwUK")

document = result.did_document
verification_method = hd(document["verificationMethod"])
```

Resolve a representation:

```elixir
result = ExDid.resolve_representation("did:web:example.com", fetch_json: fn _url ->
  {:ok, %{"@context" => ["https://www.w3.org/ns/did/v1"], "id" => "did:web:example.com"}}
end)

Jason.decode!(result.content_stream)
```

Derefence a DID URL:

```elixir
result = ExDid.dereference("did:web:example.com#key-1", fetch_json: fn _url ->
  {:ok,
   %{
     "id" => "did:web:example.com",
     "verificationMethod" => [
       %{"id" => "did:web:example.com#key-1", "controller" => "did:web:example.com"}
     ]
   }}
end)

result.content_stream["id"]
```

Use compatibility mode only when needed for known ecosystem quirks:

```elixir
result =
  ExDid.resolve("did:jwk:...", validation: :compat)
```

Override the registry or representation per call:

```elixir
registry = %{"web" => ExDid.Method.Web}

result =
  ExDid.resolve_representation("did:web:example.com",
    method_registry: registry,
    accept: "application/did+ld+json",
    fetch_json: fn _url ->
      {:ok, %{"@context" => ["https://www.w3.org/ns/did/v1"], "id" => "did:web:example.com"}}
    end
  )
```

Map a `did:web` DID to its document URL:

```elixir
{:ok, url} = ExDid.resolve_url("did:web:example.com:user:alice")
# => "https://example.com/user/alice/did.json"
```

Build a canonical `did:web` value or canonical local verification method id:

```elixir
{:ok, did} = ExDid.did_web("greenfield.gov")
{:ok, verification_method} =
  ExDid.verification_method_id("did:key:z6MkeXCES4onVW4up9Qgz1KRnZsKmGufcaZxF6Zpv2w5QwUK")
```

## Supported Method Matrix

`did:web`
- HTTPS document resolution
- DID document dereferencing for fragments and explicit `service` parameter path/query handling

`did:key`
- supported multicodec prefixes: Ed25519, X25519, secp256k1, P-256, P-384, P-521
- currently fixture-covered examples: Ed25519, X25519

`did:jwk`
- supported public key shapes: OKP, EC, RSA
- currently fixture-covered examples: OKP, RSA

## Validation Modes

`ex_did` defaults to `validation: :strict`.

`validation: :compat` is opt-in and intentionally narrow. It currently only
relaxes behaviors that are explicitly implemented and covered by fixtures and
tests, such as normalizing a single `service` object into a list and stripping
private material from `did:jwk` inputs before building the public DID document.

Strict mode is the production default. Compat mode is an interoperability tool,
not a second equal runtime profile.

## `did:web` Transport Rules

`did:web` resolution accepts the following response media types:

- strict: `application/did+json`, `application/did+ld+json`
- compat: strict types plus `application/json`

If the response media type falls outside those rules, resolution returns
`invalidDidDocument`.

## did:web Rules

`ex_did` follows the standard `did:web` mapping:

- `did:web:example.com` -> `https://example.com/.well-known/did.json`
- `did:web:example.com:user:alice` -> `https://example.com/user/alice/did.json`
- `did:web:localhost%3A8443` -> `https://localhost:8443/.well-known/did.json`

URI-encoded DID path components are decoded before building the HTTPS URL.

## Testing And Parity

The library is tested with:

- vendored fixture documents under `test/fixtures/`
- upstream parity corpora under `test/fixtures/upstream/`
- fixture provenance manifests for both local deterministic fixtures and
  upstream-recorded fixtures
- property tests for DID parsing and deterministic local DID generation
- strict / compat coverage for `did:web` and `did:jwk`
- dereferencing coverage for `did:web`, `did:key`, and `did:jwk`
- injected fetch functions so `did:web` resolution remains deterministic
- downstream validation against current `apps/delegate` DID usage

Refresh local deterministic fixtures with:

```bash
mix run scripts/refresh_fixtures.exs
```

Refresh upstream parity fixtures with the maintainer-only recorder:

```bash
cd libs/ex_did/scripts/upstream_parity
pnpm install
pnpm run record:released
pnpm run record:main
```

The committed fixtures are the contract. End users and CI should not need to
run the recorder.

## Fixture Policy

The fixture policy is documented in `FIXTURE_POLICY.md`.

- `upstream/released` is contractual and should back CI
- `upstream/main` is advisory drift detection
- scratch captures and debug output should not be committed
- compat behavior must be backed by committed upstream fixture evidence

## Open Source Notes

- License: MIT
- Changelog: `CHANGELOG.md`
- Fixture policy: `FIXTURE_POLICY.md`
- The current stable public facade is `ExDid`; method modules are implementation details even though they are user-overridable through the method registry.
- Canonical package repository: [github.com/bawolf/ex_did](https://github.com/bawolf/ex_did)

## Maintainer Workflow

`ex_did` currently lives in the `delegate` monorepo and is mirrored into the
standalone `ex_did` repository for publishing and external consumption.

The intended workflow is:

1. make library changes in `libs/ex_did`
2. run `mix test`
3. sync the package into a clean checkout of `github.com/bawolf/ex_did`
4. review and push from the standalone repo

A helper script for the sync step lives at `scripts/sync_standalone_repo.sh`.

The standalone repository also carries GitHub Actions workflows for:

- CI on push and pull request
- manual Hex publishing through `workflow_dispatch`

The publish workflow expects a `HEX_API_KEY` repository secret in the standalone
`ex_did` repository.
