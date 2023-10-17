# usage initialize.ps1
param
(
       [string] $templateLink              = "https://raw.githubusercontent.com/lsretail/azure-hybrid-cloud-server-setup/master/Environments/getbc/azuredeploy.json",
       [string] $containerName             = "navserver",
       [string] $hostName                  = "",
       [string] $vmAdminUsername           = "vmadmin",
       [string] $navAdminUsername          = "admin",
       [string] $azureSqlAdminUsername     = "sqladmin",
       [string] $adminPassword             = "P@ssword1",
       [string] $azureSqlServer            = "",
       [string] $clickonce                 = "No",
       [string] $licenseFileUri            = "",
       [string] $publicDnsName             = "",
	   [string] $beforeContainerSetupScriptUrl = "",
       [string] $style                     = "devpreview",
       [string] $RunWindowsUpdate          = "No",
       [string] $Multitenant               = "No",
       [string] $RemoteDesktopAccess       = "*",
       [string] $BCLocalization            = "W1",
       [string] $HCCProjectDirectory       = "",
       [string] $HCSWebServicesURL         = "",
       [string] $HCSWebServicesUsername    = "",
       [string] $HCSWebServicesPassword    = "",
       [string] $StorageAccountName        = "",
       [string] $StorageContainerName      = "",
       [string] $StorageSasToken           = "",
       [string] $enableTranscription       = "No"
)

$verbosePreference = "SilentlyContinue"
$warningPreference = 'Continue'
$errorActionPreference = 'Stop'

function Get-VariableDeclaration([string]$name) {
    $var = Get-Variable -Name $name
    if ($var) {
        ('$'+$var.Name+' = "'+$var.Value+'"')
    } else {
        ""
    }
}

function AddToStatus([string]$line, [string]$color = "Gray") {
    ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortDatePattern) + " " + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
    Write-Host -ForegroundColor $color $line 
}

function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    AddToStatus "Downloading $destinationFile"
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

if ($publicDnsName -eq "") {
    $publicDnsName = $hostname
}

$ComputerInfo = Get-ComputerInfo
$WindowsInstallationType = $ComputerInfo.WindowsInstallationType
$WindowsProductName = $ComputerInfo.WindowsProductName

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

$settingsScript = "c:\demo\settings.ps1"
if (Test-Path $settingsScript) {
    . "$settingsScript"
} else {
    New-Item -Path "c:\myfolder" -ItemType Directory -ErrorAction Ignore | Out-Null
    New-Item -Path "C:\DEMO" -ItemType Directory -ErrorAction Ignore | Out-Null
    
    Get-VariableDeclaration -name "templateLink"           | Set-Content $settingsScript
    Get-VariableDeclaration -name "hostName"               | Add-Content $settingsScript
    Get-VariableDeclaration -name "containerName"          | Add-Content $settingsScript
    Get-VariableDeclaration -name "vmAdminUsername"        | Add-Content $settingsScript
    Get-VariableDeclaration -name "navAdminUsername"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "azureSqlAdminUsername"  | Add-Content $settingsScript
    Get-VariableDeclaration -name "azureSqlServer"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "clickonce"              | Add-Content $settingsScript
    Get-VariableDeclaration -name "licenseFileUri"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "publicDnsName"          | Add-Content $settingsScript
    Get-VariableDeclaration -name "style"                  | Add-Content $settingsScript
    Get-VariableDeclaration -name "RunWindowsUpdate"       | Add-Content $settingsScript
    Get-VariableDeclaration -name "Multitenant"            | Add-Content $settingsScript
    Get-VariableDeclaration -name "WindowsInstallationType"| Add-Content $settingsScript
    Get-VariableDeclaration -name "WindowsProductName"     | Add-Content $settingsScript
    Get-VariableDeclaration -name "RemoteDesktopAccess"    | Add-Content $settingsScript
    Get-VariableDeclaration -name "HCCProjectDirectory"    | Add-Content $settingsScript
    Get-VariableDeclaration -name "HCSWebServicesURL"      | Add-Content $settingsScript
    Get-VariableDeclaration -name "HCSWebServicesUsername" | Add-Content $settingsScript
    Get-VariableDeclaration -name "HCSWebServicesPassword" | Add-Content $settingsScript
    Get-VariableDeclaration -name "BCLocalization"         | Add-Content $settingsScript
    Get-VariableDeclaration -name "StorageAccountName"     | Add-Content $settingsScript
    Get-VariableDeclaration -name "StorageContainerName"   | Add-Content $settingsScript
    Get-VariableDeclaration -name "StorageSasToken"        | Add-Content $settingsScript
    Get-VariableDeclaration -name "enableTranscription"    | Add-Content $settingsScript

    $passwordKey = New-Object Byte[] 16
    [Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($passwordKey)
    ('$passwordKey = [byte[]]@('+"$passwordKey".Replace(" ",",")+')') | Add-Content $settingsScript

    $securePassword = ConvertTo-SecureString -String $adminPassword -AsPlainText -Force
    $encPassword = ConvertFrom-SecureString -SecureString $securePassword -Key $passwordKey
    ('$adminPassword = "'+$encPassword+'"') | Add-Content $settingsScript

    $encOffice365Password = ""
    if ("$Office365Password" -ne "") {
        $secureOffice365Password = ConvertTo-SecureString -String $Office365Password -AsPlainText -Force
        $encOffice365Password = ConvertFrom-SecureString -SecureString $secureOffice365Password -Key $passwordKey
    }
    ('$Office365Password = "'+$encOffice365Password+'"') | Add-Content $settingsScript
}

#
# styles:
#   devpreview
#   developer
#   workshop
#   sandbox
#   demo
#

if (Test-Path -Path "c:\DEMO\Status.txt" -PathType Leaf) {
    AddToStatus "VM already initialized."
    exit
}

Set-Content "c:\DEMO\RemoteDesktopAccess.txt" -Value $RemoteDesktopAccess

Set-ExecutionPolicy -ExecutionPolicy unrestricted -Force

AddToStatus -color Green "Starting initialization"
AddToStatus "Running $WindowsProductName"
AddToStatus "Initialize, user: $env:USERNAME"
AddToStatus "TemplateLink: $templateLink"
$scriptPath = $templateLink.SubString(0,$templateLink.LastIndexOf('/')+1)

Download-File -sourceUrl "$($scriptPath)Helpers.ps1" -destinationFile "c:\demo\Helpers.ps1"
. "c:\demo\Helpers.ps1"

if ($enableTranscription) {
    Enable-Transcription
}

$downloadFolder = "C:\DOWNLOAD"
New-Item -Path $downloadFolder -ItemType Directory -ErrorAction Ignore | Out-Null

if (!(Get-PackageProvider -Name NuGet -ListAvailable -ErrorAction Ignore)) {
    AddToStatus "Installing NuGet Package Provider"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.208 -Force -WarningAction Ignore | Out-Null
}
if (!(Get-Module powershellget | Where-Object { $_.Version -ge [version]"2.2.5" })) {
    AddToStatus "Installing PowerShellGet 2.2.5"
    Install-Module powershellget -RequiredVersion 2.2.5 -force
    Import-Module powershellget -RequiredVersion 2.2.5
}

AddToStatus "Installing Internet Information Server (this might take a few minutes)"
if ($WindowsInstallationType -eq "Server") {
    Add-WindowsFeature Web-Server,web-Asp-Net45,NET-HTTP-Activation,Web-Mgmt-Console,Web-Dyn-Compression,Web-Basic-Auth
} else {
    Enable-WindowsOptionalFeature -Online -FeatureName IIS-WebServer,IIS-ASPNET45,WCF-HTTP-Activation,IIS-ManagementConsole,IIS-BasicAuthentication,IIS-HttpCompressionDynamic -All -NoRestart | Out-Null
}

# Get Version Script
Download-File -sourceUrl "$($scriptPath)GetVersion.ps1"           -destinationFile "c:\demo\GetVersion.ps1"
Download-File -sourceUrl "$($scriptPath)scriptVersion.txt"           -destinationFile "c:\demo\scriptVersion.txt"
. "c:\demo\GetVersion.ps1"

Remove-Item -Path "C:\inetpub\wwwroot\iisstart.*" -Force
Download-File -sourceUrl "$($scriptPath)Default.aspx"            -destinationFile "C:\inetpub\wwwroot\default.aspx"
Download-File -sourceUrl "$($scriptPath)status.aspx"             -destinationFile "C:\inetpub\wwwroot\status.aspx"
Download-File -sourceUrl "$($scriptPath)line.png"                -destinationFile "C:\inetpub\wwwroot\line.png"
Download-File -sourceUrl "$($scriptPath)web.config"              -destinationFile "C:\inetpub\wwwroot\web.config"

$title = 'Dynamics Container Host'
[System.IO.File]::WriteAllText("C:\inetpub\wwwroot\title.txt", $title)
[System.IO.File]::WriteAllText("C:\inetpub\wwwroot\hostname.txt", $publicDnsName)
[System.IO.File]::WriteAllText("C:\inetpub\wwwroot\containerName.txt", $containerName)

if ("$RemoteDesktopAccess" -ne "") {
AddToStatus "Creating Connect.rdp"
"full address:s:${publicDnsName}:3389
prompt for credentials:i:1
username:s:$vmAdminUsername" | Set-Content "c:\inetpub\wwwroot\Connect.rdp"
}

if ($WindowsInstallationType -eq "Server") {
    AddToStatus "Turning off IE Enhanced Security Configuration"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue | Out-Null
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}" -Name "IsInstalled" -Value 0 -ErrorAction SilentlyContinue | Out-Null
}

$setupStartScript = "c:\demo\SetupStart.ps1"
$setupVmScript = "c:\demo\SetupVm.ps1"
$setupPrerequirements = "c:\demo\SetupPrerequirements.ps1"
$setupHybridCloudServer = "c:\demo\SetupHybridCloudServer.ps1"
$setupHybridCloudServerFinal = "c:\demo\SetupHybridCloudServerFinal.ps1"
$setupDataDirectorConfig = "c:\demo\SetupDataDirectorConfig.ps1"
$setupSSMS = "c:\demo\SetupSSMS.ps1"

if ($vmAdminUsername -ne $navAdminUsername) {
    '. "c:\run\SetupWindowsUsers.ps1"
Write-Host "Creating Host Windows user"
$hostUsername = "'+$vmAdminUsername+'"
if (!($securePassword)) {
    # old version of the generic nav container
    $securePassword = ConvertTo-SecureString -String $password -AsPlainText -Force
}
New-LocalUser -AccountNeverExpires -FullName $hostUsername -Name $hostUsername -Password $securePassword -ErrorAction Ignore | Out-Null
Add-LocalGroupMember -Group administrators -Member $hostUsername -ErrorAction Ignore
' | Set-Content "c:\myfolder\SetupWindowsUsers.ps1"
}

Download-File -sourceUrl "$($scriptPath)SetupVm.ps1"           -destinationFile $setupVmScript
Download-File -sourceUrl "$($scriptPath)SetupStart.ps1"        -destinationFile $setupStartScript
Download-File -sourceUrl "$($scriptPath)SetupPrerequirements.ps1" -destinationFile $setupPrerequirements
Download-File -sourceUrl "$($scriptPath)SetupHybridCloudServer.ps1" -destinationFile $setupHybridCloudServer
Download-File -sourceUrl "$($scriptPath)SetupHybridCloudServerFinal.ps1" -destinationFile $setupHybridCloudServerFinal
Download-File -sourceUrl "$($scriptPath)SetupDataDirectorConfig.ps1" -destinationFile $setupDataDirectorConfig
Download-File -sourceUrl "$($scriptPath)SetupSSMS.ps1" -destinationFile $setupSSMS

if ($beforeContainerSetupScriptUrl) {
    # if ($beforeContainerSetupScriptUrl -notlike "https://*" -and $beforeContainerSetupScriptUrl -notlike "http://*") {
        # $beforeContainerSetupScriptUrl = "$($scriptPath)$beforeContainerSetupScriptUrl"
    # }
    $beforeContainerSetupScript = "c:\demo\BeforeContainerSetupScript.ps1"
    Download-File -sourceUrl $beforeContainerSetupScriptUrl -destinationFile $beforeContainerSetupScript
}

$startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File $setupStartScript"
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$startupTrigger.Delay = "PT1M"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
Register-ScheduledTask -TaskName "SetupStart" `
                       -Action $startupAction `
                       -Trigger $startupTrigger `
                       -Settings $settings `
                       -RunLevel "Highest" `
                       -User "NT AUTHORITY\SYSTEM" | Out-Null

try {
    $version = [System.Version](Get-ItemPropertyValue -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -Name 'Version')
    if ($version -lt '4.8.0') {
        AddToStatus "Installing DotNet 4.8 and restarting computer to start Installation tasks"
        $ProgressPreference = "SilentlyContinue"
        $dotnet48exe = Join-Path $downloadFolder "dotnet48.exe"
        Invoke-WebRequest -UseBasicParsing -uri 'https://go.microsoft.com/fwlink/?linkid=2088631' -OutFile $dotnet48exe
        & $dotnet48exe /q
    }
}
catch {
    AddToStatus -color Red ".NET Framework 4.7 or higher doesn't seem to be installed. Something went wrong during installation."
}
                    
AddToStatus "Restarting computer and start Installation tasks"
Shutdown -r -t 30
