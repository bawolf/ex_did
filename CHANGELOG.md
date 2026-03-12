# Changelog

All notable changes to `ex_did` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.2] - 2026-03-12

### Added
- Public interoperability notes with an explicit decision log for released JS-vs-Rust DID divergences.
- A committed released divergence manifest that records the winning contract for each overlapping disagreement.

### Changed
- Release docs, HexDocs extras, and release gates now require the divergence log to stay in sync with the released parity corpus.
- Release process clarity improved by making divergence coverage part of the package release contract.

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
