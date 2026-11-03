@{
    RootModule        = 'LabInventory.psm1'
    ModuleVersion     = '1.3.0'
    GUID              = '6f1d3c2a-7b84-4e0f-9a51-2c3d8e7f4b19'
    Author            = 'Lab Ops'
    CompanyName       = 'Home Lab'
    Copyright         = '(c) Lab Ops. All rights reserved.'
    Description       = 'Inventory of the lab servers: hardware, disks, reachability, exported as CSV or HTML.'
    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Get-LabServer',
        'Get-LabDiskReport',
        'Test-LabServer',
        'Export-LabInventory',
        'Get-LabInventoryConfig'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('Inventory', 'Lab', 'CIM')
            ProjectUri = ''
        }
    }
}
