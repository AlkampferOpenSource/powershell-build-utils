<#
.SYNOPSIS
Simply allow for easy XML node manipulation in context of classic .NET xml configuration
files. The purpose is to substitute specific part of the configuration file with 
predetermined tokens.

.DESCRIPTION
Basically takes an XML object and then perform a lookup of a specific part of the XML with
standard XPATH notation and perform a substitution.

.EXAMPLE

$configFile = "somedirecory/web.config"
$xml = [xml](Get-Content $configFile)
Edit-XmlNodes $xml -xpath "/configuration/appSettings/add[@key='apiClientSecret']/@value" -value "__APICLIENTSECRET__"
$xml.save($configFile)

.NOTES

#>
function Edit-XmlNodes {
  param (
      [xml] $doc = $(throw "doc is a required parameter"),
      [string] $xpath = $(throw "xpath is a required parameter"),
      [string] $value = $(throw "value is a required parameter"),
      [bool] $condition = $true
  )    
      if ($condition -eq $true) {
          $nodes = $doc.SelectNodes($xpath)
           
          foreach ($node in $nodes) {
              if ($node -ne $null) {
                  if ($node.NodeType -eq "Element") {
                      $node.InnerXml = $value
                  }
                  else {
                      $node.Value = $value
                  }
              }
          }
      }
  }

<#
.SYNOPSIS
Get location of 7za.exe and download if not present

.DESCRIPTION
Get location of 7zip executable (7za) in temp directory,
if the executable is not present it will download and 
save on disk. It will return the location of 7za executable
that can be in turn used to compress / uncompress files and dir.

.EXAMPLE

Suppose that we want to compress $source directory in a file
called $Target

$sevenZipExe = Get-7ZipLocation
set-alias sz $sevenZipExe 

Write-Output "Zipping folder $Source in file $Target"
sz a -mx=9 -r -mmt=on $Target $Source

.NOTES

#>
function Get-7ZipLocation()
{
    $exeLocation = "$env:TEMP\7z"
    $sevenZipExe = "$exeLocation\7za.exe"
    Write-Debug "Testing for 7zip executable [$sevenZipExe]"
    if (-not (test-path $sevenZipExe)) 
    {
        Write-Debug "7zip executable [$sevenZipExe] not present, download from http://www.7-zip.org/a/7za920.zip to $env:TEMP\7zip.zip"
        Invoke-WebRequest -Uri "http://www.7-zip.org/a/7za920.zip" -OutFile "$env:TEMP\7zip.zip"
        Write-Debug "Unzipping $env:TEMP\7zip.zip to directory $exeLocation"
        Expand-WithFramework -zipFile "$env:TEMP\7zip.zip" -destinationFolder "$exeLocation" -quietMode $true 
        $sevenZipExe = "$exeLocation\7za.exe"
    } 
    return $sevenZipExe 
}

<#
.SYNOPSIS
Unzip a zip file using standard .NET framework classes.

.PARAMETER zipFile
Path of zip file

.PARAMETER destinationFolder
Destination folder where to uncompress files

.PARAMETER deleteOld
If $true the routine will delete original file.

.PARAMETER quietMode
if $true it will output less information on output stream
#>
function Expand-WithFramework(
    [string] $zipFile,
    [string] $destinationFolder,
    [bool] $deleteOld = $false,
    [bool] $quietMode = $false
)
{
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ((Test-Path $destinationFolder) -and $deleteOld)
    {
          Remove-Item $destinationFolder -Recurse -Force
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $destinationFolder)
}

<#
.SYNOPSIS
Manipulate all assemblyinfo.vb and assemblyinfo.cs to change version 

.DESCRIPTION
With legacy .NET project versioning is done with specific attribtues
inside assemblyinfo.cs and assemblyinfo.vb files. This cmdlet
can scan all files and perform a substitution.

This should be done before compiling (and usually after version is 
determined with tools like gitversion)

.PARAMETER SrcPath
Source path

.PARAMETER assemblyVersion
AssemblyVersionAttribute

.PARAMETER fileAssemblyVersion
FileAssemblyVersionAttribute

.PARAMETER assemblyInformationalVersion
AssemblyinformationalVersion

#>
function Update-SourceVersion
{
  Param 
  (
    [string]$SrcPath,
    [string]$assemblyVersion, 
    [string]$fileAssemblyVersion,
    [string]$assemblyInformationalVersion,
    [bool]$modifyAssemblyVersion = $true
  )
    
    if ($fileAssemblyVersion -eq "")
    {
        $fileAssemblyVersion = $assemblyVersion
    }

        
    if ($assemblyInformationalVersion -eq "")
    {
        $assemblyInformationalVersion = $fileAssemblyVersion
    }
    
    Write-Host "Executing Update-SourceVersion in path $SrcPath, Version is $assemblyVersion and File Version is $fileAssemblyVersion and Informational Version is $assemblyInformationalVersion"
        
    $AllVersionFiles = Get-ChildItem $SrcPath\* -Include AssemblyInfo.cs,AssemblyInfo.vb -recurse
  
    foreach ($file in $AllVersionFiles)
    { 
        Write-Host "Modifying file " + $file.FullName
        #save the file for restore
        $backFile = $file.FullName + "._ORI"

        Copy-Item $file.FullName $backFile -Force
        #now load all content of the original file and rewrite modified to the same file
        $content = Get-Content $file.FullName 
        Remove-Item $file.FullName
        if ($modifyAssemblyVersion) 
        {
          $content |
            %{$_ -replace 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', "AssemblyVersion(""$assemblyVersion"")" } |
            %{$_ -replace 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', "AssemblyFileVersion(""$fileAssemblyVersion"")" } |
            %{$_ -replace 'AssemblyInformationalVersion\(".*"\)', "AssemblyInformationalVersion(""$assemblyInformationalVersion"")" } |
            Set-Content -Encoding UTF8 -Path $file.FullName -Force
        }
        else {
          $content |
            %{$_ -replace 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', "AssemblyFileVersion(""$fileAssemblyVersion"")" } |
            %{$_ -replace 'AssemblyInformationalVersion\(".*"\)', "AssemblyInformationalVersion(""$assemblyInformationalVersion"")" } |
            Set-Content -Encoding UTF8 -Path $file.FullName -Force
        }

    }
}
  