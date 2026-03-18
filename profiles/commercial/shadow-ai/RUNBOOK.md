# Shadow AI Demo — Manual Configuration Runbook

Steps that require portal access after automated deployment.

## Prerequisites

- Global Admin or Compliance Admin role
- Microsoft 365 E5 or E5 Compliance add-on
- Microsoft Defender for Cloud Apps license (for App Governance)
- Microsoft Defender for Endpoint (for Cloud Discovery integration)

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

## 2. Cloud Discovery for AI Apps

**Portal:** Microsoft Defender for Cloud Apps > Cloud Discovery

### Option A: Defender for Endpoint integration (recommended)
1. Navigate to **Settings > Cloud Apps > Microsoft Defender for Endpoint**
2. Enable integration (if not already)
3. AI app traffic will automatically appear in Cloud Discovery

### Option B: Manual log upload
1. Navigate to **Cloud Discovery > Create snapshot report**
2. Upload network appliance logs (firewall, proxy)
3. Select log format and data source

### Configure discovery policy
1. Navigate to **Policies > Policy management > Create policy > Cloud Discovery policy**
2. Filter by app category: **Generative AI**
3. Set alert threshold (e.g., > 100 MB uploaded per day)
4. Enable governance action: Tag as **Unsanctioned**

## 3. OAuth App Governance

**Portal:** Microsoft Defender for Cloud Apps > App Governance

1. Navigate to **App Governance > Policies**
2. Create new policy:
   - Name: `PVShadowAI - Risky AI OAuth Apps`
   - Condition: App requests `Mail.Read`, `Files.ReadWrite.All`, or `Sites.ReadWrite.All`
   - AND App category contains "AI" or "Generative AI"
   - Action: Generate alert + optionally disable app
3. Review existing OAuth apps for AI-related permissions

## 4. Session Policies (Real-time monitoring)

**Portal:** Microsoft Defender for Cloud Apps > Policies > Session policies

1. Create new session policy:
   - Name: `PVShadowAI - Monitor AI Uploads`
   - Session control type: **Monitor only** or **Block download/upload**
   - Activity filter: Upload file to cloud app
   - App filter: ChatGPT, Claude, or custom AI apps
   - Content inspection: Enable for sensitive info types
2. Requires Conditional Access App Control to be enabled

## 5. Conditional Access Policies

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

## 6. Activity Explorer Views

**Portal:** Microsoft Purview > Data Loss Prevention > Activity Explorer

Create filtered views for demo:
1. **AI DLP Matches:** Filter by policy name containing `PVShadowAI`
2. **Copilot Activity:** Filter by workload = `MicrosoftCopilot`
3. **External Uploads:** Filter by activity = `FileUploaded` + location = external

## 7. Pre-populate Alerts (optional, for demo impact)

To have alerts ready before a live demo:
1. Send test emails containing sensitive data (automated by deploy)
2. Attempt paste/upload of sensitive content to AI sites from a test device
3. Allow 15-30 minutes for DLP policy processing
4. Check **Alerts** dashboard in Microsoft Purview compliance portal

## Verification checklist

- [ ] Endpoint DLP browser restrictions configured for AI domains
- [ ] Cloud Discovery showing AI app traffic (or snapshot uploaded)
- [ ] OAuth app governance policy active
- [ ] Conditional Access policies in report-only mode
- [ ] Activity Explorer shows DLP matches for PVShadowAI policies
- [ ] Insider Risk dashboard shows policy activity
- [ ] Test alerts visible in compliance portal
