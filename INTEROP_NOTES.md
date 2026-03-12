# Interop Notes

`ex_did` tracks two implementation-oracle families:

- JavaScript DID resolvers for current Digital Bazaar style DID behavior
- Rust `ssi-dids` for overlapping DID-only behavior

## Contract Rule

`ex_did` does not silently merge resolver outputs.

When the JavaScript and Rust ecosystems disagree, the library records the
disagreement in committed fixtures and chooses one explicit package contract.

## Decision Log

| Surface | Decision | Chosen Contract | Notes |
| --- | --- | --- | --- |
| `did:key` strict resolve / representation / dereference | `library_contract_wins` | `ssi` | Strict `did:key` remains Multikey-first rather than older JS 2020-suite document shapes |
| `did:jwk` strict resolve / representation / dereference | `library_contract_wins` | JavaScript | Strict `did:jwk` remains JWK-native rather than converting method output into Multikey |
| `did:web` resolve / representation / dereference metadata | `library_contract_wins` | JavaScript | Current library contract keeps source URL metadata instead of the Rust `deactivated: null` metadata shape |

The full released divergence set is tracked in
`test/fixtures/divergences/released.json`.

## Policy

- Do not add a compat path just to make two upstreams pass at once.
- Do not claim parity for a divergent surface unless the winning contract is
  named explicitly in tests and docs.
- Every released JS-vs-Rust disagreement must have a committed divergence entry.
