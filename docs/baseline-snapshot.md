# Baseline Snapshot — 优化前状态记录

> 记录于 2026-03-01，用于对比后续每步改进效果

## Git 状态

- **当前 commit**: `d8256dc` — Initial commit: AI-First GTM Lead Processing System
- **分支**: main
- **已追踪文件**: 19 个
- **未追踪文件**: 42 个（其中 37 个是 `tests/tmp_*.sql` 临时调试文件）

## 已追踪文件清单（19个）

```
.env.example
.gitignore
README.md
db/dlq-queries.sql
db/init.sql
db/migrations/001_add_run_id.sql
db/migrations/002_create_dlq.sql
db/migrations/003_add_idempotency.sql
docker-compose.yml
docs/dlq-operations.md
docs/n8n-postgres-setup.md
docs/postgres-parameterized-query-fix.md
docs/slack-setup-guide.md
docs/stage1-webhook-setup.md
docs/stage1.5-events-logging.md
tests/null-value-test.sql
tests/test-queries.sql
tests/test-webhook.ps1
workflows/AI-Lead-Extractor-v1.json
```

## 关键缺失（未进仓库的重要文件）

| 文件 | 说明 | 应该提交? |
|------|------|-----------|
| `workflows/DLQ-Retry-Worker.json` | DLQ 重试工作流 | YES |
| `workflows/Error-Handler.json` | 错误处理工作流 | YES |
| `recovery/pm_credentials.json` | 加密凭据备份 | NO (敏感) |
| `recovery/pm_workflows` | 工作流备份 | 待评估 |
| `dlq_test_6_8_runbook.md` | DLQ 测试手册 | YES (移入 docs/) |

## AI 组件现状

- **Prompt**: 基础指令式（zero-shot），无 few-shot 示例，无置信度评分
- **评分算法**: 简单关键词匹配（budget +30, urgency +20, email +10）
- **AI 输出验证**: 基础 JSON 格式检查

## README 现状

- 功能性 README，有 ASCII 架构图
- 缺少：量化结果指标、Mermaid 流程图、技术决策说明、演示示例

## 待改进汇总

1. 仓库整洁度：37 个临时文件需清理
2. AI 组件：Prompt 过于简单，评分算法原始
3. README：缺少面试导向的内容（量化指标、设计决策）
4. 文档：缺少架构文档和 Prompt Engineering 文档
5. 测试：无自动化测试套件
