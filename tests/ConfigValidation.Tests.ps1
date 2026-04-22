#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'modules' 'Prerequisites.psm1'
    Import-Module $modulePath -Force
}

Describe 'Test-LabConfigValidity' {
    It 'Returns true for valid config with enabled workloads' {
        $config = [PSCustomObject]@{
            labName   = 'Test Lab'
            prefix    = 'PVTest'
            domain    = 'test.com'
            workloads = [PSCustomObject]@{
                dlp = [PSCustomObject]@{
                    enabled  = $true
                    policies = @(
                        [PSCustomObject]@{ name = 'Test Policy' }
                    )
                }
                testUsers = [PSCustomObject]@{
                    enabled = $true
                    users   = @(
                        [PSCustomObject]@{ displayName = 'Test User' }
                    )
                }
            }
        }
        Test-LabConfigValidity -Config $config | Should -Be $true
    }

    It 'Returns true when workloads are disabled (no validation needed)' {
        $config = [PSCustomObject]@{
            labName   = 'Test Lab'
            prefix    = 'PVTest'
            domain    = 'test.com'
            workloads = [PSCustomObject]@{
                dlp = [PSCustomObject]@{
                    enabled = $false
                }
            }
        }
        Test-LabConfigValidity -Config $config | Should -Be $true
    }

    It 'Warns when enabled workload has missing required field' {
        $config = [PSCustomObject]@{
            labName   = 'Test Lab'
            prefix    = 'PVTest'
            domain    = 'test.com'
            workloads = [PSCustomObject]@{
                dlp = [PSCustomObject]@{
                    enabled = $true
                }
            }
        }
        Test-LabConfigValidity -Config $config -WarningVariable w 3>$null | Should -Be $false
        $w | Should -Not -BeNullOrEmpty
    }

    It 'Warns when enabled workload has empty array' {
        $config = [PSCustomObject]@{
            labName   = 'Test Lab'
            prefix    = 'PVTest'
            domain    = 'test.com'
            workloads = [PSCustomObject]@{
                sensitivityLabels = [PSCustomObject]@{
                    enabled = $true
                    labels  = @()
                }
            }
        }
        Test-LabConfigValidity -Config $config -WarningVariable w 3>$null | Should -Be $false
    }

    It 'Returns false when no workloads section exists' {
        $config = [PSCustomObject]@{
            labName = 'Test Lab'
            prefix  = 'PVTest'
            domain  = 'test.com'
        }
        Test-LabConfigValidity -Config $config -WarningVariable w 3>$null | Should -Be $false
    }

    It 'Validates all known workload types' {
        $configDir = Join-Path $PSScriptRoot '..' 'configs' 'commercial'
        $configPath = Join-Path $configDir 'basic-lab-demo.json'
        if (Test-Path $configPath) {
            $config = Import-LabConfig -ConfigPath $configPath
            $result = Test-LabConfigValidity -Config $config
            $result | Should -Be $true
        }
    }
}

Describe 'Copilot DLP config shape' {
    BeforeAll {
        $script:CopilotConfigs = @{
            commercial = Join-Path $PSScriptRoot '..' 'configs' 'commercial' 'copilot-dlp-demo.json'
            gcc        = Join-Path $PSScriptRoot '..' 'configs' 'gcc' 'copilot-dlp-demo.json'
        }
    }

    Context 'commercial profile' {
        BeforeAll {
            $script:CommercialConfig = Get-Content $script:CopilotConfigs.commercial -Raw | ConvertFrom-Json
        }

        It 'has at least one DLP policy scoped to CopilotExperiences' {
            $copilotPolicies = @($script:CommercialConfig.workloads.dlp.policies |
                    Where-Object { @($_.locations) -contains 'CopilotExperiences' })
            $copilotPolicies.Count | Should -BeGreaterThan 0
        }

        It 'has both a prompt SIT block policy and a labeled content block policy' {
            $policyModes = @($script:CommercialConfig.workloads.dlp.policies.policyMode)
            $policyModes | Should -Contain 'copilotPromptBlock'
            $policyModes | Should -Contain 'copilotLabelBlock'
        }

        It 'deploys DLP policies in simulation mode by default' {
            [bool]$script:CommercialConfig.workloads.dlp.simulationMode | Should -Be $true
        }

        It 'every label referenced in a Copilot label rule exists in sensitivityLabels' {
            $declaredLabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($parent in @($script:CommercialConfig.workloads.sensitivityLabels.labels)) {
                $null = $declaredLabels.Add("$($script:CommercialConfig.prefix)-$($parent.name.Replace(' ','-'))")
                foreach ($child in @($parent.sublabels)) {
                    $null = $declaredLabels.Add("$($script:CommercialConfig.prefix)-$($parent.name.Replace(' ','-'))-$($child.name.Replace(' ','-'))")
                }
            }

            $referencedLabels = @()
            foreach ($policy in @($script:CommercialConfig.workloads.dlp.policies)) {
                if (@($policy.locations) -notcontains 'CopilotExperiences') { continue }
                foreach ($label in @($policy.labels)) { $referencedLabels += $label }
                foreach ($rule in @($policy.rules)) {
                    foreach ($label in @($rule.labels)) { $referencedLabels += $label }
                }
            }

            foreach ($ref in ($referencedLabels | Sort-Object -Unique)) {
                $declaredLabels.Contains($ref) | Should -Be $true -Because "label '$ref' is referenced by a Copilot DLP rule but not declared under sensitivityLabels"
            }
        }

        It 'group members reference users declared in the users list' {
            $userUpns = @($script:CommercialConfig.workloads.testUsers.users.upn) |
                ForEach-Object { ($_ -split '@')[0] } |
                Where-Object { $_ }
            foreach ($group in @($script:CommercialConfig.workloads.testUsers.groups)) {
                foreach ($member in @($group.members)) {
                    $userUpns | Should -Contain $member -Because "group '$($group.displayName)' references missing member '$member'"
                }
            }
        }

        It 'Copilot prompt SIT rules use enforcement.action = block' {
            $promptPolicy = $script:CommercialConfig.workloads.dlp.policies |
                Where-Object { $_.policyMode -eq 'copilotPromptBlock' } |
                Select-Object -First 1
            $promptPolicy | Should -Not -BeNullOrEmpty
            foreach ($rule in @($promptPolicy.rules)) {
                $rule.enforcement.action | Should -Be 'block'
            }
        }
    }

    Context 'GCC profile' {
        BeforeAll {
            $script:GccConfig = Get-Content $script:CopilotConfigs.gcc -Raw | ConvertFrom-Json
        }


        It 'has only label-based Copilot DLP policies (no prompt SIT — not supported in GCC)' {
            $copilotPolicies = @($script:GccConfig.workloads.dlp.policies |
                    Where-Object { @($_.locations) -contains 'CopilotExperiences' })
            $copilotPolicies.Count | Should -BeGreaterThan 0
            foreach ($policy in $copilotPolicies) {
                $policy.policyMode | Should -Not -Be 'copilotPromptBlock' -Because 'SIT-based Copilot DLP is not supported in GCC'
            }
        }

        It 'every label referenced in a Copilot label rule exists in sensitivityLabels' {
            $declaredLabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($parent in @($script:GccConfig.workloads.sensitivityLabels.labels)) {
                $null = $declaredLabels.Add("$($script:GccConfig.prefix)-$($parent.name.Replace(' ','-'))")
                foreach ($child in @($parent.sublabels)) {
                    $null = $declaredLabels.Add("$($script:GccConfig.prefix)-$($parent.name.Replace(' ','-'))-$($child.name.Replace(' ','-'))")
                }
            }

            $referencedLabels = @()
            foreach ($policy in @($script:GccConfig.workloads.dlp.policies)) {
                if (@($policy.locations) -notcontains 'CopilotExperiences') { continue }
                foreach ($label in @($policy.labels)) { $referencedLabels += $label }
                foreach ($rule in @($policy.rules)) {
                    foreach ($label in @($rule.labels)) { $referencedLabels += $label }
                }
            }

            foreach ($ref in ($referencedLabels | Sort-Object -Unique)) {
                $declaredLabels.Contains($ref) | Should -Be $true -Because "label '$ref' is referenced by a Copilot DLP rule but not declared under sensitivityLabels"
            }
        }
    }
}

Describe 'Shadow AI config shape' {
    BeforeAll {
        $script:ShadowAiConfigs = @{
            commercial = Join-Path $PSScriptRoot '..' 'configs' 'commercial' 'shadow-ai-demo.json'
            gcc        = Join-Path $PSScriptRoot '..' 'configs' 'gcc' 'shadow-ai-demo.json'
        }
    }

    Context 'commercial profile' {
        BeforeAll {
            $script:ShadowAiCommercial = Get-Content $script:ShadowAiConfigs.commercial -Raw | ConvertFrom-Json
        }

        It 'uses CopilotExperiences (not EnterpriseAI) for Copilot-targeting policies' {
            $copilotPolicies = @($script:ShadowAiCommercial.workloads.dlp.policies |
                    Where-Object { @($_.locations) -contains 'CopilotExperiences' })
            $copilotPolicies.Count | Should -BeGreaterOrEqual 1
        }

        It 'has no lingering EnterpriseAI location usage' {
            $enterpriseAiPolicies = @($script:ShadowAiCommercial.workloads.dlp.policies |
                    Where-Object { @($_.locations) -contains 'EnterpriseAI' })
            $enterpriseAiPolicies.Count | Should -Be 0
        }

        It 'has at least 5 DLP policies covering Devices, Browser, Network, CopilotExperiences' {
            $policies = @($script:ShadowAiCommercial.workloads.dlp.policies)
            $policies.Count | Should -BeGreaterOrEqual 5

            $locations = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($p in $policies) {
                foreach ($loc in @($p.locations)) { $null = $locations.Add([string]$loc) }
            }
            $locations | Should -Contain 'Devices'
            $locations | Should -Contain 'Browser'
            $locations | Should -Contain 'Network'
            $locations | Should -Contain 'CopilotExperiences'
        }

        It 'deploys DLP policies in simulation mode by default' {
            [bool]$script:ShadowAiCommercial.workloads.dlp.simulationMode | Should -Be $true
        }

        It 'every test document has a resolvable labelIdentity sublabel' {
            $declaredSublabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($parent in @($script:ShadowAiCommercial.workloads.sensitivityLabels.labels)) {
                foreach ($child in @($parent.sublabels)) {
                    $null = $declaredSublabels.Add("$($script:ShadowAiCommercial.prefix)-$($parent.name.Replace(' ','-'))-$($child.name.Replace(' ','-'))")
                }
            }

            foreach ($doc in @($script:ShadowAiCommercial.workloads.testData.documents)) {
                $id = if ($doc.PSObject.Properties['labelIdentity']) { [string]$doc.labelIdentity } else { $null }
                if (-not [string]::IsNullOrWhiteSpace($id)) {
                    $declaredSublabels.Contains($id) | Should -Be $true -Because "document label '$id' must reference a declared sublabel (parent labels cannot be applied to content)"
                }
            }
        }

        It 'group members reference users declared in the users list' {
            $userUpns = @($script:ShadowAiCommercial.workloads.testUsers.users.upn) |
                ForEach-Object { ($_ -split '@')[0] } |
                Where-Object { $_ }
            foreach ($group in @($script:ShadowAiCommercial.workloads.testUsers.groups)) {
                foreach ($member in @($group.members)) {
                    $userUpns | Should -Contain $member -Because "group '$($group.displayName)' references missing member '$member'"
                }
            }
        }

        It 'all DLP rules with insiderRiskLevel use valid levels' {
            $validLevels = @('Minor', 'Moderate', 'Elevated')
            foreach ($policy in @($script:ShadowAiCommercial.workloads.dlp.policies)) {
                foreach ($rule in @($policy.rules)) {
                    if ($rule.PSObject.Properties['insiderRiskLevel'] -and -not [string]::IsNullOrWhiteSpace([string]$rule.insiderRiskLevel)) {
                        $validLevels | Should -Contain $rule.insiderRiskLevel
                    }
                }
            }
        }

        It 'has Endpoint DLP browser restriction block list with AI site URLs' {
            $endpointPolicy = $script:ShadowAiCommercial.workloads.dlp.policies |
                Where-Object { @($_.locations) -contains 'Devices' -and $_.PSObject.Properties['endpointDlpBrowserRestrictions'] } |
                Select-Object -First 1
            $endpointPolicy | Should -Not -BeNullOrEmpty
            @($endpointPolicy.endpointDlpBrowserRestrictions.blockedUrls).Count | Should -BeGreaterThan 3
        }

        It 'has retention policies using AI app Applications targeting' {
            $aiRetention = @($script:ShadowAiCommercial.workloads.retention.policies |
                    Where-Object { $_.PSObject.Properties['applications'] -and @($_.applications).Count -gt 0 })
            $aiRetention.Count | Should -BeGreaterOrEqual 1
            $tokens = @()
            foreach ($r in $aiRetention) {
                foreach ($app in @($r.applications)) { $tokens += [string]$app }
            }
            $tokens | Should -Contain 'MicrosoftCopilotExperiences'
        }

        It 'has at least one IRM policy using the Risky AI usage template' {
            $riskyAi = @($script:ShadowAiCommercial.workloads.insiderRisk.policies |
                    Where-Object { $_.template -eq 'Risky AI usage' })
            $riskyAi.Count | Should -BeGreaterOrEqual 1
        }
    }

    Context 'GCC profile' {
        BeforeAll {
            $script:ShadowAiGcc = Get-Content $script:ShadowAiConfigs.gcc -Raw | ConvertFrom-Json
        }

        It 'exists and parses as JSON' {
            $script:ShadowAiGcc | Should -Not -BeNullOrEmpty
            $script:ShadowAiGcc.labName | Should -Not -BeNullOrEmpty
        }

        It 'has at least one DLP policy for Devices location' {
            $devicePolicies = @($script:ShadowAiGcc.workloads.dlp.policies |
                    Where-Object { @($_.locations) -contains 'Devices' })
            $devicePolicies.Count | Should -BeGreaterOrEqual 1
        }
    }
}

Describe 'Integrated AI Security config shape' {
    BeforeAll {
        $script:AiSecConfigs = @{
            commercial = Join-Path $PSScriptRoot '..' 'configs' 'commercial' 'ai-security-demo.json'
            gcc        = Join-Path $PSScriptRoot '..' 'configs' 'gcc' 'ai-security-demo.json'
        }
    }

    Context 'commercial profile' {
        BeforeAll {
            $script:AiSecCommercial = Get-Content $script:AiSecConfigs.commercial -Raw | ConvertFrom-Json
        }

        It 'uses the unified PVAISec prefix' {
            $script:AiSecCommercial.prefix | Should -Be 'PVAISec'
        }

        It 'combines Copilot DLP + Shadow AI + Sentinel workloads' {
            $workloadNames = @($script:AiSecCommercial.workloads.PSObject.Properties.Name)
            $workloadNames | Should -Contain 'dlp'
            $workloadNames | Should -Contain 'insiderRisk'
            $workloadNames | Should -Contain 'sentinelIntegration'
            $workloadNames | Should -Contain 'communicationCompliance'
        }

        It 'has Copilot DLP policies (prompt + label block)' {
            $policyModes = @($script:AiSecCommercial.workloads.dlp.policies.policyMode)
            $policyModes | Should -Contain 'copilotPromptBlock'
            $policyModes | Should -Contain 'copilotLabelBlock'
        }

        It 'has Shadow AI policies across Devices, Browser, Network' {
            $locations = [System.Collections.Generic.HashSet[string]]::new()
            foreach ($p in @($script:AiSecCommercial.workloads.dlp.policies)) {
                foreach ($loc in @($p.locations)) { $null = $locations.Add([string]$loc) }
            }
            $locations | Should -Contain 'Devices'
            $locations | Should -Contain 'Browser'
            $locations | Should -Contain 'Network'
            $locations | Should -Contain 'CopilotExperiences'
        }

        It 'has at least 7 Sentinel analytics rules including AI-specific ones' {
            $rules = @($script:AiSecCommercial.workloads.sentinelIntegration.analyticsRules)
            $rules.Count | Should -BeGreaterOrEqual 7
            $templates = @($rules.template)
            $templates | Should -Contain 'copilot-dlp-prompt-block'
            $templates | Should -Contain 'shadow-ai-paste-upload'
            $templates | Should -Contain 'risky-ai-usage-correlation'
        }

        It 'ships with empty subscriptionId (no hardcoded GUID)' {
            [string]::IsNullOrWhiteSpace([string]$script:AiSecCommercial.workloads.sentinelIntegration.subscriptionId) | Should -Be $true
        }

        It 'every Copilot DLP label rule references a declared sublabel' {
            $declaredSublabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($parent in @($script:AiSecCommercial.workloads.sensitivityLabels.labels)) {
                foreach ($child in @($parent.sublabels)) {
                    $null = $declaredSublabels.Add("$($script:AiSecCommercial.prefix)-$($parent.name.Replace(' ','-'))-$($child.name.Replace(' ','-'))")
                }
            }

            foreach ($policy in @($script:AiSecCommercial.workloads.dlp.policies)) {
                if (@($policy.locations) -notcontains 'CopilotExperiences') { continue }
                foreach ($label in @($policy.labels)) {
                    if ([string]::IsNullOrWhiteSpace([string]$label)) { continue }
                    $declaredSublabels.Contains([string]$label) | Should -Be $true -Because "label '$label' referenced by Copilot DLP policy must exist in sensitivityLabels"
                }
                foreach ($rule in @($policy.rules)) {
                    foreach ($label in @($rule.labels)) {
                        if ([string]::IsNullOrWhiteSpace([string]$label)) { continue }
                        $declaredSublabels.Contains([string]$label) | Should -Be $true -Because "label '$label' in rule '$($rule.name)' must exist"
                    }
                }
            }
        }

        It 'test documents reference declared sublabels' {
            $declaredSublabels = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($parent in @($script:AiSecCommercial.workloads.sensitivityLabels.labels)) {
                foreach ($child in @($parent.sublabels)) {
                    $null = $declaredSublabels.Add("$($script:AiSecCommercial.prefix)-$($parent.name.Replace(' ','-'))-$($child.name.Replace(' ','-'))")
                }
            }

            foreach ($doc in @($script:AiSecCommercial.workloads.testData.documents)) {
                $id = if ($doc.PSObject.Properties['labelIdentity']) { [string]$doc.labelIdentity } else { $null }
                if (-not [string]::IsNullOrWhiteSpace($id)) {
                    $declaredSublabels.Contains($id) | Should -Be $true -Because "document label '$id' must reference a declared sublabel"
                }
            }
        }

        It 'Content Hub solutions includes Microsoft Purview' {
            $solutions = @($script:AiSecCommercial.workloads.sentinelIntegration.additionalContentHubSolutions)
            $solutions | Should -Contain 'Microsoft Purview'
        }

        It 'deploys two workbooks (Purview Signals + AI Risk Signals)' {
            $workbooks = @($script:AiSecCommercial.workloads.sentinelIntegration.workbook.workbooks)
            $workbooks.Count | Should -Be 2
            @($workbooks.asset) | Should -Contain 'purview.json'
            @($workbooks.asset) | Should -Contain 'ai-signals.json'
        }
    }

    Context 'GCC profile' {
        BeforeAll {
            $script:AiSecGcc = Get-Content $script:AiSecConfigs.gcc -Raw | ConvertFrom-Json
        }

        It 'exists and parses' {
            $script:AiSecGcc | Should -Not -BeNullOrEmpty
            $script:AiSecGcc.cloud | Should -Be 'gcc'
        }

        It 'uses Azure Government region' {
            $location = [string]$script:AiSecGcc.workloads.sentinelIntegration.resourceGroup.location
            $location | Should -Match '^usgov'
        }

        It 'uses the same PVAISec prefix as commercial' {
            $script:AiSecGcc.prefix | Should -Be 'PVAISec'
        }
    }
}

Describe 'Sentinel integration config shape' {
    BeforeAll {
        $script:SentinelConfigs = @{
            commercial = Join-Path $PSScriptRoot '..' 'configs' 'commercial' 'purview-sentinel-demo.json'
            gcc        = Join-Path $PSScriptRoot '..' 'configs' 'gcc' 'purview-sentinel-demo.json'
        }
        $script:ValidConnectorKinds = @('MicrosoftThreatProtection', 'OfficeIRM', 'Office365')
        $script:ConnectorAssetDir = Join-Path $PSScriptRoot '..' 'modules' 'assets' 'sentinel' 'arm' 'connectors'
        $script:RuleAssetDir = Join-Path $PSScriptRoot '..' 'modules' 'assets' 'sentinel' 'arm' 'rules'
    }

    Context 'commercial profile' {
        BeforeAll {
            $script:SentinelCommercial = Get-Content $script:SentinelConfigs.commercial -Raw | ConvertFrom-Json
        }

        It 'ships with an empty subscriptionId (no hardcoded tenant-specific GUID)' {
            # Either empty or a valid placeholder, but NEVER a real GUID that would leak in the repo
            $subId = [string]$script:SentinelCommercial.workloads.sentinelIntegration.subscriptionId
            $isEmpty = [string]::IsNullOrWhiteSpace($subId)
            $isPlaceholder = $subId -match '<.*>' -or $subId -eq '00000000-0000-0000-0000-000000000000'
            ($isEmpty -or $isPlaceholder) | Should -Be $true -Because 'repo must not ship a real subscription GUID'
        }

        It 'has required resourceGroup.name and location' {
            $script:SentinelCommercial.workloads.sentinelIntegration.resourceGroup.name | Should -Not -BeNullOrEmpty
            $script:SentinelCommercial.workloads.sentinelIntegration.resourceGroup.location | Should -Not -BeNullOrEmpty
        }

        It 'has workspace name and retention within supported range (4-730 days)' {
            $ws = $script:SentinelCommercial.workloads.sentinelIntegration.workspace
            $ws.name | Should -Not -BeNullOrEmpty
            [int]$ws.retentionDays | Should -BeGreaterOrEqual 4
            [int]$ws.retentionDays | Should -BeLessOrEqual 730
        }

        It 'enables at least one data connector' {
            $connectors = $script:SentinelCommercial.workloads.sentinelIntegration.connectors
            $enabledCount = @($connectors.PSObject.Properties | Where-Object { [bool]$_.Value.enabled }).Count
            $enabledCount | Should -BeGreaterThan 0
        }

        It 'every analytics rule template has a matching ARM asset file' {
            foreach ($rule in @($script:SentinelCommercial.workloads.sentinelIntegration.analyticsRules)) {
                $assetPath = Join-Path $script:RuleAssetDir "$($rule.template).json"
                Test-Path $assetPath | Should -Be $true -Because "rule template '$($rule.template)' must have an ARM asset at $assetPath"
            }
        }

        It 'all connector ARM assets use valid MS Learn kinds' {
            foreach ($asset in (Get-ChildItem -Path $script:ConnectorAssetDir -Filter '*.json')) {
                $payload = Get-Content $asset.FullName -Raw | ConvertFrom-Json
                $script:ValidConnectorKinds | Should -Contain $payload.kind -Because "$($asset.Name) has unexpected kind '$($payload.kind)' — see MS Learn dataConnectors schema"
            }
        }

        It 'IRM connector uses OfficeIRM kind (not MicrosoftPurviewInformationProtection)' {
            $irm = Get-Content (Join-Path $script:ConnectorAssetDir 'insiderRiskManagement.json') -Raw | ConvertFrom-Json
            $irm.kind | Should -Be 'OfficeIRM' -Because 'MicrosoftPurviewInformationProtection is a different connector (Information Protection labels), not IRM'
        }

        It 'every analytics rule asset references a table documented in MS Learn' {
            $knownTables = @('SecurityAlert', 'OfficeActivity', 'DeviceEvents', 'PurviewDataSensitivityLogs', 'AlertInfo', 'AlertEvidence', 'CloudAppEvents', 'DataSecurityEvents')
            foreach ($asset in (Get-ChildItem -Path $script:RuleAssetDir -Filter '*.json')) {
                $payload = Get-Content $asset.FullName -Raw | ConvertFrom-Json
                $query = [string]$payload.properties.query
                # Rule must reference at least one known table
                $usesKnown = $false
                foreach ($t in $knownTables) {
                    if ($query -match "\b$t\b") { $usesKnown = $true; break }
                }
                $usesKnown | Should -Be $true -Because "$($asset.Name) query doesn't reference any known Sentinel/Defender table"
            }
        }
    }

    Context 'GCC profile' {
        BeforeAll {
            $script:SentinelGcc = Get-Content $script:SentinelConfigs.gcc -Raw | ConvertFrom-Json
        }

        It 'exists and parses' {
            $script:SentinelGcc | Should -Not -BeNullOrEmpty
            $script:SentinelGcc.cloud | Should -Be 'gcc'
        }

        It 'uses Azure Government region for resource group' {
            $location = [string]$script:SentinelGcc.workloads.sentinelIntegration.resourceGroup.location
            $location | Should -Match '^usgov' -Because 'GCC profile must deploy to an Azure Government region'
        }

        It 'ships with empty subscriptionId' {
            $subId = [string]$script:SentinelGcc.workloads.sentinelIntegration.subscriptionId
            [string]::IsNullOrWhiteSpace($subId) | Should -Be $true
        }
    }
}
