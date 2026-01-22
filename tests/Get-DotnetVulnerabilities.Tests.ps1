Describe 'Get-DotnetVulnerabilities' {
    It 'parses dotnet JSON and returns vulnerable packages' {
        # Arrange: fake dotnet output
        $fakeJson = @'
        {
          "projects": [
            {
              "path": "Project1.csproj",
              "frameworks": [
                {
                  "framework": "net6.0",
                  "topLevelPackages": [
                    {
                      "id":"Example.Package",
                      "resolvedVersion":"1.2.3",
                      "vulnerabilities":[{"severity":"High","advisoryurl":"https://.../CVE-2020-1234"}]
                    }
                  ]
                }
              ]
            }
          ]
        }
'@

        # Make a global dotnet function so the module (which runs in its own scope)
        # can resolve it instead of the system CLI
        function global:dotnet {
            param(
                [Parameter(ValueFromRemainingArguments=$true)]
                [string[]] $args
            )

            if ($args -contains '--version') { return '7.0.0' }
            return $fakeJson
        }

        # Import module using a compatible import (avoid -LiteralPath for older PS versions)
        $modulePath = Join-Path $PSScriptRoot '..\src\security\Get-PackageVulnerability.psm1'
        Import-Module -Force $modulePath

        # Make sure last exit code is clear so function doesn't think external dotnet failed
        $global:LASTEXITCODE = 0

        # Act
        $res = Get-DotnetVulnerabilities -SolutionPath 'dummy.sln'

        # Assert
        $res.ContainsKey('Example.Package@1.2.3') | Should -BeTrue
        $res['Example.Package@1.2.3'].Vulnerabilities.Count | Should -Be 1
        $res['Example.Package@1.2.3'].Vulnerabilities[0].CVE | Should -Match 'CVE-2020-1234|N/A'
    }
}
