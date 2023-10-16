Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

AddToStatus -color Green "Current File: SetupHybridCloudServerFinal.ps1"

. (Join-Path $PSScriptRoot "settings.ps1")

if ($enableTranscription) {
    Enable-Transcription
}

if (Get-ScheduledTask -TaskName FinishHybridSetup -ErrorAction Ignore) {
    schtasks /DELETE /TN FinishHybridSetup /F | Out-Null
}

AddToStatus "Who is running this: $(whoami)"
AddToStatus "Finishing the Hybrid Cloud Components installation"
Set-Location $HCCProjectDirectory

Start-Sleep -Seconds 60 # wait for 60 seconds, for IIS to start and Update Service API to be up and running.

$totalRetries = 0
do {
    $Failed = $false
    $response = $null
    try {
        AddToStatus "Testing the connection to Update Service server: http://$($env:computername):8060/"
        $response = Invoke-WebRequest -UseBasicParsing -Uri "http://$($env:computername):8060/api/v1/Settings/server"
        $response.StatusCode
        AddToStatus -color Green "Connection tested successfully to Update Service server: http://$($env:computername):8060"
    } catch { 
        AddToStatus -color red "Error connecting to the Update Service server: $($_)."
        AddToStatus -color red "Retrying..."
        AddToStatus -color red "Total Retries: $($totalRetries)."
        Start-Sleep -Seconds 20 # wait for 20 seconds before next attempt.
        $totalRetries += 1
        $Failed = $true
    }
} while (($Failed) -and ($totalRetries -lt 10) -and ($response.StatusCode -ne 200))

AddToStatus "Installing the POS Master (this might take a while)"
& .\UpdatePosMaster.ps1

. "c:\demo\SetupDataDirectorConfig.ps1"

AddToStatus -color Green "Current File: Back to SetupHybridCloudServerFinal.ps1"

AddToStatus "Installation finished successfully."
AddToStatus "The hybrid cloud setup is now finished."
AddToStatus "Will restart now."
# Move-Item -path "c:\demo\status.txt" "c:\demo\status-archive.txt" -Force -ErrorAction SilentlyContinue

shutdown -r -t 30