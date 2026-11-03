function Get-LabDiskReport {
    <#
    .SYNOPSIS
        Free space of every fixed disk on the lab servers, with a status per disk.
    .EXAMPLE
        Get-LabDiskReport | Where-Object Status -ne 'OK'
    #>
    [CmdletBinding()]
    param(
        [string[]]$ComputerName,

        [pscredential]$Credential
    )

    $config = Read-LabConfig
    if (-not $ComputerName) { $ComputerName = $config.Servers }

    $warning  = $config.DiskWarningPercent
    $critical = if ($config.DiskCriticalPercent) { $config.DiskCriticalPercent } else { 5 }

    foreach ($computer in $ComputerName) {
        $session = $null
        try {
            $session = New-LabCimSession -ComputerName $computer -Credential $Credential
            Get-CimInstance -CimSession $session -ClassName Win32_LogicalDisk -Filter 'DriveType = 3' |
                ForEach-Object {
                    $freePct = if ($_.Size) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 1) } else { 0 }
                    $status = switch ($freePct) {
                        { $_ -le $critical } { 'Critical'; break }
                        { $_ -le $warning }  { 'Warning'; break }
                        default              { 'OK' }
                    }
                    [PSCustomObject]@{
                        ComputerName = $computer
                        Drive        = $_.DeviceID
                        Label        = $_.VolumeName
                        Size         = ConvertTo-LabSize -Bytes $_.Size
                        Free         = ConvertTo-LabSize -Bytes $_.FreeSpace
                        FreePercent  = $freePct
                        Status       = $status
                    }
                }
        }
        catch {
            Write-LabLog "Disk query failed on ${computer}: $_" -Level ERROR
        }
        finally {
            if ($session) { Remove-CimSession -CimSession $session }
        }
    }
}
