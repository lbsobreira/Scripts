function Export-AuditReport {
    [CmdletBinding()]
    param(
        [object[]]$Groups,
        [object[]]$Users,
        [object[]]$Findings,
        [Parameter(Mandatory)]
        [object]$Summary,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

    $Groups   | Export-Csv -Path (Join-Path $OutputPath "Groups-$stamp.csv") -NoTypeInformation -Encoding UTF8
    $Users    | Export-Csv -Path (Join-Path $OutputPath "Users-$stamp.csv") -NoTypeInformation -Encoding UTF8
    $Findings | Export-Csv -Path (Join-Path $OutputPath "Findings-$stamp.csv") -NoTypeInformation -Encoding UTF8

    $style = @'
<style>
body { font-family: Segoe UI, sans-serif; font-size: 13px; }
table { border-collapse: collapse; margin-bottom: 24px; }
th, td { border: 1px solid #ccc; padding: 4px 8px; }
th { background: #eee; }
</style>
'@

    $body = @(
        $Summary | ConvertTo-Html -As List -Fragment -PreContent '<h2>Summary</h2>'
        $Findings | Sort-Object Reason, SamAccountName |
            ConvertTo-Html -Fragment -PreContent '<h2>Disabled and stale accounts</h2>'
        $Groups | Where-Object { $_.MemberCount -eq 0 } |
            ConvertTo-Html -Property Name, Scope, Category, ManagedBy -Fragment -PreContent '<h2>Empty groups</h2>'
    )

    $htmlPath = Join-Path $OutputPath "ADAudit-$stamp.html"
    ConvertTo-Html -Head $style -Body $body -Title 'AD audit' | Set-Content -Path $htmlPath -Encoding UTF8

    Write-AuditLog -Message "Report written to $htmlPath"
    $htmlPath
}
