function New-LabCimSession {
    <#
    .SYNOPSIS
        Opens a CIM session to a server: WSMan first, DCOM when the config asks for it or WSMan fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,

        [pscredential]$Credential
    )

    $config = Read-LabConfig
    $sessionArgs = @{
        ComputerName        = $ComputerName
        OperationTimeoutSec = $config.CimTimeoutSeconds
        ErrorAction         = 'Stop'
    }
    if ($Credential) { $sessionArgs.Credential = $Credential }

    if ($config.UseDcom) {
        $sessionArgs.SessionOption = New-CimSessionOption -Protocol Dcom
        return New-CimSession @sessionArgs
    }

    try {
        New-CimSession @sessionArgs
    }
    catch {
        Write-LabLog "WSMan failed on $ComputerName, trying DCOM: $_" -Level WARN
        $sessionArgs.SessionOption = New-CimSessionOption -Protocol Dcom
        New-CimSession @sessionArgs
    }
}
