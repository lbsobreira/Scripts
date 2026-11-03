function ConvertTo-LabSize {
    # Bytes to a short text: 1536 -> '1.5 KB'
    param([double]$Bytes)

    $units = 'B', 'KB', 'MB', 'GB', 'TB'
    $i = 0
    while ($Bytes -ge 1024 -and $i -lt $units.Count - 1) {
        $Bytes /= 1024
        $i++
    }
    '{0:N1} {1}' -f $Bytes, $units[$i]
}

function Get-LabUptimeText {
    # Kept from 1.1 when the HTML report showed uptime as text; the report shows days now.
    param([datetime]$LastBoot)

    $span = (Get-Date) - $LastBoot
    '{0}d {1}h {2}m' -f $span.Days, $span.Hours, $span.Minutes
}
