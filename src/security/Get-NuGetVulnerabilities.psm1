<#
.SYNOPSIS
Query OSV for NuGet package vulnerabilities.

.DESCRIPTION
Calls the OSV API to fetch vulnerability information for a given NuGet package and version.
This function intentionally does NOT cache results.

.PARAMETER PackageName
Name of the NuGet package to query.

.PARAMETER Version
Version string of the package to query.

.EXAMPLE
Get-NuGetVulnerabilities -PackageName "Newtonsoft.Json" -Version "12.0.3"
#>
function Get-NuGetVulnerabilities {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PackageName,

        [Parameter(Mandatory = $true)]
        [string]$Version
    )

    try {
        # Increment statistics if available
        if ($script:vulnerabilityStats -and $script:vulnerabilityStats.ContainsKey('Checked')) {
            $script:vulnerabilityStats.Checked++
        }

        # Query OSV API for NuGet vulnerabilities
        $osvUrl = "https://api.osv.dev/v1/query"
        $body = @{
            package = @{
                name = $PackageName
                ecosystem = "NuGet"
            }
            version = $Version
        } | ConvertTo-Json -Depth 5

        $response = Invoke-RestMethod -Uri $osvUrl -Method Post -Body $body -ContentType "application/json" -TimeoutSec 10 -ErrorAction Stop

        $vulnerabilities = @()

        if ($response.vulns -and $response.vulns.Count -gt 0) {
            foreach ($vuln in $response.vulns) {
                $severity = "UNKNOWN"
                $cvssScore = "N/A"

                # Extract severity from database_specific or severity array
                if ($vuln.database_specific -and $vuln.database_specific.severity) {
                    $severity = $vuln.database_specific.severity
                }
                elseif ($vuln.severity -and $vuln.severity.Count -gt 0) {
                    $severity = $vuln.severity[0].type
                    $cvssScore = $vuln.severity[0].score
                }

                # Get CVE ID if available
                $cveId = "N/A"
                if ($vuln.aliases -and $vuln.aliases.Count -gt 0) {
                    $cveId = ($vuln.aliases | Where-Object { $_ -match "^CVE-" }) | Select-Object -First 1
                    if (-not $cveId) {
                        $cveId = $vuln.aliases[0]
                    }
                }

                $vulnerabilities += @{
                    Id = $vuln.id
                    CVE = $cveId
                    Summary = $vuln.summary
                    Details = $vuln.details
                    Severity = $severity
                    CVSSScore = $cvssScore
                    Published = $vuln.published
                    Modified = $vuln.modified
                    References = $vuln.references
                }
            }

            if ($script:vulnerabilityStats -and $script:vulnerabilityStats.ContainsKey('Vulnerable')) {
                $script:vulnerabilityStats.Vulnerable++
            }
        }
        else {
            if ($script:vulnerabilityStats -and $script:vulnerabilityStats.ContainsKey('Safe')) {
                $script:vulnerabilityStats.Safe++
            }
        }

        return @{
            HasVulnerabilities = ($vulnerabilities.Count -gt 0)
            Vulnerabilities = $vulnerabilities
        }
    }
    catch {
        Write-Verbose "Failed to check vulnerabilities for $PackageName@$Version : $_"
        if ($script:vulnerabilityStats -and $script:vulnerabilityStats.ContainsKey('Failed')) {
            $script:vulnerabilityStats.Failed++
        }
        return @{
            HasVulnerabilities = $false
            Vulnerabilities = @()
        }
    }
}

Export-ModuleMember -Function Get-NuGetVulnerabilities
