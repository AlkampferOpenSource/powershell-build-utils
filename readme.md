# Simple repository for various PowerShell scripts

## How to consume feed repository

### If you want to publish packages in private repository

First step is register the feed where the package is published, as an example here is my public MyGet feed location. **Be sure to use v2 version of feed, because at the time of this readme PowerShell works with v2 nuget package version**

```Powershell
Register-PSRepository -Name MyGet -SourceLocation https://www.myget.org/F/alkampfer/api/v2
```

### How to consume package from a repository (public or private)

You should be able to find this module with the following command

```Powershell
PS C:\somedir> Find-Module -Name build-utils

Version    Name                                Repository           Description
-------    ----                                ----------           -----------
0.x.x      build-utils                         PSGallery            Simple utilities to simplify build of .NET project
```

If everything is done correctly, we can install the module for the current user with this command (this will not require administrative permissions and install module for current user only)

```Powershell
Install-package build-utils -Confirm:$false -Force -Scope CurrentUser -Verbose
```

Once the package is installed successfully, you can import it and verify all the functions that are available for usage

```Powershell
PS C:\somedir> Import-Module build-utils
PS C:\somedir> Get-Command -module build-utils

CommandType     Name                                               Version    Source
-----------     ----                                               -------    ------
Function        Edit-XmlNodes                                      0.1.2      build-utils
Function        Get-7ZipLocation                                   0.1.2      build-utils
Function        Update-SourceVersion                               0.1.2      build-utils
```

You should be able now to simply use and manage those functions.

## How to publish manually (if you want to add it to private gallery)

After you aligned version in .nuspec and .psd1 file, just run nuget to create package file. You can
run following command in the src directory.

```Powershell
nuget.exe pack .\build-utils.nuspec
```

This will create a nuget package that can be pushed on a specific feed by this command 

```Powershell
nuget.exe push build-utils.0.1.1.nupkg yourapikey -src https://www.myget.org/F/alkampfer/api/v3/index.json
```

To verify that the module is correct you can check for package correctness with the command

```Powershell
Test-ModuleManifest -Path .\build-utils.psd1
```
