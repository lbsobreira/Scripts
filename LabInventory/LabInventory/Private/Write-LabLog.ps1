function Write-LabLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 's'), $Level, $Message
    Write-Verbose $line

    if ($Script:LogPath) {
        try {
            Add-Content -Path $Script:LogPath -Value $line -ErrorAction Stop
        }
        catch {
            # Logging must never stop the inventory.
            Write-Warning "Could not write to $($Script:LogPath): $_"
        }
    }
}
