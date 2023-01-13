Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

$Folder = "C:\DOWNLOAD\SSMS"
$Filename = "$Folder\SSMS-Setup-ENU.exe"
New-Item $Folder -itemtype directory -ErrorAction ignore | Out-Null

if (!(Test-Path $Filename)) {
    AddToStatus "Downloading SQL Server Management Studio (SSMS)"
    $WebClient = New-Object System.Net.WebClient
    $WebClient.DownloadFile("https://aka.ms/ssmsfullsetup", $Filename)
}

AddToStatus "Installing SQL Server Management Studio (SSMS)"
$Params = " /Install /Quiet /Norestart /Logs log.txt"
$Parameters = $Params.Split(" ")
& "$Filename" $Parameters | Out-Null