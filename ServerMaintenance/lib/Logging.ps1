# Shared logging for the maintenance scripts.

$Script:MaintLogFile = $null

function Initialize-MaintLog {
    param(
        [Parameter(Mandatory)]
        [string]$Folder,

        [string]$Name = 'maintenance'
    )

    if (-not (Test-Path $Folder)) {
        New-Item -Path $Folder -ItemType Directory -Force | Out-Null
    }
    $Script:MaintLogFile = Join-Path $Folder ('{0}-{1:yyyyMMdd-HHmm}.log' -f $Name, (Get-Date))
    Write-MaintLog "Log started: $Script:MaintLogFile"
    $Script:MaintLogFile
}

function Write-MaintLog {
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$Message,

        [ValidateSet('Info', 'Warn', 'Error')]
        [string]$Level = 'Info'
    )

    process {
        $line = '{0:yyyy-MM-dd HH:mm:ss} {1,-5} {2}' -f (Get-Date), $Level.ToUpper(), $Message
        switch ($Level) {
            'Error' { Write-Host $line -ForegroundColor Red }
            'Warn'  { Write-Host $line -ForegroundColor Yellow }
            default { Write-Host $line }
        }
        if ($Script:MaintLogFile) {
            $line | Out-File -FilePath $Script:MaintLogFile -Append -Encoding utf8
        }
    }
}

function Get-ConfigValue {
    # Reads a key from the maintenance config with a default; used by both entry scripts.
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$Key,

        $Default
    )

    if ($Config.ContainsKey($Key) -and $null -ne $Config[$Key]) {
        return $Config[$Key]
    }
    Write-MaintLog "Config has no '$Key', using default '$Default'" -Level Warn
    $Default
}

function Write-EventLogEntry {
    # Used when the scripts ran under the old SCOM rule; nothing writes to the Application log any more.
    param([string]$Message, [int]$EventId = 1000)

    if (-not [System.Diagnostics.EventLog]::SourceExists('ServerMaintenance')) {
        New-EventLog -LogName Application -Source 'ServerMaintenance'
    }
    Write-EventLog -LogName Application -Source 'ServerMaintenance' -EventId $EventId -Message $Message
}
