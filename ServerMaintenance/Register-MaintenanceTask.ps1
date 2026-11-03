#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registers the weekly scheduled task that runs Invoke-ServerMaintenance.ps1 as SYSTEM.
.EXAMPLE
    .\Register-MaintenanceTask.ps1 -Day Sunday -At 03:00
#>
[CmdletBinding()]
param(
    [ValidateSet('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')]
    [string]$Day = 'Sunday',

    [string]$At = '02:30',

    [string]$TaskName = 'Lab - Server maintenance'
)

. "$PSScriptRoot\lib\Logging.ps1"

$config = Import-PowerShellDataFile -Path "$PSScriptRoot\config\maintenance.psd1"
$logFolder = Get-ConfigValue -Config $config -Key 'LogFolder' -Default "$PSScriptRoot\Logs"
Initialize-MaintLog -Folder $logFolder -Name 'register' | Out-Null

$script = Join-Path $PSScriptRoot 'Invoke-ServerMaintenance.ps1'
if (-not (Test-Path $script)) {
    Write-MaintLog "Not found: $script" -Level Error
    exit 1
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$script`"" `
    -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $At
$principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 3) -StartWhenAvailable

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Write-MaintLog "Replacing existing task '$TaskName'" -Level Warn
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings `
    -Description 'Weekly cleanup of logs and temp files on the lab servers' | Out-Null

Write-MaintLog "Task '$TaskName' registered: $Day at $At"
