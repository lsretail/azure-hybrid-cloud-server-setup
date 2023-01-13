Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

. (Join-Path $PSScriptRoot "settings.ps1")

if ($enableTranscription) {
    Enable-Transcription
}

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