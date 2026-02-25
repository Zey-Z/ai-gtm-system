# DLQ 运维手册

## 目录
1. [日常监控](#日常监控)
2. [错误处理流程](#错误处理流程)
3. [手动重试](#手动重试)
4. [常见问题排查](#常见问题排查)
5. [SQL 工具集](#sql-工具集)

---

## 日常监控

### 每日健康检查

**推荐时间**：每天早上 9:00

```bash
# 运行健康检查脚本
docker exec -it ai-gtm-system-postgres-1 psql -U aigtm_user -d aigtm -f /db/dlq-queries.sql
```

**关注指标**：
- 待处理任务数（status = 'pending'）
- 永久失败任务数（status = 'failed_permanently'）
- 今日新增错误数

**告警阈值**：
- 待处理任务 > 10：需要检查系统
- 永久失败 > 5：需要人工介入
- AI 错误 > 5/天：检查 API Key 或配额

---

## 错误处理流程

### 1. 收到 Slack 告警后

**步骤**：
1. 记录 Run ID（从 Slack 消息中获取）
2. 查询 DLQ 详情
3. 判断错误类型
4. 根据类型采取行动

**示例**：
```sql
-- 根据 Run ID 查询完整链路
SELECT * FROM dead_letter_queue WHERE run_id = 'YOUR_RUN_ID';
```

### 2. 错误分类处理

| 错误类型 | 处理方式 | 优先级 |
|---------|---------|--------|
| **validation_error** | 检查输入源，修复后不重试 | P2 |
| **ai_error** | 检查 API Key/配额，等待自动重试或手动重试 | P1 |
| **db_error** | 检查数据库连接/配置，修复后手动重试 | P0 |
| **slack_error** | 检查 Webhook URL，修复后手动重试 | P2 |
| **unknown** | 查看 error_message 和 payload，具体分析 | P1 |

### 3. 决策树

```
收到错误告警
    ↓
查看 error_type
    ↓
是 validation_error？
    YES → 标记为 failed_permanently（垃圾数据）
    NO  → 继续
    ↓
是 ai_error？
    YES → 检查 API Key → 修复 → 手动重试
    NO  → 继续
    ↓
是 db_error？
    YES → 检查数据库 → 修复 → 手动重试
    NO  → 继续
    ↓
是 slack_error？
    YES → 检查 Webhook URL → 修复 → 手动重试
    NO  → 查看 payload 具体分析
```

---

## 手动重试

### 方法 1: 重新发送 Webhook（推荐）

**适用场景**：所有错误类型

**步骤**：

```bash
# 1. 从 DLQ 提取 payload
docker exec -it ai-gtm-system-postgres-1 psql -U aigtm_user -d aigtm -c "SELECT payload FROM dead_letter_queue WHERE id = YOUR_DLQ_ID;"

# 2. 复制 payload 中的 execution.error.executionContext 或原始输入数据
# 3. 重新发送到 webhook（修改后的数据）
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"lead_text": "从 payload 中提取的原始文本"}'

# 4. 如果成功，标记原 DLQ 记录为 resolved
docker exec -it ai-gtm-system-postgres-1 psql -U aigtm_user -d aigtm -c "UPDATE dead_letter_queue SET status = 'resolved', resolved_at = NOW() WHERE id = YOUR_DLQ_ID;"
```

### 方法 2: 在 n8n 手动执行

**步骤**：
1. 打开主 workflow
2. 点击 "Test workflow" 或 "Execute Workflow"
3. 在 Webhook 节点设置中，粘贴 payload 数据
4. 点击 "Execute"
5. 成功后标记 DLQ 为 resolved

---

## 常见问题排查

### Q1: validation_error 持续出现

**原因**：
- 输入源（表单/API）配置错误
- 前端验证缺失

**排查**：
```sql
-- 查看最近的 validation_error
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

**解决**：
- 修复输入源
- 添加前端验证
- 标记所有 validation_error 为 failed_permanently

---

### Q2: ai_error 突然增多

**可能原因**：
1. OpenAI API Key 失效
2. API 配额用尽
3. OpenAI 服务故障

**排查**：
```bash
# 测试 API Key
curl https://api.openai.com/v1/models \
  -H "Authorization: Bearer YOUR_API_KEY"

# 查看 AI 错误详情
docker exec -it ai-gtm-system-postgres-1 psql -U aigtm_user -d aigtm -c "SELECT id, run_id, error_message, created_at FROM dead_letter_queue WHERE error_type = 'ai_error' ORDER BY created_at DESC LIMIT 5;"
```

**解决**：
- 更新 API Key
- 充值配额
- 等待 OpenAI 恢复

---

### Q3: 重试次数用尽但任务仍未成功

**排查**：
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

**处理**：
1. 分析根本原因
2. 修复系统问题
3. 重置 retry_count 或手动重试

```sql
-- 重置重试次数
UPDATE dead_letter_queue
SET retry_count = 0, next_retry_at = NOW()
WHERE id = YOUR_DLQ_ID;
```

---

## SQL 工具集

### 工具 1: 查看待处理任务

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

---

### 工具 2: 错误统计

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

---

### 工具 3: 手动重置任务

```sql
-- 重置特定任务，准备重试
UPDATE dead_letter_queue
SET
  retry_count = 0,
  next_retry_at = NOW(),
  status = 'pending',
  updated_at = NOW()
WHERE id = YOUR_DLQ_ID;
```

---

### 工具 4: 标记为永久失败

```sql
-- 放弃重试（如：垃圾数据）
UPDATE dead_letter_queue
SET
  status = 'failed_permanently',
  updated_at = NOW()
WHERE id = YOUR_DLQ_ID;
```

---

### 工具 5: 标记为已解决

```sql
-- 手动处理完成后标记
UPDATE dead_letter_queue
SET
  status = 'resolved',
  resolved_at = NOW(),
  updated_at = NOW()
WHERE id = YOUR_DLQ_ID;
```

---

### 工具 6: 批量处理 validation_error

```sql
-- 将所有 validation_error 标记为永久失败（因为输入错误不值得重试）
UPDATE dead_letter_queue
SET status = 'failed_permanently', updated_at = NOW()
WHERE error_type = 'validation_error' AND status = 'pending';
```

---

### 工具 7: 完整链路追踪

```sql
-- 根据 run_id 查询完整执行链路
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

---

### 工具 8: 今日错误概览

```sql
SELECT
  '今日新增错误' AS metric,
  COUNT(*) AS value
FROM dead_letter_queue
WHERE created_at >= CURRENT_DATE

UNION ALL

SELECT
  '待重试任务数',
  COUNT(*)
FROM dead_letter_queue
WHERE status = 'pending'

UNION ALL

SELECT
  '永久失败任务数',
  COUNT(*)
FROM dead_letter_queue
WHERE status = 'failed_permanently'

UNION ALL

SELECT
  '已解决任务数',
  COUNT(*)
FROM dead_letter_queue
WHERE status = 'resolved';
```

---

## 运维最佳实践

### 每日例行工作

1. **早上 9:00**：运行健康检查脚本
2. **检查 Slack 告警**：及时响应错误通知
3. **每周复盘**：分析错误类型分布，优化系统

### 告警响应时间

| 错误类型 | 响应时间 | 处理时间 |
|---------|---------|---------|
| db_error | 5 分钟 | 30 分钟 |
| ai_error | 30 分钟 | 1 小时 |
| slack_error | 1 小时 | 2 小时 |
| validation_error | 1 天 | 按需 |

### 数据保留策略

- **pending**：保留 7 天
- **resolved**：保留 30 天
- **failed_permanently**：保留 90 天

```sql
-- 清理 90 天前已解决的记录
DELETE FROM dead_letter_queue
WHERE status = 'resolved'
  AND resolved_at < NOW() - INTERVAL '90 days';
```

---

## 紧急联系人

| 角色 | 负责范围 | 联系方式 |
|------|---------|---------|
| 系统管理员 | 数据库、n8n | Slack: @admin |
| 开发负责人 | Bug 修复、逻辑优化 | Slack: @dev-lead |
| 业务负责人 | 数据质量、流程优化 | Slack: @biz-lead |

---

## 版本历史

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| 1.0 | 2026-02-22 | 初版：DLQ 运维手册 |

---

**最后更新**: 2026-02-22
**维护者**: AI GTM System Team
