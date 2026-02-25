# AI-First GTM Lead Processing System

An end-to-end AI-powered Go-To-Market lead processing pipeline built with n8n, OpenAI, PostgreSQL, HubSpot CRM, and Slack.

## What It Does

Automatically processes incoming sales leads through an intelligent pipeline:

```
Webhook Input → AI Extraction → Database Storage → CRM Sync → Team Notification
```

1. **Receives** lead inquiries via webhook
2. **Extracts** structured data (company, contact, email, budget, urgency) using OpenAI
3. **Scores** lead quality (0-100) based on budget clarity, urgency, and completeness
4. **Stores** all leads in PostgreSQL with idempotency protection
5. **Syncs** high-quality leads (score ≥ 70) to HubSpot CRM
6. **Notifies** the sales team via Slack with a clickable HubSpot link

## Architecture

```
┌─────────────┐     ┌──────────────┐     ┌────────────┐
│   Webhook   │────▶│  Input       │────▶│  OpenAI    │
│   (POST)    │     │  Validation  │     │  GPT-3.5   │
└─────────────┘     └──────────────┘     └─────┬──────┘
                                               │
                    ┌──────────────┐     ┌──────▼──────┐
                    │  Score Check │◀────│  PostgreSQL │
                    │  (IF ≥ 70)   │     │  UPSERT     │
                    └──┬───────┬───┘     └─────────────┘
                       │       │
              ┌────────▼┐   ┌─▼─────────┐
              │ HubSpot │   │ Log Low   │
              │ Upsert  │   │ Score     │
              └────┬────┘   └───────────┘
                   │
              ┌────▼────┐
              │  Slack  │
              │ Notify  │
              └─────────┘
```

## Tech Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| Orchestration | n8n | Workflow automation |
| AI | OpenAI GPT-3.5 Turbo | Information extraction & scoring |
| Database | PostgreSQL 16 | Lead storage & event logging |
| CRM | HubSpot (Private App) | Contact management |
| Notifications | Slack Webhooks | Real-time team alerts |
| Deployment | Docker Compose | Local development |

## Quick Start

### Prerequisites

- Docker & Docker Compose
- OpenAI API key
- HubSpot account with Private App ([setup guide](docs/hubspot-setup.md))
- Slack workspace with Incoming Webhook ([setup guide](docs/slack-setup-guide.md))

### 1. Clone & Configure

```bash
git clone https://github.com/Zey-Z/ai-gtm-system.git
cd ai-gtm-system
cp .env.example .env
# Edit .env with your credentials
```

### 2. Start Services

```bash
docker-compose up -d
```

This starts PostgreSQL (port 5432) and n8n (port 5678).

### 3. Import Workflow

1. Open n8n at `http://localhost:5678`
2. Go to **Settings → Import from File**
3. Select `workflows/AI-Lead-Extractor-v1.json`
4. Configure credentials in n8n:
   - OpenAI API key
   - PostgreSQL connection
   - HubSpot Private App token
   - Slack Webhook URL

### 4. Test

```bash
curl -X POST http://localhost:5678/webhook/lead-intake \
  -H "Content-Type: application/json" \
  -d '{"lead_text":"We are TechStartup Inc, interested in your enterprise AI solution. I am Sarah Chen, email sarah.chen@techstartup.com. Our budget is around $75000, hoping to start within two weeks."}'
```

**PowerShell:**
```powershell
Invoke-WebRequest -Uri "http://localhost:5678/webhook/lead-intake" `
  -Method POST -ContentType "application/json" `
  -Body '{"lead_text":"We are TechStartup Inc, interested in your enterprise AI solution. I am Sarah Chen, email sarah.chen@techstartup.com. Our budget is around $75000, hoping to start within two weeks."}'
```

## Workflow Nodes

| Node | Name | Function |
|------|------|----------|
| 1 | Receive-Webhook | HTTP POST endpoint |
| 1.5 | Validate-Input-Generate-RunID | Input validation & idempotency key |
| 1.6 | Validation-Result-Check | Route valid/invalid inputs |
| 2 | AI-Extract-Info | OpenAI structured extraction |
| 2.5 | Validate-AI-Output | Verify AI response format |
| 3 | Prepare-Data | Transform & score lead data |
| 4 | Write-to-Database | PostgreSQL UPSERT with conflict handling |
| 5 | Check-High-Score | Route by score threshold (≥ 70) |
| 6 | HubSpot-Contact-Upsert | Create/update CRM contact |
| 6.7 | Prepare-Slack-Data | Format notification payload |
| 7 | Send-Slack-Notification | POST to Slack webhook |

## Key Features

- **Idempotency**: SHA256-based deduplication prevents duplicate lead processing
- **UPSERT**: Database and HubSpot both handle create-or-update seamlessly
- **Event Logging**: Every pipeline step is logged for full audit trail
- **Score-Based Routing**: Only high-quality leads sync to CRM and trigger notifications
- **Error Handling**: Dead Letter Queue for failed processing with retry support

## Database Schema

See [db/init.sql](db/init.sql) for the base schema and [db/migrations/](db/migrations/) for incremental changes:

- `001_add_run_id.sql` - End-to-end request tracing
- `002_create_dlq.sql` - Dead Letter Queue with exponential backoff
- `003_add_idempotency.sql` - SHA256 idempotency keys

## Documentation

- [PostgreSQL Setup](docs/n8n-postgres-setup.md)
- [Slack Integration](docs/slack-setup-guide.md)
- [Stage 1: Webhook Setup](docs/stage1-webhook-setup.md)
- [Event Logging](docs/stage1.5-events-logging.md)
- [DLQ Operations](docs/dlq-operations.md)
- [Query Parameter Fix](docs/postgres-parameterized-query-fix.md)

## License

MIT
