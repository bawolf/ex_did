# Changelog

All notable changes to `ex_did` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-03-11

### Changed
- Made strict DID output canonical per method instead of allowing output-family drift:
  `did:key` strict is now consistently Multikey-first across supported multicodecs,
  while `did:jwk` strict remains JWK-native.
- Confined `validation: :compat` to legacy/interoperability quirks rather than
  alternate canonical output families.
- Clarified README, Hex docs, and fixture policy around the strict/compat
  contract and the role of the JavaScript and `ssi-dids` parity corpora.

### Removed
- Deleted stale local deterministic fixture artifacts and the orphaned fixture
  refresh script that no longer defined the current resolver contract.

## [0.1.1] - 2026-03-11

### Added
- Maintainer-only `ssi-dids` parity recorder and committed released/advisory Rust DID corpora.
- Fixture-driven `ssi` parity coverage alongside the existing JavaScript resolver corpus.
- Additional `did:key` fixture coverage for secp256k1, P-256, and P-384 multikey inputs.

### Changed
- Clarified the package docs and fixture policy around the DID-only scope of `ex_did`.
- Aligned strict `did:key` multikey output more closely with current `ssi` behavior for secp256k1 and other non-Ed25519 multikey curves.

## [0.1.0] - 2026-03-10

### Added
- Typed `ExDid` facade for parse, resolve, representation resolution, and dereferencing.
- First-class `did:web`, `did:key`, and `did:jwk` method support.
- Strict-by-default validation with narrow per-call compatibility mode.
- Fixture-driven tests and downstream validation against `apps/delegate`.
- Maintainer-only upstream parity recorder with committed released and advisory fixture corpora.
- Helper APIs for canonical `did:web` construction and canonical local verification method ids.
