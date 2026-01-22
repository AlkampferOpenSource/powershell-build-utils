BeforeAll {
    # Import the function to test
    Import-Module "$PSScriptRoot\..\src\fileManipulation\Edit-XmlNodes.psm1" -Force
}

Describe "Edit-XmlNodes" {
    
    Context "When editing XML element values" {
        BeforeEach {
            # Create a sample XML document for testing
            $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <appSettings>
        <add key="apiClientSecret" value="originalSecret" />
        <add key="connectionString" value="Server=localhost" />
    </appSettings>
    <system.web>
        <compilation debug="true" />
    </system.web>
</configuration>
"@
            $script:xml = [xml]$xmlContent
        }

        It "Should update an attribute value" {
            # Act
            Edit-XmlNodes -doc $xml -xpath "/configuration/appSettings/add[@key='apiClientSecret']/@value" -value "__APICLIENTSECRET__"
            
            # Assert
            $actualValue = $xml.SelectSingleNode("/configuration/appSettings/add[@key='apiClientSecret']/@value").Value
            $actualValue | Should -Be "__APICLIENTSECRET__"
        }

        It "Should update an element's inner XML" {
            # Act
            Edit-XmlNodes -doc $xml -xpath "/configuration/system.web/compilation/@debug" -value "false"
            
            # Assert
            $actualValue = $xml.SelectSingleNode("/configuration/system.web/compilation/@debug").Value
            $actualValue | Should -Be "false"
        }

        It "Should update multiple nodes matching XPath" {
            # Arrange - Add another element with same structure
            $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <appSettings>
        <add key="setting1" value="value1" />
        <add key="setting2" value="value2" />
        <add key="setting3" value="value3" />
    </appSettings>
</configuration>
"@
            $xml = [xml]$xmlContent

            # Act - Update all values
            Edit-XmlNodes -doc $xml -xpath "/configuration/appSettings/add/@value" -value "__TOKEN__"
            
            # Assert
            $nodes = $xml.SelectNodes("/configuration/appSettings/add/@value")
            $nodes.Count | Should -Be 3
            foreach ($node in $nodes) {
                $node.Value | Should -Be "__TOKEN__"
            }
        }

        It "Should update element InnerXml when node is an Element" {
            # Act
            Edit-XmlNodes -doc $xml -xpath "/configuration/system.web" -value "<customElement>test</customElement>"
            
            # Assert
            $actualValue = $xml.SelectSingleNode("/configuration/system.web").InnerXml
            $actualValue | Should -Be "<customElement>test</customElement>"
        }
    }

    Context "When condition parameter is used" {
        BeforeEach {
            $xmlContent = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <appSettings>
        <add key="testKey" value="originalValue" />
    </appSettings>
</configuration>
"@
            $script:xml = [xml]$xmlContent
        }

        It "Should update XML when condition is true" {
            # Act
            Edit-XmlNodes -doc $xml -xpath "/configuration/appSettings/add/@value" -value "newValue" -condition $true
            
            # Assert
            $actualValue = $xml.SelectSingleNode("/configuration/appSettings/add/@value").Value
            $actualValue | Should -Be "newValue"
        }

        It "Should not update XML when condition is false" {
            # Act
            Edit-XmlNodes -doc $xml -xpath "/configuration/appSettings/add/@value" -value "newValue" -condition $false
            
            # Assert
            $actualValue = $xml.SelectSingleNode("/configuration/appSettings/add/@value").Value
            $actualValue | Should -Be "originalValue"
        }
    }

    Context "When handling edge cases" {
        It "Should throw when doc parameter is missing" {
            # Act & Assert
            { Edit-XmlNodes -xpath "/some/path" -value "value" } | Should -Throw "*doc is a required parameter*"
        }

        It "Should throw when xpath parameter is missing" {
            # Arrange
            $xml = [xml]"<root></root>"
            
            # Act & Assert
            { Edit-XmlNodes -doc $xml -value "value" } | Should -Throw "*xpath is a required parameter*"
        }

        It "Should throw when value parameter is missing" {
            # Arrange
            $xml = [xml]"<root></root>"
            
            # Act & Assert
            { Edit-XmlNodes -doc $xml -xpath "/root" } | Should -Throw "*value is a required parameter*"
        }

        It "Should handle XPath that matches no nodes gracefully" {
            # Arrange
            $xml = [xml]"<root><child>value</child></root>"
            
            # Act - XPath that doesn't match anything
            { Edit-XmlNodes -doc $xml -xpath "/nonexistent/path" -value "newValue" } | Should -Not -Throw
            
            # Assert - XML should remain unchanged
            $xml.root.child | Should -Be "value"
        }
    }

    Context "When working with real configuration files" {
        BeforeEach {
            # Create a temporary directory for test files
            $script:testDir = Join-Path $TestDrive "XmlTests"
            New-Item -Path $testDir -ItemType Directory -Force | Out-Null
        }

        It "Should tokenize a web.config file" {
            # Arrange
            $configPath = Join-Path $testDir "web.config"
            $configContent = @"
<?xml version="1.0" encoding="utf-8"?>
<configuration>
    <appSettings>
        <add key="apiClientSecret" value="realSecretValue123" />
        <add key="connectionString" value="Server=prod.database.com;Database=MyDb" />
    </appSettings>
</configuration>
"@
            Set-Content -Path $configPath -Value $configContent
            
            # Act
            $xml = [xml](Get-Content $configPath)
            Edit-XmlNodes -doc $xml -xpath "/configuration/appSettings/add[@key='apiClientSecret']/@value" -value "__APICLIENTSECRET__"
            Edit-XmlNodes -doc $xml -xpath "/configuration/appSettings/add[@key='connectionString']/@value" -value "__CONNECTIONSTRING__"
            $xml.Save($configPath)
            
            # Assert
            $savedXml = [xml](Get-Content $configPath)
            $secretValue = $savedXml.SelectSingleNode("/configuration/appSettings/add[@key='apiClientSecret']/@value").Value
            $connValue = $savedXml.SelectSingleNode("/configuration/appSettings/add[@key='connectionString']/@value").Value
            
            $secretValue | Should -Be "__APICLIENTSECRET__"
            $connValue | Should -Be "__CONNECTIONSTRING__"
        }
    }
}
