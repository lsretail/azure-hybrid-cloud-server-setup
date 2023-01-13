Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

$version = Get-Content -Path "c:\demo\scriptVersion.txt"
AddToStatus -color Green "Running script version $($version)."
