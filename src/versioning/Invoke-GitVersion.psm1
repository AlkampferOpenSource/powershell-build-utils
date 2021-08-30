
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

Write-Host "Assembly version is $($version.assemblyVersion)"
Write-Host "File version is $($version.assemblyFileVersion)"
Write-Host "Nuget version is $($version.nugetVersion)"
Write-Host "Informational version is $($version.assemblyInformationalVersion)"
#>
function Invoke-Gitversion
{
  Param 
  (
      [string] $ConfigurationFile = "GitVersion.yml"
  )

  $sampleContent = '
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
  }'

  [hashtable]$return = @{}

  Write-Debug "Checking present of dotnet-tools.json file"
  $configFile = "./config/dotnet-tools.json"
  if (-not (Test-Path $configFile))
  {
    Write-Debug "Config file $configFile does not exists will create one"
    New-Item -ItemType Directory -Path "config"
    Set-Content -Path $configFile -Value $sampleContent
  }
  Write-Debug "restoring tooling for gitversion"
  dotnet tool restore | Out-Null

  Write-Debug "Running gitversion to determine version with config file $ConfigurationFile"
  $gitVersionOutput = dotnet tool run dotnet-gitversion /config $ConfigurationFile | Out-String
  Write-Debug "Raw GitVersion output"
  Write-Debug $gitVersionOutput

  $version = $gitVersionOutput | Out-String | ConvertFrom-Json

  Write-Debug "Parsed value to be returned"
  $return.assemblyVersion = $version.AssemblySemVer
  $return.assemblyFileVersion = $version.AssemblySemFileVer
  $return.nugetVersion = $version.NuGetVersionV2
  $return.assemblyInformationalVersion = $version.FullSemVer + "." + $version.Sha
  $return.fullSemver = $version.FullSemVer

  Write-Debug "Assembly version is $($return.assemblyVersion)"
  Write-Debug "File version is $($return.assemblyFileVersion)"
  Write-Debug "Nuget version is $($return.nugetVersion)"
  Write-Debug "Informational version is $($return.assemblyInformationalVersion)"
  Write-Debug "FullSemVer version is $($return.fullSemver)"

  return $return
}
