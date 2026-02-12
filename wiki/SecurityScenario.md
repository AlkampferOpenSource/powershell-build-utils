# Dotnet Project

This is the scenario where you have a solution file in .NET and you want to generate SBOM and also a vulnerability report.

```powershell
# Import all the utils, then you can scan vulnerabilities with the command

$dotnetvulns = Get-DotnetVulnerabilities -SolutionPath '.../test.sln' -Statistics $stats -outputfile "c:\out\sbom\sbom-xxxx.json"

```

This actually generates a list of all vulnerabilities found in the solution projects, this is not really a sbom but it is something that should be added to a sbom report, so you can have a distinct json with all the vulnerabilities of all the projects in the solution.

It can be useful **to analyze the output, you can dump with ##vso command or whathever**. This is a sample code that simply output data to the console.

```powershell
if ($dotnetvulns.Count -eq 0) {
    Write-Output "✅ No vulnerabilities found!"
} else {
    Write-Output "⚠️  Found $($dotnetvulns.Count) vulnerable package(s)"
    
    # Output vulnerability summary
    foreach ($key in $dotnetvulns.Keys) {
        $pkg = $dotnetvulns[$key]
        Write-Output ""
        Write-Output "Package: $($pkg.Name) v$($pkg.Version)"
        Write-Output "  Source: $($pkg.Source)"
        Write-Output "  Vulnerabilities: $($pkg.Vulnerabilities.Count)"
        
        foreach ($vuln in $pkg.Vulnerabilities) {
            Write-Output "    - [$($vuln.Severity)] $($vuln.CVE) - $($vuln.AdvisoryUrl)"
        }
    }
}
```

Also we have some nice utilities to generate markdown

```powershell
$markdown = ConvertTo-DotnetVulnMarkdownReport 
    -VulnerabilityData $dotnetvulns `
    -OutputFile "/out/../vulnerability-report.md"
```powershell

# Npm and node project

The situation is similar to the dotnet one, this time internally the function will call `npm audit --json` to get the vulnerabilities for the project and output on a json file. Also standard parsing is done.

```powershell
# Import all the utils, then you can scan vulnerabilities with the command

$npmvulns = Get-NpmVulnerabilities -FolderPath "A:\Develop\Proximo\Jarvis\src\Frontend\Jarvis.UI" -OutputFile "S:\Temp\sbom\npm-scan.json"

ConvertTo-NpmVulnMarkdownReport -VulnerabilityData $npmvulns -OutputFile "npm-report.md"
```

## Enriching npm vulnerabilities with OSV data

The npm audit output provides basic vulnerability information, but you can enrich it with detailed CVE numbers, CVSS scores, and descriptions from the OSV API:

```powershell
# Basic enrichment without cache
$enriched = Add-NpmVulnerabilityEnrichment -VulnerabilityData $npmvulns

# Generate enriched markdown report
$markdown = ConvertTo-NpmVulnMarkdownReport -VulnerabilityData $enriched -OutputFile "S:\Temp\sbom\npm-vuln-report-enriched.md"
```

This will add:
- Additional CVE numbers not found in npm audit
- CVSS scores and severity ratings
- Detailed vulnerability descriptions
- Publication and modification dates
- Reference links to security advisories

### Using persistent cache for faster scans

For repeated scans or CI/CD pipelines, simply specify a cache file path - everything else is automatic:

```powershell
# Run npm scan
$npmvulns = Get-NpmVulnerabilities -FolderPath ".\my-project" -OutputFile "scan.json"

# Enrich with automatic cache management (specify file path only)
$enriched = Add-NpmVulnerabilityEnrichment -VulnerabilityData $npmvulns -CacheFilePath "S:\Temp\sbom\osv-cache.json"

# Generate report
ConvertTo-NpmVulnMarkdownReport -VulnerabilityData $enriched -OutputFile "report.md"
```

**The cache is fully automatic:**
- ✅ Loads existing cache on start (if file exists)
- ✅ Stores new OSV API responses during enrichment
- ✅ Saves cache automatically on completion
- ✅ No manual Import/Export needed

**Benefits:**
- First scan: Creates cache with OSV API data
- Subsequent scans: Instant results from cached data
- Dramatically faster in CI/CD pipelines
- Reduces load on OSV API servers

# Standard nuget bom

First of all you need to use the sbom tool to generate the file, then once the file is generated you can convert it to markdown with another command that enriches the data.

```powershell
 invoke-sbom -BinaryFolder binfolder -SourcesFolder sourcefolder -ProjectName POrojectName -ProjectVersion xxxx -Publisher NebulaSrl -OutputFolder S:\Temp\sbom -GenerateMarkdown

 convert-SpdxManifestToMarkdown -InputPath "S:\Temp\sbom\manifest.spdx.json"  -verbose -EnrichMetadata
 ```

