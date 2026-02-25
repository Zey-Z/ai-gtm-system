# 阶段 1：Webhook Trigger 配置指南

## 步骤 1：执行数据库迁移（5 分钟）

### 1.1 连接到 PostgreSQL

```bash
docker exec -it aigtm_postgres psql -U aigtm_user -d aigtm
```

### 1.2 执行迁移脚本

在 psql 命令行中执行：

```sql
-- 复制粘贴 db/migrations/001_add_run_id.sql 的内容
-- 或者直接在终端执行：

\i /docker-entrypoint-initdb.d/migrations/001_add_run_id.sql
```

**手动执行（如果上面的命令不work）：**

```sql
-- 1. 为 leads 表添加 run_id
ALTER TABLE leads ADD COLUMN IF NOT EXISTS run_id TEXT;

-- 2. 为 events 表添加 run_id
ALTER TABLE events ADD COLUMN IF NOT EXISTS run_id TEXT;

-- 3. 创建索引
CREATE INDEX IF NOT EXISTS idx_leads_run_id ON leads(run_id);
CREATE INDEX IF NOT EXISTS idx_events_run_id ON events(run_id);
```

### 1.3 验证迁移

```sql
-- 查看 leads 表结构（应该看到 run_id 列）
\d leads

-- 查看 events 表结构（应该看到 run_id 列）
\d events

-- 查看索引
\di idx_leads_run_id
\di idx_events_run_id
```

**预期结果：** 两个表都有 `run_id text` 列，并且有对应的索引。

### 1.4 退出 psql

```sql
\q
```

---

## 步骤 2：在 n8n 配置 Webhook Trigger（10 分钟）

### 2.1 打开 n8n Workflow

1. 访问 http://localhost:5678
2. 打开你的 "AI GTM 主流程" workflow

### 2.2 删除 Set 节点

1. 点击 **"1-输入测试数据"** 节点
2. 按 **Delete** 键删除

### 2.3 添加 Webhook 节点

1. 点击左上角的 **"+"** 按钮
2. 搜索 **"Webhook"**
3. 选择 **"Webhook"** 节点
4. 命名为：`1-接收Webhook请求`

### 2.4 配置 Webhook 节点

**参数配置：**

| 参数 | 值 | 说明 |
|------|---|------|
| **HTTP Method** | POST | 只接受 POST 请求 |
| **Path** | `lead-intake` | URL 路径（不要加 /） |
| **Authentication** | None | 暂不启用认证（后续可加） |
| **Response Mode** | Respond Immediately | 立即返回 200，不等处理完成 |
| **Response Code** | 200 | 成功状态码 |
| **Response Data** | Using Fields Below | 使用自定义响应 |

**Response Body（展开 "Response" 部分）：**

切换到 JSON 模式，输入：

```json
{
  "status": "received",
  "message": "Lead intake processing started"
}
```

### 2.5 保存 Webhook 配置

1. 点击 **"Execute Node"** 测试（会显示 "Waiting for Webhook call"）
2. 复制显示的 Webhook URL（类似 `http://localhost:5678/webhook/lead-intake`）
3. 点击 **"Stop Waiting"**

---

## 步骤 3：添加输入校验和 run_id 生成节点（15 分钟）

### 3.1 添加 Code 节点

1. 在 Webhook 节点后面点击 **"+"**
2. 搜索 **"Code"**
3. 选择 **"Code"** 节点
4. 命名为：`1.5-校验输入并生成run_id`

### 3.2 配置 Code 节点

**Mode:** Run Once for All Items

**JavaScript 代码：**

```javascript
// ===== 1. 获取请求数据 =====
const body = $input.item.json.body || $input.item.json;

// ===== 2. 校验必填字段 =====
if (!body.lead_text || body.lead_text.trim() === '') {
  throw new Error('Missing required field: lead_text');
}

// ===== 3. 生成 run_id（使用 n8n execution ID）=====
const run_id = $execution.id || 'local_' + Date.now();

// ===== 4. 生成 external_id（防止重复）=====
const timestamp = Date.now();
const randomStr = Math.random().toString(36).substring(2, 9);
const external_id = `lead_${timestamp}_${randomStr}`;

// ===== 5. 标准化输出 =====
return {
  json: {
    run_id: run_id,
    external_id: external_id,
    lead_text: body.lead_text.trim(),
    source: body.source || 'webhook',
    received_at: new Date().toISOString()
  }
};
```

### 3.3 测试 Code 节点

1. 点击 **"Execute Node"**
2. 应该会看到输出包含 `run_id`, `external_id`, `lead_text` 等字段

---

## 步骤 4：更新后续节点（15 分钟）

### 4.1 更新 "2-AI提取信息" 节点

**修改前置连接：**
- 从 **"1.5-校验输入并生成run_id"** 连接到 **"2-AI提取信息"**

**修改 Prompt（如果需要）：**
- 确保使用 `{{ $json.lead_text }}` 获取输入文本
- 如果之前是 `{{ $('1-输入测试数据').item.json.lead_text }}`，现在改为 `{{ $json.lead_text }}`

### 4.2 更新 "3-整理数据" Code 节点

**修改代码的开头部分：**

```javascript
// 获取 run_id（新增）
const run_id = $input.first().json.run_id;

// 获取 external_id（新增）
const external_id = $input.first().json.external_id;

// 获取 OpenAI 输出
const aiOutput = $input.item.json.output[0].content[0].text;

// ... 其余代码保持不变 ...

// 修改 return 部分，添加 run_id 和 external_id
return {
  json: {
    run_id: run_id,         // 新增
    external_id: external_id, // 修改（使用传递过来的，而非重新生成）
    raw_text: $('1.5-校验输入并生成run_id').item.json.lead_text, // 修改引用
    company: toNullable(extracted.company),
    contact_name: toNullable(extracted.contact_name),
    email: toNullable(extracted.email),
    budget: toNullable(extracted.budget),
    urgency: toNullable(extracted.urgency),
    score: score,
    status: 'new'
  }
};
```

### 4.3 更新 "4-写入数据库" Postgres 节点

**确认配置：**
- Operation: **Insert**
- Schema: **public**
- Table: **leads**
- Columns: **Auto-map**（应该自动包含 run_id）

**如果 Auto-map 没有包含 run_id，手动添加：**
- 关闭 Auto-map
- 手动添加字段映射：`run_id` → `{{ $json.run_id }}`

---

## 步骤 5：测试完整流程（10 分钟）

### 5.1 激活 Workflow

1. 点击右上角的 **"Inactive"** 切换为 **"Active"**
2. 确认 workflow 已激活

### 5.2 获取 Webhook URL

1. 点击 **"1-接收Webhook请求"** 节点
2. 复制 **Production URL**（类似 `http://localhost:5678/webhook/lead-intake`）

### 5.3 发送测试请求

**打开 Git Bash 或命令行：**

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{
    "lead_text": "我是ABC科技的张三，邮箱 zhangsan@abc.com，预算10万美元，希望两周内合作。"
  }'
```

**预期响应：**

```json
{
  "status": "received",
  "message": "Lead intake processing started"
}
```

### 5.4 验证数据库

```bash
# 连接数据库
docker exec -it aigtm_postgres psql -U aigtm_user -d aigtm

# 查询最新记录
SELECT run_id, external_id, company, email, score, created_at
FROM leads
ORDER BY created_at DESC
LIMIT 5;
```

**预期结果：**
- 应该看到新记录
- `run_id` 有值（类似 `execution_123456`）
- `external_id` 有值（类似 `lead_1771625000000_abc123`）
- 其他字段（company, email 等）已被 AI 提取

### 5.5 验证 n8n 执行历史

1. 在 n8n 中点击左侧菜单 **"Executions"**
2. 应该看到成功的执行记录
3. 点击查看详情，确认所有节点都成功执行

---

## 步骤 6：测试错误场景（5 分钟）

### 6.1 测试缺少必填字段

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{}'
```

**预期结果：**
- Webhook 应该立即返回 200（因为 Respond Immediately）
- 但在 Executions 中应该看到失败记录
- 错误信息：`Missing required field: lead_text`

### 6.2 测试空文本

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{
    "lead_text": ""
  }'
```

**预期结果：** 同样应该失败，因为 `.trim()` 后为空

---

## 常见问题

### Q1: Webhook URL 无法访问

**检查：**
1. Workflow 是否已激活（Active）
2. n8n 容器是否在运行：`docker ps`
3. 端口 5678 是否被占用

### Q2: 校验节点总是失败

**检查：**
1. 请求 Body 格式是否正确（必须是 JSON）
2. Content-Type 是否是 `application/json`
3. 节点中 `$input.item.json.body` 是否能获取到数据

**调试技巧：**
在 Code 节点开头添加：
```javascript
console.log('Raw input:', JSON.stringify($input.item.json, null, 2));
```

### Q3: run_id 为空

**检查：**
1. `$execution.id` 在你的 n8n 版本是否可用
2. 如果不可用，改用时间戳：`'run_' + Date.now()`

---

## 下一步

完成这个步骤后，进入 **阶段 1.5: events 表写入逻辑**，记录每个关键步骤的执行情况。

---

## 检查清单

- [ ] 数据库迁移成功（run_id 列存在）
- [ ] Webhook 节点配置完成
- [ ] 校验节点能捕获缺失字段错误
- [ ] run_id 和 external_id 正确生成
- [ ] 后续节点能获取 run_id
- [ ] 数据库写入包含 run_id
- [ ] 测试请求成功执行
- [ ] 错误场景能正确处理
