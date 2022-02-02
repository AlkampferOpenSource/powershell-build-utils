<#
.SYNOPSIS
Check if last command was successful and then print error and take correct action

.DESCRIPTION
It uses $? variable to check if last command was successful and then call
Write-LogError cmdlet to log an error and make CI execution fail if we are im
Ci

.EXAMPLE

dotnet build foo.sln
Assert-LastExecution -message "Failed to foo the bar." -haltExecution $true

.NOTES
if you are in Continuous Integratino script the cmdlet expects
to have variable $ci_engine set to one of the supported value = ["azdo", "github"]

#>
function Assert-LastExecution(
    [string] $message,
    [bool] $haltExecution = $false) 
{
    if ($false -eq $?)
    {
        Write-LogError -Message message -HaltExecution $haltExecution
    }
}