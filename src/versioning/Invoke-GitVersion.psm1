<#
.SYNOPSIS
It contains all the data needed to work with gitversion as well as a success
property that returns to the caller if the invocation of GitVersion succeeded
or failed.
#>
class GitVersion 
{
  [bool] $Success
  [string]$AssemblyVersion
  [string]$AssemblyFileVersion
  [string]$NugetVersion
  [string]$AssemblyInformationalVersion
  [string]$FullSemver
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

.PARAMETER ConfigurationFile
Location of GitVersion.yml file, you can specify full path to the file

.EXAMPLE

$version = Invoke-GitVersion

if ($version.Success) #You can check for success of operation.

Write-Host "Assembly version is $($version.AssemblyVersion)"
Write-Host "File version is $($version.AssemblyFileVersion)"
Write-Host "Nuget version is $($version.NugetVersion)"
Write-Host "Informational version is $($version.AssemblyInformationalVersion)"
#>
function Invoke-Gitversion
{
  [OutputType([GitVersion])]
  Param 
  (
      [string] $ConfigurationFile = "GitVersion.yml"
  )

  Write-Information -MessageData "Running Invoke-Gitversion to determine version numbers for current repository."

  $sampleContent = '{
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

  $sampleGitVersion = 'branches: {}
ignore:
  sha: []
merge-message-formats: {}
mode: ContinuousDeployment'

  $retvalue = [GitVersion]::new()

  Write-Verbose "Checking present of dotnet-tools.json file"
  $toolFile = "./.config/dotnet-tools.json"
  $configFile = "./.config/GitVersion.yml"
  if (-not (Test-Path "./.config"))
  {
    New-Item -ItemType Directory -Path ".config"
  }
  if (-not (Test-Path $toolFile))
  {
    Write-Debug "Config file $toolFile does not exists will create one"
    Set-Content -Path $toolFile -Value $sampleContent
  }
  if (-not (Test-Path $configFile))
  {
    Write-Debug "Config file $configFile does not exists will create one"
    Set-Content -Path $configFile -Value $sampleGitVersion
  }

  Write-Verbose "restoring tooling for gitversion"
  dotnet tool restore | Out-Null

  if ($false -eq $?) 
  {
    Write-Error "Unable to run dotnet tool restore, execution of the command failed"
    $retvalue.Success = $false
    return $retvalue
  }

  Write-Verbose "Running gitversion to determine version with config file $ConfigurationFile"
  $gitVersionOutput = dotnet tool run dotnet-gitversion /config $ConfigurationFile | Out-String
  if ($false -eq $?) 
  {
    Write-Error "Unable to run dotnet tool run dotnet-gitversion, execution of the command failed: $gitVersionOutput"
    $retvalue.Success = $false
    return $retvalue
  }

  Write-Verbose "Raw GitVersion output"
  Write-Verbose $gitVersionOutput

  $version = $gitVersionOutput | Out-String | ConvertFrom-Json

  Write-Verbose "Parsed value to be returned"
  $retvalue.Success = $true
  $retvalue.AssemblyVersion = $version.AssemblySemVer
  $retvalue.AssemblyFileVersion = $version.AssemblySemFileVer
  $retvalue.NuGetVersion = $version.NuGetVersionV2
  $retvalue.AssemblyInformationalVersion = $version.FullSemVer + "." + $version.Sha
  $retvalue.FullSemVer = $version.FullSemVer

  Write-Verbose "Assembly version is $($retvalue.AssemblyVersion)"
  Write-Verbose "File version is $($retvalue.AssemblyFileVersion)"
  Write-Verbose "Nuget version is $($retvalue.NuGetVersionV2)"
  Write-Verbose "Informational version is $($retvalue.AssemblyInformationalVersion)"
  Write-Verbose "FullSemVer version is $($retvalue.FullSemVer)"

  return $retvalue
}
