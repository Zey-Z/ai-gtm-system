# DLQ Retry Worker 测试 6-8 执行手册

> 目标：验证 DLQ Retry Worker 在**成功重试**、**重试失败并退避**、**达到最大重试后永久失败**三种路径上的行为。

## 假设

- 数据库为 PostgreSQL。
- 关键表：
  - `dlq_events`（字段示例：`id`, `status`, `retry_count`, `max_retries`, `next_retry_at`, `resolved_at`, `payload`, `created_at`）
  - `leads`（主 pipeline 成功落库结果）
- 状态语义：
  - `pending`: 等待重试
  - `resolved`: 已重试成功并完成
  - `failed_permanently`: 达到最大重试且最终失败
- 退避策略：`[5, 15, 60]` 分钟（即第 1/2/3 次失败后对应延迟）

---

## 测试 6：DLQ Retry Worker - 成功重试

### 前置

确保存在一条可立即处理的 DLQ 记录：

```sql
SELECT id, status, retry_count, next_retry_at
FROM dlq_events
WHERE status = 'pending'
  AND next_retry_at <= NOW()
ORDER BY next_retry_at ASC
LIMIT 1;
```

如果没有，插入一条测试数据（按你的真实字段调整）：

```sql
INSERT INTO dlq_events (status, retry_count, max_retries, next_retry_at, payload, created_at)
VALUES (
  'pending',
  0,
  3,
  NOW() - INTERVAL '1 minute',
  '{"email":"test6@example.com","source":"dlq-test-6"}',
  NOW()
);
```

### 操作

1. 手动触发 DLQ Retry Worker（推荐命令示例）：
   - `npm run worker:dlq-retry`
   - 或调用内部管理端点（如果有）
2. 或等待 15 分钟调度周期触发。

### 验证

```sql
-- 1) DLQ 是否 resolved
SELECT id, status, retry_count, resolved_at
FROM dlq_events
WHERE payload::text LIKE '%test6@example.com%'
ORDER BY created_at DESC
LIMIT 1;
```

期望：
- `status = 'resolved'`
- `resolved_at IS NOT NULL`

```sql
-- 2) leads 是否有新记录
SELECT id, email, created_at
FROM leads
WHERE email = 'test6@example.com'
ORDER BY created_at DESC
LIMIT 1;
```

期望：存在记录。

---

## 测试 7：DLQ Retry Worker - 重试失败 + 退避

### 前置

准备一条可重试记录，并让主 pipeline 继续失败（例如：临时关闭 webhook 接收端，或把 webhook URL 指向无响应地址）。

```sql
INSERT INTO dlq_events (status, retry_count, max_retries, next_retry_at, payload, created_at)
VALUES (
  'pending',
  0,
  3,
  NOW() - INTERVAL '1 minute',
  '{"email":"test7@example.com","source":"dlq-test-7"}',
  NOW()
);
```

### 操作

触发一次 DLQ Retry Worker。

### 验证

```sql
SELECT id, status, retry_count, next_retry_at, NOW() AS checked_at
FROM dlq_events
WHERE payload::text LIKE '%test7@example.com%'
ORDER BY created_at DESC
LIMIT 1;
```

期望：
- `retry_count` 增加（例如 0 -> 1）
- `status` 仍为 `pending`（前提：未超过 `max_retries`）
- `next_retry_at` 更新为当前时间 + 对应退避分钟数

#### 退避校验建议

可用下列逻辑人工比对：
- 第 1 次失败后：约 +5 分钟
- 第 2 次失败后：约 +15 分钟
- 第 3 次失败后：约 +60 分钟

（允许几十秒级误差，取决于 worker 执行与 SQL 查询时间差）

---

## 测试 8：DLQ 永久失败

### 前置

准备一条 `retry_count = max_retries - 1` 的记录，并确保下一次仍会失败：

```sql
INSERT INTO dlq_events (status, retry_count, max_retries, next_retry_at, payload, created_at)
VALUES (
  'pending',
  2,
  3,
  NOW() - INTERVAL '1 minute',
  '{"email":"test8@example.com","source":"dlq-test-8"}',
  NOW()
);
```

### 操作

触发 DLQ Retry Worker 一次。

### 验证

```sql
-- 1) 记录是否永久失败
SELECT id, status, retry_count, max_retries, next_retry_at, resolved_at
FROM dlq_events
WHERE payload::text LIKE '%test8@example.com%'
ORDER BY created_at DESC
LIMIT 1;
```

期望：
- `status = 'failed_permanently'`
- `retry_count >= max_retries`

```sql
-- 2) Slack 告警检查（若系统有告警事件表，可查 DB）
-- 以下仅为示例：
SELECT *
FROM alert_events
WHERE channel = 'slack'
  AND message LIKE '%failed_permanently%'
ORDER BY created_at DESC
LIMIT 5;
```

期望：Slack 收到永久失败告警。

---

## 一次性回归检查清单（建议）

- [ ] Test 6: `resolved` + `resolved_at` + `leads` 新增
- [ ] Test 7: `retry_count` 增加、`pending` 保持、`next_retry_at` 正确退避
- [ ] Test 8: `failed_permanently` + Slack 告警

## 常见问题排查

1. **Worker 没有拾取记录**
   - 检查 `next_retry_at <= NOW()` 是否成立
   - 检查查询条件是否漏了租户/分区字段
   - 检查 worker 是否启用正确环境变量

2. **重试成功但状态未更新**
   - 检查事务提交
   - 检查状态更新 SQL 条件（是否按 `id + status='pending'` 乐观更新）

3. **退避时间异常**
   - 检查退避数组索引（0/1 起始混淆）
   - 检查时区和 `NOW()` 来源（应用层时间 vs DB 时间）

4. **Slack 没告警**
   - 检查告警开关、Webhook URL、失败分支是否真正触发
   - 建议在永久失败分支打印结构化日志（event_id, retry_count, max_retries）
