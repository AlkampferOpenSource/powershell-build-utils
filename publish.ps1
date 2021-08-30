# https://evotec.xyz/powershell-single-psm1-file-versus-multi-file-modules/
param (
    [string] $version,
    [string] $preReleaseTag,
    [string] $apiKey
)

$scriptPath = split-path -parent $MyInvocation.MyCommand.Definition
$srcPath = "$scriptPath\src";
Write-Host "Proceeding to publish all code found in $srcPath"

$outFile = "$scriptPath\BuildUtils\BuildUtils.psm1"
if (Test-Path $outFile) 
{
    Remove-Item $outFile
}

if (!(Test-Path "$scriptPath\BuildUtils")) 
{
    New-Item "$scriptPath\BuildUtils" -ItemType Directory
}

$ScriptFunctions = @( Get-ChildItem -Path $srcPath\*.ps1 -ErrorAction SilentlyContinue -Recurse )
$ModulePSM = @( Get-ChildItem -Path $srcPath\*.psm1 -ErrorAction SilentlyContinue -Recurse )
foreach ($FilePath in $ScriptFunctions) {
    Write-Host "Combining file $FilePath"
    $Results = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$null, [ref]$null)
    $Functions = $Results.EndBlock.Extent.Text
    $Functions | Add-Content -Path $outFile
}
foreach ($FilePath in $ModulePSM) {
    $Content = Get-Content $FilePath
    $Content | Add-Content -Path $outFile
}
Write-Output "All functions collapsed in single file $outFile"
"Export-ModuleMember -Function * -Cmdlet *" | Add-Content -Path $outFile

# Now replace version in psd1
$fileContent = Get-Content "$scriptPath\src\BuildUtils.psd1.source"
$fileContent = $fileContent -replace '{{version}}', $version
$fileContent = $fileContent -replace '{{preReleaseTag}}', $preReleaseTag 
Set-Content "$scriptPath\BuildUtils\BuildUtils.psd1" -Value $fileContent  -Force

Write-Output "About to publish module"
Publish-Module `
    -Path $scriptPath\BuildUtils `
    -NuGetApiKey $apiKey `
    -Verbose -Force `
    -ProjectUri "https://github.com/AlkampferOpenSource/powershell-build-utils" `
    -LicenseUri "https://github.com/AlkampferOpenSource/powershell-build-utils/blob/master/LICENSE"