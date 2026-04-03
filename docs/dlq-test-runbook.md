# DLQ Retry Worker — Test Runbook

> **Objective**: Verify DLQ Retry Worker behavior across three paths: **successful retry**, **failed retry with backoff**, and **permanent failure after max retries**.

## Assumptions

- Database: PostgreSQL
- Key tables:
  - `dead_letter_queue` (fields: `id`, `status`, `retry_count`, `max_retries`, `next_retry_at`, `resolved_at`, `payload`, `created_at`)
  - `leads` (main pipeline success records)
- Status semantics:
  - `pending`: Awaiting retry
  - `resolved`: Successfully retried and completed
  - `failed_permanently`: Max retries reached, final failure
- Backoff schedule: `[5, 15, 60]` minutes (delay after 1st/2nd/3rd failure)

---

## Test 6: Successful Retry

### Setup

Ensure a DLQ record exists that is ready for immediate processing:

```sql
SELECT id, status, retry_count, next_retry_at
FROM dead_letter_queue
WHERE status = 'pending'
  AND next_retry_at <= NOW()
ORDER BY next_retry_at ASC
LIMIT 1;
```

If none exists, insert test data:

```sql
INSERT INTO dead_letter_queue (status, retry_count, max_retries, next_retry_at, payload, created_at)
VALUES (
  'pending',
  0,
  3,
  NOW() - INTERVAL '1 minute',
  '{"email":"test6@example.com","source":"dlq-test-6"}',
  NOW()
);
```

### Execute

1. Manually trigger the DLQ Retry Worker workflow in n8n
2. Or wait for the 15-minute scheduled cycle

### Verify

```sql
-- 1) DLQ record should be resolved
SELECT id, status, retry_count, resolved_at
FROM dead_letter_queue
WHERE payload::text LIKE '%test6@example.com%'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected**:
- `status = 'resolved'`
- `resolved_at IS NOT NULL`

```sql
-- 2) Lead should appear in leads table
SELECT id, email, created_at
FROM leads
WHERE email = 'test6@example.com'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected**: Record exists.

---

## Test 7: Failed Retry with Backoff

### Setup

Prepare a retryable record and ensure the main pipeline will still fail (e.g., temporarily disable the webhook endpoint or point the webhook URL to an unresponsive address).

```sql
INSERT INTO dead_letter_queue (status, retry_count, max_retries, next_retry_at, payload, created_at)
VALUES (
  'pending',
  0,
  3,
  NOW() - INTERVAL '1 minute',
  '{"email":"test7@example.com","source":"dlq-test-7"}',
  NOW()
);
```

### Execute

Trigger the DLQ Retry Worker once.

### Verify

```sql
SELECT id, status, retry_count, next_retry_at, NOW() AS checked_at
FROM dead_letter_queue
WHERE payload::text LIKE '%test7@example.com%'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected**:
- `retry_count` incremented (e.g., 0 → 1)
- `status` remains `pending` (has not exceeded `max_retries`)
- `next_retry_at` updated to current time + corresponding backoff delay

#### Backoff Verification

Compare `next_retry_at` against expected delays:
- After 1st failure: ~+5 minutes
- After 2nd failure: ~+15 minutes
- After 3rd failure: ~+60 minutes

(Allow margin of ~30 seconds due to worker execution and query timing)

---

## Test 8: Permanent Failure

### Setup

Prepare a record with `retry_count = max_retries - 1` and ensure the next attempt will also fail:

```sql
INSERT INTO dead_letter_queue (status, retry_count, max_retries, next_retry_at, payload, created_at)
VALUES (
  'pending',
  2,
  3,
  NOW() - INTERVAL '1 minute',
  '{"email":"test8@example.com","source":"dlq-test-8"}',
  NOW()
);
```

### Execute

Trigger the DLQ Retry Worker once.

### Verify

```sql
-- 1) Record should be permanently failed
SELECT id, status, retry_count, max_retries, next_retry_at, resolved_at
FROM dead_letter_queue
WHERE payload::text LIKE '%test8@example.com%'
ORDER BY created_at DESC
LIMIT 1;
```

**Expected**:
- `status = 'failed_permanently'`
- `retry_count >= max_retries`

**Additionally**: Verify that a Slack alert was sent for the permanent failure.

---

## Regression Checklist

- [ ] Test 6: `resolved` + `resolved_at` populated + new record in `leads`
- [ ] Test 7: `retry_count` incremented, `pending` status maintained, `next_retry_at` reflects correct backoff
- [ ] Test 8: `failed_permanently` status + Slack alert triggered

## Troubleshooting

1. **Worker not picking up records**
   - Verify `next_retry_at <= NOW()` condition is met
   - Check query conditions for missing tenant/partition filters
   - Confirm worker is running with correct environment variables

2. **Retry succeeded but status not updated**
   - Check transaction commit
   - Verify status update SQL uses optimistic locking (`id + status='pending'`)

3. **Backoff timing is incorrect**
   - Check backoff array indexing (0-based vs 1-based)
   - Verify timezone alignment between application layer and database (`NOW()` source)

4. **No Slack alert on permanent failure**
   - Check alert toggle, Webhook URL, and whether the failure branch actually triggers
   - Add structured logging on the permanent failure branch (`event_id`, `retry_count`, `max_retries`)
