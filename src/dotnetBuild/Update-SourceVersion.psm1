

<#
.SYNOPSIS
Manipulate all assemblyinfo.vb and assemblyinfo.cs to change version 

.DESCRIPTION
With legacy .NET project versioning is done with specific attribtues
inside assemblyinfo.cs and assemblyinfo.vb files. This cmdlet
can scan all files and perform a substitution.

This should be done before compiling (and usually after version is 
determined with tools like gitversion)

This is a perfect match for Invoke-Getversion function

.PARAMETER SrcPath
Source path

.PARAMETER assemblyVersion
AssemblyVersionAttribute

.PARAMETER fileAssemblyVersion
FileAssemblyVersionAttribute

.PARAMETER assemblyInformationalVersion
AssemblyinformationalVersion

.EXAMPLE

$version = Invoke-GitVersion
Update-SourceVersion -SrcPath PathWithSource -assemblyVersion $version.assemblyVersion -fileAssemblyVersion $version.assemblyFileVersion -assemblyInformationalVersion = $version.assemblyInformationalVersion

#>
function Update-SourceVersion
{
  Param 
  (
    [string]$SrcPath,
    [string]$assemblyVersion, 
    [string]$fileAssemblyVersion,
    [string]$assemblyInformationalVersion,
    [bool]$modifyAssemblyVersion = $true
  )
    
    if ($fileAssemblyVersion -eq "")
    {
        $fileAssemblyVersion = $assemblyVersion
    }

        
    if ($assemblyInformationalVersion -eq "")
    {
        $assemblyInformationalVersion = $fileAssemblyVersion
    }
    
    Write-Debug "Executing Update-SourceVersion in path $SrcPath, Version is $assemblyVersion and File Version is $fileAssemblyVersion and Informational Version is $assemblyInformationalVersion"
        
    $AllVersionFiles = Get-ChildItem $SrcPath\* -Include AssemblyInfo.cs,AssemblyInfo.vb -recurse
  
    foreach ($file in $AllVersionFiles)
    { 
      Write-Debug "Modifying file " + $file.FullName
      #save the file for restore
      $backFile = $file.FullName + "._ORI"

      Copy-Item $file.FullName $backFile -Force
      #now load all content of the original file and rewrite modified to the same file
      $content = Get-Content $file.FullName 
      Remove-Item $file.FullName
      if ($modifyAssemblyVersion) 
      {
        $content |
          %{$_ -replace 'AssemblyVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', "AssemblyVersion(""$assemblyVersion"")" } |
          %{$_ -replace 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', "AssemblyFileVersion(""$fileAssemblyVersion"")" } |
          %{$_ -replace 'AssemblyInformationalVersion\(".*"\)', "AssemblyInformationalVersion(""$assemblyInformationalVersion"")" } |
          Set-Content -Encoding UTF8 -Path $file.FullName -Force
      }
      else {
        $content |
          %{$_ -replace 'AssemblyFileVersion\("[0-9]+(\.([0-9]+|\*)){1,3}"\)', "AssemblyFileVersion(""$fileAssemblyVersion"")" } |
          %{$_ -replace 'AssemblyInformationalVersion\(".*"\)', "AssemblyInformationalVersion(""$assemblyInformationalVersion"")" } |
          Set-Content -Encoding UTF8 -Path $file.FullName -Force
      }
    }
}