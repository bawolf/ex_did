defmodule ExDidTest do
  use ExUnit.Case, async: true

  use ExUnitProperties
  doctest ExDid

  alias ExDid.Base58Btc
  alias ExDid.DID
  alias ExDid.DIDURL

  @fixtures_dir Path.expand("fixtures", __DIR__)
  @upstream_dir Path.join(@fixtures_dir, "upstream")
  @ssi_upstream_dir Path.join(@upstream_dir, "ssi")
  @divergence_manifest Path.join([@fixtures_dir, "divergences", "released.json"])

  describe "method/1" do
    test "extracts the method from a DID" do
      assert ExDid.method("did:web:example.com") == "web"
      assert ExDid.method(example_did_key()) == "key"
      assert ExDid.method(example_did_jwk()) == "jwk"
    end

    test "returns nil for invalid DID syntax" do
      assert ExDid.method("did:web:") == nil
    end
  end

  describe "parse/2" do
    test "parses DID URL components into typed structs" do
      assert {:ok,
              %DIDURL{
                did: %DID{value: "did:web:example.com", method: "web"},
                method: "web",
                method_specific_id: "example.com",
                params: [%{name: "service", value: "hub"}],
                path: "/images/logo.svg",
                query: "v=1",
                fragment: "key-1"
              }} =
               ExDid.parse("did:web:example.com;service=hub/images/logo.svg?v=1#key-1")
    end

    property "round-trips generated bare did:web identifiers" do
      part =
        one_of([
          string([?a..?z, ?0..?9], min_length: 1, max_length: 8),
          constant("example.com"),
          constant("team"),
          constant("alice")
        ])

      check all(
              host <- one_of([constant("example.com"), constant("localhost%3A8443")]),
              path_segments <- list_of(part, max_length: 3)
            ) do
        did =
          case path_segments do
            [] -> "did:web:#{host}"
            _ -> "did:web:#{Enum.join([host | path_segments], ":")}"
          end

        assert {:ok, %DIDURL{did: %DID{value: ^did}, method: "web"}} = ExDid.parse(did)
      end
    end
  end

  describe "resolve_url/1" do
    test "maps did:web DIDs to HTTPS URLs" do
      assert ExDid.resolve_url("did:web:example.com") ==
               {:ok, "https://example.com/.well-known/did.json"}

      assert ExDid.resolve_url("did:web:example.com:user:alice") ==
               {:ok, "https://example.com/user/alice/did.json"}
    end

    test "returns a typed error for invalid did:web URLs" do
      assert {:error, error} = ExDid.resolve_url("did:web:example.com#key-1")
      assert error.code == :invalid_did
    end
  end

  describe "helper constructors" do
    test "builds a canonical did:web identifier" do
      assert ExDid.did_web("example.com") == {:ok, "did:web:example.com"}

      assert ExDid.did_web("localhost:8443", ["users", "alice"]) ==
               {:ok, "did:web:localhost%3A8443:users:alice"}
    end

    test "returns canonical verification method ids for local methods" do
      did_key = example_did_key()
      did_jwk = example_did_jwk()

      assert {:ok, method_id} = ExDid.verification_method_id(did_key)
      assert method_id == did_key <> "#" <> String.replace_prefix(did_key, "did:key:", "")

      assert ExDid.verification_method_id(did_jwk) == {:ok, did_jwk <> "#0"}
    end
  end

  describe "verification_method_jwks/1" do
    test "returns public JWKs from a JsonWebKey verification method" do
      document = fixture!("did_web_valid.json")

      assert [%{"kty" => "OKP", "crv" => "Ed25519", "x" => x}] =
               ExDid.verification_method_jwks(document)

      assert is_binary(x)
    end

    test "returns public JWKs derived from multikey verification methods" do
      document =
        ExDid.resolve(example_did_key()).did_document

      assert [%{"kty" => "OKP", "crv" => "Ed25519", "x" => x}] =
               ExDid.verification_method_jwks(document)

      assert is_binary(x)
    end
  end

  describe "resolve/2 for did:web" do
    test "resolves a valid document fixture" do
      did = "did:web:example.com"
      document = fixture!("did_web_valid.json")

      result = ExDid.resolve(did, fetch_json: fn _url -> {:ok, document} end)

      assert result.did_document == document

      assert result.did_document_metadata["sourceUrl"] ==
               "https://example.com/.well-known/did.json"

      assert result.did_resolution_metadata["contentType"] == "application/did+ld+json"
      assert is_binary(result.did_resolution_metadata["retrieved"])
    end

    test "strict mode rejects non-list service entries" do
      did = "did:web:example.com"
      document = fixture!("did_web_service_map.json")

      result = ExDid.resolve(did, fetch_json: fn _url -> {:ok, document} end)

      assert result.did_document == nil
      assert result.did_resolution_metadata["error"] == "invalidDidDocument"
    end

    test "compat mode normalizes a single service map" do
      did = "did:web:example.com"
      document = fixture!("did_web_service_map.json")

      result = ExDid.resolve(did, validation: :compat, fetch_json: fn _url -> {:ok, document} end)

      assert [%{"id" => "#hub"}] = result.did_document["service"]
    end

    test "strict mode rejects unexpected response content types" do
      did = "did:web:example.com"
      document = fixture!("did_web_valid.json")

      result =
        ExDid.resolve(did,
          fetch_json: fn _url ->
            {:ok, document, %{content_type: "application/json"}}
          end
        )

      assert result.did_document == nil
      assert result.did_resolution_metadata["error"] == "invalidDidDocument"

      reason =
        Map.get(result.did_resolution_metadata["details"], "reason") ||
          Map.get(result.did_resolution_metadata["details"], :reason)

      assert reason == :unexpected_content_type
    end

    test "compat mode accepts application/json response content types" do
      did = "did:web:example.com"
      document = fixture!("did_web_valid.json")

      result =
        ExDid.resolve(did,
          validation: :compat,
          fetch_json: fn _url ->
            {:ok, document, %{content_type: "application/json"}}
          end
        )

      assert result.did_document["id"] == did
    end

    test "rejects malformed resource ids even when relationships match" do
      did = "did:web:example.com"
      document = fixture!("did_web_invalid_resource_id.json")

      result = ExDid.resolve(did, fetch_json: fn _url -> {:ok, document} end)

      assert result.did_document == nil
      assert result.did_resolution_metadata["error"] == "invalidDidDocument"
    end
  end

  describe "resolve_representation/2" do
    test "returns a JSON representation for did:web" do
      document = fixture!("did_web_valid.json")

      result =
        ExDid.resolve_representation("did:web:example.com",
          fetch_json: fn _url -> {:ok, document} end
        )

      assert result.content_type == "application/did+ld+json"
      assert Jason.decode!(result.content_stream) == document
    end

    test "accept option overrides the requested representation" do
      document = fixture!("did_web_valid.json")

      result =
        ExDid.resolve_representation("did:web:example.com",
          accept: "application/did+ld+json",
          fetch_json: fn _url -> {:ok, document} end
        )

      assert result.content_type == "application/did+ld+json"
    end

    test "rejects unsupported representation requests" do
      document = fixture!("did_web_valid.json")

      result =
        ExDid.resolve_representation("did:web:example.com",
          accept: "application/did+cbor",
          fetch_json: fn _url -> {:ok, document} end
        )

      assert result.content_stream == nil
      assert result.did_resolution_metadata["error"] == "representationNotSupported"
    end
  end

  describe "resolve/2 for did:key" do
    test "strict mode resolves an Ed25519 did:key DID to canonical multikey output" do
      did = example_did_key()

      result = ExDid.resolve(did)
      document = result.did_document
      verification_method = hd(document["verificationMethod"])
      [derived_key_agreement] = document["keyAgreement"]

      assert verification_method["id"] ==
               did <> "#z6MknCCLeeHBUaHu4aHSVLDCYQW9gjVJ7a63FpMvtuVMy53T"

      assert verification_method["type"] == "Multikey"

      assert verification_method["publicKeyMultibase"] ==
               "z6MknCCLeeHBUaHu4aHSVLDCYQW9gjVJ7a63FpMvtuVMy53T"

      assert document["authentication"] == [verification_method["id"]]
      assert document["assertionMethod"] == [verification_method["id"]]
      assert document["capabilityInvocation"] == [verification_method["id"]]
      assert document["capabilityDelegation"] == [verification_method["id"]]
      assert derived_key_agreement["type"] == "Multikey"

      assert derived_key_agreement["id"] ==
               did <> "#z6LSotGbgPCJD2Y6TSvvgxERLTfVZxCh9KSrez3WNrNp7vKW"
    end

    test "strict mode resolves an X25519 did:key DID to keyAgreement-only multikey output" do
      did = example_did_key_x25519()

      result = ExDid.resolve(did)
      document = result.did_document

      assert document["keyAgreement"] == [
               %{
                 "id" => did <> "#z6LSotGbgPCJD2Y6TSvvgxERLTfVZxCh9KSrez3WNrNp7vKW",
                 "type" => "Multikey",
                 "controller" => did,
                 "publicKeyMultibase" => "z6LSotGbgPCJD2Y6TSvvgxERLTfVZxCh9KSrez3WNrNp7vKW"
               }
             ]

      refute Map.has_key?(document, "verificationMethod")
      refute Map.has_key?(document, "authentication")
    end

    property "deterministically round-trips Ed25519 public keys" do
      check all(_ <- constant(:ok)) do
        {public_key, _private_key} = :crypto.generate_key(:eddsa, :ed25519)
        fingerprint = Base58Btc.encode(<<0xED, 0x01, public_key::binary>>)
        did = "did:key:" <> fingerprint

        result = ExDid.resolve(did)

        assert hd(result.did_document["verificationMethod"])["publicKeyMultibase"] == fingerprint
      end
    end

    test "resolves a secp256k1 multikey DID locally" do
      did = example_did_key_secp256k1()
      result = ExDid.resolve(did)
      verification_method = hd(result.did_document["verificationMethod"])

      assert verification_method["type"] == "Multikey"
      assert result.did_document["authentication"] == [verification_method["id"]]
      assert result.did_document["assertionMethod"] == [verification_method["id"]]
      assert result.did_document["capabilityInvocation"] == [verification_method["id"]]
      assert result.did_document["capabilityDelegation"] == [verification_method["id"]]
    end

    test "resolves a P-256 multikey DID locally" do
      did = example_did_key_p256()
      result = ExDid.resolve(did)
      verification_method = hd(result.did_document["verificationMethod"])

      assert verification_method["type"] == "Multikey"
      assert result.did_document["authentication"] == [verification_method["id"]]
      assert result.did_document["capabilityInvocation"] == [verification_method["id"]]
    end

    test "resolves a P-384 multikey DID locally" do
      did = example_did_key_p384()
      result = ExDid.resolve(did)
      verification_method = hd(result.did_document["verificationMethod"])

      assert verification_method["type"] == "Multikey"
      assert result.did_document["authentication"] == [verification_method["id"]]
      assert result.did_document["capabilityDelegation"] == [verification_method["id"]]
    end

    test "compat mode preserves the legacy JS did:key Ed25519 shape" do
      did = example_did_key()
      expected = upstream_case!("released", "did-key-ed25519-resolve")["expected"]["didDocument"]

      result = ExDid.resolve(did, validation: :compat)

      assert result.did_document == expected
    end
  end

  describe "resolve/2 for did:jwk" do
    test "strict mode resolves an OKP public JWK DID to a JWK-native document" do
      did = example_did_jwk()
      expected = upstream_case!("released", "did-jwk-okp-resolve")["expected"]["didDocument"]

      result = ExDid.resolve(did)

      assert result.did_document == expected
      assert result.did_resolution_metadata["contentType"] == "application/did+json"
      assert result.did_document_metadata["source"] == "local"
      assert hd(result.did_document["verificationMethod"])["type"] == "JsonWebKey"
    end

    test "strict mode resolves a P-256 public JWK DID to a JWK-native document" do
      did = example_did_jwk_p256()

      result = ExDid.resolve(did)
      verification_method = hd(result.did_document["verificationMethod"])

      assert verification_method["type"] == "JsonWebKey"
      assert verification_method["publicKeyJwk"]["crv"] == "P-256"
      assert result.did_document["authentication"] == [verification_method["id"]]
      refute Map.has_key?(result.did_document, "keyAgreement")
    end

    test "strict mode resolves an RSA JWK DID to a JWK-native document" do
      did = example_did_jwk_rsa()

      result = ExDid.resolve(did)
      verification_method = hd(result.did_document["verificationMethod"])

      assert verification_method["type"] == "JsonWebKey"
      assert verification_method["publicKeyJwk"]["kty"] == "RSA"
      assert result.did_document["authentication"] == [verification_method["id"]]
      assert result.did_document["capabilityDelegation"] == [verification_method["id"]]
    end

    test "strict mode rejects private jwk material" do
      result = ExDid.resolve(example_private_did_jwk())

      assert result.did_document == nil
      assert result.did_resolution_metadata["error"] == "invalidDid"
    end

    test "compat mode strips private jwk material" do
      result = ExDid.resolve(example_private_did_jwk(), validation: :compat)

      refute Map.has_key?(hd(result.did_document["verificationMethod"])["publicKeyJwk"], "d")
    end

    test "compat mode keeps the same did:jwk output family while stripping private material" do
      strict_result =
        ExDid.resolve(example_did_jwk(), validation: :strict)

      compat_result =
        ExDid.resolve(example_private_did_jwk(), validation: :compat)

      assert hd(compat_result.did_document["verificationMethod"])["type"] == "JsonWebKey"
      assert Map.keys(compat_result.did_document) == Map.keys(strict_result.did_document)
    end

    test "strict representation can negotiate did+ld+json for JWK-native output" do
      did = example_did_jwk()

      result = ExDid.resolve_representation(did, accept: "application/did+ld+json")

      assert result.content_type == "application/did+ld+json"
      assert Jason.decode!(result.content_stream) == ExDid.resolve(did).did_document
    end
  end

  describe "dereference/2" do
    test "dereferences a did:web verification method" do
      did = "did:web:example.com"
      document = fixture!("did_web_valid.json")

      result = ExDid.dereference(did <> "#key-1", fetch_json: fn _url -> {:ok, document} end)

      assert result.content_stream["id"] == did <> "#key-1"
      assert result.dereferencing_metadata["contentType"] == "application/did+ld+json"
    end

    test "dereferences a did:web service path via service parameter" do
      did = "did:web:example.com"
      document = fixture!("did_web_valid.json")

      result =
        ExDid.dereference(did <> ";service=hub/credentials?v=1",
          validation: :compat,
          fetch_json: fn _url -> {:ok, document} end
        )

      assert result.content_stream["serviceEndpoint"] == "https://example.com/hub"
      assert result.content_stream["path"] == "/credentials"
    end

    test "dereferences a did:key fragment" do
      did = example_did_key()
      fingerprint = String.replace_prefix(did, "did:key:", "")

      result = ExDid.dereference(did <> "#" <> fingerprint)

      assert result.content_stream["type"] == "Multikey"
      assert result.content_stream["id"] == did <> "#" <> fingerprint
    end

    test "dereferences a did:jwk fragment" do
      did = example_did_jwk()
      expected = upstream_case!("released", "did-jwk-okp-dereference")["expected"]

      result = ExDid.dereference(did <> "#0")

      assert result.content_stream == expected["contentStream"]
    end
  end

  describe "custom method registries" do
    test "allow registry overrides per call" do
      registry = %{"web" => ExDid.Method.Web}
      document = fixture!("did_web_valid.json")

      result =
        ExDid.resolve("did:web:example.com",
          method_registry: registry,
          fetch_json: fn _url -> {:ok, document} end
        )

      assert result.did_document["id"] == "did:web:example.com"
    end

    test "reject invalid registry shapes" do
      assert %ExDid.ResolutionResult{did_document: nil, did_resolution_metadata: metadata} =
               ExDid.resolve("did:web:example.com", method_registry: %{web: ExDid.Method.Web})

      assert metadata["error"] == "invalidDid"
    end
  end

  describe "unsupported methods" do
    test "return methodNotSupported in the resolution metadata" do
      result = ExDid.resolve("did:example:123")

      assert result.did_document == nil
      assert result.did_resolution_metadata["error"] == "methodNotSupported"
    end
  end

  describe "upstream parity corpus" do
    test "released corpus manifests stay runnable" do
      manifest = upstream_manifest!("released")

      assert manifest["advisory"] == false
      assert manifest["cases"] != []

      Enum.each(manifest["cases"], fn entry ->
        case_data = upstream_case_by_file!("released", entry["file"])

        case case_data["operation"] do
          "resolve" ->
            result = resolve_case(case_data)

            if exact_upstream_case?(case_data) do
              assert result.did_document == case_data["expected"]["didDocument"]
            else
              assert result.did_document != nil
            end

          "resolveRepresentation" ->
            result = resolve_representation_case(case_data)

            if exact_upstream_case?(case_data) do
              assert Jason.decode!(result.content_stream) ==
                       case_data["expected"]["contentStream"]

              assert result.content_type == case_data["expected"]["contentType"]
            else
              assert result.content_stream != nil
            end

          "dereference" ->
            result = dereference_case(case_data)

            if exact_upstream_case?(case_data) do
              assert result.content_stream == case_data["expected"]["contentStream"]

              assert result.dereferencing_metadata ==
                       case_data["expected"]["dereferencingMetadata"]

              assert stringify_keys(result.content_metadata) ==
                       case_data["expected"]["contentMetadata"]
            else
              assert result.content_stream != nil
            end
        end
      end)
    end

    test "advisory corpus remains non-contractual metadata" do
      manifest = upstream_manifest!("main")

      assert manifest["advisory"] == true
      assert manifest["channel"] == "main"
    end
  end

  describe "ssi parity corpus" do
    test "released ssi corpus manifests stay runnable for overlapping cases" do
      manifest = ssi_manifest!("released")

      assert manifest["advisory"] == false
      assert manifest["cases"] != []

      Enum.each(manifest["cases"], fn entry ->
        case_data = ssi_case_by_file!("released", entry["file"])

        case case_data["operation"] do
          "resolve" ->
            result = ssi_resolve_case(case_data)
            assert result.did_document != nil

          "resolveRepresentation" ->
            result = ssi_resolve_representation_case(case_data)
            assert result.content_stream != nil
            assert result.content_type in ["application/did+json", "application/did+ld+json"]

          "dereference" ->
            result = ssi_dereference_case(case_data)
            assert result.content_stream != nil
        end
      end)
    end

    test "advisory ssi corpus remains non-contractual metadata" do
      manifest = ssi_manifest!("main")

      assert manifest["advisory"] == true
      assert manifest["channel"] == "main"
    end
  end

  describe "documented divergence log" do
    test "covers every released JS vs ssi disagreement" do
      documented =
        divergence_manifest!()["divergences"]
        |> Enum.map(& &1["file"])
        |> MapSet.new()

      actual =
        overlapping_released_case_files()
        |> Enum.filter(fn file ->
          upstream_case_by_file!("released", file)["expected"] !=
            ssi_case_by_file!("released", file)["expected"]
        end)
        |> MapSet.new()

      assert documented == actual
    end

    test "did:key strict still follows the documented ssi-backed multikey contract" do
      entry = divergence_entry!("did-key-ed25519-resolve.json")

      assert entry["decision"] == "library_contract_wins"
      assert entry["chosenOracle"] == "ssi"

      expected = ssi_case!("released", "did-key-ed25519-resolve")["expected"]["didDocument"]
      actual = ExDid.resolve(example_did_key()).did_document

      assert actual["@context"] == expected["@context"]
      assert actual["verificationMethod"] == expected["verificationMethod"]
      assert actual["authentication"] == expected["authentication"]
      assert actual["assertionMethod"] == expected["assertionMethod"]
      assert actual["id"] == expected["id"]
      assert Enum.all?(actual["keyAgreement"], &(&1["type"] == "Multikey"))
    end

    test "did:jwk strict still follows the documented js-backed jwk-native contract" do
      entry = divergence_entry!("did-jwk-okp-resolve.json")

      assert entry["decision"] == "library_contract_wins"
      assert entry["chosenOracle"] == "js"

      expected = upstream_case!("released", "did-jwk-okp-resolve")["expected"]["didDocument"]
      assert ExDid.resolve(example_did_jwk()).did_document == expected
    end

    test "did:web resolve still follows the documented js-backed metadata contract" do
      entry = divergence_entry!("did-web-root-resolve.json")

      assert entry["decision"] == "library_contract_wins"
      assert entry["chosenOracle"] == "js"

      case_data = upstream_case!("released", "did-web-root-resolve")
      result = resolve_case(case_data)

      assert result.did_document == case_data["expected"]["didDocument"]
      assert result.did_document_metadata == case_data["expected"]["didDocumentMetadata"]

      assert result.did_resolution_metadata["contentType"] ==
               case_data["expected"]["didResolutionMetadata"]["contentType"]
    end
  end

  defp fixture!(name) do
    @fixtures_dir
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end

  defp upstream_manifest!(channel) do
    @upstream_dir
    |> Path.join(channel)
    |> Path.join("manifest.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp upstream_case!(channel, id) do
    upstream_case_by_file!(channel, "#{id}.json")
  end

  defp divergence_manifest! do
    @divergence_manifest
    |> File.read!()
    |> Jason.decode!()
  end

  defp divergence_entry!(file) do
    divergence_manifest!()["divergences"]
    |> Enum.find(fn entry -> entry["file"] == file end)
    |> case do
      nil -> flunk("missing divergence entry for #{file}")
      entry -> entry
    end
  end

  defp upstream_case_by_file!(channel, file) do
    @upstream_dir
    |> Path.join(channel)
    |> Path.join("cases")
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
  end

  defp ssi_manifest!(channel) do
    @ssi_upstream_dir
    |> Path.join(channel)
    |> Path.join("manifest.json")
    |> File.read!()
    |> Jason.decode!()
  end

  defp ssi_case!(channel, id) do
    ssi_case_by_file!(channel, "#{id}.json")
  end

  defp ssi_case_by_file!(channel, file) do
    @ssi_upstream_dir
    |> Path.join(channel)
    |> Path.join("cases")
    |> Path.join(file)
    |> File.read!()
    |> Jason.decode!()
  end

  defp overlapping_released_case_files do
    js =
      Path.join([@upstream_dir, "released", "cases", "*.json"])
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> MapSet.new()

    ssi =
      Path.join([@ssi_upstream_dir, "released", "cases", "*.json"])
      |> Path.wildcard()
      |> Enum.map(&Path.basename/1)
      |> MapSet.new()

    js
    |> MapSet.intersection(ssi)
    |> MapSet.to_list()
  end

  defp example_did_key do
    "did:key:z6MknCCLeeHBUaHu4aHSVLDCYQW9gjVJ7a63FpMvtuVMy53T"
  end

  defp example_did_jwk do
    ~s({"kty":"OKP","crv":"Ed25519","x":"VCpo2LMLhn6iWku8MKvSLg2ZAoC-nlOyPVQaO3FxVeQ"})
    |> Base.url_encode64(padding: false)
    |> then(&"did:jwk:#{&1}")
  end

  defp example_did_key_x25519 do
    "did:key:z6LSotGbgPCJD2Y6TSvvgxERLTfVZxCh9KSrez3WNrNp7vKW"
  end

  defp example_did_jwk_p256 do
    ~s({"kty":"EC","crv":"P-256","x":"g3fsv1xpWPH099LIUn_zJoOF5Ur8xobyzZwX9m_dJ4E","y":"9304UAFl55xQMfrnB-zKEjjXEC4OFWSuYnr7W6hdkVA"})
    |> Base.url_encode64(padding: false)
    |> then(&"did:jwk:#{&1}")
  end

  defp example_did_key_secp256k1 do
    "did:key:zQ3shtDoCx5Sdz8r78bEKXdn9BcVpLKDD3gkvMbY4Y5zLZPhh"
  end

  defp example_did_key_p256 do
    "did:key:zDnaembS6RTHHn4VxPkoeCodDa1iwzUgUvqHN7bhBnBALBRTE"
  end

  defp example_did_key_p384 do
    "did:key:z82LkvutaARmY8poLhUnMCAhFbts88q4yDBmkqwRFYbxpFvmE1nbGUGLKf9fD66LGUbXDce"
  end

  defp example_did_jwk_rsa do
    ~s({"kty":"RSA","n":"sXch4M4FhV6d3iD4n1x4Y6w8sMtvwlHGhEq-y3OCAXoTr4Wr9PXgC7vRl6VwB3p6k9RdtqvOB0fOkH1ZZ1xd6Q","e":"AQAB"})
    |> Base.url_encode64(padding: false)
    |> then(&"did:jwk:#{&1}")
  end

  defp example_private_did_jwk do
    ~s({"kty":"OKP","crv":"Ed25519","x":"VCpo2LMLhn6iWku8MKvSLg2ZAoC-nlOyPVQaO3FxVeQ","d":"nWGxne_9Wm7Qx6AAnqS5m0r2X0Q6wK8v8B5Q2VK3T8Q"})
    |> Base.url_encode64(padding: false)
    |> then(&"did:jwk:#{&1}")
  end

  defp resolve_case(case_data) do
    if String.starts_with?(case_data["input"], "did:web:") do
      ExDid.resolve(case_data["input"],
        fetch_json: fn _url -> {:ok, case_data["expected"]["didDocument"]} end
      )
    else
      opts =
        if String.starts_with?(case_data["input"], "did:key:"),
          do: [validation: :compat],
          else: []

      ExDid.resolve(case_data["input"], opts)
    end
  end

  defp resolve_representation_case(case_data) do
    if String.starts_with?(case_data["input"], "did:web:") do
      ExDid.resolve_representation(case_data["input"],
        fetch_json: fn _url -> {:ok, case_data["expected"]["contentStream"]} end
      )
    else
      opts =
        if String.starts_with?(case_data["input"], "did:key:"),
          do: [validation: :compat],
          else: []

      ExDid.resolve_representation(case_data["input"], opts)
    end
  end

  defp dereference_case(case_data) do
    input = case_data["input"]

    if String.starts_with?(input, "did:web:") do
      root_case =
        if String.contains?(input, ":user:alice") do
          upstream_case!("released", "did-web-path-resolve")
        else
          upstream_case!("released", "did-web-root-resolve")
        end

      ExDid.dereference(input,
        fetch_json: fn _url -> {:ok, root_case["expected"]["didDocument"]} end
      )
    else
      opts =
        if String.starts_with?(input, "did:key:"),
          do: [validation: :compat],
          else: []

      ExDid.dereference(input, opts)
    end
  end

  defp ssi_resolve_case(case_data) do
    if String.starts_with?(case_data["input"], "did:web:") do
      ExDid.resolve(case_data["input"],
        fetch_json: fn _url -> {:ok, case_data["expected"]["didDocument"]} end
      )
    else
      ExDid.resolve(case_data["input"])
    end
  end

  defp ssi_resolve_representation_case(case_data) do
    if String.starts_with?(case_data["input"], "did:web:") do
      ExDid.resolve_representation(case_data["input"],
        fetch_json: fn _url -> {:ok, case_data["expected"]["contentStream"]} end
      )
    else
      ExDid.resolve_representation(case_data["input"])
    end
  end

  defp ssi_dereference_case(case_data) do
    input = case_data["input"]

    if String.starts_with?(input, "did:web:") do
      root_case =
        if String.contains?(input, ":user:alice") do
          ssi_case!("released", "did-web-path-resolve")
        else
          ssi_case!("released", "did-web-root-resolve")
        end

      ExDid.dereference(input,
        fetch_json: fn _url -> {:ok, root_case["expected"]["didDocument"]} end
      )
    else
      ExDid.dereference(input)
    end
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {key, value} ->
      normalized =
        cond do
          is_binary(key) -> key
          is_atom(key) -> Atom.to_string(key)
          true -> to_string(key)
        end

      {normalized, value}
    end)
  end

  defp exact_upstream_case?(%{"id" => "did-jwk-rsa-resolve"}), do: false
  defp exact_upstream_case?(_case_data), do: true
end
