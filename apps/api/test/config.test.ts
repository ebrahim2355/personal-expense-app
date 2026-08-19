import { describe, expect, it } from 'vitest';

import { loadConfig } from '../src/config/env.js';

/**
 * The minimum a valid environment needs. Every case below starts from this and
 * changes only the variable under test, so a failure names one cause.
 */
const baseEnvironment = {
  NODE_ENV: 'test',
  DATABASE_URL: 'postgresql://unused:unused@localhost:5432/unused',
  JWT_ACCESS_SECRET: 'a'.repeat(32),
  CURSOR_SIGNING_SECRET: 'b'.repeat(32),
} satisfies NodeJS.ProcessEnv;

function encodeServiceAccount(document: unknown): string {
  return Buffer.from(JSON.stringify(document), 'utf8').toString('base64');
}

const validServiceAccount = {
  type: 'service_account',
  project_id: 'household-expenses',
  client_email: 'pusher@household-expenses.iam.gserviceaccount.com',
  private_key: '-----BEGIN PRIVATE KEY-----\nabc\n-----END PRIVATE KEY-----\n',
};

const validEncoded = encodeServiceAccount(validServiceAccount);

function environmentWith(encoded: string): NodeJS.ProcessEnv {
  return { ...baseEnvironment, FIREBASE_SERVICE_ACCOUNT_BASE64: encoded };
}

describe('loadConfig with no Firebase credential', () => {
  it('starts with push disabled rather than refusing to boot', () => {
    const config = loadConfig({ ...baseEnvironment });

    expect(config.firebaseServiceAccount).toBeNull();
  });

  // Render writes an empty string for a `sync: false` variable that was never
  // filled in. That has to mean "not configured" rather than "a credential
  // whose fields are missing", or the API would refuse to start on a fresh
  // Blueprint before anyone had a chance to paste the key in.
  it('treats an empty value as unconfigured', () => {
    const config = loadConfig(environmentWith('   '));

    expect(config.firebaseServiceAccount).toBeNull();
  });
});

describe('loadConfig with a Firebase credential', () => {
  it('exposes the three fields firebase-admin needs', () => {
    const config = loadConfig(environmentWith(validEncoded));

    expect(config.firebaseServiceAccount).toEqual({
      projectId: 'household-expenses',
      clientEmail: 'pusher@household-expenses.iam.gserviceaccount.com',
      privateKey: validServiceAccount.private_key,
    });
  });

  // Base64 of the whole JSON file is what keeps the key usable: the newlines
  // inside it survive the round trip, where pasting raw JSON into a dashboard
  // field mangles them into literal backslash-n and breaks every signature.
  it('preserves the newlines in the private key', () => {
    const config = loadConfig(environmentWith(validEncoded));

    expect(config.firebaseServiceAccount?.privateKey).toContain('\n');
  });

  it('rejects a value that is not base64-encoded JSON', () => {
    expect(() => loadConfig(environmentWith('not-base64-at-all!!'))).toThrow(
      /base64-encoded service account JSON/,
    );
  });

  // Pasting the wrong file is the realistic mistake: google-services.json
  // instead of the service-account key. It is valid JSON and decodes cleanly, so
  // only a field check catches it, and it has to fail at startup rather than at
  // the first send, where the symptom is a notification that never arrived.
  it('rejects JSON that is missing a required field', () => {
    const encoded = encodeServiceAccount({
      type: validServiceAccount.type,
      project_id: validServiceAccount.project_id,
      private_key: validServiceAccount.private_key,
    });

    expect(() => loadConfig(environmentWith(encoded))).toThrow(
      /project_id, client_email, and private_key/,
    );
  });
});
