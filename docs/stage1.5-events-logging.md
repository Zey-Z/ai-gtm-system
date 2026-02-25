# 阶段 1.5：Events 审计日志配置指南

## 目标
在关键步骤添加 events 表写入，记录完整的执行链路，方便追踪和排查问题。

---

## 为什么需要 Events 审计日志？

**场景示例：**
- 客户投诉："我昨天提交了表单，为什么没收到回复？"
- 你可以用 run_id 查询 events 表，看到：
  - ✅ webhook_received - 成功
  - ✅ ai_extract_completed - 成功
  - ❌ slack_notification_sent - 失败（找到问题了！）

**好处：**
1. 🔍 **可追溯** - 每次执行都有完整记录
2. 🐛 **易排查** - 快速定位失败步骤
3. 📊 **可分析** - 统计成功率、耗时等指标
4. 💼 **面试加分** - 展示工程化思维

---

## 步骤 1：验证 events 表结构（2 分钟）

### 1.1 连接数据库

```bash
docker exec -it aigtm_postgres psql -U aigtm_user -d aigtm
```

### 1.2 查看 events 表结构

```sql
\d events
```

**预期输出：**
```
                                      Table "public.events"
     Column     |            Type             | Collation | Nullable |              Default
----------------+-----------------------------+-----------+----------+-----------------------------------
 id             | integer                     |           | not null | nextval('events_id_seq'::regclass)
 lead_id        | integer                     |           |          |
 step           | text                        |           | not null |
 status         | text                        |           | not null |
 error_message  | text                        |           |          |
 created_at     | timestamp without time zone |           |          | now()
 run_id         | text                        |           |          |
```

**重点检查：**
- ✅ `run_id` 列存在（如果你执行了 001_add_run_id.sql 迁移）
- ✅ `step` 和 `status` 是 NOT NULL
- ✅ `lead_id` 可以为 NULL（因为早期步骤还没有 lead_id）

### 1.3 退出数据库

```sql
\q
```

---

## 步骤 2：添加第一个 Event 记录节点（15 分钟）

### 2.1 在哪里添加？

在 **"1.5-校验输入并生成run_id"** 节点之后添加。

**Workflow 结构：**
```
1-接收Webhook请求 (Webhook)
  ↓
1.5-校验输入并生成run_id (Code)
  ↓
📝 [新增] 1.6-记录webhook接收 (Postgres Insert)  ← 我们现在添加这个
  ↓
2-AI提取信息 (OpenAI)
  ↓
...
```

### 2.2 添加 Postgres 节点

1. 在 **"1.5-校验输入并生成run_id"** 节点后面点击 **"+"**
2. 搜索 **"Postgres"**
3. 选择 **"Postgres"** 节点
4. 命名为：`1.6-记录webhook接收`

### 2.3 配置 Postgres 节点

**Credential（凭证）：** 选择你已有的 PostgreSQL 凭证

**Operation（操作）：** Insert

**Schema:** public

**Table:** events

**Columns:** 点击 "Add Column" 手动添加以下字段：

| Column | Value |
|--------|-------|
| `run_id` | `{{ $json.run_id }}` |
| `lead_id` | 留空（NULL，因为此时还没插入 leads 表） |
| `step` | `webhook_received` |
| `status` | `success` |
| `error_message` | 留空（NULL） |

**注意：**
- ✅ `step` 和 `status` 用**固定字符串**，不需要 `{{ }}` 包裹
- ✅ `run_id` 使用 `{{ $json.run_id }}`（来自 1.5 节点）
- ✅ `created_at` 不需要填写（数据库自动生成）

### 2.4 连接节点

将 **"1.6-记录webhook接收"** 连接到 **"2-AI提取信息"**：

```
1.5-校验输入并生成run_id
  ↓
1.6-记录webhook接收
  ↓
2-AI提取信息
```

### 2.5 测试

1. 发送测试请求：
   ```bash
   curl.exe -X POST "http://localhost:5678/webhook/lead-intake" `
     -H "Content-Type: application/json; charset=utf-8" `
     -d '{\"lead_text\": \"测试审计日志功能\"}'
   ```

2. 查询 events 表：
   ```bash
   docker exec -it aigtm_postgres psql -U aigtm_user -d aigtm
   ```

   ```sql
   SELECT run_id, step, status, created_at
   FROM events
   ORDER BY created_at DESC
   LIMIT 5;
   ```

**预期结果：**
```
 run_id | step             | status  | created_at
--------|------------------|---------|-------------------
 355    | webhook_received | success | 2024-02-20 14:30:00
```

---

## 步骤 3：添加第二个 Event 记录节点（10 分钟）

### 3.1 位置

在 **"4-写入数据库"** 节点之后添加。

### 3.2 添加并配置节点

1. 在 "4-写入数据库" 后点击 **"+"**
2. 添加 **Postgres** 节点
3. 命名：`4.5-记录lead创建`

**Columns 配置：**

| Column | Value |
|--------|-------|
| `run_id` | `{{ $json.run_id }}` |
| `lead_id` | `{{ $json.id }}` |
| `step` | `lead_created` |
| `status` | `success` |
| `error_message` | 留空 |

**重点：**
- ✅ `lead_id` 使用 `{{ $json.id }}`（这是 "4-写入数据库" 节点返回的 lead ID）
- ✅ 如果 "4-写入数据库" 使用了 `RETURNING *`，会自动返回插入的记录（包含 `id`）

### 3.3 连接节点

修改连接顺序：

**修改前：**
```
4-写入数据库 → 5-判断是否高分
```

**修改后：**
```
4-写入数据库 → 4.5-记录lead创建 → 5-判断是否高分
```

---

## 步骤 4：添加第三个 Event 记录节点（10 分钟）

### 4.1 位置

在 **"6-发送Slack通知"** 节点之后添加（仅在 true 分支）。

### 4.2 添加并配置节点

1. 在 "6-发送Slack通知" 后点击 **"+"**
2. 添加 **Postgres** 节点
3. 命名：`6.5-记录通知发送`

**Columns 配置：**

| Column | Value |
|--------|-------|
| `run_id` | `{{ $('1.5-校验输入并生成run_id').item.json.run_id }}` |
| `lead_id` | `{{ $('4-写入数据库').item.json.id }}` |
| `step` | `notification_sent` |
| `status` | `success` |
| `error_message` | 留空 |

**注意：**
- ⚠️ 在这个节点，我们需要**向前引用**之前的节点数据
- ✅ 使用 `$('节点名称').item.json.字段` 语法

### 4.3 连接节点

```
5-判断是否高分 (IF)
  ├─ true → 6-发送Slack通知 → 6.5-记录通知发送
  └─ false → (不做任何操作)
```

---

## 步骤 5：完整测试（10 分钟）

### 5.1 测试高分 lead（触发 Slack 通知）

```bash
curl.exe -X POST "http://localhost:5678/webhook/lead-intake" `
  -H "Content-Type: application/json; charset=utf-8" `
  -d '{\"lead_text\": \"我是ABC科技的张三，邮箱zhangsan@abc.com，预算10万美元，希望两周内合作。\"}'
```

### 5.2 查询 events 表

```sql
-- 查询最新的一次执行（假设 run_id = 356）
SELECT run_id, step, status, created_at
FROM events
WHERE run_id = '356'
ORDER BY created_at;
```

**预期结果（高分 lead）：**
```
 run_id | step                 | status  | created_at
--------|----------------------|---------|-------------------
 356    | webhook_received     | success | 2024-02-20 14:35:00
 356    | lead_created         | success | 2024-02-20 14:35:05
 356    | notification_sent    | success | 2024-02-20 14:35:08
```

### 5.3 测试低分 lead（不触发 Slack 通知）

```bash
curl.exe -X POST "http://localhost:5678/webhook/lead-intake" `
  -H "Content-Type: application/json; charset=utf-8" `
  -d '{\"lead_text\": \"我想了解一下你们的产品\"}'
```

**预期结果（低分 lead）：**
```
 run_id | step                 | status  | created_at
--------|----------------------|---------|-------------------
 357    | webhook_received     | success | 2024-02-20 14:36:00
 357    | lead_created         | success | 2024-02-20 14:36:05
```

（注意：没有 `notification_sent` 记录，因为走了 false 分支）

---

## 步骤 6：验证链路追踪（5 分钟）

### 6.1 查询特定 run_id 的完整执行链路

```sql
-- 替换为你的 run_id
SELECT
    e.step,
    e.status,
    e.created_at,
    l.company,
    l.email,
    l.score
FROM events e
LEFT JOIN leads l ON e.lead_id = l.id
WHERE e.run_id = '356'
ORDER BY e.created_at;
```

### 6.2 统计分析查询

```sql
-- 查看每个步骤的成功次数
SELECT step, COUNT(*) as count
FROM events
WHERE status = 'success'
GROUP BY step
ORDER BY count DESC;
```

**预期输出：**
```
 step                 | count
----------------------|-------
 webhook_received     | 10
 lead_created         | 10
 notification_sent    | 7
```

（说明：10 次请求，7 次触发了 Slack 通知）

---

## 常见问题

### Q1: "4-写入数据库" 节点没有返回 `id`

**检查：**
1. Operation 是 **Insert** 吗？
2. 是否勾选了 **Return Fields**？
3. 或者 SQL 查询是否包含 `RETURNING *`？

**解决方案：**
如果使用 Insert 模式，n8n 默认会返回插入的记录（包含 `id`）。

如果没有返回，可以在 "4.5-记录lead创建" 节点中用 `NULL` 代替 `lead_id`：
```
lead_id: NULL
```

然后在后续优化时，通过 `external_id` 关联 leads 表。

### Q2: "6.5-记录通知发送" 找不到 run_id

**检查：**
确保使用了**向前引用语法**：
```javascript
{{ $('1.5-校验输入并生成run_id').item.json.run_id }}
```

而不是：
```javascript
{{ $json.run_id }}  // ❌ 错误：Slack 节点输出里没有 run_id
```

### Q3: events 表记录太多，怎么清理？

**开发阶段清理命令：**
```sql
-- 删除所有测试数据（谨慎使用！）
DELETE FROM events WHERE step = 'webhook_received';

-- 只保留最近 100 条记录
DELETE FROM events
WHERE id NOT IN (
  SELECT id FROM events ORDER BY created_at DESC LIMIT 100
);
```

**生产环境建议：**
- 定期归档到历史表
- 或者添加自动清理策略（保留 30 天）

---

## 检查清单

完成阶段 1.5 后，确认：

- [ ] events 表有 run_id 列
- [ ] "1.6-记录webhook接收" 节点添加成功
- [ ] "4.5-记录lead创建" 节点添加成功，包含 lead_id
- [ ] "6.5-记录通知发送" 节点添加成功（仅 true 分支）
- [ ] 测试高分 lead，events 表有 3 条记录
- [ ] 测试低分 lead，events 表有 2 条记录
- [ ] 可以用 run_id 查询完整执行链路

---

## 下一步

完成阶段 1.5 后：
1. **阶段 1 验收测试** - 测试边界情况（空输入、重复提交等）
2. **阶段 2** - 错误处理和 DLQ（Dead Letter Queue）
3. **阶段 3** - HubSpot CRM 集成

---

## 💡 面试亮点

当面试官问："你的系统如何保证可追溯性？"

**你可以这样回答：**
> "我设计了完整的审计日志系统。每个关键步骤（webhook 接收、AI 提取、数据库写入、通知发送）都会写入 events 表，并用 run_id 关联。这样：
> 1. 可以追踪任何一次请求的完整执行链路
> 2. 快速定位失败步骤（比如 AI 超时、Slack 通知失败）
> 3. 统计分析（成功率、平均耗时等）
>
> 在企业级系统中，这是必备的工程实践，我在这个项目中实现了简化版本。"
