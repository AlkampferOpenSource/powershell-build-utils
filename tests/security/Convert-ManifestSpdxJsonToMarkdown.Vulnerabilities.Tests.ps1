BeforeAll {
    # Import the module under test
    Import-Module "$PSScriptRoot\..\..\src\security\Convert-ManifestSpdxJsonToMarkdown.psm1" -Force
}

Describe 'Convert-ManifestSpdxJsonToMarkdown - Vulnerability Enrichment' {
    Context 'When a NuGet package has vulnerabilities' {
        It 'Adds vulnerability info to markdown and updates scan statistics' {
            $sbom = @{
                name = 'test-sbom'
                spdxVersion = 'SPDX-2.2'
                packages = @(
                    @{
                        name = 'TestPkg'
                        versionInfo = '1.2.3'
                        SPDXID = 'SPDXRef-Package-TestPkg'
                        externalRefs = @(@{ referenceType = 'purl'; referenceLocator = 'pkg:nuget/testpkg@1.2.3' })
                    }
                )
            }

            $tmp = Join-Path -Path $PSScriptRoot -ChildPath 'tmp-spdx-vuln.json'
            $sbom | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding UTF8

            # Reset global stats to ensure deterministic output
            if ($script:vulnerabilityStats) { Remove-Variable -Scope Script -Name vulnerabilityStats -ErrorAction SilentlyContinue }

            Mock -CommandName Get-NuGetPackageMetadata -MockWith { @{ License = 'MIT' } }
            Mock -CommandName Get-NuGetVulnerabilities -MockWith { @{ HasVulnerabilities = $true; Vulnerabilities = @( @{ Id = 'OSV-1'; Summary = 'Exploit available' } ) } }

            $out = Convert-ManifestSpdxJsonToMarkdown -InputPath $tmp -EnrichMetadata -Verbose

            Test-Path $out | Should -BeTrue

            $content = Get-Content -Path $out -Raw
            $content | Should -Match 'NuGet Packages Scanned'
            $content | Should -Match 'Vulnerable Packages'
            $content | Should -Match 'OSV-1'
            $content | Should -Match '\*\*Vulnerable\*\*' # table header present

            Assert-MockCalled -CommandName Get-NuGetVulnerabilities -Times 1

            Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $out -Force -ErrorAction SilentlyContinue
        }
    }

    Context 'When a NuGet package is safe' {
        It 'Shows Safe and does not list vulnerabilities' {
            $sbom = @{
                name = 'safe-sbom'
                spdxVersion = 'SPDX-2.2'
                packages = @(
                    @{
                        name = 'SafePkg'
                        versionInfo = '0.0.1'
                        SPDXID = 'SPDXRef-Package-SafePkg'
                        externalRefs = @(@{ referenceType = 'purl'; referenceLocator = 'pkg:nuget/safepkg@0.0.1' })
                    }
                )
            }

            $tmp = Join-Path -Path $PSScriptRoot -ChildPath 'tmp-spdx-safe.json'
            $sbom | ConvertTo-Json -Depth 10 | Set-Content -Path $tmp -Encoding UTF8

            if ($script:vulnerabilityStats) { Remove-Variable -Scope Script -Name vulnerabilityStats -ErrorAction SilentlyContinue }

            Mock -CommandName Get-NuGetPackageMetadata -MockWith { @{ License = 'MIT' } }
            Mock -CommandName Get-NuGetVulnerabilities -MockWith { @{ HasVulnerabilities = $false; Vulnerabilities = @() } }

            $out = Convert-ManifestSpdxJsonToMarkdown -InputPath $tmp -EnrichMetadata -Verbose

            $content = Get-Content -Path $out -Raw
            $content | Should -Match 'NuGet Packages Scanned'
            $content | Should -Match 'Vulnerable Packages'
            $content | Should -Match '\*\*Vulnerable\*\*'
            $content | Should -Match '\| \*\*Vulnerabilities\*\* |' -NotMatch

            Assert-MockCalled -CommandName Get-NuGetVulnerabilities -Times 1

            Remove-Item -Path $tmp -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $out -Force -ErrorAction SilentlyContinue
        }
    }
}
