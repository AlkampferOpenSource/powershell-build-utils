<#
.SYNOPSIS
Generate cryptographic hashes and reports for files

.DESCRIPTION
Provides functions to calculate multiple hash algorithms (SHA256, SHA1, MD5) for files
and generate formatted hash reports. Useful for file integrity verification and SBOM documentation.

.EXAMPLE
$hashes = Get-MultiAlgorithmHash -FilePath "C:\files\document.pdf"
Write-Host "SHA256: $($hashes.SHA256)"

.EXAMPLE
$report = New-HashReport -Files @("file1.txt", "file2.json")
Export-HashReport -Report $report -OutputPath "hashes.txt"

.NOTES
Uses Get-FileHash cmdlet for hash calculations.
#>

function Get-MultiAlgorithmHash {
    <#
    .SYNOPSIS
    Calculate SHA256, SHA1, and MD5 hashes for a file
    
    .DESCRIPTION
    Computes multiple cryptographic hashes for a single file in one call.
    Returns all hash values in a structured object.
    
    .PARAMETER FilePath
    Path to the file to hash
    
    .OUTPUTS
    PSCustomObject with properties: FilePath, FileName, FileSize, SHA256, SHA1, MD5
    
    .EXAMPLE
    $hashes = Get-MultiAlgorithmHash -FilePath ".\output.md"
    Write-Host "File: $($hashes.FileName)"
    Write-Host "SHA256: $($hashes.SHA256)"
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$true)]
        [ValidateScript({ Test-Path $_ })]
        [string] $FilePath
    )
    
    try {
        $fileInfo = Get-Item -Path $FilePath -ErrorAction Stop
        
        $sha256Hash = Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop
        $sha1Hash = Get-FileHash -Path $FilePath -Algorithm SHA1 -ErrorAction Stop
        $md5Hash = Get-FileHash -Path $FilePath -Algorithm MD5 -ErrorAction Stop
        
        return [PSCustomObject]@{
            FilePath = $FilePath
            FileName = $fileInfo.Name
            FileSize = $fileInfo.Length
            SHA256 = $sha256Hash.Hash
            SHA1 = $sha1Hash.Hash
            MD5 = $md5Hash.Hash
        }
    }
    catch {
        Write-Error "Failed to calculate hashes for ${FilePath}: $_"
        return $null
    }
}

function New-HashReport {
    <#
    .SYNOPSIS
    Generate a hash report for multiple files
    
    .DESCRIPTION
    Creates a structured report containing hash values for one or more files.
    Includes metadata like generation timestamp and file sizes.
    
    .PARAMETER Files
    Array of file paths to include in the report
    
    .OUTPUTS
    PSCustomObject containing report metadata and file hashes
    
    .EXAMPLE
    $report = New-HashReport -Files @("output.md", "manifest.json")
    
    .EXAMPLE
    $files = Get-ChildItem ".\output" -File
    $report = New-HashReport -Files $files.FullName
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory=$false)]
        [AllowEmptyCollection()]
        [string[]] $Files = @()
    )
    
    $fileHashes = @()
    
    foreach ($file in $Files) {
        if (Test-Path $file) {
            $hash = Get-MultiAlgorithmHash -FilePath $file
            if ($hash) {
                $fileHashes += $hash
            }
        }
        else {
            Write-Warning "File not found: $file"
        }
    }
    
    return [PSCustomObject]@{
        GeneratedDate = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        FileCount = $fileHashes.Count
        Files = $fileHashes
    }
}

function Export-HashReport {
    <#
    .SYNOPSIS
    Save a hash report to a text file
    
    .DESCRIPTION
    Exports a hash report in human-readable format with sections for each file.
    Creates parent directory if needed.
    
    .PARAMETER Report
    The report object from New-HashReport
    
    .PARAMETER OutputPath
    Destination path for the report file
    
    .EXAMPLE
    Export-HashReport -Report $report -OutputPath ".\hashes.txt"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Report,
        
        [Parameter(Mandatory=$true)]
        [string] $OutputPath
    )
    
    # Ensure parent directory exists
    $parentDir = Split-Path -Path $OutputPath -Parent
    if ($parentDir -and -not (Test-Path $parentDir)) {
        New-Item -Path $parentDir -ItemType Directory -Force | Out-Null
    }
    
    try {
        $lines = @()
        $lines += "File Hash Report"
        $lines += "=" * 80
        $lines += "Generated: $($Report.GeneratedDate)"
        $lines += "Files Processed: $($Report.FileCount)"
        $lines += ""
        
        foreach ($file in $Report.Files) {
            $lines += "-" * 80
            $lines += "File: $($file.FileName)"
            $lines += "Path: $($file.FilePath)"
            $lines += "Size: $($file.FileSize) bytes"
            $lines += ""
            $lines += "SHA256: $($file.SHA256)"
            $lines += "SHA1:   $($file.SHA1)"
            $lines += "MD5:    $($file.MD5)"
            $lines += ""
        }
        
        $lines += "=" * 80
        
        $content = $lines -join "`n"
        Set-Content -Path $OutputPath -Value $content -Encoding UTF8
        
        Write-Verbose "Hash report exported to $OutputPath"
    }
    catch {
        Write-Error "Failed to export hash report to ${OutputPath}: $_"
    }
}

function ConvertTo-HashMarkdown {
    <#
    .SYNOPSIS
    Convert hash report to markdown format
    
    .DESCRIPTION
    Generates markdown-formatted hash information suitable for inclusion in documentation.
    
    .PARAMETER Report
    The report object from New-HashReport
    
    .OUTPUTS
    String containing markdown-formatted hash report
    
    .EXAMPLE
    $markdown = ConvertTo-HashMarkdown -Report $report
    Add-Content -Path "README.md" -Value $markdown
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $Report
    )
    
    $lines = @()
    $lines += "## File Integrity Hashes"
    $lines += ""
    $lines += "*Generated: $($Report.GeneratedDate)*"
    $lines += ""
    
    foreach ($file in $Report.Files) {
        $lines += "### $($file.FileName)"
        $lines += ""
        $lines += "| Property | Value |"
        $lines += "|----------|-------|"
        $lines += "| **File Path** | ``$($file.FilePath)`` |"
        $lines += "| **File Size** | $($file.FileSize) bytes |"
        $lines += "| **SHA256** | ``$($file.SHA256)`` |"
        $lines += "| **SHA1** | ``$($file.SHA1)`` |"
        $lines += "| **MD5** | ``$($file.MD5)`` |"
        $lines += ""
    }
    
    return $lines -join "`n"
}

Export-ModuleMember -Function Get-MultiAlgorithmHash, New-HashReport, Export-HashReport, ConvertTo-HashMarkdown
