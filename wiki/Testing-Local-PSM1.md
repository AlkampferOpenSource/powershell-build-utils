# Testing security module `.psm1` files locally ✅

This document explains how to interactively load and test the security modules in `src/security/` (for example `Get-PackageVulnerability.psm1`) so you can:
- run the cmdlets directly from PowerShell,
- edit a `.psm1` and re-run without reinstalling the module,
- and add Pester tests that mock `dotnet` output for `Get-DotnetVulnerabilities`.

---

## Quick interactive test (fast loop) 🔧

1. Open a PowerShell terminal in the repo root.
2. Load the module file directly (recommended during dev):

```powershell
# Set a reusable path to the module (compatible with all PowerShell versions)
$modulePath = Join-Path $PWD "src\security\Get-PackageVulnerability.psm1"

# Import the module
Import-Module -Force $modulePath

# Alternatively, dot-source the file to load private helpers into the current session:
. $modulePath

# Clear any leftover exit code so a prior failure won't cause the function to bail early
$global:LASTEXITCODE = 0
```

3. Call the function you want to test:

```powershell
# Real scan (requires dotnet CLI available)
Get-DotnetVulnerabilities -SolutionPath '.\examples\MySolution.sln' -Statistics $stats

# Quick check (increases diagnostic output)
Get-DotnetVulnerabilities -SolutionPath '.\MySolution.sln' -Verbose

# Save raw JSON output and hash to files
Get-DotnetVulnerabilities -SolutionPath '.\MySolution.sln' -OutputFile 'scan-results.json'
# Creates: scan-results.json and scan-results.json.hash.txt (with SHA256, SHA1, MD5)
```

4. After editing a `.psm1`, reload it with `Import-Module -Force -LiteralPath ...` to pick up changes.

---

## Simulating `dotnet` output for offline or unit testing 💡

If you don't want to run the real `dotnet` CLI, you can simulate its JSON output in your session by defining a `dotnet` function that returns known JSON. Example (interactive or in a test):

```powershell
# Fake dotnet JSON that mirrors the shape used by Get-DotnetVulnerabilities
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
                                        "vulnerabilities":[
                                            {"severity":"Moderate","advisoryurl":"https://.../CVE-2020-1234"}
                                        ]
                                    }
                                ]
        }
      ]
    }
  ]
}
'@

# Define a *global* dotnet function so the module resolves it instead of the system CLI
function global:dotnet { param($args) return $fakeJson }

# Import the module (compatible pattern)
$modulePath = Join-Path $PWD "src\security\Get-PackageVulnerability.psm1"
Import-Module -Force $modulePath

# Clear previous exit code and call the function
$global:LASTEXITCODE = 0
$result = Get-DotnetVulnerabilities -SolutionPath 'dummy.sln'
$result.Keys # inspect found packages
```

This works because a PowerShell function named `dotnet` will shadow the external CLI for the current session.

---

## Writing a Pester test for `Get-DotnetVulnerabilities` 🧪

Create a test file `tests/Get-DotnetVulnerabilities.Tests.ps1` with content similar to this:

```powershell
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

# Define a global dotnet function for predictable behavior in the test session
function global:dotnet { param($args) return $fakeJson }

# Import module using a path join (compatible)
$modulePath = Join-Path $PSScriptRoot "..\src\security\Get-PackageVulnerability.psm1"
Import-Module -Force $modulePath

# Make sure any prior external command errors don't interfere
$global:LASTEXITCODE = 0

        # Act
        $res = Get-DotnetVulnerabilities -SolutionPath 'dummy.sln'

        # Assert
        $res.ContainsKey('Example.Package@1.2.3') | Should -BeTrue
        $res['Example.Package@1.2.3'].Vulnerabilities.Count | Should -Be 1
    }
}
```

Notes:
- The test defines `dotnet` to return a controlled JSON string so the function under test parses predictable data.
- Alternatively, you can refactor production code to call a small wrapper (e.g. `Invoke-DotnetList`) and then `Mock` that wrapper in tests — this is cleaner and easier to maintain.

---

## Running tests

- Use the repo tasks in VS Code (Test panel) or run in terminal:

```powershell
# Run all tests
Invoke-Pester -Path .\tests -Output Detailed

# Run just the new test file
Invoke-Pester -Path .\tests\Get-DotnetVulnerabilities.Tests.ps1 -Output Detailed
```

You can also use the provided workspace tasks: `Run All Pester Tests` or `Run Current Test File`.

---

## Dev tips & troubleshooting ⚠️

- If `Import-Module` fails, check `Get-ExecutionPolicy` and run: `Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned` for the session.
- If `dotnet` CLI is not installed, the real scan will warn and return empty results; use the fake `dotnet` function to simulate.
- Use `-Verbose` and `$VerbosePreference = 'Continue'` to see `Write-Verbose` messages.
- To test private helpers directly during development, dot-source the `.psm1` file: `. .\src\security\Get-PackageVulnerability.psm1`.
- If you plan to add many tests, consider extracting a small wrapper around external commands so you can `Mock` it with Pester instead of shadowing the `dotnet` executable.

---

## Example development loop (recommended)

1. Edit `src/security/Get-PackageVulnerability.psm1` in your editor.
2. Save file.
3. In your PowerShell terminal:

```powershell
$modulePath = Join-Path $PWD "src\security\Get-PackageVulnerability.psm1"
Import-Module -Force $modulePath
# After editing: clear previous exit code, then re-import to pick up changes
$global:LASTEXITCODE = 0
Import-Module -Force $modulePath
```

4. Run the function or your Pester tests to validate behavior.
5. Repeat until satisfied.

---

If you want, I can add the example test file `tests/Get-DotnetVulnerabilities.Tests.ps1` and a small sample `examples/` solution to run an end-to-end scenario.
