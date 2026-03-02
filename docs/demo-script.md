# AI-GTM System — 5-Minute Demo Script

## 30-Second Pitch (开场)

> "This is an AI-powered lead processing pipeline that turns unstructured sales inquiries into scored, CRM-ready contacts — automatically. It uses GPT-3.5 with few-shot prompting and confidence scoring to extract structured data, scores leads across 5 weighted dimensions, and routes high-quality leads to HubSpot with Slack notifications. The system includes idempotency protection, a Dead Letter Queue with exponential backoff retry, and full event-sourced audit trails."

## Demo 1: Main Pipeline — High-Quality Lead (2 min)

### Step 1: Send a high-quality lead

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{
    "lead_text": "我是张伟，来自星辰科技有限公司，邮箱 zhangwei@xingchen.com，我们预算大约50万，希望下周能开始对接。"
  }'
```

### What to point out:

1. **AI Extraction** — GPT-3.5 extracts 5 fields with per-field confidence scores
2. **Scoring** — This lead should score 85+ (all dimensions filled: budget 30%, urgency 20%, contact 20%, company 15%, AI confidence 15%)
3. **CRM Sync** — Score ≥ 70 triggers HubSpot contact upsert
4. **Slack Alert** — Team gets notification with HubSpot link

### Verify in database:

```sql
SELECT company, email, score, status FROM leads ORDER BY created_at DESC LIMIT 1;
SELECT step, status FROM events WHERE run_id = '<run_id>' ORDER BY created_at;
```

**Key talking point:** "Every pipeline step writes to the events table with a run_id. I can reconstruct the full lifecycle of any lead with one SQL query."

---

## Demo 2: Idempotency Protection (1 min)

### Step 1: Send the exact same lead again

```bash
# Same text as Demo 1
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{
    "lead_text": "我是张伟，来自星辰科技有限公司，邮箱 zhangwei@xingchen.com，我们预算大约50万，希望下周能开始对接。"
  }'
```

### What to point out:

1. **Same idempotency key** — The text is normalized (lowercase, whitespace-collapsed) and hashed, producing the same key
2. **UPSERT, not duplicate** — PostgreSQL `ON CONFLICT` triggers UPDATE, not INSERT
3. **Event logged** — `duplicate_skipped` event recorded in audit trail

### Verify:

```sql
SELECT COUNT(*) FROM leads WHERE company LIKE '%星辰%';  -- Still 1 row
SELECT step FROM events WHERE step = 'duplicate_skipped' ORDER BY created_at DESC LIMIT 1;
```

**Key talking point:** "Idempotency is content-based, not request-based. The same lead text always produces the same hash, regardless of when or how many times it's submitted."

---

## Demo 3: Error Recovery — DLQ (1.5 min)

### What to explain (if live DLQ demo is not available):

> "When any pipeline step fails — AI extraction, database write, Slack notification — the Error Handler workflow catches it, classifies the error type, and writes the full original payload to a Dead Letter Queue."

### Key architecture points:

1. **5 error types** with different retry strategies:
   - `validation_error` → 0 retries (garbage in, garbage out)
   - `ai_error` → 3 retries (transient API issues)
   - `db_error` → 3 retries (connection/lock issues)
   - `slack_error` → 2 retries
   - `unknown` → 1 retry

2. **Exponential backoff**: 5 min → 15 min → 60 min

3. **Background worker** runs every 15 minutes, picks up pending retries

### Show DLQ monitoring query:

```sql
SELECT status, COUNT(*),
       AVG(retry_count)::numeric(3,1) as avg_retries
FROM dead_letter_queue
GROUP BY status;
```

**Key talking point:** "Failed leads are never lost. The DLQ preserves the complete original payload, so retries re-inject the exact same data. This is the same pattern used by AWS SQS and Kafka consumer groups."

---

## Closing (30 sec)

> "This system handles the full lifecycle: intake, AI extraction with confidence scoring, multi-dimension scoring, CRM sync, team notification, and error recovery. It's built for reliability — idempotency prevents duplicates, event sourcing enables debugging, and the DLQ ensures nothing is lost."

---

## Scoring Algorithm Quick Reference (if asked)

| Dimension | Weight | Max Points |
|-----------|--------|------------|
| Budget | 30% | 30 |
| Urgency | 20% | 20 |
| Contact Info | 20% | 20 |
| Company | 15% | 15 |
| AI Confidence | 15% | 15 |
| **Total** | **100%** | **100** |

Threshold for CRM sync: **Score ≥ 70**

## Unit Tests Quick Reference (if asked)

```bash
node tests/test-scoring.js    # 19 assertions, all passing
bash tests/test-webhook.sh    # 4 E2E scenarios
```
