# Contributing

Thanks for taking the time to contribute to `ex_did`.

## Development Model

`ex_did` is developed in the private `delegate` monorepo and mirrored into the
public `github.com/bawolf/ex_did` repository for issues, discussions, releases,
and Hex publishing.

- file bugs, feature requests, and interoperability questions in the public repo
- maintainers land code changes in the monorepo first
- direct standalone-repo edits are temporary hotfixes only and must be
  backported to the monorepo immediately
- community pull requests are welcome, but accepted changes are merged into the
  monorepo and then mirrored back into the public repo

## Good Reports

Please include:

- the `ex_did` version
- Elixir and OTP versions
- the DID or fixture involved
- whether the behavior differs from W3C, JavaScript, or `ssi` expectations
- a minimal reproduction when possible

## Release And Mirror Notes

Maintainers use:

- `scripts/release_preflight.sh`
- `scripts/sync_standalone_repo.sh`
- `scripts/verify_standalone_repo.sh`

The monorepo copy is the authoritative source for code, tests, docs, workflows,
and release tooling.
