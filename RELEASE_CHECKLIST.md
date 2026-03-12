# Release Checklist

Before publishing `ex_did`:

1. Run `mix format --check-formatted`.
2. Run `mix test`.
3. Run `mix docs`.
4. Confirm `README.md`, `INTEROP_NOTES.md`, `FIXTURE_POLICY.md`, and `CHANGELOG.md` still match the shipped behavior.
5. Confirm released parity fixtures still cover the supported package-owned surfaces and that every released JS-vs-Rust disagreement is listed in `test/fixtures/divergences/released.json`.
6. Confirm the version in `mix.exs` matches the intended release.
7. Sync `libs/ex_did` into a clean checkout of `github.com/bawolf/ex_did` with `scripts/sync_standalone_repo.sh /path/to/ex_did_repo`.
8. Push the release commit to the standalone repository.
9. Trigger the standalone repo publish workflow with the same version; it should publish to Hex and create the matching tag and GitHub release automatically.
