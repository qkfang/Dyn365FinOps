<#
.SYNOPSIS
    Import this module to get functions to handle file uploads to the asset library.
    
.DESCRIPTION
    This script can be imported to enable cmdlets to create a file asset, upload to blob storage,
    and commit the file asset to the asset library.

.NOTES
    This library depends on the MSAL module "MSAL.PS". 

    Copyright © 2018 Microsoft. All rights reserved.
#>

<#
.SYNOPSIS
    Authenticates with MSAL based on UserName/Password, and returns the Authorization Header
#>
function Get-MSALAuthHeader
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory registered client application id")]
        [string]$ClientId,
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory username, e.g. bob@foo.bar")]
        [string]$UserName,
        [Parameter(Mandatory=$true, HelpMessage="Password of the user (secure string)")]
        [securestring]$Password,
        [Parameter(Mandatory=$false, HelpMessage="Auth provider URL")]
        [string]$AuthProviderUri = "https://login.microsoftonline.com/organizations",
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com",
        [Parameter(Mandatory=$false, HelpMessage="Optional reference variable for token expiration date")]
        [ref]$ExpirationData
    )

    try
    {
        #Assume module is installed by installMSALModule task
        Import-Module MSAL.PS
        
        try
        {
            Import-Module $PSScriptRoot\LogToTelemetry.ps1
            LogCustomEventToTelemetry -AuthenticationMechanism "Preview/Public Marketplace using MSAL" -ClientId $ClientId
        }
        catch
        {
            Write-Host "Error logging ClientID to telemetry"
            Write-Host -Foreground Red -Background Black ($_)
        }

        Write-Host "MSAL Authentication"
        $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $UserName, $Password
        $scopeArray = @("$LCSAPI/user_impersonation")
        $accessToken = Get-MsalToken -UserCredential $Credential -ClientId $ClientId -Scopes $scopeArray -Authority $AuthProviderUri
        if ($ExpirationData)
        {
            $ExpirationData.Value = $accessToken.ExpiresOn
        }
        $header = $accessToken.AccessToken
    }
    catch
    {
        throw $_.Exception
    }
    return "Bearer $header"
}

function Get-MSALAuthHeader-New
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory registered client application id")]
        [string]$ClientId,
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory username, e.g. bob@foo.bar")]
        [string]$UserName,
        [Parameter(Mandatory=$true, HelpMessage="Password of the user (secure string)")]
        [securestring]$Password,
        [Parameter(Mandatory=$false, HelpMessage="Auth provider URL")]
        [string]$AuthProviderUri = "https://login.microsoftonline.com/organizations",
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com",
        [Parameter(Mandatory=$false, HelpMessage="Optional reference variable for token expiration date")]
        [ref]$ExpirationData
    )

    try
    {
        $res = Get-MSALAuthHeader2 -ClientId $clientId -UserName $UserName -Password $Password -AuthProviderUri $AuthProviderUri -LCSAPI $LCSAPI -ExpirationData ([ref]$ExpirationData)
        Write-Host "Parsed token type $($res.GetType())"
        $matchingObject = $res | Where-Object { $_ -is [string] -and $_ -like 'Bearer *' }
        if($matchingObject.Count -gt 1)
        {
            Write-Host "Multiple entries"
            return $matchingObject[0]
        }
        else {
            return $matchingObject
        }
    }
    catch {
        throw $_.Exception
    }
}

<#
.SYNOPSIS
    Authenticates with MSAL based on UserName/Password, and returns the Authorization Header
#>
function Get-MSALAuthHeader2
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory registered client application id")]
        [string]$ClientId,
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory username, e.g. bob@foo.bar")]
        [string]$UserName,
        [Parameter(Mandatory=$true, HelpMessage="Password of the user (secure string)")]
        [securestring]$Password,
        [Parameter(Mandatory=$false, HelpMessage="Auth provider URL")]
        [string]$AuthProviderUri = "https://login.microsoftonline.com/organizations",
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com",
        [Parameter(Mandatory=$false, HelpMessage="Optional reference variable for token expiration date")]
        [ref]$ExpirationData
    )
    try
    {
        Write-Host "MSAL Authentication against AAD authority $($AuthProviderUri)"
        [string[]] $scopeValue = "$LCSAPI/user_impersonation"
        try
        {   
            Write-Host $PSScriptRoot
            Install-Module -Name PowerShellGet -Force -Scope CurrentUser -AllowClobber
            Install-Package -Name "Microsoft.IdentityModel.Abstractions" -Confirm:$False -Force -Destination "$PSScriptRoot\packages" -RequiredVersion 6.22.0 -Source @("https://www.nuget.org/api/v2")
            Install-Package -Name "Microsoft.Identity.Client" -Confirm:$False -Force -Destination "$PSScriptRoot\packages" -RequiredVersion 4.58.0 -Source @("https://www.nuget.org/api/v2") -SkipDependencies
            Install-Package -Name "System.Memory" -Confirm:$False -Force -Destination "$PSScriptRoot\packages" -RequiredVersion 4.5.5 -Source @("https://www.nuget.org/api/v2") -SkipDependencies
            Install-Package -Name "System.Diagnostics.DiagnosticSource" -Confirm:$False -Force -Destination "$PSScriptRoot\packages" -RequiredVersion 7.0.2 -Source @("https://www.nuget.org/api/v2") -SkipDependencies

            $identity = Get-ChildItem "$PSScriptRoot\packages\*\*\net462\Microsoft.Identity.Client.dll" | % { $_.FullName }
            Write-Host (Get-Item $identity).Name
            $abstractions = Get-ChildItem "$PSScriptRoot\packages\*\*\net461\Microsoft.IdentityModel.Abstractions.dll"  -Recurse | % { $_.FullName }
            Write-Host (Get-Item $abstractions).Name
            $memory = Get-ChildItem "$PSScriptRoot\packages\*\*\net461\System.Memory.dll"  -Recurse | % { $_.FullName }
            Write-Host (Get-Item $memory).Name
            $diagSource = Get-ChildItem "$PSScriptRoot\packages\*\*\net462\System.Diagnostics.DiagnosticSource.dll"  -Recurse | % { $_.FullName }
            Write-Host (Get-Item $diagSource).Name
            Add-Type -Path $abstractions
            Add-Type -Path $identity
            Add-Type -Path $memory
            Add-Type -Path $diagSource
        }
        catch
        {
            Write-Host $_.Exception
            Write-Host $_.Exception.LoaderExceptions
            Write-Host $_.Exception.InnerException
        }

        $ClientApplicationBuilder = [Microsoft.Identity.Client.PublicClientApplicationBuilder]::Create($ClientId)
        $ClientApplicationBuilder.WithClientId($ClientId).WithAuthority($AuthProviderUri, $true).WithClientName("PowerShell $($PSVersionTable.PSEdition)").WithClientVersion($PSVersionTable.PSVersion)
        $pca = $ClientApplicationBuilder.Build()
        Write-Host "Fetching token from application"
        $secureStringPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
        
        $tokenParams = $pca.AcquireTokenByUsernamePassword($scopeValue, $UserName, [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($secureStringPtr))
        # Clear the memory occupied by the SecureString representation
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secureStringPtr)

        $tokenSource = New-Object System.Threading.CancellationTokenSource
        try 
        {
            $authResult = $tokenParams.ExecuteAsync($tokenSource.Token)
            try {
                $waitTime = 0
                while (!$authResult.IsCompleted) {
                    if ($waitTime -lt 300) {
                        Start-Sleep -Seconds 1
                        $waitTime++
                    }
                    else {
                        $tokenSource.Cancel()
                        try { $authResult.Wait() }
                        catch { }
                        Write-Error -Exception (New-Object System.TimeoutException) -Category ([System.Management.Automation.ErrorCategory]::OperationTimeout) -CategoryActivity $MyInvocation.MyCommand -ErrorId 'GetMsalTokenFailureOperationTimeout' -TargetObject $tokenParams -ErrorAction Stop
                    }
                }
            }
            finally {
                if (!$authResult.IsCompleted) {
                    Write-Debug ('Cancelled acquiring token. ClientId [{0}]' -f $ClientApplication.ClientId)
                    $tokenSource.Cancel()
                }
                $tokenSource.Dispose()
            }
            Write-Host "Fetched Result"
            Write-Host $authResult
            ## Parse task results
            if ($authResult.IsFaulted) {
                Write-Error -Exception $authResult.Exception -Category ([System.Management.Automation.ErrorCategory]::AuthenticationError) -CategoryActivity $MyInvocation.MyCommand -ErrorId 'GetMsalTokenFailureAuthenticationError' -TargetObject $tokenParams -ErrorAction Stop
            }
            if ($authResult.IsCanceled) {
                Write-Error -Exception (New-Object System.Threading.Tasks.TaskCanceledException $authResult) -Category ([System.Management.Automation.ErrorCategory]::OperationStopped) -CategoryActivity $MyInvocation.MyCommand -ErrorId 'GetMsalTokenFailureOperationStopped' -TargetObject $tokenParams -ErrorAction Stop
            }
            else {
                $tokenResult = $authResult.Result
                Write-Host "Region"
                Write-Host $authResult.Result.AuthenticationResultMetadata.RegionDetails.RegionOutcome
                Write-Host $authResult.Result.AuthenticationResultMetadata.RegionDetails.RegionUsed
                Write-Host $authResult.Result.AuthenticationResultMetadata.RegionDetails.AutoDetectionError
                Write-Host $authResult.Result.AuthenticationResultMetadata.TokenEndpoint
            }
        }
        catch {
            Write-Host $_.Exception.InnerException 
            Write-Host $_.Exception
        }    
            
        if ($ExpirationData)
        {
            $ExpirationData.Value = $tokenResult.ExpiresOn
        }
        
        $send = "Bearer " + $tokenResult.AccessToken
        Write-Host "Token type $($send.GetType())"
        return $send
    }
    catch
    {
        throw $_.Exception
    }
}
# SIG # Begin signature block
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC1+6igGI1yXCpz
# h5uWYkF1+tc8nCRZgOr9fzDs9v1jtaCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# II+qmXJtvRTH8AtRZELsXMU1WgXVR/rgAhfUG6Cq6MSfMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAYe+VkBRitcM95GmGWwaf/MFcHP1pz2EY
# Y1hJAhdYjrqh/+5v5x/Fw9ESUEbm87N9ui3j03BTh4N1csYZItkO7im1D29EOBe6
# lbykTX0/nsZ/NZiXedXrEALuk5lQpILao8n6QlPYGWMIzp5PY4WYQmk4ZvEeYRRe
# Vce+18iY0rYdocg/4bT+hJ8sercGHEdgBXxmiFreJRkOVeTjos0pwePJgkg5iKnD
# fiF/Bi0ETbGVLIxlCys/xIYdYpOYZIgqjqM8m9r1zVOic0wGpsC6z5arPbLrzCvw
# XN+rUS+mAVnid+RXb4Kj23GHkEUzlxs4D6dDPwHVSjX3+AzM7ZcrCqGCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAcgOLKFhkCEjUs2AybuEXtyumxt+yr
# vP/AHFndrNHMFwIGZ+0t1redGBMyMDI1MDQxODAwMTk1MS41NzhaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjoyQTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB
# +R9njXWrpPGxAAEAAAH5MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzEwOVoXDTI1MTAyMjE4MzEwOVowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjJBMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAtD1MH3yAHWHNVslC+CBTj/Mpd55LDPtQrhN7WeqFhReC9xKXSjobW1ZHzHU8
# V2BOJUiYg7fDJ2AxGVGyovUtgGZg2+GauFKk3ZjjsLSsqehYIsUQrgX+r/VATaW8
# /ONWy6lOyGZwZpxfV2EX4qAh6mb2hadAuvdbRl1QK1tfBlR3fdeCBQG+ybz9JFZ4
# 5LN2ps8Nc1xr41N8Qi3KVJLYX0ibEbAkksR4bbszCzvY+vdSrjWyKAjR6YgYhaBa
# DxE2KDJ2sQRFFF/egCxKgogdF3VIJoCE/Wuy9MuEgypea1Hei7lFGvdLQZH5Jo2Q
# R5uN8hiMc8Z47RRJuIWCOeyIJ1YnRiiibpUZ72+wpv8LTov0yH6C5HR/D8+AT4vq
# tP57ITXsD9DPOob8tjtsefPcQJebUNiqyfyTL5j5/J+2d+GPCcXEYoeWZ+nrsZSf
# rd5DHM4ovCmD3lifgYnzjOry4ghQT/cvmdHwFr6yJGphW/HG8GQd+cB4w7wGpOhH
# VJby44kGVK8MzY9s32Dy1THnJg8p7y1sEGz/A1y84Zt6gIsITYaccHhBKp4cOVNr
# foRVUx2G/0Tr7Dk3fpCU8u+5olqPPwKgZs57jl+lOrRVsX1AYEmAnyCyGrqRAzpG
# Xyk1HvNIBpSNNuTBQk7FBvu+Ypi6A7S2V2Tj6lzYWVBvuGECAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBSJ7aO6nJXJI9eijzS5QkR2RlngADAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEAZiAJgFbkf7jfhx/mmZlnGZrpae+HGpxWxs8I79vUb8GQou50M1ns
# 7iwG2CcdoXaq7VgpVkNf1uvIhrGYpKCBXQ+SaJ2O0BvwuJR7UsgTaKN0j/yf3fpH
# D0ktH+EkEuGXs9DBLyt71iutVkwow9iQmSk4oIK8S8ArNGpSOzeuu9TdJjBjsasm
# uJ+2q5TjmrgEKyPe3TApAio8cdw/b1cBAmjtI7tpNYV5PyRI3K1NhuDgfEj5kynG
# F/uizP1NuHSxF/V1ks/2tCEoriicM4k1PJTTA0TCjNbkpmBcsAMlxTzBnWsqnBCt
# 9d+Ud9Va3Iw9Bs4ccrkgBjLtg3vYGYar615ofYtU+dup+LuU0d2wBDEG1nhSWHaO
# +u2y6Si3AaNINt/pOMKU6l4AW0uDWUH39OHH3EqFHtTssZXaDOjtyRgbqMGmkf8K
# I3qIVBZJ2XQpnhEuRbh+AgpmRn/a410Dk7VtPg2uC422WLC8H8IVk/FeoiSS4vFo
# dhncFetJ0ZK36wxAa3FiPgBebRWyVtZ763qDDzxDb0mB6HL9HEfTbN+4oHCkZa1H
# Kl8B0s8RiFBMf/W7+O7EPZ+wMH8wdkjZ7SbsddtdRgRARqR8IFPWurQ+sn7ftEif
# aojzuCEahSAcq86yjwQeTPN9YG9b34RTurnkpD+wPGTB1WccMpsLlM0wggdxMIIF
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
# BAsTHm5TaGllbGQgVFNTIEVTTjoyQTFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAqs5WjWO7
# zVAKmIcdwhqgZvyp6UaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOurccswIhgPMjAyNTA0MTcxMjI1NDdaGA8y
# MDI1MDQxODEyMjU0N1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA66txywIBADAK
# AgEAAgIIBQIB/zAHAgEAAgISgzAKAgUA66zDSwIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBCwUAA4IBAQA2IaLxL4hQ/wLCMKQCGbBN2GPvaQZqecZxQBYFp5s9EaBxzRk0
# ZzTc5ele1+5d49GHxpTYkc3AKluMUxNplgQmnTpxYp8T5buL4oPOCy/w+oT7QDJF
# flKodcHBkcXoWEte/JRZfY2KgJWAG+FY1VanaXgaDAQHNILVz6xO/YAC+p6nfQbE
# Vq42kQgzdDQnjBTZZG9vSnkmGPY9GL6mrBjJ2Oygf3lQdtpu7tv73EIn4htXlLFW
# Q0oi7fn5qGtfzWuwlNOUx1YpGiQbGM3Yc9gdo7RVMCaivTy/+4nk4dFLDzl5Xam3
# KBvb+Zw+VJl5mtl3qp44qZftCManZE1vLCtaMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH5H2eNdauk8bEAAQAAAfkwDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQgKO3SDm9aTv09lADxkLbwypeG+lFEWprXTSDcI4fFs7UwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCA5I4zIHvCN+2T66RUOLCZrUEVdoKlK
# l8VeCO5SbGLYEDCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB+R9njXWrpPGxAAEAAAH5MCIEIORegTTHJ6SkjcGDiWLfOSnjX6peh8SC
# PPUJ+WYdhiDYMA0GCSqGSIb3DQEBCwUABIICAFMhij1yrT/00zJHk5mJmU8ojEcl
# obMbieJBXtuERUMgslgRwol3gkwns7kv/oEDlg1RQuOUbeMMFljwRcNV3XIdhtZE
# E9NssDxRkZrmUG+zXPGSkE8fsgZKDEWwQc9voCW5ZelLVBG1XLpMlNNvVMh1NAiP
# 4d/8C6bP40vVLdIRTe7GvdykCJaZgFlWoo26469/iRf+99sBW8o0VzC6WZwscXx/
# D3uXXuqx+e8bOvGgXPb3avjZhj1NU61QEN+ArmOa+00qvT9vSeeNO1KtY+Op848k
# /HswXLFAsacfPjewOWpIN0TYshWv5Ukun+Hv70qrNuq0xcGtFeCKbcT8tVR20r4g
# /dftn7F/V0BZ6hd9xnCskc3WtMZusHGNwMXOtZlb/3W8nuWAdsZ/u38hbn8wlJxI
# KSZb1XYdXMMow/tEc8swzWVUbFAmPyP4PG2TLS8f7NfvhV3cvffoX2M7IlKMsMxN
# nbaaP+IUIDPKnoOD1NtAOVsjZOF9LS3ZlDJDQNLkKFVUzMGmGT7xKkjNwvDQfpkT
# QfnbWDGz39La3jl8fem3LZm0tp8hYy4JIAO/FNOSbT6CvPzDK+QvToIBfQaaFzem
# 9232FzBGbemSP++DiRsJ+HY3txw9OCtM+OvDHfPAraPOT+hqzwJLc06vAE5GQAqr
# u5bePQf6NZ3MLJUZ
# SIG # End signature block
