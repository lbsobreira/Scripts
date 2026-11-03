#Requires -Version 5.1
<#
.SYNOPSIS
    Weekly lab report: inventory files plus a short summary of disks that need attention.
.EXAMPLE
    .\Get-LabReport.ps1 -OutputFolder D:\Reports\Lab -Verbose
#>
[CmdletBinding()]
param(
    [string]$OutputFolder = (Join-Path $PSScriptRoot 'Reports'),

    [string]$ConfigPath
)

$ErrorActionPreference = 'Stop'

if ($ConfigPath) {
    # The module reads this variable before its own config file.
    $env:LABINVENTORY_CONFIG = $ConfigPath
}

Import-Module "$PSScriptRoot\LabInventory\LabInventory.psd1" -Force

$config = Get-LabInventoryConfig
Write-Verbose "Servers in scope: $($config.Servers -join ', ')"

$files = Export-LabInventory -Path $OutputFolder -Format Both

$attention = Get-LabDiskReport | Where-Object Status -ne 'OK' | Sort-Object FreePercent
if ($attention) {
    $attention | Format-Table ComputerName, Drive, Free, FreePercent, Status -AutoSize | Out-String | Write-Host
    $attention | Export-Csv -Path (Join-Path $OutputFolder 'DisksNeedingAttention.csv') -NoTypeInformation
}
else {
    Write-Host 'All disks are above the warning level.' -ForegroundColor Green
}

$down = Test-LabServer | Where-Object { -not $_.Ping }
foreach ($server in $down) {
    Write-Warning "$($server.ComputerName) does not answer ping"
}

Write-Host "Report files:"
$files | ForEach-Object { Write-Host "  $_" }
