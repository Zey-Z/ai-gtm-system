-- AI-First GTM 系统数据库初始化脚本
-- 这个脚本会在 PostgreSQL 容器第一次启动时自动执行

-- 创建 leads 表（潜在客户信息）
CREATE TABLE IF NOT EXISTS leads (
    -- 主键，自动递增
    id SERIAL PRIMARY KEY,

    -- 外部唯一标识（防止重复提交）
    external_id TEXT UNIQUE NOT NULL,

    -- 原始输入文本
    raw_text TEXT NOT NULL,

    -- AI 提取的结构化信息
    company TEXT,
    contact_name TEXT,
    email TEXT,
    budget TEXT,
    urgency TEXT,

    -- 质量评分（0-100）
    score INTEGER,

    -- 状态（new/processing/processed/failed）
    status TEXT DEFAULT 'new',

    -- 时间戳
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 创建 events 表（审计日志）
CREATE TABLE IF NOT EXISTS events (
    -- 主键，自动递增
    id SERIAL PRIMARY KEY,

    -- 关联的 lead ID
    lead_id INTEGER REFERENCES leads(id),

    -- 步骤名称（如 "ai_extract", "slack_notify"）
    step TEXT NOT NULL,

    -- 状态（success/failed）
    status TEXT NOT NULL,

    -- 错误信息（如果失败）
    error_message TEXT,

    -- 额外数据（JSON 格式）
    data JSONB,

    -- 时间戳
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 创建索引以提升查询性能
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_score ON leads(score);
CREATE INDEX IF NOT EXISTS idx_leads_created_at ON leads(created_at);
CREATE INDEX IF NOT EXISTS idx_events_lead_id ON events(lead_id);
CREATE INDEX IF NOT EXISTS idx_events_step ON events(step);

-- 插入一条测试数据（可选）
INSERT INTO leads (external_id, raw_text, company, score, status)
VALUES ('test_001', '这是一条测试数据', '测试公司', 50, 'new')
ON CONFLICT (external_id) DO NOTHING;

-- 显示创建结果
SELECT 'Database initialized successfully!' AS status;
SELECT COUNT(*) AS lead_count FROM leads;
SELECT COUNT(*) AS event_count FROM events;
