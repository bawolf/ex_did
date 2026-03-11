# Changelog

All notable changes to `ex_did` will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Typed `ExDid` facade for parse, resolve, representation resolution, and dereferencing.
- First-class `did:web`, `did:key`, and `did:jwk` method support.
- Strict-by-default validation with narrow per-call compatibility mode.
- Fixture-driven tests and downstream validation against `apps/delegate`.
- Maintainer-only upstream parity recorder with committed released and advisory fixture corpora.
- Helper APIs for canonical `did:web` construction and canonical local verification method ids.
