<#
.SYNOPSIS
Generate an SBOM using the dotnet-sbom tool (sbom-tool) with parameterized options.

.DESCRIPTION
`Invoke-Sbom` executes a `dotnet tool run sbom-tool generate` command using the provided paths
and metadata. The function always executes the command and returns the process result.

If the .config/dotnet-tools.json manifest doesn't exist, it will be automatically created with
the Microsoft.Sbom.DotNetTool entry (version 4.1.4).

.PARAMETER BinaryFolder
Path to the build binary folder (maps to -b).

.PARAMETER OutputFolder
Path where the SBOM manifest files will be copied after generation (defaults to BinaryFolder).

.PARAMETER SourcesFolder
Path to the build sources folder (maps to -bc).

.PARAMETER ProjectName
Project name (maps to -pn).

.PARAMETER ProjectVersion
Project version/build number (maps to -pv).

.PARAMETER Publisher
Publisher string (maps to -ps). 

.PARAMETER Namespace
SBOM namespace/base URL (maps to -nsb).

.PARAMETER Verbosity
Log verbosity passed to sbom-tool (maps to -V). Default: Information.

.PARAMETER GenerateMarkdown
Switch to generate a Markdown report from the SBOM manifest.

.EXAMPLE
Invoke-Sbom -BinaryFolder "$env:Build_ArtifactStagingDirectory/buildoutput" \
             -SourcesFolder "$env:Build_SourcesDirectory/src" \
             -ProjectName "MyProj" -ProjectVersion "1.2.3"

.EXAMPLE
# With custom publisher and namespace
Invoke-Sbom -BinaryFolder "c:\build\out" -SourcesFolder "c:\src" -ProjectName "MyProj" -ProjectVersion "1.2.3" -Publisher "MyCompany" -Namespace "https://sbom.mycompany.com"

.EXAMPLE
# Generate Markdown report
Invoke-Sbom -BinaryFolder "$env:Build_ArtifactStagingDirectory/buildoutput" `
            -SourcesFolder "$env:Build_SourcesDirectory/src" `
            -OutputFolder "c:\out\sbom" `
            -ProjectName "MyProj" -ProjectVersion "1.2.3" -GenerateMarkdown
#>
function Invoke-Sbom {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [Alias('BuildArtifactStagingDirectory')]
        [string] $BinaryFolder,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $SourcesFolder,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectName,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $ProjectVersion,

        [Parameter(Mandatory = $false)]
        [string] $Publisher = 'ACME S.r.L.',

        [Parameter(Mandatory = $false)]
        [string] $Namespace = 'https://sbom.acme.com',

        [Parameter(Mandatory = $false)]
        [ValidateSet('Information','Warning','Error','Debug','Verbose')]
        [string] $Verbosity = 'Information',

        [Parameter(Mandatory = $false)]
        [string] $OutputFolder,

        [Parameter(Mandatory = $false)]
        [switch] $GenerateMarkdown
    )

    # Ensure .config directory and dotnet-tools.json exist
    Write-Verbose "Checking for dotnet-tools.json manifest"
    $configDir = "./.config"
    $toolFile = "$configDir/dotnet-tools.json"
    
    if (-not (Test-Path $configDir)) {
        Write-Verbose "Creating .config directory"
        New-Item -ItemType Directory -Path $configDir | Out-Null
    }
    
    if (-not (Test-Path $toolFile)) {
        Write-Verbose "Creating dotnet-tools.json with sbom-tool"
        $manifestContent = @'
{
  "version": 1,
  "isRoot": true,
  "tools": {
    "Microsoft.Sbom.DotNetTool": {
      "version": "4.1.4",
      "commands": [
        "sbom-tool"
      ]
    }
  }
}
'@
        Set-Content -Path $toolFile -Value $manifestContent
    }
    
    # Always restore tools to ensure sbom-tool is available
    Write-Verbose "Restoring dotnet tools"
    & dotnet tool restore
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "dotnet tool restore returned exit code $LASTEXITCODE, but continuing..."
    }

    # Ensure OutputFolder (default to BinaryFolder)
    if ([string]::IsNullOrWhiteSpace($OutputFolder)) { $OutputFolder = $BinaryFolder }
    if (-not (Test-Path $OutputFolder)) {
        Write-Verbose "Creating OutputFolder: $OutputFolder"
        New-Item -Path $OutputFolder -ItemType Directory -Force | Out-Null
    }

    # Remove existing _manifest directory if present
    $manifestDir = Join-Path -Path $BinaryFolder -ChildPath "_manifest"
    if (Test-Path $manifestDir) {
        Write-Verbose "Removing existing _manifest directory: $manifestDir"
        Remove-Item -Path $manifestDir -Recurse -Force
    }

    Write-Verbose "Generating SBOM using sbom-tool..."
    $output = dotnet tool run sbom-tool generate -b "$BinaryFolder" -bc "$SourcesFolder" -pn "$ProjectName" -pv "$ProjectVersion" -ps "$Publisher" -nsb "$Namespace" -V  $Verbosity

    if ($LASTEXITCODE -ne 0) {
        Write-Verbose "sbom-tool output:`n$output"
        Write-Warning "sbom-tool generate returned exit code $LASTEXITCODE"
        exit (0)
    }

    # Copy generated SPDX files (if present) to OutputFolder
    $spdxDir = Join-Path -Path $BinaryFolder -ChildPath "_manifest\spdx_2.2"
    Write-Verbose "Looking for SPDX manifest directory at $spdxDir"
    if (Test-Path $spdxDir) {
        Write-Verbose "Copying SBOM manifest files from $spdxDir to $OutputFolder"
        Get-ChildItem -Path $spdxDir -File | ForEach-Object {
            $dest = Join-Path -Path $OutputFolder -ChildPath $_.Name
            Write-Verbose "Copying $($_.FullName) to $dest"
            Copy-Item -Path $_.FullName -Destination $dest -Force 
            Write-Verbose "Copied $($_.Name) -> $dest"
        }
    }
    else {
        Write-Warning "SPDX manifest directory not found: $spdxDir - probably the tool generated errors $output"
    }

    # Optionally generate markdown from manifest.spdx.json (if requested)
    $manifestJson = Join-Path -Path $OutputFolder -ChildPath "manifest.spdx.json"
    if ($GenerateMarkdown -and (Test-Path $manifestJson)) {
        Write-Verbose "Request to generate markdown from $manifestJson"
        if (Get-Command -Name Convert-SpdxManifestToMarkdown -ErrorAction SilentlyContinue) {
            Convert-SpdxManifestToMarkdown -InputPath $manifestJson
        }
        else {
            Write-Warning "Convert-SpdxManifestToMarkdown not available. Import the module containing it before using -GenerateMarkdown."
        }
    }
}

Export-ModuleMember -Function Invoke-Sbom
