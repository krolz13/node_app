const request = require('supertest');
const app = require('../server');

describe('DevOps Status App Integration Tests', () => {
  
  test('GET /api/status should return system status metadata', async () => {
    const res = await request(app).get('/api/status');
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toMatch(/json/);
    expect(res.body).toHaveProperty('status', 'Healthy');
    expect(res.body).toHaveProperty('version');
    expect(res.body).toHaveProperty('hostname');
    expect(res.body).toHaveProperty('cpuCount');
    expect(res.body).toHaveProperty('freeMemory');
    expect(res.body).toHaveProperty('totalMemory');
  });

  test('GET /api/todos should return the milestones array', async () => {
    const res = await request(app).get('/api/todos');
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toMatch(/json/);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBeGreaterThan(0);
    expect(res.body[0]).toHaveProperty('text');
    expect(res.body[0]).toHaveProperty('completed');
  });

  test('GET /about should serve the about page HTML', async () => {
    const res = await request(app).get('/about');
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toMatch(/html/);
  });

  test('GET /random-route should fall back to index.html (Catch-all routing)', async () => {
    const res = await request(app).get('/non-existent-route-random');
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toMatch(/html/);
  });
});
