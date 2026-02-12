# SBOM Security Modules

Modular PowerShell utilities for processing Software Bill of Materials (SBOM) documents with security vulnerability scanning and metadata enrichment.

## Modules

### Core Functionality

#### [Measure-SBOMStatistics.psm1](../../src/security/Measure-SBOMStatistics.psm1)
Statistics tracking for SBOM processing operations.

**Functions:**
- `Initialize-SBOMStatistics` - Create new statistics object
- `Update-EnrichmentStats` - Track enrichment attempts (Enriched/Failed/Cached)
- `Update-VulnerabilityStats` - Track vulnerability scans (Vulnerable/Safe/Failed)
- `Update-DotnetVulnerabilityStats` - Track dotnet CLI findings by severity
- `Get-StatisticsSummary` - Calculate success rates and summaries

**Example:**
```powershell
$stats = Initialize-SBOMStatistics
Update-EnrichmentStats -Statistics $stats -Result "Enriched"
$summary = Get-StatisticsSummary -Statistics $stats
Write-Host "Success Rate: $($summary.EnrichmentSuccessRate)%"
```

#### [Invoke-SBOMCache.psm1](../../src/security/Invoke-SBOMCache.psm1)
Cache management for package metadata and vulnerability results.

**Functions:**
- `Initialize-SBOMCache` - Create empty cache hashtable
- `Get-CachedPackage` - Retrieve cached data
- `Set-CachedPackage` - Store data in cache
- `Import-SBOMCache` - Load cache from JSON file
- `Export-SBOMCache` - Save cache to JSON file
- `Clear-SBOMCache` - Remove all cache entries

**Example:**
```powershell
$cache = Initialize-SBOMCache
Set-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21" -Data $packageInfo
Export-SBOMCache -Cache $cache -FilePath "cache.json"
```

#### [Get-FileHashReport.psm1](../../src/security/Get-FileHashReport.psm1)
Cryptographic hash generation and reporting for file integrity verification.

**Functions:**
- `Get-MultiAlgorithmHash` - Calculate SHA256, SHA1, MD5 for a file
- `New-HashReport` - Generate report for multiple files
- `Export-HashReport` - Save report as text file
- `ConvertTo-HashMarkdown` - Convert report to markdown format

**Example:**
```powershell
$hashes = Get-MultiAlgorithmHash -FilePath "output.md"
$report = New-HashReport -Files @("file1.txt", "file2.json")
Export-HashReport -Report $report -OutputPath "hashes.txt"
```

### Package Registry Integration

#### [Get-PackageRegistryInfo.psm1](../../src/security/Get-PackageRegistryInfo.psm1)
Fetch metadata from NPM and NuGet registries.

**Functions:**
- `Get-NpmPackageInfo` - Query NPM registry API
- `Get-NuGetPackageInfo` - Query NuGet API and .nuspec files
- `Get-PackageInfo` - Unified interface for both registries

**Example:**
```powershell
$info = Get-NpmPackageInfo -PackageName "lodash" -Version "4.17.21" -Cache $cache -Statistics $stats
Write-Host "License: $($info.License), Author: $($info.Author)"
```

**Returns:** Hashtable with keys: `License`, `Author`, `Homepage`, `Repository`, `Description`, `ProjectUrl`, `LicenseUrl`, `Copyright`

### Vulnerability Scanning

#### [Get-PackageVulnerability.psm1](../../src/security/Get-PackageVulnerability.psm1)
Security vulnerability detection via OSV database and dotnet CLI.

**Functions:**
- `Get-NpmVulnerabilities` - Check NPM packages via OSV API
- `Get-NuGetVulnerabilities` - Check NuGet packages via OSV API
- `Get-DotnetVulnerabilities` - Scan .NET solutions with `dotnet list package --vulnerable`

**Example:**
```powershell
$vulns = Get-NpmVulnerabilities -PackageName "lodash" -Version "4.17.20"
if ($vulns.HasVulnerabilities) {
    Write-Warning "$($vulns.Vulnerabilities.Count) vulnerabilities found"
}

$dotnetVulns = Get-DotnetVulnerabilities -SolutionPath ".\MySolution.sln"
```

**Returns:** Hashtable with:
- `HasVulnerabilities` (bool)
- `Vulnerabilities` (array) - Each contains: `Id`, `CVE`, `Summary`, `Details`, `Severity`, `CVSSScore`, `Published`, `Modified`, `References`

### Markdown Generation

#### [ConvertTo-SBOMMarkdown.psm1](../../src/security/ConvertTo-SBOMMarkdown.psm1)
Transform SBOM data into formatted Markdown documentation.

**Functions:**
- `ConvertTo-PackageMarkdown` - Generate markdown for single package
- `New-VulnerabilitySummaryMarkdown` - Create vulnerability alert section
- `New-StatisticsMarkdown` - Generate statistics summary section

**Example:**
```powershell
$packageMarkdown = ConvertTo-PackageMarkdown -Package $pkg -EnrichedData $info -VulnerabilityData $vulns
$vulnSection = New-VulnerabilitySummaryMarkdown -VulnerablePackages $vulnerableList
$statsSection = New-StatisticsMarkdown -Statistics (Get-StatisticsSummary -Statistics $stats)
```

## Testing

All modules include comprehensive Pester v5 tests.

### Run All Security Module Tests
```powershell
Invoke-Pester -Path .\tests\security\
```

### Run Specific Module Tests
```powershell
Invoke-Pester -Path .\tests\security\Measure-SBOMStatistics.Tests.ps1
Invoke-Pester -Path .\tests\security\Invoke-SBOMCache.Tests.ps1
Invoke-Pester -Path .\tests\security\Get-FileHashReport.Tests.ps1
```

### Test Coverage Summary

| Module | Test File | Coverage |
|--------|-----------|----------|
| Statistics | `Measure-SBOMStatistics.Tests.ps1` | ✓ All functions |
| Cache | `Invoke-SBOMCache.Tests.ps1` | ✓ All functions |
| Hash Report | `Get-FileHashReport.Tests.ps1` | ✓ All functions |
| Registry Info | *Planned* | Mock API calls |
| Vulnerabilities | *Planned* | Mock OSV API + CLI |
| Markdown | *Planned* | Output validation |

## Integration Example

Complete workflow using all modules:

```powershell
# Import all security modules
Import-Module .\src\security\Measure-SBOMStatistics.psm1
Import-Module .\src\security\Invoke-SBOMCache.psm1
Import-Module .\src\security\Get-PackageRegistryInfo.psm1
Import-Module .\src\security\Get-PackageVulnerability.psm1
Import-Module .\src\security\ConvertTo-SBOMMarkdown.psm1
Import-Module .\src\security\Get-FileHashReport.psm1

# Initialize
$stats = Initialize-SBOMStatistics
$cache = Import-SBOMCache -FilePath "cache.json"

# Load SBOM
$sbom = Get-Content "manifest.json" | ConvertFrom-Json

# Process each package
foreach ($package in $sbom.packages) {
    # Enrich metadata
    if ($package.name) {
        $enrichedData = Get-PackageInfo -PackageName $package.name `
                                        -Version $package.versionInfo `
                                        -PackageType "NPM" `
                                        -Cache $cache `
                                        -Statistics $stats
        
        # Check vulnerabilities
        $vulnData = Get-NpmVulnerabilities -PackageName $package.name `
                                           -Version $package.versionInfo `
                                           -Cache $cache `
                                           -Statistics $stats
        
        # Generate markdown
        $markdown = ConvertTo-PackageMarkdown -Package $package `
                                              -EnrichedData $enrichedData `
                                              -VulnerabilityData $vulnData
    }
}

# Save cache
Export-SBOMCache -Cache $cache -FilePath "cache.json"

# Generate reports
$summary = Get-StatisticsSummary -Statistics $stats
$statsMarkdown = New-StatisticsMarkdown -Statistics $summary

$hashReport = New-HashReport -Files @("output.md", "manifest.json")
Export-HashReport -Report $hashReport -OutputPath "hashes.txt"
```

## Architecture

### Design Principles

1. **Stateless Functions**: Modules don't maintain internal state; caller manages objects
2. **Dependency Injection**: Cache, statistics passed as parameters
3. **Testability**: All external dependencies (APIs, CLI) mockable
4. **Single Responsibility**: Each module focuses on one concern
5. **Standard Returns**: Consistent object structures across modules

### Module Dependencies

```
ConvertTo-SBOMMarkdown
  ├── Get-PackageRegistryInfo
  │   ├── Invoke-SBOMCache
  │   └── Measure-SBOMStatistics
  ├── Get-PackageVulnerability
  │   ├── Invoke-SBOMCache
  │   └── Measure-SBOMStatistics
  └── Measure-SBOMStatistics

Get-FileHashReport (independent)
Invoke-SBOMCache (independent)
Measure-SBOMStatistics (independent)
```

## Original Script

The original monolithic script `sbom2markdown.ps1` remains unchanged. These modules extract its core functionality into reusable, testable components suitable for inclusion in the BuildUtils library.

## Future Enhancements

- [ ] Add retry logic with exponential backoff for API calls
- [ ] Support additional package registries (PyPI, crates.io)
- [ ] Parallel processing for large SBOM files
- [ ] Custom vulnerability database integration
- [ ] HTML report generation
- [ ] SBOM diff/comparison utilities
