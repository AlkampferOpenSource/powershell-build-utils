<#
.SYNOPSIS
Manage caching of package metadata and vulnerability scan results

.DESCRIPTION
Provides functions to cache API responses to avoid duplicate requests during SBOM processing.
Supports persisting cache to JSON files and loading from disk for subsequent runs.
Cache keys use format: "npm:package@version", "nuget:package@version", "vuln:npm:package@version"

.EXAMPLE
$cache = Initialize-SBOMCache
Set-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21" -Data $packageInfo
$data = Get-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21"

.EXAMPLE
$cache = Import-SBOMCache -FilePath "cache.json"
Export-SBOMCache -Cache $cache -FilePath "cache.json"

.NOTES
Cache entries persist only for the current session unless explicitly exported to file.
#>

function Initialize-SBOMCache {
    <#
    .SYNOPSIS
    Create a new empty cache hashtable (optionally associated with a file)
    
    .DESCRIPTION
    Initializes an empty hashtable for storing package metadata and vulnerability results.
    If a `FilePath` is provided and the file exists, the cache will be loaded from disk.
    The returned hashtable will have a `CacheFilePath` noteproperty when `-FilePath` is supplied.
    
    .OUTPUTS
    Hashtable for cache storage
    
    .PARAMETER FilePath
    Optional path to a cache JSON file to load and associate with the cache.
    
    .EXAMPLE
    $cache = Initialize-SBOMCache -FilePath '.\cache.json'
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$false)]
        [string] $FilePath
    )
    
    # If FilePath provided and file exists, import it
    if (-not [string]::IsNullOrWhiteSpace($FilePath) -and (Test-Path $FilePath)) {
        $cache = Import-SBOMCache -FilePath $FilePath
    }
    else {
        $cache = @{}
    }
    
    if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
        # store the file path as a noteproperty on the hashtable for convenience
        $cache | Add-Member -MemberType NoteProperty -Name CacheFilePath -Value $FilePath -Force
    }
    
    return $cache
}

function Get-CachedPackage {
    <#
    .SYNOPSIS
    Retrieve a package from cache
    
    .DESCRIPTION
    Returns cached data for the specified key, or $null if not found.
    
    .PARAMETER Cache
    The cache hashtable to query
    
    .PARAMETER Key
    The cache key (e.g., "npm:lodash@4.17.21")
    
    .OUTPUTS
    The cached object, or $null if not found
    
    .EXAMPLE
    $data = Get-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21"
    if ($data) { Write-Host "Found in cache" }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable] $Cache,
        
        [Parameter(Mandatory=$true)]
        [string] $Key
    )
    
    if ($Cache.ContainsKey($Key)) {
        return $Cache[$Key]
    }
    
    return $null
}

function Set-CachedPackage {
    <#
    .SYNOPSIS
    Store a package in cache
    
    .DESCRIPTION
    Adds or updates a cache entry for the specified key.
    
    .PARAMETER Cache
    The cache hashtable to update
    
    .PARAMETER Key
    The cache key (format: "type:package@version")
    
    .PARAMETER Data
    The data to cache (typically a hashtable or PSCustomObject)
    
    .EXAMPLE
    Set-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21" -Data $packageInfo
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable] $Cache,
        
        [Parameter(Mandatory=$true)]
        [string] $Key,
        
        [Parameter(Mandatory=$true)]
        $Data
    )
    
    $Cache[$Key] = $Data
}

function Import-SBOMCache {
    <#
    .SYNOPSIS
    Load cache from a JSON file
    
    .DESCRIPTION
    Reads a previously exported cache file and returns a populated cache hashtable.
    Returns an empty cache if file doesn't exist or is invalid.
    
    .PARAMETER FilePath
    Path to the cache JSON file
    
    .OUTPUTS
    Hashtable containing cached entries
    
    .EXAMPLE
    $cache = Import-SBOMCache -FilePath ".\cache\sbom-cache.json"
    Write-Host "Loaded $($cache.Count) entries"
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory=$true)]
        [string] $FilePath
    )
    
    $cache = @{}
    
    if (-not (Test-Path $FilePath)) {
        Write-Verbose "Cache file not found: $FilePath"
        return $cache
    }
    
    try {
        $json = Get-Content -Path $FilePath -Raw -ErrorAction Stop | ConvertFrom-Json
        
        if (-not $json -or -not $json.Entries) {
            Write-Verbose "Invalid cache format or empty cache"
            return $cache
        }
        
        # Rebuild hashtable from JSON entries
        foreach ($entry in $json.Entries) {
            if ($entry.Key -and $entry.Value) {
                $cache[$entry.Key] = $entry.Value
            }
        }
        
        Write-Verbose "Loaded $($cache.Count) entries from cache"
    }
    catch {
        Write-Warning "Failed to load cache from ${FilePath}: $_"
    }
    
    return $cache
}

function Export-SBOMCache {
    <#
    .SYNOPSIS
    Save cache to a JSON file
    
    .DESCRIPTION
    Persists the cache hashtable to disk as JSON for reuse in subsequent runs.
    Creates the parent directory if it doesn't exist.
    
    .PARAMETER Cache
    The cache hashtable to export
    
    .PARAMETER FilePath
    Destination path for the JSON file
    
    .EXAMPLE
    Export-SBOMCache -Cache $cache -FilePath ".\cache\sbom-cache.json"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable] $Cache,
        
        [Parameter(Mandatory=$true)]
        [string] $FilePath
    )
    
    # Ensure parent directory exists
    $parentDir = Split-Path -Path $FilePath -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }
    
    try {
        # Convert hashtable to array of key-value pairs for JSON serialization
        $entries = @()
        foreach ($key in $Cache.Keys) {
            $entries += [PSCustomObject]@{
                Key = $key
                Value = $Cache[$key]
            }
        }
        
        $cacheData = [PSCustomObject]@{
            ExportDate = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Entries = $entries
        }
        
        $json = $cacheData | ConvertTo-Json -Depth 10
        Set-Content -Path $FilePath -Value $json -Encoding UTF8
        
        Write-Verbose "Exported $($entries.Count) cache entries to $FilePath"
    }
    catch {
        Write-Warning "Failed to save cache to ${FilePath}: $_"
    }
}

function Clear-SBOMCache {
    <#
    .SYNOPSIS
    Remove all entries from cache
    
    .DESCRIPTION
    Clears all cached data. Does not delete cache files on disk.
    
    .PARAMETER Cache
    The cache hashtable to clear
    
    .EXAMPLE
    Clear-SBOMCache -Cache $cache
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable] $Cache
    )
    
    $Cache.Clear()
    Write-Verbose "Cache cleared"
}

Export-ModuleMember -Function Initialize-SBOMCache, Get-CachedPackage, Set-CachedPackage, Import-SBOMCache, Export-SBOMCache, Clear-SBOMCache
