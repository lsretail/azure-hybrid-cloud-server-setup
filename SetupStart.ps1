Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

function Download-File([string]$sourceUrl, [string]$destinationFile)
{
    AddToStatus "Downloading $destinationFile"
    Remove-Item -Path $destinationFile -Force -ErrorAction Ignore
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    (New-Object System.Net.WebClient).DownloadFile($sourceUrl, $destinationFile)
}

function Register-NativeMethod([string]$dll, [string]$methodSignature)
{
    $script:nativeMethods += [PSCustomObject]@{ Dll = $dll; Signature = $methodSignature; }
}

function Add-NativeMethods()
{
    $nativeMethodsCode = $script:nativeMethods | % { "
        [DllImport(`"$($_.Dll)`")]
        public static extern $($_.Signature);
    " }

    Add-Type @"
        using System;
        using System.Text;
        using System.Runtime.InteropServices;
        public class NativeMethods {
            $nativeMethodsCode
        }
"@
}

. (Join-Path $PSScriptRoot "settings.ps1")

if ($enableTranscription) {
    Enable-Transcription
}

AddToStatus "SetupStart, User: $env:USERNAME"

$ComputerInfo = Get-ComputerInfo
$WindowsInstallationType = $ComputerInfo.WindowsInstallationType

if (-not (Get-InstalledModule AzureAD -ErrorAction SilentlyContinue)) {
    AddToStatus "Installing AzureAD module"
    Install-Module AzureAD -Force
}

# if (-not (Get-InstalledModule SqlServer -ErrorAction SilentlyContinue)) {
    AddToStatus "Installing SqlServer module"
    # Installing this specific version because of the following error when running the UpdatePOSMaster.ps1 script.
    # https://github.com/microsoft/SQLServerPSModule/issues/45
    #
    # Method not found: 'Void 
	# Microsoft.Data.SqlClient.AlwaysEncrypted.AzureKeyVaultProvider.SqlColumnEncryptionAzureKeyVaultProvider..ctor(Azure.Core.TokenCredential)'.
    #
    # This is due to some incompatibility with SqlServer and Az modules.
    Uninstall-Module -Name SqlServer -AllVersion  -Force
    Install-Module -Name SqlServer -RequiredVersion 21.1.18256 -AllowClobber -Force
# }

$securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
$plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

if ($WindowsInstallationType -eq "Server") {

    if (Get-ScheduledTask -TaskName SetupStart -ErrorAction Ignore) {
        schtasks /DELETE /TN SetupStart /F | Out-Null
    }

    AddToStatus "Launch SetupVm"
    $onceAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\setupVm.ps1"
    Register-ScheduledTask -TaskName SetupVm `
                           -Action $onceAction `
                           -RunLevel Highest `
                           -User $vmAdminUsername `
                           -Password $plainPassword | Out-Null
    
    Start-ScheduledTask -TaskName SetupVm

    if ($enableTranscription) {
        Disable-Transcription
    }    
}
else {
    
    if (Get-ScheduledTask -TaskName SetupStart -ErrorAction Ignore) {
        schtasks /DELETE /TN SetupStart /F | Out-Null
    }
    
    $startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File c:\demo\SetupVm.ps1"
    $startupTrigger = New-ScheduledTaskTrigger -AtStartup
    $startupTrigger.Delay = "PT1M"
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable -DontStopOnIdleEnd -WakeToRun
    Register-ScheduledTask -TaskName "SetupVm" `
                           -Action $startupAction `
                           -Trigger $startupTrigger `
                           -Settings $settings `
                           -RunLevel "Highest" `
                           -User $vmAdminUsername `
                           -Password $plainPassword | Out-Null
    
    AddToStatus -color Yellow "Restarting computer. After restart, please Login to computer using RDP in order to resume the installation process. This is not needed for Windows Server."
    shutdown -r -t 30
}
