-- 测试查询集合

-- 1. 查看所有 leads（最多 10 条）
SELECT * FROM leads ORDER BY created_at DESC LIMIT 10;

-- 2. 查看 leads 总数
SELECT COUNT(*) as total_leads FROM leads;

-- 3. 插入测试数据（每次运行生成不同的 ID）
INSERT INTO leads (external_id, raw_text, company, score, status)
VALUES (
    'test_n8n_' || EXTRACT(EPOCH FROM NOW())::TEXT,
    'n8n测试数据 - ' || NOW()::TEXT,
    '我的测试公司',
    60,
    'new'
)
RETURNING *;

-- 4. 查看最近 5 条 leads
SELECT
    id,
    external_id,
    company,
    score,
    status,
    created_at
FROM leads
ORDER BY created_at DESC
LIMIT 5;

-- 5. 清空测试数据（慎用！）
-- DELETE FROM leads WHERE external_id LIKE 'test_%';
-- SELECT COUNT(*) as remaining_leads FROM leads;
