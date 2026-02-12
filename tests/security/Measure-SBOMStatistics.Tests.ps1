BeforeAll {
    # Import the module
    Import-Module "$PSScriptRoot\..\..\src\security\Measure-SBOMStatistics.psm1" -Force
}

Describe "Measure-SBOMStatistics" {
    Context "When initializing statistics" {
        It "Should create a statistics object with all counters at zero" {
            $stats = Initialize-SBOMStatistics
            
            $stats | Should -Not -BeNullOrEmpty
            $stats.Enrichment | Should -Not -BeNullOrEmpty
            $stats.Vulnerability | Should -Not -BeNullOrEmpty
            $stats.DotnetVulnerability | Should -Not -BeNullOrEmpty
            
            $stats.Enrichment.Total | Should -Be 0
            $stats.Enrichment.Enriched | Should -Be 0
            $stats.Enrichment.Failed | Should -Be 0
            $stats.Enrichment.Cached | Should -Be 0
        }
        
        It "Should create independent statistics objects" {
            $stats1 = Initialize-SBOMStatistics
            $stats2 = Initialize-SBOMStatistics
            
            Update-EnrichmentStats -Statistics $stats1 -Result "Enriched"
            
            $stats1.Enrichment.Enriched | Should -Be 1
            $stats2.Enrichment.Enriched | Should -Be 0
        }
    }
    
    Context "When updating enrichment statistics" {
        BeforeEach {
            $stats = Initialize-SBOMStatistics
        }
        
        It "Should increment Total and Enriched counters" {
            Update-EnrichmentStats -Statistics $stats -Result "Enriched"
            
            $stats.Enrichment.Total | Should -Be 1
            $stats.Enrichment.Enriched | Should -Be 1
            $stats.Enrichment.Failed | Should -Be 0
            $stats.Enrichment.Cached | Should -Be 0
        }
        
        It "Should increment Total and Failed counters" {
            Update-EnrichmentStats -Statistics $stats -Result "Failed"
            
            $stats.Enrichment.Total | Should -Be 1
            $stats.Enrichment.Failed | Should -Be 1
            $stats.Enrichment.Enriched | Should -Be 0
        }
        
        It "Should increment Total and Cached counters" {
            Update-EnrichmentStats -Statistics $stats -Result "Cached"
            
            $stats.Enrichment.Total | Should -Be 1
            $stats.Enrichment.Cached | Should -Be 1
        }
        
        It "Should handle multiple updates correctly" {
            Update-EnrichmentStats -Statistics $stats -Result "Enriched"
            Update-EnrichmentStats -Statistics $stats -Result "Enriched"
            Update-EnrichmentStats -Statistics $stats -Result "Failed"
            Update-EnrichmentStats -Statistics $stats -Result "Cached"
            
            $stats.Enrichment.Total | Should -Be 4
            $stats.Enrichment.Enriched | Should -Be 2
            $stats.Enrichment.Failed | Should -Be 1
            $stats.Enrichment.Cached | Should -Be 1
        }
        
        It "Should throw for invalid result values" {
            { Update-EnrichmentStats -Statistics $stats -Result "InvalidValue" } | Should -Throw
        }
    }
    
    Context "When updating vulnerability statistics" {
        BeforeEach {
            $stats = Initialize-SBOMStatistics
        }
        
        It "Should increment Checked and Vulnerable counters" {
            Update-VulnerabilityStats -Statistics $stats -Result "Vulnerable"
            
            $stats.Vulnerability.Checked | Should -Be 1
            $stats.Vulnerability.Vulnerable | Should -Be 1
            $stats.Vulnerability.Safe | Should -Be 0
        }
        
        It "Should increment Checked and Safe counters" {
            Update-VulnerabilityStats -Statistics $stats -Result "Safe"
            
            $stats.Vulnerability.Checked | Should -Be 1
            $stats.Vulnerability.Safe | Should -Be 1
            $stats.Vulnerability.Vulnerable | Should -Be 0
        }
        
        It "Should handle multiple scans" {
            Update-VulnerabilityStats -Statistics $stats -Result "Safe"
            Update-VulnerabilityStats -Statistics $stats -Result "Vulnerable"
            Update-VulnerabilityStats -Statistics $stats -Result "Safe"
            Update-VulnerabilityStats -Statistics $stats -Result "Failed"
            
            $stats.Vulnerability.Checked | Should -Be 4
            $stats.Vulnerability.Safe | Should -Be 2
            $stats.Vulnerability.Vulnerable | Should -Be 1
            $stats.Vulnerability.Failed | Should -Be 1
        }
    }
    
    Context "When updating dotnet vulnerability statistics" {
        BeforeEach {
            $stats = Initialize-SBOMStatistics
        }
        
        It "Should increment Total and Critical counters" {
            Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Critical"
            
            $stats.DotnetVulnerability.Total | Should -Be 1
            $stats.DotnetVulnerability.Critical | Should -Be 1
        }
        
        It "Should track all severity levels" {
            Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Critical"
            Update-DotnetVulnerabilityStats -Statistics $stats -Severity "High"
            Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Moderate"
            Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Low"
            
            $stats.DotnetVulnerability.Total | Should -Be 4
            $stats.DotnetVulnerability.Critical | Should -Be 1
            $stats.DotnetVulnerability.High | Should -Be 1
            $stats.DotnetVulnerability.Moderate | Should -Be 1
            $stats.DotnetVulnerability.Low | Should -Be 1
        }
        
        It "Should handle multiple vulnerabilities of same severity" {
            Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Critical"
            Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Critical"
            Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Critical"
            
            $stats.DotnetVulnerability.Total | Should -Be 3
            $stats.DotnetVulnerability.Critical | Should -Be 3
        }
    }
    
    Context "When getting statistics summary" {
        BeforeEach {
            $stats = Initialize-SBOMStatistics
        }
        
        It "Should return summary with calculated rates" {
            Update-EnrichmentStats -Statistics $stats -Result "Enriched"
            Update-EnrichmentStats -Statistics $stats -Result "Enriched"
            Update-EnrichmentStats -Statistics $stats -Result "Failed"
            
            Update-VulnerabilityStats -Statistics $stats -Result "Safe"
            Update-VulnerabilityStats -Statistics $stats -Result "Vulnerable"
            
            $summary = Get-StatisticsSummary -Statistics $stats
            
            $summary | Should -Not -BeNullOrEmpty
            $summary.EnrichmentSuccessRate | Should -Be 66.67
            $summary.VulnerabilityRate | Should -Be 50
        }
        
        It "Should calculate 100% success rate correctly" {
            Update-EnrichmentStats -Statistics $stats -Result "Enriched"
            Update-EnrichmentStats -Statistics $stats -Result "Enriched"
            
            $summary = Get-StatisticsSummary -Statistics $stats
            
            $summary.EnrichmentSuccessRate | Should -Be 100
        }
        
        It "Should handle zero totals without errors" {
            $summary = Get-StatisticsSummary -Statistics $stats
            
            $summary.EnrichmentSuccessRate | Should -Be 0
            $summary.VulnerabilityRate | Should -Be 0
        }
        
        It "Should include all original statistics" {
            Update-EnrichmentStats -Statistics $stats -Result "Enriched"
            
            $summary = Get-StatisticsSummary -Statistics $stats
            
            $summary.Enrichment | Should -Not -BeNullOrEmpty
            $summary.Vulnerability | Should -Not -BeNullOrEmpty
            $summary.DotnetVulnerability | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "When using statistics in realistic scenario" {
        It "Should track complete SBOM processing workflow" {
            $stats = Initialize-SBOMStatistics
            
            # Simulate enrichment of 100 packages
            1..70 | ForEach-Object { Update-EnrichmentStats -Statistics $stats -Result "Enriched" }
            1..20 | ForEach-Object { Update-EnrichmentStats -Statistics $stats -Result "Cached" }
            1..10 | ForEach-Object { Update-EnrichmentStats -Statistics $stats -Result "Failed" }
            
            # Simulate vulnerability scanning
            1..80 | ForEach-Object { Update-VulnerabilityStats -Statistics $stats -Result "Safe" }
            1..15 | ForEach-Object { Update-VulnerabilityStats -Statistics $stats -Result "Vulnerable" }
            1..5 | ForEach-Object { Update-VulnerabilityStats -Statistics $stats -Result "Failed" }
            
            # Simulate dotnet vulnerabilities
            1..2 | ForEach-Object { Update-DotnetVulnerabilityStats -Statistics $stats -Severity "Critical" }
            1..3 | ForEach-Object { Update-DotnetVulnerabilityStats -Statistics $stats -Severity "High" }
            
            $summary = Get-StatisticsSummary -Statistics $stats
            
            $summary.Enrichment.Total | Should -Be 100
            $summary.Vulnerability.Checked | Should -Be 100
            $summary.DotnetVulnerability.Total | Should -Be 5
            $summary.EnrichmentSuccessRate | Should -Be 70
            $summary.VulnerabilityRate | Should -Be 15
        }
    }
}
