if (!(Test-Path function:AddToStatus)) {
    function AddToStatus([string]$line, [string]$color = "Gray") {
        ("<font color=""$color"">" + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortDatePattern) + " " + [DateTime]::Now.ToString([System.Globalization.DateTimeFormatInfo]::CurrentInfo.ShortTimePattern.replace(":mm",":mm:ss")) + " $line</font>") | Add-Content -Path "c:\demo\status.txt" -Force -ErrorAction SilentlyContinue
        Write-Host -ForegroundColor $color $line 
    }
}

if (!(Test-Path function:Enable-Transcription)) {
    function Enable-Transcription([string]$logPath) {
        if (!($logPath)) {
            $path = "c:\demo\transcriptions"
        }
        $currentDateTime = Get-Date -UFormat %s
        Start-Transcript (Join-Path $path "transcription-$currentDateTime.log")
    }
}

if (!(Test-Path function:Disable-Transcription)) {
    function Disable-Transcription() {
        Stop-Transcript
    }
}
