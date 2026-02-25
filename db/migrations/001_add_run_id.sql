-- Migration: 添加 run_id 列用于全链路追踪
-- Date: 2026-02-20
-- Description: 为 leads 和 events 表添加 run_id 字段，支持端到端链路追踪

-- 1. 为 leads 表添加 run_id
ALTER TABLE leads ADD COLUMN IF NOT EXISTS run_id TEXT;

-- 2. 为 events 表添加 run_id
ALTER TABLE events ADD COLUMN IF NOT EXISTS run_id TEXT;

-- 3. 创建索引以提升查询性能
CREATE INDEX IF NOT EXISTS idx_leads_run_id ON leads(run_id);
CREATE INDEX IF NOT EXISTS idx_events_run_id ON events(run_id);

-- 4. 验证迁移结果
-- 运行以下命令查看表结构：
-- \d leads
-- \d events

-- 预期结果：两个表都应该有 run_id 列和对应的索引
