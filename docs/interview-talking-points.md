# Interview Talking Points — AI-GTM Lead Processing System

## Technical Decision Questions

### Q1: "Why n8n instead of writing your own API?"

> **Answer:** n8n gave me two things custom code wouldn't: a visual workflow editor for rapid iteration, and built-in connectors for HubSpot, Slack, and PostgreSQL. During development I changed the pipeline flow over 10 times — moving nodes, adding validation steps, inserting event logging. With n8n I could do this in minutes by dragging connections. With a custom API, each change would require code changes, testing, and redeployment.
>
> **Trade-off I'm aware of:** n8n adds a dependency and limits some flexibility. If this system needed sub-100ms latency or custom ML models, I'd switch to a Python FastAPI service. But for an event-driven pipeline with external API calls, the orchestration overhead is negligible.

### Q2: "Why GPT-3.5 instead of GPT-4?"

> **Answer:** For structured information extraction from short text (typically 50-200 characters), GPT-3.5 achieves near-identical accuracy to GPT-4 at roughly 1/10 the cost. The task is extracting 5 named fields from Chinese business text — not creative reasoning or complex logic.
>
> I compensate for GPT-3.5's lower capability with prompt engineering: few-shot examples anchor the output format, and per-field confidence scores let downstream logic know when the extraction is unreliable. If confidence drops below acceptable levels, the scoring algorithm automatically penalizes the lead score.
>
> **When I would upgrade:** If we needed multi-language support, complex reasoning about budget ranges, or extraction from long documents (>1000 chars), I'd route those to GPT-4 while keeping GPT-3.5 for standard cases — a model routing pattern.

### Q3: "Why rule-based scoring instead of ML?"

> **Answer:** Three reasons:
>
> 1. **Transparency** — Every score has a `score_breakdown` object showing exactly which dimensions contributed how many points. Sales teams need to understand and trust the scores.
>
> 2. **No training data** — ML scoring requires labeled conversion data (which leads actually became customers). This is a new system with no historical data yet.
>
> 3. **Tunability** — Business priorities change. If the company decides urgency matters more than budget, I change one weight constant. With ML, I'd need to retrain.
>
> **My v2 plan:** Once we have 6+ months of conversion data, I'd train a logistic regression model using the existing `score_breakdown` dimensions as features and actual conversion as the label. The rule-based system becomes a feature engineering layer for the ML model.

### Q4: "Why content-based idempotency instead of request IDs?"

> **Answer:** Request IDs prevent the *same request* from being processed twice. Content-based hashing prevents the *same lead* from being processed twice, regardless of which system submits it.
>
> If a lead comes in through the webhook today and someone manually enters the same text tomorrow, a request ID wouldn't catch it — but my content hash will. The text is normalized (lowercase, whitespace-collapsed, punctuation-standardized) before hashing, so minor formatting differences don't create false negatives.
>
> The PostgreSQL `ON CONFLICT (idempotency_key) DO UPDATE` makes this atomic — no race conditions, no application-level locking needed.

### Q5: "What's the analysis_summary field for? Why not full chain-of-thought?"

> **Answer:** `analysis_summary` is a one-line extraction reasoning note, like: "High-quality lead: company, contact, email, clear budget and urgent timeline."
>
> I chose this over full chain-of-thought for three production reasons:
> 1. **Cost** — CoT output can be 3-5x more tokens
> 2. **Latency** — More tokens = slower response in a real-time pipeline
> 3. **Parsing** — CoT text needs additional parsing; a single summary line is directly usable
>
> The summary gives human reviewers enough context without the overhead. In production AI systems, inference outputs should be compact and structured.

---

## Scalability Questions

### Q6: "What if traffic increases 10x?"

> **Answer:** The current system processes leads sequentially. For 10x scale:
>
> 1. **Webhook layer** — Add a message queue (Redis or SQS) between webhook and processing. The webhook immediately acknowledges and queues the job.
> 2. **Processing** — Run multiple n8n worker instances consuming from the queue in parallel.
> 3. **Database** — PostgreSQL can handle 10x easily with connection pooling (PgBouncer). The idempotency index makes duplicate checks O(1).
> 4. **AI calls** — OpenAI API is the bottleneck. Batch requests or use async calls. Consider caching extractions for identical text (already prevented by idempotency, but could cache AI responses separately).
> 5. **DLQ worker** — Currently runs every 15 minutes. At scale, switch to event-driven processing (retry immediately on failure instead of polling).

### Q7: "What was the hardest part of this project?"

> **Answer:** Getting the DLQ retry worker to work correctly with the main pipeline. The challenge was ensuring that a retried lead goes through the exact same flow as a new lead — including idempotency checks, scoring, and event logging — without creating duplicate entries or infinite retry loops.
>
> The key insight was that the retry worker should re-inject the original payload to the webhook, not try to resume from the failed step. This means the entire pipeline is tested on every retry, and the idempotency guard prevents duplicates even if the original processing partially succeeded before failing.
>
> The second challenge was exponential backoff timing. I had to make sure `next_retry_at` was calculated correctly so the worker doesn't pick up a record too early, and that the `retrying` status acts as an optimistic lock so two worker executions don't process the same record.

---

## Quick Stats to Mention

- **Pipeline nodes:** 19 (main) + 11 (retry worker) + 8 (error handler)
- **Database tables:** 3 (leads, events, dead_letter_queue)
- **Scoring dimensions:** 5 with configurable weights
- **Test coverage:** 19 unit test assertions + 4 E2E scenarios
- **Error types handled:** 5 (validation, AI, DB, Slack, unknown)
- **Retry schedule:** 5 min → 15 min → 60 min (exponential backoff)
