# Slack 通知配置完整指南

## 目标
当系统检测到高质量潜在客户（score >= 70）时，自动发送 Slack 通知。

---

## 第一部分：创建 Slack Workspace 和 Incoming Webhook

### 步骤 1：访问 Slack

如果你还没有 Slack 账号，访问：https://slack.com/

- **有账号**：直接登录
- **没有账号**：点击 "Get Started" 创建账号（免费）

### 步骤 2：创建或选择 Workspace

1. 登录后，你会看到你的 Workspaces（工作区）
2. **如果没有 Workspace**：
   - 点击 "Create a Workspace"
   - 输入 Workspace 名称（比如 "AI GTM Test"）
   - 创建一个频道（比如 "leads-notifications"）
3. **如果已有 Workspace**：
   - 选择一个现有的 Workspace
   - 创建一个新频道用于测试（推荐命名：`#ai-leads`）

### 步骤 3：创建 Incoming Webhook

1. **访问 Slack Apps 页面**
   - 打开浏览器访问：https://api.slack.com/apps
   - 点击右上角 **"Create New App"（创建新应用）**

2. **选择创建方式**
   - 选择 **"From scratch"（从头开始）**
   - App Name（应用名称）：输入 `AI GTM Notifier`
   - Pick a workspace：选择你刚才创建或选择的 Workspace
   - 点击 **"Create App"**

3. **激活 Incoming Webhooks**
   - 在左侧菜单找到 **"Incoming Webhooks"**
   - 点击进入
   - 找到 **"Activate Incoming Webhooks"** 开关
   - **打开开关**（从 Off 切换到 On）

4. **添加 Webhook 到频道**
   - 页面往下滚动，找到 **"Webhook URLs for Your Workspace"** 部分
   - 点击 **"Add New Webhook to Workspace"** 按钮
   - 选择一个频道（比如 `#ai-leads` 或 `#general`）
   - 点击 **"Allow"（允许）**

5. **复制 Webhook URL**
   - 回到 Incoming Webhooks 页面
   - 你会看到一个新的 Webhook URL，格式类似：
     ```
     https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXX
     ```
   - **点击 "Copy"（复制）这个 URL**
   - ⚠️ **重要**：这个 URL 是敏感信息，不要分享给他人

### 步骤 4：测试 Webhook（可选但推荐）

在命令行（或 Git Bash）测试 Webhook 是否工作：

```bash
curl -X POST -H 'Content-type: application/json' \
--data '{"text":"Hello from AI GTM System! 🚀"}' \
YOUR_WEBHOOK_URL_HERE
```

把 `YOUR_WEBHOOK_URL_HERE` 替换成你复制的 Webhook URL。

如果成功，你会在 Slack 频道看到这条消息。

---

## 第二部分：在 n8n 配置 Slack 通知

### 步骤 1：添加 IF 条件节点

1. 在 n8n workflow 中，在 `4-写入数据库` 节点后面添加一个 **IF 节点**
2. 命名为：`5-判断是否高分`

**配置 IF 节点：**

| 字段 | 值 |
|------|---|
| **Conditions** | Value 1: `{{ $json.score }}` |
| **Operation** | Number → Larger or Equal |
| **Value 2** | `70` |

这个节点会判断：如果 score >= 70，走 "true" 分支；否则走 "false" 分支。

### 步骤 2：添加 Slack 节点（在 true 分支）

1. 在 IF 节点的 **true** 输出连接一个新节点
2. 搜索并添加 **"Slack"** 节点
3. 命名为：`6-发送Slack通知`

**配置 Slack 节点：**

**方法 A：使用 Webhook 模式（推荐，更简单）**

如果 Slack 节点有 "Send Message via Webhook" 选项：
- Resource: Webhook
- Operation: Send Message
- Webhook URL: 粘贴你的 Webhook URL

**方法 B：使用 HTTP Request 节点（通用方法）**

如果 Slack 节点配置复杂，可以用 **HTTP Request** 节点代替：

1. 删除 Slack 节点，改用 **HTTP Request** 节点
2. 命名为：`6-发送Slack通知`

**配置 HTTP Request 节点：**

| 字段 | 值 |
|------|---|
| **Method** | POST |
| **URL** | 粘贴你的 Webhook URL |
| **Body Content Type** | JSON |
| **Specify Body** | Using JSON |
| **JSON** | 见下方消息模板 |

**消息模板（JSON）：**

```json
{
  "text": "🎯 新的高质量潜在客户！",
  "blocks": [
    {
      "type": "header",
      "text": {
        "type": "plain_text",
        "text": "🎯 新的高质量潜在客户"
      }
    },
    {
      "type": "section",
      "fields": [
        {
          "type": "mrkdwn",
          "text": "*公司:*\n{{ $json.company || '未提供' }}"
        },
        {
          "type": "mrkdwn",
          "text": "*联系人:*\n{{ $json.contact_name || '未提供' }}"
        },
        {
          "type": "mrkdwn",
          "text": "*邮箱:*\n{{ $json.email || '未提供' }}"
        },
        {
          "type": "mrkdwn",
          "text": "*预算:*\n{{ $json.budget || '未提供' }}"
        },
        {
          "type": "mrkdwn",
          "text": "*紧急度:*\n{{ $json.urgency || '未提供' }}"
        },
        {
          "type": "mrkdwn",
          "text": "*质量评分:*\n{{ $json.score }}/100"
        }
      ]
    },
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*原始咨询内容:*\n{{ $json.raw_text }}"
      }
    },
    {
      "type": "context",
      "elements": [
        {
          "type": "mrkdwn",
          "text": "📋 Lead ID: {{ $json.external_id }}"
        }
      ]
    }
  ]
}
```

**注意：** 如果 n8n 不支持 `||` 语法，用简化版：

```json
{
  "text": "🎯 新的高质量潜在客户！",
  "attachments": [
    {
      "color": "#36a64f",
      "fields": [
        {
          "title": "公司",
          "value": "{{ $json.company }}",
          "short": true
        },
        {
          "title": "联系人",
          "value": "{{ $json.contact_name }}",
          "short": true
        },
        {
          "title": "邮箱",
          "value": "{{ $json.email }}",
          "short": true
        },
        {
          "title": "预算",
          "value": "{{ $json.budget }}",
          "short": true
        },
        {
          "title": "质量评分",
          "value": "{{ $json.score }}/100",
          "short": true
        },
        {
          "title": "原始咨询",
          "value": "{{ $json.raw_text }}",
          "short": false
        }
      ]
    }
  ]
}
```

### 步骤 3：连接工作流

完整的节点连接顺序：

```
1-输入测试数据 (Set)
  ↓
2-AI提取信息 (OpenAI)
  ↓
3-整理数据 (Code)
  ↓
4-写入数据库 (Postgres - Insert)
  ↓
5-判断是否高分 (IF)
  ├─ true → 6-发送Slack通知 (HTTP Request)
  └─ false → (不做任何操作，流程结束)
```

---

## 第三部分：测试 Slack 通知

### 测试步骤

1. 在 `1-输入测试数据` 节点，使用高分测试数据：
   ```
   我是ABC科技有限公司的张三，邮箱是 zhangsan@abc.com。我们预算大概10万美元，希望两周内能确定方案并开始实施。
   ```

2. 点击 **"Test workflow"**

3. 检查结果：
   - ✅ 工作流成功执行
   - ✅ 数据写入数据库（score = 100）
   - ✅ IF 节点走了 true 分支
   - ✅ **Slack 频道收到通知消息**

### 常见问题

**Q1: Slack 节点报错 "Invalid Webhook URL"**
- 检查 Webhook URL 是否完整复制
- 确保 URL 以 `https://hooks.slack.com/services/` 开头

**Q2: 收不到 Slack 消息**
- 检查 Webhook 是否激活（在 Slack API 页面）
- 用 curl 命令单独测试 Webhook 是否工作
- 检查 IF 节点是否走了 true 分支

**Q3: 消息格式乱码**
- 检查 JSON 格式是否正确（使用 JSONLint 验证）
- 确保 Content-Type 是 `application/json`

---

## 安全提示

⚠️ **Webhook URL 是敏感信息**
- 不要上传到 GitHub（已在 .gitignore 排除）
- 不要分享给他人
- 如果泄露，可以在 Slack API 页面重新生成

---

## 下一步

配置完成后，你可以：
1. 测试不同评分的数据（低分不触发通知，高分触发通知）
2. 自定义 Slack 消息格式（添加表情、颜色等）
3. 添加更多通知渠道（邮件、微信等）
