## Check for gum 
$gumInstalled = Get-Command gum -ErrorAction SilentlyContinue
if(!$gumInstalled) {
    return "Please install gum to continue (https://github.com/charmbracelet/gum)"
} 

## Helper function to select with gum if more than one match
function Select-WithGum {
    param(
        [string[]]$Options,
        [string]$Prompt
    )
    if ($Options.Count -eq 1) {
        return $Options[0]
    } elseif ($Options.Count -gt 1) {
        # Requires gum to be installed and available in PATH
        return ($Options | gum choose --header "$Prompt")
    } else {
        return $null
    }
}

function Clean-FilePath {
    param(
        [string]$filePath
    )
    return $filePath  -replace '"', ''
}

function Cancel-Restore {
    return "Import canceled"
}

function Rename-Database {
    return gum input --placeholder "please input database name"
}

function Check-IfDatabaseExists {
    param(
        [string]$databaseName,
        [string]$sqlServerInstance
    )

    Write-Host $databaseName 
    Write-Host $sqlServerInstance

    $doesTheDatabaseAlreadyExists = Invoke-Sqlcmd -TrustServerCertificate -ServerInstance $sqlServerInstance -Database master -Query "SELECT name FROM sys.databases" | Where-Object { $_.name -ieq $databaseName }

    if ($doesTheDatabaseAlreadyExists) {
        $actionDatabaseExists = gum choose --header "Database ${databaseName} already exists. Do you really want to override it?" "Override" "Rename" "Cancel"  
        
        switch ($actionDatabaseExists) {
            'Rename'  { 
                $databaseName = Rename-Database 
                return Check-IfDatabaseExists -databaseName $databaseName -sqlServerInstance $sqlServerInstance 
            }
            'Cancel'  { Cancel-Restore }
            'Override' { Write-Host "Overriding ${databaseName} " }
        }
    } 

    return $databaseName
}



$bakFilePath = Clean-FilePath(gum input --placeholder "please type .bak file path")

if([System.IO.File]::Exists($bakFilePath) -eq $false) {
    throw "bak file does not exist. please check the path"
}

if((Get-Item $bakFilePath ).Extension -ne ".bak") {
    throw "this is not a .bak file"
}

$sqlServerInstance = gum choose --header "please choose SQL Server instance" "LOCALHOST\SQLEXPRESS" "LOCALHOST" --selected-prefix "LOCALHOST\SQLEXPRESS"
$mdfFilesLocation = Clean-FilePath(gum input --placeholder "please type the path where .mdf and .ldf files will be restored to")

if((Test-Path -Path $mdfFilesLocation) -eq $false) {
    $createDirectory = gum choose --header "directory does not exist. create?" "Yes" "No"
    
    if($createDirectory -eq "Yes") {  
        New-Item -ItemType Directory -Path $mdfFilesLocation 
    } else {
        return "Cancelling"
    }
}

$databaseName = (Invoke-SqlCmd -TrustServerCertificate -ServerInstance $sqlServerInstance -Query "RESTORE HEADERONLY FROM DISK = '$bakFilePath'" ).DatabaseName
$customizeDbName = gum choose --header "do you want to customize database name? default is ${databaseName}" "Keep default" "Customize" --selected-prefix "Keep default"

if($customizeDbName -eq "Customize") {
    $databaseName = Rename-Database
} 

$databaseName = Check-IfDatabaseExists -databaseName $databaseName -sqlServerInstance $sqlServerInstance

$moveBakFileToMdfDirectory = gum choose --header "move bak file to the same location as mdf files?" "Yes" "No"

# Get Logical name first 

$logicalNames = Invoke-Sqlcmd -TrustServerCertificate -ServerInstance $sqlServerInstance -Query "RESTORE FILELISTONLY FROM DISK = N'$bakFilePath'"
$logicalNames = $logicalNames | Where-Object {
    $_.LogicalName -and
    $_.LogicalName.Trim() -ne "" -and
    $_.LogicalName -notmatch "^-+$"
} | Select-Object -ExpandProperty LogicalName

# Extract log file logical names
$logFileLogicalNames = $logicalNames | ForEach-Object {
    $col = $_.ToString().Split(",")[0]
    if ($col -match "(\w*_log\w*\.\w+)") { $matches[1] }
} | Where-Object {
    $_ -and $_.Trim() -ne "" -and $_.Trim() -notmatch "^-+$"
} | Select-Object -Unique


# Extract data file logical names (not containing _log)
$nonLogFileLogicalNames = $logicalNames | ForEach-Object {
    $col = $_.ToString().Split(",")[0]
    if ($col -notmatch "(\w*_log\w*)") { $col }
} | Where-Object { 
    $_ -and $_.Trim() -ne "" -and $_.Trim() -notmatch "^-+$"
} | Select-Object -Unique

# Use the helper to select the logical names
$logFileLogicalName = Select-WithGum -Options $logFileLogicalNames -Prompt "Select the LOG file logical name:"
$mdfFileLogicalName = Select-WithGum -Options $nonLogFileLogicalNames -Prompt "Select the DATA file logical name:"

# Build new paths 
$newLdfFilePath = Join-Path -Path $mdfFilesLocation -ChildPath $logFileLogicalName
$newMdfFilePath = Join-Path -Path $mdfFilesLocation -ChildPath $mdfFileLogicalName

#Write-Host "RESTORE DATABASE ${databaseName} FROM DISK = '${bakFilePath}' WITH RECOVERY, MOVE '${mdfFileLogicalName}' TO '${newMdfFilePath}', MOVE '${logFileLogicalName}' TO '${newLdfFilePath}';"
Write-Host "Restoring ${databaseName} ..." 
Invoke-SqlCmd -TrustServerCertificate -ServerInstance $sqlServerInstance -Query  "RESTORE DATABASE ${databaseName} FROM DISK = '${bakFilePath}' WITH RECOVERY, MOVE '${mdfFileLogicalName}' TO '${newMdfFilePath}', MOVE '${logFileLogicalName}' TO '${newLdfFilePath}';"

if($moveBakFileToMdfDirectory -eq "Yes") {
    $destination = Join-Path -Path $mdfFilesLocation -ChildPath ($databaseName  + ".bak")
    if(Test-Path -Path $destination) {
        return "Item already exist. It has been left at its original location: ${bakFilePath}"
    }
    Move-Item -Path $bakFilePath -Destination $destination
}
