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

    It 'Returns a bindable empty array for a missing report instead of throwing' {
        $entries = ConvertFrom-TrivyReport -TrivyReportPath (Join-Path $TestDrive 'nope.json') -Ecosystem 'nuget' -WarningAction SilentlyContinue

        # $null.Count is also 0 in PowerShell 7, so asserting only the count would pass even
        # when the function returns nothing at all. What callers need is a real array: an
        # unwrapped `return @()` binds as $null and blows up Merge-VulnerabilitiesSourceEntries.
        ($null -ne $entries) | Should -BeTrue -Because 'an empty array is not $null'
        ($entries -is [array]) | Should -BeTrue
        $entries.Count | Should -Be 0
    }

    It 'Returns a bindable empty array for a malformed report' {
        Set-Content -Path $script:reportPath -Value '{ this is not json' -Encoding utf8

        $entries = ConvertFrom-TrivyReport -TrivyReportPath $script:reportPath -Ecosystem 'nuget' -WarningAction SilentlyContinue

        ($entries -is [array]) | Should -BeTrue
        $entries.Count | Should -Be 0
    }

    It 'Says so instead of quietly returning nothing when the report cannot be read' {
        # A locked report used to leave $report null, fall through the Results check and return
        # an empty array with no warning: every finding in it gone, and nothing to say why.
        @{ Results = @(@{ Type = 'nuget'; Vulnerabilities = @(
            @{ PkgName = 'A'; InstalledVersion = '1.0.0'; VulnerabilityID = 'CVE-2024-1111'; Severity = 'HIGH' }) }) } |
            ConvertTo-Json -Depth 10 | Set-Content -Path $script:reportPath -Encoding utf8

        $handle = [System.IO.File]::Open($script:reportPath, 'Open', 'ReadWrite', 'None')
        try {
            $entries = ConvertFrom-TrivyReport -TrivyReportPath $script:reportPath -Ecosystem 'nuget' `
                -WarningVariable readWarning -WarningAction SilentlyContinue
        }
        finally { $handle.Close() }

        $entries.Count | Should -Be 0
        "$readWarning" | Should -BeLike '*Failed to read Trivy report*'
    }

    It 'Returns something -NewEntries can actually bind on every failure path' {
        $target = Join-Path $TestDrive 'bind-check.json'
        Set-Content -Path $target -Value '[]' -Encoding utf8
        Set-Content -Path $script:reportPath -Value '{ this is not json' -Encoding utf8

        foreach ($report in @((Join-Path $TestDrive 'nope.json'), $script:reportPath)) {
            $entries = ConvertFrom-TrivyReport -TrivyReportPath $report -Ecosystem 'nuget' -WarningAction SilentlyContinue
            { Merge-VulnerabilitiesSourceEntries -ExistingFilePath $target -NewEntries $entries } |
                Should -Not -Throw
        }
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

    It 'Keeps one entry per installed version of the same advisory' {
        # Trivy reports the same advisory once per installed version; collapsing them would
        # leave the other SBOM package with no vulnerability association at all.
        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH'; packageVersion = '1.0.0' },
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH'; packageVersion = '2.0.0' }
        )

        $result.Added | Should -Be 2
        $result.Skipped | Should -Be 0

        $merged = @(Get-Content -Raw $script:existingPath | ConvertFrom-Json)
        ($merged.packageVersion | Sort-Object) | Should -Be @('1.0.0', '2.0.0')
    }

    It 'Still skips an incoming finding for a version already on file' {
        @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH'; packageVersion = '1.0.0' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'LOW'; packageVersion = '1.0.0' },
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'LOW'; packageVersion = '3.0.0' }
        )

        $result.Added | Should -Be 1
        $result.Skipped | Should -Be 1
    }

    It 'Keeps both entries when a range and an exact version overlap' {
        # npm audit reports a range ("<=4.17.20"), Trivy the resolved version ("4.17.20"). They
        # describe the same install, but proving that means implementing npm range semantics, and
        # a wrong answer there deletes a vulnerability record. Both entries are kept instead.
        @(
            [ordered]@{ packageName = 'lodash'; id = '1106913'; severity = 'HIGH'; vulnerableVersionRange = '<=4.17.20' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'lodash'; id = '1106913'; severity = 'HIGH'; packageVersion = '4.17.20' }
        )

        $result.Added | Should -Be 1
        $result.Skipped | Should -Be 0

        $merged = @(Get-Content -Raw $script:existingPath | ConvertFrom-Json)
        $merged.Count | Should -Be 2
        ($merged | Where-Object vulnerableVersionRange -eq '<=4.17.20') | Should -Not -BeNullOrEmpty
        ($merged | Where-Object packageVersion -eq '4.17.20')           | Should -Not -BeNullOrEmpty
    }

    It 'Never lets a range suppress an exact-version finding, whatever the range says' {
        # Every one of these would need a different corner of npm's range semantics to judge --
        # a plain bound, a partial operand ('>1.2' means '>=1.3.0'), prerelease admission, and a
        # range that is not valid npm syntax at all. None of them may cost us the finding.
        @(
            [ordered]@{ packageName = 'A'; id = 'CVE-1'; severity = 'HIGH'; vulnerableVersionRange = '<2.0.0' },
            [ordered]@{ packageName = 'B'; id = 'CVE-2'; severity = 'HIGH'; vulnerableVersionRange = '>1.2' },
            [ordered]@{ packageName = 'C'; id = 'CVE-3'; severity = 'HIGH'; vulnerableVersionRange = '>=1.0.0 <2.0.0' },
            [ordered]@{ packageName = 'D'; id = 'CVE-4'; severity = 'HIGH'; vulnerableVersionRange = 'whatever-this-is' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'A'; id = 'CVE-1'; severity = 'HIGH'; packageVersion = '1.5.0' },
            [ordered]@{ packageName = 'B'; id = 'CVE-2'; severity = 'HIGH'; packageVersion = '1.2.5' },
            [ordered]@{ packageName = 'C'; id = 'CVE-3'; severity = 'HIGH'; packageVersion = '1.5.0-beta' },
            [ordered]@{ packageName = 'D'; id = 'CVE-4'; severity = 'HIGH'; packageVersion = '9.9.9' }
        )

        $result.Added | Should -Be 4
        $result.Skipped | Should -Be 0
    }

    It 'Still collapses two identical range entries' {
        # Dropping range evaluation does not mean dropping deduplication: an identical scope is
        # still an identical finding.
        @(
            [ordered]@{ packageName = 'A'; id = 'CVE-1'; severity = 'HIGH'; vulnerableVersionRange = '<2.0.0' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'A'; id = 'CVE-1'; severity = 'LOW'; vulnerableVersionRange = '<2.0.0' }
        )

        $result.Added | Should -Be 0
        $result.Skipped | Should -Be 1
    }

    It 'Does not let an unscoped entry suppress a scoped one either' {
        # An entry with no packageVersion and no range looks like it covers the whole package,
        # but that is a reading of a schema we cannot check, and acting on it deletes a finding
        # if the reading is wrong. It also made the merge order-dependent: unscoped-then-exact
        # collapsed while exact-then-unscoped did not.
        @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH'; packageVersion = '9.9.9' },
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH'; vulnerableVersionRange = '<2.0.0' }
        )

        $result.Added | Should -Be 2
        $result.Skipped | Should -Be 0
    }

    It 'Merges the same pair to the same result whichever side is already on file' {
        # Dedup is now pure key equality, so it cannot depend on which scanner wrote first.
        $unscoped = [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH' }
        $exact    = [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH'; packageVersion = '9.9.9' }

        $forward = Join-Path $TestDrive 'forward.json'
        @($unscoped) | ConvertTo-Json -Depth 10 | Set-Content -Path $forward -Encoding utf8
        $forwardResult = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $forward -NewEntries @($exact)

        $reverse = Join-Path $TestDrive 'reverse.json'
        @($exact) | ConvertTo-Json -Depth 10 | Set-Content -Path $reverse -Encoding utf8
        $reverseResult = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $reverse -NewEntries @($unscoped)

        $forwardResult.Total | Should -Be $reverseResult.Total
        $forwardResult.Added | Should -Be $reverseResult.Added
        $forwardResult.Total | Should -Be 2
    }

    It 'Still collapses two identical unscoped entries' {
        @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'HIGH' }
        ) | ConvertTo-Json -Depth 10 | Set-Content -Path $script:existingPath -Encoding utf8

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2024-1111'; severity = 'LOW' }
        )

        $result.Added | Should -Be 0
        $result.Skipped | Should -Be 1
    }

    It 'Refuses to overwrite an existing file it cannot read' {
        $original = '[{"packageName":"Real","id":"CVE-2020-0001","severity":"HIGH"}]'
        Set-Content -Path $script:existingPath -Value $original -Encoding utf8

        # An exclusive handle makes Get-Content fail. That failure is *non-terminating*, so
        # without -ErrorAction Stop it never reaches the catch and the merge overwrites the file.
        $handle = [System.IO.File]::Open($script:existingPath, 'Open', 'ReadWrite', 'None')
        try {
            { Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @() } |
                Should -Throw -ExpectedMessage '*Refusing to overwrite it*'
        }
        finally { $handle.Close() }

        (Get-Content -Raw $script:existingPath).Trim() | Should -Be $original
    }

    It 'Refuses to overwrite an existing file it cannot parse' {
        $corrupt = '[{"packageName":"Real","id":"CVE-2020-0001","severity":"HIGH"},,,BROKEN'
        Set-Content -Path $script:existingPath -Value $corrupt -Encoding utf8

        { Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @() } |
            Should -Throw -ExpectedMessage '*Refusing to overwrite it*'

        # The original bytes are the only copy of those findings -- they must survive.
        (Get-Content -Raw $script:existingPath).Trim() | Should -Be $corrupt
    }

    It 'Refreshes the companion hash report after rewriting the file' {
        $data = @{
            'Pkg@1.0.0' = @{
                Name            = 'Pkg'
                Version         = '1.0.0'
                Vulnerabilities = @(@{ Id = 'CVE-2020-0001'; Severity = 'HIGH'; CVE = 'CVE-2020-0001' })
            }
        }
        ConvertTo-VulnerabilitiesSourceJson -VulnerabilityData $data -PackageVersionIsExact -OutputFile $script:existingPath | Out-Null

        Merge-VulnerabilitiesSourceEntries -ExistingFilePath $script:existingPath -NewEntries @(
            [ordered]@{ packageName = 'Other'; id = 'CVE-2021-2222'; severity = 'LOW'; packageVersion = '2.0.0' }
        ) | Out-Null

        $lines = Get-Content "$($script:existingPath).hash.txt"
        $recordedSha = ($lines | Where-Object { $_.StartsWith('SHA256:') }).Substring(7).Trim()
        $recordedSize = [int](($lines | Where-Object { $_.StartsWith('Size:') }).Substring(5).Trim().Split(' ')[0])

        $recordedSha | Should -Be (Get-FileHash $script:existingPath -Algorithm SHA256).Hash
        $recordedSize | Should -Be (Get-Item $script:existingPath).Length
    }

    It 'Does not invent a hash report for a file that never had one' {
        # A path of its own: TestDrive is shared across the tests in this Describe, and the
        # preceding one deliberately leaves a .hash.txt behind.
        $unhashed = Join-Path $TestDrive 'no-hash-report.json'

        $result = Merge-VulnerabilitiesSourceEntries -ExistingFilePath $unhashed -NewEntries @(
            [ordered]@{ packageName = 'A'; id = 'CVE-2020-0001'; severity = 'LOW' }
        )

        $result.Added | Should -Be 1
        Test-Path "$unhashed.hash.txt" | Should -BeFalse
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

    It 'Writes npm advisory ids as strings, not numbers' {
        # npm audit's via[].source is a JSON number, so ConvertFrom-Json hands us an Int64.
        # Left alone it serializes unquoted, giving `id` a different type than the CVE ids,
        # advisory URLs and Trivy VulnerabilityIDs that share the same array.
        $numericSource = ('{"source":1106913}' | ConvertFrom-Json).source
        $numericSource | Should -BeOfType [long]

        $data = @{
            'lodash@<=4.17.20' = @{
                Name            = 'lodash'
                Version         = '<=4.17.20'
                Vulnerabilities = @(@{ Id = $numericSource; Severity = 'high'; CVE = 'N/A' })
            }
        }

        $outputFile = Join-Path $TestDrive 'npm-vulnerabilities.json'
        $entries = ConvertTo-VulnerabilitiesSourceJson -VulnerabilityData $data -OutputFile $outputFile

        $entries[0].id | Should -BeOfType [string]
        (Get-Content -Raw $outputFile) | Should -Match '"id": "1106913"'
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

Describe 'Write-FileHashReport' {

    It 'Fails rather than publishing a report with blank hashes' {
        # Get-FileHash and Get-Item are non-terminating by default, and a null result did not stop
        # the function: it wrote a report carrying a real path and size next to empty SHA256, SHA1
        # and MD5 lines. That reads as a genuine integrity report while attesting to nothing.
        $target = Join-Path $TestDrive 'locked-payload.json'
        Set-Content -Path $target -Value '{"a":1}' -Encoding utf8

        $handle = [System.IO.File]::Open($target, 'Open', 'ReadWrite', 'None')
        try {
            { Write-FileHashReport -FilePath $target } | Should -Throw
        }
        finally { $handle.Close() }

        Test-Path "$target.hash.txt" | Should -BeFalse
    }

    It 'Records hashes that match the file it was pointed at' {
        $target = Join-Path $TestDrive 'payload.json'
        Set-Content -Path $target -Value '{"a":1}' -Encoding utf8

        Write-FileHashReport -FilePath $target

        $lines = Get-Content "$target.hash.txt"
        ($lines | Where-Object { $_.StartsWith('SHA256:') }).Substring(7).Trim() |
            Should -Be (Get-FileHash $target -Algorithm SHA256).Hash
        [int](($lines | Where-Object { $_.StartsWith('Size:') }).Substring(5).Trim().Split(' ')[0]) |
            Should -Be (Get-Item $target).Length
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
