#################################################
# CommonLib.ps1 - shared functions for the user scripts
# dot-source this file:   . .\CommonLib.ps1
#################################################

Import-Module ActiveDirectory

Function Write-Log($msg) {
    if (!(Test-Path $Global:LogDir)) { mkdir $Global:LogDir | Out-Null }
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$stamp $env:USERNAME $msg" | Out-File -FilePath "$Global:LogDir\$Global:LogName" -Append
}

Function Get-UserInfo($sam) {
    $u = Get-ADUser -Identity $sam -Properties DisplayName, EmailAddress, LastLogonDate, Enabled, LockedOut, MemberOf, HomeDirectory -ErrorAction SilentlyContinue
    if (!$u) {
        Write-Host "User $sam not found" -ForegroundColor Red
        Write-Log "lookup failed: $sam"
        return $null
    }
    return $u
}

Function Find-UserByName($name) {
    Get-ADUser -Filter "Name -like '*$name*'" -Properties DisplayName, Department |
        Select-Object SamAccountName, DisplayName, Department, Enabled
}

Function New-RandomPassword {
    param([int]$Length = $Global:PasswordLength)
    $chars = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!#%+'
    -join (1..$Length | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

Function Get-SamFromName($first, $last) {
    $sam = ($first.Substring(0, 1) + $last).ToLower() -replace '[^a-z0-9]', ''
    if ($sam.Length -gt 20) { $sam = $sam.Substring(0, 20) }
    $i = 1
    $candidate = $sam
    while (Get-ADUser -Filter "SamAccountName -eq '$candidate'" -ErrorAction SilentlyContinue) {
        $candidate = "$sam$i"
        $i++
    }
    return $candidate
}

Function Import-NewUsers {
    param([string]$CsvPath = "users.csv")
    if (!(Test-Path $CsvPath)) {
        Write-Host "CSV not found: $CsvPath" -ForegroundColor Red
        return
    }
    $rows = Import-Csv $CsvPath
    $created = @()
    foreach ($r in $rows) {
        $sam = Get-SamFromName $r.FirstName $r.LastName
        $pw = New-RandomPassword
        $params = @{
            Name              = "$($r.FirstName) $($r.LastName)"
            GivenName         = $r.FirstName
            Surname           = $r.LastName
            SamAccountName    = $sam
            UserPrincipalName = "$sam@$Global:MailDomain"
            Department        = $r.Department
            Title             = $r.Title
            Path              = $Global:DefaultOU
            AccountPassword   = (ConvertTo-SecureString $pw -AsPlainText -Force)
            Enabled           = $true
            ChangePasswordAtLogon = $true
        }
        try {
            New-ADUser @params
            if ($r.Manager) { Set-ADUser -Identity $sam -Manager $r.Manager }
            foreach ($g in $Global:DefaultGroups) { Add-ADGroupMember -Identity $g -Members $sam }
            New-HomeFolder $sam
            Write-Log "created $sam"
            $created += [pscustomobject]@{ Sam = $sam; Password = $pw }
        } catch {
            Write-Host "Failed to create $sam : $_" -ForegroundColor Red
            Write-Log "create failed $sam : $_"
        }
    }
    $created | Export-Csv -Path ".\created_$(Get-Date -Format yyyyMMdd).csv" -NoTypeInformation
    Write-Host "$($created.Count) users created, passwords in created_$(Get-Date -Format yyyyMMdd).csv"
}

Function New-HomeFolder($sam) {
    $path = Join-Path $Global:HomeShare $sam
    if (!(Test-Path $path)) {
        New-Item -Path $path -ItemType Directory | Out-Null
        $acl = Get-Acl $path
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Global:Domain\$sam", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.AddAccessRule($rule)
        Set-Acl -Path $path -AclObject $acl
    }
    Set-ADUser -Identity $sam -HomeDirectory $path -HomeDrive "H:"
}

# old version, the one in UserTools.ps1 is newer
Function Show-UserInfo($sam) {
    $u = Get-UserInfo $sam
    if ($u) { $u | Format-List Name, SamAccountName, Enabled }
}

Function Pause-Screen {
    Read-Host "Press Enter to continue" | Out-Null
}
