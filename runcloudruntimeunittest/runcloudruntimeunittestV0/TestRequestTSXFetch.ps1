<#
.SYNOPSIS
    This file helps create and execute tests for UDE.
    
    Copyright © 2024 Microsoft. All rights reserved.
#>

function Get-TestTSXDirectory {
    [Cmdletbinding()]
	param(
		[Parameter(Mandatory)]
		[string[]]$potentialPackages,
        [string]$compilerPathInput,
        [string]$platformPathInput
	)

    try
    {
        $packages = @()
        if ($potentialPackages.Length -gt 0)
        {
            Write-Host "Found $($potentialPackages.Length) potential folders to include:"
            foreach($package in $potentialPackages)
            {
                $packageBinPath = Join-Path -Path $package -ChildPath "bin"
                # If there is a bin folder and it contains *.MD files, assume it's a valid X++ binary
                if ((Test-Path -Path $packageBinPath) -and ((Get-ChildItem -Path $packageBinPath -Filter *.md).Count -gt 0))
                {
                    Write-Host "  - $package"
                    $packages += $package
                }
                else
                {
                    Write-Warning "  - $package (not an X++ binary folder, skipped)"
                }
            }


            $dllFiles = @("<SysTest><Partition>initial</Partition><RuntimePackagesDirectory>$platformPathInput</RuntimePackagesDirectory><FrameworkBinDirectory>$compilerPathInput</FrameworkBinDirectory></SysTest>")
            foreach ($directory in $packages) {
                $dllFiles += Get-ChildItem -Path $directory -Filter *.dll -File -Recurse | Select-Object -ExpandProperty FullName
            }

            #calling to get tsx from the dlls
            $tsxresult = TestRequestTSXFetch -dllList $dllFiles -compilerPathValue $compilerPathInput
            if ($tsxresult -eq "")
            {
                throw
            }
            else {
                return $tsxresult
            }
        }
    }
    finally
    {
    }
}

function TestRequestTSXFetch {
	param(
		[Parameter(Mandatory)]
		[string[]]$dllList,
        [Parameter(Mandatory)]
        [string]$compilerPathValue
	)

    $vers = ".17.0"
    try 
    {
        if (Test-Path (Join-Path -Path $compilerPathValue -ChildPath "Microsoft.Dynamics.Framework.Tools.Configuration$($vers).dll"))
        {
            Write-Host "Version 17 available"
        }
        else
        {
            $vers = ""
            if (Test-Path (Join-Path -Path $compilerPathValue -ChildPath "Microsoft.Dynamics.Framework.Tools.Configuration$($vers).dll"))
            {
                Write-Host "Default available"
            }
            else
            {
                $_.Exception
                throw "Invalid compiler package path, please modify and rerun."
            }
        }
        Copy-Item (Join-Path -Path $compilerPathValue -ChildPath "Microsoft.Dynamics.Framework.Tools.Configuration$($vers).dll") -Destination (Join-Path -Path $PSScriptRoot -ChildPath "CloudRuntimeDlls\Microsoft.Dynamics.Framework.Tools.Configuration$($vers).dll") -Force
        Copy-Item (Join-Path -Path $compilerPathValue -ChildPath "Microsoft.Dynamics.Framework.Tools.Core$($vers).dll") -Destination (Join-Path -Path $PSScriptRoot -ChildPath "CloudRuntimeDlls\Microsoft.Dynamics.Framework.Tools.Core$($vers).dll") -Force
        Copy-Item (Join-Path -Path $compilerPathValue -ChildPath "Microsoft.Dynamics.Framework.Tools.MetaModel.Core$($vers).dll") -Destination (Join-Path -Path $PSScriptRoot -ChildPath "CloudRuntimeDlls\Microsoft.Dynamics.Framework.Tools.MetaModel.Core$($vers).dll") -Force
        Write-Host "Imported necessary files"
    }
    catch
    {
        $_.Exception
        throw "Invalid compiler package path, please modify and rerun. Supported platform version 64 or higher."
    }

    try
    {
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.VisualStudio.TestPlatform.ObjectModel.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Dynamics.TestTools$($vers).TestAdapter.dll"
    }
    catch
    {
        #$_.Exception.LoaderExceptions
        Write-Host "Proceeding"
    }

    $assemblies = ("System", "System.Xml", "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Dynamics.TestTools$($vers).TestAdapter.dll", "$PSScriptRoot\CloudRuntimeDlls\Microsoft.VisualStudio.TestPlatform.ObjectModel.dll")
        
    $id = get-random
    $code = 
@"
    using Microsoft.Dynamics.TestTools.TestAdapter.Discovery;
    using Microsoft.Dynamics.TestTools.TestAdapter.Execution;
    using Microsoft.VisualStudio.TestPlatform.ObjectModel;
    using Microsoft.VisualStudio.TestPlatform.ObjectModel.Adapter;
    using Microsoft.VisualStudio.TestPlatform.ObjectModel.Logging;
    using System;
    using System.Collections.Generic;
    using System.IO;
    using System.Linq;
    using System.Threading.Tasks;
    using System.Xml;
    namespace TestExecutionTSX
    {
        public class Program$id
        {
            public static string MainCreate(string[] args)
            {
                try
                {
                    for(int i = 0; i< args.Length; i++)
                    Console.WriteLine(args[i]);

                    var sources = args.Skip(1).ToList();
                    Console.WriteLine(sources[0]);
                    var settingxml = args[0];
                    var discoverContext = new DiscoverContext(settingxml);
                    var msgLogger = new MessageLogger();
                    var discoverySink = new TestCaseDiscoverySink();
                    var systestDiscoverer = new SysTestDiscoverer();
                    systestDiscoverer.DiscoverPipelineTests(sources, discoverContext, msgLogger, discoverySink);
                    Console.WriteLine("Found Test Cases: " + discoverySink.testCases.Count);

                    var executor = new SysTestExecutor();
                    var caseList = discoverySink.testCases.GroupBy(testCase => testCase.Source);
                    var testSuites = new List<TestSuite>();
                    foreach (var entry in caseList)
                    {
                        testSuites.AddRange(executor.CreateTestSuites(entry.Key, entry.OrderBy(tc => tc.DisplayName)));
                    }
                    var tempFolderName = DateTime.UtcNow.ToFileTimeUtc().ToString();
                    var suiteDirectory = Path.Combine(Path.GetTempPath(), executor.FinOpsTestRequestPackaging, tempFolderName);
                    var suiteListFile = Path.Combine(suiteDirectory, "testSuiteList.txt");
                    var insideTestSuite = Path.Combine(suiteDirectory, "TestSuites");
                    SysTestExecutor.SaveTestSuites(insideTestSuite, suiteListFile, testSuites);
                    return insideTestSuite;
                }
                catch (Exception ex)
                {
                    Console.WriteLine("Error discovering tests: " + ex.Message);
                }
                return string.Empty;
            }

            public class DiscoverContext : IDiscoveryContext
            {
                // Implement the interface members here
                public string PipelineSettingsXml;

                public DiscoverContext(string PipelineSettingsXml)
                {
                    this.PipelineSettingsXml = PipelineSettingsXml;
                    this.RunSettings = new RunSettings(PipelineSettingsXml);
                }

                public IRunSettings RunSettings {get; set;}
            }

            public class RunSettings : IRunSettings
            {
                public RunSettings(string pipelineSettingsXml)
                {
                    PipelineSettingsXml = pipelineSettingsXml;
                }

                public string SettingsXml { get; set; }
                public string PipelineSettingsXml { get; set; }

                public ISettingsProvider GetSettings(string settingsName)
                {
                    if (string.Equals(settingsName, Microsoft.Dynamics.TestTools.TestAdapter.Constants.SysTestSettingsName))
                    {
                        var testSettingProvider = new Microsoft.Dynamics.TestTools.TestAdapter.SysTestSettingsProvider();
                        using (var stringReader = new StringReader(this.PipelineSettingsXml))
                        using (XmlReader reader = XmlReader.Create(stringReader))
                        {
                            testSettingProvider.Load(reader);
                        }
                        return testSettingProvider;
                    }
                    return null;
                }
            }

            public class MessageLogger : IMessageLogger
            {
                public void SendMessage(TestMessageLevel testMessageLevel, string message)
                {
                    Console.WriteLine(testMessageLevel + ":" + message);
                }
            }

            public class TestCaseDiscoverySink : ITestCaseDiscoverySink
            {
                public IList<TestCase> testCases;

                public TestCaseDiscoverySink()
                {
                    this.testCases = new List<TestCase>();
                }

                public void SendTestCase(TestCase discoveredTest)
                {
                    Console.WriteLine("Adding Test Case: " + discoveredTest.FullyQualifiedName);
                    this.testCases.Add(discoveredTest);
                }
            }
        }
    }
"@

    try
    {
        Write-Host "Starting fetching of test request tsx:"
        Add-Type -ReferencedAssemblies $assemblies -TypeDefinition $code -Language CSharp
        [System.AppContext]::SetSwitch('Switch.System.IO.Compression.ZipFile.UseBackslash', $false)
        $argumentString = @('"' + ($dllList -join '","') + '"')
        $tsxLocation = ""
        Invoke-Expression "[TestExecutionTSX.Program$id]::MainCreate(@($argumentString))" | Tee-Object -Var tsxLocation
        Write-Host "Ending test tsx fetch request"
    }
    finally
    {
        
    }
}
# SIG # Begin signature block
# MIIoCwYJKoZIhvcNAQcCoIIn/DCCJ/gCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDXkNStRs2lbEet
# CX5Nm4HYO/cJrvyi9qiD55WrX4z9KqCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
# Bv9XKydyAAAAAAQEMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjQwOTEyMjAxMTE0WhcNMjUwOTExMjAxMTE0WjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQC0KDfaY50MDqsEGdlIzDHBd6CqIMRQWW9Af1LHDDTuFjfDsvna0nEuDSYJmNyz
# NB10jpbg0lhvkT1AzfX2TLITSXwS8D+mBzGCWMM/wTpciWBV/pbjSazbzoKvRrNo
# DV/u9omOM2Eawyo5JJJdNkM2d8qzkQ0bRuRd4HarmGunSouyb9NY7egWN5E5lUc3
# a2AROzAdHdYpObpCOdeAY2P5XqtJkk79aROpzw16wCjdSn8qMzCBzR7rvH2WVkvF
# HLIxZQET1yhPb6lRmpgBQNnzidHV2Ocxjc8wNiIDzgbDkmlx54QPfw7RwQi8p1fy
# 4byhBrTjv568x8NGv3gwb0RbAgMBAAGjggFzMIIBbzAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU8huhNbETDU+ZWllL4DNMPCijEU4w
# RQYDVR0RBD4wPKQ6MDgxHjAcBgNVBAsTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEW
# MBQGA1UEBRMNMjMwMDEyKzUwMjkyMzAfBgNVHSMEGDAWgBRIbmTlUAXTgqoXNzci
# tW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3JsMGEG
# CCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDExXzIwMTEtMDctMDguY3J0
# MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIBAIjmD9IpQVvfB1QehvpC
# Ge7QeTQkKQ7j3bmDMjwSqFL4ri6ae9IFTdpywn5smmtSIyKYDn3/nHtaEn0X1NBj
# L5oP0BjAy1sqxD+uy35B+V8wv5GrxhMDJP8l2QjLtH/UglSTIhLqyt8bUAqVfyfp
# h4COMRvwwjTvChtCnUXXACuCXYHWalOoc0OU2oGN+mPJIJJxaNQc1sjBsMbGIWv3
# cmgSHkCEmrMv7yaidpePt6V+yPMik+eXw3IfZ5eNOiNgL1rZzgSJfTnvUqiaEQ0X
# dG1HbkDv9fv6CTq6m4Ty3IzLiwGSXYxRIXTxT4TYs5VxHy2uFjFXWVSL0J2ARTYL
# E4Oyl1wXDF1PX4bxg1yDMfKPHcE1Ijic5lx1KdK1SkaEJdto4hd++05J9Bf9TAmi
# u6EK6C9Oe5vRadroJCK26uCUI4zIjL/qG7mswW+qT0CW0gnR9JHkXCWNbo8ccMk1
# sJatmRoSAifbgzaYbUz8+lv+IXy5GFuAmLnNbGjacB3IMGpa+lbFgih57/fIhamq
# 5VhxgaEmn/UjWyr+cPiAFWuTVIpfsOjbEAww75wURNM1Imp9NJKye1O24EspEHmb
# DmqCUcq7NqkOKIG4PVm3hDDED/WQpzJDkvu4FrIbvyTGVU01vKsg4UfcdiZ0fQ+/
# V0hf8yrtq9CkB8iIuk5bBxuPMIIHejCCBWKgAwIBAgIKYQ6Q0gAAAAAAAzANBgkq
# hkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5
# IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEwOTA5WjB+MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYDVQQDEx9NaWNyb3NvZnQg
# Q29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIIC
# CgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+laUKq4BjgaBEm6f8MMHt03
# a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc6Whe0t+bU7IKLMOv2akr
# rnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4Ddato88tt8zpcoRb0Rrrg
# OGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+lD3v++MrWhAfTVYoonpy
# 4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nkkDstrjNYxbc+/jLTswM9
# sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6A4aN91/w0FK/jJSHvMAh
# dCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmdX4jiJV3TIUs+UsS1Vz8k
# A/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL5zmhD+kjSbwYuER8ReTB
# w3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zdsGbiwZeBe+3W7UvnSSmn
# Eyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3T8HhhUSJxAlMxdSlQy90
# lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS4NaIjAsCAwEAAaOCAe0w
# ggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRIbmTlUAXTgqoXNzcitW2o
# ynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYD
# VR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBDuRQFTuHqp8cx0SOJNDBa
# BgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2Ny
# bC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3JsMF4GCCsG
# AQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3dy5taWNyb3NvZnQuY29t
# L3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFfMDNfMjIuY3J0MIGfBgNV
# HSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEFBQcCARYzaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1hcnljcHMuaHRtMEAGCCsG
# AQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkAYwB5AF8AcwB0AGEAdABl
# AG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn8oalmOBUeRou09h0ZyKb
# C5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7v0epo/Np22O/IjWll11l
# hJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0bpdS1HXeUOeLpZMlEPXh6
# I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/KmtYSWMfCWluWpiW5IP0
# wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvyCInWH8MyGOLwxS3OW560
# STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBpmLJZiWhub6e3dMNABQam
# ASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJihsMdYzaXht/a8/jyFqGa
# J+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYbBL7fQccOKO7eZS/sl/ah
# XJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbSoqKfenoi+kiVH6v7RyOA
# 9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sLgOppO6/8MO0ETI7f33Vt
# Y5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtXcVZOSEXAQsmbdlsKgEhr
# /Xmfwb1tbWrJUnMTDXpQzTGCGeswghnnAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IDc9GKgc23kGIgReoO+G4+4gb1Wg2s8X9tfUGADopz2yMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAdChDvUmqVyxdczBPusfob0f6T8/edh6o
# 2keS1GfUlO7I4xZTw93iACaGkcsXStM2PBOjc8ufjQcmPyQl7brO0uKMEoSKvdvB
# AKnjDeQR+7s+1eGx2IUFA2ZWnLD6ablJ8u41ECdz49xvVq1bmHkDTV0BjmziRtYX
# quetjo9Cj1ma13jLGyktWyfjnV+oVubQN/JYlwPRty+syYmfSyQpcQqoOhQDjKOK
# TM8xwfAPbgfw3UgDNqAGcxm4va06FC5j7rfLP8gV5KFA7fldLjSmISTxQoBrWKna
# W/3bvfE2BnllENpgfFKOoDlgWPp8uQTtT1iQ9JeDeY/jmeqzCVqpuKGCF5MwgheP
# BgorBgEEAYI3AwMBMYIXfzCCF3sGCSqGSIb3DQEHAqCCF2wwghdoAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFRBgsqhkiG9w0BCRABBKCCAUAEggE8MIIBOAIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCcgHki+/dtZ5AXaWcwKA3A/Mi9A42D
# PgAbpjgxul5BwgIGZ/gQe5XeGBIyMDI1MDQxODAwMjAwNC42N1owBIACAfSggdGk
# gc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNV
# BAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo4OTAwLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZaCCEeowggcgMIIFCKADAgECAhMzAAACDizLKH2VIHVj
# AAEAAAIOMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMB4XDTI1MDEzMDE5NDMwM1oXDTI2MDQyMjE5NDMwM1owgcsxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBB
# bWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo4OTAw
# LTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2Vydmlj
# ZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAKzm3uJG1e3SFt6j0wTv
# xliMijexpC5YwEVDtfiz2+ihhEAFM5/amhMdq3H4TCcFQYHVXa38TozCxA2Zjlek
# z/vloKtl3ECetX2jhO7mwF6ltt96Gys5ZEEgagkTo+1ah3UKsV6GbV2LPeNjcfyI
# WuHuep5+eJnVKdtxY8zI0jG4YXOlCIMD4TlhLfeZ4yppfCF1vTUKW7KaH/cQq+Se
# Ph0ilBkRY48zePFtFUBg3kna06tiQlx0PHSXTZX81h3WqS9QGA/Gsq+KrmTPsToB
# s6J8INIwGByf9ftFDDrfRCTOqGnSQNTap6L9qj0gea65F5cSOeOmBOyvgBvfcgIA
# oxjE5B76fnCoRVwT05PKGZZklLkCdZROeKiTiaDA40FZDUMs4YWRnBdPffgg8Kp3
# j/f8t38i2LOKy3JRliyaX8LhmF0Atu99jDO/fU7F/w1OZXkgbFZ0eeTYeGHhufNM
# qiwRoOsm9AyJD6WiiMzt/luB3IEGdhAGbn7+ImzHDyTbbvMXaNs0j47Czwct5ka3
# y3q4nZ5WM0PUHRi2CwE/RywGWecj7j528thG3RwCrDo+JhLPkVJlxumLTF0Af+N3
# d3PIYCtvIu6jr0e6B8YQRv+wzTutyg/Wjdxnx5Yxvj4wgHx645vkNU8OcRwWLg0O
# 6Rgz3WDUO3+oh6T6u0TzxVLxAgMBAAGjggFJMIIBRTAdBgNVHQ4EFgQUhXFEaVIR
# kT7URIrpQYjtg1wQiNswHwYDVR0jBBgwFoAUn6cVXQBeYl2D9OXSZacbUzUZ6XIw
# XwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3Js
# MGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0cDovL3d3dy5taWNyb3Nv
# ZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIwUENB
# JTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEF
# BQcDCDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQELBQADggIBAHXgvZMv4vw5
# cvGcZJqXaHfSZnsWwEWiiJiRRU5jTkX2mfA9NW58QMZYSk03LY59pQdYg6hD/3+u
# PA7SFLZKkHQHMwCTaDLP3Y0ZY6lZukF0y+utEOmJZmL+4tLhkZ1Gfc/YNxxiaWQ0
# /69pEBe+e/6anbsqAjv2Yn2EbIJBu+0wiORtiguoruwXtZqGf2suNfXLlAkviW8T
# LdCYD0pEGPnpwS/+UC/MOrt5KKpGr+kLKrJzy7OZDxJ4pbJa7oONQD2+LzhCyYuO
# o8YKcfhw/KD633lGlb7veyeF7DWIJX7Be7ZHEydaDsSwPl4uQkcuzNQg935cKUP4
# VO9XTcZ+sMN+T7jl+Uf94pFlzcxRm2eEsmM/C/cqgoNJxbiJXpJsJHJxg+SqhYGs
# d/tK8MDsasfZQ63PVZrWTbux1mCkbr9z0KoojwJfm+Bpr4DuhgdvhkGPtLy7yyDH
# BYrseBYNEHI4fcKIm7gsnyHdOJGRECuYdGnSVs1/WIAq4vzzogoT3Xa/TKrnm3yM
# zGMFTu6guythUigqTOH6wCSCSkY6hkvXj52XFUz3UFq/NriQ4NNSXDNv5KlexKpX
# Hye4HqqFTLumqmDDDWrhI2EDEWcXGzGJOVqgvvkY3E9HrTmUnZZd6G0SLv/5h8mq
# 8f6+epymoKPJD2E1pXO44QdfgzK6pyPCMIIHcTCCBVmgAwIBAgITMwAAABXF52ue
# AptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgyMjI1WhcNMzAwOTMwMTgz
# MjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYD
# VQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMDCCAiIwDQYJKoZIhvcN
# AQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ckeb0O1YLT/e6cBwfSqWxO
# dcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+uDZnhUYjDLWNE893MsAQ
# GOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4bo3t1w/YJlN8OWECesSq
# /XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhiJdxqD89d9P6OU8/W7IVW
# Te/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD4MmPfrVUj9z6BVWYbWg7
# mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKNiOSWrAFKu75xqRdbZ2De
# +JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXftnIv231fgLrbqn427DZM
# 9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8P0zbr17C89XYcz1DTsEz
# OUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMYctenIPDC+hIK12NvDMk2
# ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9stQcxWv2XFJRXRLbJbqv
# UAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUeh17aj54WcmnGrnu3tz5q
# 4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQIDAQABMCMGCSsGAQQBgjcV
# AgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4EFgQUn6cVXQBeYl2D9OXS
# ZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcC
# ARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRv
# cnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1
# AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaA
# FNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0wS6BJoEeGRWh0dHA6Ly9j
# cmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3RzL01pY1Jvb0NlckF1dF8y
# MDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYIKwYBBQUHMAKGPmh0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWljUm9vQ2VyQXV0XzIwMTAt
# MDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38Kq3hLB9nATEkW+Geckv8
# qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTltuw8x5MKP+2zRoZQYIu7p
# Zmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99qb74py27YP0h1AdkY3m2C
# DPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQJL1AoL8ZthISEV09J+BA
# ljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1ijbCHcNhcy4sa3tuPywJ
# eBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP9pEB9s7GdP32THJvEKt1
# MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkkvnNtyo4JvbMBV0lUZNlz
# 138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFHqfG3rsjoiV5PndLQTHa1
# V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g75LcVv7TOPqUxUYS8vwLB
# gqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr4A245oyZ1uEi6vAnQj0l
# lOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghif9lwY1NNje6CbaUFEMFx
# BmoQtB1VM1izoXBm8qGCA00wggI1AgEBMIH5oYHRpIHOMIHLMQswCQYDVQQGEwJV
# UzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1l
# cmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0w
# NUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2Wi
# IwoBATAHBgUrDgMCGgMVAErodj9lYuc5wwRCyOQMCgH8llYIoIGDMIGApH4wfDEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZIhvcNAQELBQACBQDrq8jb
# MCIYDzIwMjUwNDE3MTgzNzE1WhgPMjAyNTA0MTgxODM3MTVaMHQwOgYKKwYBBAGE
# WQoEATEsMCowCgIFAOuryNsCAQAwBwIBAAICC3AwBwIBAAICErkwCgIFAOutGlsC
# AQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGEWQoDAqAKMAgCAQACAwehIKEK
# MAgCAQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEA2LSD/TcwSk94ygjSgBEgPv+J
# k3cdBhX5BeKoRP81IB+0YBl4UaUzWI2s3Ta6GLSBt6IJ86TJS+gJ2+UuFjFDpFQT
# dXw4fDKvYNU+LRLUWdqtYbXw7tALuv8BWAd2Zy45IKr4cWhNtzEalFv5MQBmrJJg
# gdRB4pP0JPVV0ecqz5DpLW7ehWQFuYdSZbM7M3CJ90b5zdC4SQnHwCfFFFOlOPnL
# HTbWFuQ9w0mIn/Vv/FddYM0Lu/xrFfSKPP8SFq+zOiSnZDJJ0i43DPhsZTdbDGqA
# LCUYgyYy+U8BLOS5z4xhJDY77YheFVWIt+v3DtmnBazlfXfm5bVPupyEF4Tg0zGC
# BA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwAhMzAAAC
# DizLKH2VIHVjAAEAAAIOMA0GCWCGSAFlAwQCAQUAoIIBSjAaBgkqhkiG9w0BCQMx
# DQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIEIM9n4xokxKdm8Ins9gk2Tbgd
# 26YsmBoGI3ye+h6lN+5dMIH6BgsqhkiG9w0BCRACLzGB6jCB5zCB5DCBvQQgAXQd
# cyXw6YGQrbrubGhspKKHA50/R5Q1dAzKk/NPEoYwgZgwgYCkfjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAg4syyh9lSB1YwABAAACDjAiBCDfDf+4
# H4vR2XyZbyyRYMARB1CeFUgiloNVY14p3LbfyDANBgkqhkiG9w0BAQsFAASCAgCV
# VvoAsdzMxT12TSzuAY+KiqXQn37nZkmdomtTgCXycHQNHrsVttIBYNOlBodwYBP2
# ZKdOC8HYYSKGHHWiaZ/F+PDy3tbdyS1wHZLIYnyUm3RBWGmEK43t76oD8Pcg6hfU
# H2gbr2cO7FV6hAIaawyNiu51+6RsWCGzEX2L7h0OXwBZyiewSM+kRQDG3i/sLYOq
# w+xzIRC56i7otWn38z9sTy+6dBdbLimSH+xmLQJO0x8+/m9nu9NT7UShMJAv40bM
# TSV6kMm/Mjh53bqhRlSveF2SR/mffEOEKyKMTnBtoXgR0UXSFkkSKqUYNkrkpe4Q
# D4A3p/Uv7/z1x0w8MMqpnArthtTBzU+5q/YDoHQR4X7H6GQ2sp0//jnVJ1c1N9S2
# rTx3UawBwawLlmwWdX8yxKkm1JI6o5SE5QxfZfWTfyS0/ZgPbi3I9e7srHz9t5md
# N0b/EgJI9sxgl0KOf7PKGMfgRsSjZf1eahk/OVtqkCIy2hgaDn/DlskihcpO2c5N
# ItpriHGSLzJWFK4saVG6x50YkFZqevu6pxSn8VSG2rR+GGyJg6D21QHWWVl8okIi
# /LufINrj0vBASM4ALJBnlMtEcyAD+Cfas8yHEswRfTJxPR4BM/6SpYB8ZYXPLeE9
# DY3CHxRAEX+kzJTSuQXjQDXmCK8Y2ODjREMDJsTFpw==
# SIG # End signature block
