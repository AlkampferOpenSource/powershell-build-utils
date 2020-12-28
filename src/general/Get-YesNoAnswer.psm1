<#
.SYNOPSIS
Allow for asking a simple yes/no question

.DESCRIPTION
Given a question this function ask for a yes/no response
it handles default value, casing and accepts both y n short answer
or long yes no version

.EXAMPLE

Get-YesNoAnswer -question "Do you want to do this?" -default $true

.NOTES

#>
function Get-YesNoAnswer(
    [string] $question,
    [System.Nullable[bool]] $default = $null) 
{
  $yesValues = "y", "yes";
  $noValues = "n", "no";
  do 
  {
    $realQuestion = $question.TrimEnd(":");
    if ($default -eq $true) 
    {
      $realQuestion += ": (Y/n)" 
    }
    elseif ($default -eq $true) 
    {
      $realQuestion += ": (y/N)" 
    }
    else 
    {
      $realQuestion += ": (y/n)" 
    }
    Write-Host $realQuestion -NoNewline
    $answer = Read-Host
    if ($answer -eq '' -and $default -ne $null) 
    {
        return $default
    }
    $answer = $answer.ToLower()
  } while (!$yesValues.Contains($answer) -and !$noValues.Contains($answer))

  return $yesValues.Contains($answer);
}

