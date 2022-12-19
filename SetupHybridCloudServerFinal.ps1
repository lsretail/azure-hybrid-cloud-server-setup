if (!(Test-Path function:AddToStatus)) {
    function AddToStatus([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortDatePattern) + " " + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor $color $line 
    }
}

. (Join-Path $PSScriptRoot "settings.ps1")

AddToStatus "Who is running this: $(whoami)"
AddToStatus "Finishing the Hybrid Cloud Components installation"
Set-Location $HCCProjectDirectory

AddToStatus "Installing the POS Master"
& .\UpdatePosMaster.ps1

. "c:\demo\SetupDataDirectorConfig.ps1"

if (Get-ScheduledTask -TaskName FinishHybridSetup -ErrorAction Ignore) {
    schtasks /DELETE /TN FinishHybridSetup /F | Out-Null
}

AddToStatus "Installation finished successfully."
AddToStatus "The hybrid cloud setup is now finished."
AddToStatus "Will restart now."
# Move-Item -path "c:\demo\status.txt" "c:\demo\status-archive.txt" -Force -ErrorAction SilentlyContinue

shutdown -r -t 30