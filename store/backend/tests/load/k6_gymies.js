/**
 * Gymies — k6 Load Test Script
 * ─────────────────────────────
 * Test de belangrijkste API endpoints onder belasting.
 *
 * Installeer k6:
 *   brew install k6          (macOS)
 *   sudo apt install k6      (Ubuntu)
 *
 * Gebruik:
 *   k6 run tests/load/k6_gymies.js
 *   k6 run --vus 50 --duration 2m tests/load/k6_gymies.js
 *   k6 run --env BASE_URL=https://gymies.nl/api/gymies tests/load/k6_gymies.js
 *
 * Omgevingsvariabelen:
 *   BASE_URL      — API base URL (default: https://gymies.nl/api/gymies)
 *   AUTH_TOKEN     — Bearer token voor authenticated endpoints
 *   TRAINER_TOKEN  — Bearer token voor trainer endpoints
 */

import http from 'k6/http';
import { check, group, sleep } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';

// ── Custom metrics ───────────────────────────────────────────────────

const errorRate   = new Rate('gymies_errors');
const p95Latency  = new Trend('gymies_p95_latency', true);
const reqCount    = new Counter('gymies_requests');

// ── Configuration ────────────────────────────────────────────────────

const BASE_URL      = __ENV.BASE_URL      || 'https://gymies.nl/api/gymies';
const AUTH_TOKEN    = __ENV.AUTH_TOKEN     || '';
const TRAINER_TOKEN = __ENV.TRAINER_TOKEN  || '';

// ── Scenarios ────────────────────────────────────────────────────────

export const options = {
    scenarios: {
        // Scenario 1: Publieke endpoints (zoeken, health, flags)
        public_endpoints: {
            executor: 'ramping-vus',
            startVUs: 1,
            stages: [
                { duration: '30s', target: 10 },  // Ramp up
                { duration: '1m',  target: 20 },   // Steady state
                { duration: '30s', target: 50 },   // Peak
                { duration: '30s', target: 0 },    // Ramp down
            ],
            exec: 'publicFlow',
            tags: { scenario: 'public' },
        },
        // Scenario 2: Authenticated user flow
        authenticated_flow: {
            executor: 'ramping-vus',
            startVUs: 0,
            stages: [
                { duration: '30s', target: 5 },
                { duration: '1m',  target: 15 },
                { duration: '30s', target: 30 },
                { duration: '30s', target: 0 },
            ],
            exec: 'authFlow',
            tags: { scenario: 'auth' },
            startTime: '10s', // Start 10s na public
        },
    },
    thresholds: {
        // Performance budgets
        http_req_duration: [
            'p(95)<500',  // 95% van requests onder 500ms
            'p(99)<1500', // 99% onder 1500ms
        ],
        gymies_errors: ['rate<0.05'], // Max 5% error rate
        http_req_failed: ['rate<0.05'],
    },
};

// ── Helper functies ──────────────────────────────────────────────────

function authHeaders(token) {
    return {
        headers: {
            'Authorization': `Bearer ${token}`,
            'Accept': 'application/json',
            'Content-Type': 'application/json',
        },
    };
}

function publicHeaders() {
    return {
        headers: {
            'Accept': 'application/json',
        },
    };
}

function trackResponse(res, name) {
    reqCount.add(1);
    p95Latency.add(res.timings.duration);
    const success = res.status >= 200 && res.status < 400;
    errorRate.add(!success);

    check(res, {
        [`${name} — status OK`]: (r) => r.status >= 200 && r.status < 400,
        [`${name} — onder 500ms`]: (r) => r.timings.duration < 500,
        [`${name} — heeft body`]: (r) => r.body && r.body.length > 0,
    });
}

// ── Scenario 1: Public endpoints ─────────────────────────────────────

export function publicFlow() {
    group('Health Check', () => {
        const res = http.get(`${BASE_URL}/health`, publicHeaders());
        trackResponse(res, 'health');
    });

    sleep(0.5);

    group('App Version', () => {
        const res = http.get(`${BASE_URL}/app-version?version=1.2.1&platform=ios`, publicHeaders());
        trackResponse(res, 'app-version');

        check(res, {
            'app-version bevat min_version': (r) => {
                try { return JSON.parse(r.body).min_version !== undefined; }
                catch { return false; }
            },
        });
    });

    sleep(0.5);

    group('Feature Flags', () => {
        const res = http.get(`${BASE_URL}/feature-flags`, publicHeaders());
        trackResponse(res, 'feature-flags');

        check(res, {
            'feature-flags bevat flags': (r) => {
                try { return JSON.parse(r.body).flags !== undefined; }
                catch { return false; }
            },
        });
    });

    sleep(0.5);

    group('Trainer Search', () => {
        // Zoek trainers (meest gebruikte publieke endpoint)
        const queries = ['amsterdam', 'yoga', 'personal training', 'fitness', 'rotterdam'];
        const q = queries[Math.floor(Math.random() * queries.length)];

        const res = http.get(`${BASE_URL}/search?q=${encodeURIComponent(q)}&limit=10`, publicHeaders());
        trackResponse(res, 'search');
    });

    sleep(1);
}

// ── Scenario 2: Authenticated flow ──────────────────────────────────

export function authFlow() {
    if (!AUTH_TOKEN) {
        // Skip als geen token geconfigureerd
        sleep(2);
        return;
    }

    const opts = authHeaders(AUTH_TOKEN);

    group('My Profile', () => {
        const res = http.get(`${BASE_URL}/me`, opts);
        trackResponse(res, 'me');

        check(res, {
            'profiel bevat geen password': (r) => !r.body.includes('password'),
            'profiel bevat geen iban': (r) => !r.body.includes('iban'),
        });
    });

    sleep(0.5);

    group('My Bookings', () => {
        const res = http.get(`${BASE_URL}/bookings`, opts);
        trackResponse(res, 'bookings');
    });

    sleep(0.5);

    group('Conversations', () => {
        const res = http.get(`${BASE_URL}/conversations`, opts);
        trackResponse(res, 'conversations');
    });

    sleep(0.5);

    group('Notifications', () => {
        const res = http.get(`${BASE_URL}/notifications`, opts);
        trackResponse(res, 'notifications');
    });

    sleep(1);
}

// ── Samenvatting ─────────────────────────────────────────────────────

export function handleSummary(data) {
    const p95 = data.metrics.http_req_duration?.values?.['p(95)'] || 0;
    const p99 = data.metrics.http_req_duration?.values?.['p(99)'] || 0;
    const errRate = data.metrics.gymies_errors?.values?.rate || 0;
    const totalReqs = data.metrics.http_reqs?.values?.count || 0;

    const summary = `
╔══════════════════════════════════════════════════════╗
║              GYMIES Load Test Results                ║
╠══════════════════════════════════════════════════════╣
║  Total Requests:    ${String(totalReqs).padStart(8)}                    ║
║  p95 Latency:       ${String(Math.round(p95)).padStart(8)}ms                  ║
║  p99 Latency:       ${String(Math.round(p99)).padStart(8)}ms                  ║
║  Error Rate:        ${String((errRate * 100).toFixed(2)).padStart(8)}%                  ║
║  Status:            ${p95 < 500 && errRate < 0.05 ? '   ✅ PASS' : '   ❌ FAIL'}                     ║
╚══════════════════════════════════════════════════════╝
`;
    console.log(summary);

    return {
        stdout: summary,
        'tests/load/k6_results.json': JSON.stringify(data, null, 2),
    };
}
