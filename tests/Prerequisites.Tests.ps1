#Requires -Version 7.0
#Requires -Modules Pester

BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'modules' 'Prerequisites.psm1'
    Import-Module $modulePath -Force
}

Describe 'Get-ProfileConfigMapping' {
    It 'Returns a hashtable with all canonical profiles and deprecated aliases' {
        $map = Get-ProfileConfigMapping
        $map | Should -BeOfType [hashtable]
        $map.Keys.Count | Should -Be 8
    }

    It 'Canonical profiles resolve correctly' {
        $map = Get-ProfileConfigMapping
        $map['basic']            | Should -Be 'basic-demo.json'
        $map['ai']               | Should -Be 'ai-demo.json'
        $map['purview-sentinel'] | Should -Be 'purview-sentinel-demo.json'
    }

    It 'Deprecated aliases resolve to canonical config files' {
        $map = Get-ProfileConfigMapping
        $map['basic-lab']        | Should -Be 'basic-demo.json'
        $map['shadow-ai']        | Should -Be 'ai-demo.json'
        $map['copilot-dlp']      | Should -Be 'ai-demo.json'
        $map['copilot-protection'] | Should -Be 'ai-demo.json'
        $map['ai-security']      | Should -Be 'ai-demo.json'
    }
}

Describe 'Resolve-LabProfile' {
    It 'Returns canonical name unchanged' {
        Resolve-LabProfile -LabProfile 'basic'            | Should -Be 'basic'
        Resolve-LabProfile -LabProfile 'ai'               | Should -Be 'ai'
        Resolve-LabProfile -LabProfile 'purview-sentinel' | Should -Be 'purview-sentinel'
    }

    It 'Resolves basic-lab to basic with a warning' {
        $result = Resolve-LabProfile -LabProfile 'basic-lab' -WarningVariable w 3>$null
        $result | Should -Be 'basic'
        $w | Should -Not -BeNullOrEmpty
    }

    It 'Resolves shadow-ai to ai with a warning' {
        $result = Resolve-LabProfile -LabProfile 'shadow-ai' -WarningVariable w 3>$null
        $result | Should -Be 'ai'
        $w | Should -Not -BeNullOrEmpty
    }

    It 'Resolves copilot-dlp to ai with a warning' {
        $result = Resolve-LabProfile -LabProfile 'copilot-dlp' -WarningVariable w 3>$null
        $result | Should -Be 'ai'
        $w | Should -Not -BeNullOrEmpty
    }

    It 'Resolves copilot-protection to ai with a warning' {
        $result = Resolve-LabProfile -LabProfile 'copilot-protection' -WarningVariable w 3>$null
        $result | Should -Be 'ai'
        $w | Should -Not -BeNullOrEmpty
    }

    It 'Resolves ai-security to ai with a warning' {
        $result = Resolve-LabProfile -LabProfile 'ai-security' -WarningVariable w 3>$null
        $result | Should -Be 'ai'
        $w | Should -Not -BeNullOrEmpty
    }
}

Describe 'Import-LabConfig' {
    It 'Loads a valid config file' {
        $configPath = Join-Path $PSScriptRoot '..' 'configs' 'commercial' 'basic-demo.json'
        $config = Import-LabConfig -ConfigPath $configPath
        $config | Should -Not -BeNullOrEmpty
        $config.labName | Should -Not -BeNullOrEmpty
        $config.prefix | Should -Not -BeNullOrEmpty
        $config.domain | Should -Not -BeNullOrEmpty
    }

    It 'Throws on missing required field' {
        $tempFile = Join-Path $TestDrive 'bad-config.json'
        @{ prefix = 'Test'; domain = 'test.com' } | ConvertTo-Json | Set-Content $tempFile
        { Import-LabConfig -ConfigPath $tempFile } | Should -Throw '*labName*'
    }

    It 'Throws on empty required field' {
        $tempFile = Join-Path $TestDrive 'empty-field.json'
        @{ labName = ''; prefix = 'Test'; domain = 'test.com' } | ConvertTo-Json | Set-Content $tempFile
        { Import-LabConfig -ConfigPath $tempFile } | Should -Throw '*must not be empty*'
    }
}

Describe 'Resolve-LabCloud' {
    It 'Prefers explicit -Cloud parameter' {
        $config = [PSCustomObject]@{ cloud = 'gcc' }
        Resolve-LabCloud -Cloud 'commercial' -Config $config | Should -Be 'commercial'
    }

    It 'Falls back to config cloud field' {
        $config = [PSCustomObject]@{ cloud = 'gcc' }
        Resolve-LabCloud -Cloud '' -Config $config | Should -Be 'gcc'
    }

    It 'Defaults to commercial' {
        $config = [PSCustomObject]@{}
        Resolve-LabCloud -Cloud '' -Config $config | Should -Be 'commercial'
    }

    It 'Throws on unsupported cloud' {
        $config = [PSCustomObject]@{}
        { Resolve-LabCloud -Cloud 'azure-gov' -Config $config } | Should -Throw '*Unsupported cloud*'
    }
}

Describe 'Invoke-LabRetry' {
    It 'Returns result on first success' {
        $result = Invoke-LabRetry -MaxAttempts 3 -DelaySeconds 0 -OperationName 'test' -ScriptBlock { 'ok' }
        $result | Should -Be 'ok'
    }

    It 'Retries and succeeds on later attempt' {
        $script:counter = 0
        $result = Invoke-LabRetry -MaxAttempts 3 -DelaySeconds 0 -OperationName 'test' -ScriptBlock {
            $script:counter++
            if ($script:counter -lt 3) { throw 'not yet' }
            return 'done'
        }
        $result | Should -Be 'done'
        $script:counter | Should -Be 3
    }

    It 'Throws after max attempts exhausted' {
        { Invoke-LabRetry -MaxAttempts 2 -DelaySeconds 0 -OperationName 'fail-test' -ScriptBlock { throw 'always fails' } } |
            Should -Throw '*fail-test failed after 2 attempts*'
    }
}

Describe 'Get-LabStringArray' {
    It 'Returns empty array for null' {
        $result = Get-LabStringArray -Value $null
        $result | Should -HaveCount 0
    }

    It 'Returns trimmed, unique strings' {
        $result = Get-LabStringArray -Value @(' a ', 'b', ' a ')
        $result | Should -Contain 'a'
        $result | Should -Contain 'b'
        $result | Should -HaveCount 2
    }

    It 'Handles single string value' {
        $result = Get-LabStringArray -Value 'hello'
        $result | Should -HaveCount 1
        $result | Should -Contain 'hello'
    }
}

Describe 'Export-LabManifest and Import-LabManifest' {
    It 'Round-trips manifest data' {
        $data = [PSCustomObject]@{
            testUsers = @('user1', 'user2')
            dlp       = @('policy1')
        }
        $manifestPath = Join-Path $TestDrive 'test-manifest.json'
        Export-LabManifest -ManifestData $data -OutputPath $manifestPath
        $loaded = Import-LabManifest -ManifestPath $manifestPath
        $loaded.generatedAt | Should -Not -BeNullOrEmpty
        $loaded.data.testUsers | Should -HaveCount 2
        $loaded.data.dlp | Should -HaveCount 1
    }
}

Describe 'Test-LabManifestValidity' {
    It 'Returns true for valid manifest' {
        $manifest = [PSCustomObject]@{
            generatedAt = '2026-04-11T10:00:00'
            data        = [PSCustomObject]@{ testUsers = @() }
        }
        Test-LabManifestValidity -Manifest $manifest | Should -Be $true
    }

    It 'Warns on missing generatedAt' {
        $manifest = [PSCustomObject]@{
            data = [PSCustomObject]@{}
        }
        Test-LabManifestValidity -Manifest $manifest -WarningVariable w 3>$null | Should -Be $false
    }

    It 'Warns on missing data section' {
        $manifest = [PSCustomObject]@{
            generatedAt = '2026-04-11T10:00:00'
        }
        Test-LabManifestValidity -Manifest $manifest -WarningVariable w 3>$null | Should -Be $false
    }
}
