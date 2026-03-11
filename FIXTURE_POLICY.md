# Fixture Policy

`ex_did` ships its interoperability corpus in-repo.

## Contract Levels

- `test/fixtures/upstream/released/` is contractual.
- `test/fixtures/upstream/main/` is advisory drift detection.

Released fixtures are the resolver-parity contract used by tests. Advisory
fixtures exist to show how current upstream default branches are changing before
those changes become release targets.

## Runtime Boundary

Using `ex_did` does not require JavaScript, pnpm, or network access. Running
the normal Elixir test suite should only consume committed fixtures.

JavaScript tooling is maintainer-only and exists solely to refresh upstream
fixtures under `libs/ex_did/scripts/upstream_parity/`.

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

Add a compat rule only when:

1. strict mode behavior is already clear,
2. an upstream resolver divergence is real and reproducible,
3. the divergence is captured in a committed fixture, and
4. the README and tests explain the exception.
