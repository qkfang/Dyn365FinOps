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
        [string]$platformPathInput,
        [string]$referencePaths
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

            $symLinkCreatedPath = $platformPathInput
            if ($referencePaths.Trim() -ne "")
            {
                $symLinkCreatedPath = CreateSymLinksForRefPaths -platformPath $platformPathInput -referencePaths $referencePaths
            }
            Write-Host "Reference paths directory $symLinkCreatedPath"

            if("" -ne $symLinkCreatedPath)
            {
                $dllFiles = @("<SysTest><Partition>initial</Partition><RuntimePackagesDirectory>$symLinkCreatedPath</RuntimePackagesDirectory><FrameworkBinDirectory>$compilerPathInput</FrameworkBinDirectory></SysTest>")
                foreach ($directory in $packages)
                {
                    $dllFiles += Get-ChildItem -Path $directory -Filter *.dll -File -Recurse | Select-Object -ExpandProperty FullName
                }

                #calling to get tsx from the dlls
                $tsxresult = TestRequestTSXFetch -dllList $dllFiles -compilerPathValue $compilerPathInput
                if ($tsxresult -eq "")
                {
                    throw
                }
                else
                {
                    return $tsxresult
                }
            }
            else
            {
                Write-Host "Unable to load reference paths, test execution failed."
                throw
            }
        }
    }
    finally
    {
        if (($null -ne $symLinkCreatedPath) -and ($symLinkCreatedPath -ne $platformPathInput))
        {
            try 
            {
                if (Test-Path $symLinkCreatedPath) 
                {
                    # Delete the folder and its contents
                    Remove-Item -Path $symLinkCreatedPath -Recurse -Force
                    Write-Host "The folder has been deleted successfully. Proceeding."
                } 
                else
                {
                    Write-Host "The reference folder does not exist. Proceeding."
                }
            }
            catch 
            {
                Write-Host "Failed to delete reference folder. Proceeding."
            }
        }
    }
}

function CreateSymLinksForRefPaths {
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [string] $platformPath,
        [string] $referencePaths
    )
    # Ensure the platformPath is a valid directory
    if (-not (Test-Path -Path $platformPath -PathType Container)) {
        Write-Host "Invalid platform path: $platformPath"
        return ""
    }

    $uuid = [Guid]::NewGuid().ToString()
    $tempPath = [System.IO.Path]::GetTempPath()
    $uniqueTempPath = Join-Path -Path $tempPath -ChildPath $uuid
    New-Item -ItemType Directory -Path $uniqueTempPath | Out-Null
    Write-Host "Temporary reference path location is: $uniqueTempPath"

    $topLevelPlatformSubDirs = Get-ChildItem -Path $platformPath -Directory
    foreach($subPathPlat in $topLevelPlatformSubDirs) {
        # Create the symbolic link
        $linkName = [System.IO.Path]::GetFileName($subPathPlat)
        $linkPath = Join-Path -Path $uniqueTempPath -ChildPath $linkName
        New-Item -ItemType SymbolicLink -Path $linkPath -Target $subPathPlat.FullName -Force | Out-Null
    }

    # Split the reference paths into an array
    $pathsArray = $referencePaths -split ';'

    # Loop through each path in the array
    foreach ($topLevelPath in $pathsArray) {
        $topLevelPath = $topLevelPath.Trim()
        if($topLevelPath -eq "") {
            Write-Host "Skipping empty entry"
            continue;
        }
        if (-not (Test-Path -Path $topLevelPath -PathType Container)) {
            Write-Host "Invalid folder path: $topLevelPath"
            return ""
        }

        $topLevelSubDirs = Get-ChildItem -Path $topLevelPath -Directory

        foreach($subPath in $topLevelSubDirs) {
            # Create the symbolic link
            $linkName = [System.IO.Path]::GetFileName($subPath)
            # create the symbolic link
            $linkPath = Join-Path -Path $uniqueTempPath -ChildPath $linkName
            New-Item -ItemType SymbolicLink -Path $linkPath -Target $subPath.FullName -Force | Out-Null
        }
    }
    Start-Sleep -Seconds 1
    return $uniqueTempPath
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
                    if (discoverySink.testCases.Count == 0)
                    {
                        Console.WriteLine("Unable to discover any test cases. Please ensure the model is built along with any required dependencies.");
                        return string.Empty;
                    }

                    var executor = new SysTestExecutor();
                    var caseList = discoverySink.testCases.GroupBy(testCase => testCase.Source);
                    System.Threading.Thread.Sleep(1000);
                    Console.WriteLine("Got case list");

                    var testSuites = new List<TestSuite>();
                    foreach (var entry in caseList)
                    {
                        Console.WriteLine(entry.Key);
                        testSuites.AddRange(executor.CreateTestSuites(entry.Key, entry.OrderBy(tc => tc.DisplayName)));
                    }
                    Console.WriteLine("TestSuites list created");
                    var tempFolderName = DateTime.UtcNow.ToFileTimeUtc().ToString();
                    var suiteDirectory = Path.Combine(Path.GetTempPath(), executor.FinOpsTestRequestPackaging, tempFolderName);
                    var suiteListFile = Path.Combine(suiteDirectory, "testSuiteList.txt");
                    var insideTestSuite = Path.Combine(suiteDirectory, "TestSuites");
                    Console.WriteLine("Saving test suites");
                    SysTestExecutor.SaveTestSuites(insideTestSuite, suiteListFile, testSuites);
                    Console.WriteLine("Saved test suites");
                    return insideTestSuite;
                }
                catch (Exception ex)
                {
                    Console.WriteLine("Error discovering tests: " + ex.Message);
                    Console.WriteLine(ex.StackTrace.ToString());
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
# MIIoGwYJKoZIhvcNAQcCoIIoDDCCKAgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCyZdCPaANKca14
# IWoC6500HoKCTtJ6rOjBHtZDiTLFt6CCDYUwggYDMIID66ADAgECAhMzAAAEA73V
# lV0POxitAAAAAAQDMA0GCSqGSIb3DQEBCwUAMH4xCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNpZ25p
# bmcgUENBIDIwMTEwHhcNMjQwOTEyMjAxMTEzWhcNMjUwOTExMjAxMTEzWjB0MQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMR4wHAYDVQQDExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIB
# AQCfdGddwIOnbRYUyg03O3iz19XXZPmuhEmW/5uyEN+8mgxl+HJGeLGBR8YButGV
# LVK38RxcVcPYyFGQXcKcxgih4w4y4zJi3GvawLYHlsNExQwz+v0jgY/aejBS2EJY
# oUhLVE+UzRihV8ooxoftsmKLb2xb7BoFS6UAo3Zz4afnOdqI7FGoi7g4vx/0MIdi
# kwTn5N56TdIv3mwfkZCFmrsKpN0zR8HD8WYsvH3xKkG7u/xdqmhPPqMmnI2jOFw/
# /n2aL8W7i1Pasja8PnRXH/QaVH0M1nanL+LI9TsMb/enWfXOW65Gne5cqMN9Uofv
# ENtdwwEmJ3bZrcI9u4LZAkujAgMBAAGjggGCMIIBfjAfBgNVHSUEGDAWBgorBgEE
# AYI3TAgBBggrBgEFBQcDAzAdBgNVHQ4EFgQU6m4qAkpz4641iK2irF8eWsSBcBkw
# VAYDVR0RBE0wS6RJMEcxLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJh
# dGlvbnMgTGltaXRlZDEWMBQGA1UEBRMNMjMwMDEyKzUwMjkyNjAfBgNVHSMEGDAW
# gBRIbmTlUAXTgqoXNzcitW2oynUClTBUBgNVHR8ETTBLMEmgR6BFhkNodHRwOi8v
# d3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNDb2RTaWdQQ0EyMDExXzIw
# MTEtMDctMDguY3JsMGEGCCsGAQUFBwEBBFUwUzBRBggrBgEFBQcwAoZFaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNDb2RTaWdQQ0EyMDEx
# XzIwMTEtMDctMDguY3J0MAwGA1UdEwEB/wQCMAAwDQYJKoZIhvcNAQELBQADggIB
# AFFo/6E4LX51IqFuoKvUsi80QytGI5ASQ9zsPpBa0z78hutiJd6w154JkcIx/f7r
# EBK4NhD4DIFNfRiVdI7EacEs7OAS6QHF7Nt+eFRNOTtgHb9PExRy4EI/jnMwzQJV
# NokTxu2WgHr/fBsWs6G9AcIgvHjWNN3qRSrhsgEdqHc0bRDUf8UILAdEZOMBvKLC
# rmf+kJPEvPldgK7hFO/L9kmcVe67BnKejDKO73Sa56AJOhM7CkeATrJFxO9GLXos
# oKvrwBvynxAg18W+pagTAkJefzneuWSmniTurPCUE2JnvW7DalvONDOtG01sIVAB
# +ahO2wcUPa2Zm9AiDVBWTMz9XUoKMcvngi2oqbsDLhbK+pYrRUgRpNt0y1sxZsXO
# raGRF8lM2cWvtEkV5UL+TQM1ppv5unDHkW8JS+QnfPbB8dZVRyRmMQ4aY/tx5x5+
# sX6semJ//FbiclSMxSI+zINu1jYerdUwuCi+P6p7SmQmClhDM+6Q+btE2FtpsU0W
# +r6RdYFf/P+nK6j2otl9Nvr3tWLu+WXmz8MGM+18ynJ+lYbSmFWcAj7SYziAfT0s
# IwlQRFkyC71tsIZUhBHtxPliGUu362lIO0Lpe0DOrg8lspnEWOkHnCT5JEnWCbzu
# iVt8RX1IV07uIveNZuOBWLVCzWJjEGa+HhaEtavjy6i7MIIHejCCBWKgAwIBAgIK
# YQ6Q0gAAAAAAAzANBgkqhkiG9w0BAQsFADCBiDELMAkGA1UEBhMCVVMxEzARBgNV
# BAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9zb2Z0IFJvb3QgQ2VydGlm
# aWNhdGUgQXV0aG9yaXR5IDIwMTEwHhcNMTEwNzA4MjA1OTA5WhcNMjYwNzA4MjEw
# OTA5WjB+MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSgwJgYD
# VQQDEx9NaWNyb3NvZnQgQ29kZSBTaWduaW5nIFBDQSAyMDExMIICIjANBgkqhkiG
# 9w0BAQEFAAOCAg8AMIICCgKCAgEAq/D6chAcLq3YbqqCEE00uvK2WCGfQhsqa+la
# UKq4BjgaBEm6f8MMHt03a8YS2AvwOMKZBrDIOdUBFDFC04kNeWSHfpRgJGyvnkmc
# 6Whe0t+bU7IKLMOv2akrrnoJr9eWWcpgGgXpZnboMlImEi/nqwhQz7NEt13YxC4D
# dato88tt8zpcoRb0RrrgOGSsbmQ1eKagYw8t00CT+OPeBw3VXHmlSSnnDb6gE3e+
# lD3v++MrWhAfTVYoonpy4BI6t0le2O3tQ5GD2Xuye4Yb2T6xjF3oiU+EGvKhL1nk
# kDstrjNYxbc+/jLTswM9sbKvkjh+0p2ALPVOVpEhNSXDOW5kf1O6nA+tGSOEy/S6
# A4aN91/w0FK/jJSHvMAhdCVfGCi2zCcoOCWYOUo2z3yxkq4cI6epZuxhH2rhKEmd
# X4jiJV3TIUs+UsS1Vz8kA/DRelsv1SPjcF0PUUZ3s/gA4bysAoJf28AVs70b1FVL
# 5zmhD+kjSbwYuER8ReTBw3J64HLnJN+/RpnF78IcV9uDjexNSTCnq47f7Fufr/zd
# sGbiwZeBe+3W7UvnSSmnEyimp31ngOaKYnhfsi+E11ecXL93KCjx7W3DKI8sj0A3
# T8HhhUSJxAlMxdSlQy90lfdu+HggWCwTXWCVmj5PM4TasIgX3p5O9JawvEagbJjS
# 4NaIjAsCAwEAAaOCAe0wggHpMBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRI
# bmTlUAXTgqoXNzcitW2oynUClTAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAL
# BgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAWgBRyLToCMZBD
# uRQFTuHqp8cx0SOJNDBaBgNVHR8EUzBRME+gTaBLhklodHRwOi8vY3JsLm1pY3Jv
# c29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3JsMF4GCCsGAQUFBwEBBFIwUDBOBggrBgEFBQcwAoZCaHR0cDovL3d3
# dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXQyMDExXzIwMTFf
# MDNfMjIuY3J0MIGfBgNVHSAEgZcwgZQwgZEGCSsGAQQBgjcuAzCBgzA/BggrBgEF
# BQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9kb2NzL3ByaW1h
# cnljcHMuaHRtMEAGCCsGAQUFBwICMDQeMiAdAEwAZQBnAGEAbABfAHAAbwBsAGkA
# YwB5AF8AcwB0AGEAdABlAG0AZQBuAHQALiAdMA0GCSqGSIb3DQEBCwUAA4ICAQBn
# 8oalmOBUeRou09h0ZyKbC5YR4WOSmUKWfdJ5DJDBZV8uLD74w3LRbYP+vj/oCso7
# v0epo/Np22O/IjWll11lhJB9i0ZQVdgMknzSGksc8zxCi1LQsP1r4z4HLimb5j0b
# pdS1HXeUOeLpZMlEPXh6I/MTfaaQdION9MsmAkYqwooQu6SpBQyb7Wj6aC6VoCo/
# KmtYSWMfCWluWpiW5IP0wI/zRive/DvQvTXvbiWu5a8n7dDd8w6vmSiXmE0OPQvy
# CInWH8MyGOLwxS3OW560STkKxgrCxq2u5bLZ2xWIUUVYODJxJxp/sfQn+N4sOiBp
# mLJZiWhub6e3dMNABQamASooPoI/E01mC8CzTfXhj38cbxV9Rad25UAqZaPDXVJi
# hsMdYzaXht/a8/jyFqGaJ+HNpZfQ7l1jQeNbB5yHPgZ3BtEGsXUfFL5hYbXw3MYb
# BL7fQccOKO7eZS/sl/ahXJbYANahRr1Z85elCUtIEJmAH9AAKcWxm6U/RXceNcbS
# oqKfenoi+kiVH6v7RyOA9Z74v2u3S5fi63V4GuzqN5l5GEv/1rMjaHXmr/r8i+sL
# gOppO6/8MO0ETI7f33VtY5E90Z1WTk+/gFcioXgRMiF670EKsT/7qMykXcGhiJtX
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGewwghnoAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAQDvdWVXQ87GK0AAAAA
# BAMwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# LwYJKoZIhvcNAQkEMSIEIKPP+gqyHl14Zw3DDeh1m35l3+IfRq8znEUMBYF1UoXO
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAJ6O/ZwbVsk5Y
# 3EXJKtKdfEhvDlzoFG535O3ng1/XqfGHt2XRafQ3LNhHGKzRY9+qAWoClWcdEdSc
# jDDydUUPuIkknnYHBFMzFy5NfIOdIZkWdGXPHxupRrowhdrYJC0zosaaXaQll7lH
# NMXHkiE8uozl3WK/mt82scXJy7QZQVgnNVIO1mPi9QaHVyuZFURxx10RrevwG09k
# Y5HIgWVj4lgxC+hp9NQuN/NhKikUl4ucVEJfO2bXT3tMuHgKe7cAQlC+mmh2DbE6
# h+F2c/yFcB5wT47Kk/ASj/Qj0X2qQvH0UpD2Mor16UyQK1P1RWUc00qnzMziLs3a
# 3YwyoEzKZKGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCC
# F20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEE
# ggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBlb2ofod8M
# iNsreZWMOpmFcahbZqKFOXAnReMxGXEcwwIGZ/gQe5P0GBMyMDI1MDQxODAwMTk0
# NC45MzVaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIB
# AgITMwAAAg4syyh9lSB1YwABAAACDjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQzMDNaFw0yNjA0MjIxOTQz
# MDNaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCs5t7iRtXt0hbeo9ME78ZYjIo3saQuWMBFQ7X4s9vooYRABTOf2poTHatx+Ewn
# BUGB1V2t/E6MwsQNmY5XpM/75aCrZdxAnrV9o4Tu5sBepbbfehsrOWRBIGoJE6Pt
# Wod1CrFehm1diz3jY3H8iFrh7nqefniZ1SnbcWPMyNIxuGFzpQiDA+E5YS33meMq
# aXwhdb01Cluymh/3EKvknj4dIpQZEWOPM3jxbRVAYN5J2tOrYkJcdDx0l02V/NYd
# 1qkvUBgPxrKviq5kz7E6AbOifCDSMBgcn/X7RQw630Qkzqhp0kDU2qei/ao9IHmu
# uReXEjnjpgTsr4Ab33ICAKMYxOQe+n5wqEVcE9OTyhmWZJS5AnWUTniok4mgwONB
# WQ1DLOGFkZwXT334IPCqd4/3/Ld/ItizistyUZYsml/C4ZhdALbvfYwzv31Oxf8N
# TmV5IGxWdHnk2Hhh4bnzTKosEaDrJvQMiQ+loojM7f5bgdyBBnYQBm5+/iJsxw8k
# 227zF2jbNI+Ows8HLeZGt8t6uJ2eVjND1B0YtgsBP0csBlnnI+4+dvLYRt0cAqw6
# PiYSz5FSZcbpi0xdAH/jd3dzyGArbyLuo69HugfGEEb/sM07rcoP1o3cZ8eWMb4+
# MIB8euOb5DVPDnEcFi4NDukYM91g1Dt/qIek+rtE88VS8QIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFIVxRGlSEZE+1ESK6UGI7YNcEIjbMB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQB14L2TL+L8OXLxnGSal2h30mZ7FsBFooiYkUVOY05F9pnwPTVufEDG
# WEpNNy2OfaUHWIOoQ/9/rjwO0hS2SpB0BzMAk2gyz92NGWOpWbpBdMvrrRDpiWZi
# /uLS4ZGdRn3P2DccYmlkNP+vaRAXvnv+mp27KgI79mJ9hGyCQbvtMIjkbYoLqK7s
# F7Wahn9rLjX1y5QJL4lvEy3QmA9KRBj56cEv/lAvzDq7eSiqRq/pCyqyc8uzmQ8S
# eKWyWu6DjUA9vi84QsmLjqPGCnH4cPyg+t95RpW+73snhew1iCV+wXu2RxMnWg7E
# sD5eLkJHLszUIPd+XClD+FTvV03GfrDDfk+45flH/eKRZc3MUZtnhLJjPwv3KoKD
# ScW4iV6SbCRycYPkqoWBrHf7SvDA7GrH2UOtz1Wa1k27sdZgpG6/c9CqKI8CX5vg
# aa+A7oYHb4ZBj7S8u8sgxwWK7HgWDRByOH3CiJu4LJ8h3TiRkRArmHRp0lbNf1iA
# KuL886IKE912v0yq55t8jMxjBU7uoLsrYVIoKkzh+sAkgkpGOoZL14+dlxVM91Ba
# vza4kODTUlwzb+SpXsSqVx8nuB6qhUy7pqpgww1q4SNhAxFnFxsxiTlaoL75GNxP
# R605lJ2WXehtEi7/+YfJqvH+vnqcpqCjyQ9hNaVzuOEHX4MyuqcjwjCCB3EwggVZ
# oAMCAQICEzMAAAAVxedrngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJ
# BgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25k
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jv
# c29mdCBSb290IENlcnRpZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4
# MjIyNVoXDTMwMDkzMDE4MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldh
# c2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBD
# b3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIw
# MTAwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvX
# JHm9DtWC0/3unAcH0qlsTnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa
# /rg2Z4VGIwy1jRPPdzLAEBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AK
# OG6N7dcP2CZTfDlhAnrEqv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rbo
# YiXcag/PXfT+jlPP1uyFVk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIck
# w+DJj361VI/c+gVVmG1oO5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbni
# jYjklqwBSru+cakXW2dg3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F
# 37ZyL9t9X4C626p+Nuw2TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZ
# fD9M269ewvPV2HM9Q07BMzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIz
# GHLXpyDwwvoSCtdjbwzJNmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR
# /bLUHMVr9lxSUV0S2yW6r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1
# Hode2o+eFnJpxq57t7c+auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUC
# AwEAATAjBgkrBgEEAYI3FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0O
# BBYEFJ+nFV0AXmJdg/Tl0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yD
# fQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkr
# BgEEAYI3FAIEDB4KAFMAdQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUw
# AwEB/zAfBgNVHSMEGDAWgBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBN
# MEugSaBHhkVodHRwOi8vY3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0
# cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoG
# CCsGAQUFBzAChj5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01p
# Y1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9
# /Cqt4SwfZwExJFvhnnJL/Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5
# bbsPMeTCj/ts0aGUGCLu6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvf
# am++Kctu2D9IdQHZGN5tggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn
# 0CS9QKC/GbYSEhFdPSfgQJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlS
# dYo2wh3DYXMuLGt7bj8sCXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0
# j/aRAfbOxnT99kxybxCrdTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5
# JL5zbcqOCb2zAVdJVGTZc9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakUR
# R6nxt67I6IleT53S0Ex2tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4
# O+S3Fb+0zj6lMVGEvL8CwYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVn
# K+ANuOaMmdbhIurwJ0I9JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoI
# Yn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSB
# zjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UE
# CxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjg5MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQBK6HY/ZWLnOcMEQsjkDAoB
# /JZWCKCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBCwUAAgUA66vI2zAiGA8yMDI1MDQxNzE4MzcxNVoYDzIwMjUwNDE4MTgz
# NzE1WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDrq8jbAgEAMAcCAQACAgtwMAcC
# AQACAhK5MAoCBQDrrRpbAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBANi0
# g/03MEpPeMoI0oARID7/iZN3HQYV+QXiqET/NSAftGAZeFGlM1iNrN02uhi0gbei
# CfOkyUvoCdvlLhYxQ6RUE3V8OHwyr2DVPi0S1FnarWG18O7QC7r/AVgHdmcuOSCq
# +HFoTbcxGpRb+TEAZqySYIHUQeKT9CT1VdHnKs+Q6S1u3oVkBbmHUmWzOzNwifdG
# +c3QuEkJx8AnxRRTpTj5yx021hbkPcNJiJ/1b/xXXWDNC7v8axX0ijz/Ehavszok
# p2QySdIuNwz4bGU3WwxqgCwlGIMmMvlPASzkuc+MYSQ2O+2IXhVViLfr9w7ZpwWs
# 5X135uW1T7qchBeE4NMxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMAITMwAAAg4syyh9lSB1YwABAAACDjANBglghkgBZQMEAgEFAKCC
# AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAM
# Z9mUcDUhJh7sYU2PkrdNoOJxp6diIe6t7hOFKNSEZTCB+gYLKoZIhvcNAQkQAi8x
# geowgecwgeQwgb0EIAF0HXMl8OmBkK267mxobKSihwOdP0eUNXQMypPzTxKGMIGY
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIOLMsofZUg
# dWMAAQAAAg4wIgQg3w3/uB+L0dl8mW8skWDAEQdQnhVIIpaDVWNeKdy238gwDQYJ
# KoZIhvcNAQELBQAEggIAJfbiQq9InRaDV6Fzp6B8fLav6urNG71UVUcDoxkgeOLT
# zExnmnaGLoZo/svStYCxAZ/RT5dtHg9PTJwJB7uZcg5AmVOFMisyK3t9Oa9/Zk5f
# m4caMenV7pD8WTmCOyRWmS/j1cunia0CQyzDv3UR8TqEbE0FMkzkhHX/zlL+9vZU
# bjKrrqzktoWg8UDcfr6jl5pz23KDMiHck9N59YaYTANX4ibSxQFH9Xj1VfM/Gbbc
# Eaw6zNoXZLoG5w+SVUfy4+IWUJZZtGH8QppqaWzCeFSWxPMcWkABzSxP2kHxJxeR
# mCstAvSqIyxqnF7abpyk4rhgzX5SoxbU9wze9OPUj9Jc/taldZYKLMkBj/qsmSpT
# RIGpcWakS4obfT4henRGbjKJMwjXA7PlHPAoIlfBzzB7Z8Hf/ludVoJguvWlVv6U
# MemrrMTMKP57GopLmJc8XzSfKMozhikPscbffyop+o4lNMF2ftlqJD0uGa5JyNZ6
# 3v8Oshq+vPPx+B/XuUK+p4OGSD+ojiZKw4V3l+5xlEWlJH3YQNu4j9NpdOriqb9/
# icuY2jdNBNlhOAsLNFTLJxqpywfZe3HbnqAT4Qa4dicV7eJPl9xIua1OVLZrL1uU
# 4/zW3Oh+AQNMRwQ2gogBrNfQjlIBuG3VsquEZYxfsnGFVqflUyQVHvkLle+ikd8=
# SIG # End signature block
