function Export-LabInventory {
    <#
    .SYNOPSIS
        Collects servers, disks and reachability and writes them as CSV files and one HTML page.
    .EXAMPLE
        Export-LabInventory -Path D:\Reports -Format Html
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path,

        [ValidateSet('Csv', 'Html', 'Both')]
        [string]$Format = 'Both',

        [pscredential]$Credential
    )

    $config = Read-LabConfig
    if (-not $Path) { $Path = $config.ReportFolder }
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }

    $common = @{}
    if ($Credential) { $common.Credential = $Credential }

    $reach   = Test-LabServer
    $up      = $reach | Where-Object WinRM | Select-Object -ExpandProperty ComputerName
    $servers = Get-LabServer -ComputerName $up @common
    $disks   = Get-LabDiskReport -ComputerName $up @common

    $stamp = Get-Date -Format 'yyyyMMdd'
    $written = @()

    if ($Format -in 'Csv', 'Both') {
        foreach ($set in @{ Servers = $servers; Disks = $disks; Reachability = $reach }.GetEnumerator()) {
            $file = Join-Path $Path "$($set.Key)-$stamp.csv"
            if ($PSCmdlet.ShouldProcess($file, 'Write CSV')) {
                $set.Value | Export-Csv -Path $file -NoTypeInformation -Encoding UTF8
                $written += $file
            }
        }
    }

    if ($Format -in 'Html', 'Both') {
        $html = Join-Path $Path "LabInventory-$stamp.html"
        if ($PSCmdlet.ShouldProcess($html, 'Write HTML')) {
            $body = @(
                $servers | ConvertTo-Html -Fragment -PreContent '<h2>Servers</h2>'
                $disks | Sort-Object Status, ComputerName | ConvertTo-Html -Fragment -PreContent '<h2>Disks</h2>'
                $reach | ConvertTo-Html -Fragment -PreContent '<h2>Reachability</h2>'
            )
            ConvertTo-Html -Title 'Lab inventory' -Body $body | Out-File -FilePath $html -Encoding utf8
            $written += $html
        }
    }

    Write-LabLog "Inventory written: $($written -join ', ')"
    $written
}
