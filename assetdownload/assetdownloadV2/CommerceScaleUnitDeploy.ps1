<#
.SYNOPSIS
    Import this module to get functions to handle deploying Commerce Scale Unit Extension Packages.
    
.DESCRIPTION
    This script can be imported to enable cmdlets to trigger an LCS deployment of
    Commerce Scale Unit Extension Package (from asset library) to a specific environment in an LCS project.

.NOTES
    This library depends on RESTHelpers.ps1

    Copyright © 2020 Microsoft. All rights reserved.
#>

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to deploy Commerce Scale Unit
#>
function Publish-CommerceScaleUnit
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the environment to deploy to")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The Commerce Scale Unit name")]
        [string]$ScaleUnitName,
        [Parameter(Mandatory=$true, HelpMessage="The asset's ID in the asset library")]
        [string]$AssetId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient

    $deployCommerceScaleUnitUri = "$LCSAPI/environment/v2/applyupdate/project/$($ProjectId)/environment/$($EnvironmentId)/commercescaleunit/$($ScaleUnitName)/asset/$($AssetId)"
    
    do
    {
        $retry = $false
        $request = New-JsonRequestMessage -Uri $deployCommerceScaleUnitUri -BearerTokenHeader $BearerTokenHeader
        
        $result = Get-AsyncResult -task $client.SendAsync($request)

        # Handle throttling error
        if ($result.StatusCode -eq 429)
        {
            Write-Host "Reached the maximum number of Commerce Cloud Scale Unit Extension deployments for the LCS environment: $($EnvironmentId)."
            $headers = @{}
            $result.Headers | ForEach-Object {
                $headers[$_.Key] = $_.Value
            }

            $retryAfter = [int]::Parse($headers["Retry-After"])
            Write-Host "Retry the deployment after $retryAfter seconds. Waiting for $retryAfter seconds..."
            $retry = $true
            Start-Sleep -Seconds $retryAfter
        }
        elseif ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
        {
            try
            {
                $failureResponse = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            catch { }

            if ($failureResponse)
            {
                if ($failureResponse.ErrorMessage)
                {
                    if ($failureResponse.OperationActivityId)
                    {
                        throw "Error in deploying Commerce Cloud Scale Unit Extension file asset - '$($activity.ErrorMessage)' (Activity Id: '$($failureResponse.OperationActivityId)')"
                    }
                    else
                    {
                        throw "Error in deploying Commerce Cloud Scale Unit Extension file asset - '$($activity.ErrorMessage)'"
                    }
                }
                elseif ($failureResponse.OperationActivityId)
                {
                    throw "API return code - $($result.StatusCode): $($result.ReasonPhrase) (Activity Id - '$($failureResponse.OperationActivityId)')"
                }
                else
                {
                    throw "API return code - $($result.StatusCode): $($result.ReasonPhrase)"
                }
            }
            else
            {
                throw "API return code - $($result.StatusCode): $($result.ReasonPhrase)"
            }
        }
    }
    while ($retry)

    $activity = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if ($activity.IsSuccess -ne $True)
    {
        if ($activity.ErrorMessage)
        {
            throw "Error in deploying Commerce Cloud Scale Unit Extension file asset - '$($activity.ErrorMessage)' (Activity Id: '$($activity.OperationActivityId)')"
        }
        elseif ($activity.OperationActivityId)
        {
            throw "Error in deploying Commerce Cloud Scale Unit Extension file asset (Activity Id: '$($activity.OperationActivityId)')"
        }
        else
        {
            throw "Exceptions occurred in deploying Commerce Cloud Scale Unit Extension file asset."
        }
    }

    return $activity
}


<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to get the Commerce Scale Unit Deployment Status
#>
function Get-CommerceScaleUnitStatus
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the environment to deploy to")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The Commerce Cloud Scale Unit name")]
        [string]$ScaleUnitName,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient
    
    $getStatusFileAssetUri = "$LCSAPI/environment/v2/fetchstatus/project/$($ProjectId)/environment/$($EnvironmentId)/commercescaleunit/$($ScaleUnitName)"

    $request = New-JsonRequestMessage -Uri $getStatusFileAssetUri -BearerTokenHeader $BearerTokenHeader -HttpMethod ([System.Net.Http.HttpMethod]::Get)

    $result = Get-AsyncResult -task $client.SendAsync($request)

    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $failureResponse = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if ($failureResponse)
        {
            if ($failureResponse.ErrorMessage)
            {
                if ($failureResponse.OperationActivityId)
                {
                    throw "Error in api call for retrieving status of Commerce Cloud Scale Unit Extension deployment action: '$($failureResponse.ErrorMessage)' (Activity Id: '$($failureResponse.OperationActivityId)')"
                }
                else
                {
                    throw "Error in api capp for retrieving status of Commerce Cloud Scale Unit Extension deployment action: '$($failureResponse.ErrorMessage)'"
                }
            }
            elseif ($failureResponse.OperationActivityId)
            {
                throw "API return code - $($result.StatusCode): $($result.ReasonPhrase) (Activity Id - '$($failureResponse.OperationActivityId)')"
            }
            else
            {
                throw "API return code - $($result.StatusCode): $($result.ReasonPhrase)"
            }
        }
        else
        {
            throw "API return code - $($result.StatusCode): $($result.ReasonPhrase)"
        }
    } 

    $activity = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if ($activity.IsSuccess -ne $True)
    {
        if ($activity.ErrorMessage)
        {
            throw "Not able to retrieve the status of Commerce Cloud Scale Unit Extension deployment: '$($activity.ErrorMessage)' (Activity Id: '$($activity.OperationActivityId)')"
        }
        elseif ($activity.OperationActivityId)
        {
            throw "Not able to retrieve the status of Commerce Cloud Scale Unit Extension deployment. (Activity Id: '$($activity.OperationActivityId)')"
        }
        else
        {
            throw "Exceptions occurred in retrieving the status of Commerce Cloud Scale Unit Extension deployment."
        }
    }

    return $activity
}
# SIG # Begin signature block
# MIIoDwYJKoZIhvcNAQcCoIIoADCCJ/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBrpzJTrgMP3B5A
# t18rjta5e+BTrt2zt76CaPO/50jQ2aCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IC3OES4wNMb7ByRYeI0tmJj+5f2C5jB9+hNZ+a0L4XMOMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAAJ6KPbLYvYR7uK2V3KIgulTd04w9dq1E
# oQvffLfy43/Hn1iHI7cD9i64HjzFN0hm8M7G54RiCvQF4JfxCuFHRWD95YIIEyHm
# uzs7nEmWfGDJG4aeeJnlWdn8s9Uf/YYR6TFG5Vsur25a5CGdkxev8Xa8CqPP9Lpd
# G6IummoSoiZWHGNXDQw7dajBqWcRdy2aHvUKR3BPtyxw49cMpQ/0xGpedhUkm6bg
# bQXWP+S+fOgBxeUyeQScQ31JnWpuWyn1jbOcvt5imN/3fk7qIjjgQNvVGX6gh4ES
# +69i5HXNI75nNv+BHRAykzZfPh1rafuRqtZNO2UQlR7RhMgoaAT/NaGCF5cwgheT
# BgorBgEEAYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCB3x+xkS5A7NbVg/IVWpIiN16Hz0aMk
# pFJNO5DPOPEmlwIGZ/hMBO0oGBMyMDI1MDQxODAwMjAxOS45NjFaMASAAgH0oIHR
# pIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046MzMwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAg9XmkcUQOZG
# 5gABAAACDzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yNTAxMzAxOTQzMDRaFw0yNjA0MjIxOTQzMDRaMIHLMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQg
# QW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzMw
# My0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCl6DTurxf66o73G0A2
# yKo1/nYvITBQsd50F52SQzo2cSrt+EDEFCDlSxZzWJD7ujQ1Z1dMbMT6YhK7JUvw
# xQ+LkQXv2k/3v3xw8xJ2mhXuwbT+s1WOL0+9g9AOEAAM6WGjCzI/LZq3/tzHr56i
# n/Z++o/2soGhyGhKMDwWl4J4L1Fn8ndtoM1SBibPdqmwmPXpB9QtaP+TCOC1vAaG
# QOdsqXQ8AdlK6Vuk9yW9ty7S0kRP1nXkFseM33NzBu//ubaoJHb1ceYPZ4U4EOXB
# Hi/2g09WRL9QWItHjPGJYjuJ0ckyrOG1ksfAZWP+Bu8PXAq4s1Ba/h/nXhXAwuxT
# hpvaFb4T0bOjYO/h2LPRbdDMcMfS9Zbhq10hXP6ZFHR0RRJ+rr5A8ID9l0UgoUu/
# gNvCqHCMowz97udo7eWODA7LaVv81FHHYw3X5DSTUqJ6pwP+/0lxatxajbSGsm26
# 7zqVNsuzUoF2FzPM+YUIwiOpgQvvjYIBkB+KUwZf2vRIPWmhAEzWZAGTox/0vj4e
# HgxwER9fpThcsbZGSxx0nL54Hz+L36KJyEVio+oJVvUxm75YEESaTh1RnL0Dls91
# sBw6mvKrO2O+NCbUtfx+cQXYS0JcWZef810BW9Bn/eIvow3Kcx0dVuqDfIWfW7im
# eTLAK9QAEk+oZCJzUUTvhh2hYQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFJnUMQ2O
# tyAhLR/MD2qtJ9lKRP9ZMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNy
# bDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQBTowbo1bUE
# 7fXTy+uW9m58qGEXRBGVMEQiFEfSui1fhN7jS+kSiN0SR5Kl3AuV49xOxgHo9+GI
# ne5Mpg5n4NS5PW8nWIWGj/8jkE3pdJZSvAZarXD4l43iMNxDhdBZqVCkAYcdFVZn
# xdy+25MRY6RfaGwkinjnYNFA6DYL/1cxw6Ya4sXyV7FgPdMmxVpffnPEDFv4mcVx
# 3jvPZod7gqiDcUHbyV1gaND3PejyJ1MGfBYbAQxsynLX1FUsWLwKsNPRJjynwlzB
# T/OQbxnzkjLibi4h4dOwcN+H4myDtUSnYq9Xf4YvFlZ+mJs5Ytx4U9JVCyW/WERt
# IEieTvTRgvAYj/4Mh1F2Elf8cdILgzi9ezqYefxdsBD8Vix35yMC5LTnDUoyVVul
# UeeDAJY8+6YBbtXIty4phIkihiIHsyWVxW2YGG6A6UWenuwY6z9oBONvMHlqtD37
# ZyLn0h1kCkkp5kcIIhMtpzEcPkfqlkbDVogMoWy80xulxt64P4+1YIzkRht3zTO+
# jLONu1pmBt+8EUh7DVct/33tuW5NOSx56jXQ1TdOdFBpgcW8HvJii8smQ1TQP42H
# NIKIJY5aiMkK9M2HoxYrQy2MoHNOPySsOzr3le/4SDdX67uobGkUNerlJKzKpTR5
# ZU0SeNAu5oCyDb6gdtTiaN50lCC6m44sXjCCB3EwggVZoAMCAQICEzMAAAAVxedr
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
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjMzMDMt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQBetIzj2C/MkdiI03EyNsCtSOMdWqCBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA66wE
# bDAiGA8yMDI1MDQxNzIyNTEyNFoYDzIwMjUwNDE4MjI1MTI0WjB3MD0GCisGAQQB
# hFkKBAExLzAtMAoCBQDrrARsAgEAMAoCAQACAhQYAgH/MAcCAQACAhInMAoCBQDr
# rVXsAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMH
# oSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAIGjTfjeNWcxyUPgY5ko
# daq10+WURHJfFKClihRJAtnKKpAniPrLc/akek/JkM2m6noRBqho6sy1PzC8Om7i
# 1tFcwJ5PiQTMzQKB6ZzlKDMalVg70YFsYvfqFDTN1kkH+wrNmXioQwavil8QX4n8
# 6rQn0inY3r+JaWYtiHID23avmkIFVQjVpBmm8cxAJGh8iRCLmPVXqFxa4zoR/+1/
# ZMWlYcKpvEEIU6qviUHxbSEENvcLhHzVtKR40dV38xo2Dfa3cih+QJP9U9YZeFU5
# cZruk/dsWBxe/D67CAfDZFwnpP4mK9WM/jEuP3VQ50H/obyzZ4MqG1LiOeLtoSgc
# a9kxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAg9XmkcUQOZG5gABAAACDzANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
# AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCA/ycA0lkZNrjSokdQJ
# i1Uk8Ey0HqBsH+vEk0WlQA6RiDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0E
# IN1Hd5UmKnm7FW7xP3niGsfHJt4xR8Xu+MxgXXc0iqn4MIGYMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIPV5pHFEDmRuYAAQAAAg8wIgQg
# m9xNb1Roin7p4H6ujP74O1OwbgHXVGp5thghpz3GFPQwDQYJKoZIhvcNAQELBQAE
# ggIASlb6xaXRqWaEQsmUF/XUi7plUghFW4ZNX6x32QKADKsethRawVrEjdZr8No2
# D9sXnRjCOVY4I4fY303i8o7xiDSJb36ikcYwmD18lC5wT73Cm70Qw6a+BzL0t5VK
# dxLJsx7cePFSkaRMe5p0Azhal8tXlXE3rFBLPJtCXVtRXT2P6ySnyFVIGO+uJ3kC
# PeLb5L37J3De8QfwpEWH5faypgDDVLsov1WIYnhyuDwPki1hFVsnaXOFH4Eu0P9V
# AfVvhZ+nA7ScLXlnhb7sczxOVz2UTKkaEW3x72PIgMGGCNsiszpYk3cnjkMFuTQu
# /wOYxbm8h4FFE/P2+ilxkokGm19qq3GhRpYhQBwVnQsEa2ujOE0YJGCqNTQn/w+Y
# S/51bg3GSlV2d+Q+DhG5kjK7xMT/i1ui17gqfrG0Q3/pOTWtDOPTPfDZ6ZZYsaGx
# /LG4mCYVcoxdra5HzcdMiPmnngl2T4rxBytgzDsn/532tBokTMsqzmlbceUPTgrf
# hF8bYELdJaYNJmDCFcEvcGxmrE8Rp6Oe55nlyAd09rTsFeG1+lM8f6Q69BVMNT37
# wRlePdoaJLB1KYNzGBIP8G7tthWNdqZ9sc5ygn0uuPkXmTAFfZcm2REHoOWaNbbu
# T8si74O9x3NNb2bYQMEu0CHIXIBJLzKM8mzQ0gV16G61G7M=
# SIG # End signature block
