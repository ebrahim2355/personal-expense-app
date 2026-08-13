import request from 'supertest';
import { describe, expect, it } from 'vitest';

import { createApp } from '../src/app.js';

describe('GET /health/live', () => {
  it('returns the liveness response without framework disclosure', async () => {
    const response = await request(createApp()).get('/health/live');

    expect(response.status).toBe(200);
    expect(response.headers['content-type']).toMatch(/^application\/json/);
    expect(response.headers['x-powered-by']).toBeUndefined();
    expect(response.body).toEqual({ status: 'ok' });
  });
});
