#Requires -Version 5.1
#Requires -Modules ActiveDirectory
<#
.SYNOPSIS
    Audits Active Directory groups and users and reports disabled and stale accounts.

.DESCRIPTION
    Collects the groups and users under a search base, checks which accounts are disabled
    or have not logged on for a while, and writes a CSV and an HTML report.

.EXAMPLE
    .\Invoke-ADAudit.ps1 -SearchBase "OU=Staff,DC=example,DC=org" -StaleDays 60
#>
[CmdletBinding()]
param(
    [string]$SearchBase = (Get-ADDomain).DistinguishedName,

    [ValidateRange(1, 3650)]
    [int]$StaleDays = 90,

    [string]$OutputPath = (Join-Path $PSScriptRoot 'Reports')
)

$ErrorActionPreference = 'Stop'

# Load every helper and the shared functions.
foreach ($folder in 'Common', 'Helpers') {
    Get-ChildItem -Path (Join-Path $PSScriptRoot $folder) -Filter '*.ps1' | ForEach-Object {
        . $_.FullName
    }
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath | Out-Null
}

$logFile = Join-Path $OutputPath ("ADAudit-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))
Write-AuditLog -Message "Audit started on $SearchBase" -LogFile $logFile

try {
    $groups = Get-AuditGroups -SearchBase $SearchBase -LogFile $logFile
    $users = Get-AuditUsers -SearchBase $SearchBase -LogFile $logFile
    $disabled = Test-DisabledAccounts -Users $users -StaleDays $StaleDays -LogFile $logFile

    $summary = [PSCustomObject]@{
        SearchBase       = $SearchBase
        Groups           = $groups.Count
        EmptyGroups      = ($groups | Where-Object { $_.MemberCount -eq 0 }).Count
        Users            = $users.Count
        DisabledAccounts = ($disabled | Where-Object Reason -eq 'Disabled').Count
        StaleAccounts    = ($disabled | Where-Object Reason -eq 'Stale').Count
    }

    Export-AuditReport -Groups $groups -Users $users -Findings $disabled -Summary $summary -OutputPath $OutputPath
    Write-AuditLog -Message "Audit finished: $($summary.Users) users, $($summary.Groups) groups" -LogFile $logFile
    $summary
}
catch {
    Write-AuditLog -Message "Audit failed: $_" -Level Error -LogFile $logFile
    throw
}
