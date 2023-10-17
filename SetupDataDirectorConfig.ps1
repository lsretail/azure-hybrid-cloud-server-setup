Import-Module (Join-Path $PSScriptRoot "Helpers.ps1") -Force

if ($enableTranscription) {
    Enable-Transcription
}

AddToStatus -color Green "Current File: SetupDataDirectorConfig.ps1"
AddToStatus "Loading the Data Director license"

Import-Module Az.Storage -Force

try
{   
  $licenseFileName = 'license.lic'
  $LicenseFileSourcePath = "c:\demo\license.lic"
  $LicenseFileDestinationPath = "C:\ProgramData\LS Retail\Data Director\license.lic"
  
  $storageContext = New-AzStorageContext -StorageAccountName $storageAccountName -SasToken $storageSasToken
  Get-AzStorageBlobContent -Container $storageContainerName -Blob $licenseFileName -Context $storageContext -Destination $LicenseFileSourcePath -ErrorAction Stop
  Copy-Item -Path $LicenseFileSourcePath -Destination $LicenseFileDestinationPath -Force

  if (0 -ne $LASTEXITCODE) {
    AddToStatus -color Red  "Error loading the Data Director license."
    AddToStatus -ForegroundColor Red $_.Exception.Message
    return
  }
}
catch [Microsoft.WindowsAzure.Commands.Storage.Common.ResourceNotFoundException]
{
  AddToStatus -color Red "Data Director license file not found. Using test license."
}
catch [Microsoft.Azure.Storage.StorageException]
{
    AddToStatus -color Red "Please check your Storage Sas Token."
    AddToStatus -ForegroundColor Red $_.Exception.Message
}
catch
{
  AddToStatus -color Red  "Error loading the Data Director license."
  AddToStatus -ForegroundColor Red $_.Exception.Message
}

AddToStatus "Enabling Web Services in LS Data Director"
$ddConfigFilename = "C:\ProgramData\LS Retail\Data Director\lsretail.config"
$dd_config = Get-Content $ddConfigFilename
$dd_config | % { $_.Replace("<WebSrv>false</WebSrv>", "<WebSrv>true</WebSrv>") } | Set-Content $ddConfigFilename

$xml = [xml](get-content $ddConfigFilename)

if ($null -eq $xml.SelectSingleNode('//DDConfig/AppConfig/Program[@Port="8"]')) {
  AddToStatus "Adding Web Service related configuration to Data Director configuration file."

  [xml]$newNode = @"
  <Program Port="8">
  <Exec>DDDatabaseWS.exe</Exec>
  <Desc>Web Service Program</Desc>
  <Host>$($env:Computername)</Host>
  <Type>WebService</Type>
  <ExecBy>1</ExecBy>
  <Router>2</Router>
  <Debug>0</Debug>
  <Param>
    <NavPath>C:\Program Files (x86)\LS Retail\Data Director 3\cfront</NavPath>
    <DecFix>F05</DecFix>
    <RepChr></RepChr>
    <IsoLevel>ReadCommitted</IsoLevel>
    <ConTimeOut>1</ConTimeOut>
    <FOBTimeOut>10</FOBTimeOut>
    <SQLTimeOut>0</SQLTimeOut>
    <ThrTimeOut>60</ThrTimeOut>
    <WSBatchSize>100</WSBatchSize>
    <WSTimeout>10</WSTimeout>
    <TSTimeOut>10</TSTimeOut>
    <Extra>true</Extra>
    <BigDec>false</BigDec>
    <SUpd>false</SUpd>
    <UseTrunc>false</UseTrunc>
    <NavCU>99001483</NavCU>
  </Param>
  </Program>
"@

  $xml.DDConfig.AppConfig.InsertAfter($xml.ImportNode($newNode.Program, $true), $xml.DDConfig.AppConfig.LastChild) | out-null
  $xml.Save($ddConfigFilename)
}

Restart-Service -Force 'DDService'

AddToStatus "Setting up Full Control permissions to the Data Director folder"

$DDFolder = "C:\ProgramData\LS Retail\Data Director"
$Acl = Get-Acl $DDFolder
$Ar = New-Object System.Security.AccessControl.FileSystemAccessRule("Users", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$Acl.SetAccessRule($Ar)
Set-Acl $DDFolder $Acl

AddToStatus "Adding a new SQL user for DD usage"

# TODO: Add as a parameter (Only for the password but keep the username hardcoded)
$sqlDDUser = 'datadirector'
$sqlDDPassword = 'jrPLY6zAXxgVyG2u'

AddToStatus "Data Director user added with username: '$($sqlDDUser)'."
AddToStatus "Data Director user added with password: '$($sqlDDPassword)'."

# To create user the sa user
Invoke-Sqlcmd -ServerInstance "$($env:Computername)\SQLEXPRESS" -Database "master" -Query "CREATE LOGIN [$($sqlDDUser)] WITH PASSWORD=N'$($sqlDDPassword)', CHECK_POLICY=OFF"
Invoke-Sqlcmd -ServerInstance "$($env:Computername)\SQLEXPRESS" -Database "GoCurrent" -Query "CREATE USER [$($sqlDDUser)] FOR LOGIN [$($sqlDDUser)]"
Invoke-Sqlcmd -ServerInstance "$($env:Computername)\SQLEXPRESS" -Database "GoCurrent" -Query "ALTER ROLE [db_owner] ADD MEMBER [$($sqlDDUser)]"
Invoke-Sqlcmd -ServerInstance "$($env:Computername)\SQLEXPRESS" -Database "POSMaster" -Query "CREATE USER [$($sqlDDUser)] FOR LOGIN [$($sqlDDUser)]"
Invoke-Sqlcmd -ServerInstance "$($env:Computername)\SQLEXPRESS" -Database "POSMaster" -Query "ALTER ROLE [db_owner] ADD MEMBER [$($sqlDDUser)]"

Restart-Service -Force 'MSSQL$SQLEXPRESS'