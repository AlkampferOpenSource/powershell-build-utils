<#
.SYNOPSIS
Query public package registries for metadata

.DESCRIPTION
Fetches additional metadata from NPM and NuGet registries including license information,
author details, project URLs, and descriptions. Supports caching to minimize API requests.

.EXAMPLE
$info = Get-NpmPackageInfo -PackageName "lodash" -Version "4.17.21" -Cache $cache -Statistics $stats

.EXAMPLE
$info = Get-NuGetPackageInfo -PackageName "Newtonsoft.Json" -Version "13.0.1" -Cache $cache -Statistics $stats

.NOTES
Requires internet connectivity to access public registries.
Respects cache to avoid duplicate requests.
#>

function Get-NpmPackageInfo {
    <#
    .SYNOPSIS
    Retrieve package metadata from NPM registry
    
    .DESCRIPTION
    Queries the NPM registry API for package information including license, author,
    homepage, repository, and description.
    
    .PARAMETER PackageName
    The NPM package name
    
    .PARAMETER Version
    The package version
    
    .PARAMETER Cache
    Cache hashtable for storing results (optional)
    
    .PARAMETER Statistics
    Statistics object to update (optional)
    
    .OUTPUTS
    Hashtable with keys: License, Author, Homepage, Repository, Description
    Returns $null on failure
    
    .EXAMPLE
    $info = Get-NpmPackageInfo -PackageName "lodash" -Version "4.17.21"
    if ($info) { Write-Host "License: $($info.License)" }
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)]
        [string] $PackageName,
        
        [Parameter(Mandatory=$true)]
        [string] $Version,
        
        [Parameter(Mandatory=$false)]
        [hashtable] $Cache,
        
        [Parameter(Mandatory=$false)]
        [PSCustomObject] $Statistics
    )
    
    $cacheKey = "npm:${PackageName}@${Version}"
    
    # Check cache first
    if ($Cache) {
        $cached = Get-CachedPackage -Cache $Cache -Key $cacheKey
        if ($cached) {
            if ($Statistics) {
                Update-EnrichmentStats -Statistics $Statistics -Result "Cached"
            }
            return $cached
        }
    }
    
    try {
        $url = "https://registry.npmjs.org/$PackageName/$Version"
        $response = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 10 -ErrorAction Stop
        
        $info = @{
            License = $response.license
            Author = $response.author.name
            Homepage = $response.homepage
            Repository = $response.repository.url
            Description = $response.description
        }
        
        # Cache the result
        if ($Cache) {
            Set-CachedPackage -Cache $Cache -Key $cacheKey -Data $info
        }
        
        if ($Statistics) {
            Update-EnrichmentStats -Statistics $Statistics -Result "Enriched"
        }
        
        return $info
    }
    catch {
        Write-Verbose "Failed to fetch NPM info for ${PackageName}@${Version}: $_"
        
        if ($Statistics) {
            Update-EnrichmentStats -Statistics $Statistics -Result "Failed"
        }
        
        return $null
    }
}

function Get-NuGetPackageInfo {
    <#
    .SYNOPSIS
    Retrieve package metadata from NuGet registry
    
    .DESCRIPTION
    Queries NuGet API for package .nuspec file and extracts metadata including
    license, author, project URL, description, and copyright.
    
    .PARAMETER PackageName
    The NuGet package name
    
    .PARAMETER Version
    The package version
    
    .PARAMETER Cache
    Cache hashtable for storing results (optional)
    
    .PARAMETER Statistics
    Statistics object to update (optional)
    
    .OUTPUTS
    Hashtable with keys: License, LicenseUrl, Author, ProjectUrl, Description, Copyright
    Returns $null on failure
    
    .EXAMPLE
    $info = Get-NuGetPackageInfo -PackageName "Newtonsoft.Json" -Version "13.0.1"
    Write-Host "Author: $($info.Author)"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)]
        [string] $PackageName,
        
        [Parameter(Mandatory=$true)]
        [string] $Version,
        
        [Parameter(Mandatory=$false)]
        [hashtable] $Cache,
        
        [Parameter(Mandatory=$false)]
        [PSCustomObject] $Statistics
    )
    
    $cacheKey = "nuget:${PackageName}@${Version}"
    
    # Check cache first
    if ($Cache) {
        $cached = Get-CachedPackage -Cache $Cache -Key $cacheKey
        if ($cached) {
            if ($Statistics) {
                Update-EnrichmentStats -Statistics $Statistics -Result "Cached"
            }
            return $cached
        }
    }
    
    try {
        # Get .nuspec file
        $nuspecUrl = "https://api.nuget.org/v3-flatcontainer/$($PackageName.ToLower())/$Version/$($PackageName.ToLower()).nuspec"
        $nuspecXml = Invoke-RestMethod -Uri $nuspecUrl -Method Get -TimeoutSec 10 -ErrorAction Stop
        
        # Parse XML
        [xml]$xml = $nuspecXml
        $metadata = $xml.package.metadata
        
        $info = @{
            License = $metadata.license.'#text'
            LicenseUrl = $metadata.licenseUrl
            Author = $metadata.authors
            ProjectUrl = $metadata.projectUrl
            Description = $metadata.description
            Copyright = $metadata.copyright
        }
        
        # If no license text, try to extract from licenseUrl
        if ([string]::IsNullOrWhiteSpace($info.License) -and -not [string]::IsNullOrWhiteSpace($info.LicenseUrl)) {
            if ($info.LicenseUrl -match "MIT") {
                $info.License = "MIT"
            }
            elseif ($info.LicenseUrl -match "Apache-2.0|apache.org/licenses/LICENSE-2.0") {
                $info.License = "Apache-2.0"
            }
            elseif ($info.LicenseUrl -match "GPL-3.0") {
                $info.License = "GPL-3.0"
            }
            elseif ($info.LicenseUrl -match "BSD") {
                $info.License = "BSD"
            }
            else {
                $info.License = "See: $($info.LicenseUrl)"
            }
        }
        
        # Cache the result
        if ($Cache) {
            Set-CachedPackage -Cache $Cache -Key $cacheKey -Data $info
        }
        
        if ($Statistics) {
            Update-EnrichmentStats -Statistics $Statistics -Result "Enriched"
        }
        
        return $info
    }
    catch {
        Write-Verbose "Failed to fetch NuGet info for ${PackageName}@${Version}: $_"
        
        if ($Statistics) {
            Update-EnrichmentStats -Statistics $Statistics -Result "Failed"
        }
        
        return $null
    }
}

function Get-PackageInfo {
    <#
    .SYNOPSIS
    Retrieve package metadata from appropriate registry
    
    .DESCRIPTION
    Routes to NPM or NuGet metadata functions based on package type.
    Convenience wrapper for unified package information retrieval.
    
    .PARAMETER PackageName
    The package name
    
    .PARAMETER Version
    The package version
    
    .PARAMETER PackageType
    The package manager type: "NPM" or "NUGET"
    
    .PARAMETER Cache
    Cache hashtable for storing results (optional)
    
    .PARAMETER Statistics
    Statistics object to update (optional)
    
    .OUTPUTS
    Hashtable with package metadata, or $null on failure
    
    .EXAMPLE
    $info = Get-PackageInfo -PackageName "lodash" -Version "4.17.21" -PackageType "NPM"
    
    .EXAMPLE
    $info = Get-PackageInfo -PackageName "Newtonsoft.Json" -Version "13.0.1" -PackageType "NUGET" -Cache $cache
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)]
        [string] $PackageName,
        
        [Parameter(Mandatory=$true)]
        [string] $Version,
        
        [Parameter(Mandatory=$true)]
        [ValidateSet("NPM", "NUGET")]
        [string] $PackageType,
        
        [Parameter(Mandatory=$false)]
        [hashtable] $Cache,
        
        [Parameter(Mandatory=$false)]
        [PSCustomObject] $Statistics
    )
    
    switch ($PackageType.ToUpper()) {
        "NPM" {
            return Get-NpmPackageInfo -PackageName $PackageName -Version $Version -Cache $Cache -Statistics $Statistics
        }
        "NUGET" {
            return Get-NuGetPackageInfo -PackageName $PackageName -Version $Version -Cache $Cache -Statistics $Statistics
        }
        default {
            Write-Warning "Unsupported package type: $PackageType"
            return $null
        }
    }
}

Export-ModuleMember -Function Get-NpmPackageInfo, Get-NuGetPackageInfo, Get-PackageInfo
