import fs from 'node:fs/promises';
import https from 'node:https';
import os from 'node:os';
import path from 'node:path';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const fixturesRoot = path.resolve(__dirname, '../../test/fixtures/upstream');
const didWebPort = 57432;

process.env.NODE_TLS_REJECT_UNAUTHORIZED = '0';

const scenarios = [
  {
    id: 'did-key-ed25519-resolve',
    method: 'key',
    operation: 'resolve',
    input: 'did:key:z6MknCCLeeHBUaHu4aHSVLDCYQW9gjVJ7a63FpMvtuVMy53T'
  },
  {
    id: 'did-key-ed25519-representation',
    method: 'key',
    operation: 'resolveRepresentation',
    input: 'did:key:z6MknCCLeeHBUaHu4aHSVLDCYQW9gjVJ7a63FpMvtuVMy53T'
  },
  {
    id: 'did-key-ed25519-dereference',
    method: 'key',
    operation: 'dereference',
    input: 'did:key:z6MknCCLeeHBUaHu4aHSVLDCYQW9gjVJ7a63FpMvtuVMy53T#z6MknCCLeeHBUaHu4aHSVLDCYQW9gjVJ7a63FpMvtuVMy53T'
  },
  {
    id: 'did-key-x25519-resolve',
    method: 'key',
    operation: 'resolve',
    input: 'did:key:z6LSotGbgPCJD2Y6TSvvgxERLTfVZxCh9KSrez3WNrNp7vKW'
  },
  {
    id: 'did-jwk-okp-resolve',
    method: 'jwk',
    operation: 'resolve',
    input:
      'did:jwk:eyJrdHkiOiJPS1AiLCJjcnYiOiJFZDI1NTE5IiwieCI6IlZDcG8yTE1MaG42aVdrdThNS3ZTTGcyWkFvQy1ubE95UFZRYU8zRnhWZVEifQ'
  },
  {
    id: 'did-jwk-okp-representation',
    method: 'jwk',
    operation: 'resolveRepresentation',
    input:
      'did:jwk:eyJrdHkiOiJPS1AiLCJjcnYiOiJFZDI1NTE5IiwieCI6IlZDcG8yTE1MaG42aVdrdThNS3ZTTGcyWkFvQy1ubE95UFZRYU8zRnhWZVEifQ'
  },
  {
    id: 'did-jwk-okp-dereference',
    method: 'jwk',
    operation: 'dereference',
    input:
      'did:jwk:eyJrdHkiOiJPS1AiLCJjcnYiOiJFZDI1NTE5IiwieCI6IlZDcG8yTE1MaG42aVdrdThNS3ZTTGcyWkFvQy1ubE95UFZRYU8zRnhWZVEifQ#0'
  },
  {
    id: 'did-jwk-rsa-resolve',
    method: 'jwk',
    operation: 'resolve',
    input:
      'did:jwk:eyJrdHkiOiJSU0EiLCJuIjoic1hjaDRNNEZoVjZkM2lENG4xeDRZNnc4c010dndsSEdoRXEteTNPQ0FYb1RyNFdyOVBYZ0M3dlJsNlZ3QjNwNms5UmR0cXZPQjBmT2tIMVpaMXhkNlEiLCJlIjoiQVFBQiJ9'
  },
  {
    id: 'did-web-root-resolve',
    method: 'web',
    operation: 'resolve',
    input: ({port}) => `did:web:localhost%3A${port}`
  },
  {
    id: 'did-web-root-representation',
    method: 'web',
    operation: 'resolveRepresentation',
    input: ({port}) => `did:web:localhost%3A${port}`
  },
  {
    id: 'did-web-root-dereference',
    method: 'web',
    operation: 'dereference',
    input: ({port}) => `did:web:localhost%3A${port}#key-1`
  },
  {
    id: 'did-web-path-resolve',
    method: 'web',
    operation: 'resolve',
    input: ({port}) => `did:web:localhost%3A${port}:user:alice`
  },
  {
    id: 'did-web-path-dereference',
    method: 'web',
    operation: 'dereference',
    input: ({port}) => `did:web:localhost%3A${port}:user:alice#key-1`
  }
];

const webDocuments = {
  '/.well-known/did.json': {
    '@context': ['https://www.w3.org/ns/did/v1'],
    id: null,
    verificationMethod: [
      {
        id: null,
        type: 'JsonWebKey2020',
        controller: null,
        publicKeyJwk: {
          kty: 'OKP',
          crv: 'Ed25519',
          x: 'VCpo2LMLhn6iWku8MKvSLg2ZAoC-nlOyPVQaO3FxVeQ'
        }
      }
    ],
    authentication: [null],
    assertionMethod: [null],
    capabilityInvocation: [null],
    capabilityDelegation: [null]
  },
  '/user/alice/did.json': {
    '@context': ['https://www.w3.org/ns/did/v1'],
    id: null,
    verificationMethod: [
      {
        id: null,
        type: 'JsonWebKey2020',
        controller: null,
        publicKeyJwk: {
          kty: 'OKP',
          crv: 'Ed25519',
          x: 'VCpo2LMLhn6iWku8MKvSLg2ZAoC-nlOyPVQaO3FxVeQ'
        }
      }
    ],
    authentication: [null],
    assertionMethod: [null]
  }
};

async function main() {
  const channel = process.argv[2] ?? 'released';

  if (!['released', 'main'].includes(channel)) {
    throw new Error(`unsupported channel: ${channel}`);
  }

  const withServer = await createDidWebServer();

  await withServer(async context => {
    const recorder = await buildRecorder();
    const channelDir = path.join(fixturesRoot, channel);

    await fs.rm(path.join(channelDir, 'cases'), {recursive: true, force: true});
    await fs.mkdir(path.join(channelDir, 'cases'), {recursive: true});

    const cases = [];

    for (const scenario of scenarios) {
      const input = typeof scenario.input === 'function' ? scenario.input(context) : scenario.input;
      const result = await recorder.record({...scenario, input});
      const file = `${scenario.id}.json`;
      await fs.writeFile(
        path.join(channelDir, 'cases', file),
        JSON.stringify(result, null, 2) + '\n'
      );

      cases.push({
        id: scenario.id,
        operation: scenario.operation,
        input,
        file
      });
    }

    const manifest = {
      schemaVersion: 1,
      advisory: channel === 'main',
      channel,
      generatedAt: new Date().toISOString(),
      recorder: {
        name: 'ex_did_upstream_parity',
        packageManager: 'pnpm'
      },
      packages: await recorder.packages(),
      cases
    };

    await fs.writeFile(
      path.join(channelDir, 'manifest.json'),
      JSON.stringify(manifest, null, 2) + '\n'
    );
  });
}

async function buildRecorder() {
  const [
    {Resolver},
    webDidResolver,
    didKey,
    didJwk,
    didWeb,
    {Ed25519VerificationKey2020},
    {X25519KeyAgreementKey2020}
  ] = await Promise.all([
    import('did-resolver'),
    import('web-did-resolver'),
    import('@digitalbazaar/did-method-key'),
    import('@digitalbazaar/did-method-jwk'),
    import('@digitalbazaar/did-method-web'),
    import('@digitalbazaar/ed25519-verification-key-2020'),
    import('@digitalbazaar/x25519-key-agreement-key-2020')
  ]);

  const webResolver = new Resolver(webDidResolver.getResolver());

  const keyDriver =
    typeof didKey.driver === 'function'
      ? didKey.driver()
      : typeof didKey.default?.driver === 'function'
        ? didKey.default.driver()
        : null;

  if(keyDriver?.use) {
    keyDriver.use({
      multibaseMultikeyHeader: 'z6Mk',
      fromMultibase: Ed25519VerificationKey2020.from
    });

    keyDriver.use({
      multibaseMultikeyHeader: 'z6LS',
      fromMultibase: X25519KeyAgreementKey2020.from
    });
  }

  const jwkDriver =
    typeof didJwk.driver === 'function'
      ? didJwk.driver()
      : typeof didJwk.default?.driver === 'function'
        ? didJwk.default.driver()
        : null;

  const webDriver =
    typeof didWeb.driver === 'function'
      ? didWeb.driver()
      : typeof didWeb.default?.driver === 'function'
        ? didWeb.default.driver()
        : null;

  return {
    async record(scenario) {
      switch (scenario.method) {
        case 'key':
          return recordWithDriver(scenario, keyDriver, '@digitalbazaar/did-method-key');
        case 'jwk':
          return recordWithDriver(scenario, jwkDriver, '@digitalbazaar/did-method-jwk');
        case 'web':
          return recordDidWeb(scenario, webResolver, webDriver);
        default:
          throw new Error(`unsupported method: ${scenario.method}`);
      }
    },
    async packages() {
      const packageJson = JSON.parse(
        await fs.readFile(path.join(__dirname, 'package.json'), 'utf8')
      );

      return packageJson.dependencies;
    }
  };
}

async function recordWithDriver(scenario, driver, sourcePackage) {
  if (!driver || typeof driver.get !== 'function') {
    throw new Error(`${sourcePackage} does not expose a usable driver.get API`);
  }

  switch (scenario.operation) {
    case 'resolve': {
      const didDocument = await driver.get({did: scenario.input});

      return {
        id: scenario.id,
        operation: scenario.operation,
        input: scenario.input,
        provenance: {
          sourcePackage,
          sourceUrl: packageUrl(sourcePackage)
        },
        expected: {
          didDocument,
          didDocumentMetadata: {'source': 'local'},
          didResolutionMetadata: {'contentType': 'application/did+json'}
        }
      };
    }

    case 'resolveRepresentation': {
      const didDocument = await driver.get({did: scenario.input});

      return {
        id: scenario.id,
        operation: scenario.operation,
        input: scenario.input,
        provenance: {
          sourcePackage,
          sourceUrl: packageUrl(sourcePackage)
        },
        expected: {
          contentType: 'application/did+json',
          contentStream: didDocument,
          didDocumentMetadata: {'source': 'local'},
          didResolutionMetadata: {'contentType': 'application/did+json'}
        }
      };
    }

    case 'dereference': {
      const contentStream = await driver.get({url: scenario.input});

      return {
        id: scenario.id,
        operation: scenario.operation,
        input: scenario.input,
        provenance: {
          sourcePackage,
          sourceUrl: packageUrl(sourcePackage)
        },
        expected: {
          contentStream,
          contentMetadata: {
            did_document: scenario.input.split('#')[0]
          },
          dereferencingMetadata: {
            contentType: 'application/did+json'
          }
        }
      };
    }

    default:
      throw new Error(`unsupported operation: ${scenario.operation}`);
  }
}

async function recordDidWeb(scenario, resolver, driver) {
  switch (scenario.operation) {
    case 'resolve': {
      const resolved = await resolver.resolve(scenario.input);
      const didDocument =
        resolved.didDocument ?? resolved.didDocumentStream ?? resolved.didDocumentMetadata?.document;

      return {
        id: scenario.id,
        operation: scenario.operation,
        input: scenario.input,
        provenance: {
          sourcePackage: 'web-did-resolver',
          sourceUrl: packageUrl('web-did-resolver')
        },
        expected: {
          didDocument,
          didDocumentMetadata: {
            sourceUrl: didWebSourceUrl(scenario.input)
          },
          didResolutionMetadata: normalizeDidResolverMetadata(resolved.didResolutionMetadata)
        }
      };
    }

    case 'resolveRepresentation': {
      const resolved = await resolver.resolve(scenario.input);
      const didDocument =
        resolved.didDocument ?? resolved.didDocumentStream ?? resolved.didDocumentMetadata?.document;
      const contentType = resolved.didResolutionMetadata?.contentType ?? inferContentType(didDocument);

      return {
        id: scenario.id,
        operation: scenario.operation,
        input: scenario.input,
        provenance: {
          sourcePackage: 'web-did-resolver',
          sourceUrl: packageUrl('web-did-resolver')
        },
        expected: {
          contentType,
          contentStream: didDocument,
          didDocumentMetadata: {
            sourceUrl: didWebSourceUrl(scenario.input)
          },
          didResolutionMetadata: normalizeDidResolverMetadata(resolved.didResolutionMetadata)
        }
      };
    }

    case 'dereference': {
      if (!driver || typeof driver.get !== 'function') {
        throw new Error('@digitalbazaar/did-method-web does not expose a usable driver.get API');
      }

      const contentStream = await driver.get({url: scenario.input});

      return {
        id: scenario.id,
        operation: scenario.operation,
        input: scenario.input,
        provenance: {
          sourcePackage: '@digitalbazaar/did-method-web',
          sourceUrl: packageUrl('@digitalbazaar/did-method-web')
        },
        expected: {
          contentStream,
          contentMetadata: {
            did_document: scenario.input.split('#')[0]
          },
          dereferencingMetadata: {
            contentType: inferContentType(contentStream)
          }
        }
      };
    }

    default:
      throw new Error(`unsupported operation: ${scenario.operation}`);
  }
}

function normalizeDidResolverMetadata(metadata = {}) {
  const normalized = {};

  for (const [key, value] of Object.entries(metadata)) {
    if (key === 'retrieved' || key === 'duration') {
      continue;
    }

    normalized[key] = value;
  }

  return normalized;
}

function inferContentType(value) {
  if (value && typeof value === 'object' && '@context' in value) {
    return 'application/did+ld+json';
  }

  if (value && typeof value === 'object') {
    return 'application/did+json';
  }

  return 'text/plain';
}

function packageUrl(name) {
  return `https://www.npmjs.com/package/${name}`;
}

function didWebSourceUrl(did) {
  const [, , host, ...pathSegments] = did.split(':');
  const decodedHost = decodeURIComponent(host);

  if (pathSegments.length === 0) {
    return `https://${decodedHost}/.well-known/did.json`;
  }

  return `https://${decodedHost}/${pathSegments.map(decodeURIComponent).join('/')}/did.json`;
}

async function createDidWebServer() {
  const {key, cert, cleanup} = await createSelfSignedCertificate();

  const server = https.createServer({key, cert}, (req, res) => {
    const pathName = req.url?.split('?')[0] ?? '/';
    const template = webDocuments[pathName];

    if(!template) {
      res.writeHead(404, {'content-type': 'application/json'});
      res.end(JSON.stringify({error: 'not_found'}));
      return;
    }

    const did =
      pathName === '/.well-known/did.json' ? currentDidWebDid(req) : currentDidWebPathDid(req);

    const document = hydrateDidWebDocument(template, did);

    res.writeHead(200, {'content-type': 'application/did+ld+json'});
    res.end(JSON.stringify(document));
  });

  await new Promise((resolve, reject) => {
    server.listen(didWebPort, '127.0.0.1', error => {
      if(error) {
        reject(error);
        return;
      }

      resolve();
    });
  });

  const {port} = server.address();

  return async callback => {
    try {
      await callback({port});
    } finally {
      await new Promise((resolve, reject) => {
        server.close(error => {
          if(error) {
            reject(error);
            return;
          }

          resolve();
        });
      });

      await cleanup();
    }
  };
}

function currentDidWebDid(req) {
  const port = req.socket.localPort;
  return `did:web:localhost%3A${port}`;
}

function currentDidWebPathDid(req) {
  const port = req.socket.localPort;
  return `did:web:localhost%3A${port}:user:alice`;
}

function hydrateDidWebDocument(template, did) {
  const verificationMethodId = `${did}#key-1`;
  const document = structuredClone(template);

  document.id = did;
  document.verificationMethod[0].id = verificationMethodId;
  document.verificationMethod[0].controller = did;

  for(const relationship of [
    'authentication',
    'assertionMethod',
    'capabilityInvocation',
    'capabilityDelegation'
  ]) {
    if(Array.isArray(document[relationship])) {
      document[relationship] = [verificationMethodId];
    }
  }

  return document;
}

async function createSelfSignedCertificate() {
  const tempRoot = await fs.mkdtemp(path.join(os.tmpdir(), 'ex-did-upstream-'));
  const keyPath = path.join(tempRoot, 'localhost.key');
  const certPath = path.join(tempRoot, 'localhost.crt');

  execFileSync(
    'openssl',
    [
      'req',
      '-x509',
      '-newkey',
      'rsa:2048',
      '-nodes',
      '-days',
      '1',
      '-subj',
      '/CN=localhost',
      '-keyout',
      keyPath,
      '-out',
      certPath
    ],
    {stdio: 'ignore'}
  );

  const [key, cert] = await Promise.all([
    fs.readFile(keyPath),
    fs.readFile(certPath)
  ]);

  return {
    key,
    cert,
    cleanup: async () => {
      await fs.rm(tempRoot, {recursive: true, force: true});
    }
  };
}

main().catch(error => {
  console.error(error);
  process.exitCode = 1;
});
