# LabInventory root module: loads the private helpers and the public functions,
# then exports only the public ones.

$public  = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Public')  -Filter '*.ps1' -ErrorAction SilentlyContinue)
$private = @(Get-ChildItem -Path (Join-Path $PSScriptRoot 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        Write-Error "Failed to import function $($file.FullName): $_"
    }
}

# Module-wide state: the config is read once per session.
$Script:LabConfig = $null
$Script:LogPath = Join-Path $env:TEMP 'LabInventory.log'

Export-ModuleMember -Function $public.BaseName
