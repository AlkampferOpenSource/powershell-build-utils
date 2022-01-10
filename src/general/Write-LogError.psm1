<#
.SYNOPSIS
Write a log error CI enabled

.DESCRIPTION
Simply write a log error to the console and write also a special
command for continous integration engine to have the script signal
an error in the step. Remember to set $ci_engine to the correct value
for your CI engine

.EXAMPLE

Write-LogError -message "Failed to foo the bar." -$haltExecution $true

.NOTES
$ci_engine valid values are ["azdo", "github"]

#>
function Write-LogError(
    [string] $message,
    [bool] $haltExecution = $false) 
{
    # Trying to detect if we are running inside a CI engine, to try to emit correct error message
    if ("azdo" -eq $ci_engine)
    {
        Write-Host "##vso[task.logissue type=error]$message"
    }
    elseif ("github" -eq $ci_engine)
    {
        Write-Host "::error::$message"
    }
    
    # Write with Write-error always.
    Write-Host $message -ForegroundColor Red

    if ($true -eq $haltExecution)
    {
        Write-Host "Request script exit!!!!!"
        exit (1)
    }
}