# Upstream Parity Recorder

This maintainer-only tool records resolver outputs from current JavaScript DID
libraries into committed fixtures under `test/fixtures/upstream/`.

## Usage

Install the pinned recorder dependencies:

```bash
pnpm install
```

Refresh the required released corpus:

```bash
pnpm run record:released
```

Refresh the advisory upstream-`main` corpus:

```bash
pnpm run record:main
```

Normal `mix test` and normal `ex_did` usage do not require Node, pnpm, or
network access. The JavaScript toolchain is only for maintainers refreshing the
committed upstream parity fixtures.

## Policy

- `released/` is contractual and should back CI.
- `main/` is advisory and should be used for drift detection only.
- Only deterministic JSON outputs and manifests should be committed.
- Scratch captures, debug dumps, and temporary upstream checkouts should stay untracked.
