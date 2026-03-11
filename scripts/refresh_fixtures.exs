alias ExDid.Base58Btc

fixtures_dir = Path.expand("../test/fixtures", __DIR__)

File.mkdir_p!(fixtures_dir)

did_key =
  <<0xED, 0x01, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
    22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32>>
  |> Base58Btc.encode()
  |> then(&"did:key:#{&1}")

did_key_x25519 =
  <<0xEC, 0x01, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21,
    22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32>>
  |> Base58Btc.encode()
  |> then(&"did:key:#{&1}")

did_jwk =
  ~s({"kty":"OKP","crv":"Ed25519","x":"VCpo2LMLhn6iWku8MKvSLg2ZAoC-nlOyPVQaO3FxVeQ"})
  |> Base.url_encode64(padding: false)
  |> then(&"did:jwk:#{&1}")

did_jwk_rsa =
  ~s({"kty":"RSA","n":"sXch4M4FhV6d3iD4n1x4Y6w8sMtvwlHGhEq-y3OCAXoTr4Wr9PXgC7vRl6VwB3p6k9RdtqvOB0fOkH1ZZ1xd6Q","e":"AQAB"})
  |> Base.url_encode64(padding: false)
  |> then(&"did:jwk:#{&1}")

manifest = %{
  generated_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(),
  sources: [
    %{
      fixture: "did_web_valid.json",
      source: %{
        type: "reference",
        urls: [
          "https://www.w3.org/TR/did-1.0/",
          "https://w3c-ccg.github.io/did-method-web/"
        ],
        note: "Local vendored example aligned to DID Core and did:web examples"
      }
    },
    %{
      fixture: "did_web_service_map.json",
      source: %{
        type: "compat",
        urls: [
          "https://github.com/decentralized-identity/did-resolver"
        ],
        note: "Compat fixture exercising single-service normalization"
      }
    },
    %{
      fixture: "did_key_valid.json",
      source: %{
        type: "reference",
        urls: [
          "https://w3c-ccg.github.io/did-method-key/"
        ],
        note: "Generated locally from ex_did deterministic did:key helper"
      }
    },
    %{
      fixture: "did_key_x25519_valid.json",
      source: %{
        type: "reference",
        urls: [
          "https://w3c-ccg.github.io/did-method-key/"
        ],
        note: "Generated locally from ex_did deterministic X25519 did:key helper"
      }
    },
    %{
      fixture: "did_jwk_valid.json",
      source: %{
        type: "reference",
        urls: [
          "https://github.com/quartzjer/did-jwk"
        ],
        note: "Generated locally from ex_did deterministic did:jwk helper"
      }
    },
    %{
      fixture: "did_jwk_rsa_valid.json",
      source: %{
        type: "reference",
        urls: [
          "https://github.com/quartzjer/did-jwk"
        ],
        note: "Generated locally from ex_did deterministic RSA did:jwk helper"
      }
    },
    %{
      fixture: "generated_ids.json",
      source: %{
        type: "generated",
        urls: [],
        note: "Generated locally from ex_did deterministic did:key and did:jwk helpers"
      }
    }
  ],
  generated: %{
    did_key: did_key,
    did_key_x25519: did_key_x25519,
    did_jwk: did_jwk,
    did_jwk_rsa: did_jwk_rsa
  }
}

Path.join(fixtures_dir, "generated_ids.json")
|> File.write!(Jason.encode_to_iodata!(manifest, pretty: true))

IO.puts("Refreshed fixture manifest at #{Path.join(fixtures_dir, "generated_ids.json")}")
