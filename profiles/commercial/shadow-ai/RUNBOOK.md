# Shadow AI Demo — Post-Deploy Runbook (Commercial)

Post-deployment steps and demo-day preparation.

## Prerequisites

- Global Admin or Compliance Admin role
- Microsoft 365 E5 or E5 Compliance add-on
- Microsoft Defender for Endpoint on at least one test device (for live paste/upload demos)
- Microsoft 365 Copilot licenses on demo users (for the "use Copilot instead" flow)

---

## 1. Run the readiness check

```powershell
./scripts/Test-ShadowAiReady.ps1 -LabProfile shadow-ai -Cloud commercial
```

Green across the board = safe to demo. Red or yellow items tell you what to fix.

---

## 2. Push Endpoint DLP browser-and-domain restrictions

Endpoint DLP enforces paste/upload blocks via a **tenant-wide** domain list. The config lists the AI sites to block, but the list must be merged into the tenant's shared `EndpointDlpGlobalSettings`.

### Preview the merge

```powershell
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile shadow-ai
```

The script prints the current `EndpointDlpGlobalSettings` entry and shows what it would change. Review this output — this is tenant-wide, so other DLP policies share the domain list.

### Apply the merge

```powershell
./scripts/Set-ShadowAiEndpointDlpDomains.ps1 -LabProfile shadow-ai -Apply
```

After applying, allow 15–30 min for the setting to propagate to devices.

### Manual fallback

If the script fails (the `EndpointDlpGlobalSettings` schema is not fully documented on MS Learn and can change across tenants):

1. Purview portal → **Data loss prevention** → **Endpoint DLP settings** → **Browser and domain restrictions to sensitive data**
2. Set **Service domains** to **Block**
3. Add each domain from `configs/commercial/shadow-ai-demo.json` → `workloads.dlp.policies[0].endpointDlpBrowserRestrictions.blockedUrls`

---

## 3. Onboard a test device (for live blocking demo)

Endpoint DLP enforces on managed devices. Without a device onboarded to Microsoft Defender for Endpoint, the Devices DLP rules audit but do not block.

1. Intune / Endpoint admin center → **Onboarding** → Windows device
2. Install MDE agent on test VM
3. Verify device appears in Purview → **Settings** → **Device onboarding**
4. Allow 15–60 min for first sync

## 4. Conditional Access policies (report-only)

Two policies deploy in **report-only**. For live enforcement:

1. Entra admin center → **Protection** → **Conditional Access**
2. Open `PVShadowAI-Block AI Apps High Sign-In Risk`
3. Populate **Cloud apps** with your tenant's enterprise app IDs for ChatGPT, Claude, Gemini (these are registered only after first user sign-in)
4. Move from **Report-only** to **On** when ready

---

## 5. Activity Explorer filtered views

After DLP alerts start flowing:

1. Purview → **Data loss prevention** → **Activity Explorer**
2. Saved filters:
   - **AI DLP Matches** — Policy name contains `PVShadowAI`
   - **Copilot Activity** — Workload = `MicrosoftCopilotForM365`
   - **External Uploads** — Activity = `FileUploaded` + location = external cloud

---

## 6. Pre-populate alerts before a live demo

Empty dashboards read as "nothing's working." Seed the environment 15-30 min before demo time:

```powershell
./scripts/Invoke-SmokeTest.ps1 -LabProfile shadow-ai -Cloud commercial
```

Or manually walk through the prompts in `scripts/shadow-ai-test-prompts.md` to generate diverse matches.

---

## 7. Optional: Activate DSPM for AI (recommended)

DSPM for AI is Microsoft's posture-management surface for AI data security. It layers on top of this lab and provides the "where is risk concentrated?" story.

1. [Microsoft Purview portal](https://purview.microsoft.com) → **Solutions** → **DSPM for AI**
2. Under **Get started**, turn on prerequisites that aren't already green:
   - Microsoft Purview audit (auto-on for new tenants)
   - Microsoft Purview browser extension (for third-party AI site visibility)
   - Device onboarding to Microsoft Purview
3. Under **Recommendations**, activate:
   - **Fortify your data security** — creates DLP one-click policies:
     - *DSPM for AI - Block sensitive info from AI sites* (Adaptive Protection, block-with-override for elevated-risk users)
     - *DSPM for AI - Block elevated risk users from submitting prompts to AI apps in Microsoft Edge*
     - *DSPM for AI - Block sensitive info from AI apps in Edge*
     - *DSPM for AI - Protect sensitive data from Copilot processing*
   - **Detect risky interactions in AI apps** — creates IRM policy for risky AI usage
   - **Detect unethical behavior in AI apps** — creates Communication Compliance policy
   - **Extend your insights for data discovery** — collection policy for Edge AI prompt detection + IRM policy for AI site visits
   - **Secure interactions in Microsoft Copilot experiences** — collection policy to capture prompts/responses
   - **Secure interactions from enterprise apps** — collection policy for Entra-registered AI apps (ChatGPT Enterprise, Foundry, etc.)
4. Wait 24 hours, then return to **Reports** to see:
   - **Sensitive interactions per generative AI app**
   - **Top sensitive info types shared with AI**
   - **Insider risk severity per AI apps**
5. Run the built-in weekly **Data risk assessment** for the top 100 SharePoint sites

> **Demo framing:** "This lab is enforcement — DLP stopping data in the moment. DSPM for AI is posture — where risk still lives, which users carry it, which sites need labeling before Copilot touches them. Enforcement + posture is the complete Shadow AI story."

---

## 8. Optional: Browser Data Security for Edge

Purview Browser Data Security (DLP for Cloud Apps in Edge for Business) activates automatically when you publish a DLP policy targeting unmanaged cloud apps. It's a separate in-Edge inline control that:

- Inspects text typed/pasted into AI prompts in real time
- Blocks submission before leaving the browser
- Applies to Microsoft Edge for Business (other browsers get blocked entirely when the policy is in block mode)

Covered AI apps today: ChatGPT (consumer), Microsoft Chat (consumer), Google Gemini, DeepSeek.

### Activation

1. Purview portal → **Data loss prevention** → **Policies** → **Create policy**
2. Template: **Custom** → Location: **Unmanaged cloud apps** → Scope to **Generative AI** app category
3. Add Content contains → Sensitive information types
4. Action: **Block** (or **Block with override** for a warning flow)
5. Publish — Edge management service auto-provisions the required Intune configuration

See `RUNBOOK` section 7 above for the DSPM for AI one-click version of the same policy.

---

## 9. Optional: Collection policies (AI content capture)

Collection policies capture prompts/responses from AI apps for eDiscovery, retention, and Communication Compliance review.

- Covered sources: Copilot experiences, Enterprise AI apps (Entra-registered / ChatGPT Enterprise / Foundry), unmanaged cloud AI apps
- Requires a policy with `Content contains classifiers = All` to capture full content
- See [Collection Policies solution overview](https://learn.microsoft.com/purview/collection-policies-solution-overview)

The DSPM for AI one-click policies include these — activating the DSPM recommendations is the fastest path.

---

## Verification checklist

- [ ] `Test-ShadowAiReady.ps1` returns READY
- [ ] Endpoint DLP domain block list pushed (`Set-ShadowAiEndpointDlpDomains.ps1 -Apply`)
- [ ] At least one test device onboarded to Defender for Endpoint
- [ ] DLP policies propagated (up to 4h after deploy / mode switch)
- [ ] Sensitivity labels published to demo users
- [ ] Microsoft 365 Copilot licenses assigned to demo users
- [ ] Test documents uploaded to OneDrive and auto-labeled
- [ ] Alerts generated by smoke test before demo-time
- [ ] DSPM for AI activated (optional, recommended)

---

## Switching from Simulation to Enforcement

DLP policies deploy in `TestWithNotifications` by default. To enable live block:

1. Purview portal → **DLP** → **Policies**
2. Select each `PVShadowAI-*` policy
3. Change status from **Test it out** → **Turn it on**
4. Allow up to 4h for full propagation
5. Rerun `Test-ShadowAiReady.ps1` — wait for READY before demoing

Or redeploy with `"simulationMode": false` in the config (same propagation window applies).

> **Caution:** Switching a policy from simulation to enforced restarts the 4-hour propagation window.
