-- NULL 值测试查询

-- 1. 查看最新的一条记录（应该是刚才插入的测试数据）
SELECT
    id,
    external_id,
    company,
    contact_name,
    email,
    budget,
    urgency,
    score,
    status,
    created_at
FROM leads
ORDER BY created_at DESC
LIMIT 1;

-- 2. 检查 NULL 字段（重点！）
-- 这个查询会显示哪些字段是真正的 NULL
SELECT
    id,
    external_id,
    company IS NULL AS company_is_null,
    contact_name IS NULL AS contact_name_is_null,
    email IS NULL AS email_is_null,
    budget IS NULL AS budget_is_null,
    urgency IS NULL AS urgency_is_null,
    score,
    created_at
FROM leads
ORDER BY created_at DESC
LIMIT 1;

-- 3. 查看所有包含 NULL 值的记录
SELECT
    id,
    external_id,
    CASE WHEN company IS NULL THEN 'NULL' ELSE company END AS company,
    CASE WHEN email IS NULL THEN 'NULL' ELSE email END AS email,
    CASE WHEN budget IS NULL THEN 'NULL' ELSE budget END AS budget,
    score,
    created_at
FROM leads
WHERE company IS NULL
   OR contact_name IS NULL
   OR email IS NULL
   OR budget IS NULL
   OR urgency IS NULL
ORDER BY created_at DESC;
