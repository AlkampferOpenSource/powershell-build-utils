Describe 'Get-NuGetVulnerabilities' {
    Context 'No vulnerabilities' {
        It 'Returns no vulnerabilities and calls API on each invocation (no cache)' {
            Mock -CommandName Invoke-RestMethod -MockWith { @{ vulns = @() } }

            $r1 = Get-NuGetVulnerabilities -PackageName 'TestPkg' -Version '1.0.0'
            $r2 = Get-NuGetVulnerabilities -PackageName 'TestPkg' -Version '1.0.0'

            $r1.HasVulnerabilities | Should -BeFalse
            ($r1.Vulnerabilities).Count | Should -Be 0

            Assert-MockCalled -CommandName Invoke-RestMethod -Times 2
        }
    }

    Context 'Vulnerability with database_specific severity' {
        It 'Parses database_specific severity and CVE alias' {
            $mockVuln = @{
                id = 'OSV-1'
                summary = 'summary'
                details = 'details'
                database_specific = @{ severity = 'HIGH' }
                aliases = @('CVE-2020-1234')
                published = '2020-01-01'
                modified = '2020-02-01'
                references = @()
            }

            Mock -CommandName Invoke-RestMethod -MockWith { @{ vulns = @($mockVuln) } }

            $r = Get-NuGetVulnerabilities -PackageName 'Foo' -Version '1.2.3'

            $r.HasVulnerabilities | Should -BeTrue
            $r.Vulnerabilities.Count | Should -Be 1
            $r.Vulnerabilities[0].Severity | Should -Be 'HIGH'
            $r.Vulnerabilities[0].CVE | Should -Be 'CVE-2020-1234'
        }
    }

    Context 'Vulnerability with severity array (cvss)' {
        It 'Parses severity array and CVSS score' {
            $mockVuln = @{
                id = 'OSV-2'
                summary = 's'
                details = 'd'
                severity = @(@{ type = 'CVSSv3'; score = '9.8' })
                aliases = @()
            }

            Mock -CommandName Invoke-RestMethod -MockWith { @{ vulns = @($mockVuln) } }

            $r = Get-NuGetVulnerabilities -PackageName 'Bar' -Version '9.9.9'

            $r.HasVulnerabilities | Should -BeTrue
            $r.Vulnerabilities[0].Severity | Should -Be 'CVSSv3'
            $r.Vulnerabilities[0].CVSSScore | Should -Be '9.8'
            $r.Vulnerabilities[0].CVE | Should -Be 'N/A'
        }
    }

    Context 'API error' {
        It 'Returns empty result and does not throw' {
            Mock -CommandName Invoke-RestMethod -MockWith { throw 'network' }

            { Get-NuGetVulnerabilities -PackageName 'Err' -Version '0.0.1' } | Should -Not -Throw

            $r = Get-NuGetVulnerabilities -PackageName 'Err' -Version '0.0.1'
            $r.HasVulnerabilities | Should -BeFalse
            $r.Vulnerabilities.Count | Should -Be 0
        }
    }
}
