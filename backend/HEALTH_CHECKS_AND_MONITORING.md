# Gymies API Health Checks & Monitoring Guide

## Overview

This document outlines the health check endpoints, performance monitoring, error handling, and cron job management for the Gymies backend API.

## Health Check Endpoints

### 1. Public Health Ping

**Endpoint:** `GET /api/gymies/health`

**Authentication:** None required (public)

**Rate Limit:** 30 requests/minute

**Response (200 OK):**
```json
{
  "status": "ok",
  "timestamp": "2026-05-07T10:30:00Z",
  "database": "connected",
  "version": "1.0"  // only in local/testing
}
```

**Response (503 Service Unavailable):**
```json
{
  "status": "degraded",
  "timestamp": "2026-05-07T10:30:00Z",
  "database": "error"
}
```

**Use Case:** Uptime monitoring, load balancer health checks, status page integration.

### 2. Detailed Status Check

**Endpoint:** `GET /api/gymies/health/status`

**Authentication:** Bearer token required (admin/cyber access)

**Rate Limit:** 30 requests/minute

**Response (200 OK):**
```json
{
  "status": "ok",
  "timestamp": "2026-05-07T10:30:00Z",
  "checks": {
    "database": {
      "ok": true,
      "critical": true,
      "latency_ms": 15,
      "note": null
    },
    "cache": {
      "ok": true,
      "critical": false,
      "driver": "redis"
    },
    "queue": {
      "ok": true,
      "critical": false,
      "pending": 42,
      "failed": 0
    },
    "storage": {
      "ok": true,
      "critical": false,
      "free_mb": 5420,
      "free_percent": 67.5
    },
    "mollie": {
      "ok": true,
      "critical": false,
      "reachable": true,
      "status": 200
    },
    "mail": {
      "ok": true,
      "critical": false,
      "driver": "smtp"
    }
  },
  "check_time_ms": 234,
  "environment": "production",  // only in local/testing
  "version": "1.0"              // only in local/testing
}
```

**Status Codes:**
- `200 OK` - All systems operational
- `207 Multi-Status` - Some non-critical checks failed
- `503 Service Unavailable` - Critical system down (database, Mollie)

**Use Case:** Detailed dashboard, admin alerts, deployment validation.

## Cron Jobs

### Registered Cron Routes

All cron endpoints require `GYMIES_CRON_KEY` environment variable (16+ characters).

Pass key via:
- Query parameter: `?key=YOUR_CRON_KEY`
- Header: `X-Cron-Key: YOUR_CRON_KEY`

**Endpoints:**

```
POST /api/gymies/cron/expire-pending-bookings          (48h timeout)
POST /api/gymies/cron/expire-reserved-bookings         (expired reserves)
POST /api/gymies/cron/booking-reminders                (24h before session)
POST /api/gymies/cron/auto-complete-sessions           (24h after completion)
POST /api/gymies/cron/refresh-pro-client-health        (trainer analytics)
POST /api/gymies/cron/subscription-reminders           (trial/payment expiry)
POST /api/gymies/cron/availability-check               (trainer inactivity, 30 days)
POST /api/gymies/cron/process-notification-emails      (email batch processor)
POST /api/gymies/cron/recalculate-quality-scores       (trainer rating recalc)
POST /api/gymies/cron/run-all                          (master runner)
```

### Scheduling Recommendations

```bash
# Every minute
*/1 * * * * curl -X POST https://api.example.com/api/gymies/cron/expire-reserved-bookings?key=$CRON_KEY

# Every hour
0 * * * * curl -X POST https://api.example.com/api/gymies/cron/booking-reminders?key=$CRON_KEY

# Daily
0 6 * * * curl -X POST https://api.example.com/api/gymies/cron/auto-pilot-retention?key=$CRON_KEY
0 9 * * * curl -X POST https://api.example.com/api/gymies/cron/availability-check?key=$CRON_KEY

# Weekly (Monday 01:00 UTC)
0 1 * * 1 curl -X POST https://api.example.com/api/gymies/cron/recalculate-quality-scores?key=$CRON_KEY

# Master cron (runs multiple jobs)
*/5 * * * * curl -X POST https://api.example.com/api/gymies/cron/run-all?key=$CRON_KEY
```

## Performance Monitoring

### Request Timing Headers (Development/Testing)

When `APP_ENV` is `local` or `testing`, responses include:

```
X-Response-Time-Ms: 234
X-Db-Query-Count: 12
```

### Slow Request Logging

Requests exceeding `GYMIES_SLOW_REQUEST_THRESHOLD_MS` (default 1000ms) are logged to `storage/logs/performance.log`.

Configure via environment:
```bash
GYMIES_SLOW_REQUEST_THRESHOLD_MS=1000  # default
GYMIES_LOG_QUERIES=true                # enable query logging
GYMIES_QUERY_THRESHOLD_MS=500          # slow query threshold
```

### Performance Log Table

Requests are stored in `gymies_performance_logs` table with:
- HTTP method & path
- Status code & duration
- Query count
- User ID
- Timestamp

**Query:**
```sql
SELECT * FROM gymies_performance_logs
WHERE duration_ms > 5000
ORDER BY created_at DESC
LIMIT 100;
```

### Query Log Table

Slow queries (>500ms by default) are stored in `gymies_slow_queries`:
- SQL statement (truncated)
- Query bindings
- Duration in ms
- Database connection

**Query:**
```sql
SELECT sql, duration_ms, created_at
FROM gymies_slow_queries
WHERE duration_ms > 1000
ORDER BY duration_ms DESC
LIMIT 50;
```

## Error Handling

### Error Response Format

**Default (Production):**
```json
{
  "status": "error",
  "message": "An error occurred processing your request.",
  "timestamp": "2026-05-07T10:30:00Z"
}
```

**Development/Testing:**
```json
{
  "status": "error",
  "message": "SQLSTATE[HY000]: General error: 1030 Got error...",
  "timestamp": "2026-05-07T10:30:00Z",
  "trace": {
    "file": "/app/backend/Controllers/MyController.php",
    "line": 123,
    "class": "PDOException"
  },
  "full_trace": "..."  // only if APP_DEBUG=true
}
```

### Error Logging

All errors are logged to:
1. **Laravel logs** (`storage/logs/laravel.log`)
2. **Database** (`gymies_api_error_logs` table)
3. **Sentry** (if configured, for errors ≥500 or requests >5s)

**Redaction:** Passwords, tokens, IBANs, and emails are automatically redacted.

### Sentry Integration

For critical error tracking, configure in `.env`:

```bash
SENTRY_LARAVEL_DSN=https://your-sentry-key@sentry.io/project-id
SENTRY_ENVIRONMENT=production
```

Errors are sent to Sentry if:
- Status code ≥ 500, OR
- Request duration > 5000ms

## Middleware Configuration

### Required Middleware

Add to `config/app.php` or `routes/web.php`:

```php
// In middleware aliases or route groups:
'gymies.performance' => \App\Http\Middleware\GymiesPerformanceMiddleware::class,
'gymies.error_log' => \App\Http\Middleware\GymiesErrorHandlerMiddleware::class,
'gymies.rate.limit' => \App\Http\Middleware\GymiesRateLimitMiddleware::class,
```

### Rate Limiting Profiles

```php
// login:    5 per minute, block 10 min
// register: 4 per 5 min, block 15 min
// health:   30 per minute (lenient)
// cron:     10 per minute, block 2 min
// api:      120 per minute (default)
```

## Database Tables

Run the migration to create monitoring tables:

```bash
mysql < backend/migrations/create_monitoring_tables.sql
```

**Tables:**
- `gymies_performance_logs` - Request timing
- `gymies_slow_queries` - Slow query tracking
- `gymies_cron_logs` - Cron execution history
- `gymies_health_check_history` - Health check timeline
- `gymies_api_error_logs` - Error tracking

## Monitoring Dashboard

### Key Metrics to Track

1. **Health Check Status** - `/api/gymies/health`
   - Response time
   - Component status (database, cache, queue, etc.)

2. **Performance** - Top slow requests
   ```sql
   SELECT method, path, AVG(duration_ms) as avg_time, COUNT(*) as count
   FROM gymies_performance_logs
   GROUP BY method, path
   ORDER BY avg_time DESC
   LIMIT 20;
   ```

3. **Slow Queries** - Most expensive queries
   ```sql
   SELECT sql, AVG(duration_ms) as avg_time, COUNT(*) as count
   FROM gymies_slow_queries
   GROUP BY SUBSTRING(sql, 1, 100)
   ORDER BY avg_time DESC
   LIMIT 20;
   ```

4. **Error Rate** - API errors over time
   ```sql
   SELECT DATE(created_at) as date, COUNT(*) as errors
   FROM gymies_api_error_logs
   GROUP BY DATE(created_at)
   ORDER BY date DESC;
   ```

5. **Cron Job Success** - Cron execution tracking
   ```sql
   SELECT job_name, status, COUNT(*) as count
   FROM gymies_cron_logs
   WHERE created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)
   GROUP BY job_name, status;
   ```

## Alerting

### Recommended Alerts

1. **Health Check Failed** - Status != ok
2. **High Error Rate** - >1% of requests returning 5xx
3. **Slow Requests** - >10 requests/hour taking >5s
4. **Slow Queries** - >20 queries/hour taking >2s
5. **Cron Job Failed** - job_status = 'failed'
6. **Low Disk Space** - storage check returns free_mb < 200
7. **Queue Backup** - pending jobs > 1000

## Environment Variables

```bash
# Health & Monitoring
GYMIES_SLOW_REQUEST_THRESHOLD_MS=1000
GYMIES_QUERY_THRESHOLD_MS=500
GYMIES_LOG_QUERIES=true

# Cron Security
GYMIES_CRON_KEY=your_secure_random_key_16plus_chars

# Error Tracking
SENTRY_LARAVEL_DSN=https://key@sentry.io/project-id
SENTRY_ENVIRONMENT=production
```

## Troubleshooting

### Health check returns 503

1. Check database connectivity: `mysql -h host -u user -p database`
2. Check Redis/Cache: `redis-cli ping`
3. Check Mollie API: `curl https://api.mollie.com/v2/methods`
4. Check mail config: Verify SMTP settings

### Cron jobs not running

1. Verify `GYMIES_CRON_KEY` is set (16+ chars)
2. Check cron server clock sync
3. Check cron logs: `tail -f storage/logs/laravel.log | grep cron`
4. Verify endpoint is accessible: `curl -X POST http://localhost/api/gymies/cron/ping`

### Slow requests in production

1. Check `GYMIES_SLOW_REQUEST_THRESHOLD_MS` setting
2. Review slow query logs
3. Check database indexes
4. Monitor memory usage
5. Review recent code changes

## References

- [Health Endpoints](#health-check-endpoints)
- [Cron Jobs](#cron-jobs)
- [Performance Monitoring](#performance-monitoring)
- [Error Handling](#error-handling)
- [Middleware](#middleware-configuration)
