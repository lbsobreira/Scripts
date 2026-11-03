#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Weekly maintenance of the lab servers: old logs and temp files, service restarts,
    pending-reboot check, and a mail summary.

.DESCRIPTION
    Runs from the scheduled task registered by Register-MaintenanceTask.ps1.
    Settings come from config\maintenance.psd1; servers listed in config\exclude-servers.txt are skipped.

.PARAMETER WhatIf
    Lists what would be done and changes nothing on the servers.

.EXAMPLE
    .\Invoke-ServerMaintenance.ps1 -Servers LAB-WEB01 -NoMail
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string[]]$Servers,

    [string]$ConfigFile = "$PSScriptRoot\config\maintenance.psd1",

    [switch]$NoMail,

    [switch]$SkipRestart
)

$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\Logging.ps1"
. "$PSScriptRoot\lib\Remote.ps1"

$config = Import-PowerShellDataFile -Path $ConfigFile
$logFolder = Get-ConfigValue -Config $config -Key 'LogFolder' -Default "$PSScriptRoot\Logs"
Initialize-MaintLog -Folder $logFolder | Out-Null

$transcript = Join-Path $logFolder ('transcript-{0:yyyyMMdd-HHmm}.txt' -f (Get-Date))
Start-Transcript -Path $transcript | Out-Null

function Get-TargetServers {
    param([string[]]$Requested, [hashtable]$Config)

    $list = if ($Requested) { $Requested } else { $Config.Servers }
    $excludeFile = Join-Path (Split-Path $ConfigFile) 'exclude-servers.txt'
    if (Test-Path $excludeFile) {
        $exclude = Get-Content -Path $excludeFile | Where-Object { $_ -and $_ -notmatch '^\s*#' } | ForEach-Object { $_.Trim() }
        $list = $list | Where-Object { $exclude -notcontains $_ }
    }
    $list
}

function Send-MaintenanceSummary {
    param([object[]]$Results, [hashtable]$Mail)

    $failed = @($Results | Where-Object { -not $_.Success })
    $subject = 'Server maintenance: {0} servers, {1} failed' -f $Results.Count, $failed.Count
    $body = $Results |
        Select-Object Server, Success, LogFiles, LogMB, TempFiles, TempMB, RebootPending, Error |
        ConvertTo-Html -Title $subject | Out-String

    $mailArgs = @{
        SmtpServer = $Mail.SmtpServer
        Port       = $Mail.Port
        From       = $Mail.From
        To         = $Mail.To
        Subject    = $subject
        Body       = $body
        BodyAsHtml = $true
    }
    Send-MailMessage @mailArgs
    Write-MaintLog "Summary mailed to $($Mail.To -join ', ')"
}

function Invoke-OldCleanup {
    # Before 2.0 the cleanup ran over admin shares instead of WinRM. Kept until every server has WinRM.
    param([string]$Server, [int]$Days)
    Get-ChildItem "\\$Server\c$\Windows\Temp" -File |
        Where-Object LastWriteTime -lt (Get-Date).AddDays(-$Days) |
        Remove-Item -Force
}

$results = @()
try {
    $targets = Get-TargetServers -Requested $Servers -Config $config
    Write-MaintLog "Maintenance on $(@($targets).Count) servers: $($targets -join ', ')"

    $logDays  = Get-ConfigValue -Config $config -Key 'LogRetentionDays' -Default 30
    $tempDays = Get-ConfigValue -Config $config -Key 'TempRetentionDays' -Default 7
    $services = if ($SkipRestart) { @() } else { Get-ConfigValue -Config $config -Key 'RestartServices' -Default @() }

    # The remote side has none of lib\Remote.ps1: send the function bodies along.
    $ClearOldLogsDef  = ${function:Clear-OldLogs}.ToString()
    $ClearTempDef     = ${function:Clear-TempFolders}.ToString()
    $PendingRebootDef = ${function:Test-PendingReboot}.ToString()
    $RestartSafeDef   = ${function:Restart-ServiceSafe}.ToString()

    foreach ($server in $targets) {
        if (-not $PSCmdlet.ShouldProcess($server, 'Clean logs and temp, restart services')) { continue }
        Write-MaintLog "--- $server"
        try {
            $remote = Invoke-Command -ComputerName $server -ErrorAction Stop -ArgumentList $config.LogFolders, $logDays, $tempDays, $services -ScriptBlock {
                param($folders, $logDays, $tempDays, $services)

                # The functions come over as text and are defined again on the server.
                ${function:Clear-OldLogs}       = [scriptblock]::Create($using:ClearOldLogsDef)
                ${function:Clear-TempFolders}   = [scriptblock]::Create($using:ClearTempDef)
                ${function:Test-PendingReboot}  = [scriptblock]::Create($using:PendingRebootDef)
                ${function:Restart-ServiceSafe} = [scriptblock]::Create($using:RestartSafeDef)

                $logs = Clear-OldLogs -Folders $folders -Days $logDays
                $temp = Clear-TempFolders -Days $tempDays
                if ($services) { Restart-ServiceSafe -Name $services }

                [PSCustomObject]@{
                    LogFiles      = $logs.Files
                    LogMB         = $logs.MB
                    TempFiles     = $temp.Files
                    TempMB        = $temp.MB
                    RebootPending = Test-PendingReboot
                }
            }

            Write-MaintLog ("{0}: {1} log files ({2} MB), {3} temp files ({4} MB), reboot pending: {5}" -f
                $server, $remote.LogFiles, $remote.LogMB, $remote.TempFiles, $remote.TempMB, $remote.RebootPending)

            $results += [PSCustomObject]@{
                Server        = $server
                Success       = $true
                LogFiles      = $remote.LogFiles
                LogMB         = $remote.LogMB
                TempFiles     = $remote.TempFiles
                TempMB        = $remote.TempMB
                RebootPending = $remote.RebootPending
                Error         = $null
            }
        }
        catch {
            Write-MaintLog "${server}: $($_.Exception.Message)" -Level Error
            $results += [PSCustomObject]@{ Server = $server; Success = $false; Error = $_.Exception.Message }
        }
    }

    if (-not $NoMail -and $results) {
        Send-MaintenanceSummary -Results $results -Mail (Get-ConfigValue -Config $config -Key 'Mail' -Default $null)
    }
}
catch {
    Write-MaintLog "Maintenance stopped: $_" -Level Error
    throw
}
finally {
    Stop-Transcript | Out-Null
}
