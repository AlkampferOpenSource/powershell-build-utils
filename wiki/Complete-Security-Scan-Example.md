# Complete Security Scan Example

This document contains a ready-to-use PowerShell script that performs a complete security scan including .NET and NPM vulnerability analysis with markdown report generation.

> **Important**: This script requires **PowerShell 7+** (`pwsh`) because the NPM scanning uses the `-AsHashTable` parameter which is not available in PowerShell 5.1.

## Prerequisites

- PowerShell 7+ installed
- .NET SDK installed (for `dotnet list package --vulnerable`)
- Node.js/npm installed (for `npm audit`)
- Internet connectivity (for OSV API enrichment)

## Complete Script

```powershell
#requires -Version 7.0

<#
.SYNOPSIS
    Complete security scan for .NET and NPM projects with vulnerability reporting.

.DESCRIPTION
    This script performs:
    1. .NET vulnerability scanning using dotnet CLI
    2. NPM vulnerability scanning using npm audit
    3. OSV API enrichment for detailed CVE information
    4. Markdown report generation
    5. File integrity hash generation

.PARAMETER DotnetSolutionPath
    Path to the .NET solution file (.sln)

.PARAMETER NpmProjectPath
    Path to NPM project folder containing package.json

.PARAMETER OutputDirectory
    Directory for output files (will be created if it doesn't exist)

.EXAMPLE
    .\Complete-Security-Scan.ps1 `
        -DotnetSolutionPath "C:\src\MySolution.sln" `
        -NpmProjectPath "C:\src\frontend" `
        -OutputDirectory "C:\reports\security"
#>

param(
    [Parameter(Mandatory = $false)]
    [string]$DotnetSolutionPath,

    [Parameter(Mandatory = $false)]
    [string]$NpmProjectPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [string]$ModulesPath = ".\src\security"
)

# ============================================================================
# STEP 1: Setup and import modules
# ============================================================================

Write-Host "========================================"
Write-Host "  Security Scan - Setup"
Write-Host "========================================"

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    Write-Host "[+] Created output directory: $OutputDirectory"
}

# Import all required modules
Write-Host "[*] Importing security modules..."
Import-Module (Join-Path $ModulesPath "Get-PackageVulnerability.psm1") -Force
Import-Module (Join-Path $ModulesPath "Measure-SBOMStatistics.psm1") -Force
Import-Module (Join-Path $ModulesPath "ConvertTo-SBOMMarkdown.psm1") -Force
Import-Module (Join-Path $ModulesPath "Get-FileHashReport.psm1") -Force
Write-Host "[+] Modules imported successfully"

# ============================================================================
# STEP 2: Initialize statistics tracking
# ============================================================================

$stats = Initialize-SBOMStatistics

# ============================================================================
# STEP 3: Run .NET vulnerability scan (if solution path provided)
# ============================================================================

$dotnetvulns = @{}

if ($DotnetSolutionPath -and (Test-Path $DotnetSolutionPath)) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  .NET Vulnerability Scan"
    Write-Host "========================================"
    Write-Host "[*] Scanning: $DotnetSolutionPath"

    $dotnetvulns = Get-DotnetVulnerabilities `
        -SolutionPath $DotnetSolutionPath `
        -Statistics $stats `
        -OutputFile (Join-Path $OutputDirectory "dotnet-vulnerabilities.json")

    Write-Host "[+] Found $($dotnetvulns.Count) vulnerable .NET package(s)"

    # Display vulnerable packages
    if ($dotnetvulns.Count -gt 0) {
        foreach ($key in $dotnetvulns.Keys) {
            $pkg = $dotnetvulns[$key]
            Write-Host "    - $($pkg.Name) v$($pkg.Version): $($pkg.Vulnerabilities.Count) vulnerabilities" -ForegroundColor Yellow
        }
    }

    # Generate .NET vulnerability markdown report
    Write-Host "[*] Generating .NET vulnerability report..."
    $dotnetMarkdown = ConvertTo-DotnetVulnMarkdownReport `
        -VulnerabilityData $dotnetvulns `
        -OutputFile (Join-Path $OutputDirectory "dotnet-vulnerability-report.md") `
        -SolutionPath $DotnetSolutionPath

    Write-Host "[+] Report saved: dotnet-vulnerability-report.md"
}
else {
    Write-Host ""
    Write-Host "[!] Skipping .NET scan (no valid solution path provided)"
}

# ============================================================================
# STEP 4: Run NPM vulnerability scan (if project path provided)
# ============================================================================

$npmvulns = @{}
$enrichedNpmVulns = @{}

if ($NpmProjectPath -and (Test-Path $NpmProjectPath)) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "  NPM Vulnerability Scan"
    Write-Host "========================================"
    Write-Host "[*] Scanning: $NpmProjectPath"

    $npmvulns = Get-NpmVulnerabilities `
        -FolderPath $NpmProjectPath `
        -Statistics $stats `
        -OutputFile (Join-Path $OutputDirectory "npm-vulnerabilities.json")

    Write-Host "[+] Found $($npmvulns.Count) vulnerable NPM package(s)"

    # Display vulnerable packages
    if ($npmvulns.Count -gt 0) {
        foreach ($key in $npmvulns.Keys) {
            $pkg = $npmvulns[$key]
            Write-Host "    - $($pkg.Name) $($pkg.Version): $($pkg.Vulnerabilities.Count) vulnerabilities" -ForegroundColor Yellow
        }

        # Enrich NPM vulnerabilities with OSV data
        Write-Host "[*] Enriching with OSV vulnerability data..."
        $enrichedNpmVulns = Add-NpmVulnerabilityEnrichment `
            -VulnerabilityData $npmvulns `
            -CacheFilePath (Join-Path $OutputDirectory "osv-cache.json")
        Write-Host "[+] Enrichment complete (cached for future scans)"
    }
    else {
        $enrichedNpmVulns = $npmvulns
    }

    # Generate NPM vulnerability markdown report
    Write-Host "[*] Generating NPM vulnerability report..."
    $npmMarkdown = ConvertTo-NpmVulnMarkdownReport `
        -VulnerabilityData $enrichedNpmVulns `
        -OutputFile (Join-Path $OutputDirectory "npm-vulnerability-report.md") `
        -ProjectPath $NpmProjectPath

    Write-Host "[+] Report saved: npm-vulnerability-report.md"
}
else {
    Write-Host ""
    Write-Host "[!] Skipping NPM scan (no valid project path provided)"
}

# ============================================================================
# STEP 5: Generate file integrity hashes
# ============================================================================

Write-Host ""
Write-Host "========================================"
Write-Host "  File Integrity Hashes"
Write-Host "========================================"

$outputFiles = Get-ChildItem -Path $OutputDirectory -File | Where-Object {
    $_.Extension -in @('.json', '.md')
}

if ($outputFiles.Count -gt 0) {
    $hashReport = New-HashReport -Files $outputFiles.FullName
    Export-HashReport -Report $hashReport -OutputPath (Join-Path $OutputDirectory "integrity-hashes.txt")
    Write-Host "[+] Hash report saved: integrity-hashes.txt"
}

# ============================================================================
# STEP 6: Display summary
# ============================================================================

Write-Host ""
Write-Host "========================================"
Write-Host "  Summary"
Write-Host "========================================"

$summary = Get-StatisticsSummary -Statistics $stats

if ($DotnetSolutionPath) {
    Write-Host ""
    Write-Host ".NET Vulnerabilities:"
    Write-Host "  Total:    $($summary.DotnetVulnerability.Total)"
    Write-Host "  Critical: $($summary.DotnetVulnerability.Critical)" -ForegroundColor $(if ($summary.DotnetVulnerability.Critical -gt 0) { "Red" } else { "Green" })
    Write-Host "  High:     $($summary.DotnetVulnerability.High)" -ForegroundColor $(if ($summary.DotnetVulnerability.High -gt 0) { "Red" } else { "Green" })
    Write-Host "  Moderate: $($summary.DotnetVulnerability.Moderate)" -ForegroundColor $(if ($summary.DotnetVulnerability.Moderate -gt 0) { "Yellow" } else { "Green" })
    Write-Host "  Low:      $($summary.DotnetVulnerability.Low)"
}

if ($NpmProjectPath) {
    Write-Host ""
    Write-Host "NPM Vulnerabilities:"
    Write-Host "  Vulnerable Packages: $($npmvulns.Count)"
    $totalNpmVulns = ($npmvulns.Values | ForEach-Object { $_.Vulnerabilities.Count } | Measure-Object -Sum).Sum
    Write-Host "  Total Vulnerabilities: $totalNpmVulns"
}

Write-Host ""
Write-Host "Files Generated:"
Get-ChildItem $OutputDirectory | ForEach-Object { Write-Host "  - $($_.Name)" }

# Return exit code based on vulnerabilities found
$totalVulns = $summary.DotnetVulnerability.Total + $(if ($npmvulns.Count -gt 0) { ($npmvulns.Values | ForEach-Object { $_.Vulnerabilities.Count } | Measure-Object -Sum).Sum } else { 0 })

Write-Host ""
if ($totalVulns -gt 0) {
    Write-Host "WARNING: $totalVulns total vulnerabilities detected!" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "All packages are secure." -ForegroundColor Green
    exit 0
}
```

## Quick Start - Inline Commands

If you prefer to run commands interactively, here is the exact sequence:

```powershell
# ============================================================================
# STEP 1: Set working directory and import all required modules
# ============================================================================

Set-Location 'A:\Develop\github\powershell-build-utils'

Import-Module '.\src\security\Get-PackageVulnerability.psm1' -Force
Import-Module '.\src\security\Measure-SBOMStatistics.psm1' -Force
Import-Module '.\src\security\ConvertTo-SBOMMarkdown.psm1' -Force
Import-Module '.\src\security\Get-FileHashReport.psm1' -Force

# ============================================================================
# STEP 2: Initialize statistics tracking
# ============================================================================

$stats = Initialize-SBOMStatistics

# ============================================================================
# STEP 3: Run .NET vulnerability scan
# ============================================================================

$dotnetvulns = Get-DotnetVulnerabilities `
    -SolutionPath 'A:\Develop\Proximo\Jarvis\src\Jarvis.Common.Shared.sln' `
    -Statistics $stats `
    -OutputFile 'S:\Temp\sbom-test\dotnet-vulnerabilities.json'

# ============================================================================
# STEP 4: Generate .NET vulnerability markdown report
# ============================================================================

$dotnetMarkdown = ConvertTo-DotnetVulnMarkdownReport `
    -VulnerabilityData $dotnetvulns `
    -OutputFile 'S:\Temp\sbom-test\dotnet-vulnerability-report.md' `
    -SolutionPath 'A:\Develop\Proximo\Jarvis\src\Jarvis.Common.Shared.sln'

# ============================================================================
# STEP 5: Run NPM vulnerability scan
# ============================================================================

$npmvulns = Get-NpmVulnerabilities `
    -FolderPath 'A:\Develop\Proximo\Jarvis\src\frontend\Jarvis.UI' `
    -Statistics $stats `
    -OutputFile 'S:\Temp\sbom-test\npm-vulnerabilities.json'

# ============================================================================
# STEP 6: Enrich NPM vulnerabilities with OSV data (adds CVE details, CVSS scores)
# ============================================================================

$enrichedNpmVulns = Add-NpmVulnerabilityEnrichment `
    -VulnerabilityData $npmvulns `
    -CacheFilePath 'S:\Temp\sbom-test\osv-cache.json'

# ============================================================================
# STEP 7: Generate NPM vulnerability markdown report
# ============================================================================

$npmMarkdown = ConvertTo-NpmVulnMarkdownReport `
    -VulnerabilityData $enrichedNpmVulns `
    -OutputFile 'S:\Temp\sbom-test\npm-vulnerability-report.md' `
    -ProjectPath 'A:\Develop\Proximo\Jarvis\src\frontend\Jarvis.UI'

# ============================================================================
# STEP 8: Generate file integrity hashes
# ============================================================================

$outputFiles = Get-ChildItem -Path 'S:\Temp\sbom-test' -File | Where-Object {
    $_.Extension -in @('.json', '.md')
}
$hashReport = New-HashReport -Files $outputFiles.FullName
Export-HashReport -Report $hashReport -OutputPath 'S:\Temp\sbom-test\integrity-hashes.txt'

# ============================================================================
# STEP 9: Display summary
# ============================================================================

$summary = Get-StatisticsSummary -Statistics $stats

Write-Host ".NET Vulnerabilities:"
Write-Host "  Total: $($summary.DotnetVulnerability.Total)"
Write-Host "  Critical: $($summary.DotnetVulnerability.Critical)"
Write-Host "  High: $($summary.DotnetVulnerability.High)"
Write-Host "  Moderate: $($summary.DotnetVulnerability.Moderate)"
Write-Host "  Low: $($summary.DotnetVulnerability.Low)"

Write-Host ""
Write-Host "NPM Vulnerabilities:"
Write-Host "  Vulnerable Packages: $($npmvulns.Count)"
$totalNpmVulns = ($npmvulns.Values | ForEach-Object { $_.Vulnerabilities.Count } | Measure-Object -Sum).Sum
Write-Host "  Total Vulnerabilities: $totalNpmVulns"

Write-Host ""
Write-Host "Files Generated:"
Get-ChildItem 'S:\Temp\sbom-test' | ForEach-Object { Write-Host "  - $($_.Name)" }
```

## How to Run

### Option 1: Save as script file

1. Save the complete script as `Complete-Security-Scan.ps1`
2. Run with PowerShell 7:

```bash
pwsh -NoProfile -ExecutionPolicy Bypass -File "Complete-Security-Scan.ps1" `
    -DotnetSolutionPath "C:\src\MySolution.sln" `
    -NpmProjectPath "C:\src\frontend" `
    -OutputDirectory "C:\reports\security"
```

### Option 2: Interactive execution

1. Open PowerShell 7:
```bash
pwsh
```

2. Copy and paste the inline commands from the "Quick Start" section above.

## Output Files

After running the script, you will have the following files in your output directory:

| File | Description |
|------|-------------|
| `dotnet-vulnerabilities.json` | Raw JSON from dotnet CLI vulnerability scan |
| `dotnet-vulnerabilities.json.hash.txt` | Integrity hash for the JSON file |
| `dotnet-vulnerability-report.md` | Human-readable Markdown report for .NET |
| `dotnet-vulnerability-report.md.hash.txt` | Integrity hash for the report |
| `npm-vulnerabilities.json` | Raw JSON from npm audit |
| `npm-vulnerabilities.json.hash.txt` | Integrity hash for the JSON file |
| `npm-vulnerability-report.md` | Human-readable Markdown report for NPM (enriched with OSV data) |
| `npm-vulnerability-report.md.hash.txt` | Integrity hash for the report |
| `osv-cache.json` | Cached OSV API responses (speeds up future scans) |
| `integrity-hashes.txt` | Combined hash report for all output files |

## Sample Output

```
========================================
  Security Scan - Setup
========================================
[+] Created output directory: S:\Temp\sbom-test
[*] Importing security modules...
[+] Modules imported successfully

========================================
  .NET Vulnerability Scan
========================================
[*] Scanning: A:\Develop\Proximo\Jarvis\src\Jarvis.Common.Shared.sln
[+] Found 3 vulnerable .NET package(s)
    - System.Net.Http v4.3.0: 1 vulnerabilities
    - System.Text.RegularExpressions v4.3.0: 1 vulnerabilities
    - Magick.NET-Q16-AnyCPU v14.10.1: 4 vulnerabilities
[*] Generating .NET vulnerability report...
[+] Report saved: dotnet-vulnerability-report.md

========================================
  NPM Vulnerability Scan
========================================
[*] Scanning: A:\Develop\Proximo\Jarvis\src\frontend\Jarvis.UI
[+] Found 8 vulnerable NPM package(s)
    - extend <2.0.2: 1 vulnerabilities
    - mermaid >=11.0.0-alpha.1: 2 vulnerabilities
    - lodash-es 4.0.0 - 4.17.22: 1 vulnerabilities
    - bootstrap 3.1.1 - 3.4.1: 2 vulnerabilities
    - lodash 4.0.0 - 4.17.21: 1 vulnerabilities
    - d3-color <3.1.0: 1 vulnerabilities
    - diff <4.0.4: 1 vulnerabilities
    - tar <=7.5.3: 2 vulnerabilities
[*] Enriching with OSV vulnerability data...
[+] Enrichment complete (cached for future scans)
[*] Generating NPM vulnerability report...
[+] Report saved: npm-vulnerability-report.md

========================================
  Summary
========================================

.NET Vulnerabilities:
  Total:    6
  Critical: 0
  High:     2
  Moderate: 4
  Low:      0

NPM Vulnerabilities:
  Vulnerable Packages: 8
  Total Vulnerabilities: 11

Files Generated:
  - dotnet-vulnerabilities.json
  - dotnet-vulnerabilities.json.hash.txt
  - dotnet-vulnerability-report.md
  - dotnet-vulnerability-report.md.hash.txt
  - integrity-hashes.txt
  - npm-vulnerabilities.json
  - npm-vulnerabilities.json.hash.txt
  - npm-vulnerability-report.md
  - npm-vulnerability-report.md.hash.txt
  - osv-cache.json

WARNING: 17 total vulnerabilities detected!
```

## See Also

- [SBOM-Dependency-Analysis-Guide.md](SBOM-Dependency-Analysis-Guide.md) - Complete module reference and individual use cases
- [SecurityScenario.md](SecurityScenario.md) - Quick scenario-based examples
- [Dotnet-Vulnerability-Report.md](Dotnet-Vulnerability-Report.md) - Detailed .NET vulnerability reporting
