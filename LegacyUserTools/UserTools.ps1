#################################################
# UserTools.ps1
# Helpdesk menu for everyday AD user tasks.
# Run from the UserTools folder:  cd C:\Scripts\UserTools; .\UserTools.ps1
#
# 2017-05  first version (jm)
# 2018-11  reports menu, CSV import moved to CommonLib
# 2021-02  custom query option for the 2nd line team
#################################################

#Requires -Modules ActiveDirectory

. "$PSScriptRoot\Settings.ps1"
. .\CommonLib.ps1

$Script:Operator = $env:USERNAME
$Script:Changes = 0
$Global:LastUser = $null

function check_admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    if (-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Run this as administrator!" -ForegroundColor Yellow
    }
}

function Show-Menu {
    Clear-Host
    Write-Host "==================== USER TOOLS ===================="
    Write-Host " Operator: $Script:Operator    Domain: $Global:Domain"
    Write-Host " Last user: $Global:LastUser   Changes this session: $Script:Changes"
    Write-Host "===================================================="
    Write-Host " 1) Show user info"
    Write-Host " 2) Find user by name"
    Write-Host " 3) Unlock account"
    Write-Host " 4) Reset password"
    Write-Host " 5) Disable leaver"
    Write-Host " 6) Enable account"
    Write-Host " 7) Copy groups from another user"
    Write-Host " 8) Import new users from users.csv"
    Write-Host " 9) Reports"
    Write-Host " Q) Custom query"
    Write-Host " X) Exit"
}

function Show-UserInfo {
    param([string]$sam)
    $u = Get-UserInfo $sam
    if (-not $u) { return }
    $Global:LastUser = $u.SamAccountName
    $u | Format-List Name, SamAccountName, DisplayName, EmailAddress, Enabled, LockedOut, LastLogonDate, HomeDirectory
    Write-Host "Groups:"
    $u.MemberOf | ForEach-Object { "  " + (($_ -split ',')[0] -replace '^CN=') } | Sort-Object
    Get-PasswordExpiry $sam
}

function Get-PasswordExpiry($sam) {
    $u = Get-ADUser $sam -Properties "msDS-UserPasswordExpiryTimeComputed", PasswordNeverExpires
    if ($u.PasswordNeverExpires) {
        Write-Host "Password never expires" -ForegroundColor Yellow
    } else {
        $exp = [datetime]::FromFileTime($u."msDS-UserPasswordExpiryTimeComputed")
        Write-Host "Password expires: $exp"
    }
}

function Unlock-User($sam) {
    $u = Get-UserInfo $sam
    if (-not $u) { return }
    if ($u.LockedOut) {
        Unlock-ADAccount -Identity $sam
        Write-Log "unlocked $sam"
        $Script:Changes++
        Write-Host "$sam unlocked" -ForegroundColor Green
    } else {
        Write-Host "$sam is not locked"
    }
}

function Reset-UserPassword($sam) {
    if (-not (Get-UserInfo $sam)) { return }
    $pw = New-RandomPassword
    Set-ADAccountPassword -Identity $sam -Reset -NewPassword (ConvertTo-SecureString $pw -AsPlainText -Force)
    Set-ADUser -Identity $sam -ChangePasswordAtLogon $true
    Unlock-ADAccount -Identity $sam
    Write-Log "password reset $sam"
    $Script:Changes++
    Write-Host "New password for ${sam}: $pw" -ForegroundColor Cyan
}

function Disable-LeaverAccount($sam) {
    $u = Get-UserInfo $sam
    if (-not $u) { return }
    $confirm = Read-Host "Disable $($u.Name) and remove all groups? (y/n)"
    if ($confirm -ne 'y') { return }

    foreach ($g in $u.MemberOf) {
        Remove-ADGroupMember -Identity $g -Members $sam -Confirm:$false
    }
    Disable-ADAccount -Identity $sam
    Set-ADUser -Identity $sam -Description ("Disabled {0} by {1}" -f (Get-Date -Format yyyy-MM-dd), $Script:Operator)
    Move-ADObject -Identity $u.DistinguishedName -TargetPath $Global:DisabledOU
    Write-Log "disabled leaver $sam"
    $Script:Changes++
}

function Enable-User($sam) {
    Enable-ADAccount -Identity $sam
    Write-Log "enabled $sam"
    $Script:Changes++
}

function Copy-UserGroups($from, $to) {
    $src = Get-UserInfo $from
    $dst = Get-UserInfo $to
    if (-not $src -or -not $dst) { return }
    $src.MemberOf | Where-Object { $dst.MemberOf -notcontains $_ } | ForEach-Object {
        Add-ADGroupMember -Identity $_ -Members $to
        Write-Log "added $to to $_ (copied from $from)"
    }
    $Script:Changes++
}

function Get-LockedUsers {
    Search-ADAccount -LockedOut -UsersOnly | Select-Object SamAccountName, Name, LastLogonDate | Format-Table -AutoSize
}

function Get-InactiveUsers([int]$days = 90) {
    Search-ADAccount -AccountInactive -TimeSpan (New-TimeSpan -Days $days) -UsersOnly -SearchBase $Global:DefaultOU |
        Where-Object Enabled |
        Select-Object SamAccountName, Name, LastLogonDate |
        Sort-Object LastLogonDate
}

function Export-GroupMembers($group) {
    $file = ".\members_$($group -replace '\W', '_').csv"
    Get-ADGroupMember -Identity $group -Recursive |
        Get-ADUser -Properties DisplayName, Department |
        Select-Object SamAccountName, DisplayName, Department |
        Export-Csv $file -NoTypeInformation
    Write-Host "Written to $file"
}

function Run-CustomQuery {
    # 2nd line asked for this: type a filter like  Department -eq 'IT'
    $filter = Read-Host "AD filter"
    $props = Read-Host "Extra properties (comma separated, blank for none)"
    $cmd = "Get-ADUser -Filter `"$filter`" -SearchBase '$Global:DefaultOU'"
    if ($props) { $cmd += " -Properties $props" }
    Write-Log "custom query: $cmd"
    Invoke-Expression $cmd | Format-Table -AutoSize
}

function Show-ReportsMenu {
    $reports = @{
        '1' = @{ Name = 'Locked accounts';            Action = { Get-LockedUsers } }
        '2' = @{ Name = 'Inactive 90 days';           Action = { Get-InactiveUsers 90 | Format-Table -AutoSize } }
        '3' = @{ Name = 'Inactive 180 days (CSV)';    Action = { Get-InactiveUsers 180 | Export-Csv .\inactive180.csv -NoTypeInformation } }
        '4' = @{ Name = 'Group members to CSV';       Action = { Export-GroupMembers (Read-Host "Group") } }
    }
    $reports.Keys | Sort-Object | ForEach-Object { Write-Host " $_) $($reports[$_].Name)" }
    $pick = Read-Host "Report"
    if ($reports.ContainsKey($pick)) {
        $action = $reports[$pick].Action
        & $action
    }
}

function Remove-OldHomeFolders {
    # TODO: never finished - do not use, it does not check if the user still exists
    Get-ChildItem $Global:HomeShare -Directory |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddYears(-2) } |
        ForEach-Object { Write-Host "would remove $($_.FullName)" }
}

### MAIN ###
check_admin
Write-Log "UserTools started by $Script:Operator"

$running = $true
while ($running) {
    Show-Menu
    $choice = Read-Host "Choice"
    switch ($choice) {
        '1' { Show-UserInfo (Read-Host "Username") }
        '2' { Find-UserByName (Read-Host "Name contains") | Format-Table -AutoSize }
        '3' { Unlock-User (Read-Host "Username") }
        '4' { Reset-UserPassword (Read-Host "Username") }
        '5' { Disable-LeaverAccount (Read-Host "Username") }
        '6' { Enable-User (Read-Host "Username") }
        '7' { Copy-UserGroups (Read-Host "Copy from") (Read-Host "Copy to") }
        '8' { Import-NewUsers }
        '9' { Show-ReportsMenu }
        'q' { Run-CustomQuery }
        'x' { $running = $false; continue }
        default { Write-Host "Unknown choice" }
    }
    if ($running) { Pause-Screen }
}

Write-Log "UserTools closed, $Script:Changes changes"
