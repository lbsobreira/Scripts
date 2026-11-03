# Functions that run ON the target servers. They are sent with Invoke-Command,
# so they must not use anything from Logging.ps1.

function Clear-OldLogs {
    param(
        [string[]]$Folders,
        [int]$Days
    )

    $cutoff = (Get-Date).AddDays(-$Days)
    $removed = 0
    $bytes = 0
    foreach ($folder in $Folders) {
        if (-not (Test-Path $folder)) { continue }
        Get-ChildItem -Path $folder -Recurse -File -Include '*.log', '*.txt', '*.cab' -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt $cutoff } |
            ForEach-Object {
                $bytes += $_.Length
                Remove-Item -Path $_.FullName -Force -ErrorAction SilentlyContinue
                $removed++
            }
    }
    [PSCustomObject]@{ Files = $removed; MB = [math]::Round($bytes / 1MB, 1) }
}

function Clear-TempFolders {
    param([int]$Days)

    $targets = @("$env:windir\Temp") + (Get-ChildItem 'C:\Users' -Directory | ForEach-Object { Join-Path $_.FullName 'AppData\Local\Temp' })
    Clear-OldLogs -Folders $targets -Days $Days
}

function Test-PendingReboot {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )
    foreach ($key in $keys) {
        if (Test-Path $key) { return $true }
    }
    $pfro = Get-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue
    [bool]$pfro
}

function Restart-ServiceSafe {
    param([string[]]$Name)

    foreach ($svc in Get-Service -Name $Name -ErrorAction SilentlyContinue) {
        if ($svc.Status -eq 'Running') {
            Restart-Service -InputObject $svc -Force -ErrorAction Continue
        }
    }
}
