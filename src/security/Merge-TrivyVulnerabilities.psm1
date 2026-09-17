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

    # The leading comma matters on every return path, not just the happy one: a bare `return @()`
    # is unrolled by the pipeline to *nothing*, so the caller's variable ends up $null and binding
    # it to Merge-VulnerabilitiesSourceEntries -NewEntries fails (AllowEmptyCollection permits an
    # empty array, not $null).
    if (-not (Test-Path $TrivyReportPath)) {
        Write-Warning "Trivy report not found at: $TrivyReportPath"
        return ,@()
    }

    try {
        $report = Get-Content -Path $TrivyReportPath -Raw | ConvertFrom-Json
    }
    catch {
        Write-Warning "Failed to parse Trivy report at ${TrivyReportPath}: $_"
        return ,@()
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

function Get-VulnerabilityEntryKey {
    <#
    .SYNOPSIS
    Build the dedup keys for a vulnerabilitiesSource entry (module-private helper).

    .DESCRIPTION
    An entry is identified by package name (case-insensitive) plus advisory id, scoped by the
    versions it applies to: an exact `packageVersion` (dotnet's resolvedVersion, Trivy's
    InstalledVersion) pins one installed version, a `vulnerableVersionRange` (npm audit's range)
    names a set of them, and an entry with neither is unscoped.

    The scope goes into the key as raw text -- two entries are the same finding only when their
    scopes are spelled identically. Nothing here interprets a range.

    .PARAMETER Entry
    An externalVulnerability entry, either an ordered hashtable we just built or a PSCustomObject
    read back from an existing JSON file.

    .OUTPUTS
    Hashtable with Base ("name|id"), Full ("name|id|version-scope") and Kind ('exact', 'range' or
    'none').
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    $name = if ($null -ne $Entry.packageName) { ([string]$Entry.packageName).ToLowerInvariant() } else { '' }
    $base = "$name|$($Entry.id)"

    if ($Entry.packageVersion) {
        return @{ Base = $base; Full = "$base|v=$([string]$Entry.packageVersion)"; Kind = 'exact' }
    }
    if ($Entry.vulnerableVersionRange) {
        return @{ Base = $base; Full = "$base|r=$([string]$Entry.vulnerableVersionRange)"; Kind = 'range' }
    }
    return @{ Base = $base; Full = "$base|*"; Kind = 'none' }
}

function Merge-VulnerabilitiesSourceEntries {
    <#
    .SYNOPSIS
    Merge extra externalVulnerability entries into an existing vulnerabilitiesSource file.

    .DESCRIPTION
    Dedupes by (packageName, id, version scope), case-insensitive on packageName. Entries already
    present in the existing file are left completely untouched -- the scan script's own finding
    wins on overlap; only genuinely new entries from -NewEntries are appended.

    Two entries are the same finding only when their version scopes match as text. An exact
    packageVersion therefore suppresses only that same version, so a report covering A@1.0.0 and
    A@2.0.0 keeps one entry per version instead of collapsing to whichever came first. An entry
    with no version at all is about the package as a whole, and does suppress any incoming
    version of it.

    An existing vulnerableVersionRange (npm audit's "<=4.17.20") is deliberately NOT matched
    against an incoming exact packageVersion (Trivy's "4.17.20"), so where npm and Trivy overlap
    the file ends up holding both entries. Deciding that overlap correctly means implementing npm
    range semantics in full -- prerelease admission, partial operand expansion, X-ranges -- and a
    subtly wrong answer silently discards a real vulnerability. A duplicate entry is noise a
    reader can see and reconcile; a dropped finding leaves nothing behind at all.

    Rewrites the file in place with the merged array and, when the file has a companion
    .hash.txt, regenerates it so the recorded hashes describe the merged content.

    Throws without touching the file if existing data cannot be read or parsed: continuing would
    overwrite the previous scan findings with just the new entries (or an empty array).

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
            # -ErrorAction Stop is what makes the catch below reachable: a locked file or a
            # denied ACL is a *non-terminating* error, so without it Get-Content just writes to
            # the error stream, $raw stays $null, and we fall through to the overwrite.
            $raw = Get-Content -Path $ExistingFilePath -Raw -ErrorAction Stop
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
                if ($parsed) {
                    $existing = @($parsed)
                }
            }
        }
        catch {
            # Swallowing this would leave $existing empty and rewrite the file with only the new
            # entries -- or [] when there are none -- destroying the scan findings we were asked
            # to merge into, while still reporting a successful merge.
            throw "Failed to read existing vulnerabilitiesSource file at ${ExistingFilePath}: $($_.Exception.Message). Refusing to overwrite it."
        }
    }
    else {
        Write-Verbose "No existing file at ${ExistingFilePath}; treating as empty"
    }

    # Scoped keys ("name|id|version-scope") identify one specific finding, compared as text. The
    # one entry that subsumes others is the unscoped one, which is about the package as a whole.
    #
    # A range is deliberately never matched against an incoming exact version: see .DESCRIPTION.
    $seenKeys = [System.Collections.Generic.HashSet[string]]::new()
    $unscopedKeys = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($item in $existing) {
        $itemKey = Get-VulnerabilityEntryKey -Entry $item
        [void]$seenKeys.Add($itemKey.Full)
        if ($itemKey.Kind -eq 'none') { [void]$unscopedKeys.Add($itemKey.Base) }
    }

    $merged = [System.Collections.ArrayList]::new()
    foreach ($item in $existing) { [void]$merged.Add($item) }

    $added = 0
    $skipped = 0
    foreach ($newEntry in $NewEntries) {
        $newKey = Get-VulnerabilityEntryKey -Entry $newEntry
        if ($seenKeys.Contains($newKey.Full) -or $unscopedKeys.Contains($newKey.Base)) {
            $skipped++
            continue
        }

        [void]$seenKeys.Add($newKey.Full)
        if ($newKey.Kind -eq 'none') { [void]$unscopedKeys.Add($newKey.Base) }
        [void]$merged.Add($newEntry)
        $added++
    }

    $json = ConvertTo-Json -InputObject $merged.ToArray() -Depth 10
    $json | Out-File -FilePath $ExistingFilePath -Encoding UTF8 -Force

    # ConvertTo-VulnerabilitiesSourceJson drops a .hash.txt next to the file it writes. We have
    # just rewritten that file, so without this the recorded SHA256/SHA1/MD5 and size describe
    # the pre-merge revision and the supplied integrity report is simply wrong.
    if (Test-Path "$ExistingFilePath.hash.txt") {
        Write-FileHashReport -FilePath $ExistingFilePath
    }

    return @{
        Added   = $added
        Skipped = $skipped
        Total   = $merged.Count
    }
}

Export-ModuleMember -Function ConvertFrom-TrivyReport, Merge-VulnerabilitiesSourceEntries
