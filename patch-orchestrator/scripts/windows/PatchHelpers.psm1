function Write-PatchLog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [string]$Path
    )
    $line = '{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message
    Write-Host $line
    if ($Path) { Add-Content -Path $Path -Value $line }
}

function Get-PendingRebootState {
    <#
    .SYNOPSIS
        True when the computer has a reboot pending (CBS, Windows Update or a pending rename).
    #>
    param([Parameter(Mandatory)][System.Management.Automation.Runspaces.PSSession]$Session)

    Invoke-Command -Session $Session -ScriptBlock {
        $keys = @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
        )
        foreach ($k in $keys) { if (Test-Path $k) { return $true } }
        $rename = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ActiveComputerName'
        $pending = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\ComputerName\ComputerName'
        return $rename.ComputerName -ne $pending.ComputerName
    }
}

Export-ModuleMember -Function Write-PatchLog, Get-PendingRebootState
