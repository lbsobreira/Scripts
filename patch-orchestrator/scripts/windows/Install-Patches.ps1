#Requires -Version 7.2
<#
.SYNOPSIS
    Installs the approved Windows updates on a remote computer.
.DESCRIPTION
    Uses the PSWindowsUpdate module on the target. Exit code 3010 when the computer
    needs a reboot afterwards, 0 when not, 1 on failure.
.EXAMPLE
    pwsh -File Install-Patches.ps1 -ComputerName file-01 -LogPath /var/log/patching/file-01.log
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ComputerName,
    [string]$LogPath,
    [string[]]$ExcludeKB = @()
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'PatchHelpers.psm1') -Force

$session = $null
try {
    $session = New-PSSession -ComputerName $ComputerName
    Write-PatchLog -Message "Connected to $ComputerName" -Path $LogPath

    $result = Invoke-Command -Session $session -ArgumentList (, $ExcludeKB) -ScriptBlock {
        param($exclude)
        Import-Module PSWindowsUpdate
        Install-WindowsUpdate -AcceptAll -IgnoreReboot -NotKBArticleID $exclude -Confirm:$false |
            Select-Object KB, Size, Title, Result
    }
    foreach ($u in $result) {
        Write-PatchLog -Message ("{0} {1} {2}" -f $u.KB, $u.Result, $u.Title) -Path $LogPath
    }

    if (Get-PendingRebootState -Session $session) {
        Write-PatchLog -Message "$ComputerName needs a reboot" -Path $LogPath
        exit 3010
    }
    Write-PatchLog -Message "$ComputerName patched, no reboot needed" -Path $LogPath
    exit 0
}
catch {
    Write-PatchLog -Message "FAILED on ${ComputerName}: $_" -Path $LogPath
    exit 1
}
finally {
    if ($session) { Remove-PSSession $session }
}
