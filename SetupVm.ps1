$ErrorActionPreference = "Stop"
$WarningActionPreference = "Continue"

Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

. (Join-Path $PSScriptRoot "settings.ps1")

if ($enableTranscription) {
    Enable-Transcription
}

$ComputerInfo = Get-ComputerInfo
$WindowsInstallationType = $ComputerInfo.WindowsInstallationType
$WindowsProductName = $ComputerInfo.WindowsProductName

try {
    AddToStatus "SetupVm, User: $env:USERNAME"

    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls -bor [System.Net.SecurityProtocolType]::Ssl3 -bor [System.Net.SecurityProtocolType]::Tls11 -bor [System.Net.SecurityProtocolType]::Tls12

    AddToStatus "Enabling File Download in IE"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1803" -Value 0

    AddToStatus "Enabling Font Download in IE"
    Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0
    Set-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\Zones\3" -Name "1604" -Value 0

    AddToStatus "Show hidden files and file types"
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  -Name "Hidden"      -value 1
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'  -Name "HideFileExt" -value 0

    if ($WindowsInstallationType -eq "Server") {
        AddToStatus "Disabling Server Manager Open At Logon"
        New-ItemProperty -Path "HKCU:\Software\Microsoft\ServerManager" -Name "DoNotOpenServerManagerAtLogon" -PropertyType "DWORD" -Value "0x1" –Force | Out-Null
    }

    $beforeContainerSetupScript = (Join-Path $PSScriptRoot "BeforeContainerSetupScript.ps1")
    if (Test-Path $beforeContainerSetupScript) {
        AddToStatus "Running beforeContainerSetupScript"
        . $beforeContainerSetupScript
    }

    if (Get-ScheduledTask -TaskName SetupVm -ErrorAction Ignore) {
        schtasks /DELETE /TN SetupVm /F | Out-Null
    }

    if ($RunWindowsUpdate -eq "Yes") {
        AddToStatus "Installing Windows Updates"
        install-module PSWindowsUpdate -force
        Get-WUInstall -install -acceptall -autoreboot | ForEach-Object { AddToStatus ($_.Status + " " + $_.KB + " " +$_.Title) }
        AddToStatus "Windows updates installed"
    }

    # if (!($imageName)) {
    #    Remove-Item -path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
    # }

    . "c:\demo\SetupPrerequirements.ps1"

    $setupHybridCloudServer = "c:\demo\SetupHybridCloudServer.ps1"   

    $securePassword = ConvertTo-SecureString -String $adminPassword -Key $passwordKey
    $plainPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))

    $taskName = 'StartHybridCloudServerSetup'
    $startupAction = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy UnRestricted -File $setupHybridCloudServer"
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

    AddToStatus "Restarting the virtual machine."
    shutdown -r -t 30

} catch {
    AddToStatus -Color Red -line $_.Exception.Message
    $_.ScriptStackTrace.Replace("`r`n","`n").Split("`n") | ForEach-Object { AddToStatus -Color Red -line $_ }
    throw
}
