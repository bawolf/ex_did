defmodule ExDid.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/bawolf/ex_did"

  def project do
    [
      app: :ex_did,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Typed DID resolver library for did:web, did:key, and did:jwk.",
      package: package(),
      source_url: @source_url,
      homepage_url: @source_url,
      docs: [
        main: "readme",
        extras: ["README.md", "FIXTURE_POLICY.md", "CHANGELOG.md", "LICENSE"],
        source_ref: "v#{@version}",
        source_url: @source_url
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :crypto, :public_key],
      mod: {ExDid.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.37", only: :dev, runtime: false},
      {:jason, "~> 1.4"},
      {:jose, "~> 1.11"},
      {:nimble_options, "~> 1.1"},
      {:req, "~> 0.5"},
      {:stream_data, "~> 1.1", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Bryant Wolf"],
      links: %{
        "GitHub" => @source_url,
        "Hex" => "https://hex.pm/packages/ex_did",
        "Docs" => "https://hexdocs.pm/ex_did",
        "CI" => "#{@source_url}/actions/workflows/ci.yml",
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Fixture Policy" => "#{@source_url}/blob/main/FIXTURE_POLICY.md"
      }
    ]
  end
end
