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
