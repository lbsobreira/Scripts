function Get-AuditUsers {
    <#
    .SYNOPSIS
        Returns the user accounts under a search base with the properties the audit needs.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SearchBase,

        [string]$LogFile
    )

    Write-AuditLog -Message "Collecting users under $SearchBase" -LogFile $LogFile

    $properties = @(
        'DisplayName', 'Enabled', 'LastLogonDate', 'PasswordLastSet',
        'PasswordNeverExpires', 'whenCreated', 'MemberOf'
    )

    $users = Get-ADUser -Filter * -SearchBase $SearchBase -Properties $properties |
        Select-Object SamAccountName, DisplayName, Enabled, LastLogonDate, PasswordLastSet,
            PasswordNeverExpires, whenCreated,
            @{ Name = 'GroupCount'; Expression = { @($_.MemberOf).Count } }

    Write-AuditLog -Message "Found $(@($users).Count) users" -LogFile $LogFile
    $users
}
