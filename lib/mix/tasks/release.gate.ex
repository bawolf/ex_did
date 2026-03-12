defmodule Mix.Tasks.ExDid.Release.Gate do
  use Mix.Task

  @shortdoc "Runs the ex_did release gate checks"

  @moduledoc """
  Runs the standard release gate for `ex_did`.

  The gate checks:

  - formatting
  - compilation with warnings as errors
  - test suite
  - released JavaScript and `ssi` parity corpus presence
  - docs build
  - Hex package build
  """

  @required_docs ~w(
    README.md
    INTEROP_NOTES.md
    FIXTURE_POLICY.md
    CHANGELOG.md
    LICENSE
  )

  @released_manifests [
    "test/fixtures/upstream/released/manifest.json",
    "test/fixtures/upstream/ssi/released/manifest.json",
    "test/fixtures/divergences/released.json"
  ]

  @impl Mix.Task
  def run(_args) do
    ensure_release_docs!()
    ensure_released_corpora!()

    run_mix_command!(["format", "--check-formatted"])
    run_mix_command!(["compile", "--warning-as-errors"])
    run_mix_command!(["test"], %{"MIX_ENV" => "test"})
    run_mix_command!(["docs"])
    run_mix_command!(["hex.build"])

    Mix.shell().info("ex_did release gate passed")
  end

  defp ensure_release_docs! do
    missing =
      Enum.reject(@required_docs, fn path ->
        File.regular?(path)
      end)

    if missing != [] do
      Mix.raise("missing release docs: #{Enum.join(missing, ", ")}")
    end
  end

  defp ensure_released_corpora! do
    missing =
      Enum.reject(@released_manifests, fn path ->
        File.regular?(path)
      end)

    if missing != [] do
      Mix.raise("missing released parity manifest(s): #{Enum.join(missing, ", ")}")
    end
  end

  defp run_mix_command!(args, extra_env \\ %{}) do
    case System.cmd("mix", args,
           into: IO.stream(:stdio, :line),
           stderr_to_stdout: true,
           env: Enum.to_list(extra_env)
         ) do
      {_output, 0} ->
        :ok

      {_output, status} ->
        Mix.raise("mix #{Enum.join(args, " ")} failed with exit status #{status}")
    end
  end
end
