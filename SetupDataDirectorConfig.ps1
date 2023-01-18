if ($enableTranscription) {
    Enable-Transcription
}

AddToStatus "Loading the Data Director license"

AddToStatus -color Red "Current File: SetupDataDirectorConfig.ps1"
AddToStatus "Will import Az.Storage module"
AddToStatus "Az.Storage import module skipped"
# Import-Module Az.Storage -Force
AddToStatus "Did import Az.Storage module"

$licenseFileName = 'license.lic'
# AddToStatus "Will create AzStorageContext"
try {
  AddToStatus "StorageAccountName: $StorageAccountName"
  AddToStatus "StorageSasToken: $StorageSasToken"
  AddToStatus "Current AzStorageContext: $storageAccountContext"
  # $storageAccountContext = New-AzStorageContext $StorageAccountName -SasToken $StorageSasToken
}
catch
{
  AddToStatus -color Red  "Error creating Azure Storage Context."
  AddToStatus $Error[0].Exception
}
# AddToStatus "Did create AzStorageContext"

$ListDDLicenseFileHT = @{
  Blob        = $licenseFileName
  Container   = $StorageContainerName
  Context     = $storageAccountContext
}

try
{   
  AddToStatus "Loading the Data Director license - Before Get-AzStorageBlob"
  AddToStatus "Just to test some log overflow - 1"
  AddToStatus "Just to test some log overflow - 2"
  AddToStatus "Just to test some log overflow - 3"
  AddToStatus "Just to test some log overflow - 4"
  AddToStatus "Just to test some log overflow - 5"
  AddToStatus "Just to test some log overflow - 6"
  AddToStatus "Just to test some log overflow - 7"
  AddToStatus "Just to test some log overflow - 8"
  AddToStatus "Just to test some log overflow - 9"
  AddToStatus "Just to test some log overflow - 10"
    $storageAccountContext = New-AzStorageContext $StorageAccountName -SasToken $StorageSasToken -ErrorAction Stop    
  AddToStatus "Just to test some log overflow - 11"
  AddToStatus "Current AzStorageContext: $storageAccountContext"
  Get-AzStorageBlob @ListDDLicenseFileHT -ErrorAction Stop
  AddToStatus "Loading the Data Director license - After Get-AzStorageBlob"

  $LicenseFileSourcePath = "c:\demo\license.lic"
  $LicenseFileDestinationPath = "C:\ProgramData\LS Retail\Data Director\license.lic"
  
  $DownloadDDLicenseFileHT = @{
    Blob        = $licenseFileName
    Container   = $StorageContainerName
    Destination = $LicenseFileSourcePath
    Context     = $storageAccountContext
  }
  AddToStatus "Loading the Data Director license - Before Get-AzStorageBlobContent"
  Get-AzStorageBlobContent @DownloadDDLicenseFileHT -Force
  AddToStatus "Loading the Data Director license - Before Copy-Item"
  Copy-Item -Path $LicenseFileSourcePath -Destination $LicenseFileDestinationPath -Force
}
catch [Microsoft.WindowsAzure.Commands.Storage.Common.ResourceNotFoundException]
{
  AddToStatus -color Red "Data Director license file not found. Using test license."
}
catch
{
  AddToStatus -color Red  "Error loading the Data Director license."
  AddToStatus $Error[0].Exception
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