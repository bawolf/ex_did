use std::fs;
use std::path::{Path, PathBuf};

use chrono::Utc;
use serde::Serialize;
use serde_json::{json, Value};
use ssi_dids::resolution::Content;
use ssi_dids::{AnyDidMethod, DIDBuf, DIDResolver, DIDURLBuf};
use ssi_jwk::JWK;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;
use tokio::task::JoinHandle;

const DID_WEB_PORT: u16 = 57433;

#[derive(Clone)]
struct Scenario {
    id: &'static str,
    operation: &'static str,
    input: String,
}

#[derive(Serialize)]
struct Manifest<'a> {
    #[serde(rename = "schemaVersion")]
    schema_version: u8,
    advisory: bool,
    channel: &'a str,
    #[serde(rename = "generatedAt")]
    generated_at: String,
    recorder: Value,
    packages: Value,
    cases: Vec<Value>,
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let channel = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "released".to_string());

    if channel != "released" && channel != "main" {
        return Err(format!("unsupported channel: {channel}").into());
    }

    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../../test/fixtures/upstream/ssi")
        .join(&channel);
    let cases_dir = root.join("cases");

    if cases_dir.exists() {
        fs::remove_dir_all(&cases_dir)?;
    }

    fs::create_dir_all(&cases_dir)?;

    let resolver = AnyDidMethod::default();
    let scenarios = scenarios();
    let mut manifest_cases = Vec::new();

    with_did_web_server(|| async {
        for scenario in scenarios {
            let record = record(&resolver, &scenario).await?;
            let file = format!("{}.json", scenario.id);
            write_json(&cases_dir.join(&file), &record)?;
            manifest_cases.push(json!({
                "id": scenario.id,
                "operation": scenario.operation,
                "input": scenario.input,
                "file": file
            }));
        }

        Ok::<(), Box<dyn std::error::Error>>(())
    })
    .await?;

    let manifest = Manifest {
        schema_version: 1,
        advisory: channel == "main",
        channel: &channel,
        generated_at: Utc::now().to_rfc3339(),
        recorder: json!({
            "name": "ex_did_ssi_parity",
            "packageManager": "cargo"
        }),
        packages: package_versions(),
        cases: manifest_cases,
    };

    write_json(&root.join("manifest.json"), &manifest)?;
    Ok(())
}

fn scenarios() -> Vec<Scenario> {
    let did_key_ed25519 = "did:key:z6MknCCLeeHBUaHu4aHSVLDCYQW9gjVJ7a63FpMvtuVMy53T".to_string();
    let did_key_x25519 = "did:key:z6LSotGbgPCJD2Y6TSvvgxERLTfVZxCh9KSrez3WNrNp7vKW".to_string();
    let did_key_secp256k1 = did_key_from_jwk(jwk_secp256k1());
    let did_key_p256 = did_key_from_jwk(jwk_p256());
    let did_key_p384 = did_key_from_jwk(jwk_p384());

    let did_jwk_okp = did_jwk_from_json(json!({
        "kty": "OKP",
        "crv": "Ed25519",
        "x": "VCpo2LMLhn6iWku8MKvSLg2ZAoC-nlOyPVQaO3FxVeQ"
    }));
    let did_jwk_p256 = did_jwk_from_json(json!({
        "kty": "EC",
        "crv": "P-256",
        "x": "g3fsv1xpWPH099LIUn_zJoOF5Ur8xobyzZwX9m_dJ4E",
        "y": "9304UAFl55xQMfrnB-zKEjjXEC4OFWSuYnr7W6hdkVA"
    }));
    let did_jwk_rsa = did_jwk_from_json(json!({
        "kty": "RSA",
        "n": "sXch4M4FhV6d3iD4n1x4Y6w8sMtvwlHGhEq-y3OCAXoTr4Wr9PXgC7vRl6VwB3p6k9RdtqvOB0fOkH1ZZ1xd6Q",
        "e": "AQAB"
    }));

    vec![
        Scenario {
            id: "did-key-ed25519-resolve",
            operation: "resolve",
            input: did_key_ed25519.clone(),
        },
        Scenario {
            id: "did-key-ed25519-representation",
            operation: "resolveRepresentation",
            input: did_key_ed25519.clone(),
        },
        Scenario {
            id: "did-key-ed25519-dereference",
            operation: "dereference",
            input: format!(
                "{did_key_ed25519}#{}",
                did_key_ed25519.trim_start_matches("did:key:")
            ),
        },
        Scenario {
            id: "did-key-x25519-resolve",
            operation: "resolve",
            input: did_key_x25519.clone(),
        },
        Scenario {
            id: "did-key-secp256k1-resolve",
            operation: "resolve",
            input: did_key_secp256k1.clone(),
        },
        Scenario {
            id: "did-key-p256-resolve",
            operation: "resolve",
            input: did_key_p256.clone(),
        },
        Scenario {
            id: "did-key-p384-resolve",
            operation: "resolve",
            input: did_key_p384.clone(),
        },
        Scenario {
            id: "did-jwk-okp-resolve",
            operation: "resolve",
            input: did_jwk_okp.clone(),
        },
        Scenario {
            id: "did-jwk-okp-representation",
            operation: "resolveRepresentation",
            input: did_jwk_okp.clone(),
        },
        Scenario {
            id: "did-jwk-okp-dereference",
            operation: "dereference",
            input: format!("{did_jwk_okp}#0"),
        },
        Scenario {
            id: "did-jwk-p256-resolve",
            operation: "resolve",
            input: did_jwk_p256,
        },
        Scenario {
            id: "did-jwk-rsa-resolve",
            operation: "resolve",
            input: did_jwk_rsa,
        },
        Scenario {
            id: "did-web-root-resolve",
            operation: "resolve",
            input: format!("did:web:localhost%3A{DID_WEB_PORT}"),
        },
        Scenario {
            id: "did-web-root-representation",
            operation: "resolveRepresentation",
            input: format!("did:web:localhost%3A{DID_WEB_PORT}"),
        },
        Scenario {
            id: "did-web-root-dereference",
            operation: "dereference",
            input: format!("did:web:localhost%3A{DID_WEB_PORT}#key-1"),
        },
        Scenario {
            id: "did-web-path-resolve",
            operation: "resolve",
            input: format!("did:web:localhost%3A{DID_WEB_PORT}:user:alice"),
        },
        Scenario {
            id: "did-web-path-dereference",
            operation: "dereference",
            input: format!("did:web:localhost%3A{DID_WEB_PORT}:user:alice#key-1"),
        },
    ]
}

async fn record(
    resolver: &AnyDidMethod,
    scenario: &Scenario,
) -> Result<Value, Box<dyn std::error::Error>> {
    match scenario.operation {
        "resolve" => {
            let did = DIDBuf::from_string(scenario.input.clone())?;
            let output = resolver.resolve(did.as_did()).await?;
            let did_document = serde_json::to_value(output.document)?;

            Ok(json!({
                "id": scenario.id,
                "operation": scenario.operation,
                "input": scenario.input,
                "provenance": provenance(),
                "expected": {
                    "didDocument": did_document,
                    "didDocumentMetadata": output.document_metadata,
                    "didResolutionMetadata": normalize_resolution_metadata(&output.metadata)
                }
            }))
        }
        "resolveRepresentation" => {
            let did = DIDBuf::from_string(scenario.input.clone())?;
            let output = resolver
                .resolve_representation(did.as_did(), ssi_dids::resolution::Options::default())
                .await?;
            let content_stream: Value = serde_json::from_slice(&output.document)?;

            Ok(json!({
                "id": scenario.id,
                "operation": scenario.operation,
                "input": scenario.input,
                "provenance": provenance(),
                "expected": {
                    "contentType": output.metadata.content_type,
                    "contentStream": content_stream,
                    "didDocumentMetadata": output.document_metadata,
                    "didResolutionMetadata": normalize_resolution_metadata(&output.metadata)
                }
            }))
        }
        "dereference" => {
            let did_url = DIDURLBuf::from_string(scenario.input.clone())?;
            let output = resolver.dereference(did_url.as_did_url()).await?;
            let content_stream = normalize_dereferenced_content(output.content);

            Ok(json!({
                "id": scenario.id,
                "operation": scenario.operation,
                "input": scenario.input,
                "provenance": provenance(),
                "expected": {
                    "contentStream": content_stream,
                    "contentMetadata": output.content_metadata,
                    "dereferencingMetadata": normalize_resolution_metadata(&output.metadata)
                }
            }))
        }
        other => Err(format!("unsupported operation: {other}").into()),
    }
}

fn normalize_resolution_metadata(metadata: &impl Serialize) -> Value {
    let mut value = serde_json::to_value(metadata).unwrap_or_else(|_| json!({}));

    if let Some(object) = value.as_object_mut() {
        object.remove("error");
        if object.get("contentType").is_none() {
            object.insert("contentType".to_string(), json!("application/did+json"));
        }
    }

    value
}

fn normalize_dereferenced_content(content: Content) -> Value {
    match content {
        Content::Null => Value::Null,
        Content::Url(url) => Value::String(url.to_string()),
        Content::Resource(resource) => serde_json::to_value(resource).unwrap_or(Value::Null),
    }
}

fn package_versions() -> Value {
    json!({
        "ssi-dids": "0.5.0",
        "ssi-jwk": "0.4.0"
    })
}

fn provenance() -> Value {
    json!({
        "sourcePackage": "ssi-dids",
        "sourceUrl": "https://crates.io/crates/ssi-dids/0.5.0"
    })
}

fn did_jwk_from_json(value: Value) -> String {
    let json = serde_json::to_string(&value).unwrap();
    format!("did:jwk:{}", base64_url::encode(&json.as_bytes()))
}

fn did_key_from_jwk(jwk: JWK) -> String {
    ssi_dids::DIDKey::generate(&jwk).unwrap().to_string()
}

fn jwk_secp256k1() -> JWK {
    serde_json::from_value(json!({
        "kty": "EC",
        "crv": "secp256k1",
        "x": "yclqMZ0MtyVkKm1eBh2AyaUtsqT0l5RJM3g4SzRT96A",
        "y": "yQzUwKnftWCJPGs-faGaHiYi1sxA6fGJVw2Px_LCNe8"
    }))
    .unwrap()
}

fn jwk_p256() -> JWK {
    serde_json::from_value(json!({
        "kty": "EC",
        "crv": "P-256",
        "x": "OnI8cxizlWZUBw5icIHEUn5EVMpcz4bNr__HnrmYGrE",
        "y": "IB3NJQlX9rCu0yyAYSm0k-Vk1NlNkkEcRUZLwZHnuGc"
    }))
    .unwrap()
}

fn jwk_p384() -> JWK {
    serde_json::from_value(json!({
        "kty": "EC",
        "crv": "P-384",
        "x": "G09OCsHnoen7IWnA9ETEKl7NmPwakpHo9KOH5bUB2nJzyn5Zco-qqBchqUi1-uaz",
        "y": "_CtCA3SUZS4IEOJN999aLTEIQOOWOX9biXqbFs4OCa1OMvjoVzzC2BimVnHrrcQ7"
    }))
    .unwrap()
}

fn write_json(path: &Path, value: &impl Serialize) -> Result<(), Box<dyn std::error::Error>> {
    let json = serde_json::to_string_pretty(value)?;
    fs::write(path, format!("{json}\n"))?;
    Ok(())
}

async fn with_did_web_server<F, Fut>(f: F) -> Result<(), Box<dyn std::error::Error>>
where
    F: FnOnce() -> Fut,
    Fut: std::future::Future<Output = Result<(), Box<dyn std::error::Error>>>,
{
    let listener = TcpListener::bind(("127.0.0.1", DID_WEB_PORT)).await?;
    let server: JoinHandle<Result<(), std::io::Error>> = tokio::spawn(async move {
        loop {
            let (mut stream, _) = listener.accept().await?;
            let mut buffer = vec![0u8; 4096];
            let bytes_read = stream.read(&mut buffer).await?;
            let request = String::from_utf8_lossy(&buffer[..bytes_read]);
            let path = request
                .lines()
                .next()
                .and_then(|line| line.split_whitespace().nth(1))
                .unwrap_or("/");

            let response = if let Some(body) = did_web_document(path) {
                format!(
                    "HTTP/1.1 200 OK\r\nContent-Type: application/did+ld+json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{}",
                    body.len(),
                    body
                )
            } else {
                "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                    .to_string()
            };

            stream.write_all(response.as_bytes()).await?;
            stream.flush().await?;
        }

        #[allow(unreachable_code)]
        Ok::<(), std::io::Error>(())
    });

    let result = f().await;
    server.abort();
    result
}

fn did_web_document(path: &str) -> Option<String> {
    let did = match path {
        "/.well-known/did.json" => format!("did:web:localhost%3A{DID_WEB_PORT}"),
        "/user/alice/did.json" => format!("did:web:localhost%3A{DID_WEB_PORT}:user:alice"),
        _ => return None,
    };

    let method_id = format!("{did}#key-1");

    Some(
        serde_json::to_string(&json!({
            "@context": ["https://www.w3.org/ns/did/v1"],
            "id": did,
            "verificationMethod": [
                {
                    "id": method_id,
                    "type": "JsonWebKey2020",
                    "controller": did,
                    "publicKeyJwk": {
                        "kty": "OKP",
                        "crv": "Ed25519",
                        "x": "VCpo2LMLhn6iWku8MKvSLg2ZAoC-nlOyPVQaO3FxVeQ"
                    }
                }
            ],
            "authentication": [method_id],
            "assertionMethod": [method_id],
            "capabilityInvocation": [method_id],
            "capabilityDelegation": [method_id]
        }))
        .unwrap(),
    )
}

mod base64_url {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

    pub fn encode(bytes: &[u8]) -> String {
        let mut output = String::new();
        let mut i = 0;

        while i + 3 <= bytes.len() {
            let chunk =
                ((bytes[i] as u32) << 16) | ((bytes[i + 1] as u32) << 8) | bytes[i + 2] as u32;
            output.push(TABLE[((chunk >> 18) & 0x3F) as usize] as char);
            output.push(TABLE[((chunk >> 12) & 0x3F) as usize] as char);
            output.push(TABLE[((chunk >> 6) & 0x3F) as usize] as char);
            output.push(TABLE[(chunk & 0x3F) as usize] as char);
            i += 3;
        }

        match bytes.len() - i {
            1 => {
                let chunk = (bytes[i] as u32) << 16;
                output.push(TABLE[((chunk >> 18) & 0x3F) as usize] as char);
                output.push(TABLE[((chunk >> 12) & 0x3F) as usize] as char);
            }
            2 => {
                let chunk = ((bytes[i] as u32) << 16) | ((bytes[i + 1] as u32) << 8);
                output.push(TABLE[((chunk >> 18) & 0x3F) as usize] as char);
                output.push(TABLE[((chunk >> 12) & 0x3F) as usize] as char);
                output.push(TABLE[((chunk >> 6) & 0x3F) as usize] as char);
            }
            _ => {}
        }

        output
    }
}
