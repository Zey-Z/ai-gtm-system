# DLQ Operations Manual

## Table of Contents
1. [Daily Monitoring](#daily-monitoring)
2. [Error Handling Procedures](#error-handling-procedures)
3. [Manual Retry](#manual-retry)
4. [Common Troubleshooting](#common-troubleshooting)
5. [SQL Toolkit](#sql-toolkit)

---

## Daily Monitoring

### Daily Health Check

**Recommended time**: Every morning at 9:00 AM

```bash
# Run health check script
docker exec -it ai-gtm-system-postgres-1 psql -U aigtm_user -d aigtm -f /db/dlq-queries.sql
```

**Key metrics to watch**:
- Pending tasks (`status = 'pending'`)
- Permanently failed tasks (`status = 'failed_permanently'`)
- New errors today

**Alert thresholds**:
- Pending tasks > 10: System investigation required
- Permanent failures > 5: Manual intervention needed
- AI errors > 5/day: Check API key or quota

---

## Error Handling Procedures

### 1. After Receiving a Slack Alert

**Steps**:
1. Note the Run ID (from the Slack message)
2. Query DLQ details
3. Identify the error type
4. Take action based on type

**Example**:
```sql
-- Query full trace by Run ID
SELECT * FROM dead_letter_queue WHERE run_id = 'YOUR_RUN_ID';
```

### 2. Error Classification & Response

| Error Type | Action | Priority |
|-----------|--------|----------|
| **validation_error** | Check input source, fix upstream — do not retry | P2 |
| **ai_error** | Check API key/quota, wait for auto-retry or trigger manual retry | P1 |
| **db_error** | Check database connection/config, fix then manual retry | P0 |
| **slack_error** | Check Webhook URL, fix then manual retry | P2 |
| **unknown** | Inspect error_message and payload, analyze case-by-case | P1 |

### 3. Decision Tree

```
Error alert received
    ↓
Check error_type
    ↓
Is it validation_error?
    YES → Mark as failed_permanently (bad input data)
    NO  → Continue
    ↓
Is it ai_error?
    YES → Check API Key → Fix → Manual retry
    NO  → Continue
    ↓
Is it db_error?
    YES → Check database → Fix → Manual retry
    NO  → Continue
    ↓
Is it slack_error?
    YES → Check Webhook URL → Fix → Manual retry
    NO  → Inspect payload, analyze case-by-case
```

---

## Manual Retry

### Method 1: Resend via Webhook (Recommended)

**Applicable to**: All error types

**Steps**:

```bash
# 1. Extract payload from DLQ
docker exec -it ai-gtm-system-postgres-1 psql -U aigtm_user -d aigtm -c "SELECT payload FROM dead_letter_queue WHERE id = YOUR_DLQ_ID;"

# 2. Copy the original input data from the payload
# 3. Resend to webhook
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"lead_text": "original text extracted from payload"}'

# 4. If successful, mark original DLQ record as resolved
docker exec -it ai-gtm-system-postgres-1 psql -U aigtm_user -d aigtm -c "UPDATE dead_letter_queue SET status = 'resolved', resolved_at = NOW() WHERE id = YOUR_DLQ_ID;"
```

### Method 2: Manual Execution in n8n

**Steps**:
1. Open the main workflow
2. Click "Test workflow" or "Execute Workflow"
3. Paste the payload data into the Webhook node settings
4. Click "Execute"
5. On success, mark the DLQ record as resolved

---

## Common Troubleshooting

### Q1: Recurring validation_errors

**Causes**:
- Misconfigured input source (form/API)
- Missing frontend validation

**Investigate**:
```sql
-- View recent validation_errors
SELECT
  id,
  run_id,
  error_message,
  payload->'execution'->'error'->'tags'->>'message' as detail
FROM dead_letter_queue
WHERE error_type = 'validation_error'
ORDER BY created_at DESC
LIMIT 5;
```

**Resolution**:
- Fix the input source
- Add frontend validation
- Mark all validation_errors as failed_permanently

---

### Q2: Sudden spike in ai_errors

**Possible causes**:
1. OpenAI API key expired
2. API quota exhausted
3. OpenAI service outage

**Investigate**:
```bash
# Test API key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"
```

```sql
-- View AI error details
SELECT id, run_id, error_message, created_at
FROM dead_letter_queue
WHERE error_type = 'ai_error'
ORDER BY created_at DESC
LIMIT 5;
```

**Resolution**:
- Update API key
- Top up quota
- Wait for OpenAI recovery

---

### Q3: Retries exhausted but task still unresolved

**Investigate**:
```sql
SELECT
  id,
  run_id,
  error_type,
  retry_count,
  max_retries,
  error_message
FROM dead_letter_queue
WHERE retry_count >= max_retries
ORDER BY created_at DESC;
```

**Resolution**:
1. Analyze root cause
2. Fix the underlying system issue
3. Reset retry_count or trigger manual retry

```sql
-- Reset retry count
UPDATE dead_letter_queue
SET retry_count = 0, next_retry_at = NOW()
WHERE id = YOUR_DLQ_ID;
```

---

## SQL Toolkit

### Tool 1: View Pending Tasks

```sql
SELECT
  id,
  run_id,
  error_type,
  failed_step,
  retry_count || '/' || max_retries AS retries,
  TO_CHAR(next_retry_at, 'YYYY-MM-DD HH24:MI:SS') as next_retry
FROM dead_letter_queue
WHERE status = 'pending'
ORDER BY next_retry_at ASC;
```

### Tool 2: Error Statistics

```sql
SELECT
  error_type,
  status,
  COUNT(*) as count,
  ROUND(AVG(retry_count), 2) as avg_retries
FROM dead_letter_queue
GROUP BY error_type, status
ORDER BY count DESC;
```

### Tool 3: Reset a Task for Retry

```sql
UPDATE dead_letter_queue
SET
  retry_count = 0,
  next_retry_at = NOW(),
  status = 'pending',
  updated_at = NOW()
WHERE id = YOUR_DLQ_ID;
```

### Tool 4: Mark as Permanently Failed

```sql
UPDATE dead_letter_queue
SET
  status = 'failed_permanently',
  updated_at = NOW()
WHERE id = YOUR_DLQ_ID;
```

### Tool 5: Mark as Resolved

```sql
UPDATE dead_letter_queue
SET
  status = 'resolved',
  resolved_at = NOW(),
  updated_at = NOW()
WHERE id = YOUR_DLQ_ID;
```

### Tool 6: Bulk Handle validation_errors

```sql
-- Mark all validation_errors as permanently failed (bad input is not worth retrying)
UPDATE dead_letter_queue
SET status = 'failed_permanently', updated_at = NOW()
WHERE error_type = 'validation_error' AND status = 'pending';
```

### Tool 7: Full Trace Reconstruction

```sql
-- Reconstruct full execution trace by run_id
WITH run_info AS (
  SELECT 'YOUR_RUN_ID' AS target_run_id
)
SELECT
  'leads' AS source_table,
  l.id::TEXT,
  l.company,
  l.email,
  l.score::TEXT,
  l.status
FROM leads l, run_info r
WHERE l.run_id = r.target_run_id

UNION ALL

SELECT
  'events' AS source_table,
  e.id::TEXT,
  e.step,
  e.status,
  NULL,
  NULL
FROM events e, run_info r
WHERE e.run_id = r.target_run_id

UNION ALL

SELECT
  'dead_letter_queue' AS source_table,
  d.id::TEXT,
  d.error_type,
  d.failed_step,
  d.error_message,
  d.status
FROM dead_letter_queue d, run_info r
WHERE d.run_id = r.target_run_id;
```

### Tool 8: Today's Error Overview

```sql
SELECT
  'New errors today' AS metric,
  COUNT(*) AS value
FROM dead_letter_queue
WHERE created_at >= CURRENT_DATE

UNION ALL

SELECT
  'Pending retries',
  COUNT(*)
FROM dead_letter_queue
WHERE status = 'pending'

UNION ALL

SELECT
  'Permanently failed',
  COUNT(*)
FROM dead_letter_queue
WHERE status = 'failed_permanently'

UNION ALL

SELECT
  'Resolved',
  COUNT(*)
FROM dead_letter_queue
WHERE status = 'resolved';
```

---

## Operational Best Practices

### Daily Routine

1. **9:00 AM**: Run health check script
2. **Check Slack alerts**: Respond to error notifications promptly
3. **Weekly review**: Analyze error type distribution, optimize system

### Alert Response Times

| Error Type | Response Time | Resolution Time |
|-----------|--------------|-----------------|
| db_error | 5 minutes | 30 minutes |
| ai_error | 30 minutes | 1 hour |
| slack_error | 1 hour | 2 hours |
| validation_error | 1 day | As needed |

### Data Retention Policy

- **pending**: Retain for 7 days
- **resolved**: Retain for 30 days
- **failed_permanently**: Retain for 90 days

```sql
-- Clean up resolved records older than 90 days
DELETE FROM dead_letter_queue
WHERE status = 'resolved'
  AND resolved_at < NOW() - INTERVAL '90 days';
```
