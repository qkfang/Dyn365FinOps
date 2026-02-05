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
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.PowerPlatform.VSShared.Util.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Xrm.Tooling.Connector.dll"
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
        if ($allBlank.Count -eq 0) {
            throw "Results not recorded, please look at the test logs on the environment"
        }
    }
    Write-Host "Ending test request"
}
# SIG # Begin signature block
# MIIoDwYJKoZIhvcNAQcCoIIoADCCJ/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBZKHSekObzreb2
# EEDVvBUCoAambgoYG6RGOf0o1zd9FKCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGe8wghnrAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IDpn7duUAUnIcIi24vOizE+0GYg5uQrr4cF0fiqMMieBMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAiMpFNUVDJCe89i4gj0EGKqgkWdqj9RTb
# DPaGuOoZj5h7+qbCjgB4Jpg+QjdGueBxGOALER9CeEj84sCBxhCun7NsmoQBM8g1
# gfSoNVHfk++0/IiVYoqX0xjuOPU2BBzJb4LVxTQV1uWlu2U+7A7MHq2DMW3b+Fx5
# drCKdrLcdGTVwAv7k10kpuI6BwZuYU6ZDqpEEr9NqeCR3gU9768qOGX1oFOpEVCc
# 4j8YhGoO12mfCzBNZSzZNNgdM6y4v4JbGtTsXw2A1qfniaeXARHcrzJi3pdqUToq
# Aq0GK7vO/6r2rZ7wwBOFE4tjL9XDpkEsgw5a2CEcw2BK6TbaaaGZQKGCF5cwgheT
# BgorBgEEAYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBheE2ORLNzcOD3efA4WOaiK5WORhv7
# Y5LIUlCWGOdDYAIGZ/g0cGLdGBMyMDI1MDQxODAwMjAwNy42NjRaMASAAgH0oIHR
# pIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046RjAwMi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAgU8dWyCRIfN
# /gABAAACBTANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yNTAxMzAxOTQyNDlaFw0yNjA0MjIxOTQyNDlaMIHLMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQg
# QW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RjAw
# Mi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCSkvLfd7gF1r2wGdy8
# 5CFYXHUC8ywEyD4LRLv0WYEXeeZ0u5YuK7p2cXVzQmZPOHTN8TWqG2SPlUb+7Pld
# zFDDAlR3vU8piOjmhu9rHW43M2dbor9jl9gluhzwUd2SciVGa7f9t67tM3KFKRSM
# XFtHKF3KwBB7aVo+b1qy5p9DWlo2N5FGrBqHMEVlNyzreHYoDLL+m8fSsqMu/iYU
# qxzK5F4S7IY5NemAB8B+A3QgwVIi64KJIfeKZUeiWKCTf4odUgP3AQilxh48P6z7
# AT4IA0dMEtKhYLFs4W/KNDMsYr7KpQPKVCcC5E8uDHdKewubyzenkTxy4ff1N3g8
# yho5Pi9BfjR0VytrkmpDfep8JPwcb4BNOIXOo1pfdHZ8EvnR7JFZFQiqpMZFlO5C
# AuTYH8ujc5PUHlaMAJ8NEa9TFJTOSBrB7PRgeh/6NJ2xu9yxPh/kVN9BGss93MC6
# UjpoxeM4x70bwbwiK8SNHIO8D8cql7VSevUYbjN4NogFFwhBClhodE/zeGPq6y6i
# xD4z65IHY3zwFQbBVX/w+L/VHNn/BMGs2PGHnlRjO/Kk8NIpN4shkFQqA1fM08fr
# rDSNEY9VKDtpsUpAF51Y1oQ6tJhWM1d3neCXh6b/6N+XeHORCwnY83K+pFMMhg8i
# sXQb6KRl65kg8XYBd4JwkbKoVQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFHR6Wrs2
# 7b6+yJ3bEZ9o5NdL1bLwMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNy
# bDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQAOuxk47b1i
# 75V81Tx6xo10xNIr4zZxYVfkF5TFq2kndPHgzVyLnssw/HKkEZRCgZVpkKEJ6Y4j
# vG5tugMi+Wjt7hUMSipk+RpB5gFQvh1xmAEL2flegzTWEsnj0wrESplI5Z3vgf2e
# GXAr/RcqGjSpouHbD2HY9Y3F0Ol6FRDCV/HEGKRHzn2M5rQpFGSjacT4DkqVYmem
# /ArOfSvVojnKEIW914UxGtuhJSr9jOo5RqTX7GIqbtvN7zhWld+i3XxdhdNcflQz
# 9YhoFqQexBenoIRgAPAtwH68xczr9LMC3l9ALEpnsvO0RiKPXF4l22/OfcFffaph
# nl/TDwkiJfxOyAMfUF3xI9+3izT1WX2CFs2RaOAq3dcohyJw+xRG0E8wkCHqkV57
# BbUBEzLX8L9lGJ1DoxYNpoDX7iQzJ9Qdkypi5fv773E3Ch8A+toxeFp6FifQZyCc
# 8IcIBlHyak6MbT6YTVQNgQ/h8FF+S5OqP7CECFvIH2Kt2P0GlOu9C0BfashnTjod
# mtZFZsptUvirk/2HOLLjBiMjDwJsQAFAzJuz4ZtTyorrvER10Gl/mbmViHqhvNAC
# fTzPiLfjDgyvp9s7/bHu/CalKmeiJULGjh/lwAj5319pggsGJqbhJ4FbFc+oU5zf
# fbm/rKjVZ8kxND3im10Qp41n2t/qpyP6ETCCB3EwggVZoAMCAQICEzMAAAAVxedr
# ngKbSZkAAAAAABUwDQYJKoZIhvcNAQELBQAwgYgxCzAJBgNVBAYTAlVTMRMwEQYD
# VQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNy
# b3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBSb290IENlcnRp
# ZmljYXRlIEF1dGhvcml0eSAyMDEwMB4XDTIxMDkzMDE4MjIyNVoXDTMwMDkzMDE4
# MzIyNVowfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwggIiMA0GCSqGSIb3
# DQEBAQUAA4ICDwAwggIKAoICAQDk4aZM57RyIQt5osvXJHm9DtWC0/3unAcH0qls
# TnXIyjVX9gF/bErg4r25PhdgM/9cT8dm95VTcVrifkpa/rg2Z4VGIwy1jRPPdzLA
# EBjoYH1qUoNEt6aORmsHFPPFdvWGUNzBRMhxXFExN6AKOG6N7dcP2CZTfDlhAnrE
# qv1yaa8dq6z2Nr41JmTamDu6GnszrYBbfowQHJ1S/rboYiXcag/PXfT+jlPP1uyF
# Vk3v3byNpOORj7I5LFGc6XBpDco2LXCOMcg1KL3jtIckw+DJj361VI/c+gVVmG1o
# O5pGve2krnopN6zL64NF50ZuyjLVwIYwXE8s4mKyzbnijYjklqwBSru+cakXW2dg
# 3viSkR4dPf0gz3N9QZpGdc3EXzTdEonW/aUgfX782Z5F37ZyL9t9X4C626p+Nuw2
# TPYrbqgSUei/BQOj0XOmTTd0lBw0gg/wEPK3Rxjtp+iZfD9M269ewvPV2HM9Q07B
# MzlMjgK8QmguEOqEUUbi0b1qGFphAXPKZ6Je1yh2AuIzGHLXpyDwwvoSCtdjbwzJ
# NmSLW6CmgyFdXzB0kZSU2LlQ+QuJYfM2BjUYhEfb3BvR/bLUHMVr9lxSUV0S2yW6
# r1AFemzFER1y7435UsSFF5PAPBXbGjfHCBUYP3irRbb1Hode2o+eFnJpxq57t7c+
# auIurQIDAQABo4IB3TCCAdkwEgYJKwYBBAGCNxUBBAUCAwEAATAjBgkrBgEEAYI3
# FQIEFgQUKqdS/mTEmr6CkTxGNSnPEP8vBO4wHQYDVR0OBBYEFJ+nFV0AXmJdg/Tl
# 0mWnG1M1GelyMFwGA1UdIARVMFMwUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUH
# AgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0
# b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEFBQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMA
# dQBiAEMAQTALBgNVHQ8EBAMCAYYwDwYDVR0TAQH/BAUwAwEB/zAfBgNVHSMEGDAW
# gBTV9lbLj+iiXGJo0T2UkFvXzpoYxDBWBgNVHR8ETzBNMEugSaBHhkVodHRwOi8v
# Y3JsLm1pY3Jvc29mdC5jb20vcGtpL2NybC9wcm9kdWN0cy9NaWNSb29DZXJBdXRf
# MjAxMC0wNi0yMy5jcmwwWgYIKwYBBQUHAQEETjBMMEoGCCsGAQUFBzAChj5odHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpL2NlcnRzL01pY1Jvb0NlckF1dF8yMDEw
# LTA2LTIzLmNydDANBgkqhkiG9w0BAQsFAAOCAgEAnVV9/Cqt4SwfZwExJFvhnnJL
# /Klv6lwUtj5OR2R4sQaTlz0xM7U518JxNj/aZGx80HU5bbsPMeTCj/ts0aGUGCLu
# 6WZnOlNN3Zi6th542DYunKmCVgADsAW+iehp4LoJ7nvfam++Kctu2D9IdQHZGN5t
# ggz1bSNU5HhTdSRXud2f8449xvNo32X2pFaq95W2KFUn0CS9QKC/GbYSEhFdPSfg
# QJY4rPf5KYnDvBewVIVCs/wMnosZiefwC2qBwoEZQhlSdYo2wh3DYXMuLGt7bj8s
# CXgU6ZGyqVvfSaN0DLzskYDSPeZKPmY7T7uG+jIa2Zb0j/aRAfbOxnT99kxybxCr
# dTDFNLB62FD+CljdQDzHVG2dY3RILLFORy3BFARxv2T5JL5zbcqOCb2zAVdJVGTZ
# c9d/HltEAY5aGZFrDZ+kKNxnGSgkujhLmm77IVRrakURR6nxt67I6IleT53S0Ex2
# tVdUCbFpAUR+fKFhbHP+CrvsQWY9af3LwUFJfn6Tvsv4O+S3Fb+0zj6lMVGEvL8C
# wYKiexcdFYmNcP7ntdAoGokLjzbaukz5m/8K6TT4JDVnK+ANuOaMmdbhIurwJ0I9
# JZTmdHRbatGePu1+oDEzfbzL6Xu/OHBE0ZDxyKs6ijoIYn/ZcGNTTY3ugm2lBRDB
# cQZqELQdVTNYs6FwZvKhggNQMIICOAIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkYwMDIt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQDVsH9p1tJn+krwCMvqOhVvXrbetKCBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA66vs
# 1TAiGA8yMDI1MDQxNzIxMTA0NVoYDzIwMjUwNDE4MjExMDQ1WjB3MD0GCisGAQQB
# hFkKBAExLzAtMAoCBQDrq+zVAgEAMAoCAQACAg7YAgH/MAcCAQACAhSyMAoCBQDr
# rT5VAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMH
# oSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAAqpZnzTnxEnFwLSht4u
# l88ef0p8L9STqkKIV3WbRVkp26t9WAYCELAOirjzIbCK4LlvI6ajAfr/ju9psP5Z
# /357Rzu5da31gSnNjkUjnfUpFD626zJ1fpOg9bpaT4sxrGEjbzO1o7VjTt6SY6w3
# rfHvdmW5G50U+/GUW2m/lXzStEE/vmAPAnra2cdL61on0rIehIdvMyx3j74dzWO8
# 8tzCnQkgm9muAUpFJBVUvH+M6AaNfxJocud8oLjIgsEg9zdjZwKmK8/4QRsDPvwf
# F55cET6fnhI/6c6vWuVv//1pcQR+kyEmcUZGrsF3EMMYEfC+a2ikDDBnIaUL1qoI
# wr0xggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAgU8dWyCRIfN/gABAAACBTANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
# AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAu7+A+vzwrxi6+GM+A
# 3Cf9IpeLpLk1V778Mzy1uu0VqDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0E
# IIANAz3ceY0umhdWLR2sJpq0OPqtJDTAYRmjHVkwEW9IMIGYMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIFPHVsgkSHzf4AAQAAAgUwIgQg
# yeBq2JnTypbh+6amUPqsU7YvJEpE+fqce8Bu+5O+1v4wDQYJKoZIhvcNAQELBQAE
# ggIAHs7wWkonoRDV6P1sDslLaM8b/B+iq60OCqucoj7Fk4rxx+ARxJDol+d61Hyu
# eY2RtaO9YBUwK2SFGUNmimB3LF225x0CIXFmk7+f3rPrc6KuftPU+peojHzMnvu8
# 6Hu5SuLupMTmx9W3q9IkD3SEN1KUl9Sgg1pBD3FRnqsOK42NYL/CKHIucn9Jje0M
# HPSGm2BKMFjc9yDrs+n2EViiuxEIb/OWtdm7a1mdf8vostxMQwfsUKNLOcm/L3nm
# uQ+1eg6llDP9RDVA+vq9MDgwKC8I3D6OVp3E19fhBZabw7UQV2AdG3m+QD4lrnat
# 1ZZUGyAVtiRQI9ICeplamZenfRSYzYUcbZy0//yoG+XLZ94IMH48/LrudhLAwCCu
# 31KyfdCY8iaRLD/8Ap12/i1UDdUSDkAWpdHH2VRxOCyUIlx0IStbblBc1UcwZa+B
# T2vjC3YvPhSFcJwKt9bcwatDYYZG5kadS6DPBK1NIuq2Ix60+5rD8dpiEyY9/9Ye
# O4lXqwisT91TJOL6slQv/duRO7AFBRiy42nqTrGOQal0hyocoxq2O+30Ye/+lzS3
# 6G+i/6Kzae+Z0fDQstqIZM+WPhzqrQ4Fvo01GSWp8NCpQKtqRf21CDMKmjIRpNYF
# k+8Pj3mmFwLpXmKS7k58NmeTDzbWpY5z+bfkBBugMG0/vek=
# SIG # End signature block
