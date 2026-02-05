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
function Get-MSALAuthHeaderOld
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
        try
        {
            Import-Module $PSScriptRoot\LogToTelemetry.ps1
            LogCustomEventToTelemetry -AuthenticationMechanism "Preview/Public Marketplace using MSAL library" -ClientId $ClientId
        }
        catch
        {
            Write-Host "Error logging ClientID to telemetry"
            Write-Host -Foreground Red -Background Black ($_)
        }
        if ($ExpirationData)
        {
            $res = Get-MSALAuthHeader2 -ClientId $ClientId -UserName $UserName -Password $Password -AuthProviderUri $AuthProviderUri -LCSAPI $LCSAPI -ExpirationData $ExpirationData
        }
        else {
            $res = Get-MSALAuthHeader2 -ClientId $ClientId -UserName $UserName -Password $Password -AuthProviderUri $AuthProviderUri -LCSAPI $LCSAPI
        }
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
            if (Get-Module -ListAvailable -Name 'PowerShellGet') {
                Write-Host "PowerShellGet Module exists"
                Import-Module PowerShellGet
            }
            else {
                Install-Module -Name PowerShellGet -Force -Scope CurrentUser -AllowClobber
                Import-Module PowerShellGet
            }
            Install-Package -Name "Microsoft.IdentityModel.Abstractions" -Confirm:$False -Force -Destination "$PSScriptRoot\packages" -RequiredVersion 6.35.0 -Source @("https://www.nuget.org/api/v2")
            Install-Package -Name "Microsoft.Identity.Client" -Confirm:$False -Force -Destination "$PSScriptRoot\packages" -RequiredVersion 4.60.4 -Source @("https://www.nuget.org/api/v2") -SkipDependencies
            Install-Package -Name "System.Memory" -Confirm:$False -Force -Destination "$PSScriptRoot\packages" -RequiredVersion 4.5.5 -Source @("https://www.nuget.org/api/v2") -SkipDependencies
            Install-Package -Name "System.Diagnostics.DiagnosticSource" -Confirm:$False -Force -Destination "$PSScriptRoot\packages" -RequiredVersion 7.0.2 -Source @("https://www.nuget.org/api/v2") -SkipDependencies

            $identity = Get-ChildItem "$PSScriptRoot\packages\*\*\net462\Microsoft.Identity.Client.dll" | % { $_.FullName }
            $abstractions = Get-ChildItem "$PSScriptRoot\packages\*\*\net461\Microsoft.IdentityModel.Abstractions.dll"  -Recurse | % { $_.FullName }
            $memory = Get-ChildItem "$PSScriptRoot\packages\*\*\net461\System.Memory.dll"  -Recurse | % { $_.FullName }
            $diagSource = Get-ChildItem "$PSScriptRoot\packages\*\*\net462\System.Diagnostics.DiagnosticSource.dll"  -Recurse | % { $_.FullName }
            Add-Type -Path $abstractions
            Add-Type -Path $identity
            Add-Type -Path $memory
            Add-Type -Path $diagSource
            Write-Host "Required libraries loaded"
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
        
        $AquireTokenParameters = $pca.AcquireTokenByUsernamePassword($scopeValue, $UserName, [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($secureStringPtr))
        # Clear the memory occupied by the SecureString representation
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secureStringPtr)

        $tokenSource = New-Object System.Threading.CancellationTokenSource
        try 
        {
            $taskAuthenticationResult = $AquireTokenParameters.ExecuteAsync($tokenSource.Token)
            if (!$Timeout) { $Timeout = [timespan]::Zero }
            try {
                $endTime = [datetime]::Now.Add($Timeout)
                while (!$taskAuthenticationResult.IsCompleted) {
                    if ($Timeout -eq [timespan]::Zero -or [datetime]::Now -lt $endTime) {
                        Start-Sleep -Seconds 1
                    }
                    else {
                        $tokenSource.Cancel()
                        try { $taskAuthenticationResult.Wait() }
                        catch { }
                        Write-Error -Exception (New-Object System.TimeoutException) -Category ([System.Management.Automation.ErrorCategory]::OperationTimeout) -CategoryActivity $MyInvocation.MyCommand -ErrorId 'GetMsalTokenFailureOperationTimeout' -TargetObject $AquireTokenParameters -ErrorAction Stop
                    }
                }
            }
            finally {
                if (!$taskAuthenticationResult.IsCompleted) {
                    Write-Debug ('Canceling Token Acquisition for Application with ClientId [{0}]' -f $ClientApplication.ClientId)
                    $tokenSource.Cancel()
                }
                $tokenSource.Dispose()
            }
            Write-Host "Fetched Result"
            ## Parse task results
            if ($taskAuthenticationResult.IsFaulted) {
                Write-Error -Exception $taskAuthenticationResult.Exception -Category ([System.Management.Automation.ErrorCategory]::AuthenticationError) -CategoryActivity $MyInvocation.MyCommand -ErrorId 'GetMsalTokenFailureAuthenticationError' -TargetObject $AquireTokenParameters -ErrorAction Stop
            }
            if ($taskAuthenticationResult.IsCanceled) {
                Write-Error -Exception (New-Object System.Threading.Tasks.TaskCanceledException $taskAuthenticationResult) -Category ([System.Management.Automation.ErrorCategory]::OperationStopped) -CategoryActivity $MyInvocation.MyCommand -ErrorId 'GetMsalTokenFailureOperationStopped' -TargetObject $AquireTokenParameters -ErrorAction Stop
            }
            else {
                $tokenResult = $taskAuthenticationResult.Result
                Write-Host "Region"
                Write-Host $taskAuthenticationResult.Result.AuthenticationResultMetadata.RegionDetails.RegionOutcome
                Write-Host $taskAuthenticationResult.Result.AuthenticationResultMetadata.RegionDetails.RegionUsed
                Write-Host $taskAuthenticationResult.Result.AuthenticationResultMetadata.RegionDetails.AutoDetectionError
                Write-Host $taskAuthenticationResult.Result.AuthenticationResultMetadata.TokenEndpoint
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
# MIIoDAYJKoZIhvcNAQcCoIIn/TCCJ/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCC4OQ18/xx0XXJY
# P6iD2klQHVePVn8cIYvdJ5PSKXfqB6CCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# /Xmfwb1tbWrJUnMTDXpQzTGCGewwghnoAgEBMIGVMH4xCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01pY3Jvc29mdCBDb2RlIFNp
# Z25pbmcgUENBIDIwMTECEzMAAAQEbHQG/1crJ3IAAAAABAQwDQYJYIZIAWUDBAIB
# BQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQwLwYJKoZIhvcNAQkEMSIE
# ILf5uwoneJFHVR5T3ZJb+EqZNkPo7J9StjuWa+CydJBNMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAK5g/Xw2fS7wdr8p338c+MoXNAFIZJPKr
# OzbOR1hz0ZXRdwhN9c2MUA2VKWfMQi1J9dG322RY6moxmQleaU9YqJ8OoYV8mHQA
# rqNbr6B+QOwu9ocWRaVVFM0iNCQm2gGgUOhFz0QgnDcGeJ8h3akxO5pmv/oX21gV
# QJc0QCpAo+FvohGHEkj0eFW7JnMoaFAJaopkiG0XXGSy1qTYGKgUilKqj6+sa+/J
# NhYt8An2aSD0tVnKvjsXXXTDBkwHF1m7Af8LNFNrePBkAE2z4dQo2+c0c5dL6KZV
# HRZK7mRTxWBepIHFWCupo+fbRqEdZgDIicsLq+x3CfQVsMbotzSklqGCF5QwgheQ
# BgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDE8Yxo15cCc/N3HKElzGSjXPOi89Rb
# gvZHmsljWohP7QIGZ/fVkqGIGBMyMDI1MDQxODAwMjAxOC42MzlaMASAAgH0oIHR
# pIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046QTAwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAgh4nVhdksfZ
# UgABAAACCDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yNTAxMzAxOTQyNTNaFw0yNjA0MjIxOTQyNTNaMIHLMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQg
# QW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTAw
# MC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC1y3AI5lIz3Ip1nK5B
# MUUbGRsjSnCz/VGs33zvY0NeshsPgfld3/Z3/3dS8WKBLlDlosmXJOZlFSiNXUd6
# DTJxA9ik/ZbCdWJ78LKjbN3tFkX2c6RRpRMpA8sq/oBbRryP3c8Q/gxpJAKHHz8c
# uSn7ewfCLznNmxqliTk3Q5LHqz2PjeYKD/dbKMBT2TAAWAvum4z/HXIJ6tFdGoNV
# 4WURZswCSt6ROwaqQ1oAYGvEndH+DXZq1+bHsgvcPNCdTSIpWobQiJS/UKLiR02K
# NCqB4I9yajFTSlnMIEMz/Ni538oGI64phcvNpUe2+qaKWHZ8d4T1KghvRmSSF4YF
# 5DNEJbxaCUwsy7nULmsFnTaOjVOoTFWWfWXvBuOKkBcQKWGKvrki976j4x+5ezAP
# 36fq3u6dHRJTLZAu4dEuOooU3+kMZr+RBYWjTHQCKV+yZ1ST0eGkbHXoA2lyyRDl
# NjBQcoeZIxWCZts/d3+nf1jiSLN6f6wdHaUz0ADwOTQ/aEo1IC85eFePvyIKaxFJ
# kGU2Mqa6Xzq3qCq5tokIHtjhogsrEgfDKTeFXTtdhl1IPtLcCfMcWOGGAXosVUU7
# G948F6W96424f2VHD8L3FoyAI9+r4zyIQUmqiESzuQWeWpTTjFYwCmgXaGOuSDV8
# cNOVQB6IPzPneZhVTjwxbAZlaQIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFKMx4vfO
# qcUTgYOVB9f18/mhegFNMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNy
# bDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQBRszKJKwAf
# swqdaQPFiaYB/ZNAYWDa040XTcQsCaCua5nsG1IslYaSpH7miTLr6eQEqXczZoqe
# Oa/xvDnMGifGNda0CHbQwtpnIhsutrKO2jhjEaGwlJgOMql21r7Ik6XnBza0e3hB
# Ou4UBkMl/LEX+AURt7i7+RTNsGN0cXPwPSbTFE+9z7WagGbY9pwUo/NxkGJseqGC
# Q/9K2VMU74bw5e7+8IGUhM2xspJPqnSeHPhYmcB0WclOxcVIfj/ZuQvworPbTEEY
# DVCzSN37c0yChPMY7FJ+HGFBNJxwd5lKIr7GYfq8a0gOiC2ljGYlc4rt4cCed1XK
# g83f0l9aUVimWBYXtfNebhpfr6Lc3jD8NgsrDhzt0WgnIdnTZCi7jxjsIBilH99p
# Y5/h6bQcLKK/E6KCP9E1YN78fLaOXkXMyO6xLrvQZ+uCSi1hdTufFC7oSB/CU5Rb
# fIVHXG0j1o2n1tne4eCbNfKqUPTE31tNbWBR23Yiy0r3kQmHeYE1GLbL4pwknqai
# p1BRn6WIUMJtgncawEN33f8AYGZ4a3NnHopzGVV6neffGVag4Tduy+oy1YF+shCh
# oXdMqfhPWFpHe3uJGT4GJEiNs4+28a/wHUuF+aRaR0cN5P7XlOwU1360iUCJtQdv
# KQaNAwGI29KOwS3QGriR9F2jOGPUAlpeEzCCB3EwggVZoAMCAQICEzMAAAAVxedr
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
# cQZqELQdVTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSBzjCByzELMAkGA1UEBhMC
# VVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNV
# BAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFt
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkEwMDAt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQCNkvu0NKcSjdYKyrhJZcsyXOUTNKCBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA66uN
# 5jAiGA8yMDI1MDQxNzE0MjU0MloYDzIwMjUwNDE4MTQyNTQyWjB0MDoGCisGAQQB
# hFkKBAExLDAqMAoCBQDrq43mAgEAMAcCAQACAgI8MAcCAQACAhJXMAoCBQDrrN9m
# AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSCh
# CjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAJLsymUGIuS5rSOQb8EEmJr4
# osxmFbqSiG6JkjEipasAgz0pMChFvHo5WXdJeXkJs4dovfgeAPJQuXdWeGkEZB/K
# KCZiuiM+uE78ednQFJ4rRmd6sSN3TTN0TBL1F6KaNo1QxDm/ojPbkfuxb9+hju6p
# hmwJmQ48bxaGfJ/O1EW1q50g61bVcNCS0YPZArXF5xdzDQGufoQO0zVAK3qNbCPX
# 38wfhVtu/PF0u6xShLF6KA3eZB/6I1ZDGSPnxwkO+ZPOvefIc91RlFHN2TXIh8du
# LjGgqmJNY7hAy1T0OI7G1cC4PcxBkfbh4XU0ii41yEKuZN2ZS6i3J906epjjHBwx
# ggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# Agh4nVhdksfZUgABAAACCDANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCD02F+lYzzqG0lipKRl+gsy
# qb9GXxDr9puRt6IuOjSTSDCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EII//
# jm8JHa2W1O9778t9+Ft2Z5NmKqttPk6Q+9RRpmepMIGYMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIIeJ1YXZLH2VIAAQAAAggwIgQg4TnI
# KP+IV/R8in9i4lsy3mMQAxN6dnWjyETrR7GyAi0wDQYJKoZIhvcNAQELBQAEggIA
# ofq1XDcELgfVxHbSp//4P9IfDhbWcH4G/+kCeedCker58qNwqritL//wN4bF4pKO
# M+Wdj+p/ks9tVnjv2OGaNgKBwPshuZEiQhg82WXv06PnVdNaHL+hc+bBtK6la+oC
# ejsVbBHhWBszAeLyYoobni8v9tDGSSTSmBXqsKZcViF373barocoBQXX2T1Fosly
# 3icNXy+kGCHTvjMdUSHMA8SIGDmnQ2PdVy6kd+VeG2IrHCgjXSEMbwQ6SRxw8gMY
# 2/Ut9iThYoyQOwuK/jQMIFfWU0HSQWy1P+u4OIXy1i3HvSXSgsfRuirHsX8LEAmf
# mgqugxtElwhXGOHAx2Qly3/dofISvxk+cRCZZFGM60bdOgP/weQA1Rp+apSMSNAm
# K/M9yZ6NxM1D8bHBNFyboq3wv6ryhGU1ziMkxVfqWPkI6Bq3JB+5mfay015C7ynB
# AlS/weuqeVSAJpqjF1uoo3cqCrVhhKF37t9QmsipbxSwwWNxFSkG7t9yIwFzWtIM
# ecG/sBwUUjNnHpjwa12geizL9Zouk2juAs2WNMoz3R/s9BcybfuIe3ZruWLsQExe
# J50VztqbVGDY6CRgq7XqauqN1n+zs/y2x2yCtdvRLeAdwH+i7VNqgVoWrkfFfODy
# oza/vEwOqd64EoPdCtetWZ2u4HvVhCfoNnUXPEwxRjo=
# SIG # End signature block
