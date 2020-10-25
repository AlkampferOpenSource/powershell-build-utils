
<#
.SYNOPSIS
Unzip a zip file using standard .NET framework classes.

.PARAMETER zipFile
Path of zip file

.PARAMETER destinationFolder
Destination folder where to uncompress files

.PARAMETER deleteOld
If $true the routine will delete original file.

.PARAMETER quietMode
if $true it will output less information on output stream
#>
function Expand-WithFramework(
    [string] $zipFile,
    [string] $destinationFolder,
    [bool] $deleteOld = $false,
    [bool] $quietMode = $false
)
{
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    if ((Test-Path $destinationFolder) -and $deleteOld)
    {
          Remove-Item $destinationFolder -Recurse -Force
    }
    [System.IO.Compression.ZipFile]::ExtractToDirectory($zipfile, $destinationFolder)
}