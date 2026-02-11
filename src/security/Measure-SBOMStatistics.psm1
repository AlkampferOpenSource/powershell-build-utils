<#
.SYNOPSIS
Initialize and track SBOM processing statistics

.DESCRIPTION
Provides functions to create, update, and retrieve statistics for SBOM processing operations.
Tracks enrichment attempts (successful, failed, cached) and vulnerability scanning results
(checked, vulnerable, safe, failed, severity breakdown).

.EXAMPLE
$stats = Initialize-SBOMStatistics
Update-EnrichmentStats -Statistics $stats -Result "Enriched"
$summary = Get-StatisticsSummary -Statistics $stats

.NOTES
Statistics are returned as PSCustomObjects that can be passed between functions.
This module does not maintain internal state - callers must manage statistics objects.
#>

function Initialize-SBOMStatistics {
    <#
    .SYNOPSIS
    Create a new statistics tracking object
    
    .DESCRIPTION
    Initializes all counters to zero for enrichment and vulnerability scanning statistics.
    
    .OUTPUTS
    PSCustomObject with nested hashtables for all statistics categories
    
    .EXAMPLE
    $stats = Initialize-SBOMStatistics
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()
    
    return [PSCustomObject]@{
        Enrichment = @{
            Total = 0
            Enriched = 0
            Failed = 0
            Cached = 0
        }
        Vulnerability = @{
            Checked = 0
            Vulnerable = 0
            Safe = 0
            Failed = 0
        }
        DotnetVulnerability = @{
            Total = 0
            Critical = 0
            High = 0
            Moderate = 0
            Low = 0
        }
        NpmVulnerability = @{
            Total = 0
            Critical = 0
            High = 0
            Moderate = 0
            Low = 0
        }
    }
}

function Update-EnrichmentStats {
    <#
    .SYNOPSIS
    Update enrichment statistics counters
    
    .DESCRIPTION
    Increments the appropriate enrichment counter based on the operation result.
    Always increments the Total counter.
    
    .PARAMETER Statistics
    The statistics object to update (from Initialize-SBOMStatistics)
    
    .PARAMETER Result
    The enrichment result: "Enriched", "Failed", or "Cached"
    
    .EXAMPLE
    Update-EnrichmentStats -Statistics $stats -Result "Enriched"
    
    .EXAMPLE
    Update-EnrichmentStats -Statistics $stats -Result "Cached"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Statistics,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("Enriched", "Failed", "Cached")]
        [string] $Result
    )
    
    $Statistics.Enrichment.Total++
    $Statistics.Enrichment[$Result]++
}

function Update-VulnerabilityStats {
    <#
    .SYNOPSIS
    Update vulnerability scanning statistics
    
    .DESCRIPTION
    Increments vulnerability scan counters based on scan result.
    Always increments the Checked counter.
    
    .PARAMETER Statistics
    The statistics object to update
    
    .PARAMETER Result
    The scan result: "Vulnerable", "Safe", or "Failed"
    
    .EXAMPLE
    Update-VulnerabilityStats -Statistics $stats -Result "Vulnerable"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Statistics,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("Vulnerable", "Safe", "Failed")]
        [string] $Result
    )
    
    $Statistics.Vulnerability.Checked++
    $Statistics.Vulnerability[$Result]++
}

function Update-DotnetVulnerabilityStats {
    <#
    .SYNOPSIS
    Update dotnet-specific vulnerability statistics by severity
    
    .DESCRIPTION
    Increments counters for vulnerabilities found by dotnet CLI.
    Tracks severity breakdown (Critical, High, Moderate, Low).
    
    .PARAMETER Statistics
    The statistics object to update
    
    .PARAMETER Severity
    The vulnerability severity level
    
    .EXAMPLE
    Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Critical"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Statistics,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("Critical", "High", "Moderate", "Low")]
        [string] $Severity
    )
    
    $Statistics.DotnetVulnerability.Total++
    $Statistics.DotnetVulnerability[$Severity]++
}

function Update-NpmVulnerabilityStats {
    <#
    .SYNOPSIS
    Update npm-specific vulnerability statistics by severity

    .DESCRIPTION
    Increments counters for vulnerabilities found by npm audit.
    Tracks severity breakdown (Critical, High, Moderate, Low).

    .PARAMETER Statistics
    The statistics object to update

    .PARAMETER Severity
    The vulnerability severity level

    .EXAMPLE
    Update-NpmVulnerabilityStats -Statistics $stats -Severity "High"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Statistics,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Critical", "High", "Moderate", "Low")]
        [string] $Severity
    )

    $Statistics.NpmVulnerability.Total++
    $Statistics.NpmVulnerability[$Severity]++
}

function Get-StatisticsSummary {
    <#
    .SYNOPSIS
    Retrieve a formatted summary of statistics
    
    .DESCRIPTION
    Returns the current statistics object with calculated rates and summaries.
    Adds computed properties like success rates and vulnerability percentages.
    
    .PARAMETER Statistics
    The statistics object to summarize
    
    .OUTPUTS
    PSCustomObject with statistics and calculated summary values
    
    .EXAMPLE
    $summary = Get-StatisticsSummary -Statistics $stats
    Write-Host "Success Rate: $($summary.EnrichmentSuccessRate)%"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Statistics
    )
    
    # Calculate success rates
    $enrichmentSuccessRate = if ($Statistics.Enrichment.Total -gt 0) {
        [math]::Round(($Statistics.Enrichment.Enriched / $Statistics.Enrichment.Total) * 100, 2)
    } else { 0 }
    
    $vulnerabilityRate = if ($Statistics.Vulnerability.Checked -gt 0) {
        [math]::Round(($Statistics.Vulnerability.Vulnerable / $Statistics.Vulnerability.Checked) * 100, 2)
    } else { 0 }
    
    return [PSCustomObject]@{
        Enrichment = $Statistics.Enrichment
        Vulnerability = $Statistics.Vulnerability
        DotnetVulnerability = $Statistics.DotnetVulnerability
        NpmVulnerability = $Statistics.NpmVulnerability
        EnrichmentSuccessRate = $enrichmentSuccessRate
        VulnerabilityRate = $vulnerabilityRate
    }
}

Export-ModuleMember -Function Initialize-SBOMStatistics, Update-EnrichmentStats, Update-VulnerabilityStats, Update-DotnetVulnerabilityStats, Update-NpmVulnerabilityStats, Get-StatisticsSummary
