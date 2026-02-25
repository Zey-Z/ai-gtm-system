-- ========================================
-- Migration: 003_add_idempotency.sql
-- Description: 添加幂等键支持（基于内容哈希）
-- Author: AI GTM System
-- Date: 2026-02-21
-- Purpose: 实现基于内容的幂等机制，确保相同内容只处理一次
-- ========================================

-- ============================================================
-- 背景说明
-- ============================================================
-- 问题：
-- 1. external_id 包含随机字符串，每次生成都不同（不能用于幂等）
-- 2. run_id 是执行 ID，每次执行都会变（不能用于幂等）
--
-- 解决方案：
-- 使用基于 raw_text 的 SHA256 哈希作为幂等键
-- - 文本标准化：trim、toLowerCase、多空格合一
-- - 相同内容 → 相同哈希 → 相同幂等键
-- - 使用 UNIQUE 约束防止重复插入
-- ============================================================

-- 1. 为 leads 表添加 idempotency_key
ALTER TABLE leads ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

COMMENT ON COLUMN leads.idempotency_key IS '幂等键 - 基于标准化文本的 SHA256 哈希（格式：lead:${hash}）';

-- 2. 添加唯一约束（核心：防止重复插入）
CREATE UNIQUE INDEX IF NOT EXISTS idx_leads_idempotency_key
ON leads(idempotency_key);

-- 3. 添加复合索引以提升查询性能（幂等键 + 创建时间）
CREATE INDEX IF NOT EXISTS idx_leads_idempotency_created
ON leads(idempotency_key, created_at);

-- 4. 为 dead_letter_queue 表添加幂等键（如果表已存在）
DO $$
BEGIN
    -- 检查 dead_letter_queue 表是否存在
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'dead_letter_queue') THEN
        -- 添加 idempotency_key 列
        ALTER TABLE dead_letter_queue ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

        -- 添加注释
        COMMENT ON COLUMN dead_letter_queue.idempotency_key IS '幂等键 - 关联到失败的 lead，确保同一失败只记录一次';

        -- 创建部分唯一索引（只对未解决的失败去重）
        CREATE UNIQUE INDEX IF NOT EXISTS idx_dlq_idempotency_key
        ON dead_letter_queue(idempotency_key)
        WHERE status IN ('pending', 'retrying');
    END IF;
END $$;

-- ============================================================
-- 验证检查
-- ============================================================

-- 检查 1: 验证 leads 表的 idempotency_key 列
SELECT
    'leads.idempotency_key column' AS check_item,
    COUNT(*) > 0 AS has_column,
    'Column created successfully' AS status
FROM information_schema.columns
WHERE table_name = 'leads' AND column_name = 'idempotency_key';

-- 检查 2: 验证唯一索引
SELECT
    'Unique index on idempotency_key' AS check_item,
    COUNT(*) > 0 AS has_index,
    'Index created successfully' AS status
FROM pg_indexes
WHERE tablename = 'leads' AND indexname = 'idx_leads_idempotency_key';

-- 检查 3: 验证性能索引
SELECT
    'Performance index' AS check_item,
    COUNT(*) > 0 AS has_index,
    'Index created successfully' AS status
FROM pg_indexes
WHERE tablename = 'leads' AND indexname = 'idx_leads_idempotency_created';

-- 检查 4: 验证 DLQ 表的幂等键（如果存在）
SELECT
    'DLQ.idempotency_key column' AS check_item,
    CASE
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'dead_letter_queue')
        THEN (SELECT COUNT(*) > 0 FROM information_schema.columns
              WHERE table_name = 'dead_letter_queue' AND column_name = 'idempotency_key')
        ELSE FALSE
    END AS has_column,
    CASE
        WHEN EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'dead_letter_queue')
        THEN 'DLQ table exists, column checked'
        ELSE 'DLQ table not yet created (will be created in 002_create_dlq.sql)'
    END AS status;

-- ============================================================
-- 使用示例（仅供参考，不执行）
-- ============================================================

-- 示例 1: UPSERT 逻辑（在 n8n workflow 中使用）
/*
INSERT INTO leads (
    idempotency_key,
    external_id,
    run_id,
    raw_text,
    ...
)
VALUES ($1, $2, $3, $4, ...)
ON CONFLICT (idempotency_key) DO UPDATE SET
    run_id = EXCLUDED.run_id,
    updated_at = NOW()
RETURNING
    id,
    idempotency_key,
    (xmax = 0) AS is_new_record;  -- true = 新插入，false = 更新
*/

-- 示例 2: 查询重复记录
/*
SELECT
    idempotency_key,
    COUNT(*) AS record_count,
    MIN(created_at) AS first_created,
    MAX(updated_at) AS last_updated,
    STRING_AGG(DISTINCT run_id, ', ') AS all_run_ids
FROM leads
GROUP BY idempotency_key
HAVING COUNT(*) > 1;
*/

-- 示例 3: 查询幂等键对应的完整链路
/*
WITH target_lead AS (
    SELECT run_id, idempotency_key
    FROM leads
    WHERE idempotency_key = 'lead:YOUR_HASH_HERE'
    LIMIT 1
)
SELECT
    'leads' AS source,
    l.*
FROM leads l, target_lead t
WHERE l.idempotency_key = t.idempotency_key

UNION ALL

SELECT
    'events' AS source,
    e.*
FROM events e, target_lead t
WHERE e.run_id = t.run_id;
*/

-- ============================================================
-- 迁移完成提示
-- ============================================================

SELECT
    'Idempotency migration completed' AS message,
    'idempotency_key column added to leads table' AS detail_1,
    'Unique constraint created to prevent duplicates' AS detail_2,
    'Next: Modify n8n workflow nodes to generate and use idempotency keys' AS next_step;
