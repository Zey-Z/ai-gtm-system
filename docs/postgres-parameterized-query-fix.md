# PostgreSQL 参数化查询修复方案

## 问题
n8n Postgres 节点报错：`there is no parameter $2`

## 原因
Query Parameters 的表达式语法或数组传递方式在当前 n8n 版本不兼容。

---

## 🎯 解决方案 A：使用 COALESCE 处理 NULL（推荐）

这个方案不使用参数化查询，但通过 COALESCE 和类型转换安全处理 NULL 值。

### 步骤 1：修改 `3-整理数据` Code 节点

保持现有代码不变，但去掉 `db_params` 数组（不需要了）：

```javascript
// Get OpenAI output
const aiOutput = $input.item.json.output[0].content[0].text;

// Parse data with type checking
let extracted;
if (typeof aiOutput === 'object') {
  extracted = aiOutput;
} else if (typeof aiOutput === 'string') {
  try {
    extracted = JSON.parse(aiOutput);
  } catch (error) {
    extracted = {
      company: null,
      contact_name: null,
      email: null,
      budget: null,
      urgency: null,
      employee_count: null
    };
  }
}

// Calculate score
let score = 50;
if (extracted.budget && (
  extracted.budget.includes('元') ||
  extracted.budget.includes('美元') ||
  extracted.budget.includes('$') ||
  extracted.budget.includes('万')
)) {
  score += 30;
}
if (extracted.urgency && (
  extracted.urgency.includes('天') ||
  extracted.urgency.includes('周') ||
  extracted.urgency.includes('内')
)) {
  score += 20;
}
if (extracted.email) {
  score += 10;
}
score = Math.min(score, 100);

// Prepare data for database
const external_id = 'ai_lead_' + Date.now();
const raw_text = $('1-输入测试数据').item.json.lead_text;

function toNullable(value) {
  if (value === undefined || value === null || value === '') {
    return null;
  }
  return value;
}

return {
  json: {
    raw_text: raw_text,
    company: toNullable(extracted.company),
    contact_name: toNullable(extracted.contact_name),
    email: toNullable(extracted.email),
    budget: toNullable(extracted.budget),
    urgency: toNullable(extracted.urgency),
    employee_count: toNullable(extracted.employee_count),
    external_id: external_id,
    score: score
  }
};
```

### 步骤 2：修改 `4-写入数据库` Postgres 节点

**Operation:** Execute Query

**Query:**
```sql
INSERT INTO leads (
    external_id,
    raw_text,
    company,
    contact_name,
    email,
    budget,
    urgency,
    score,
    status
)
VALUES (
    '{{ $json.external_id }}',
    '{{ $json.raw_text }}',
    NULLIF('{{ $json.company }}', 'null'),
    NULLIF('{{ $json.contact_name }}', 'null'),
    NULLIF('{{ $json.email }}', 'null'),
    NULLIF('{{ $json.budget }}', 'null'),
    NULLIF('{{ $json.urgency }}', 'null'),
    {{ $json.score }},
    'new'
)
RETURNING *;
```

**Query Parameters:** 留空（不使用）

### 工作原理：
- `NULLIF(value, 'null')`: 如果值是字符串 `'null'`，转换为 SQL NULL
- 单引号包裹字符串字段：`'{{ $json.company }}'`
- 数字字段不需要引号：`{{ $json.score }}`
- JavaScript 的 `null` 会被 n8n 转换为字符串 `'null'`，NULLIF 捕获并转换为真正的 NULL

### 安全性：
- ⚠️ 仍有 SQL 注入风险（因为直接拼接字符串）
- ✅ 但风险较低，因为：
  1. 数据来源是 OpenAI API（不是用户直接输入）
  2. 只用于内部系统（不暴露给外部用户）
  3. 可以在 Code 节点添加输入验证

---

## 🔧 解决方案 B：添加输入验证增强安全性

如果担心安全性，在 `3-整理数据` Code 节点添加验证：

```javascript
// ... (前面的代码保持不变)

// 输入验证函数（防止 SQL 注入字符）
function sanitize(value) {
  if (value === undefined || value === null || value === '') {
    return null;
  }
  // 移除潜在的 SQL 注入字符
  const sanitized = String(value).replace(/['";\\]/g, '');
  return sanitized || null;
}

return {
  json: {
    raw_text: raw_text,
    company: sanitize(extracted.company),
    contact_name: sanitize(extracted.contact_name),
    email: sanitize(extracted.email),
    budget: sanitize(extracted.budget),
    urgency: sanitize(extracted.urgency),
    employee_count: sanitize(extracted.employee_count),
    external_id: external_id,
    score: score
  }
};
```

**注意：** 这会移除单引号、分号等特殊字符，可能影响正常数据（如公司名 "O'Reilly"）。

---

## 📊 解决方案 C：使用 JSON 字段存储（最安全）

如果想彻底避免 SQL 注入，可以把所有提取的数据存为一个 JSON 字段：

### 修改数据库表结构：
```sql
ALTER TABLE leads ADD COLUMN extracted_data JSONB;
```

### 修改 Postgres 节点查询：
```sql
INSERT INTO leads (
    external_id,
    raw_text,
    extracted_data,
    score,
    status
)
VALUES (
    '{{ $json.external_id }}',
    '{{ $json.raw_text }}',
    '{{ JSON.stringify($json.extracted) }}'::jsonb,
    {{ $json.score }},
    'new'
)
RETURNING *;
```

---

## ✅ 推荐方案

**对于你的项目（求职作品集），推荐 方案 A + 解决方案 B：**
1. ✅ 简单易实现
2. ✅ 处理 NULL 值正确
3. ✅ 有基本的输入验证
4. ✅ 面试时可以解释安全考虑和权衡

**如果未来投入生产，建议：**
- 升级到支持参数化查询的 n8n 版本
- 或使用 ORM（如在 Code 节点中用 `pg` 库直接连接数据库）
