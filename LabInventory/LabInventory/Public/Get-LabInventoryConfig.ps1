function Get-LabInventoryConfig {
    <#
    .SYNOPSIS
        Shows the settings the module is using, and where they came from.
    .EXAMPLE
        Get-LabInventoryConfig -Reload
    #>
    [CmdletBinding()]
    param(
        [switch]$Reload
    )

    Read-LabConfig -Force:$Reload
}
