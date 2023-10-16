Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

AddToStatus -color Green "Current File: SetupHybridCloudServer.ps1"

. (Join-Path $PSScriptRoot "settings.ps1")

if (Get-ScheduledTask -TaskName StartHybridCloudServerSetup -ErrorAction Ignore) {
    schtasks /DELETE /TN StartHybridCloudServerSetup /F | Out-Null
}

# Check for a valid Storage Token before moving forward
try {
    $result = az storage blob list --account-name $storageAccountName --container-name $storageContainerName --sas-token """$storageSasToken""" # --debug
    if (0 -ne $LASTEXITCODE) {
        AddToStatus -color Red "Please check your Storage Sas Token."
        AddToStatus $Error[0].Exception.Message
        AddToStatus $($result[0])
        return
    }

    AddToStatus -color Green "Storage Sas Token seems to be valid."
}
catch
{
    AddToStatus -color Red "Please check your Storage Sas Token."
    AddToStatus $Error[0].Exception.Message
    return
}

$Folder = "C:\DOWNLOAD\HybridCloudServerComponents"
$Filename = "$Folder\ls-central-latest.exe"
New-Item $Folder -itemtype directory -ErrorAction ignore | Out-Null

if (!(Test-Path $Filename)) {
    AddToStatus "Downloading Update Service Client Installer Script"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://updateservice.lsretail.com/api/v1/installers/6c1d515b-9b40-4074-ae40-b921f0b2a67d/download", $Filename)
}

AddToStatus "Installing Update Service Client module"
. "$Filename" -silent | Out-Null
if ($LASTEXITCODE -ne 0) { 
    AddToStatus -color red "Error installing Update Service Client module: $($LASTEXITCODE)"
    return
}

$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")
Import-Module UpdateService

AddToStatus "Will install go-current-client package"
$totalRetries = 0
do {
    $Failed = $false
    try {
        Install-GocPackage -Id 'go-current-client'
    } catch { 
        $totalRetries += 1
        AddToStatus -color red "Error installing go-current-client: $($LASTEXITCODE). Retrying..."
        AddToStatus -color red "Error installing go-current-client - Total Retries: $($totalRetries)."

        AddToStatus -color red "Error installing go-current-client: $($_)."
        AddToStatus -color red "Error installing go-current-client - Exception: $($_.Exception)."
        AddToStatus -color red "Error installing go-current-client - ScriptStackTrace: $($_.ScriptStackTrace)."
        AddToStatus -color red "Error installing go-current-client - ErrorDetails: $($_.ErrorDetails)."
        Start-Sleep -Seconds 1 # wait for a seconds before next attempt.
        $Failed = $true
    }
} while (($Failed) -and ($totalRetries -lt 3))

AddToStatus "Did install go-current-client package"
$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")

AddToStatus "Installing SQL Server Express (this might take a while)"
Install-UscPackage -Id 'sql-server-express'

AddToStatus "Configuring the SQL Server authentication mode to mixed mode"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL15.SQLEXPRESS\MSSQLServer" -Name "LoginMode" -Value 2 | Out-Null
Restart-Service -Force 'MSSQL$SQLEXPRESS'

AddToStatus "Preparing SQL Server Studio Management (SSMS) installation (this might take a while)"
. "c:\demo\SetupSSMS.ps1"

AddToStatus "Installing LS Data Director Service"
Install-UscPackage -Id 'ls-dd-service'

AddToStatus "Installing Update Service Server"
Install-UscPackage -Id 'ls-update-service-server'

$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")

Import-Module UpdateService
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
Install-UscPackage -Id 'ls-central-hcc-project' -Arguments $Arguments

$ProjectJson = Get-Content -Path (Join-Path $HCCProjectDirectory 'Project.json') | ConvertFrom-Json
$ProjectJson.WsPassword = $HCSWebServicesPassword
ConvertTo-Json $ProjectJson | Set-Content (Join-Path $HCCProjectDirectory 'Project.json')

AddToStatus "Installing Hybrid Cloud Components"
Set-Location $HCCProjectDirectory

$env:PSModulePath = [System.Environment]::GetEnvironmentVariable("PSModulePath", "Machine")

AddToStatus "Downloading the Business Central license"
if ($licenseFileUri) {
    $LicenseFileSourcePath = "c:\demo\license.bclicense"
    $LicenseFileDestinationPath = (Join-Path $HCCProjectDirectory 'Files/License')
    Download-File -sourceUrl $licensefileuri -destinationFile $LicenseFileSourcePath
    Copy-Item -Path $LicenseFileSourcePath -Destination $LicenseFileDestinationPath -Force
}
else {
    try
    {   
        $licenseFileName = 'DEV.bclicense'
        $LicenseFileSourcePath = "c:\demo\license.bclicense"
        $LicenseFileDestinationPath = (Join-Path $HCCProjectDirectory 'Files/License')

        $result = az storage blob download --file $LicenseFileSourcePath --name $licenseFileName --account-name $storageAccountName --container-name $storageContainerName --sas-token """$storageSasToken""" # --debug
        Copy-Item -Path $LicenseFileSourcePath -Destination $LicenseFileDestinationPath -Force
    
        if (0 -ne $LASTEXITCODE) {
            AddToStatus -color Red  "Error loading the Business Central license."
            AddToStatus $Error[0].Exception
            AddToStatus $($result[0])
            return
        }
    }
    catch
    {
        AddToStatus -color Red  "Error loading the Business Central license."
        AddToStatus $Error[0].Exception
        return
    }
}

AddToStatus "Creating license package"
& .\NewLicensePackage.ps1 -Import

AddToStatus "Downloading necessary package to the Update Service Server (this might take a while as the packages are downloaded from LS Retail's Update Service server)"
& .\GetLsCentralPackages.ps1
AddToStatus "Packages downloaded. You can view all packages on the server: http://localhost:8060"

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