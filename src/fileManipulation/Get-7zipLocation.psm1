
<#
.SYNOPSIS
Get location of 7za.exe and download if not present

.DESCRIPTION
Get location of 7zip executable (7za). The function first checks
for an already installed executable on PATH or in common Windows
install folders. If it cannot find one it will use a cache folder
to store a downloaded copy and return the executable path.

.EXAMPLE

Suppose that we want to compress $source directory in a file
called $Target

$sevenZipExe = Get-7ZipLocation
set-alias sz $sevenZipExe 

Write-Output "Zipping folder $Source in file $Target"
sz a -mx=9 -r -mmt=on $Target $Source

.PARAMETER ToolsRoot
Optional root folder used to cache the downloaded 7zip package.
If omitted, the function will use BUILDUTILS_7ZIP_TOOLS_DIR when
available, then AGENT_TOOLSDIRECTORY, LOCALAPPDATA, ProgramData,
and finally TEMP.

.PARAMETER SevenZipUrl
Optional URL used to download the 7zip package if no local
installation is found. Defaults to the official 7-Zip URL.

.NOTES

#>
function Get-7ZipLocation(
    [string] $ToolsRoot,
    [string] $SevenZipUrl = "https://www.7-zip.org/a/7za920.zip"
)
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

    $cacheRoot = if (-not [string]::IsNullOrWhiteSpace($ToolsRoot))
    {
        $ToolsRoot
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:BUILDUTILS_7ZIP_TOOLS_DIR))
    {
        $env:BUILDUTILS_7ZIP_TOOLS_DIR
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:AGENT_TOOLSDIRECTORY))
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
    $sevenZipArchiveName = Split-Path $SevenZipUrl -Leaf
    if ([string]::IsNullOrWhiteSpace($sevenZipArchiveName))
    {
        $sevenZipArchiveName = "7za920.zip"
    }
    $sevenZipArchive = Join-Path $cacheRoot ("tools\" + $sevenZipArchiveName)

    Write-Debug "Testing cached 7zip executable [$sevenZipExe]"
    if (-not (Test-Path $sevenZipExe))
    {
        $parentDirectory = Split-Path $sevenZipArchive -Parent
        if (-not (Test-Path $parentDirectory))
        {
            New-Item -ItemType Directory -Path $parentDirectory -Force | Out-Null
        }

        Write-Debug "7zip executable not found, downloading [$SevenZipUrl] to [$sevenZipArchive]"
        Invoke-WebRequest -Uri $SevenZipUrl -OutFile $sevenZipArchive
        Write-Debug "Unzipping [$sevenZipArchive] to directory [$exeLocation]"
        Expand-WithFramework -zipFile $sevenZipArchive -destinationFolder $exeLocation -quietMode $true 
    }

    return $sevenZipExe 
}
