<#
.SYNOPSIS
    Import this module to get functions to handle file uploads to the asset library.
    
.DESCRIPTION
    This script can be imported to enable cmdlets to create a file asset, upload to blob storage,
    and commit the file asset to the asset library.

.NOTES
    This library depends on the Azure PowerShell module "AzureRM". It handles different versions
    of the dependencies it has to Active Directory Authentication Library (ADAL) and Azure Storage.

    Copyright © 2018 Microsoft. All rights reserved.
#>


<#
.SYNOPSIS
    Get version of an object's type assembly
#>
function Get-AssemblyVersion
{
    param($object)

    return $object.GetType().Assembly.GetName().Version
}

<#
.SYNOPSIS
    Authenticates with Azure Active Directory based on UserName/Password, and returns the Authorization Header
#>
function Get-AADAuthHeader
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory registered client application id")]
        [string]$ClientId,
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory username, e.g. bob@foo.bar")]
        [string]$UserName,
        [Parameter(Mandatory=$true, HelpMessage="Password of the user (secure string)")]
        [string]$Password,
        [Parameter(Mandatory=$false, HelpMessage="Auth provider URL")]
        [string]$AuthProviderUri = "https://login.microsoftonline.com/common/oauth2",
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com",
        [Parameter(Mandatory=$false, HelpMessage="Optional reference variable for token expiration date")]
        [ref]$ExpirationData
    )

    try
    {
        Import-Module AzureRM -ErrorAction Stop
    }
    catch
    {
        Write-Host "*Task version upgrade required*"
        throw $_.Exception.Message
    }

    try
    {
        Import-Module $PSScriptRoot\LogToTelemetry.ps1
        LogCustomEventToTelemetry -AuthenticationMechanism "Preview/Public Marketplace using ADAL" -ClientId $ClientId
    }
    catch
    {
        Write-Host "Error logging ClientID to telemetry"
        Write-Host -Foreground Red -Background Black ($_)
    }

    $authContext = New-Object -TypeName Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext -ArgumentList @($AuthProviderUri)

    $version = Get-AssemblyVersion $authContext
    if ($version -lt "3.0.0.0")
    {
        # Older versions of ADAL use "UserCredential"
        $userCredential = New-Object -TypeName Microsoft.IdentityModel.Clients.ActiveDirectory.UserCredential -ArgumentList @($Username, $Password)
    }
    else
    {
        # Version 3.0+ of ADAL uses "UserPasswordCredential"
        $userCredential = New-Object -TypeName Microsoft.IdentityModel.Clients.ActiveDirectory.UserPasswordCredential -ArgumentList @($Username, $Password)
    }

    try
    {
        $authResult = $authContext.AcquireToken($LCSAPI, $ClientId, $userCredential)
        if ($ExpirationData)
        {
            $ExpirationData.Value = $authResult.ExpiresOn
        }
    }
    catch
    {
        # Authentication errors will throw an error from AcquireToken so the actual authentication error msg is in the inner exception
        if ($_.Exception.InnerException -and $_.Exception.InnerException.Message.StartsWith("AAD"))
        {
            throw $_.Exception.InnerException
        }
        else
        {
            throw $_.Exception
        }
    }

    return $authResult.CreateAuthorizationHeader()
}

function Get-AADAuthHeaderInteractive
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory registered client application id")]
        [string]$ClientId,
        [Parameter(Mandatory=$false, HelpMessage="Auth provider URL")]
        [string]$AuthProviderUri = "https://login.microsoftonline.com/common/oauth2",
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com",
        [Parameter(Mandatory=$true, HelpMessage="Auth Reply URL")]
        [string]$ReplyURL,
        [Parameter(Mandatory=$false, HelpMessage="Optional reference variable for token expiration date")]
        [ref]$ExpirationData
    )

    $authContext = New-Object -TypeName Microsoft.IdentityModel.Clients.ActiveDirectory.AuthenticationContext -ArgumentList @($AuthProviderUri)

    try
    {
        $authResult = $authContext.AcquireToken($LCSAPI, $ClientId, $ReplyURL)
        if ($ExpirationData)
        {
            $ExpirationData.Value = $authResult.ExpiresOn
        }
    }
    catch
    {
        # Authentication errors will throw an error from AcquireToken so the actual authentication error msg is in the inner exception
        if ($_.Exception.InnerException -and $_.Exception.InnerException.Message.StartsWith("AAD"))
        {
            throw $_.Exception.InnerException
        }
        else
        {
            throw $_.Exception
        }
    }

    return $authResult.CreateAuthorizationHeader()
}

# SIG # Begin signature block
# MIIoJwYJKoZIhvcNAQcCoIIoGDCCKBQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDvTsOSqnYDuT+5
# 6gtSxMk2/gSPcmMHp2oj3peFj4W+eqCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGgcwghoDAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# IEo5Mc0zcHld3nSIUbZEiYBxor5HhEgBGlGx1dz7W4pbMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAdPyrL2bbFBYOtm3AtVa7KpdMjmCpnHGm
# Jw5cQnUp/ryiEMXJzTm/3wg2SMvVRqVpiMzDpu+53jdkNKzJcq9iqVBlHyXKvT6M
# 1zC4sv4fh9ghafFsR1VS1pC6m/cJPQNx5O054/KuD3lHzXMJWCCwOBPo0lSrztrE
# tamjp7if/kS8vsTXmuxKgYYuS6C6sovIoZ9FWkIYrOZHOF63YSDop+Lyx2PvVynf
# 2AEanbWJ6A3zDu30YKMwGC0GmAs3sq+S0yGBw7VwKWcGJUyfzRBLvz83WUJECIh5
# 9Hr/bTrY+y8+kKWXqzLxLdRzoSMzEw1SLXgOp2EITr3g6c29Qavae6GCF68wgher
# BgorBgEEAYI3AwMBMYIXmzCCF5cGCSqGSIb3DQEHAqCCF4gwgheEAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFZBgsqhkiG9w0BCRABBKCCAUgEggFEMIIBQAIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDOO2iFrzWQML7sMbejvBxZrMMR2yUu
# zs8DQqDwmcfqeQIGZ+03K3uvGBIyMDI1MDQxODAwMjAzOS4wOVowBIACAfSggdmk
# gdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloIIR/jCCBygwggUQoAMCAQICEzMAAAH+
# 0KjCezQhCwEAAQAAAf4wDQYJKoZIhvcNAQELBQAwfDELMAkGA1UEBhMCVVMxEzAR
# BgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1p
# Y3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3Rh
# bXAgUENBIDIwMTAwHhcNMjQwNzI1MTgzMTE4WhcNMjUxMDIyMTgzMTE4WjCB0zEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEtMCsGA1UECxMkTWlj
# cm9zb2Z0IElyZWxhbmQgT3BlcmF0aW9ucyBMaW1pdGVkMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046NDAxQS0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQC8vCEXFaWoDjeiWwTg8J6BniZJ+wfZhNIoRi/wafffrYGZrJx1/lPe1DGk/c1a
# brZgdSJ4hBfD7S7iqVrLgA3ciicj7js2mL1+jnbF0BcxfSkatzR6pbxFY3dt/Nc8
# q/Ts7XyLYeMPIu7LBjIoD0WZZt4+NqF/0zB3xCDKCQ+3AOtVAYvI6TIzdVOIcqqE
# a70EIZVF0db2WY8yutSU9aJhX0tUIHlVh34ARS11+oB2qXNXEDncSDFKqGnolt8Q
# qdN1x8/pPwyKvQevBNO1XaHbIMG2NdtAhqrJwo5vrfcZ9GSfbXos4MGDfs//HCGh
# 1dPzVkLZoc3t7EQOaZuJayyMa8UmSWLaDp23TV5KE6IaaFuievSpddwF6o1vpCgX
# yNf+4NW1j2m8viPxoRZLj2EpQfSbOwK5wivBRL7Hwy5PS5/tVcIU0VuIJQ1FOh/E
# ncHjnh4YmEvR/BRNFuDIJukuAowoOIJG5vrkOFp4O9QAAlP3cpIKh4UKiSU9q9uB
# DJqEZkMv+9YBWNflvwnOGXL2AYJ0r+qLqL5zFnRLzHoHbKM9tl90FV8f80Gn/Uuf
# vFt44RMA6fs5P0PdQa3Sr4qJaBjjYecuPKGXVsC7kd+CvIA7cMJoh1Xa2O+QlrLa
# o6cXsOCPxrrQpBP1CB8l/BeevdkqJtgyNpRsI0gOfHPbKQIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFG/Oe4n1JTaDmX/n9v7kIGJtscXdMB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQCJPg1S87aXD7R0My2wG7GZfajeVVCqdCS4hMAYgYKAj6yXtmpk5MN3
# wurGwfgZYI9PO1ze2vwCAG+xgjNaMXCKgKMJA4OrWgExY3MSwrNyQfEDNijlLN7s
# 4+QwDcMDFWrhJJHzL5NELYZw53QlF5nWU+WGU+X1cj7Pw6C04+ZCcsuI/2rOlMfA
# XN76xupKfxx6R24xl0vIcmTc2LDcCeCVT9ZPMaxAB1yH1JVXgseJ9SebBN/SLTuI
# q1OU2SrdvHWLJaDs3uMZkAFFZPaZf5gBUeUrbu32f5a1hufpw4k1fouwfzE9UFFg
# AhFWRawzIQB2g/12p9pnPBcaaO5VD3fU2HMeOMb4R/DXXwNeOTdWrepQjWt7fjMw
# xNHNlkTDzYW6kXe+Jc1HcNU6VL0kfjHl6Z8g1rW65JpzoXgJ4kIPUZqR9LsPlrI2
# xpnZ76wFSHrYpVOWESxBEdlHAJPFuLHVjiInD48M0tzQd/X2pfZeJfS7ZIz0JZNO
# OzP1K8KMgpLEJkUI2//OkoiWwfHuFA1AdIxsqHT/DCfzq6IgAsSNrNSzMTT5fqtw
# 5sN9TiH87/S+ZsXcExH7jmsBkwARMmxEM/EckKj/lcaFZ2D8ugnldYGs4Mvjhg2s
# 3sVGccQACvTqx+Wpnx55XcW4Mp0/mHX1ZScZbA7Uf9mNTM6hUaJXeDCCB3EwggVZ
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
# Yn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNZMIICQQIBATCCAQGhgdmk
# gdYwgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNV
# BAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UE
# CxMeblNoaWVsZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNy
# b3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCEY0cP9rtD
# RtAtZUb0m4bGAtFex6CBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpX
# YXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQg
# Q29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAy
# MDEwMA0GCSqGSIb3DQEBCwUAAgUA66t7IDAiGA8yMDI1MDQxNzEzMDUzNloYDzIw
# MjUwNDE4MTMwNTM2WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDrq3sgAgEAMAoC
# AQACAgq5AgH/MAcCAQACAhRuMAoCBQDrrMygAgEAMDYGCisGAQQBhFkKBAIxKDAm
# MAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcN
# AQELBQADggEBAKcblXgMu3XCeVmOapZwjVIBDGHJspwjPmmj73K/1RpIfC8MC/9F
# ByNSjiDPBDyX6B7lwr9ozq1Y/vx4N6ymWHxqyRTTaD4EiRV630GLs2YyH+smlJhZ
# KqtP/t/90UNAbJXJnCykKZk8Gw9EB70IZ+hzepmPTfxDdTCpeegvcVZgB8XLMfgL
# jVh61AC+fzVReA3TmKvkmkbfRu0Y5qZSXA1AW6znny6KYBMqqAZnWKHzn0XormFW
# TCHe1cJyEWQe5FltH6xhm5E4PoUPu+jOXCD3M1X7RSGgxI8A/GH3jirnZK8+n3sj
# PjlFx79ClV5b0HmUDk/kNW1liouHX81GXVIxggQNMIIECQIBATCBkzB8MQswCQYD
# VQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3Nv
# ZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAf7QqMJ7NCELAQABAAAB/jANBglg
# hkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqG
# SIb3DQEJBDEiBCACgrjXJX1rmu4TuxY7vHJHCQh2FWeA2S/l/himGOffAjCB+gYL
# KoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIBGFzN38U8ifGNH3abaE9apz68Y4bX78
# jRa2QKy3KHR5MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hp
# bmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jw
# b3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAC
# EzMAAAH+0KjCezQhCwEAAQAAAf4wIgQg8CfmaQJn6u+5JZCMryWH0UISHbNWe3y7
# p0ctc4MeMNcwDQYJKoZIhvcNAQELBQAEggIALJIpJ/FJFznjYTyUA/6dqcnzvqlW
# MdNmVWXrdXtPL1qNXO/e3eshQXRvrXHdkLmvm171S/OFdv2wm9OwvPMwW+AGojUS
# GYiESIKCbRNxmzOHze0vwKR7omdNxtF9ZomWndGi8ZokiANstaZp3zRTKAhHSJvo
# vDlRxDytNM68TV/DH36TPWbvb4DifLh76BXHN14dYjKKPsSj8Z/ulGrXThS8w98q
# GxMelCMVxC/Mq2mE49Mtk6TOGkGFAebudOhDIJ4FF/4d+qfcrfeLCI2JSH5/Vz1W
# Nt0/1h04ZjOR3JmRp6IZQdJDoOsquLA63JAOS3bPkEvq4DPxPnyYROj+x++H1Hon
# WBvk5oWfn/MbBIHjVvUZIuO62h9W18x7SZEfHh4goBox67wWikLnHzgmZbzVzZcB
# friaXaNluWaZEdpz/pV/wIJ7E8DOJAuDDW0loZHauEG5MIoKsbqScORB5cIusUbE
# RIb0CsraFLlvnzkULJ5BXf1vHf+34SG2JICCIawN8laAJ5vSMK34ysj5a/rz+mxq
# RJoKwpNyC9LCFpKaU0+kZhQxjOvtRTfqgoNH+NMe5zMYXOShCBcHFMXOeQF2tpGM
# zlauEw9UyjPGedKwbKC0mo+QsxRf9AFFThuU1D3iYg3sHNCY7SewDfov8VsPGgBi
# jmDZpMx8bsW064U=
# SIG # End signature block
