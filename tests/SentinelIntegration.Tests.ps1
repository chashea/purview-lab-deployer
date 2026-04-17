#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:ModulePath = Join-Path $PSScriptRoot '..' 'modules' 'SentinelIntegration.psm1'
    $script:LoggingPath = Join-Path $PSScriptRoot '..' 'modules' 'Logging.psm1'
    Import-Module $script:LoggingPath -Force
    Import-Module $script:ModulePath -Force

    $script:ConfigPath = Join-Path $PSScriptRoot '..' 'configs' 'commercial' 'purview-sentinel-demo.json'
    $script:ArmRoot = Join-Path $PSScriptRoot '..' 'modules' 'assets' 'sentinel' 'arm'

    function Get-TestConfig {
        $c = Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json
        $c.workloads.sentinelIntegration.subscriptionId = '11111111-2222-3333-4444-555555555555'
        return $c
    }
}

Describe 'Demo config' {
    It 'Exists and is valid JSON' {
        Test-Path $script:ConfigPath | Should -Be $true
        { Get-Content -Path $script:ConfigPath -Raw | ConvertFrom-Json } | Should -Not -Throw
    }

    It 'Declares sentinelIntegration enabled with required fields' {
        $c = Get-TestConfig
        $c.workloads.sentinelIntegration.enabled | Should -Be $true
        $c.workloads.sentinelIntegration.resourceGroup.name | Should -Not -BeNullOrEmpty
        $c.workloads.sentinelIntegration.workspace.name | Should -Not -BeNullOrEmpty
        $c.workloads.sentinelIntegration.analyticsRules.Count | Should -BeGreaterOrEqual 1
    }
}

Describe 'Get-SentinelScope' {
    It 'Returns a scope hashtable when config is complete' {
        $c = Get-TestConfig
        $scope = Get-SentinelScope -Config $c
        $scope | Should -Not -BeNullOrEmpty
        $scope.SubscriptionId | Should -Be '11111111-2222-3333-4444-555555555555'
        $scope.ResourceGroup | Should -Be 'PVSentinel-rg'
        $scope.WorkspaceName | Should -Be 'PVSentinel-ws'
    }

    It 'Throws when subscriptionId is missing' {
        $c = Get-TestConfig
        $c.workloads.sentinelIntegration.subscriptionId = ''
        { Get-SentinelScope -Config $c } | Should -Throw '*subscriptionId*'
    }
}

Describe 'Expand-SentinelTemplate' {
    It 'Substitutes {{key}} tokens' {
        $tpl = '{"name":"{{prefix}}-foo","ws":"{{workspaceName}}"}'
        $out = Expand-SentinelTemplate -Template $tpl -Tokens @{ prefix = 'PV'; workspaceName = 'ws1' }
        $out | Should -Be '{"name":"PV-foo","ws":"ws1"}'
    }

    It 'Leaves unknown tokens in place' {
        $tpl = '{"x":"{{unknown}}"}'
        $out = Expand-SentinelTemplate -Template $tpl -Tokens @{ }
        $out | Should -Match '\{\{unknown\}\}'
    }
}

Describe 'Test-SentinelRgDeletionAuthorized — safety gate' {
    BeforeEach {
        $script:scope = @{
            SubscriptionId      = '11111111-2222-3333-4444-555555555555'
            ResourceGroup       = 'PVSentinel-rg'
            WorkspaceName       = 'PVSentinel-ws'
            Location            = 'eastus'
            ArmBase             = 'https://management.azure.com'
            WorkspaceResourceId = '/subscriptions/11111111-2222-3333-4444-555555555555/resourceGroups/PVSentinel-rg/providers/Microsoft.OperationalInsights/workspaces/PVSentinel-ws'
        }
        $script:manifest = [pscustomobject]@{
            subscriptionId       = '11111111-2222-3333-4444-555555555555'
            resourceGroup        = 'PVSentinel-rg'
            createdResourceGroup = $true
            onboardedBy          = 'purview-lab-deployer'
        }
    }

    It 'Refuses without -ForceDeleteResourceGroup switch' {
        $r = & { $WhatIfPreference = $true; Test-SentinelRgDeletionAuthorized -Scope $script:scope -Manifest $script:manifest }
        $r.authorized | Should -Be $false
        $r.reasons | Should -Contain 'ForceDeleteResourceGroup switch was not provided.'
    }

    It 'Refuses when manifest is null' {
        $r = & { $WhatIfPreference = $true; Test-SentinelRgDeletionAuthorized -Scope $script:scope -Manifest $null -ForceDeleteResourceGroup }
        $r.authorized | Should -Be $false
    }

    It 'Refuses when createdResourceGroup is false' {
        $script:manifest.createdResourceGroup = $false
        $r = & { $WhatIfPreference = $true; Test-SentinelRgDeletionAuthorized -Scope $script:scope -Manifest $script:manifest -ForceDeleteResourceGroup }
        $r.authorized | Should -Be $false
    }

    It 'Refuses when RG name does not match' {
        $script:manifest.resourceGroup = 'some-other-rg'
        $r = & { $WhatIfPreference = $true; Test-SentinelRgDeletionAuthorized -Scope $script:scope -Manifest $script:manifest -ForceDeleteResourceGroup }
        $r.authorized | Should -Be $false
    }

    It 'Refuses when subscriptionId does not match' {
        $script:manifest.subscriptionId = '99999999-9999-9999-9999-999999999999'
        $r = & { $WhatIfPreference = $true; Test-SentinelRgDeletionAuthorized -Scope $script:scope -Manifest $script:manifest -ForceDeleteResourceGroup }
        $r.authorized | Should -Be $false
    }

    It 'Authorizes when all checks pass (WhatIf bypasses live tag check)' {
        Mock -ModuleName SentinelIntegration Test-SentinelWhatIf { $true }
        $r = Test-SentinelRgDeletionAuthorized -Scope $script:scope -Manifest $script:manifest -ForceDeleteResourceGroup
        $r.authorized | Should -Be $true
        $r.reasons.Count | Should -Be 0
    }
}

Describe 'WhatIf mutation boundary' {
    It 'Deploy-SentinelIntegration with -WhatIf never invokes az' {
        Mock -ModuleName SentinelIntegration Invoke-SentinelAzRest { throw "az must not be called in WhatIf" }
        $c = Get-TestConfig
        { Deploy-SentinelIntegration -Config $c -WhatIf } | Should -Not -Throw
        Should -Invoke -ModuleName SentinelIntegration Invoke-SentinelAzRest -Times 0
    }

    It 'Remove-SentinelIntegration with -WhatIf never invokes az' {
        Mock -ModuleName SentinelIntegration Invoke-SentinelAzRest { throw "az must not be called in WhatIf" }
        $c = Get-TestConfig
        $manifest = [pscustomobject]@{
            subscriptionId       = $c.workloads.sentinelIntegration.subscriptionId
            resourceGroup        = 'PVSentinel-rg'
            workspaceName        = 'PVSentinel-ws'
            createdResourceGroup = $true
            connectors           = @()
            rules                = @()
            workbooks            = @()
        }
        { Remove-SentinelIntegration -Config $c -Manifest $manifest -WhatIf } | Should -Not -Throw
        Should -Invoke -ModuleName SentinelIntegration Invoke-SentinelAzRest -Times 0
    }
}

Describe 'Remove-SentinelIntegration without manifest' {
    It 'Refuses destructive operations when no manifest is present (not WhatIf)' {
        Mock -ModuleName SentinelIntegration Invoke-SentinelAzRest { throw "should not be called" }
        $c = Get-TestConfig
        { Remove-SentinelIntegration -Config $c -Manifest $null } | Should -Not -Throw
        Should -Invoke -ModuleName SentinelIntegration Invoke-SentinelAzRest -Times 0
    }
}

Describe 'ARM assets' {
    It 'Has at least 8 JSON asset files' {
        $assetFiles = Get-ChildItem -Path $script:ArmRoot -Recurse -Filter *.json
        $assetFiles.Count | Should -BeGreaterOrEqual 8
    }

    It 'Every ARM asset is valid JSON' {
        $assetFiles = Get-ChildItem -Path $script:ArmRoot -Recurse -Filter *.json
        foreach ($file in $assetFiles) {
            { Get-Content -Path $file.FullName -Raw | ConvertFrom-Json } | Should -Not -Throw
        }
    }
}

Describe 'Install-SentinelContentHubSolution' {
    BeforeEach {
        $script:scope = @{
            ArmBase             = 'https://management.azure.com'
            WorkspaceResourceId = '/subscriptions/s/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/ws'
            WorkspaceName       = 'ws'
        }
    }

    It 'WhatIf mode: returns $true without calling ARM' {
        Mock -ModuleName SentinelIntegration Test-SentinelWhatIf { return $true }
        Mock -ModuleName SentinelIntegration Invoke-SentinelAzRest { throw 'should not be called' }
        $result = Install-SentinelContentHubSolution -Scope $script:scope -SolutionDisplayName 'Microsoft Defender XDR'
        $result | Should -Be $true
        Should -Invoke -ModuleName SentinelIntegration Invoke-SentinelAzRest -Times 0
    }

    It 'Installs matching solution by displayName and PUTs to contentPackages' {
        Mock -ModuleName SentinelIntegration Test-SentinelWhatIf { return $false }
        Mock -ModuleName SentinelIntegration Invoke-SentinelAzRest {
            if ($Method -eq 'GET') {
                return [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            properties = [pscustomobject]@{
                                displayName = 'Some Other Solution'
                                contentId   = 'other'
                                version     = '1.0.0'
                            }
                        },
                        [pscustomobject]@{
                            properties = [pscustomobject]@{
                                displayName = 'Microsoft Defender XDR'
                                contentId   = 'azuresentinel.azure-sentinel-solution-microsoft365defender'
                                version     = '3.0.13'
                            }
                        }
                    )
                }
            }
            return [pscustomobject]@{ id = 'installed' }
        }

        $result = Install-SentinelContentHubSolution -Scope $script:scope -SolutionDisplayName 'Microsoft Defender XDR'
        $result | Should -Be $true
        Should -Invoke -ModuleName SentinelIntegration Invoke-SentinelAzRest -Times 1 -ParameterFilter {
            $Method -eq 'PUT' -and $Url -like '*contentPackages/azuresentinel.azure-sentinel-solution-microsoft365defender*'
        }
    }

    It 'Returns $false when the solution is not in the catalog' {
        Mock -ModuleName SentinelIntegration Test-SentinelWhatIf { return $false }
        Mock -ModuleName SentinelIntegration Invoke-SentinelAzRest {
            return [pscustomobject]@{ value = @() }
        }
        $result = Install-SentinelContentHubSolution -Scope $script:scope -SolutionDisplayName 'Nonexistent Solution'
        $result | Should -Be $false
    }

    It 'Returns $false when the install PUT fails' {
        Mock -ModuleName SentinelIntegration Test-SentinelWhatIf { return $false }
        Mock -ModuleName SentinelIntegration Invoke-SentinelAzRest {
            if ($Method -eq 'GET') {
                return [pscustomobject]@{
                    value = @(
                        [pscustomobject]@{
                            properties = [pscustomobject]@{
                                displayName = 'Microsoft Defender XDR'
                                contentId   = 'azuresentinel.azure-sentinel-solution-microsoft365defender'
                                version     = '3.0.13'
                            }
                        }
                    )
                }
            }
            throw 'ARM install failed'
        }
        $result = Install-SentinelContentHubSolution -Scope $script:scope -SolutionDisplayName 'Microsoft Defender XDR'
        $result | Should -Be $false
    }
}
