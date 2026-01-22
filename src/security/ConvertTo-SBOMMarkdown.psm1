<#
.SYNOPSIS
Convert SBOM data to formatted Markdown documentation

.DESCRIPTION
Provides functions to transform SPDX SBOM JSON data into human-readable Markdown format.
Supports package tables, vulnerability alerts, enrichment data display, and statistics summaries.

.EXAMPLE
$markdown = ConvertTo-PackageMarkdown -Package $pkg -EnrichedData $info -VulnerabilityData $vulns

.EXAMPLE
$fullMarkdown = ConvertTo-SBOMDocument -SBOM $sbomData -VulnerablePackages $vulnList

.NOTES
Designed to work with SPDX 2.2+ format SBOM documents.
Integrates with enrichment and vulnerability modules for complete reporting.
#>

function ConvertTo-PackageMarkdown {
    <#
    .SYNOPSIS
    Generate markdown for a single package entry
    
    .DESCRIPTION
    Creates formatted markdown table rows for package metadata including SBOM fields,
    enriched data from registries, and vulnerability alerts.
    
    .PARAMETER Package
    PSCustomObject from SBOM packages array
    
    .PARAMETER EnrichedData
    Hashtable from Get-PackageInfo (optional)
    
    .PARAMETER VulnerabilityData
    Hashtable from vulnerability scan functions (optional)
    
    .OUTPUTS
    Array of strings representing markdown lines
    
    .EXAMPLE
    $lines = ConvertTo-PackageMarkdown -Package $package
    $markdown = $lines -join "`n"
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Package,
        
        [Parameter(Mandatory=$false)]
        [hashtable] $EnrichedData,
        
        [Parameter(Mandatory=$false)]
        [hashtable] $VulnerabilityData
    )
    
    $lines = @()
    
    # Package header
    $packageName = $Package.name
    $packageVersion = $Package.versionInfo
    $lines += "### $packageName v$packageVersion"
    $lines += ""
    
    # Vulnerability warning
    if ($VulnerabilityData -and $VulnerabilityData.HasVulnerabilities) {
        $vulnCount = $VulnerabilityData.Vulnerabilities.Count
        
        # Find highest severity
        $severityValues = @{ "CRITICAL" = 0; "HIGH" = 1; "MODERATE" = 2; "MEDIUM" = 2; "LOW" = 3 }
        $highestSev = "UNKNOWN"
        $highestVal = 999
        
        foreach ($vuln in $VulnerabilityData.Vulnerabilities) {
            $sevUpper = $vuln.Severity.ToUpper()
            $val = $severityValues[$sevUpper]
            if ($null -eq $val) { $val = 4 }
            if ($val -lt $highestVal) {
                $highestVal = $val
                $highestSev = $sevUpper
            }
        }
        
        $vulnText = if ($vulnCount -gt 1) { "vulnerabilities" } else { "vulnerability" }
        $lines += "> **[!] SECURITY ALERT**: $vulnCount known $vulnText - Highest severity: **$highestSev**"
        $lines += ""
    }
    
    # Table header
    $lines += "| Property | Value |"
    $lines += "|----------|-------|"
    
    # SPDX ID
    $spdxId = $Package.SPDXID
    $lines += "| **SPDX ID** | ``$spdxId`` |"
    
    # Version
    $lines += "| **Version** | $packageVersion |"
    
    # License
    if ($EnrichedData -and $EnrichedData.License) {
        $license = $EnrichedData.License
        $lines += "| **License** | [E] $license |"
    }
    elseif ($Package.licenseConcluded -ne "NOASSERTION") {
        $license = $Package.licenseConcluded
        $lines += "| **License Concluded** | $license |"
    }
    elseif ($Package.licenseDeclared -ne "NOASSERTION") {
        $license = $Package.licenseDeclared
        $lines += "| **License Declared** | $license |"
    }
    else {
        $lines += "| **License** | [!] Not Available |"
    }
    
    # Author/Supplier
    if ($EnrichedData -and $EnrichedData.Author) {
        $author = $EnrichedData.Author
        $lines += "| **Author** | [E] $author |"
    }
    elseif ($Package.supplier -ne "NOASSERTION") {
        $supplier = $Package.supplier
        $lines += "| **Supplier** | $supplier |"
    }
    
    # Copyright
    if ($EnrichedData -and $EnrichedData.Copyright) {
        $copyright = $EnrichedData.Copyright
        $lines += "| **Copyright** | [E] $copyright |"
    }
    elseif ($Package.copyrightText -ne "NOASSERTION") {
        $copyright = $Package.copyrightText
        $lines += "| **Copyright** | $copyright |"
    }
    
    # Additional enriched fields
    if ($EnrichedData) {
        if ($EnrichedData.ProjectUrl) {
            $lines += "| **Project URL** | $($EnrichedData.ProjectUrl) |"
        }
        if ($EnrichedData.Homepage) {
            $lines += "| **Homepage** | $($EnrichedData.Homepage) |"
        }
        if ($EnrichedData.Repository) {
            $lines += "| **Repository** | $($EnrichedData.Repository) |"
        }
        if ($EnrichedData.Description) {
            $lines += "| **Description** | $($EnrichedData.Description) |"
        }
    }
    
    # Download location
    $lines += "| **Download Location** | $($Package.downloadLocation) |"
    
    # Files analyzed
    $lines += "| **Files Analyzed** | $($Package.filesAnalyzed) |"
    
    # External references
    if ($Package.externalRefs) {
        foreach ($ref in $Package.externalRefs) {
            if ($ref.referenceType -eq "purl") {
                $lines += "| **Package URL** | ``$($ref.referenceLocator)`` |"
                
                # Extract package manager from purl
                if ($ref.referenceLocator -match "^pkg:([^/]+)/") {
                    $lines += "| **Package Manager** | $($matches[1]) |"
                }
            }
        }
    }
    
    return $lines
}

function New-VulnerabilitySummaryMarkdown {
    <#
    .SYNOPSIS
    Generate markdown section for vulnerability summary
    
    .DESCRIPTION
    Creates a formatted vulnerability section with severity-sorted table and detailed listings.
    
    .PARAMETER VulnerablePackages
    Array of vulnerable package objects with Vulnerabilities property
    
    .OUTPUTS
    Array of strings representing markdown lines
    
    .EXAMPLE
    $vulnSection = New-VulnerabilitySummaryMarkdown -VulnerablePackages $vulnList
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory=$true)]
        [array] $VulnerablePackages
    )
    
    $lines = @()
    
    if ($VulnerablePackages.Count -eq 0) {
        return $lines
    }
    
    $lines += "---"
    $lines += ""
    $lines += "## [!] Security Vulnerabilities"
    $lines += ""
    $lines += "> **CRITICAL**: $($VulnerablePackages.Count) vulnerable package(s) detected!"
    $lines += ""
    $lines += "| Package | Version | Severity | CVE | Vulnerability ID | Source |"
    $lines += "|---------|---------|----------|-----|------------------|--------|"
    
    # Sort by severity
    $severityOrder = @{ "CRITICAL" = 0; "HIGH" = 1; "MODERATE" = 2; "MEDIUM" = 2; "LOW" = 3; "UNKNOWN" = 4 }
    
    $sortedVulnPackages = $VulnerablePackages | Sort-Object {
        $maxSeverity = 999
        foreach ($vuln in $_.Vulnerabilities) {
            $sev = $severityOrder[$vuln.Severity.ToUpper()]
            if ($null -eq $sev) { $sev = 4 }
            if ($sev -lt $maxSeverity) { $maxSeverity = $sev }
        }
        $maxSeverity
    }
    
    foreach ($vulnPkg in $sortedVulnPackages) {
        foreach ($vuln in $vulnPkg.Vulnerabilities) {
            $severityText = "[$($vuln.Severity.ToUpper())]"
            $cveText = if ($vuln.CVE -ne "N/A") { $vuln.CVE } else { "-" }
            $sourceText = if ($vulnPkg.Source) { $vulnPkg.Source } else { "Unknown" }
            
            $lines += "| **$($vulnPkg.Name)** | $($vulnPkg.Version) | $severityText | $cveText | ``$($vuln.Id)`` | $sourceText |"
        }
    }
    
    $lines += ""
    
    # Detailed vulnerability information
    $lines += "### Vulnerability Details"
    $lines += ""
    
    foreach ($vulnPkg in $sortedVulnPackages) {
        $lines += "#### [!] $($vulnPkg.Name) v$($vulnPkg.Version)"
        $lines += ""
        
        foreach ($vuln in $vulnPkg.Vulnerabilities) {
            $lines += "**Vulnerability: ``$($vuln.Id)``**"
            $lines += ""
            $lines += "| Property | Value |"
            $lines += "|----------|-------|"
            
            if ($vuln.CVE -ne "N/A") {
                $lines += "| **CVE** | $($vuln.CVE) |"
            }
            $lines += "| **Severity** | $($vuln.Severity) |"
            if ($vuln.CVSSScore -ne "N/A") {
                $lines += "| **CVSS Score** | $($vuln.CVSSScore) |"
            }
            if ($vuln.Published) {
                $lines += "| **Published** | $($vuln.Published) |"
            }
            if ($vuln.Modified) {
                $lines += "| **Modified** | $($vuln.Modified) |"
            }
            
            if ($vuln.Summary) {
                $lines += ""
                $lines += "**Summary:**"
                $lines += ""
                $lines += $vuln.Summary
                $lines += ""
            }
            
            if ($vuln.Details) {
                $lines += "**Details:**"
                $lines += ""
                $lines += $vuln.Details
                $lines += ""
            }
            
            if ($vuln.References -and $vuln.References.Count -gt 0) {
                $lines += "**References:**"
                $lines += ""
                foreach ($ref in $vuln.References) {
                    if ($ref.url) {
                        $lines += "- $($ref.url)"
                    }
                }
                $lines += ""
            }
            
            $lines += "---"
            $lines += ""
        }
    }
    
    return $lines
}

function New-StatisticsMarkdown {
    <#
    .SYNOPSIS
    Generate markdown section for processing statistics
    
    .DESCRIPTION
    Creates formatted markdown tables showing enrichment and vulnerability scan statistics.
    
    .PARAMETER Statistics
    Statistics object from Get-StatisticsSummary
    
    .OUTPUTS
    Array of strings representing markdown lines
    
    .EXAMPLE
    $statsSection = New-StatisticsMarkdown -Statistics $stats
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Statistics
    )
    
    $lines = @()
    $lines += "---"
    $lines += ""
    $lines += "## Processing Statistics"
    $lines += ""
    
    # Enrichment statistics
    $lines += "### Enrichment Statistics"
    $lines += ""
    $lines += "| Metric | Count |"
    $lines += "|--------|-------|"
    $lines += "| **Total Packages Processed** | $($Statistics.Enrichment.Total) |"
    $lines += "| **Successfully Enriched** | $($Statistics.Enrichment.Enriched) |"
    $lines += "| **Failed to Enrich** | $($Statistics.Enrichment.Failed) |"
    $lines += "| **Cached Results** | $($Statistics.Enrichment.Cached) |"
    $lines += "| **Success Rate** | $($Statistics.EnrichmentSuccessRate)% |"
    $lines += ""
    
    # Vulnerability statistics
    if ($Statistics.Vulnerability.Checked -gt 0) {
        $lines += "### Vulnerability Scan Statistics"
        $lines += ""
        $lines += "| Metric | Count |"
        $lines += "|--------|-------|"
        $lines += "| **Packages Scanned** | $($Statistics.Vulnerability.Checked) |"
        $lines += "| **Vulnerable Packages** | $($Statistics.Vulnerability.Vulnerable) |"
        $lines += "| **Safe Packages** | $($Statistics.Vulnerability.Safe) |"
        $lines += "| **Scan Failures** | $($Statistics.Vulnerability.Failed) |"
        $lines += "| **Vulnerability Rate** | $($Statistics.VulnerabilityRate)% |"
        $lines += ""
    }
    
    # Dotnet vulnerability statistics
    if ($Statistics.DotnetVulnerability.Total -gt 0) {
        $lines += "### Dotnet CLI Vulnerability Scan"
        $lines += ""
        $lines += "| Metric | Count |"
        $lines += "|--------|-------|"
        $lines += "| **Total Vulnerabilities** | $($Statistics.DotnetVulnerability.Total) |"
        $lines += "| **Critical** | $($Statistics.DotnetVulnerability.Critical) |"
        $lines += "| **High** | $($Statistics.DotnetVulnerability.High) |"
        $lines += "| **Moderate** | $($Statistics.DotnetVulnerability.Moderate) |"
        $lines += "| **Low** | $($Statistics.DotnetVulnerability.Low) |"
        $lines += ""
    }
    
    return $lines
}

Export-ModuleMember -Function ConvertTo-PackageMarkdown, New-VulnerabilitySummaryMarkdown, New-StatisticsMarkdown
