
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

.PARAMETER ConfigurationFile
Location of GitVersion.yml file, you can specify full path to the file

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
        [string] $ConfigurationFile = "GitVersion.yml"
    )

    [hashtable]$return = @{}

    Write-Host "restoring tooling for gitversion"
    dotnet tool restore

    Write-Host "Running gitversion to determine version with config file $ConfigurationFile"
    $gitVersionOutput = dotnet tool run dotnet-gitversion /config $ConfigurationFile | Out-String
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
