# Fixture Policy

`ex_did` ships its interoperability corpus in-repo.

## Contract Levels

- `test/fixtures/upstream/released/` is the contractual JavaScript corpus.
- `test/fixtures/upstream/main/` is advisory JavaScript drift detection.
- `test/fixtures/upstream/ssi/released/` is the contractual overlapping `ssi` DID corpus.
- `test/fixtures/upstream/ssi/main/` is advisory `ssi` drift detection.

Released fixtures are the resolver-parity contract used by tests. Advisory
fixtures exist to show how current upstream default branches or recorder
snapshots are changing before those changes become release targets.

## Runtime Boundary

Using `ex_did` does not require JavaScript, pnpm, or network access. Running
the normal Elixir test suite should only consume committed fixtures.

JavaScript tooling is maintainer-only and exists solely to refresh JS fixtures
under `libs/ex_did/scripts/upstream_parity/`.

Rust tooling is also maintainer-only and exists solely to refresh `ssi` DID
fixtures under `libs/ex_did/scripts/ssi_parity/`.

The vendored top-level fixtures under `test/fixtures/` are local deterministic
examples for `did:web` validation paths. They are not a second parity corpus.

## What Gets Committed

Commit:

- normalized JSON fixtures
- corpus manifests with provenance
- recorder source code
- package manager manifest and lockfile for the recorder

Do not commit:

- scratch captures
- temporary upstream checkouts
- debug dumps
- machine-specific cache files

## Compat Rules

`validation: :compat` must stay narrow.

Strict mode follows the canonical `ex_did` contract on a per-method basis:

- `did:key` strict is Multikey-first
- `did:jwk` strict is JWK-native

`ssi` disagreements are useful evidence, but they do not override the
method-specific strict contract on their own.

Add a compat rule only when:

1. strict mode behavior is already clear,
2. an upstream resolver divergence is real and reproducible,
3. the divergence is captured in a committed fixture, and
4. the README, `INTEROP_NOTES.md`, and tests explain the exception.
