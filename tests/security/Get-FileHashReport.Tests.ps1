BeforeAll {
    # Import the module
    Import-Module "$PSScriptRoot\..\..\src\security\Get-FileHashReport.psm1" -Force
}

Describe "Get-FileHashReport" {
    Context "When calculating hashes for a single file" {
        BeforeEach {
            $testFile = Join-Path $TestDrive "test-file.txt"
            Set-Content -Path $testFile -Value "Test content for hashing"
        }
        
        It "Should calculate all three hash algorithms" {
            $hashes = Get-MultiAlgorithmHash -FilePath $testFile
            
            $hashes | Should -Not -BeNullOrEmpty
            $hashes.SHA256 | Should -Not -BeNullOrEmpty
            $hashes.SHA1 | Should -Not -BeNullOrEmpty
            $hashes.MD5 | Should -Not -BeNullOrEmpty
        }
        
        It "Should include file metadata" {
            $hashes = Get-MultiAlgorithmHash -FilePath $testFile
            
            $hashes.FilePath | Should -Be $testFile
            $hashes.FileName | Should -Be "test-file.txt"
            $hashes.FileSize | Should -BeGreaterThan 0
        }
        
        It "Should produce consistent hashes for same content" {
            $hash1 = Get-MultiAlgorithmHash -FilePath $testFile
            $hash2 = Get-MultiAlgorithmHash -FilePath $testFile
            
            $hash1.SHA256 | Should -Be $hash2.SHA256
            $hash1.SHA1 | Should -Be $hash2.SHA1
            $hash1.MD5 | Should -Be $hash2.MD5
        }
        
        It "Should produce different hashes for different content" {
            $hash1 = Get-MultiAlgorithmHash -FilePath $testFile
            
            Set-Content -Path $testFile -Value "Different content"
            $hash2 = Get-MultiAlgorithmHash -FilePath $testFile
            
            $hash1.SHA256 | Should -Not -Be $hash2.SHA256
        }
        
        It "Should throw for non-existent file" {
            { Get-MultiAlgorithmHash -FilePath "C:\nonexistent\file.txt" } | Should -Throw
        }
    }
    
    Context "When creating hash reports for multiple files" {
        BeforeEach {
            $file1 = Join-Path $TestDrive "file1.txt"
            $file2 = Join-Path $TestDrive "file2.json"
            $file3 = Join-Path $TestDrive "file3.md"
            
            Set-Content -Path $file1 -Value "Content 1"
            Set-Content -Path $file2 -Value '{"key": "value"}'
            Set-Content -Path $file3 -Value "# Markdown"
        }
        
        It "Should create report for multiple files" {
            $files = @($file1, $file2, $file3)
            $report = New-HashReport -Files $files
            
            $report | Should -Not -BeNullOrEmpty
            $report.FileCount | Should -Be 3
            $report.Files.Count | Should -Be 3
        }
        
        It "Should include generation timestamp" {
            $report = New-HashReport -Files @($file1)
            
            $report.GeneratedDate | Should -Not -BeNullOrEmpty
            $report.GeneratedDate | Should -Match "\d{4}-\d{2}-\d{2}"
        }
        
        It "Should handle empty file list" {
            $report = New-HashReport -Files @()
            
            $report.FileCount | Should -Be 0
            $report.Files.Count | Should -Be 0
        }
        
        It "Should skip non-existent files with warning" {
            $files = @($file1, "C:\nonexistent.txt", $file2)
            
            $report = New-HashReport -Files $files -WarningAction SilentlyContinue
            
            $report.FileCount | Should -Be 2
        }
    }
    
    Context "When exporting hash reports" {
        BeforeEach {
            $testFile = Join-Path $TestDrive "source.txt"
            Set-Content -Path $testFile -Value "Test content"
            
            $report = New-HashReport -Files @($testFile)
            $outputPath = Join-Path $TestDrive "hash-report.txt"
        }
        
        It "Should create hash report file" {
            Export-HashReport -Report $report -OutputPath $outputPath
            
            Test-Path $outputPath | Should -Be $true
        }
        
        It "Should include all hash algorithms in output" {
            Export-HashReport -Report $report -OutputPath $outputPath
            
            $content = Get-Content $outputPath -Raw
            
            $content | Should -Match "SHA256:"
            $content | Should -Match "SHA1:"
            $content | Should -Match "MD5:"
        }
        
        It "Should include file metadata in output" {
            Export-HashReport -Report $report -OutputPath $outputPath
            
            $content = Get-Content $outputPath -Raw
            
            $content | Should -Match "File:"
            $content | Should -Match "Path:"
            $content | Should -Match "Size:"
        }
        
        It "Should create parent directory if needed" {
            $nestedPath = Join-Path $TestDrive "nested\dir\report.txt"
            
            Export-HashReport -Report $report -OutputPath $nestedPath
            
            Test-Path $nestedPath | Should -Be $true
        }
    }
    
    Context "When converting to markdown format" {
        BeforeEach {
            $file1 = Join-Path $TestDrive "doc.md"
            $file2 = Join-Path $TestDrive "data.json"
            
            Set-Content -Path $file1 -Value "# Title"
            Set-Content -Path $file2 -Value '{"test": true}'
            
            $report = New-HashReport -Files @($file1, $file2)
        }
        
        It "Should generate valid markdown" {
            $markdown = ConvertTo-HashMarkdown -Report $report
            
            $markdown | Should -Not -BeNullOrEmpty
            $markdown | Should -Match "##"
            $markdown | Should -Match "###"
        }
        
        It "Should include markdown tables" {
            $markdown = ConvertTo-HashMarkdown -Report $report
            
            $markdown | Should -Match "\| Property \| Value \|"
            $markdown | Should -Match "\|----------|-------|"
        }
        
        It "Should format hashes as code blocks" {
            $markdown = ConvertTo-HashMarkdown -Report $report
            
            $markdown | Should -Match "``[A-F0-9]+``"
        }
        
        It "Should include all files in report" {
            $markdown = ConvertTo-HashMarkdown -Report $report
            
            $markdown | Should -Match "doc\.md"
            $markdown | Should -Match "data\.json"
        }
    }
    
    Context "When using in realistic scenario" {
        It "Should generate complete hash report workflow" {
            # Create test files
            $sbomFile = Join-Path $TestDrive "manifest.json"
            $markdownFile = Join-Path $TestDrive "report.md"
            Set-Content -Path $sbomFile -Value '{"packages": []}'
            Set-Content -Path $markdownFile -Value "# SBOM Report"
            
            # Generate hashes
            $files = @($sbomFile, $markdownFile)
            $report = New-HashReport -Files $files
            
            # Verify report
            $report.FileCount | Should -Be 2
            $report.Files | ForEach-Object {
                $_.SHA256 | Should -Match "^[A-F0-9]{64}$"
                $_.SHA1 | Should -Match "^[A-F0-9]{40}$"
                $_.MD5 | Should -Match "^[A-F0-9]{32}$"
            }
            
            # Export as text
            $textReport = Join-Path $TestDrive "hashes.txt"
            Export-HashReport -Report $report -OutputPath $textReport
            Test-Path $textReport | Should -Be $true
            
            # Export as markdown
            $markdownReport = ConvertTo-HashMarkdown -Report $report
            $markdownReport | Should -Not -BeNullOrEmpty
            
            # Verify file can be re-hashed and matches
            $originalSbomHash = ($report.Files | Where-Object { $_.FileName -eq "manifest.json" }).SHA256
            $recheck = Get-MultiAlgorithmHash -FilePath $sbomFile
            $recheck.SHA256 | Should -Be $originalSbomHash
        }
    }
}
