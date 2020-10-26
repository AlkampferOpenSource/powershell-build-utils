
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
    $exeLocation = "$env:TEMP\7z"
    $sevenZipExe = "$exeLocation\7za.exe"
    Write-Debug "Testing for 7zip executable [$sevenZipExe]"
    if (-not (test-path $sevenZipExe)) 
    {
        Write-Debug "7zip executable [$sevenZipExe] not present, download from http://www.7-zip.org/a/7za920.zip to $env:TEMP\7zip.zip"
        Invoke-WebRequest -Uri "http://www.7-zip.org/a/7za920.zip" -OutFile "$env:TEMP\7zip.zip"
        Write-Debug "Unzipping $env:TEMP\7zip.zip to directory $exeLocation"
        Expand-WithFramework -zipFile "$env:TEMP\7zip.zip" -destinationFolder "$exeLocation" -quietMode $true 
        $sevenZipExe = "$exeLocation\7za.exe"
    } 
    return $sevenZipExe 
}