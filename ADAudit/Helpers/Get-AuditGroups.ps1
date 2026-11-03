function Get-AuditGroups {
    <#
    .SYNOPSIS
        Returns the groups under a search base with their scope, category and member count.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SearchBase,

        [string]$LogFile
    )

    Write-AuditLog -Message "Collecting groups under $SearchBase" -LogFile $LogFile

    $groups = Get-ADGroup -Filter * -SearchBase $SearchBase -Properties Description, ManagedBy, whenCreated

    foreach ($group in $groups) {
        $members = @(Get-ADGroupMember -Identity $group -ErrorAction SilentlyContinue)

        [PSCustomObject]@{
            Name        = $group.Name
            Scope       = $group.GroupScope
            Category    = $group.GroupCategory
            MemberCount = $members.Count
            ManagedBy   = $group.ManagedBy
            Description = $group.Description
            Created     = $group.whenCreated
        }
    }

    Write-AuditLog -Message "Found $(@($groups).Count) groups" -LogFile $LogFile
}
