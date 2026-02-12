BeforeAll {
    # Import the module
    Import-Module "$PSScriptRoot\..\..\src\security\Invoke-SBOMCache.psm1" -Force
}

Describe "Invoke-SBOMCache" {
    Context "When initializing cache" {
        It "Should create an empty hashtable" {
            $cache = Initialize-SBOMCache
            
            $cache.GetType().Name | Should -Be "Hashtable"
            $cache.Count | Should -Be 0
        }
        
        It "Should create independent cache instances" {
            $cache1 = Initialize-SBOMCache
            $cache2 = Initialize-SBOMCache
            
            Set-CachedPackage -Cache $cache1 -Key "test:key" -Data "value"
            
            $cache1.Count | Should -Be 1
            $cache2.Count | Should -Be 0
        }
    }
    
    Context "When setting and getting cached packages" {
        BeforeEach {
            $cache = Initialize-SBOMCache
        }
        
        It "Should store and retrieve simple values" {
            Set-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21" -Data "test-data"
            
            $result = Get-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21"
            
            $result | Should -Be "test-data"
        }
        
        It "Should store and retrieve hashtables" {
            $data = @{
                License = "MIT"
                Author = "John Doe"
            }
            
            Set-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21" -Data $data
            
            $result = Get-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21"
            
            $result.License | Should -Be "MIT"
            $result.Author | Should -Be "John Doe"
        }
        
        It "Should return null for missing keys" {
            $result = Get-CachedPackage -Cache $cache -Key "nonexistent:key"
            
            $result | Should -BeNullOrEmpty
        }
        
        It "Should overwrite existing entries" {
            Set-CachedPackage -Cache $cache -Key "test:key" -Data "value1"
            Set-CachedPackage -Cache $cache -Key "test:key" -Data "value2"
            
            $result = Get-CachedPackage -Cache $cache -Key "test:key"
            
            $result | Should -Be "value2"
            $cache.Count | Should -Be 1
        }
        
        It "Should handle multiple entries" {
            Set-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21" -Data "data1"
            Set-CachedPackage -Cache $cache -Key "nuget:Newtonsoft.Json@13.0.1" -Data "data2"
            Set-CachedPackage -Cache $cache -Key "vuln:npm:lodash@4.17.20" -Data "data3"
            
            $cache.Count | Should -Be 3
            Get-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21" | Should -Be "data1"
            Get-CachedPackage -Cache $cache -Key "nuget:Newtonsoft.Json@13.0.1" | Should -Be "data2"
            Get-CachedPackage -Cache $cache -Key "vuln:npm:lodash@4.17.20" | Should -Be "data3"
        }
    }
    
    Context "When exporting cache to file" {
        BeforeEach {
            $cache = Initialize-SBOMCache
            $testFile = Join-Path $TestDrive "cache-test.json"
        }
        
        It "Should export empty cache" {
            Export-SBOMCache -Cache $cache -FilePath $testFile
            
            Test-Path $testFile | Should -Be $true
            $content = Get-Content $testFile -Raw | ConvertFrom-Json
            $content.Entries.Count | Should -Be 0
        }
        
        It "Should export cache with entries" {
            Set-CachedPackage -Cache $cache -Key "npm:lodash@4.17.21" -Data @{ License = "MIT" }
            Set-CachedPackage -Cache $cache -Key "nuget:Newtonsoft.Json@13.0.1" -Data @{ License = "MIT" }
            
            Export-SBOMCache -Cache $cache -FilePath $testFile
            
            Test-Path $testFile | Should -Be $true
            $content = Get-Content $testFile -Raw | ConvertFrom-Json
            $content.Entries.Count | Should -Be 2
        }
        
        It "Should include export date in file" {
            Export-SBOMCache -Cache $cache -FilePath $testFile
            
            $content = Get-Content $testFile -Raw | ConvertFrom-Json
            $content.ExportDate | Should -Not -BeNullOrEmpty
        }
        
        It "Should create parent directory if missing" {
            $nestedPath = Join-Path $TestDrive "nested\dir\cache.json"
            
            Export-SBOMCache -Cache $cache -FilePath $nestedPath
            
            Test-Path $nestedPath | Should -Be $true
        }

        It "Should accept a cache file path on initialization and export using it" {
            $cacheFile = Join-Path $TestDrive "init-cache.json"
            $cacheWithPath = Initialize-SBOMCache -FilePath $cacheFile
            Set-CachedPackage -Cache $cacheWithPath -Key "npm:pkg@1.0.0" -Data @{ License = "MIT" }
            
            # Export explicitly passing the same FilePath
            Export-SBOMCache -Cache $cacheWithPath -FilePath $cacheFile
            Test-Path $cacheFile | Should -Be $true
            $content = Get-Content $cacheFile -Raw | ConvertFrom-Json
            $content.Entries.Count | Should -Be 1
        }

        It "Should load cache from an existing file when initialized with FilePath" {
            $cacheFile = Join-Path $TestDrive "preload-cache.json"
            $orig = Initialize-SBOMCache
            Set-CachedPackage -Cache $orig -Key "npm:pre@1.0.0" -Data @{ License = "MIT" }
            Export-SBOMCache -Cache $orig -FilePath $cacheFile
            
            $loaded = Initialize-SBOMCache -FilePath $cacheFile
            $loaded.GetType().Name | Should -Be "Hashtable"
            $loaded.Count | Should -Be 1
            $loaded.CacheFilePath | Should -Be $cacheFile
        }
    }
    
    Context "When importing cache from file" {
        BeforeEach {
            $testFile = Join-Path $TestDrive "cache-import-test.json"
        }
        
        It "Should return empty cache for missing file" {
            $cache = Import-SBOMCache -FilePath $testFile
            
            $cache.Count | Should -Be 0
        }
        
        It "Should import previously exported cache" {
            # Create and export cache
            $originalCache = Initialize-SBOMCache
            Set-CachedPackage -Cache $originalCache -Key "npm:lodash@4.17.21" -Data @{ License = "MIT"; Author = "John" }
            Set-CachedPackage -Cache $originalCache -Key "nuget:Json@13.0.1" -Data @{ License = "Apache" }
            Export-SBOMCache -Cache $originalCache -FilePath $testFile
            
            # Import cache
            $importedCache = Import-SBOMCache -FilePath $testFile
            
            $importedCache.Count | Should -Be 2
            $result1 = Get-CachedPackage -Cache $importedCache -Key "npm:lodash@4.17.21"
            $result1.License | Should -Be "MIT"
            $result1.Author | Should -Be "John"
        }
        
        It "Should handle empty cache file" {
            $emptyCache = Initialize-SBOMCache
            Export-SBOMCache -Cache $emptyCache -FilePath $testFile
            
            $cache = Import-SBOMCache -FilePath $testFile
            
            $cache.Count | Should -Be 0
        }
        
        It "Should handle invalid JSON gracefully" {
            Set-Content -Path $testFile -Value "{ invalid json }"
            
            $cache = Import-SBOMCache -FilePath $testFile
            
            $cache.Count | Should -Be 0
        }
    }
    
    Context "When clearing cache" {
        It "Should remove all entries" {
            $cache = Initialize-SBOMCache
            Set-CachedPackage -Cache $cache -Key "key1" -Data "value1"
            Set-CachedPackage -Cache $cache -Key "key2" -Data "value2"
            Set-CachedPackage -Cache $cache -Key "key3" -Data "value3"
            
            Clear-SBOMCache -Cache $cache
            
            $cache.Count | Should -Be 0
        }
        
        It "Should not affect other cache instances" {
            $cache1 = Initialize-SBOMCache
            $cache2 = Initialize-SBOMCache
            Set-CachedPackage -Cache $cache1 -Key "key1" -Data "value1"
            Set-CachedPackage -Cache $cache2 -Key "key2" -Data "value2"
            
            Clear-SBOMCache -Cache $cache1
            
            $cache1.Count | Should -Be 0
            $cache2.Count | Should -Be 1
        }
    }
    
    Context "When using cache in realistic scenario" {
        It "Should support round-trip export and import" {
            $cacheFile = Join-Path $TestDrive "realistic-cache.json"
            
            # First run - populate cache
            $cache1 = Initialize-SBOMCache
            Set-CachedPackage -Cache $cache1 -Key "npm:lodash@4.17.21" -Data @{ License = "MIT"; Author = "JDD" }
            Set-CachedPackage -Cache $cache1 -Key "npm:react@18.0.0" -Data @{ License = "MIT"; Author = "Facebook" }
            Set-CachedPackage -Cache $cache1 -Key "nuget:Newtonsoft.Json@13.0.1" -Data @{ License = "MIT" }
            Export-SBOMCache -Cache $cache1 -FilePath $cacheFile
            
            # Second run - load from cache
            $cache2 = Import-SBOMCache -FilePath $cacheFile
            
            $cache2.Count | Should -Be 3
            
            # Verify data integrity
            $lodash = Get-CachedPackage -Cache $cache2 -Key "npm:lodash@4.17.21"
            $lodash.License | Should -Be "MIT"
            $lodash.Author | Should -Be "JDD"
            
            # Add new entry and export again
            Set-CachedPackage -Cache $cache2 -Key "npm:vue@3.0.0" -Data @{ License = "MIT" }
            Export-SBOMCache -Cache $cache2 -FilePath $cacheFile
            
            # Third run - verify updated cache
            $cache3 = Import-SBOMCache -FilePath $cacheFile
            $cache3.Count | Should -Be 4
        }
    }
}
