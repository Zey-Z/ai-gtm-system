-- ========================================
-- Migration: 002_create_dlq.sql
-- Description: Create Dead Letter Queue (DLQ) table and indexes
-- Author: AI GTM System
-- Date: 2026-02-21
-- ========================================

-- Create dead_letter_queue table
CREATE TABLE IF NOT EXISTS dead_letter_queue (
    id SERIAL PRIMARY KEY,
    run_id TEXT NOT NULL,                    -- Execution ID for tracing
    lead_id INTEGER,                         -- Associated lead ID (if created)
    error_type TEXT NOT NULL,                -- Error type: validation_error, ai_error, db_error, slack_error, unknown
    failed_step TEXT NOT NULL,               -- Failed node name
    error_message TEXT,                      -- Error details
    payload JSONB NOT NULL,                  -- Complete original data (for replay)
    retry_count INTEGER DEFAULT 0,           -- Current retry count
    max_retries INTEGER DEFAULT 3,           -- Maximum retry attempts
    status TEXT DEFAULT 'pending',           -- Status: pending, retrying, failed_permanently, resolved
    next_retry_at TIMESTAMP,                 -- Next retry time (exponential backoff)
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    resolved_at TIMESTAMP,                   -- Resolution time
    idempotency_key TEXT                     -- Idempotency key (prevent duplicate error records)
);

-- Create indexes for query performance
CREATE INDEX IF NOT EXISTS idx_dlq_status ON dead_letter_queue(status);
CREATE INDEX IF NOT EXISTS idx_dlq_run_id ON dead_letter_queue(run_id);
CREATE INDEX IF NOT EXISTS idx_dlq_error_type ON dead_letter_queue(error_type);

-- Partial index - only index pending retry records (optimize retry queries)
CREATE INDEX IF NOT EXISTS idx_dlq_next_retry
ON dead_letter_queue(next_retry_at)
WHERE status = 'pending';

-- Partial unique index for idempotency (only for unresolved failures)
CREATE UNIQUE INDEX IF NOT EXISTS idx_dlq_idempotency_key
ON dead_letter_queue(idempotency_key)
WHERE status IN ('pending', 'retrying');

-- Add constraint checks
ALTER TABLE dead_letter_queue
ADD CONSTRAINT check_error_type CHECK (
    error_type IN ('validation_error', 'ai_error', 'db_error', 'slack_error', 'unknown')
);

ALTER TABLE dead_letter_queue
ADD CONSTRAINT check_status CHECK (
    status IN ('pending', 'retrying', 'failed_permanently', 'resolved')
);

-- Add foreign key constraint (if lead exists)
ALTER TABLE dead_letter_queue
ADD CONSTRAINT fk_dlq_lead_id
FOREIGN KEY (lead_id) REFERENCES leads(id)
ON DELETE SET NULL;  -- If lead is deleted, DLQ record remains but lead_id is set to NULL

-- Verify table creation
SELECT 'DLQ table created successfully' AS message,
       COUNT(*) AS column_count
FROM information_schema.columns
WHERE table_name = 'dead_letter_queue';

-- Verify index creation
SELECT 'DLQ indexes created successfully' AS message,
       COUNT(*) AS index_count
FROM pg_indexes
WHERE tablename = 'dead_letter_queue';
