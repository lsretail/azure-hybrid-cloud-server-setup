Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

# Install Choco
AddToSTatus "Install Choco"
Set-ExecutionPolicy Bypass -Scope Process -Force; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
choco feature enable -n allowGlobalConfirmation

AddToStatus "Install Edge"
choco install microsoft-edge

AddToStatus "Install .net Framework 4.8"
choco install dotnetfx

AddToStatus "Install Azure CLI"
choco install azure-cli