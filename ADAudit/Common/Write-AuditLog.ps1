function Write-AuditLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info',

        [string]$LogFile
    )

    $line = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level.ToUpper(), $Message

    switch ($Level) {
        'Warning' { Write-Warning $Message }
        'Error'   { Write-Error $Message -ErrorAction Continue }
        default   { Write-Verbose $Message }
    }

    if ($LogFile) {
        Add-Content -Path $LogFile -Value $line
    }
}
