<#
.SYNOPSIS
Convert an SPDX manifest JSON (manifest.spdx.json) to a concise Markdown report.

.DESCRIPTION
Parses the SPDX JSON produced by sbom-tool and generates a readable Markdown document
containing document metadata, basic statistics and a per-package summary.
The original JSON is copied to the same output folder for traceability.

.PARAMETER InputPath
Path to the manifest.spdx.json file to convert.

.PARAMETER EnrichMetadata
Switch to enable metadata enrichment from NuGet API for NuGet packages.

.EXAMPLE
Convert-ManifestSpdxJsonToMarkdown -InputPath ".\manifest.spdx.json"

.EXAMPLE
Convert-ManifestSpdxJsonToMarkdown -InputPath ".\manifest.spdx.json" -EnrichMetadata

.NOTES
Keep this function lightweight; enrichment/vulnerability scans are out-of-scope for initial implementation.
#>
function Convert-ManifestSpdxJsonToMarkdown {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $InputPath,

        [Parameter(Mandatory = $false)]
        [switch] $EnrichMetadata
    )

    # $OutputPath is the same directory as InputPath, with .md extension
    $outDir = Split-Path -Path $InputPath -Parent
    $outFileName = [System.IO.Path]::GetFileNameWithoutExtension($InputPath) + ".md"
    $OutputPath = Join-Path -Path $outDir -ChildPath $outFileName

    try {
        if (-not (Test-Path $InputPath)) {
            Throw "Input SPDX JSON not found: $InputPath"
        }

        Write-Verbose "Reading SPDX JSON: $InputPath"
        $jsonText = Get-Content -Path $InputPath -Raw -ErrorAction Stop
        $sbom = $jsonText | ConvertFrom-Json -ErrorAction Stop
        
        # Enrich SBOM with NuGet metadata if requested
        if ($EnrichMetadata) {
            Write-Verbose "Enriching SBOM with NuGet metadata..."

            # Initialize vulnerability statistics for this run (no cache across runs)
            if (-not $script:vulnerabilityStats) {
                $script:vulnerabilityStats = @{
                    Checked = 0
                    Vulnerable = 0
                    Safe = 0
                    Failed = 0
                }
            }

            # dump all the license info and check vulnerabilities (no cache)
            Enrich-SbomWithNuGetMetadata -Sbom ([ref]$sbom)
            Write-Verbose "Enrichment complete."
        }

        $md = @()
        # Header
        $md += "# Software Bill of Materials (SBOM)"
        $md += ""
        $md += "---"
        $md += ""

        # Document information
        $md += "## Document Information"
        $md += ""
        if ($sbom.name) { $md += "| **Name** | $($sbom.name) |" }
        if ($sbom.spdxVersion) { $md += "| **SPDX Version** | $($sbom.spdxVersion) |" }
        if ($sbom.dataLicense) { $md += "| **Data License** | $($sbom.dataLicense) |" }
        if ($sbom.SPDXID) { $md += "| **SPDX ID** | $($sbom.SPDXID) |" }
        if ($sbom.documentNamespace) { $md += "| **Document Namespace** | $($sbom.documentNamespace) |" }
        $md += ""

        # Creation info
        if ($sbom.creationInfo) {
            $md += "## Creation Information"
            $md += ""
            if ($sbom.creationInfo.created) { $md += "| **Created** | $($sbom.creationInfo.created) |" }
            if ($sbom.creationInfo.creators) {
                foreach ($c in $sbom.creationInfo.creators) { $md += "| **Creator** | $c |" }
            }
            $md += ""
        }

        # Statistics
        $pkgCount = 0
        $relCount = 0
        if ($sbom.packages) { $pkgCount = $sbom.packages.Count }
        if ($sbom.relationships) { $relCount = $sbom.relationships.Count }

        $md += "## Statistics"
        $md += ""
        $md += "| Metric | Count |"
        $md += "|--------|-------|"
        $md += "| **Total Packages** | $pkgCount |"
        $md += "| **Total Relationships** | $relCount |"
        $md += ""

        # If enrichment/vulnerability scanning was enabled, show scan statistics
        if ($script:vulnerabilityStats -and $script:vulnerabilityStats.Checked -gt 0) {
            $md += "| **NuGet Packages Scanned** | $($script:vulnerabilityStats.Checked) |"
            $md += "| **Vulnerable Packages** | $($script:vulnerabilityStats.Vulnerable) |"
            $md += "| **Safe Packages** | $($script:vulnerabilityStats.Safe) |"
            $md += "| **Scan Failures** | $($script:vulnerabilityStats.Failed) |"
            $md += ""
        }
        
        # Add enrichment notice if enabled
        if ($EnrichMetadata) {
            $md += "> **Note**: NuGet package metadata has been enriched from nuget.org"
            $md += ""
        }

        # Group packages by type
        $packagesByType = @{}
        if ($sbom.packages) {
            foreach ($p in $sbom.packages) {
                $type = "Other"
                if ($p.externalRefs) {
                    foreach ($ref in $p.externalRefs) {
                        if ($ref.referenceType -eq "purl" -and $ref.referenceLocator -match "^pkg:([^/]+)/") {
                            $type = $matches[1].ToUpper()
                            break
                        }
                    }
                }
                if (-not $packagesByType.ContainsKey($type)) {
                    $packagesByType[$type] = @()
                }
                $packagesByType[$type] += $p
            }
        }

        # Packages summary
        if ($pkgCount -eq 0) {
            $md += "## Packages"
            $md += ""
            $md += "_No packages found in SPDX manifest_"
            $md += ""
        } else {
            $sortedTypes = $packagesByType.Keys | Sort-Object
            foreach ($type in $sortedTypes) {
                $md += "## $type Packages"
                $md += ""
                
                foreach ($p in $packagesByType[$type]) {

                    $name = if ($p.name) { $p.name } else { ($p.SPDXID -replace '^SPDXRef-Package-','') }
                    $version = if ($p.versionInfo) { $p.versionInfo } else { "-" }
                    $spdxId = if ($p.SPDXID) { $p.SPDXID } else { "-" }
                    $license = if ($p.licenseConcluded -and $p.licenseConcluded -ne "NOASSERTION") { $p.licenseConcluded }
                               elseif ($p.licenseDeclared -and $p.licenseDeclared -ne "NOASSERTION") { $p.licenseDeclared }
                               else { "Not available" }
                    $supplier = if ($p.supplier -and $p.supplier -ne "NOASSERTION") { $p.supplier } else { "-" }
                    $download = if ($p.downloadLocation -and $p.downloadLocation -ne "NOASSERTION") { $p.downloadLocation } else { "" }

                    $md += "### $name v$version"
                    $md += ""
                    $md += "| Property | Value |"
                    $md += "|----------|-------|"
                    $md += "| **SPDX ID** | ``$spdxId`` |"
                    $md += "| **Version** | $version |"
                    $md += "| **License** | $license |"
                    $md += "| **Supplier** | $supplier |"
                    
                    # add download location if available
                    if ($p.downloadLocation) {
                        $md += "| **Download Location** | $download |"
                    }

                    # Add enriched fields if available
                    if ($p.projectUrl) {
                        $md += "| **Project URL** | $($p.projectUrl) |"
                    }

                    # Render vulnerability summary if available
                    if ($p.Vulnerable -ne $null) {
                        $vulnText = if ($p.Vulnerable) { 'Yes' } else { 'No' }
                        $md += "| **Vulnerable** | $vulnText |"

                        if ($p.Vulnerabilities -and $p.Vulnerabilities.Count -gt 0) {
                            $md += "| **Vulnerabilities** | $($p.Vulnerabilities.Count) |"
                            $md += ""
                            $md += "#### Vulnerabilities"
                            $md += ""
                            foreach ($v in $p.Vulnerabilities) {
                                $id = if ($v.Id) { $v.Id } elseif ($v.id) { $v.id } else { '' }
                                $summary = if ($v.Summary) { $v.Summary } elseif ($v.summary) { $v.summary } else { '' }
                                $md += "- **$id**: $summary"
                            }
                        }
                    }

                    # if ($p.description) {
                    #     $md += "| **Description** | $($p.description) |"
                    # }
                    # if ($p.copyrightText -and $p.copyrightText -ne "NOASSERTION") {
                    #     $md += "| **Copyright** | $($p.copyrightText) |"
                    # }
                    
                    $md += ""
                }
            }
        }

        # Footer
        $md += "---"
        $md += ""
        $md += "*Generated from SPDX SBOM file*"
        if ($EnrichMetadata) {
            $md += ""
            $md += "*NuGet packages enriched with metadata from nuget.org*"
        }
        $md += ""

        # Write markdown file (UTF8 no BOM)
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($OutputPath, ($md -join "`n"), $utf8NoBom)
        Write-Verbose "Markdown written to $OutputPath"

        Write-Verbose "Conversion complete: $OutputPath"
        return $OutputPath
    }
    catch {
        Write-Error "Failed to convert SPDX manifest: $_"
        throw
    }
}

<#
.SYNOPSIS
Get detailed package information from NuGet API.

.DESCRIPTION
Queries the NuGet API to retrieve package metadata including license, author, description, etc.

.PARAMETER PackageName
The NuGet package name.

.PARAMETER Version
The package version.

.NOTES
Internal helper function for enriching SBOM data.
#>
function Get-NuGetPackageMetadata {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [string] $PackageName,

        [Parameter(Mandatory = $true)]
        [string] $Version
    )

    try {
        Write-Verbose "Querying NuGet for: $PackageName@$Version"
        
        # Get .nuspec file from NuGet
        $nuspecUrl = "https://api.nuget.org/v3-flatcontainer/$($PackageName.ToLower())/$Version/$($PackageName.ToLower()).nuspec"
        $nuspecXml = Invoke-RestMethod -Uri $nuspecUrl -Method Get -TimeoutSec 10 -ErrorAction Stop
        
        Write-Verbose $nuspecUrl
        # Parse XML
        [xml]$xml = $nuspecXml
        $metadata = $xml.package.metadata
        
        $enrichedData = @{
            License = $null
            LicenseUrl = $metadata.licenseUrl
            Authors = $metadata.authors
            Owners = $metadata.owners
            ProjectUrl = $metadata.projectUrl
            Description = $metadata.description
            Copyright = $metadata.copyright
            Tags = $metadata.tags
        }
        
        # Handle license information
        if ($metadata.license) {
            # SPDX license expression or license file
            if ($metadata.license.type -eq "expression") {
                $enrichedData.License = $metadata.license.'#text'
            }
            elseif ($metadata.license.type -eq "file") {
                $enrichedData.License = "See package: $($metadata.license.'#text')"
            }
            else {
                $enrichedData.License = $metadata.license.'#text'
            }
        }
        elseif ($enrichedData.LicenseUrl) {
            # Extract license from common URLs
            if ($enrichedData.LicenseUrl -match "MIT") { 
                $enrichedData.License = "MIT" 
            }
            elseif ($enrichedData.LicenseUrl -match "Apache-2\.0|apache\.org/licenses/LICENSE-2\.0") { 
                $enrichedData.License = "Apache-2.0" 
            }
            elseif ($enrichedData.LicenseUrl -match "GPL-3\.0") { 
                $enrichedData.License = "GPL-3.0" 
            }
            elseif ($enrichedData.LicenseUrl -match "GPL-2\.0") { 
                $enrichedData.License = "GPL-2.0" 
            }
            elseif ($enrichedData.LicenseUrl -match "BSD-3-Clause") { 
                $enrichedData.License = "BSD-3-Clause" 
            }
            elseif ($enrichedData.LicenseUrl -match "BSD-2-Clause") { 
                $enrichedData.License = "BSD-2-Clause" 
            }
            elseif ($enrichedData.LicenseUrl -match "BSD") { 
                $enrichedData.License = "BSD" 
            }
            elseif ($enrichedData.LicenseUrl -match "MS-PL") { 
                $enrichedData.License = "MS-PL" 
            }
            else { 
                $enrichedData.License = $enrichedData.LicenseUrl 
            }
        }
        
        Write-Verbose "Successfully retrieved metadata for $PackageName@$Version"
        Write-Verbose "License: $($enrichedData.License)"
        write-Verbose "Authors: $($enrichedData.Authors)"
        return $enrichedData
    }
    catch {
        Write-Verbose "Failed to retrieve NuGet metadata for ${PackageName}@${Version}: $_"
        return $null
    }
}

<#
.SYNOPSIS
Enrich SBOM packages with NuGet metadata.

.DESCRIPTION
Identifies NuGet packages in the SBOM and enriches them with metadata from NuGet API.
Modifies the SBOM object in-place.

.PARAMETER Sbom
The SBOM object to enrich (passed by reference).

.NOTES
Internal helper function.
#>
function Enrich-SbomWithNuGetMetadata {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ref] $Sbom
    )

    if (-not $Sbom.Value.packages) {
        Write-Verbose "No packages found in SBOM"
        return
    }

    $nugetPackages = @()
    
    # Identify NuGet packages
    foreach ($package in $Sbom.Value.packages) {
        $isNuGet = $false
        
        if ($package.externalRefs) {
            foreach ($ref in $package.externalRefs) {
                if ($ref.referenceType -eq "purl" -and $ref.referenceLocator -match "^pkg:nuget/") {
                    $isNuGet = $true
                    break
                }
            }
        }
        
        if ($isNuGet) {
            $nugetPackages += $package
        }
    }
    
    if ($nugetPackages.Count -eq 0) {
        Write-Verbose "No NuGet packages found in SBOM"
        return
    }
    
    Write-Verbose "Found $($nugetPackages.Count) NuGet package(s) to enrich"
    
    $enriched = 0
    $failed = 0
    
    foreach ($package in $nugetPackages) {
        Write-Verbose "Enriching: $($package.name) v$($package.versionInfo)"
        
        $metadata = Get-NuGetPackageMetadata -PackageName $package.name -Version $package.versionInfo

        # Check vulnerabilities (no cache)
        try {
            $vulnResult = Get-NuGetVulnerabilities -PackageName $package.name -Version $package.versionInfo
        }
        catch {
            $vulnResult = $null
        }

        if ($vulnResult) {
            if ($vulnResult.HasVulnerabilities) {
                
                $package | Add-Member -NotePropertyName 'Vulnerable' -NotePropertyValue $true -Force
                $package | Add-Member -NotePropertyName 'Vulnerabilities' -NotePropertyValue $vulnResult.Vulnerabilities -Force
            }
            else {
                $package | Add-Member -NotePropertyName 'Vulnerable' -NotePropertyValue $false -Force
                $package | Add-Member -NotePropertyName 'Vulnerabilities' -NotePropertyValue @() -Force
            }
        }
        else {
            # If we couldn't determine vulnerabilities, add properties with default empty values
            $package | Add-Member -NotePropertyName 'Vulnerable' -NotePropertyValue $null -Force
            $package | Add-Member -NotePropertyName 'Vulnerabilities' -NotePropertyValue @() -Force
        }
        
        if ($metadata) {
            # Update license information
            if ($metadata.License) {
                $package.licenseConcluded = $metadata.License
                $package.licenseDeclared = $metadata.License
            }
            
            # Update supplier (use authors or owners)
            if ($metadata.Authors) {
                $package.supplier = "Organization: $($metadata.Authors)"
            }
            elseif ($metadata.Owners) {
                $package.supplier = "Organization: $($metadata.Owners)"
            }
            
            # Update copyright
            if ($metadata.Copyright) {
                $package.copyrightText = $metadata.Copyright
            }
            
            # Update download location if project URL exists
            if ($metadata.ProjectUrl) {
                # Keep original download location but add as comment
                $package | Add-Member -NotePropertyName "projectUrl" -NotePropertyValue $metadata.ProjectUrl -Force
            }
            
            # Add description as comment
            if ($metadata.Description) {
                $package | Add-Member -NotePropertyName "description" -NotePropertyValue $metadata.Description -Force
            }
            
            $enriched++
        }
        else {
            $failed++
        }
    }
    
    Write-Verbose "Enrichment complete: $enriched succeeded, $failed failed"
}

<#
.SYNOPSIS
Convert an SPDX manifest JSON to Markdown report (wrapper function).

.DESCRIPTION
Wrapper for Convert-ManifestSpdxJsonToMarkdown using standard PowerShell verb-noun naming.

.PARAMETER InputPath
Path to the manifest.spdx.json file.


.PARAMETER EnrichMetadata
Reserved for future metadata enrichment.


.EXAMPLE
Convert-SpdxManifestToMarkdown -InputPath ".\manifest.spdx.json" 
#>
function Convert-SpdxManifestToMarkdown {
    [CmdletBinding()]
    Param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string] $InputPath,

        [Parameter(Mandatory = $false)]
        [switch] $EnrichMetadata
    )

    return Convert-ManifestSpdxJsonToMarkdown -InputPath $InputPath -EnrichMetadata:$EnrichMetadata
}

Export-ModuleMember -Function Convert-ManifestSpdxJsonToMarkdown, Convert-SpdxManifestToMarkdown
