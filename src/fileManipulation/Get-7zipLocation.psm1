
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
    $candidateCommands = @("7z.exe", "7za.exe", "7z", "7za")
    foreach ($candidateCommand in $candidateCommands)
    {
        $existingCommand = Get-Command $candidateCommand -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($null -ne $existingCommand -and -not [string]::IsNullOrWhiteSpace($existingCommand.Source) -and (Test-Path $existingCommand.Source))
        {
            Write-Debug "Using 7zip executable already available on PATH [$($existingCommand.Source)]"
            return $existingCommand.Source
        }
    }

    $commonInstallLocations = @(
        "$env:ProgramFiles\7-Zip\7z.exe",
        "${env:ProgramFiles(x86)}\7-Zip\7z.exe",
        "$env:ChocolateyInstall\bin\7z.exe",
        "$env:ChocolateyInstall\tools\7za.exe"
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($commonInstallLocation in $commonInstallLocations)
    {
        Write-Debug "Testing for 7zip executable [$commonInstallLocation]"
        if (Test-Path $commonInstallLocation)
        {
            return $commonInstallLocation
        }
    }

    $cacheRoot = if (-not [string]::IsNullOrWhiteSpace($env:AGENT_TOOLSDIRECTORY))
    {
        Join-Path $env:AGENT_TOOLSDIRECTORY "BuildUtils"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:LOCALAPPDATA))
    {
        Join-Path $env:LOCALAPPDATA "BuildUtils"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:ProgramData))
    {
        Join-Path $env:ProgramData "BuildUtils"
    }
    else
    {
        Join-Path $env:TEMP "BuildUtils"
    }

    $exeLocation = Join-Path $cacheRoot "tools\7zip"
    $sevenZipExe = Join-Path $exeLocation "7za.exe"
    $sevenZipArchive = Join-Path $cacheRoot "tools\7za920.zip"

    Write-Debug "Testing cached 7zip executable [$sevenZipExe]"
    if (-not (Test-Path $sevenZipExe))
    {
        $parentDirectory = Split-Path $sevenZipArchive -Parent
        if (-not (Test-Path $parentDirectory))
        {
            New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
        }

        Write-Debug "7zip executable not found, downloading https://www.7-zip.org/a/7za920.zip to [$sevenZipArchive]"
        Invoke-WebRequest -Uri "https://www.7-zip.org/a/7za920.zip" -OutFile $sevenZipArchive
        Write-Debug "Unzipping [$sevenZipArchive] to directory [$exeLocation]"
        Expand-WithFramework -zipFile $sevenZipArchive -destinationFolder $exeLocation -quietMode $true 
    }

    return $sevenZipExe 
}
