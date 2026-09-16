BeforeAll {
    # ConvertFrom-TrivyReport calls ConvertTo-VulnerabilitySourceSeverity, which lives in
    # Get-PackageVulnerability.psm1 - import that one first when loading the .psm1 files
    # directly (in the built module both end up in the same BuildUtils.psm1).
    Import-Module "$PSScriptRoot\..\..\src\security\Get-PackageVulnerability.psm1" -Force
    Import-Module "$PSScriptRoot\..\..\src\security\Merge-TrivyVulnerabilities.psm1" -Force
}

Describe 'ConvertFrom-TrivyReport' {

    BeforeEach {
        $script:reportPath = Join-Path $TestDrive 'trivy-results.json'
    }

    It 'Extracts only the requested ecosystem' {
        @{
            Results = @(
                @{
                    Type            = 'nuget'
                    Vulnerabilities = @(
                        @{ PkgName = 'System.Drawing.Common'; InstalledVersion = '4.7.0'; VulnerabilityID = 'CVE-2021-24112'; Severity = 'CRITICAL' }
                    )
                },
                @{
                    Type            = 'npm'
                    Vulnerabilities = @(
                        @{ PkgName = 'lodash'; InstalledVersion = '4.17.20'; VulnerabilityID = 'CVE-2021-23337'; Severity = 'HIGH' }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:reportPath -Encoding utf8

        $nuget = ConvertFrom-TrivyReport -TrivyReportPath $script:reportPath -Ecosystem 'nuget'

        $nuget.Count | Should -Be 1
        $nuget[0].packageName | Should -Be 'System.Drawing.Common'
        $nuget[0].severity | Should -Be 'CRITICAL'
        # Trivy reads lock files, so the version is always exact - never a range.
        $nuget[0].packageVersion | Should -Be '4.7.0'
        $nuget[0].cveId | Should -Be 'CVE-2021-24112'
    }

    It 'Returns a one-element array without unwrapping it' {
        @{
            Results = @(
                @{
                    Type            = 'nuget'
                    Vulnerabilities = @(
                        @{ PkgName = 'Snappier'; InstalledVersion = '1.0.0'; VulnerabilityID = 'GHSA-xxxx-yyyy-zzzz'; Severity = 'HIGH' }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:reportPath -Encoding utf8

        $entries = ConvertFrom-TrivyReport -TrivyReportPath $script:reportPath -Ecosystem 'nuget'

        # Without the leading comma on the return, PowerShell unwraps this to the bare
        # hashtable and .Count would report the key count instead of 1.
        $entries.Count | Should -Be 1
        # A GHSA id is not a CVE, so cveId must not be set.
        $entries[0].Contains('cveId') | Should -BeFalse
    }

    It 'Picks the first available CVSS v3 score and ignores out-of-range values' {
        @{
            Results = @(
                @{
                    Type            = 'nuget'
                    Vulnerabilities = @(
                        @{
                            PkgName = 'A'; InstalledVersion = '1.0.0'; VulnerabilityID = 'CVE-2020-0001'; Severity = 'HIGH'
                            CVSS    = @{ redhat = @{ V3Score = 7.5 } }
                        },
                        @{
                            PkgName = 'B'; InstalledVersion = '2.0.0'; VulnerabilityID = 'CVE-2020-0002'; Severity = 'LOW'
                            CVSS    = @{ nvd = @{ V3Score = 42 } }
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:reportPath -Encoding utf8

        $entries = ConvertFrom-TrivyReport -TrivyReportPath $script:reportPath -Ecosystem 'nuget'

        ($entries | Where-Object packageName -eq 'A').cvssScore | Should -Be 7.5
        ($entries | Where-Object packageName -eq 'B').Contains('cvssScore') | Should -BeFalse
    }

    It 'Skips findings with an unmappable severity or no identifier' {
        @{
            Results = @(
                @{
                    Type            = 'nuget'
                    Vulnerabilities = @(
                        @{ PkgName = 'A'; InstalledVersion = '1.0.0'; VulnerabilityID = 'CVE-2020-0001'; Severity = 'UNKNOWN' },
                        @{ PkgName = 'B'; InstalledVersion = '1.0.0'; VulnerabilityID = ''; Severity = 'HIGH' },
                        @{ PkgName = 'C'; InstalledVersion = '1.0.0'; VulnerabilityID = 'CVE-2020-0003'; Severity = 'MEDIUM' }
                    )
                }
            )
        } | ConvertTo-Json -Depth 10 | Set-Content -Path $script:reportPath -Encoding utf8

        $entries = ConvertFrom-TrivyReport -TrivyReportPath $script:reportPath -Ecosystem 'nuget' -WarningAction SilentlyContinue

        $entries.Count | Should -Be 1
        $entries[0].packageName | Should -Be 'C'
        # MEDIUM is not a value the vulnerabilitiesSource schema accepts.
        $entries[0].severity | Should -Be 'MODERATE'
    }

    It 'Returns an empty array for a missing report instead of throwing' {
        $entries = ConvertFrom-TrivyReport -TrivyReportPath (Join-Path $TestDrive 'nope.json') -Ecosystem 'nuget' -WarningAction SilentlyContinue
        $entries.Count | Should -Be 0
    }
}

Describe 'Merge-VulnerabilitiesSourceEntries' {

    BeforeEach {
        $script:existingPath = Join-Path $TestDrive 'dotnet-vulnerabilities.json'
    }

    It 'Appends only entries that are not already present' {
        @(
            [ordered]@{ packageName = 'System.Drawing.Common'; id = 'CVE-2021-24112'; severity = 'CRITICAL' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $new = @(
            [ordered]@{ packageName = 'System.Drawing.Common'; id = 'CVE-2021-24112'; severity = 'HIGH' },
            [ordered]@{ packageName = 'Snappier'; id = 'GHSA-xxxx-yyyy-zzzz'; severity = 'HIGH' }
        )

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries $new

        $result.Added | Should -Be 1
        $result.Skipped | Should -Be 1
        $result.Total | Should -Be 2

        $merged = Get-Content -Raw $script:existingPath | ConvertFrom-Json
        # The existing entry wins on overlap: its severity must be untouched.
        ($merged | Where-Object packageName -eq 'System.Drawing.Common').severity | Should -Be 'CRITICAL'
    }

    It 'Matches package names case-insensitively' {
        @(
            [ordered]@{ packageName = 'AutoMapper'; id = 'CVE-2020-0001'; severity = 'HIGH' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'automapper'; id = 'CVE-2020-0001'; severity = 'HIGH' }
        )

        $result.Added | Should -Be 0
        $result.Skipped | Should -Be 1
    }

    It 'Treats a missing file as an empty set and writes all new entries' {
        $missing = Join-Path $TestDrive 'not-there.json'

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $missing -NewEntries @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2020-0001'; severity = 'LOW' }
        )

        $result.Added | Should -Be 1
        $result.Total | Should -Be 1
        Test-Path $missing | Should -BeTrue
    }

    It 'Leaves the file usable when there are no new entries' {
        @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2020-0001'; severity = 'LOW' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @()

        $result.Added | Should -Be 0
        $result.Total | Should -Be 1
        (Get-Content -Raw $script:existingPath | ConvertFrom-Json).Count | Should -Be 1
    }
}

Describe 'ConvertTo-VulnerabilitiesSourceJson' {

    It 'Writes dotnet scan data as exact-version entries' {
        $data = @{
            'System.Drawing.Common@4.7.0' = @{
                Name            = 'System.Drawing.Common'
                Version         = '4.7.0'
                Vulnerabilities = @(
                    @{ Severity = 'Critical'; CVE = 'CVE-2021-24112'; AdvisoryUrl = 'https://github.com/advisories/GHSA-rxg9-xrhp-64gj' }
                )
            }
        }

        $outputFile = Join-Path $TestDrive 'dotnet-vulnerabilities.json'
        $entries = ConvertTo-VulnerabilitiesSourceJson -VulnerabilityData $data -PackageVersionIsExact -OutputFile $outputFile

        $entries.Count | Should -Be 1
        $entries[0].packageVersion | Should -Be '4.7.0'
        $entries[0].severity | Should -Be 'CRITICAL'
        $entries[0].id | Should -Be 'CVE-2021-24112'
        Test-Path $outputFile | Should -BeTrue
        Test-Path "$outputFile.hash.txt" | Should -BeTrue
    }

    It 'Writes a version range when the version is not exact' {
        $data = @{
            'lodash@<=4.17.20' = @{
                Name            = 'lodash'
                Version         = '<=4.17.20'
                Vulnerabilities = @(
                    @{ Severity = 'high'; Id = 'GHSA-35jh-r3h4-6jhm' }
                )
            }
        }

        $entries = ConvertTo-VulnerabilitiesSourceJson -VulnerabilityData $data

        $entries[0].vulnerableVersionRange | Should -Be '<=4.17.20'
        $entries[0].Contains('packageVersion') | Should -BeFalse
    }

    It 'Skips entries the schema cannot represent' {
        $data = @{
            'A@1.0.0' = @{
                Name            = 'A'
                Version         = '1.0.0'
                Vulnerabilities = @(
                    @{ Severity = 'info'; Id = 'GHSA-aaaa-bbbb-cccc' },
                    @{ Severity = 'High' }
                )
            }
        }

        $entries = ConvertTo-VulnerabilitiesSourceJson -VulnerabilityData $data -WarningAction SilentlyContinue

        # "info" has no schema equivalent, and the second has no usable identifier.
        $entries.Count | Should -Be 0
    }
}

Describe 'ConvertTo-VulnerabilitySourceSeverity' {

    It 'Maps every accepted severity spelling' {
        ConvertTo-VulnerabilitySourceSeverity -Severity 'critical' | Should -Be 'CRITICAL'
        ConvertTo-VulnerabilitySourceSeverity -Severity 'High'     | Should -Be 'HIGH'
        ConvertTo-VulnerabilitySourceSeverity -Severity 'moderate' | Should -Be 'MODERATE'
        ConvertTo-VulnerabilitySourceSeverity -Severity 'MEDIUM'   | Should -Be 'MODERATE'
        ConvertTo-VulnerabilitySourceSeverity -Severity 'low'      | Should -Be 'LOW'
    }

    It 'Returns null for anything else, so callers can skip the entry' {
        ConvertTo-VulnerabilitySourceSeverity -Severity 'info'    | Should -BeNullOrEmpty
        ConvertTo-VulnerabilitySourceSeverity -Severity 'unknown' | Should -BeNullOrEmpty
        ConvertTo-VulnerabilitySourceSeverity -Severity ''        | Should -BeNullOrEmpty
        ConvertTo-VulnerabilitySourceSeverity -Severity $null     | Should -BeNullOrEmpty
    }
}
