# SSI Parity Recorder

This directory contains maintainer-only tooling for recording DID-only parity
fixtures from the Rust `ssi-dids` stack.

It is not required to use `ex_did` and is not part of the library runtime.

## Usage

```bash
cargo run -- released
cargo run -- main
```

The recorder writes normalized fixtures under `test/fixtures/upstream/ssi/`.
