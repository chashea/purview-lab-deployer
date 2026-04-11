# Foundry AI Governance Demo — Commercial Deployment Guide

**Tagline:** "We're not blocking AI — we're proving it's governed, auditable, and compliant from day one."

## Scenario Overview

This lab deploys Microsoft AI Foundry agents into an Azure subscription and wraps them with the full Microsoft Purview governance stack: DLP policies for AI prompts, sensitivity labels that control what agents can access, insider risk policies for risky AI usage, and audit/eDiscovery evidence for compliance investigations.

| Component | Count | Details |
|---|---|---|
| Test users | 5 | Alicia Hernandez (HR), Brian Wallace (Finance), Chris Park (IT), Diana Morgan (Sales), Ethan Patel (Executive) |
| Security groups | 3 | Finance-Team, IT-Team, Sales-Team |
| Foundry agents | 4 | HR-Helpdesk, Finance-Analyst, IT-Support, Sales-Research |
| Azure AI Services | 1 account, 1 project | pvfoundry-lab / pvfoundry-project (swedencentral) |
| Model deployment | 1 | gpt-4o |
| Bot Service | 1 | Teams app catalog publishing for all 4 agents |
| Sensitivity labels | 2 parents, 4 sublabels | Confidential (AI-Accessible, AI-Protected), Highly Confidential (AI-Restricted, Executives-Only) |
| Auto-label policies | 1 | SSN content -> Confidential\AI-Protected |
| DLP policies | 3 | PII Prompt Protection (EnterpriseAI), Sensitivity Label Block (CopilotExperiences), Endpoint Shadow AI Block (Devices) |
| Retention policies | 1 | AI Interaction Retention (365 days) |
| eDiscovery cases | 1 | AI-Governance-Investigation with custodians and hold |
| Communication compliance | 1 | Foundry AI Interaction Monitoring |
| Insider risk | 1 | Foundry AI Risky Usage (priority user groups) |
| Audit searches | 2 | CopilotInteraction, DLP violations |

## Prerequisites

- Microsoft 365 E5 (or E5 Compliance add-on)
- Azure subscription with Contributor access to the target resource group
- `Az.Accounts` PowerShell module (`Install-Module Az.Accounts -Scope CurrentUser`)
- Purview permissions: Compliance Administrator, User Administrator, eDiscovery Administrator
- Azure AI Foundry: resource provider registered (`Microsoft.CognitiveServices`)

## Quick Start

```powershell
# Deploy (creates Azure AI resources + Purview policies + test users)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile foundry -TenantId <tenant-guid>

# Deploy without test users (use existing tenant accounts)
./Deploy-Lab.ps1 -Cloud commercial -LabProfile foundry -TenantId <tenant-guid> -SkipTestUsers

# Dry run
./Deploy-Lab.ps1 -Cloud commercial -LabProfile foundry -WhatIf

# Teardown (removes Azure resources + Purview policies)
./Remove-Lab.ps1 -Cloud commercial -LabProfile foundry -Confirm:$false -TenantId <tenant-guid>
```

## What Gets Deployed

### Azure AI Foundry (deploys first)

1. **Azure AI Services account** (`pvfoundry-lab`) in `rg-pvfoundry-demo` (swedencentral)
2. **AI Foundry project** (`pvfoundry-project`) linked to the account
3. **gpt-4o model deployment** provisioned on the account
4. **4 AI agents** created in the project:
   - **HR-Helpdesk** — HR policy, benefits, and PTO assistant
   - **Finance-Analyst** — Financial data analysis and reporting
   - **IT-Support** — IT helpdesk and system access
   - **Sales-Research** — Market research and competitive intelligence
5. **Bot Service + Teams publishing** — each agent published as a Teams app

### Sensitivity Labels (AI-aware)

| Parent | Sublabel | Encryption | AI Access |
|---|---|---|---|
| Confidential | AI-Accessible | No | Full (RAG + indexing) |
| Confidential | AI-Protected | Yes | User-context only |
| Highly Confidential | AI-Restricted | Yes | Blocked from AI |
| Highly Confidential | Executives-Only | Yes | Blocked from AI |

### DLP Policies (3 policies, tiered by insider risk level)

| Policy | Location | Rules |
|---|---|---|
| Foundry AI - PII Prompt Protection | EnterpriseAI | Block (Elevated), Warn (Moderate), Audit (Minor) — SSN, credit card, bank account, medical terms |
| Foundry AI - Sensitivity Label Block | CopilotExperiences | Block AI-Restricted content, Block Executives-Only content |
| Foundry AI - Endpoint Shadow AI Block | Devices | Block uploads to ChatGPT, Claude, Gemini, Copilot, Perplexity, HuggingFace Chat |

### Retention, eDiscovery, Compliance

- **AI Interaction Retention** — 365 days, Exchange + OneDrive
- **AI-Governance-Investigation** — eDiscovery case with 4 custodians, hold query for AI/Copilot terms
- **Foundry AI Interaction Monitoring** — Communication compliance for AI agent interactions
- **Foundry AI Risky Usage** — Insider risk policy targeting Finance-Team and Sales-Team

## Deployment Order

1. Foundry (Azure AI account, project, agents, Teams publishing)
2. TestUsers (5 users, 3 groups)
3. SensitivityLabels (2 parents, 4 sublabels, 1 auto-label policy)
4. DLP (3 policies with insider risk tiering)
5. Retention (1 policy)
6. eDiscovery (1 case)
7. CommunicationCompliance (1 policy)
8. InsiderRisk (1 policy)
9. AuditConfig (2 searches)

Removal reverses this order (Foundry removed last).

## Key Technical Notes

- Foundry deploys first because Purview policies govern the agents it creates
- DLP rules use insider risk level tiering (Elevated/Moderate/Minor) for graduated enforcement
- The `EnterpriseAI` DLP location targets Foundry agent prompts; `CopilotExperiences` targets Copilot interactions with labeled content
- Endpoint DLP blocks uploads to 7 shadow AI sites via browser restrictions
- Azure resources are created via ARM REST API (not Az PowerShell cmdlets) for granular control
