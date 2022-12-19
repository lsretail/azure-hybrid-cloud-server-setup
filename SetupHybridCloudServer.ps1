if (!(Test-Path function:AddToStatus)) {
    function AddToStatus([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortDatePattern) + " " + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor $color $line 
    }
}

. (Join-Path $PSScriptRoot "settings.ps1")

$Folder = "C:\DOWNLOAD\HybridCloudServerComponents"
$Filename = "$Folder\ls-central-latest.exe"
New-Item $Folder -itemtype directory -ErrorAction ignore | Out-Null

if (!(Test-Path $Filename)) {
    AddToStatus "Downloading Update Service Client Installer Script"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://portal.lsretail.com/media/uiucpd5g/ls-central-latest.exe", $Filename)
}

AddToStatus "Installing Update Service Client module"
. "$Filename" /VERYSILENT /NORESTART /SUPPRESSMSGBOXES | Out-Null
if ($LASTEXITCODE -ne 0) { 
    AddToStatus -color red "Error installing Update Service Client module: $($LASTEXITCODE)"
    return
}

$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
AddToStatus "Will install go-current-client"
Start-Sleep -Seconds 5

try { 
    Install-GocPackage -Id 'go-current-client'
}
catch {
    AddToStatus "Error installing go-current-client: $($LASTEXITCODE). Retrying..."
    Install-GocPackage -Id 'go-current-client'
}

AddToStatus "Did install go-current-client"
$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")

AddToStatus "Installing SQL Server Express (this might take a while)"
Install-GocPackage -Id 'sql-server-express'

AddToStatus "Configuring the SQL Server authentication mode to mixed mode"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQLServer" -Name "LoginMode" -Value 2 | Out-Null
Restart-Service -Force 'MSSQL$SQLEXPRESS'

AddToStatus "Preparing SQL Server Studio Management (SSMS) installation (this might take a while)"
. "c:\demo\SetupSSMS.ps1"

AddToStatus "Installing LS Data Director Service"
Install-GocPackage -Id 'ls-dd-service'

AddToStatus "Installing Update Service Server"
Install-GocPackage -Id 'go-current-server'

AddToStatus "Installing Update Service Server Management"
Install-GocPackage -Id 'go-current-server-management'

$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")

Import-Module GoCurrent
Import-Module GoCurrentServer

$ServerAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName.StartsWith('LSRetail.GoCurrent.Server.Management')}
$ClientAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.FullName.StartsWith('LSRetail.GoCurrent.Client.Management')}
$ServerVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ServerAssembly.Location).ProductVersion
$ClientVersion = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ClientAssembly.Location).ProductVersion
if ($ServerVersion -ne $ClientVersion)
{
    Write-Warning "Client and server version are not the same ($ServerVersion vs $ClientVersion)"
}

AddToStatus "Preparing Hybrid Cloud Components project"
$Arguments = @{
    'ls-central-hcc-project' = @{
        ProjectDir = $HCCProjectDirectory
        CompanyName = 'POSMaster'
        PackageIdPrefix = 'posmaster'
        Localization = $BCLocalization
        WsUri = $HCSWebServicesURL
        WsUser = $HCSWebServicesUsername
        WsPassword = $HCSWebServicesPassword
    }
}
Install-GocPackage -Id 'ls-central-hcc-project' -Arguments $Arguments

$ProjectJson = Get-Content -Path (Join-Path $HCCProjectDirectory 'Project.json') | ConvertFrom-Json
$ProjectJson.WsPassword = $HCSWebServicesPassword
ConvertTo-Json $ProjectJson | Set-Content (Join-Path $HCCProjectDirectory 'Project.json')

AddToStatus "Installing Hybrid Cloud Components"
Set-Location $HCCProjectDirectory

$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")

AddToStatus "Downloading the Business Central license"
if ($licenseFileUri) {
    $LicenseFileSourcePath = "c:\demo\license.flf"
    $LicenseFileDestinationPath = (Join-Path $HCCProjectDirectory 'Files/License')
    Download-File -sourceUrl $licensefileuri -destinationFile $LicenseFileSourcePath
    Copy-Item -Path $LicenseFileSourcePath -Destination $LicenseFileDestinationPath -Force
}
else {
    Import-Module Az.Storage

    $licenseFileName = 'DEV.flf'
    $storageAccountContext = New-AzStorageContext $StorageAccountName -SasToken $StorageSasToken

    $LicenseFileSourcePath = "c:\demo\license.flf"
    $LicenseFileDestinationPath = (Join-Path $HCCProjectDirectory 'Files/License')

    $DownloadBCLicenseFileHT = @{
        Blob        = $licenseFileName
        Container   = $StorageContainerName
        Destination = $LicenseFileSourcePath
        Context     = $storageAccountContext
    }
    Get-AzStorageBlobContent @DownloadBCLicenseFileHT
    Copy-Item -Path $LicenseFileSourcePath -Destination $LicenseFileDestinationPath -Force
}

AddToStatus "Creating license package"
& .\NewLicensePackage.ps1 -Import

AddToStatus "Downloading necessary package to the Update Service Server (this might take a while as the packages are downloaded from LS Retail's Update Service server)"
& .\GetLsCentralPackages.ps1
AddToStatus "Packages downloaded. You can view all packages on the server: http://localhost:8030"

AddToStatus "Updating NewBundlePackage script to include the license package"
$bundlePackage = Get-Content -Path (Join-Path $HCCProjectDirectory 'NewBundlePackage.ps1')
$newBundlePackage = $bundlePackage -replace '#@{ Id = "$($Config.PackageIdPrefix)-license"; "Version" = "1.0.0" }', '@{ Id = "$($Config.PackageIdPrefix)-license"; "Version" = "1.0.0" }'
$newBundlePackage | Set-Content -Path (Join-Path $HCCProjectDirectory 'NewBundlePackage.ps1')

# TODO: Include customer extensions

AddToStatus "Updating NewBundlePackage script to include the LS Hardware Station"
$bundlePackage = Get-Content -Path (Join-Path $HCCProjectDirectory 'NewBundlePackage.ps1')
$newBundlePackage = $bundlePackage -replace '#@{ Id = "ls-hardware-station"; Version = $Config.LsCentralVersion }', '@{ Id = "ls-hardware-station"; Version = $Config.LsCentralVersion }'
$newBundlePackage | Set-Content -Path (Join-Path $HCCProjectDirectory 'NewBundlePackage.ps1')

# TODO: Include OPOS drivers (?)

$setupHybridCloudServerFinal = "c:\demo\SetupHybridCloudServerFinal.ps1"

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

$taskName = 'FinishHybridSetup'
$startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File $setupHybridCloudServerFinal"
$startupTrigger = New-ScheduledTaskTrigger -AtStartup
$startupTrigger.Delay = "PT1M"
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd
Register-ScheduledTask -TaskName $taskName `
                       -Action $startupAction `
                       -Trigger $startupTrigger `
                       -Settings $settings `
                       -RunLevel "Highest" `
                       -User $vmAdminUsername `
                       -Password $plainPassword | Out-Null

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($null -ne $task)
{
    AddToStatus "Created scheduled task: '$($task.ToString())'."
}
else
{
    AddToStatus "Created scheduled task: FAILED."
}

AddToStatus "Creating the POS Master and POS bundle"
& .\NewBundlePackage.ps1 -Import

# Will run after the start on the SetupVm.ps1
AddToStatus "Will finish Hybrid Cloud Server setup after the restart"
shutdown -r -t 30