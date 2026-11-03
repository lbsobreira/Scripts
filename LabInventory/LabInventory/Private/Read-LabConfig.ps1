function Read-LabConfig {
    <#
    .SYNOPSIS
        Reads LabInventory.config.json (or the file named by $env:LABINVENTORY_CONFIG) once per session.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if ($Script:LabConfig -and -not $Force) {
        return $Script:LabConfig
    }

    $path = if ($env:LABINVENTORY_CONFIG) {
        $env:LABINVENTORY_CONFIG
    }
    else {
        Join-Path (Split-Path $PSScriptRoot -Parent) 'LabInventory.config.json'
    }

    if (-not (Test-Path -Path $path)) {
        throw "LabInventory config not found: $path"
    }

    Write-LabLog "Reading config from $path"
    $config = Get-Content -Path $path -Raw | ConvertFrom-Json

    # Defaults for settings older config files do not have.
    if (-not $config.CimTimeoutSeconds) {
        $config | Add-Member -NotePropertyName CimTimeoutSeconds -NotePropertyValue 30 -Force
    }
    if (-not $config.DiskWarningPercent) {
        $config | Add-Member -NotePropertyName DiskWarningPercent -NotePropertyValue 10 -Force
    }

    $Script:LabConfig = $config
    $config
}
