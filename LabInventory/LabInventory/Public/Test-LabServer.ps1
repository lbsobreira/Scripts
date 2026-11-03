function Test-LabServer {
    <#
    .SYNOPSIS
        Checks that each lab server answers ping, WinRM and RDP.
    #>
    [CmdletBinding()]
    param(
        [string[]]$ComputerName = (Read-LabConfig).Servers
    )

    foreach ($computer in $ComputerName) {
        $ping  = Test-Connection -ComputerName $computer -Count 1 -Quiet
        $winrm = [bool](Test-WSMan -ComputerName $computer -ErrorAction SilentlyContinue)
        $rdp   = (Test-NetConnection -ComputerName $computer -Port 3389 -WarningAction SilentlyContinue).TcpTestSucceeded

        if (-not ($ping -and $winrm)) {
            Write-LabLog "$computer is not fully reachable (ping=$ping winrm=$winrm rdp=$rdp)" -Level WARN
        }

        [PSCustomObject]@{
            ComputerName = $computer
            Ping         = $ping
            WinRM        = $winrm
            RDP          = $rdp
        }
    }
}
