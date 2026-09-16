<#
.SYNOPSIS
Fold Trivy's own vulnerability findings into the sbom-tool vulnerabilitiesSource files.

.DESCRIPTION
A dependency scan driven by Get-DotnetVulnerabilities / Get-NpmVulnerabilities and Trivy's
filesystem scan use different vulnerability sources (NuGet's advisory feed / npm audit + OSV,
vs. Trivy's own aggregated database) and different detection mechanisms, so they don't always
agree -- each finds things the other misses. This module extracts Trivy's nuget/npm findings from its JSON report
into the same externalVulnerability shape ConvertTo-VulnerabilitiesSourceJson produces
(see Get-PackageVulnerability.psm1), then merges them into the existing
dotnet-vulnerabilities.json / npm-vulnerabilities.json files, skipping anything already present
so the scan script's own data always wins on overlap.

.NOTES
Uses ConvertTo-VulnerabilitySourceSeverity from Get-PackageVulnerability.psm1. Both live in the
same module once BuildUtils is built, so importing BuildUtils is enough; when importing the
.psm1 files directly, import Get-PackageVulnerability.psm1 first.
#>

function ConvertFrom-TrivyReport {
    <#
    .SYNOPSIS
    Extract package vulnerabilities from a Trivy JSON report into the vulnerabilitiesSource schema.

    .DESCRIPTION
    Reads a Trivy `--format json` report and converts findings from a single ecosystem detector
    (nuget or npm) into externalVulnerability entries. Trivy's other detectors in this report
    (composer, pip, misconfig, secret, license) are out of scope for vulnerabilitiesSource, which
    only covers package-level vulnerabilities matched against SBOM packages by name/version.

    Both Trivy's nuget and npm detectors read lock files (packages.lock.json / package-lock.json),
    so InstalledVersion is always an exact resolved version -- unlike the scan script's own npm
    audit data, which reports a version range. Every entry here therefore uses packageVersion
    (exact), never vulnerableVersionRange.

    .PARAMETER TrivyReportPath
    Path to a Trivy JSON report file (trivy --format json --output <path>).

    .PARAMETER Ecosystem
    Which Trivy detector's results to extract: 'nuget' or 'npm'.

    .OUTPUTS
    Array of ordered hashtables matching the externalVulnerability schema.

    .EXAMPLE
    $trivyNuget = ConvertFrom-TrivyReport -TrivyReportPath "trivy-results.json" -Ecosystem 'nuget'
    #>
    [CmdletBinding()]
    [OutputType([array])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $TrivyReportPath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('nuget', 'npm')]
        [string] $Ecosystem
    )

    if (-not (Test-Path $TrivyReportPath)) {
        Write-Warning "Trivy report not found at: $TrivyReportPath"
        return @()
    }

    try {
        $report = Get-Content -Path $TrivyReportPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Failed to parse Trivy report at ${TrivyReportPath}: $_"
        return @()
    }

    $entries = @()

    if (-not $report.Results) {
        Write-Verbose "Trivy report has no Results section"
        return ,$entries
    }

    foreach ($result in $report.Results) {
        if ($result.Type -ne $Ecosystem) { continue }
        if (-not $result.Vulnerabilities) { continue }

        foreach ($vuln in $result.Vulnerabilities) {
            $severity = ConvertTo-VulnerabilitySourceSeverity -Severity $vuln.Severity
            if (-not $severity) {
                Write-Warning "Skipping Trivy finding for $($vuln.PkgName): unmappable severity '$($vuln.Severity)'"
                continue
            }

            if (-not $vuln.VulnerabilityID) {
                Write-Warning "Skipping Trivy finding for $($vuln.PkgName): no VulnerabilityID"
                continue
            }

            $entry = [ordered]@{
                packageName = $vuln.PkgName
                id          = $vuln.VulnerabilityID
                severity    = $severity
            }

            if ($vuln.InstalledVersion) {
                $entry.packageVersion = $vuln.InstalledVersion
            }

            if ($vuln.VulnerabilityID -match '^CVE-\d{4}-\d{4,}$') {
                $entry.cveId = $vuln.VulnerabilityID
            }

            if ($vuln.Title) { $entry.summary = $vuln.Title }
            if ($vuln.Description) { $entry.description = $vuln.Description }
            if ($vuln.PrimaryURL) { $entry.url = $vuln.PrimaryURL }
            if ($vuln.FixedVersion) { $entry.fixedVersion = $vuln.FixedVersion }

            $cvssScore = $null
            if ($vuln.CVSS) {
                foreach ($sourceName in @('nvd', 'redhat', 'ghsa')) {
                    $source = $vuln.CVSS.$sourceName
                    if ($source -and $null -ne $source.V3Score) {
                        $cvssScore = [double]$source.V3Score
                        break
                    }
                }
            }
            if ($null -ne $cvssScore -and $cvssScore -ge 0 -and $cvssScore -le 10) {
                $entry.cvssScore = $cvssScore
            }

            if ($vuln.PublishedDate) { $entry.publishedAt = $vuln.PublishedDate }

            $entries += $entry
        }
    }

    # Leading comma is required: without it, PowerShell silently unwraps a 1-element array
    # return value to the bare element (then e.g. .Count on the caller's side would return
    # the *hashtable's key count* instead of 1) -- caught by testing with exactly one entry.
    return ,$entries
}

function Merge-VulnerabilitiesSourceEntries {
    <#
    .SYNOPSIS
    Merge extra externalVulnerability entries into an existing vulnerabilitiesSource file.

    .DESCRIPTION
    Dedupes by (packageName, id), case-insensitive on packageName. Entries already present in
    the existing file are left completely untouched -- the scan script's own finding wins on
    overlap; only genuinely new entries from -NewEntries are appended. Rewrites the file in
    place with the merged array.

    .PARAMETER ExistingFilePath
    Path to an existing vulnerabilitiesSource JSON file (as written by
    ConvertTo-VulnerabilitiesSourceJson). If missing or empty, treated as an empty array.

    .PARAMETER NewEntries
    Array of additional externalVulnerability entries (e.g. from ConvertFrom-TrivyReport) to
    merge in.

    .OUTPUTS
    Hashtable with keys: Added, Skipped, Total.

    .EXAMPLE
    $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath "dotnet-vulnerabilities.json" -NewEntries $trivyNuget
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        [string] $ExistingFilePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [array] $NewEntries
    )

    $existing = @()
    if (Test-Path $ExistingFilePath) {
        try {
            $raw = Get-Content -Path $ExistingFilePath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json
                if ($parsed) {
                    $existing = @($parsed)
                }
            }
        }
        catch {
            Write-Warning "Failed to parse existing vulnerabilitiesSource file at ${ExistingFilePath}: $_"
        }
    }
    else {
        Write-Verbose "No existing file at ${ExistingFilePath}; treating as empty"
    }

    $existingKeys = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($item in $existing) {
        $key = "$($item.packageName.ToLowerInvariant())|$($item.id)"
        [void]$existingKeys.Add($key)
    }

    $merged = [System.Collections.ArrayList]::new()
    foreach ($item in $existing) { [void]$merged.Add($item) }

    $added = 0
    $skipped = 0
    foreach ($newEntry in $NewEntries) {
        $key = "$($newEntry.packageName.ToLowerInvariant())|$($newEntry.id)"
        if ($existingKeys.Contains($key)) {
            $skipped++
            continue
        }
        [void]$existingKeys.Add($key)
        [void]$merged.Add($newEntry)
        $added++
    }

    $json = ConvertTo-Json -InputObject $merged.ToArray() -Depth 10
    $json | Out-File -FilePath $ExistingFilePath -Encoding UTF8 -Force

    return @{
        Added   = $added
        Skipped = $skipped
        Total   = $merged.Count
    }
}

Export-ModuleMember -Function ConvertFrom-TrivyReport, Merge-VulnerabilitiesSourceEntries
