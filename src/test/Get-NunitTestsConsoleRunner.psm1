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
    $consoleRunner = ""
    if (Test-Path -Path $nunitLocation) {
      $consoleRunner = Get-ChildItem -Path $nunitLocation -Name nunit3-console.exe -Recurse 
      if ($consoleRunner -eq $null) 
      {
        Write-Debug "no runner found in folder $nunitLocation"
        Remove-Item $nunitLocation -Recurse
      }
    }

    if (!(Test-Path -Path $nunitLocation)) {
      $nugetLocation = Get-NugetLocation
      set-alias nugetinternal $nugetLocation
      nugetinternal install NUnit.Runners -OutputDirectory $nunitLocation | Out-Null
    }

    #Now we need to locate the console runner
    $consoleRunner = Get-ChildItem -Path $nunitLocation -Name nunit3-console.exe -Recurse 
    Write-Debug "Found nunit runner in $nunitLocation\$consoleRunner"
    return "$nunitLocation\$consoleRunner"
}