# Purview Lab Deployer — Tasks

## Phase 1: Scaffolding
- [x] Init repo, .gitignore, CLAUDE.md, README.md
- [x] Logging.psm1
- [x] Prerequisites.psm1
- [x] Deploy-Lab.ps1 orchestrator
- [x] Remove-Lab.ps1 orchestrator
- [x] full-demo.json config
- [x] _schema.json config validation

## Phase 2: Users & Groups
- [x] TestUsers.psm1 — deploy + teardown

## Phase 3: Core Workloads
- [x] DLP.psm1
- [x] SensitivityLabels.psm1
- [x] Retention.psm1

## Phase 4: Advanced Workloads
- [x] EDiscovery.psm1
- [x] CommunicationCompliance.psm1
- [x] InsiderRisk.psm1

## Phase 5: Test Data & Polish
- [x] TestData.psm1
- [x] Additional configs (dlp-only.json, ediscovery-retention.json)
- [x] GitHub Actions validation workflow
- [x] README.md finalized

## Phase 6: Microsoft Foundry + AI Governance
- [x] modules/Foundry.psm1 — ARM provisioning (account, model, project, agents) + teardown
- [x] Prerequisites.psm1 — Az.Accounts check (gated on foundry enabled + not SkipAuth)
- [x] Deploy-Lab.ps1 — foundry workload dispatch (step 8, after InsiderRisk)
- [x] Remove-Lab.ps1 — foundry removal (before InsiderRisk, reverse order)
- [x] configs/commercial/_schema.json — foundry workload block
- [x] configs/gcc/_schema.json — foundry workload block
- [x] profiles/commercial/capabilities.json — foundry available; auditConfig + conditionalAccess entries
- [x] profiles/gcc/capabilities.json — foundry limited; auditConfig + conditionalAccess entries
- [x] configs/commercial/foundry-demo.json — full Foundry AI governance demo config
- [x] Lint clean (PSScriptAnalyzer zero warnings)
- [x] Dry run verified (-SkipAuth -WhatIf passes)
