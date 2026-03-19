# Shadow AI Demo — Manual Configuration Runbook

Steps that require portal access after automated deployment.

## Prerequisites

- Global Admin or Compliance Admin role
- Microsoft 365 E5 or E5 Compliance add-on

## 1. Endpoint DLP Browser Restrictions

**Portal:** Microsoft Purview > Data Loss Prevention > Endpoint DLP settings

1. Navigate to **Browser and domain restrictions**
2. Under **Service domains**, add the following AI tool domains:
   - `chat.openai.com`
   - `chatgpt.com`
   - `claude.ai`
   - `gemini.google.com`
   - `bard.google.com`
   - `poe.com`
   - `perplexity.ai`
   - `huggingface.co`
3. Set action to **Block** or **Audit** depending on demo mode
4. Ensure Microsoft Edge is configured as the allowed browser

## 2. Conditional Access Policies

**Portal:** Microsoft Entra admin center > Protection > Conditional Access

### Policy 1: Block AI for High-Risk Users
1. **Create new policy**
2. Users: All users (or pilot group)
3. Cloud apps: Select AI enterprise applications (if registered)
4. Conditions: Sign-in risk = High
5. Grant: Block access
6. Enable in **Report-only** mode first

### Policy 2: Require MFA for AI Access
1. **Create new policy**
2. Users: All users
3. Cloud apps: Select AI enterprise applications
4. Grant: Require multifactor authentication
5. Enable in **Report-only** mode first

## 3. Activity Explorer Views

**Portal:** Microsoft Purview > Data Loss Prevention > Activity Explorer

Create filtered views for demo:
1. **AI DLP Matches:** Filter by policy name containing `PVShadowAI`
2. **Copilot Activity:** Filter by workload = `MicrosoftCopilot`
3. **External Uploads:** Filter by activity = `FileUploaded` + location = external

## 4. Pre-populate Alerts (optional, for demo impact)

To have alerts ready before a live demo:
1. Send test emails containing sensitive data (automated by deploy)
2. Attempt paste/upload of sensitive content to AI sites from a test device
3. Allow 15-30 minutes for DLP policy processing
4. Check **Alerts** dashboard in Microsoft Purview compliance portal

## Verification checklist

- [ ] Endpoint DLP browser restrictions configured for AI domains
- [ ] Conditional Access policies in report-only mode
- [ ] Activity Explorer shows DLP matches for PVShadowAI policies
- [ ] Insider Risk dashboard shows policy activity
- [ ] Test alerts visible in compliance portal
