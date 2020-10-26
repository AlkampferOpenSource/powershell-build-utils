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