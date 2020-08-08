Write-Host "build utils installed"

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
Execute GitVersion using dotnet core version of the tool

.DESCRIPTION
This command requires that gitversion tool was already configured in 
.config folder of the project in standard dotnet-tools.json file. A simple
content could be

{
  "version": 1,
  "isRoot": true,
  "tools": {
    "gitversion.tool": {
      "version": "5.2.4",
      "commands": [
        "dotnet-gitversion"
      ]
    }
  }
}

.EXAMPLE

$version = Invoke-GitVersion

Write-Host "Assembly version is $($version.assemblyVer)"
Write-Host "File version is $($version.assemblyFileVer)"
Write-Host "Nuget version is $($version.nugetVersion)"
Write-Host "Informational version is $($version.assemblyInformationalVersion)"
#>
function Invoke-Gitversion
{
    Param 
    (
        
    )

    [hashtable]$return = @{}

    Write-Host "restoring tooling for gitversion"
    dotnet tool restore

    Write-Host "Running gitversion to determine version"
    $gitVersionOutput = dotnet tool run dotnet-gitversion /config GitVersion.yml | Out-String
    $version = $gitVersionOutput | Out-String | ConvertFrom-Json
    Write-Host "Raw GitVersion output"
    Write-Host $gitVersionOutput

    Write-Host "Parsed value to be returned"
    $return.assemblyVersion = $version.AssemblySemVer
    $return.assemblyFileVersion = $version.AssemblySemFileVer
    $return.nugetVersion = $version.NuGetVersionV2
    $return.assemblyInformationalVersion = $version.FullSemVer + "." + $version.Sha
    $return.fullSemver = $version.FullSemVer

    Write-Host "Assembly version is $($return.assemblyVersion)"
    Write-Host "File version is $($return.assemblyFileVersion)"
    Write-Host "Nuget version is $($return.nugetVersion)"
    Write-Host "Informational version is $($return.assemblyInformationalVersion)"
    Write-Host "FullSemVer version is $($return.fullSemver)"

    return $return
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

This is a perfect match for Invoke-Getversion function

.PARAMETER SrcPath
Source path

.PARAMETER assemblyVersion
AssemblyVersionAttribute

.PARAMETER fileAssemblyVersion
FileAssemblyVersionAttribute

.PARAMETER assemblyInformationalVersion
AssemblyinformationalVersion

.EXAMPLE

$version = Invoke-GitVersion
Update-SourceVersion -SrcPath PathWithSource -assemblyVersion $version.assemblyVersion -fileAssemblyVersion $version.assemblyFileVersion -assemblyInformationalVersion = $version.assemblyInformationalVersion

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

<#
.SYNOPSIS
Get location of latest msbuild installed on the system

.DESCRIPTION
It requires modules VSSetup installed in the system, you can install
with standard instruction

Install-Module VSSetup -Scope CurrentUser -Force

.EXAMPLE

$msbuildLocation = Get-LatestMsbuildLocation
set-alias msb $msbuildLocation 

msb yoursolution.sln
#>
function Get-LatestMsbuildLocation
{
  Param 
  (
    [bool] $allowPreviewVersions = $false
  )
    if ($allowPreviewVersions) {
      $latestVsInstallationInfo = Get-VSSetupInstance -All -Prerelease | Sort-Object -Property InstallationVersion -Descending | Select-Object -First 1
    } else {
      $latestVsInstallationInfo = Get-VSSetupInstance -All | Sort-Object -Property InstallationVersion -Descending | Select-Object -First 1
    }
    Write-Host "Latest version installed is $($latestVsInstallationInfo.InstallationVersion)"
    if ($latestVsInstallationInfo.InstallationVersion -like "15.*") {
      $msbuildLocation = "$($latestVsInstallationInfo.InstallationPath)\MSBuild\15.0\Bin\msbuild.exe"
    
      Write-Host "Located msbuild for Visual Studio 2017 in $msbuildLocation"
    } else {
      $msbuildLocation = "$($latestVsInstallationInfo.InstallationPath)\MSBuild\Current\Bin\msbuild.exe"
      Write-Host "Located msbuild in $msbuildLocation"
    }

    return $msbuildLocation
}

<#
.SYNOPSIS
Get location of latest nuget in temp folder, if nuget.exe is not found it will download

.DESCRIPTION

.EXAMPLE

$nugetLocation = Get-NugetLocation
set-alias nuget $nugetLocation 

nuget yoursolution.sln
#>
function Get-NugetLocation
{
  Param 
  (
  )
    
    $nugetLocation = "$env:TEMP\nuget.exe"
    if (!(Test-Path -Path $nugetLocation)) {

      Invoke-WebRequest -Uri "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe" -OutFile $nugetLocation
    }

    return $nugetLocation
}

<#
.SYNOPSIS
Get / download nunit test runners and return the folder
with the console runner

.DESCRIPTION

.EXAMPLE

$nunitConsoleRunner = GEt-NunitTestsConsoleRunner
set-alias nunit "$nunitConsoleRunner\nunit3-console-exe"

#>
function Get-NunitTestsConsoleRunner
{
  Param 
  (
  )
    
    $nunitLocation = "$env:TEMP\nunitrunners"
    if (!(Test-Path -Path $nunitLocation)) {

      $nugetLocation = Get-NugetLocation
      set-alias nunitinternal $nugetLocation
      nunitinternal install NUnit.Runners -OutputDirectory $nunitLocation
    }

    #Now we need to locate the console runner
    $consoleRunner = Get-ChildItem -Path $nunitLocation -Name nunit3-console.exe -Recurse 
    Write-Host "Found nunit runner in $nunitLocation\$consoleRunner"
    return "$nunitLocation\$consoleRunner"
}

Export-ModuleMember -Function * -Cmdlet *
  