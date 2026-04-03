Describe 'Get-7ZipLocation' {
    BeforeEach {
        $modulePath = Join-Path $PSScriptRoot '..\src\fileManipulation\Get-7zipLocation.psm1'
        Import-Module -Force $modulePath
    }

    It 'returns an existing 7zip executable from PATH before downloading' {
        InModuleScope Get-7zipLocation {
            Mock Get-Command {
                [pscustomobject]@{
                    Source = 'C:\Tools\7-Zip\7z.exe'
                }
            }

            Mock Test-Path {
                param($Path)
                return $Path -eq 'C:\Tools\7-Zip\7z.exe'
            }

            Mock Invoke-WebRequest {}
            Mock Expand-WithFramework {}

            $result = Get-7ZipLocation

            $result | Should -Be 'C:\Tools\7-Zip\7z.exe'
            Should -Invoke Invoke-WebRequest -Times 0
            Should -Invoke Expand-WithFramework -Times 0
        }
    }

    It 'downloads 7zip in a stable cache folder when no local executable is available' {
        InModuleScope Get-7zipLocation {
            $env:AGENT_TOOLSDIRECTORY = 'C:\agent\_tool'
            $env:LOCALAPPDATA = ''
            $env:ProgramData = 'C:\ProgramData'
            $env:TEMP = 'C:\Temp'

            Mock Get-Command { $null }
            Mock Test-Path {
                param($Path)
                return $false
            }
            Mock New-Item {}
            Mock Invoke-WebRequest {}
            Mock Expand-WithFramework {}

            $result = Get-7ZipLocation

            $result | Should -Be 'C:\agent\_tool\BuildUtils\tools\7zip\7za.exe'
            Should -Invoke New-Item -Times 1 -ParameterFilter { $Path -eq 'C:\agent\_tool\BuildUtils\tools' }
            Should -Invoke Invoke-WebRequest -Times 1 -ParameterFilter {
                $Uri -eq 'https://www.7-zip.org/a/7za920.zip' -and
                $OutFile -eq 'C:\agent\_tool\BuildUtils\tools\7za920.zip'
            }
            Should -Invoke Expand-WithFramework -Times 1 -ParameterFilter {
                $zipFile -eq 'C:\agent\_tool\BuildUtils\tools\7za920.zip' -and
                $destinationFolder -eq 'C:\agent\_tool\BuildUtils\tools\7zip'
            }
        }
    }
}
