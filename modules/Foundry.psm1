#Requires -Version 7.0

<#
.SYNOPSIS
    Microsoft Foundry workload module for purview-lab-deployer.
.DESCRIPTION
    Deploys a Microsoft Foundry account (Microsoft.CognitiveServices/accounts kind=AIServices),
    a gpt-4o model deployment, a Foundry project, a Purview governance toggle, and AI agents.
    Uses the 2025 Foundry resource model — no Hub, Storage, or Key Vault required.
    Requires the Az.Accounts PowerShell module for ARM authentication.
#>

$script:ArmApiVersion   = '2025-09-01'
$script:AgentApiVersion = '2025-05-15-preview'
$script:AppApiVersion   = '2025-10-01-preview'   # accounts/projects/applications (publish agent endpoint)
$script:ArmBase         = 'https://management.azure.com'
$script:GptModelVersion = '2024-11-20'   # Current GA version of gpt-4o; update if deploying to a region with a newer default

# ─── Private helpers ──────────────────────────────────────────────────────────

function Get-FoundryArmToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    $tok = (Get-AzAccessToken -ResourceUrl 'https://management.azure.com' -ErrorAction Stop).Token
    # Az.Accounts 3.x+ returns a SecureString; convert to plain text for HTTP headers
    if ($tok -is [System.Security.SecureString]) { return $tok | ConvertFrom-SecureString -AsPlainText }
    return $tok
}

function Get-FoundryDataToken {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    # Foundry agent data-plane (services.ai.azure.com) requires https://ai.azure.com audience
    $tok = (Get-AzAccessToken -ResourceUrl 'https://ai.azure.com' -ErrorAction Stop).Token
    if ($tok -is [System.Security.SecureString]) { return $tok | ConvertFrom-SecureString -AsPlainText }
    return $tok
}

function Invoke-ArmGet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $headers = @{ 'Authorization' = "Bearer $Token" }
    $webResponse = Invoke-WebRequest -Uri $Uri -Method Get -Headers $headers `
        -SkipHttpErrorCheck -ErrorAction Stop

    $statusCode = [int]$webResponse.StatusCode
    if ($statusCode -eq 404) { return $null }
    if ($statusCode -ge 400) {
        throw "ARM GET failed (HTTP $statusCode): $($webResponse.Content)"
    }

    return ($webResponse.Content | ConvertFrom-Json)
}

function Invoke-ArmPut {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Body,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter()]
        [switch]$Async
    )

    $headers = @{
        'Authorization' = "Bearer $Token"
        'Content-Type'  = 'application/json'
    }

    $webResponse = Invoke-WebRequest -Uri $Uri -Method Put -Headers $headers -Body $Body `
        -SkipHttpErrorCheck -ErrorAction Stop
    $statusCode = [int]$webResponse.StatusCode

    if ($statusCode -ge 400) {
        throw "ARM PUT failed (HTTP $statusCode): $($webResponse.Content)"
    }

    $parsed = if ($webResponse.Content) {
        try { $webResponse.Content | ConvertFrom-Json } catch { $null }
    }
    else { $null }

    if ($Async -and $statusCode -in @(201, 202)) {
        $asyncUrl = $null
        if ($webResponse.Headers['Azure-AsyncOperation']) {
            $asyncUrl = [string]($webResponse.Headers['Azure-AsyncOperation'] | Select-Object -First 1)
        }
        elseif ($webResponse.Headers['Location']) {
            $asyncUrl = [string]($webResponse.Headers['Location'] | Select-Object -First 1)
        }

        if ($asyncUrl) {
            Wait-ArmAsyncOperation -OperationUrl $asyncUrl -Token $Token
        }
    }

    return $parsed
}

function Invoke-ArmDelete {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [string]$Token,

        [Parameter()]
        [switch]$Async
    )

    $headers = @{ 'Authorization' = "Bearer $Token" }
    $webResponse = Invoke-WebRequest -Uri $Uri -Method Delete -Headers $headers `
        -SkipHttpErrorCheck -ErrorAction Stop
    $statusCode = [int]$webResponse.StatusCode

    if ($statusCode -eq 404) { return }  # Already gone
    if ($statusCode -ge 400) {
        throw "ARM DELETE failed (HTTP $statusCode): $($webResponse.Content)"
    }

    if ($Async -and $statusCode -eq 202) {
        $asyncUrl = $null
        if ($webResponse.Headers['Azure-AsyncOperation']) {
            $asyncUrl = [string]($webResponse.Headers['Azure-AsyncOperation'] | Select-Object -First 1)
        }
        elseif ($webResponse.Headers['Location']) {
            $asyncUrl = [string]($webResponse.Headers['Location'] | Select-Object -First 1)
        }

        if ($asyncUrl) {
            Wait-ArmAsyncOperation -OperationUrl $asyncUrl -Token $Token
        }
    }
}

function Initialize-PngWriter {
    if (-not ([System.Management.Automation.PSTypeName]'Foundry.PngWriter').Type) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.IO.Compression;

namespace Foundry {
    public static class PngWriter {
        static uint[] _crcTable;

        static PngWriter() {
            _crcTable = new uint[256];
            for (uint n = 0; n < 256; n++) {
                uint c = n;
                for (int k = 0; k < 8; k++) {
                    if ((c & 1) != 0) c = 0xEDB88320u ^ (c >> 1);
                    else c >>= 1;
                }
                _crcTable[n] = c;
            }
        }

        static uint Crc32(byte[] data, int offset, int length) {
            uint crc = 0xFFFFFFFFu;
            for (int i = offset; i < offset + length; i++)
                crc = _crcTable[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
            return crc ^ 0xFFFFFFFFu;
        }

        static uint Adler32(byte[] data) {
            uint s1 = 1, s2 = 0;
            foreach (byte b in data) {
                s1 = (s1 + b) % 65521;
                s2 = (s2 + s1) % 65521;
            }
            return (s2 << 16) | s1;
        }

        static byte[] BigEndian4(uint v) {
            return new byte[] {
                (byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8), (byte)v
            };
        }

        static void WriteChunk(Stream out_, byte[] type, byte[] data) {
            byte[] lenBytes = BigEndian4((uint)data.Length);
            out_.Write(lenBytes, 0, 4);
            out_.Write(type, 0, 4);
            out_.Write(data, 0, data.Length);

            byte[] crcInput = new byte[4 + data.Length];
            Array.Copy(type, 0, crcInput, 0, 4);
            Array.Copy(data, 0, crcInput, 4, data.Length);
            byte[] crcBytes = BigEndian4(Crc32(crcInput, 0, crcInput.Length));
            out_.Write(crcBytes, 0, 4);
        }

        public static void Write(string path, int size, byte r, byte g, byte b) {
            // Build raw image: one filter byte (0x00) per scanline + RGB pixels
            int scanline = 1 + size * 3;
            byte[] raw = new byte[size * scanline];
            for (int y = 0; y < size; y++) {
                int off = y * scanline;
                raw[off] = 0x00; // filter type None
                for (int x = 0; x < size; x++) {
                    raw[off + 1 + x * 3 + 0] = r;
                    raw[off + 1 + x * 3 + 1] = g;
                    raw[off + 1 + x * 3 + 2] = b;
                }
            }

            // Zlib-compress: 0x78 0x9C + Deflate + Adler-32
            byte[] compressed;
            using (var comp = new MemoryStream()) {
                comp.WriteByte(0x78);
                comp.WriteByte(0x9C);
                using (var dfl = new DeflateStream(comp, CompressionLevel.Optimal, true)) {
                    dfl.Write(raw, 0, raw.Length);
                }
                uint adler = Adler32(raw);
                byte[] adlerBytes = BigEndian4(adler);
                comp.Write(adlerBytes, 0, 4);
                compressed = comp.ToArray();
            }

            // Build IHDR: width, height, bit depth 8, colour type 2 (RGB), compress 0, filter 0, interlace 0
            byte[] ihdr = new byte[13];
            byte[] wb = BigEndian4((uint)size); Array.Copy(wb, 0, ihdr, 0, 4);
            byte[] hb = BigEndian4((uint)size); Array.Copy(hb, 0, ihdr, 4, 4);
            ihdr[8] = 8; ihdr[9] = 2; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;

            byte[] pngSig = new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 };
            byte[] typeIHDR = new byte[] { 73, 72, 68, 82 };
            byte[] typeIDAT = new byte[] { 73, 68, 65, 84 };
            byte[] typeIEND = new byte[] { 73, 69, 78, 68 };

            using (var fs = File.Open(path, FileMode.Create, FileAccess.Write)) {
                fs.Write(pngSig, 0, 8);
                WriteChunk(fs, typeIHDR, ihdr);
                WriteChunk(fs, typeIDAT, compressed);
                WriteChunk(fs, typeIEND, new byte[0]);
            }
        }
    }
}
'@
    }
}

function New-FoundryAgentPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Agent,

        [Parameter(Mandatory)]
        [string]$Prefix,

        [Parameter(Mandatory)]
        [PSCustomObject]$AgentConfig,

        [Parameter(Mandatory)]
        [string]$OutputDir,

        [Parameter(Mandatory)]
        [string]$TenantId
    )

    $agentName   = [string]$Agent.name
    # Strip prefix: PVFoundry-HR-Helpdesk → HR-Helpdesk
    $shortName   = $agentName -replace "^$([regex]::Escape($Prefix))-", ''
    # No hyphens: HR-Helpdesk → HRHelpdesk
    $shortNameNH = $shortName -replace '-', ''

    $description     = if ($AgentConfig.PSObject.Properties['description'] -and
                           -not [string]::IsNullOrWhiteSpace([string]$AgentConfig.description)) {
                           [string]$AgentConfig.description
                       } else { $shortName }
    $instructions    = [string]$AgentConfig.instructions
    $baseUrl         = if ($Agent.PSObject.Properties['baseUrl']) { [string]$Agent.baseUrl } else { '' }

    $descShort = if ($description.Length -le 80) { $description } else { $description.Substring(0, 77) + '...' }

    $pkgDir  = Join-Path $OutputDir $shortName
    $zipPath = Join-Path $OutputDir "$shortName.zip"

    if (Test-Path $pkgDir) { Remove-Item $pkgDir -Recurse -Force }
    New-Item -ItemType Directory -Path $pkgDir -Force | Out-Null

    # --- manifest.json ---
    $teamsManifest = [ordered]@{
        '$schema'       = 'https://developer.microsoft.com/json-schemas/teams/v1.19/MicrosoftTeams.schema.json'
        manifestVersion = '1.19'
        version         = '1.0.0'
        id              = [string][System.Guid]::NewGuid()
        developer       = [ordered]@{
            name           = 'Contoso'
            websiteUrl     = 'https://contoso.com'
            privacyUrl     = 'https://contoso.com/privacy'
            termsOfUseUrl  = 'https://contoso.com/terms'
        }
        name            = [ordered]@{
            short = $shortName
            full  = "$Prefix $shortName"
        }
        description     = [ordered]@{
            short = $descShort
            full  = "$description — powered by Microsoft Foundry + Purview AI Governance"
        }
        icons           = [ordered]@{ color = 'color.png'; outline = 'outline.png' }
        accentColor     = '#0078D4'
        copilotAgents   = [ordered]@{
            declarativeAgents = @(
                [ordered]@{ id = $shortNameNH; file = 'declarativeAgent.json' }
            )
        }
    }
    $teamsManifest | ConvertTo-Json -Depth 10 |
        Set-Content -Path (Join-Path $pkgDir 'manifest.json') -Encoding UTF8

    # --- declarativeAgent.json ---
    $declAgent = [ordered]@{
        '$schema'    = 'https://developer.microsoft.com/json-schemas/copilot/declarative-agent/v1.4/schema.json'
        version      = 'v1.4'
        name         = $shortName
        description  = $description
        instructions = $instructions
        actions      = @(
            [ordered]@{ id = "${shortNameNH}API"; file = 'plugin.json' }
        )
    }
    $declAgent | ConvertTo-Json -Depth 10 |
        Set-Content -Path (Join-Path $pkgDir 'declarativeAgent.json') -Encoding UTF8

    # --- plugin.json ---
    $plugin = [ordered]@{
        schema_version        = 'v2.1'
        name_for_human        = $shortName
        name_for_model        = $shortNameNH
        description_for_human = $description
        description_for_model = "$description. $instructions"
        auth                  = [ordered]@{ type = 'none' }
        api                   = [ordered]@{ type = 'openapi'; url = 'openapi.json' }
    }
    $plugin | ConvertTo-Json -Depth 10 |
        Set-Content -Path (Join-Path $pkgDir 'plugin.json') -Encoding UTF8

    # --- openapi.json ---
    $authUrl  = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/authorize"
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $openapi = [ordered]@{
        openapi  = '3.0.1'
        info     = [ordered]@{ title = $shortName; version = '1.0.0' }
        servers  = @(@{ url = $baseUrl })
        paths    = [ordered]@{
            '/responses' = [ordered]@{
                post = [ordered]@{
                    operationId = "ask$shortNameNH"
                    summary     = "Ask $shortName a question"
                    requestBody = [ordered]@{
                        required = $true
                        content  = [ordered]@{
                            'application/json' = [ordered]@{
                                schema = [ordered]@{
                                    type       = 'object'
                                    required   = @('input')
                                    properties = [ordered]@{
                                        input = [ordered]@{ type = 'string'; description = 'User question or prompt' }
                                    }
                                }
                            }
                        }
                    }
                    responses   = [ordered]@{
                        '200' = [ordered]@{
                            description = 'Successful response'
                            content     = [ordered]@{
                                'application/json' = [ordered]@{
                                    schema = [ordered]@{
                                        type       = 'object'
                                        properties = [ordered]@{
                                            output = [ordered]@{ type = 'array'; items = [ordered]@{ type = 'object' } }
                                            status = [ordered]@{ type = 'string' }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    security    = @(@{ EntraOAuth = @() })
                }
            }
        }
        components = [ordered]@{
            securitySchemes = [ordered]@{
                EntraOAuth = [ordered]@{
                    type  = 'oauth2'
                    flows = [ordered]@{
                        authorizationCode = [ordered]@{
                            authorizationUrl = $authUrl
                            tokenUrl         = $tokenUrl
                            scopes           = [ordered]@{
                                'https://cognitiveservices.azure.com/.default' = 'Access Azure AI services'
                            }
                        }
                    }
                }
            }
        }
    }
    $openapi | ConvertTo-Json -Depth 15 |
        Set-Content -Path (Join-Path $pkgDir 'openapi.json') -Encoding UTF8

    # --- PNG icons ---
    Initialize-PngWriter
    [Foundry.PngWriter]::Write((Join-Path $pkgDir 'color.png'),   192,   0, 120, 212)
    [Foundry.PngWriter]::Write((Join-Path $pkgDir 'outline.png'),  32, 255, 255, 255)

    # --- Zip ---
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Compress-Archive -Path (Join-Path $pkgDir '*') -DestinationPath $zipPath -Force

    # Cleanup staging dir
    Remove-Item $pkgDir -Recurse -Force

    return $zipPath
}

function Wait-ArmAsyncOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$OperationUrl,

        [Parameter(Mandatory)]
        [string]$Token
    )

    $headers    = @{ 'Authorization' = "Bearer $Token" }
    $maxAttempts = 40   # 40 × 15s = 10 min

    for ($i = 1; $i -le $maxAttempts; $i++) {
        Start-Sleep -Seconds 15
        $opResponse = Invoke-WebRequest -Uri $OperationUrl -Method Get -Headers $headers `
            -SkipHttpErrorCheck -ErrorAction Stop
        $opBody = try { $opResponse.Content | ConvertFrom-Json } catch { $null }

        $httpStatus = [int]$opResponse.StatusCode

        # For Location-header style polling: 200/204 with no status body = operation complete
        if ($httpStatus -in @(200, 204) -and (-not $opBody -or (-not $opBody.PSObject.Properties['status'] -and -not $opBody.PSObject.Properties['provisioningState']))) {
            Write-LabLog -Message "ARM async polling... status: Succeeded (HTTP $httpStatus, attempt $i/$maxAttempts)" -Level Info
            return
        }

        $status = if ($opBody) {
            if ($opBody.PSObject.Properties['status']) {
                [string]$opBody.status
            }
            elseif ($opBody.PSObject.Properties['provisioningState']) {
                [string]$opBody.provisioningState
            }
            else { 'Unknown' }
        }
        else { 'Unknown' }

        Write-LabLog -Message "ARM async polling... status: $status (attempt $i/$maxAttempts)" -Level Info

        if ($status -eq 'Succeeded') { return }
        if ($status -in @('Failed', 'Canceled')) {
            $errorMsg = if ($opBody -and $opBody.PSObject.Properties['error']) {
                $opBody.error | ConvertTo-Json -Compress
            }
            else { $opResponse.Content }
            throw "ARM async operation $status`: $errorMsg"
        }
    }

    throw "ARM async operation did not complete within $($maxAttempts * 15) seconds."
}


# ─── Deploy-Foundry ───────────────────────────────────────────────────────────

function Deploy-Foundry {
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config
    )

    $fw              = $Config.workloads.foundry
    $subscriptionId  = [string]$fw.subscriptionId
    $resourceGroup   = [string]$fw.resourceGroup
    $location        = [string]$fw.location
    $accountName     = [string]$fw.accountName
    $projectName     = [string]$fw.projectName
    $modelDeployName = [string]$fw.modelDeploymentName

    # Validate required config fields
    if ([string]::IsNullOrWhiteSpace($subscriptionId) -or $subscriptionId -eq 'YOUR_SUBSCRIPTION_ID') {
        throw 'foundry.subscriptionId must be set to a real Azure subscription ID before deploying.'
    }
    foreach ($field in @('resourceGroup', 'location', 'accountName', 'projectName', 'modelDeploymentName')) {
        if ([string]::IsNullOrWhiteSpace([string]$fw.$field)) {
            throw "foundry.$field is required but not set in the config."
        }
    }

    $manifest = [PSCustomObject]@{
        subscriptionId            = $subscriptionId
        resourceGroup             = $resourceGroup
        location                  = $location
        accountId                 = $null
        projectId                 = $null
        projectEndpoint           = $null
        modelDeploymentName       = $modelDeployName
        purviewIntegrationEnabled = $false
        agents                    = @()
    }

    if (-not $PSCmdlet.ShouldProcess("Foundry lab '$($Config.prefix)'", 'Deploy Foundry account, project, and agents')) {
        return $manifest
    }

    # Re-assert Az context with the target subscription before acquiring tokens.
    # The Purview workloads run for 10-30 min before Foundry; re-setting context
    # ensures Get-AzAccessToken issues a fresh token for the correct subscription.
    Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null

    $armToken  = Get-FoundryArmToken
    $dataToken = Get-FoundryDataToken

    $subPath     = "$($script:ArmBase)/subscriptions/$subscriptionId"
    $rgPath      = "$subPath/resourceGroups/$resourceGroup"
    $accountPath = "$rgPath/providers/Microsoft.CognitiveServices/accounts/$accountName"
    $modelPath   = "$accountPath/deployments/$modelDeployName"
    $projectPath = "$accountPath/projects/$projectName"

    # ── 1. Resource Group ──────────────────────────────────────────────────────
    Write-LabLog -Message "Ensuring resource group: $resourceGroup" -Level Info
    $rgUri = "$rgPath`?api-version=2021-04-01"
    $existingRg = Invoke-ArmGet -Uri $rgUri -Token $armToken
    if (-not $existingRg) {
        $rgBody = @{ location = $location } | ConvertTo-Json -Compress
        Invoke-ArmPut -Uri $rgUri -Body $rgBody -Token $armToken | Out-Null
        Write-LabLog -Message "Created resource group: $resourceGroup" -Level Success
    }
    else {
        Write-LabLog -Message "Resource group already exists: $resourceGroup" -Level Info
    }

    # ── 2. Foundry Account (CognitiveServices AIServices) ──────────────────────
    Write-LabLog -Message "Ensuring Foundry account: $accountName" -Level Info
    $accountUri      = "$accountPath`?api-version=$($script:ArmApiVersion)"
    $existingAccount = Invoke-ArmGet -Uri $accountUri -Token $armToken

    if ($existingAccount) {
        Write-LabLog -Message "Foundry account already exists: $accountName" -Level Info
        $manifest.accountId = [string]$existingAccount.id
    }
    else {
        $accountBody = @{
            kind       = 'AIServices'
            location   = $location
            sku        = @{ name = 'S0' }
            properties = @{
                allowProjectManagement = $true
                publicNetworkAccess    = 'Enabled'
                customSubDomainName    = $accountName   # Required for Foundry project creation
            }
        } | ConvertTo-Json -Depth 5 -Compress

        $createdAccount = Invoke-ArmPut -Uri $accountUri -Body $accountBody -Token $armToken -Async
        $manifest.accountId = if ($createdAccount -and $createdAccount.PSObject.Properties['id']) {
            [string]$createdAccount.id
        }
        else { $accountPath }
        Write-LabLog -Message "Created Foundry account: $accountName" -Level Success
    }

    # ── 3. Model Deployment (gpt-4o GlobalStandard) ───────────────────────────
    Write-LabLog -Message "Ensuring model deployment: $modelDeployName" -Level Info
    $modelUri      = "$modelPath`?api-version=$($script:ArmApiVersion)"
    $existingModel = Invoke-ArmGet -Uri $modelUri -Token $armToken

    if ($existingModel) {
        Write-LabLog -Message "Model deployment already exists: $modelDeployName" -Level Info
    }
    else {
        $modelBody = @{
            sku        = @{ name = 'GlobalStandard'; capacity = 10 }
            properties = @{
                model = @{
                    format  = 'OpenAI'
                    name    = 'gpt-4o'
                    version = $script:GptModelVersion
                }
            }
        } | ConvertTo-Json -Depth 5 -Compress

        Invoke-ArmPut -Uri $modelUri -Body $modelBody -Token $armToken -Async | Out-Null
        Write-LabLog -Message "Created model deployment: $modelDeployName (gpt-4o $($script:GptModelVersion))" -Level Success
    }

    # ── 4. Foundry Project ────────────────────────────────────────────────────
    Write-LabLog -Message "Ensuring Foundry project: $projectName" -Level Info
    $projectUri      = "$projectPath`?api-version=$($script:ArmApiVersion)"
    $existingProject = Invoke-ArmGet -Uri $projectUri -Token $armToken

    # Treat a Failed project as non-existent — delete and recreate
    $projectFailed = $existingProject -and
        $existingProject.PSObject.Properties['properties'] -and
        $existingProject.properties.PSObject.Properties['provisioningState'] -and
        [string]$existingProject.properties.provisioningState -eq 'Failed'

    if ($projectFailed) {
        Write-LabLog -Message "Foundry project '$projectName' is in Failed state — deleting and recreating." -Level Warning
        Invoke-ArmDelete -Uri $projectUri -Token $armToken | Out-Null
        $existingProject = $null
    }

    if ($existingProject) {
        Write-LabLog -Message "Foundry project already exists: $projectName" -Level Info
        $manifest.projectId = [string]$existingProject.id
    }
    else {
        $projectBody = @{
            location   = $location
            properties = @{
                description = 'Purview AI governance demo — deployed by purview-lab-deployer'
            }
        } | ConvertTo-Json -Depth 5 -Compress

        $createdProject = Invoke-ArmPut -Uri $projectUri -Body $projectBody -Token $armToken -Async
        $manifest.projectId = if ($createdProject -and $createdProject.PSObject.Properties['id']) {
            [string]$createdProject.id
        }
        else { $projectPath }
        Write-LabLog -Message "Created Foundry project: $projectName" -Level Success
    }

    $projectEndpoint          = "https://$accountName.services.ai.azure.com/api/projects/$projectName"
    $manifest.projectEndpoint = $projectEndpoint

    # ── 5. Enable Purview governance integration (best-effort REST) ────────────
    try {
        $govUri  = "$projectEndpoint/governance/settings?api-version=$($script:AgentApiVersion)"
        $govBody = @{ purviewIntegrationEnabled = $true } | ConvertTo-Json -Compress
        $govHeaders = @{
            'Authorization' = "Bearer $dataToken"
            'Content-Type'  = 'application/json'
        }
        $govResponse = Invoke-WebRequest -Uri $govUri -Method Put -Headers $govHeaders -Body $govBody `
            -SkipHttpErrorCheck -ErrorAction Stop

        if ([int]$govResponse.StatusCode -lt 400) {
            $manifest.purviewIntegrationEnabled = $true
            Write-LabLog -Message 'Purview governance integration enabled on Foundry project.' -Level Success
        }
        else {
            Write-LabLog -Message "Purview governance toggle returned HTTP $($govResponse.StatusCode). Enable integration manually: Foundry portal > Governance settings." -Level Warning
        }
    }
    catch {
        Write-LabLog -Message "Purview governance toggle not available via API. Enable manually: Foundry portal > Governance settings. ($($_.Exception.Message))" -Level Warning
    }

    # ── 6. Create agents ───────────────────────────────────────────────────────
    $createdAgents = [System.Collections.Generic.List[PSCustomObject]]::new()
    $agentHeaders  = @{
        'Authorization' = "Bearer $dataToken"
        'Content-Type'  = 'application/json'
    }
    $agentsUri = "$projectEndpoint/agents?api-version=$($script:AgentApiVersion)"

    foreach ($agentConfig in $Config.workloads.foundry.agents) {
        $agentName = "$($Config.prefix)-$($agentConfig.name)"
        Write-LabLog -Message "Creating agent: $agentName" -Level Info

        $agentPayload = [ordered]@{
            name       = $agentName
            definition = [ordered]@{
                kind         = 'prompt'
                model        = [string]$agentConfig.model
                instructions = [string]$agentConfig.instructions
            }
        }
        if ($agentConfig.PSObject.Properties['description'] -and
            -not [string]::IsNullOrWhiteSpace([string]$agentConfig.description)) {
            $agentPayload['description'] = [string]$agentConfig.description
        }

        try {
            # Check if agent already exists (idempotent)
            $existingAgent = Invoke-WebRequest -Uri "$projectEndpoint/agents/$agentName`?api-version=$($script:AgentApiVersion)" `
                -Headers $agentHeaders -Method Get -SkipHttpErrorCheck -ErrorAction Stop
            if ([int]$existingAgent.StatusCode -eq 200) {
                Write-LabLog -Message "Agent already exists: $agentName" -Level Info
                $createdAgents.Add([PSCustomObject]@{
                    id    = $agentName
                    name  = $agentName
                    model = [string]$agentConfig.model
                })
                continue
            }

            $agentResponse = Invoke-WebRequest -Uri $agentsUri -Method Post -Headers $agentHeaders `
                -Body ($agentPayload | ConvertTo-Json -Depth 5 -Compress) -SkipHttpErrorCheck -ErrorAction Stop

            if ([int]$agentResponse.StatusCode -lt 400) {
                $agentResult = $agentResponse.Content | ConvertFrom-Json
                $createdAgents.Add([PSCustomObject]@{
                    id    = [string]$agentResult.id
                    name  = $agentName
                    model = [string]$agentConfig.model
                })
                Write-LabLog -Message "Created agent: $agentName (id: $($agentResult.id))" -Level Success
            }
            else {
                Write-LabLog -Message "Agent '$agentName' creation failed (HTTP $($agentResponse.StatusCode)): $($agentResponse.Content)" -Level Warning
            }
        }
        catch {
            Write-LabLog -Message "Error creating agent '$agentName'`: $($_.Exception.Message)" -Level Warning
        }
    }

    $manifest.agents = $createdAgents.ToArray()

    # ── 7. Publish agents as applications ─────────────────────────────────────
    Write-LabLog -Message 'Publishing agents as Foundry application endpoints...' -Level Info
    foreach ($agent in $manifest.agents) {
        $agentName = [string]$agent.name
        $appUri    = "$accountPath/projects/$projectName/applications/$agentName`?api-version=$($script:AppApiVersion)"

        # Check if already published
        try {
            $existing = Invoke-WebRequest -Uri $appUri -Method Get -Headers @{ Authorization = "Bearer $armToken"; 'Content-Type' = 'application/json' } -SkipHttpErrorCheck -ErrorAction Stop
            if ([int]$existing.StatusCode -eq 200) {
                Write-LabLog -Message "Application already exists: $agentName" -Level Info
                $appResult = $existing.Content | ConvertFrom-Json
                $agent | Add-Member -NotePropertyName 'baseUrl' -NotePropertyValue ([string]$appResult.properties.baseUrl) -Force
                continue
            }
        } catch { }

        $appBody = @{
            properties = @{
                displayName = $agentName
                agents      = @(@{ agentName = $agentName })
            }
        } | ConvertTo-Json -Depth 5 -Compress

        try {
            $appResp = Invoke-WebRequest -Uri $appUri -Method Put `
                -Headers @{ Authorization = "Bearer $armToken"; 'Content-Type' = 'application/json' } `
                -Body $appBody -SkipHttpErrorCheck -ErrorAction Stop

            if ([int]$appResp.StatusCode -lt 400) {
                $appResult = $appResp.Content | ConvertFrom-Json
                $baseUrl   = [string]$appResult.properties.baseUrl
                $agent | Add-Member -NotePropertyName 'baseUrl' -NotePropertyValue $baseUrl -Force
                Write-LabLog -Message "Published agent: $agentName → $baseUrl" -Level Success
            }
            else {
                Write-LabLog -Message "Publish failed for '$agentName' (HTTP $($appResp.StatusCode)): $($appResp.Content)" -Level Warning
            }
        }
        catch {
            Write-LabLog -Message "Error publishing agent '$agentName'`: $($_.Exception.Message)" -Level Warning
        }
    }

    # ── 8. Generate Teams/Copilot declarative agent packages ─────────────────
    Write-LabLog -Message 'Generating Teams/Copilot declarative agent packages...' -Level Info

    $tenantId  = [string](Get-AzContext).Tenant.Id
    $packagesDir = Join-Path $PWD 'packages' 'foundry'
    if (-not (Test-Path $packagesDir)) {
        New-Item -ItemType Directory -Path $packagesDir -Force | Out-Null
    }

    foreach ($agent in $manifest.agents) {
        $agentName   = [string]$agent.name
        $agentConfig = $Config.workloads.foundry.agents |
            Where-Object { "$($Config.prefix)-$($_.name)" -eq $agentName } |
            Select-Object -First 1

        if (-not $agentConfig) {
            Write-LabLog -Message "Skipping package for '$agentName' — agent config not found." -Level Warning
            continue
        }

        try {
            $zipPath = New-FoundryAgentPackage `
                -Agent        $agent `
                -Prefix       ([string]$Config.prefix) `
                -AgentConfig  $agentConfig `
                -OutputDir    $packagesDir `
                -TenantId     $tenantId

            $agent | Add-Member -NotePropertyName 'packagePath' -NotePropertyValue $zipPath -Force
            Write-LabLog -Message "Package: $zipPath" -Level Success
        }
        catch {
            Write-LabLog -Message "Error generating package for '$agentName'`: $($_.Exception.Message)" -Level Warning
        }
    }

    return $manifest
}


# ─── Remove-Foundry ───────────────────────────────────────────────────────────

function Remove-Foundry {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Config,

        [Parameter()]
        [PSCustomObject]$Manifest
    )

    $fw = $Config.workloads.foundry

    $subscriptionId = if ($Manifest -and $Manifest.PSObject.Properties['subscriptionId']) {
        [string]$Manifest.subscriptionId
    }
    else { [string]$fw.subscriptionId }

    $resourceGroup = if ($Manifest -and $Manifest.PSObject.Properties['resourceGroup']) {
        [string]$Manifest.resourceGroup
    }
    else { [string]$fw.resourceGroup }

    $accountName     = [string]$fw.accountName
    $projectName     = [string]$fw.projectName
    $modelDeployName = [string]$fw.modelDeploymentName

    $projectEndpoint = if ($Manifest -and $Manifest.PSObject.Properties['projectEndpoint'] -and
        -not [string]::IsNullOrWhiteSpace([string]$Manifest.projectEndpoint)) {
        [string]$Manifest.projectEndpoint
    }
    else {
        "https://$accountName.services.ai.azure.com/api/projects/$projectName"
    }

    if ([string]::IsNullOrWhiteSpace($subscriptionId) -or $subscriptionId -eq 'YOUR_SUBSCRIPTION_ID') {
        Write-LabLog -Message 'foundry.subscriptionId not configured — skipping Foundry teardown.' -Level Warning
        return
    }

    if (-not $PSCmdlet.ShouldProcess("Foundry lab '$($Config.prefix)'", 'Remove Foundry agents, project, and account')) {
        return
    }

    Set-AzContext -SubscriptionId $subscriptionId -ErrorAction Stop | Out-Null

    $armToken  = Get-FoundryArmToken
    $dataToken = Get-FoundryDataToken

    $rgPath      = "$($script:ArmBase)/subscriptions/$subscriptionId/resourceGroups/$resourceGroup"
    $accountPath = "$rgPath/providers/Microsoft.CognitiveServices/accounts/$accountName"

    # ── 1. Delete published applications ──────────────────────────────────────
    $agentsToDelete = @()
    if ($Manifest -and $Manifest.PSObject.Properties['agents'] -and $Manifest.agents) {
        $agentsToDelete = @($Manifest.agents)
    }
    else {
        Write-LabLog -Message 'No agent manifest available — delete agents manually in the Foundry portal.' -Level Warning
    }

    $appHeaders = @{ Authorization = "Bearer $armToken"; 'Content-Type' = 'application/json' }
    foreach ($agent in $agentsToDelete) {
        $agentName = [string]$agent.name
        if ([string]::IsNullOrWhiteSpace($agentName)) { continue }
        $appUri = "$accountPath/projects/$projectName/applications/$agentName`?api-version=$($script:AppApiVersion)"
        try {
            $delResp = Invoke-WebRequest -Uri $appUri -Method Delete -Headers $appHeaders -SkipHttpErrorCheck -ErrorAction Stop
            if ([int]$delResp.StatusCode -lt 400) {
                Write-LabLog -Message "Unpublished application: $agentName" -Level Success
            }
        }
        catch {
            Write-LabLog -Message "Error unpublishing application '$agentName'`: $($_.Exception.Message)" -Level Warning
        }
    }

    # ── 2. Delete agents ───────────────────────────────────────────────────────

    $agentHeaders = @{
        'Authorization' = "Bearer $dataToken"
        'Content-Type'  = 'application/json'
    }

    foreach ($agent in $agentsToDelete) {
        $agentId   = [string]$agent.id
        $agentName = [string]$agent.name
        if ([string]::IsNullOrWhiteSpace($agentId)) { continue }

        try {
            $deleteUri   = "$projectEndpoint/agents/$($agentId)?api-version=$($script:AgentApiVersion)"
            $delResponse = Invoke-WebRequest -Uri $deleteUri -Method Delete -Headers $agentHeaders `
                -SkipHttpErrorCheck -ErrorAction Stop

            if ([int]$delResponse.StatusCode -lt 400) {
                Write-LabLog -Message "Deleted agent: $agentName ($agentId)" -Level Success
            }
            else {
                Write-LabLog -Message "Agent delete HTTP $($delResponse.StatusCode) for '$agentName' — may already be removed." -Level Warning
            }
        }
        catch {
            Write-LabLog -Message "Error deleting agent '$agentName' ($agentId)`: $($_.Exception.Message)" -Level Warning
        }
    }

    # ── 2. Delete Foundry Project ──────────────────────────────────────────────
    Write-LabLog -Message "Removing Foundry project: $projectName" -Level Info
    try {
        Invoke-ArmDelete -Uri "$accountPath/projects/$projectName`?api-version=$($script:ArmApiVersion)" `
            -Token $armToken -Async
        Write-LabLog -Message "Removed Foundry project: $projectName" -Level Success
    }
    catch {
        Write-LabLog -Message "Error removing Foundry project '$projectName'`: $($_.Exception.Message)" -Level Warning
    }

    # ── 3. Delete Model Deployment ─────────────────────────────────────────────
    Write-LabLog -Message "Removing model deployment: $modelDeployName" -Level Info
    try {
        Invoke-ArmDelete -Uri "$accountPath/deployments/$modelDeployName`?api-version=$($script:ArmApiVersion)" `
            -Token $armToken -Async
        Write-LabLog -Message "Removed model deployment: $modelDeployName" -Level Success
    }
    catch {
        Write-LabLog -Message "Error removing model deployment '$modelDeployName'`: $($_.Exception.Message)" -Level Warning
    }

    # ── 4. Delete Foundry Account ──────────────────────────────────────────────
    Write-LabLog -Message "Removing Foundry account: $accountName" -Level Info
    try {
        Invoke-ArmDelete -Uri "$accountPath`?api-version=$($script:ArmApiVersion)" `
            -Token $armToken -Async
        Write-LabLog -Message "Removed Foundry account: $accountName" -Level Success
    }
    catch {
        Write-LabLog -Message "Error removing Foundry account '$accountName'`: $($_.Exception.Message)" -Level Warning
    }

    # ── 5. Delete Resource Group (cascades remaining resources) ───────────────
    Write-LabLog -Message "Removing resource group: $resourceGroup" -Level Info
    try {
        Invoke-ArmDelete -Uri "$rgPath`?api-version=2021-04-01" -Token $armToken -Async
        Write-LabLog -Message "Removed resource group: $resourceGroup" -Level Success
    }
    catch {
        Write-LabLog -Message "Error removing resource group '$resourceGroup'`: $($_.Exception.Message)" -Level Warning
    }
}

Export-ModuleMember -Function @(
    'Deploy-Foundry'
    'Remove-Foundry'
)
