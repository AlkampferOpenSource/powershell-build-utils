# BuildUtils Tests

This directory contains Pester tests for the BuildUtils PowerShell module.

## Prerequisites

Ensure Pester is installed:

```powershell
# Check if Pester is installed
Get-Module -ListAvailable Pester

# Install/Update Pester (if needed) - no admin rights required
Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
```

## Running Tests

### Run all tests
```powershell
Invoke-Pester -Path .\tests
```

### Run specific test file
```powershell
Invoke-Pester -Path .\tests\Edit-XmlNodes.Tests.ps1
```

### Run with detailed output
```powershell
Invoke-Pester -Path .\tests -Output Detailed
```

### Run with code coverage
```powershell
$config = New-PesterConfiguration
$config.CodeCoverage.Enabled = $true
$config.CodeCoverage.Path = ".\src\**\*.psm1"
Invoke-Pester -Configuration $config
```

## Test Structure

Tests follow Pester v5 conventions:
- `BeforeAll`: Setup that runs once before all tests
- `BeforeEach`: Setup that runs before each test
- `Describe`: Groups related tests
- `Context`: Specific scenarios within a group
- `It`: Individual test case

## Writing New Tests

When adding new tests:
1. Create `[FunctionName].Tests.ps1` in the `tests` directory
2. Import the module/function in `BeforeAll`
3. Use `Describe`, `Context`, and `It` blocks to organize tests
4. Use `Should` assertions to verify behavior
