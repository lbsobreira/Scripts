# Settings for UserTools - edit these for your site
# Last changed: 2019-03-11 by jm

$Global:Domain        = "LAB"
$Global:DefaultOU     = "OU=Users,OU=Lab,DC=lab,DC=local"
$Global:DisabledOU    = "OU=Disabled,OU=Lab,DC=lab,DC=local"
$Global:HomeShare     = "\\LAB-FS01\Home$"
$Global:LogDir        = "C:\Scripts\UserTools\Logs"
$Global:LogName       = "usertools_" + (Get-Date -Format "yyyyMM") + ".log"
$Global:DefaultGroups = @("Lab Users", "VPN Users")
$Global:MailDomain    = "lab.local"

# Password for new accounts is generated, see New-RandomPassword in CommonLib
$Global:PasswordLength = 14
