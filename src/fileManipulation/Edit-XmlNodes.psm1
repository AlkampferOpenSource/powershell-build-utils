
<#
.SYNOPSIS
Simply allow for easy XML node manipulation in context of classic .NET xml configuration
files. The purpose is to substitute specific part of the configuration file with 
predetermined tokens.

.DESCRIPTION
Basically takes an XML object and then perform a lookup of a specific part of the XML with
standard XPATH notation and perform a substitution.

.EXAMPLE

$configFile = "somedirecory/web.config"
$xml = [xml](Get-Content $configFile)
Edit-XmlNodes $xml -xpath "/configuration/appSettings/add[@key='apiClientSecret']/@value" -value "__APICLIENTSECRET__"
$xml.save($configFile)

.NOTES

#>
function Edit-XmlNodes {
    param (
        [xml] $doc = $(throw "doc is a required parameter"),
        [string] $xpath = $(throw "xpath is a required parameter"),
        [string] $value = $(throw "value is a required parameter"),
        [bool] $condition = $true
    )    
        if ($condition -eq $true) {
            $nodes = $doc.SelectNodes($xpath)
             
            foreach ($node in $nodes) {
                if ($node -ne $null) {
                    if ($node.NodeType -eq "Element") {
                        $node.InnerXml = $value
                    }
                    else {
                        $node.Value = $value
                    }
                }
            }
        }
    }
  