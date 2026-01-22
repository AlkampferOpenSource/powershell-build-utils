# SBOM and Dependency Analysis Guide

This guide documents the new security tools introduced for SBOM (Software Bill of Materials) generation and dependency vulnerability analysis.

> **Quick Start**: For a ready-to-use complete security scan script, see [Complete-Security-Scan-Example.md](Complete-Security-Scan-Example.md)

---

## Overview

The latest commit introduces a comprehensive set of PowerShell modules for:

1. **SBOM Generation** - Generate SPDX-compliant SBOM documents
2. **Vulnerability Scanning** - Detect security vulnerabilities in .NET and NPM projects
3. **Metadata Enrichment** - Enhance package information from public registries
4. **Markdown Reporting** - Generate human-readable reports
5. **File Hash Verification** - Create integrity hashes for output files
6. **Caching** - Optimize API calls with persistent caching

---

## Module Reference

| Module | Description |
|--------|-------------|
| `Generate-Sbom.psm1` | Generate SBOM using Microsoft sbom-tool |
| `Get-PackageVulnerability.psm1` | Detect vulnerabilities in .NET/NPM packages |
| `Get-NuGetVulnerabilities.psm1` | Query OSV API for NuGet vulnerabilities |
| `Get-PackageRegistryInfo.psm1` | Fetch metadata from NPM/NuGet registries |
| `Convert-ManifestSpdxJsonToMarkdown.psm1` | Convert SPDX JSON to Markdown |
| `ConvertTo-SBOMMarkdown.psm1` | Generate formatted Markdown documentation |
| `Get-FileHashReport.psm1` | Calculate SHA256/SHA1/MD5 hashes |
| `Invoke-SBOMCache.psm1` | Manage API response caching |
| `Measure-SBOMStatistics.psm1` | Track processing statistics |

---

## Exported Functions

### SBOM Generation
- `Invoke-Sbom` - Generate SBOM using sbom-tool

### Vulnerability Scanning
- `Get-DotnetVulnerabilities` - Scan .NET solutions for vulnerable packages
- `Get-NpmVulnerabilities` - Scan NPM projects using `npm audit`
- `Get-NuGetVulnerabilities` - Query OSV API for NuGet package vulnerabilities
- `Get-NpmPackageVulnerabilities` - Query OSV API for npm package vulnerabilities
- `Add-NpmVulnerabilityEnrichment` - Enrich npm vulnerabilities with OSV data

### Markdown Reports
- `ConvertTo-DotnetVulnMarkdownReport` - Generate .NET vulnerability report
- `ConvertTo-NpmVulnMarkdownReport` - Generate NPM vulnerability report
- `Convert-ManifestSpdxJsonToMarkdown` - Convert SPDX manifest to Markdown
- `Convert-SpdxManifestToMarkdown` - Wrapper for SPDX conversion
- `ConvertTo-PackageMarkdown` - Generate markdown for single package
- `New-VulnerabilitySummaryMarkdown` - Generate vulnerability summary section
- `New-StatisticsMarkdown` - Generate statistics section

### Package Metadata
- `Get-NpmPackageInfo` - Retrieve NPM package metadata
- `Get-NuGetPackageInfo` - Retrieve NuGet package metadata
- `Get-PackageInfo` - Unified package info retrieval

### File Hashing
- `Get-MultiAlgorithmHash` - Calculate SHA256, SHA1, MD5 for a file
- `New-HashReport` - Generate hash report for multiple files
- `Export-HashReport` - Save hash report to file
- `ConvertTo-HashMarkdown` - Convert hash report to markdown

### Caching
- `Initialize-SBOMCache` - Create or load cache
- `Get-CachedPackage` - Retrieve from cache
- `Set-CachedPackage` - Store in cache
- `Import-SBOMCache` - Load cache from JSON file
- `Export-SBOMCache` - Save cache to JSON file
- `Clear-SBOMCache` - Clear cache entries

### Statistics
- `Initialize-SBOMStatistics` - Create statistics tracker
- `Update-EnrichmentStats` - Update enrichment counters
- `Update-VulnerabilityStats` - Update vulnerability counters
- `Update-DotnetVulnerabilityStats` - Update .NET vulnerability severity counters
- `Get-StatisticsSummary` - Get formatted statistics summary

---

## Complete Full Report Script

The following script generates a comprehensive security report including all functionalities:

```powershell
#requires -Version 5.1

<#
.SYNOPSIS
    Generate a complete security report with SBOM, vulnerability analysis, and integrity hashes.

.DESCRIPTION
    This script performs:
    1. SBOM generation for .NET projects
    2. .NET vulnerability scanning
    3. NPM vulnerability scanning (if applicable)
    4. Metadata enrichment
    5. Markdown report generation
    6. File integrity hash generation

.PARAMETER SolutionPath
    Path to the .NET solution file (.sln)

.PARAMETER NpmProjectPath
    Path to NPM project folder (optional)

.PARAMETER OutputDirectory
    Directory for output files

.PARAMETER ProjectName
    Name for the SBOM document

.PARAMETER ProjectVersion
    Version for the SBOM document

.PARAMETER Publisher
    Publisher name for SBOM

.EXAMPLE
    .\Generate-FullSecurityReport.ps1 `
        -SolutionPath "C:\src\MySolution.sln" `
        -OutputDirectory "C:\reports\sbom" `
        -ProjectName "MyProject" `
        -ProjectVersion "1.0.0"
#>

param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({ Test-Path $_ })]
    [string]$SolutionPath,

    [Parameter(Mandatory = $false)]
    [string]$NpmProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string]$ProjectName,

    [Parameter(Mandatory = $true)]
    [string]$ProjectVersion,

    [Parameter(Mandatory = $false)]
    [string]$Publisher = "MyOrganization",

    [Parameter(Mandatory = $false)]
    [string]$Namespace = "https://sbom.myorganization.com"
)

# ============================================================================
# STEP 1: Import all required modules
# ============================================================================

$scriptRoot = $PSScriptRoot
if (-not $scriptRoot) {
    $scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
}

# Adjust path to your module location
$modulePath = Join-Path $scriptRoot "src\security"

Import-Module (Join-Path $modulePath "Generate-Sbom.psm1") -Force
Import-Module (Join-Path $modulePath "Get-PackageVulnerability.psm1") -Force
Import-Module (Join-Path $modulePath "Get-NuGetVulnerabilities.psm1") -Force
Import-Module (Join-Path $modulePath "Get-PackageRegistryInfo.psm1") -Force
Import-Module (Join-Path $modulePath "Convert-ManifestSpdxJsonToMarkdown.psm1") -Force
Import-Module (Join-Path $modulePath "ConvertTo-SBOMMarkdown.psm1") -Force
Import-Module (Join-Path $modulePath "Get-FileHashReport.psm1") -Force
Import-Module (Join-Path $modulePath "Invoke-SBOMCache.psm1") -Force
Import-Module (Join-Path $modulePath "Measure-SBOMStatistics.psm1") -Force

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Security Report Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================================================
# STEP 2: Initialize output directory and statistics
# ============================================================================

if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    Write-Host "[+] Created output directory: $OutputDirectory" -ForegroundColor Green
}

# Initialize statistics tracking
$stats = Initialize-SBOMStatistics

# Initialize cache (optional - for faster repeated scans)
$cachePath = Join-Path $OutputDirectory "security-cache.json"
$cache = Initialize-SBOMCache -FilePath $cachePath

# ============================================================================
# STEP 3: Generate SBOM using sbom-tool
# ============================================================================

Write-Host "`n[1/6] Generating SBOM..." -ForegroundColor Yellow

$sourcesFolder = Split-Path $SolutionPath -Parent
$binaryFolder = Join-Path $sourcesFolder "bin"

# If bin folder doesn't exist, use sources folder
if (-not (Test-Path $binaryFolder)) {
    $binaryFolder = $sourcesFolder
}

try {
    Invoke-Sbom `
        -BinaryFolder $binaryFolder `
        -SourcesFolder $sourcesFolder `
        -ProjectName $ProjectName `
        -ProjectVersion $ProjectVersion `
        -Publisher $Publisher `
        -Namespace $Namespace `
        -OutputFolder $OutputDirectory `
        -GenerateMarkdown `
        -Verbose

    Write-Host "[+] SBOM generated successfully" -ForegroundColor Green
}
catch {
    Write-Warning "SBOM generation failed: $_"
    Write-Host "[!] Continuing with vulnerability scanning..." -ForegroundColor Yellow
}

# ============================================================================
# STEP 4: Scan .NET vulnerabilities
# ============================================================================

Write-Host "`n[2/6] Scanning .NET vulnerabilities..." -ForegroundColor Yellow

$dotnetScanPath = Join-Path $OutputDirectory "dotnet-vulnerabilities.json"
$dotnetReportPath = Join-Path $OutputDirectory "dotnet-vulnerability-report.md"

$dotnetvulns = Get-DotnetVulnerabilities `
    -SolutionPath $SolutionPath `
    -Statistics $stats `
    -OutputFile $dotnetScanPath

if ($dotnetvulns.Count -eq 0) {
    Write-Host "[+] No .NET vulnerabilities found!" -ForegroundColor Green
}
else {
    Write-Host "[!] Found $($dotnetvulns.Count) vulnerable .NET package(s)" -ForegroundColor Red

    # Display vulnerability summary
    foreach ($key in $dotnetvulns.Keys) {
        $pkg = $dotnetvulns[$key]
        Write-Host "    - $($pkg.Name) v$($pkg.Version): $($pkg.Vulnerabilities.Count) vulnerabilities" -ForegroundColor Yellow
    }
}

# Generate .NET vulnerability markdown report
$dotnetMarkdown = ConvertTo-DotnetVulnMarkdownReport `
    -VulnerabilityData $dotnetvulns `
    -OutputFile $dotnetReportPath `
    -SolutionPath $SolutionPath

Write-Host "[+] .NET report saved: $dotnetReportPath" -ForegroundColor Green

# ============================================================================
# STEP 5: Scan NPM vulnerabilities (if applicable)
# ============================================================================

$npmvulns = @{}
$npmReportPath = $null

if ($NpmProjectPath -and (Test-Path $NpmProjectPath)) {
    Write-Host "`n[3/6] Scanning NPM vulnerabilities..." -ForegroundColor Yellow

    $npmScanPath = Join-Path $OutputDirectory "npm-vulnerabilities.json"
    $npmReportPath = Join-Path $OutputDirectory "npm-vulnerability-report.md"

    $npmvulns = Get-NpmVulnerabilities `
        -FolderPath $NpmProjectPath `
        -Statistics $stats `
        -OutputFile $npmScanPath

    if ($npmvulns.Count -eq 0) {
        Write-Host "[+] No NPM vulnerabilities found!" -ForegroundColor Green
    }
    else {
        Write-Host "[!] Found $($npmvulns.Count) vulnerable NPM package(s)" -ForegroundColor Red

        # Enrich with OSV data (uses cache automatically)
        Write-Host "    Enriching with OSV vulnerability data..." -ForegroundColor Gray
        $enrichedNpmVulns = Add-NpmVulnerabilityEnrichment `
            -VulnerabilityData $npmvulns `
            -CacheFilePath $cachePath

        # Generate NPM vulnerability markdown report
        $npmMarkdown = ConvertTo-NpmVulnMarkdownReport `
            -VulnerabilityData $enrichedNpmVulns `
            -OutputFile $npmReportPath `
            -ProjectPath $NpmProjectPath

        Write-Host "[+] NPM report saved: $npmReportPath" -ForegroundColor Green
    }
}
else {
    Write-Host "`n[3/6] Skipping NPM scan (no NPM project specified)" -ForegroundColor Gray
}

# ============================================================================
# STEP 6: Convert SBOM manifest to enriched Markdown
# ============================================================================

Write-Host "`n[4/6] Converting SBOM to enriched Markdown..." -ForegroundColor Yellow

$sbomManifestPath = Join-Path $OutputDirectory "manifest.spdx.json"

if (Test-Path $sbomManifestPath) {
    $sbomMarkdownPath = Convert-SpdxManifestToMarkdown `
        -InputPath $sbomManifestPath `
        -EnrichMetadata

    Write-Host "[+] SBOM Markdown saved: $sbomMarkdownPath" -ForegroundColor Green
}
else {
    Write-Host "[!] SBOM manifest not found, skipping conversion" -ForegroundColor Yellow
}

# ============================================================================
# STEP 7: Generate file integrity hashes
# ============================================================================

Write-Host "`n[5/6] Generating file integrity hashes..." -ForegroundColor Yellow

$outputFiles = Get-ChildItem -Path $OutputDirectory -File | Where-Object {
    $_.Extension -in @('.json', '.md', '.txt')
}

$hashReport = New-HashReport -Files $outputFiles.FullName

$hashReportPath = Join-Path $OutputDirectory "integrity-hashes.txt"
Export-HashReport -Report $hashReport -OutputPath $hashReportPath

$hashMarkdownPath = Join-Path $OutputDirectory "integrity-hashes.md"
$hashMarkdown = ConvertTo-HashMarkdown -Report $hashReport
$hashMarkdown | Out-File -FilePath $hashMarkdownPath -Encoding UTF8

Write-Host "[+] Hash reports saved:" -ForegroundColor Green
Write-Host "    - $hashReportPath" -ForegroundColor Gray
Write-Host "    - $hashMarkdownPath" -ForegroundColor Gray

# ============================================================================
# STEP 8: Generate combined summary report
# ============================================================================

Write-Host "`n[6/6] Generating combined summary report..." -ForegroundColor Yellow

$summaryPath = Join-Path $OutputDirectory "security-summary.md"
$summary = Get-StatisticsSummary -Statistics $stats

$summaryLines = @()
$summaryLines += "# Security Analysis Summary Report"
$summaryLines += ""
$summaryLines += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$summaryLines += "**Project:** $ProjectName v$ProjectVersion"
$summaryLines += "**Solution:** $(Split-Path -Leaf $SolutionPath)"
$summaryLines += ""
$summaryLines += "---"
$summaryLines += ""
$summaryLines += "## Quick Summary"
$summaryLines += ""

# Vulnerability overview
$totalDotnetVulns = $summary.DotnetVulnerability.Total
$totalNpmVulns = ($npmvulns.Values | ForEach-Object { $_.Vulnerabilities.Count } | Measure-Object -Sum).Sum
if (-not $totalNpmVulns) { $totalNpmVulns = 0 }
$totalVulns = $totalDotnetVulns + $totalNpmVulns

if ($totalVulns -eq 0) {
    $summaryLines += "> **Status: SECURE** - No known vulnerabilities detected"
}
else {
    $summaryLines += "> **Status: VULNERABILITIES FOUND** - $totalVulns total vulnerabilities detected"
}
$summaryLines += ""

$summaryLines += "## Vulnerability Statistics"
$summaryLines += ""
$summaryLines += "### .NET Packages"
$summaryLines += ""
$summaryLines += "| Severity | Count |"
$summaryLines += "|----------|-------|"
$summaryLines += "| **Critical** | $($summary.DotnetVulnerability.Critical) |"
$summaryLines += "| **High** | $($summary.DotnetVulnerability.High) |"
$summaryLines += "| **Moderate** | $($summary.DotnetVulnerability.Moderate) |"
$summaryLines += "| **Low** | $($summary.DotnetVulnerability.Low) |"
$summaryLines += "| **Total** | $($summary.DotnetVulnerability.Total) |"
$summaryLines += ""

if ($NpmProjectPath) {
    $summaryLines += "### NPM Packages"
    $summaryLines += ""
    $summaryLines += "| Metric | Count |"
    $summaryLines += "|--------|-------|"
    $summaryLines += "| **Vulnerable Packages** | $($npmvulns.Count) |"
    $summaryLines += "| **Total Vulnerabilities** | $totalNpmVulns |"
    $summaryLines += ""
}

$summaryLines += "## Enrichment Statistics"
$summaryLines += ""
$summaryLines += "| Metric | Count | Rate |"
$summaryLines += "|--------|-------|------|"
$summaryLines += "| **Total Processed** | $($summary.Enrichment.Total) | - |"
$summaryLines += "| **Enriched** | $($summary.Enrichment.Enriched) | $($summary.EnrichmentSuccessRate)% |"
$summaryLines += "| **Cached** | $($summary.Enrichment.Cached) | - |"
$summaryLines += "| **Failed** | $($summary.Enrichment.Failed) | - |"
$summaryLines += ""

$summaryLines += "## Generated Files"
$summaryLines += ""
$summaryLines += "| File | Description |"
$summaryLines += "|------|-------------|"
$summaryLines += "| ``manifest.spdx.json`` | SPDX SBOM document |"
$summaryLines += "| ``manifest.spdx.md`` | SBOM in Markdown format |"
$summaryLines += "| ``dotnet-vulnerabilities.json`` | Raw .NET vulnerability data |"
$summaryLines += "| ``dotnet-vulnerability-report.md`` | .NET vulnerability report |"
if ($npmReportPath) {
    $summaryLines += "| ``npm-vulnerabilities.json`` | Raw NPM vulnerability data |"
    $summaryLines += "| ``npm-vulnerability-report.md`` | NPM vulnerability report |"
}
$summaryLines += "| ``integrity-hashes.txt`` | File integrity hashes |"
$summaryLines += "| ``integrity-hashes.md`` | Hashes in Markdown format |"
$summaryLines += "| ``security-cache.json`` | API response cache |"
$summaryLines += ""

$summaryLines += "---"
$summaryLines += ""
$summaryLines += "*Generated by Security Report Generator*"

$summaryContent = $summaryLines -join "`n"
$summaryContent | Out-File -FilePath $summaryPath -Encoding UTF8

Write-Host "[+] Summary report saved: $summaryPath" -ForegroundColor Green

# Save cache for future runs
Export-SBOMCache -Cache $cache -FilePath $cachePath

# ============================================================================
# FINAL OUTPUT
# ============================================================================

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Report Generation Complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Output Directory: $OutputDirectory" -ForegroundColor White
Write-Host ""
Write-Host "Files Generated:" -ForegroundColor White
Get-ChildItem -Path $OutputDirectory -File | ForEach-Object {
    Write-Host "  - $($_.Name)" -ForegroundColor Gray
}
Write-Host ""

if ($totalVulns -gt 0) {
    Write-Host "WARNING: $totalVulns vulnerabilities detected!" -ForegroundColor Red
    Write-Host "Review the vulnerability reports for details." -ForegroundColor Yellow
    exit 1
}
else {
    Write-Host "All packages are secure." -ForegroundColor Green
    exit 0
}
```

---

## Individual Use Cases

### 1. Generate SBOM Only

```powershell
Import-Module ".\src\security\Generate-Sbom.psm1" -Force

Invoke-Sbom `
    -BinaryFolder "C:\build\output" `
    -SourcesFolder "C:\src\MyProject" `
    -ProjectName "MyProject" `
    -ProjectVersion "1.2.3" `
    -Publisher "MyCompany" `
    -Namespace "https://sbom.mycompany.com" `
    -OutputFolder "C:\reports\sbom" `
    -GenerateMarkdown
```

### 2. Scan .NET Vulnerabilities Only

```powershell
Import-Module ".\src\security\Get-PackageVulnerability.psm1" -Force

# Scan solution
$vulns = Get-DotnetVulnerabilities `
    -SolutionPath "C:\src\MySolution.sln" `
    -OutputFile "C:\reports\dotnet-scan.json"

# Generate markdown report
$markdown = ConvertTo-DotnetVulnMarkdownReport `
    -VulnerabilityData $vulns `
    -OutputFile "C:\reports\dotnet-report.md" `
    -SolutionPath "C:\src\MySolution.sln"

# Display results
if ($vulns.Count -eq 0) {
    Write-Host "No vulnerabilities found!"
}
else {
    Write-Host "Found $($vulns.Count) vulnerable packages"
    foreach ($key in $vulns.Keys) {
        $pkg = $vulns[$key]
        Write-Host "`nPackage: $($pkg.Name) v$($pkg.Version)"
        foreach ($v in $pkg.Vulnerabilities) {
            Write-Host "  [$($v.Severity)] $($v.CVE)"
        }
    }
}
```

### 3. Scan NPM Vulnerabilities with Enrichment

```powershell
Import-Module ".\src\security\Get-PackageVulnerability.psm1" -Force

# Scan NPM project
$npmvulns = Get-NpmVulnerabilities `
    -FolderPath "C:\src\frontend" `
    -OutputFile "C:\reports\npm-scan.json"

# Enrich with OSV data (automatic caching)
$enriched = Add-NpmVulnerabilityEnrichment `
    -VulnerabilityData $npmvulns `
    -CacheFilePath "C:\reports\osv-cache.json"

# Generate enriched markdown report
ConvertTo-NpmVulnMarkdownReport `
    -VulnerabilityData $enriched `
    -OutputFile "C:\reports\npm-report.md" `
    -ProjectPath "C:\src\frontend"
```

### 4. Convert SBOM to Enriched Markdown

```powershell
Import-Module ".\src\security\Convert-ManifestSpdxJsonToMarkdown.psm1" -Force

# Basic conversion
Convert-SpdxManifestToMarkdown -InputPath "C:\sbom\manifest.spdx.json"

# With NuGet metadata enrichment and vulnerability checking
Convert-SpdxManifestToMarkdown `
    -InputPath "C:\sbom\manifest.spdx.json" `
    -EnrichMetadata
```

### 5. Generate File Integrity Hashes

```powershell
Import-Module ".\src\security\Get-FileHashReport.psm1" -Force

# Single file
$hash = Get-MultiAlgorithmHash -FilePath "C:\reports\report.md"
Write-Host "SHA256: $($hash.SHA256)"
Write-Host "SHA1:   $($hash.SHA1)"
Write-Host "MD5:    $($hash.MD5)"

# Multiple files
$files = Get-ChildItem "C:\reports" -Filter "*.md" | Select-Object -ExpandProperty FullName
$report = New-HashReport -Files $files

# Export as text
Export-HashReport -Report $report -OutputPath "C:\reports\hashes.txt"

# Export as markdown
$markdown = ConvertTo-HashMarkdown -Report $report
$markdown | Out-File "C:\reports\hashes.md"
```

### 6. Using the Cache System

```powershell
Import-Module ".\src\security\Invoke-SBOMCache.psm1" -Force

# Initialize cache (creates new or loads existing)
$cache = Initialize-SBOMCache -FilePath "C:\cache\sbom-cache.json"

# Use cache with package info functions
$info = Get-NuGetPackageInfo `
    -PackageName "Newtonsoft.Json" `
    -Version "13.0.3" `
    -Cache $cache

# Check if item is cached
$cached = Get-CachedPackage -Cache $cache -Key "nuget:Newtonsoft.Json@13.0.3"

# Manually add to cache
Set-CachedPackage -Cache $cache -Key "custom:mydata" -Data @{ Value = "test" }

# Save cache to disk
Export-SBOMCache -Cache $cache -FilePath "C:\cache\sbom-cache.json"

# Clear cache
Clear-SBOMCache -Cache $cache
```

### 7. Query Package Registries

```powershell
Import-Module ".\src\security\Get-PackageRegistryInfo.psm1" -Force

# Get NuGet package info
$nugetInfo = Get-NuGetPackageInfo -PackageName "Newtonsoft.Json" -Version "13.0.3"
Write-Host "License: $($nugetInfo.License)"
Write-Host "Author: $($nugetInfo.Author)"
Write-Host "Project URL: $($nugetInfo.ProjectUrl)"

# Get NPM package info
$npmInfo = Get-NpmPackageInfo -PackageName "lodash" -Version "4.17.21"
Write-Host "License: $($npmInfo.License)"
Write-Host "Homepage: $($npmInfo.Homepage)"

# Unified function (specify package type)
$info = Get-PackageInfo -PackageName "axios" -Version "1.6.0" -PackageType "NPM"
```

### 8. Track Statistics

```powershell
Import-Module ".\src\security\Measure-SBOMStatistics.psm1" -Force

# Initialize statistics
$stats = Initialize-SBOMStatistics

# Update during processing
Update-EnrichmentStats -Statistics $stats -Result "Enriched"
Update-EnrichmentStats -Statistics $stats -Result "Cached"
Update-EnrichmentStats -Statistics $stats -Result "Failed"

Update-VulnerabilityStats -Statistics $stats -Result "Vulnerable"
Update-VulnerabilityStats -Statistics $stats -Result "Safe"

Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Critical"
Update-DotnetVulnerabilityStats -Statistics $stats -Severity "High"

# Get summary with calculated rates
$summary = Get-StatisticsSummary -Statistics $stats
Write-Host "Enrichment Success Rate: $($summary.EnrichmentSuccessRate)%"
Write-Host "Vulnerability Rate: $($summary.VulnerabilityRate)%"
```

---

## CI/CD Integration Example

### Azure DevOps Pipeline

```yaml
trigger:
  - main

pool:
  vmImage: 'windows-latest'

variables:
  outputDir: '$(Build.ArtifactStagingDirectory)/security-reports'

steps:
  - task: PowerShell@2
    displayName: 'Generate Security Report'
    inputs:
      targetType: 'inline'
      script: |
        # Import modules
        Import-Module "$(Build.SourcesDirectory)/src/security/Get-PackageVulnerability.psm1" -Force
        Import-Module "$(Build.SourcesDirectory)/src/security/Generate-Sbom.psm1" -Force

        # Create output directory
        New-Item -Path "$(outputDir)" -ItemType Directory -Force

        # Scan vulnerabilities
        $vulns = Get-DotnetVulnerabilities `
            -SolutionPath "$(Build.SourcesDirectory)/MySolution.sln" `
            -OutputFile "$(outputDir)/vulnerabilities.json"

        # Generate report
        $markdown = ConvertTo-DotnetVulnMarkdownReport `
            -VulnerabilityData $vulns `
            -OutputFile "$(outputDir)/vulnerability-report.md"

        # Fail build if critical vulnerabilities found
        $critical = $vulns.Values | Where-Object {
            $_.Vulnerabilities | Where-Object { $_.Severity -eq "CRITICAL" }
        }

        if ($critical.Count -gt 0) {
            Write-Host "##vso[task.logissue type=error]Critical vulnerabilities found!"
            exit 1
        }

  - task: PublishBuildArtifacts@1
    displayName: 'Publish Security Reports'
    inputs:
      PathtoPublish: '$(outputDir)'
      ArtifactName: 'security-reports'
```

---

## Output Examples

### Vulnerability Report Structure

```markdown
# .NET Vulnerability Scan Report

**Scan Date:** 2026-01-22 14:30:00
**Solution:** MySolution.sln

## Summary

| Metric | Count |
|--------|-------|
| **Vulnerable Packages** | 3 |
| **Total Vulnerabilities** | 5 |
| **Critical** | 1 |
| **High** | 2 |
| **Moderate** | 2 |
| **Low** | 0 |

---

## [!] Security Vulnerabilities

| Package | Version | Severity | CVE | Vulnerability ID |
|---------|---------|----------|-----|------------------|
| **System.Text.Json** | 6.0.0 | [CRITICAL] | CVE-2024-XXXX | GHSA-xxxx |
...
```

### Hash Report Structure

```
File Hash Report
================================================================================
Generated: 2026-01-22 14:30:00
Files Processed: 3

--------------------------------------------------------------------------------
File: vulnerability-report.md
Path: C:\reports\vulnerability-report.md
Size: 12345 bytes

SHA256: ABC123...
SHA1:   DEF456...
MD5:    789GHI...
================================================================================
```

---

## Notes

- All functions support `-Verbose` for detailed logging
- Cache files are JSON format and human-readable
- Hash reports include SHA256, SHA1, and MD5 for maximum compatibility
- SBOM generation requires .NET SDK and internet connectivity
- NPM scanning requires Node.js/npm installed and **PowerShell 7+** (`pwsh`)
- OSV API queries require internet connectivity

---

## See Also

- [Complete-Security-Scan-Example.md](Complete-Security-Scan-Example.md) - **Ready-to-use complete security scan script** with step-by-step commands
- [SecurityScenario.md](SecurityScenario.md) - Quick scenario-based examples
- [Dotnet-Vulnerability-Report.md](Dotnet-Vulnerability-Report.md) - Detailed .NET vulnerability reporting

---

*Documentation generated for powershell-build-utils security modules*
