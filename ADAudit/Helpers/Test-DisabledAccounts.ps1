function Test-DisabledAccounts {
    <#
    .SYNOPSIS
        Flags accounts that are disabled, or enabled but not used for StaleDays days.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object[]]$Users,

        [int]$StaleDays = 90,

        [string]$LogFile
    )

    $cutoff = (Get-Date).AddDays(-$StaleDays)
    Write-AuditLog -Message "Checking $($Users.Count) accounts (stale before $($cutoff.ToShortDateString()))" -LogFile $LogFile

    $findings = foreach ($user in $Users) {
        if (-not $user.Enabled) {
            [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName    = $user.DisplayName
                Reason         = 'Disabled'
                LastLogonDate  = $user.LastLogonDate
            }
        }
        elseif ($null -eq $user.LastLogonDate -or $user.LastLogonDate -lt $cutoff) {
            [PSCustomObject]@{
                SamAccountName = $user.SamAccountName
                DisplayName    = $user.DisplayName
                Reason         = 'Stale'
                LastLogonDate  = $user.LastLogonDate
            }
        }
    }

    # Accounts AD itself considers inactive, in case LastLogonDate has not replicated yet.
    $inactive = Search-ADAccount -AccountInactive -TimeSpan (New-TimeSpan -Days $StaleDays) -UsersOnly
    foreach ($account in $inactive) {
        if ($findings.SamAccountName -notcontains $account.SamAccountName) {
            $findings += [PSCustomObject]@{
                SamAccountName = $account.SamAccountName
                DisplayName    = $account.Name
                Reason         = 'Stale'
                LastLogonDate  = $account.LastLogonDate
            }
        }
    }

    Write-AuditLog -Message "$(@($findings).Count) accounts flagged" -LogFile $LogFile
    $findings
}
