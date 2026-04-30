#!/usr/bin/env pwsh
#Requires -Version 7.0
param([string]$TenantId = '119e9fe0-c9d3-4a9d-be8b-c82d03fd0cd4')

Connect-MgGraph -TenantId $TenantId `
    -Scopes 'Mail.Send','User.Read.All','Files.ReadWrite.All','Sites.ReadWrite.All','Organization.Read.All' `
    -NoWelcome -ErrorAction Stop

$ctx = Get-MgContext
if (-not $ctx) { throw 'Connect-MgGraph silent reuse failed.' }
Write-Host "Graph reattached: $($ctx.Account) on $($ctx.TenantId)" -ForegroundColor Green

& "$PSScriptRoot/Invoke-SmokeTest.ps1" -Cloud gcc -TenantId $TenantId -SkipAuth
