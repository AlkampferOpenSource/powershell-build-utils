# PowerShell Build Utils - AI Agent Instructions

## Project Overview

This is a PowerShell module library (`BuildUtils`) containing reusable build automation utilities for .NET projects. The module is published to PowerShell Gallery and follows a **multi-file development, single-file deployment** pattern for performance optimization.

## Critical Architecture Pattern

It is mandatory that, whenver you add or modify utilities in this project, you will check if you need to update/modify existing pester tests. Always check if some new test can be added, give eventually the list to the user then ask if he wants to add them.

### Multi-File to Single-File Module Bundling

**Source Structure:** Individual `.psm1` and `.ps1` files organized in `src/` by category:
- `dotnetBuild/` - MSBuild and .NET versioning utilities
- `fileManipulation/` - XML editing, 7-Zip, file expansion
- `general/` - Logging, execution assertions, user prompts
- `versioning/` - GitVersion integration
- `test/` - NUnit test runner utilities
- `security/` - SBOM processing

**Build Output:** All functions are collapsed into single `BuildUtils/BuildUtils.psm1` by [publish.ps1](publish.ps1) using PowerShell AST parsing for performance ([reference](https://evotec.xyz/powershell-single-psm1-file-versus-multi-file-modules/)).

**When modifying utilities:**
1. Edit source files in `src/` subdirectories, NOT `BuildUtils/BuildUtils.psm1`
2. The publish script will automatically combine them during deployment
3. Each source file should be a self-contained `.psm1` module with complete function definitions

## Publishing Workflow

**Command:** `.\publish.ps1 -version x.y.z -preReleaseTag "beta" -apiKey <key>`

**Critical transformations in [publish.ps1](publish.ps1):**
1. Combines all `.ps1` functions using AST parsing (`Parser::ParseFile()` extracts `EndBlock.Extent.Text`)
2. Appends all `.psm1` module content directly
3. Adds `Export-ModuleMember -Function * -Cmdlet *` at end
4. Generates `BuildUtils.psd1` from template [src/BuildUtils.psd1.source](src/BuildUtils.psd1.source):
   - Replaces `{{version}}` with version parameter
   - Replaces `{{preReleaseTag}}` after: removing leading `-` characters, replacing `.` with `-`
5. Publishes to PowerShell Gallery using `Publish-Module` cmdlet

## Code Conventions

### Function Structure (every utility follows this pattern)

```powershell
<#
.SYNOPSIS
Brief description of purpose

.DESCRIPTION
Detailed explanation including dependencies and prerequisites

.PARAMETER ParameterName
Parameter description

.EXAMPLE
# Show realistic usage with context
$version = Invoke-GitVersion
Update-SourceVersion -SrcPath $path -assemblyVersion $version.AssemblyVersion

.NOTES
Special considerations, CI variables, or dependencies
#>
function Verb-Noun {
    Param (
        [type] $parameter
    )
    # Implementation
}
```

### Naming and Structure
- Use approved PowerShell verbs (`Get-`, `Update-`, `Invoke-`, `Edit-`, `Assert-`)
- Parameter names use PascalCase
- Variables use camelCase
- Return complex data using custom classes (see `[GitVersion]` class in [Invoke-GitVersion.psm1](src/versioning/Invoke-GitVersion.psm1))
- Include `[OutputType()]` attribute when returning custom objects

### CI/CD Integration Pattern

Functions that should behave differently in CI expect `$ci_engine` variable:
```powershell
# Expected values: "azdo" (Azure DevOps) or "github" (GitHub Actions)
# See Assert-LastExecution and Write-LogError for implementation pattern
```

## Key Dependencies

- **VSSetup** module: Required by `Get-LatestMsbuildLocation` for finding MSBuild
- **GitVersion.Tool**: Expected in `.config/dotnet-tools.json` for `Invoke-GitVersion`
- **.NET SDK**: Required for `dotnet tool restore` and `dotnet-gitversion`

Functions that need external tools include download/install logic (see `Get-7ZipLocation` auto-downloading 7za.exe to `$env:TEMP`).

## GitVersion Integration

[Invoke-GitVersion.psm1](src/versioning/Invoke-GitVersion.psm1) is the primary versioning mechanism:
- Auto-creates `.config/dotnet-tools.json` and `.config/GitVersion.yml` if missing
- Returns custom `[GitVersion]` object with properties: `Success`, `AssemblyVersion`, `AssemblyFileVersion`, `NugetVersion`, `AssemblyInformationalVersion`, `FullSemver`
- Designed to work with `Update-SourceVersion` for legacy .NET AssemblyInfo patching

## XML Configuration Pattern

`Edit-XmlNodes` demonstrates the project's approach to config file manipulation:
- Load XML: `$xml = [xml](Get-Content $configFile)`
- Modify using XPath: `Edit-XmlNodes $xml -xpath "/path/@attribute" -value "newValue"`
- Save: `$xml.save($configFile)`

Used for tokenizing configs before deployment (replacing secrets/settings with tokens).

## Testing and Validation

When adding new utilities:
- Test module manifest: `Test-ModuleManifest -Path .\BuildUtils.psd1`
- Verify function export: `Get-Command -Module BuildUtils`
- Test publish locally first using PSRepository (see README "How to publish on PowerShell official gallery (old)")

## Common Pitfalls

1. **Don't edit** `BuildUtils/BuildUtils.psm1` directly - changes will be overwritten by publish script
2. **preReleaseTag processing**: Remember leading `-` removal and `.` to `-` conversion in publish.ps1
3. **UTF-8 encoding**: `Update-SourceVersion` explicitly uses `-Encoding UTF8` - maintain this for AssemblyInfo files
4. **Parser limitations**: `.ps1` files use AST parsing to extract function bodies, `.psm1` files are copied verbatim - choose file extension appropriately
