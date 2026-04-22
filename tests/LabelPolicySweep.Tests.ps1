#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $script:LoggingPath = Join-Path $PSScriptRoot '..' 'modules' 'Logging.psm1'
    $script:SensPath = Join-Path $PSScriptRoot '..' 'modules' 'SensitivityLabels.psm1'
    $script:RetPath = Join-Path $PSScriptRoot '..' 'modules' 'Retention.psm1'

    Import-Module $script:LoggingPath -Force
    Import-Module $script:SensPath -Force
    Import-Module $script:RetPath -Force

    # Inject Exchange Online / Security & Compliance cmdlet stubs into global scope
    # so both modules can resolve them and Pester's Mock -ModuleName can shadow them.
    # Stubs accept any args via $args - Pester replaces them before any real invocation.
    function global:Get-AutoSensitivityLabelRule { $null = $args }
    function global:Remove-AutoSensitivityLabelRule { $null = $args }
    function global:Get-AutoSensitivityLabelPolicy { $null = $args }
    function global:Remove-AutoSensitivityLabelPolicy { $null = $args }
    function global:Get-LabelPolicyRule { $null = $args }
    function global:Remove-LabelPolicyRule { $null = $args }
    function global:Get-LabelPolicy { $null = $args }
    function global:Remove-LabelPolicy { $null = $args }
    function global:Get-Label { $null = $args }
    function global:Remove-Label { $null = $args }
    function global:Get-RetentionComplianceRule { $null = $args }
    function global:Remove-RetentionComplianceRule { $null = $args }
    function global:Get-RetentionCompliancePolicy { $null = $args }
    function global:Remove-RetentionCompliancePolicy { $null = $args }
    function global:Get-ComplianceTag { $null = $args }
    function global:Remove-ComplianceTag { $null = $args }

    function Get-SensTestConfig {
        [pscustomobject]@{
            prefix = 'PVTest'
            workloads = [pscustomobject]@{
                sensitivityLabels = [pscustomobject]@{
                    enabled = $true
                    labels = @(
                        [pscustomobject]@{
                            name = 'Confidential'
                            sublabels = @(
                                [pscustomobject]@{ name = 'Internal' }
                            )
                        }
                    )
                    autoLabelPolicies = @(
                        [pscustomobject]@{ name = 'Auto-SSN' }
                    )
                }
            }
        }
    }

    function Get-RetTestConfig {
        [pscustomobject]@{
            prefix = 'PVTest'
            workloads = [pscustomobject]@{
                retention = [pscustomobject]@{
                    enabled = $true
                    labels = @(
                        [pscustomobject]@{ name = 'Fin-Records' }
                    )
                    policies = @(
                        [pscustomobject]@{ name = 'Baseline-Retention' }
                    )
                }
            }
        }
    }
}

Describe 'Remove-SensitivityLabels switch behavior' {
    BeforeEach {
        $script:callOrder = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName SensitivityLabels Get-AutoSensitivityLabelRule { [pscustomobject]@{ Name = 'stub' } }
        Mock -ModuleName SensitivityLabels Remove-AutoSensitivityLabelRule {
            param($Identity) $script:callOrder.Add("Remove-AutoSensitivityLabelRule:$Identity")
        }
        Mock -ModuleName SensitivityLabels Get-AutoSensitivityLabelPolicy {
            param($Identity) [pscustomobject]@{ Name = $Identity }
        }
        Mock -ModuleName SensitivityLabels Remove-AutoSensitivityLabelPolicy {
            param($Identity) $script:callOrder.Add("Remove-AutoSensitivityLabelPolicy:$Identity")
        }
        Mock -ModuleName SensitivityLabels Get-LabelPolicyRule {
            param($Identity) [pscustomobject]@{ Name = $Identity }
        }
        Mock -ModuleName SensitivityLabels Remove-LabelPolicyRule {
            param($Identity) $script:callOrder.Add("Remove-LabelPolicyRule:$Identity")
        }
        Mock -ModuleName SensitivityLabels Get-LabelPolicy {
            param($Identity) [pscustomobject]@{ Name = $Identity }
        }
        Mock -ModuleName SensitivityLabels Remove-LabelPolicy {
            param($Identity) $script:callOrder.Add("Remove-LabelPolicy:$Identity")
        }
        Mock -ModuleName SensitivityLabels Get-Label {
            param($Identity) [pscustomobject]@{ Name = $Identity }
        }
        Mock -ModuleName SensitivityLabels Remove-Label {
            param($Identity) $script:callOrder.Add("Remove-Label:$Identity")
        }
    }

    It 'Removes policies but not labels when -PoliciesOnly' {
        Remove-SensitivityLabels -Config (Get-SensTestConfig) -PoliciesOnly

        $script:callOrder | Should -Contain 'Remove-AutoSensitivityLabelPolicy:PVTest-Auto-SSN'
        $script:callOrder | Should -Contain 'Remove-LabelPolicy:PVTest-Sensitivity-Labels-Publish'
        ($script:callOrder | Where-Object { $_ -like 'Remove-Label:*' }).Count | Should -Be 0
    }

    It 'Removes labels but not policies when -LabelsOnly' {
        Remove-SensitivityLabels -Config (Get-SensTestConfig) -LabelsOnly

        ($script:callOrder | Where-Object { $_ -like 'Remove-AutoSensitivityLabel*' }).Count | Should -Be 0
        ($script:callOrder | Where-Object { $_ -like 'Remove-LabelPolicy*' }).Count | Should -Be 0
        ($script:callOrder | Where-Object { $_ -like 'Remove-Label:*' }).Count | Should -BeGreaterThan 0
    }

    It 'Default (no switch) removes all policies before any label' {
        Remove-SensitivityLabels -Config (Get-SensTestConfig)

        $lastPolicyIdx = -1
        $firstLabelIdx = -1
        for ($i = 0; $i -lt $script:callOrder.Count; $i++) {
            $entry = $script:callOrder[$i]
            if ($entry -like 'Remove-*Policy:*' -or $entry -like 'Remove-*PolicyRule:*' -or $entry -like 'Remove-AutoSensitivityLabel*') {
                $lastPolicyIdx = $i
            }
            if ($entry -like 'Remove-Label:*' -and $firstLabelIdx -lt 0) {
                $firstLabelIdx = $i
            }
        }

        $firstLabelIdx | Should -BeGreaterThan -1
        $lastPolicyIdx | Should -BeLessThan $firstLabelIdx
    }

    It '-PoliciesOnly then -LabelsOnly is idempotent against missing policies' {
        Remove-SensitivityLabels -Config (Get-SensTestConfig) -PoliciesOnly

        Mock -ModuleName SensitivityLabels Get-AutoSensitivityLabelPolicy { throw 'not found' }
        Mock -ModuleName SensitivityLabels Get-LabelPolicy { throw 'not found' }

        { Remove-SensitivityLabels -Config (Get-SensTestConfig) -LabelsOnly -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Rejects both -PoliciesOnly and -LabelsOnly together' {
        {
            Remove-SensitivityLabels -Config (Get-SensTestConfig) -PoliciesOnly -LabelsOnly -ErrorAction Stop
        } | Should -Throw
    }
}

Describe 'Remove-Retention switch behavior' {
    BeforeEach {
        $script:callOrder = [System.Collections.Generic.List[string]]::new()

        Mock -ModuleName Retention Get-RetentionComplianceRule {
            param($Identity)
            [pscustomobject]@{ Name = $Identity }
        }
        Mock -ModuleName Retention Remove-RetentionComplianceRule {
            param($Identity) $script:callOrder.Add("Remove-RetentionComplianceRule:$Identity")
        }
        Mock -ModuleName Retention Get-RetentionCompliancePolicy {
            param($Identity) [pscustomobject]@{ Name = $Identity }
        }
        Mock -ModuleName Retention Remove-RetentionCompliancePolicy {
            param($Identity) $script:callOrder.Add("Remove-RetentionCompliancePolicy:$Identity")
        }
        Mock -ModuleName Retention Get-ComplianceTag {
            param($Identity) [pscustomobject]@{ Name = $Identity }
        }
        Mock -ModuleName Retention Remove-ComplianceTag {
            param($Identity) $script:callOrder.Add("Remove-ComplianceTag:$Identity")
        }
    }

    It 'Removes only label-publish rules and policies when -PoliciesOnly' {
        Remove-Retention -Config (Get-RetTestConfig) -PoliciesOnly

        $script:callOrder | Should -Contain 'Remove-RetentionComplianceRule:PVTest-Fin-Records-publish-rule'
        $script:callOrder | Should -Contain 'Remove-RetentionCompliancePolicy:PVTest-Fin-Records-publish'
        ($script:callOrder | Where-Object { $_ -like 'Remove-ComplianceTag:*' }).Count | Should -Be 0
        $script:callOrder | Should -Not -Contain 'Remove-RetentionCompliancePolicy:PVTest-Baseline-Retention'
    }

    It 'Removes compliance tags and standalone retention policies when -LabelsOnly' {
        Remove-Retention -Config (Get-RetTestConfig) -LabelsOnly

        $script:callOrder | Should -Contain 'Remove-ComplianceTag:PVTest-Fin-Records'
        $script:callOrder | Should -Contain 'Remove-RetentionCompliancePolicy:PVTest-Baseline-Retention'
        $script:callOrder | Should -Not -Contain 'Remove-RetentionCompliancePolicy:PVTest-Fin-Records-publish'
    }

    It '-PoliciesOnly then -LabelsOnly is idempotent against missing publish policies' {
        Remove-Retention -Config (Get-RetTestConfig) -PoliciesOnly

        Mock -ModuleName Retention Get-RetentionCompliancePolicy {
            param($Identity)
            if ($Identity -like '*-publish') { throw 'not found' }
            [pscustomobject]@{ Name = $Identity }
        }

        { Remove-Retention -Config (Get-RetTestConfig) -LabelsOnly -ErrorAction Stop } | Should -Not -Throw
    }

    It 'Rejects both -PoliciesOnly and -LabelsOnly together' {
        {
            Remove-Retention -Config (Get-RetTestConfig) -PoliciesOnly -LabelsOnly -ErrorAction Stop
        } | Should -Throw
    }
}
