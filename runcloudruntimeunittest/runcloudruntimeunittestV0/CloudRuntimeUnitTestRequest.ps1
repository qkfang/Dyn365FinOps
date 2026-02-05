<#
.SYNOPSIS
    This file helps create and execute tests for UDE.
    
    Copyright © 2024 Microsoft. All rights reserved.
#>

function Create-CloudRuntimeUnitTestRequest {
    [Cmdletbinding()]
	param(
		[Parameter(Mandatory)]
		[string]$platVersionNumber,
        [Parameter(Mandatory)]
		[string]$appVersionNumber,
        [Parameter(Mandatory)]
		[string]$connectionString,
        [Parameter(Mandatory)]
		[string]$testSuiteDirectory
	)

    try{
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.PowerPlatform.VSShared.Util.dll"                                                   #"PowerPlatSharedLibrary.1.0.0\lib\net472\PowerPlatSharedLibrary.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Xrm.Tooling.Connector.dll"                                          #"Microsoft.CrmSdk.XrmTooling.CoreAssembly.9.1.1.27\lib\net462\Microsoft.Xrm.Tooling.Connector.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Dynamics.VSExtension.Shared.dll"
    }
    catch
    {
        $_.Exception.LoaderExceptions
    }
    
    $assemblies = ("System", "$PSScriptRoot\CloudRuntimeDlls\Microsoft.PowerPlatform.VSShared.Util.dll", "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Dynamics.VSExtension.Shared.dll")
        
    $id = get-random
    $code = 
@"
    using System;
    using System.Collections.Generic;
    using System.Threading.Tasks;
    using Microsoft.Dynamics.VSExtension.Shared;
    using Microsoft.PowerPlatform.VSShared.Util;
    namespace TestExecution
    {
        public class Program$id
        {
            public static async Task<string[]> MainCreate(string[] args)
            {
                var fnoTestDefinition = new FnoTestRequestDefinition
                {
                    Versions = new Versions
                    {
                        Platform = args[0],
                        Application = args[1],
                        Compiler = args[0],
                        PackageVersion = args[1],
                    },
                    CorrelationID = Guid.NewGuid(),
                    ClientID = Environment.MachineName,
                    TimestampUtc = DateTime.UtcNow.ToString(),
                    BuildType = "Full",
                    PackageType = "Dev",
                    OrganizationID = Guid.Empty,
                    DBSync = new DBSync() { Arguments = null, SyncKind = "None" },
                    Module = new Module()
                    {
                        Name = "test",
                        properties = new List<Tuple<string, string>>
                        {
                            new Tuple<string, string>("property1", "value1"),
                            new Tuple<string, string>("property2", "value2")
                        }
                    },
                    AdditionalData = new AdditionalData()
                };
                return await RunTest(args[2], fnoTestDefinition, args[3]);
            }

            static async Task<string[]> RunTest(string conn, FnoTestRequestDefinition reqObj, string tsxPath, string trxPath = "")
            {
                var createPkg = new PipelineOperation();
                return await createPkg.PerformSubmitFinOpsTestPackageOperation(conn, reqObj, tsxPath, trxPath);
            }
        }
    }
"@

    Write-Host "Starting submit of test request:"
    Add-Type -ReferencedAssemblies $assemblies -TypeDefinition $code -Language CSharp
    [System.AppContext]::SetSwitch('Switch.System.IO.Compression.ZipFile.UseBackslash', $false)
    Invoke-Expression "[TestExecution.Program$id]::MainCreate(@('$platVersionNumber', '$appVersionNumber', '$connectionString', '$testSuiteDirectory'))" | Tee-Object -Var packageLocation
    Write-Host "Received the results"
    if ($packageLocation.Result.Length -ne 0)
    {
        if ($packageLocation.Result.Length -eq 1)
        {
            throw $packageLocation.Result
        }
        foreach ($item in $packageLocation.Result) {
            Write-Host $item
        }
            
        if ($packageLocation.Result[0] -eq "False")
        {
            throw $packageLocation.Result
        }
        
        $allBlank = $packageLocation.Result[1..$packageLocation.Result.Length] | Where-Object { $_.Trim() -ne '' }
        # throw if none of the elements from index 1 onward are non-blank
        if ($allBlank.Count -eq 0)
        {
            throw "Results not recorded, please look at the test logs on the environment"
        }
    }
    Write-Host "Ending test request"
}
# SIG # Begin signature block
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAEzaQl1b9wcxUy
# Fy5+FH3mq0j0mpcFtqXxWfZHvmiXZqCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGggwghoEAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IJtgxEfAevN18xN12TmYCy9OKykmH0v1VXTgkYVTKkGPMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAUPkcUuiYGsk4Kwbp8fsaS72h2lhos2I0
# e1bQVbyD6DKc+CTUvD9U3XIm5RkOqHQKw92RROCHjYEFf32jEIwpLuIzrgEkEHIt
# vNFUZ5vNnFueijJryHQwR9t0QMe4UWYrG7OX5ZHd3RTuw8SQmVFRShkp1FHo6VtJ
# I3LPYbaB/na97+bFjwrajKNibkgvdreew5XccDVPQLzlyo9JaS2ObJvSp1KgX5YA
# fSOf0TxqKSri60zkcwIFh8oiRNFKRpMkojKpYf7Q0eq3jnGB0+bmN2A4qpT/RehX
# 5a0hv8o44H+2LRWz1uaSfkEChuq0mxF0aEGgrQ37TfLK1KrwF1RVGqGCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCByGvBABvg9dS3F0Ea1yguOTazh57Qh
# oWDsW4rgHsUy6wIGZ+0kvadXGBMyMDI1MDQxODAwMjAwNi45NTJaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB
# +KOhJgwMQEj+AAEAAAH4MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzEwOFoXDTI1MTAyMjE4MzEwOFowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjMyMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAxR23pXYnD2BuODdeXs2Cu/T5kKI+bAw8cbtN50Cm/FArjXyL4RTqMe6laQ/C
# qeMTxgckvZr1JrW0Mi4F15rx/VveGhKBmob45DmOcV5xyx7h9Tk59NAl5PNMAWKA
# IWf270SWAAWxQbpVIhhPWCnVV3otVvahEad8pMmoSXrT5Z7Nk1RnB70A2bq9Hk8w
# IeC3vBuxEX2E8X50IgAHsyaR9roFq3ErzUEHlS8YnSq33ui5uBcrFOcFOCZILuVF
# VTgEqSrX4UiX0etqi7jUtKypgIflaZcV5cI5XI/eCxY8wDNmBprhYMNlYxdmQ9aL
# RDcTKWtddWpnJtyl5e3gHuYoj8xuDQ0XZNy7ESRwJIK03+rTZqfaYyM4XSK1s0aa
# +mO69vo/NmJ4R/f1+KucBPJ4yUdbqJWM3xMvBwLYycvigI/WK4kgPog0UBNczaQw
# DVXpcU+TMcOvWP8HBWmWJQImTZInAFivXqUaBbo3wAfPNbsQpvNNGu/12pg0F8O/
# CdRfgPHfOhIWQ0D8ALCY+LsiwbzcejbrVl4N9fn2wOg2sDa8RfNoD614I0pFjy/l
# q1NsBo9V4GZBikzX7ZjWCRgd1FCBXGpfpDikHjQ05YOkAakdWDT2bGSaUZJGVYte
# pIpPTAs1gd/vUogcdiL51o7shuHIlB6QSUiQ24XYhRbbQCECAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBS9zsZzz57QlT5nrt/oitLv1OQ7tjAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEAYfk8GzzpEVnGl7y6oXoytCb42Hx6TOA0+dkaBI36ftDE9tLubUa/
# xMbHB5rcNiRhFHZ93RefdPpc4+FF0DAl5lP8xKAO+293RWPKDFOFIxgtZY08t8D9
# cSQpgGUzyw3lETZebNLEA17A/CTpA2F9uh8j84KygeEbj+bidWDiEfayoH2A5/5y
# wJJxIuLzFVHacvWxSCKoF9hlSrZSG5fXWS3namf4tt690UT6AGyWLFWe895coFPx
# m/m0UIMjjp9VRFH7nb3Ng2Q4gPS9E5ZTMZ6nAlmUicDj0NXAs2wQuQrnYnbRAJ/D
# QW35qLo7Daw9AsItqjFhbMcG68gDc4j74L2KYe/2goBHLwzSn5UDftS1HZI0ZRsq
# mNHI0TZvvUWX9ajm6SfLBTEtoTo6gLOX0UD/9rrhGjdkiCw4SwU5osClgqgiNMK5
# ndk2gxFlDXHCyLp5qB6BoPpc82RhO0yCzoP9gv7zv2EocAWEsqE5+0Wmu5uarmfv
# cziLfU1SY240OZW8ld4sS8fnybn/jDMmFAhazV1zH0QERWEsfLSpwkOXaImWNFJ5
# lmcnf1VTm6cmfasScYtElpjqZ9GooCmk1XFApORPs/PO43IcFmPRwagt00iQSw+r
# BeIH00KQq+FJT/62SB70g9g/R8TS6k6b/wt2UWhqrW+Q8lw6Xzgex/YwggdxMIIF
# WaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqGSIb3DQEBCwUAMIGIMQsw
# CQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9u
# ZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNy
# b3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAxMDAeFw0yMTA5MzAx
# ODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA5OGmTOe0ciELeaLL
# 1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4XYDP/XE/HZveVU3Fa4n5K
# Wv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTzxXb1hlDcwUTIcVxRMTeg
# Cjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7uhp7M62AW36MEBydUv62
# 6GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlwaQ3KNi1wjjHINSi947SH
# JMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedGbsoy1cCGMFxPLOJiss25
# 4o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXNxF803RKJ1v2lIH1+/Nme
# Rd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03dJQcNIIP8BDyt0cY7afo
# mXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9ahhaYQFzymeiXtcodgLi
# Mxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5UPkLiWHzNgY1GIRH29wb
# 0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReTwDwV2xo3xwgVGD94q0W2
# 9R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZMBIGCSsGAQQBgjcVAQQF
# AgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8RjUpzxD/LwTuMB0GA1Ud
# DgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAEVTBTMFEGDCsGAQQBgjdM
# g30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# b3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAwwCgYIKwYBBQUHAwgwGQYJ
# KwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQDAgGGMA8GA1UdEwEB/wQF
# MAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb186aGMQwVgYDVR0fBE8w
# TTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29tL3BraS9jcmwvcHJvZHVj
# dHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoGCCsGAQUFBwEBBE4wTDBK
# BggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraS9jZXJ0cy9N
# aWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZIhvcNAQELBQADggIBAJ1V
# ffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9MTO1OdfCcTY/2mRsfNB1
# OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2LpypglYAA7AFvonoaeC6Ce57
# 32pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OOPcbzaN9l9qRWqveVtihV
# J9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8DJ6LGYnn8AtqgcKBGUIZ
# UnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA0j3mSj5mO0+7hvoyGtmW
# 9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1RtnWN0SCyxTkctwRQEcb9k
# +SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjcZxkoJLo4S5pu+yFUa2pF
# EUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq77EFmPWn9y8FBSX5+k77L
# +DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJC4822rpM+Zv/Cuk0+CQ1
# ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328y+l7vzhwRNGQ8cirOoo6
# CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYIDWTCCAkECAQEwggEBoYHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAtkQt/ebW
# SQ5DnG+aKRzPELCFE9GggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOusEXEwIhgPMjAyNTA0MTcyMzQ2NTdaGA8y
# MDI1MDQxODIzNDY1N1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA66wRcQIBADAK
# AgEAAgINcgIB/zAHAgEAAgISWzAKAgUA661i8QIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBCwUAA4IBAQAsiUv5X4zkPnQdqeqYTGweUPG4vb7y/Tu7CwkphEvrnYvBbcdQ
# cZVzJyAYYwUf8xQ3CQ+/UxMr3/iEju/GLylHafoE/IOHvrxDd7qgIESEAAu4H6bi
# 2upWThwC7VP1L71M7qf4+8X4GGNO4KDmK+Oqq+xXo/tT7Lqf5FKEAc+X/Dz1VOek
# X1iGC00x6dMAIIRT8nwq7igculAS34ObbW0Gl9gokgXJ8vi04HiRdNSIDMdrOK+e
# Np9sZ8lQr1JDbipiE8PyvPBEL60ycvaALv4EfeV8XgmIY0J30SQTOUPdSvolwt5M
# YpAD75ZZ0n1eqGTp+kuM4tQneWkSqTw/BdHwMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH4o6EmDAxASP4AAQAAAfgwDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQgjzT7WJTfDlGuz5aXFtoRA9hK++g0a6At7P/E1ixGNM0wgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDvzDPyXw1UkAUFYt8bR4UdjM90Qv5x
# nVaiKD3I0Zz3WjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB+KOhJgwMQEj+AAEAAAH4MCIEICZCuso8Jx0XGfYWeqhz4EPj7BI63Dxb
# 2kh86JGB1kuaMA0GCSqGSIb3DQEBCwUABIICALS/4ox/H3JPnY8Ds2c7sKGoV64D
# U788wHnTE+jKXnu/4cFIL21yqKkiWi6CvYpi/VMWnicF0QQREa3ZQW/Fm+nm+CRX
# 2nmkrGiIEqvz22i0R063ETbLyTevvYBbIQa8O31PB3TpRgYHCUVbi8liGZ8iyioS
# I64J4M5NAd2BPcHw1QwAZntOAcNCtXfIrV9dUnmIXT/9aSC5lkVNdwxOCpHPEK2X
# EMtOrRff+hO5jHxJKNi64XxZLZfC8CDLUqcR/DC4kuLvX9nx+ppuvE6JwEGOPKK7
# xiYI208fAwiTB7F5/3MmnTtqplECsW03E9u4/e6AlvEQEpu4q3VCSMn2NgyxU7q4
# AQKC23ozb9KpH5DqPImKIvSgG0QFObG03zbMBgDfUO7xiteb3Ycx0Wk7010mSl+n
# /LAe/baCyEXEW7vJ0pYXd7LIgf4WSs1iYsiVn9It38O2yCksRGeR7xRd4D0WGZr7
# NQfEy8cOhURSE/9x0+xE8/hrVELAU6giJut0c/sf/c3WsuEJ1QTs18HNYqQLMpAY
# 6PJ7VvuVBcAE8sMZ67aIEL7EEX7LHvxY7MDzZIzbDh+l5QA3DpIJw9V3SKG3BdxJ
# 4IO2wUWQqz5/Ikuz5y0+EoCQSIaD9gX1jEz8kMiLxRhOWEziOiqI/Jy21goKQybr
# olOYYNS8U7AL3Jo3
# SIG # End signature block
