function Get-LabServer {
    <#
    .SYNOPSIS
        Returns the hardware and OS facts of the lab servers.
    .DESCRIPTION
        Without -ComputerName, the servers listed in the module config are queried.
    .EXAMPLE
        Get-LabServer -ComputerName LAB-FS01 | Format-List
    #>
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [Alias('Name', 'Server')]
        [string[]]$ComputerName,

        [pscredential]$Credential
    )

    begin {
        if (-not $PSBoundParameters.ContainsKey('ComputerName')) {
            $ComputerName = (Read-LabConfig).Servers
        }
    }

    process {
        foreach ($computer in $ComputerName) {
            Write-LabLog "Querying $computer"
            $session = $null
            try {
                $session = New-LabCimSession -ComputerName $computer -Credential $Credential

                $os  = Get-CimInstance -CimSession $session -ClassName Win32_OperatingSystem
                $cs  = Get-CimInstance -CimSession $session -ClassName Win32_ComputerSystem
                $cpu = Get-CimInstance -CimSession $session -ClassName Win32_Processor | Select-Object -First 1
                $bios = Get-CimInstance -CimSession $session -ClassName Win32_BIOS

                [PSCustomObject]@{
                    PSTypeName   = 'LabInventory.Server'
                    ComputerName = $computer
                    OS           = $os.Caption
                    Build        = $os.BuildNumber
                    Manufacturer = $cs.Manufacturer
                    Model        = $cs.Model
                    CPU          = $cpu.Name
                    Cores        = $cpu.NumberOfCores
                    Memory       = ConvertTo-LabSize -Bytes $cs.TotalPhysicalMemory
                    Serial       = $bios.SerialNumber
                    LastBoot     = $os.LastBootUpTime
                    UptimeDays   = [int]((Get-Date) - $os.LastBootUpTime).TotalDays
                }
            }
            catch {
                Write-LabLog "Could not query ${computer}: $_" -Level ERROR
                Write-Error -Message "Could not query ${computer}: $_" -TargetObject $computer
            }
            finally {
                if ($session) { Remove-CimSession -CimSession $session }
            }
        }
    }
}
