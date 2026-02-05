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
function Deploy-CommerceScaleUnit
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
# MIIoNwYJKoZIhvcNAQcCoIIoKDCCKCQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDzpcTf1WW87Xeg
# Ep8G+8sV/EHzt3fgFBuwOIJF5+nh1qCCDYUwggYDMIID66ADAgECAhMzAAAEA73V
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGggwghoEAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAQDvdWVXQ87GK0AAAAA
# BAMwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# LwYJKoZIhvcNAQkEMSIEIINmiz+LNVr3oZ7mKRoNvN48A0Sn9/Jm4ZWfU03JkW6T
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEANwiYWGugfqKS
# Fx2gzkrgue6yAp7Zsghq1g7MltIDAKPwZS2e/Vc0YzHmdD9qN3wjFejtY2clzPGo
# 1cWWUoishctK2JgjWs96ME9xcgOD5h+F4psnOikn7EIxJwlXJWKFGFGuTh6NXAg0
# 9FRc1KxTBUo1iiKRS0yi71EelOnVuscPPpaLDbW59gaVUw06G2eyFs1qogClwMji
# OFwRJ6UAok4l5aUPXeIwCEXtBdFHuzMnGfaay92rf1PjX86hPaV4y1cGFXFOkCk0
# bfIAiu3A08W/HK2iZupjl61FexUxoxmUoiA2WeVblTktMdnfpdjeBE1WwC1rXB1b
# 43A5pABrPKGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCC
# F4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkE
# ggFFMIIBQQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCB7JtQ2Xb41
# 5aVv7xYsFN2DSMQUyrJ1YrXMu8olEpDOFwIGZ+0tnM9IGBMyMDI1MDQxODAwMjAx
# Ny4xMzhaMASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25z
# IExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0
# NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggco
# MIIFEKADAgECAhMzAAAB+vs7RNN3M8bTAAEAAAH6MA0GCSqGSIb3DQEBCwUAMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzExMVoXDTI1
# MTAyMjE4MzExMVowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjQzMUEtMDVFMC1EOTQ3MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAyhZVBM3PZcBfEpAf7fIIhygwYVVP64USeZbSlRR3
# pvJebva0LQCDW45yOrtpwIpGyDGX+EbCbHhS5Td4J0Ylc83ztLEbbQD7M6kqR0Xj
# +n82cGse/QnMH0WRZLnwggJdenpQ6UciM4nMYZvdQjybA4qejOe9Y073JlXv3VIb
# dkQH2JGyT8oB/LsvPL/kAnJ45oQIp7Sx57RPQ/0O6qayJ2SJrwcjA8auMdAnZKOi
# xFlzoooh7SyycI7BENHTpkVKrRV5YelRvWNTg1pH4EC2KO2bxsBN23btMeTvZFie
# GIr+D8mf1lQQs0Ht/tMOVdah14t7Yk+xl5P4Tw3xfAGgHsvsa6ugrxwmKTTX1kqX
# H5XCdw3TVeKCax6JV+ygM5i1NroJKwBCW11Pwi0z/ki90ZeO6XfEE9mCnJm76Qcx
# i3tnW/Y/3ZumKQ6X/iVIJo7Lk0Z/pATRwAINqwdvzpdtX2hOJib4GR8is2bpKks0
# 4GurfweWPn9z6jY7GBC+js8pSwGewrffwgAbNKm82ZDFvqBGQQVJwIHSXpjkS+G3
# 9eyYOG2rcILBIDlzUzMFFJbNh5tDv3GeJ3EKvC4vNSAxtGfaG/mQhK43YjevsB72
# LouU78rxtNhuMXSzaHq5fFiG3zcsYHaa4+w+YmMrhTEzD4SAish35BjoXP1P1Ct4
# Va0CAwEAAaOCAUkwggFFMB0GA1UdDgQWBBRjjHKbL5WV6kd06KocQHphK9U/vzAf
# BgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQ
# hk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQl
# MjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBe
# MFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2Nl
# cnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAM
# BgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQE
# AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAuFbCorFrvodG+ZNJH3Y+Nz5QpUytQVOb
# OyYFrgcGrxq6MUa4yLmxN4xWdL1kygaW5BOZ3xBlPY7Vpuf5b5eaXP7qRq61xeOr
# X3f64kGiSWoRi9EJawJWCzJfUQRThDL4zxI2pYc1wnPp7Q695bHqwZ02eaOBudh/
# IfEkGe0Ofj6IS3oyZsJP1yatcm4kBqIH6db1+weM4q46NhAfAf070zF6F+IpUHyh
# tMbQg5+QHfOuyBzrt67CiMJSKcJ3nMVyfNlnv6yvttYzLK3wS+0QwJUibLYJMI6F
# GcSuRxKlq6RjOhK9L3QOjh0VCM11rHM11ZmN0euJbbBCVfQEufOLNkG88MFCUNE1
# 0SSbM/Og/CbTko0M5wbVvQJ6CqLKjtHSoeoAGPeeX24f5cPYyTcKlbM6LoUdO2P5
# JSdI5s1JF/On6LiUT50adpRstZajbYEeX/N7RvSbkn0djD3BvT2Of3Wf9gIeaQIH
# bv1J2O/P5QOPQiVo8+0AKm6M0TKOduihhKxAt/6Yyk17Fv3RIdjT6wiL2qRIEsgO
# Jp3fILw4mQRPu3spRfakSoQe5N0e4HWFf8WW2ZL0+c83Qzh3VtEPI6Y2e2BO/eWh
# TYbIbHpqYDfAtAYtaYIde87ZymXG3MO2wUjhL9HvSQzjoquq+OoUmvfBUcB2e5L6
# QCHO6qTO7WowggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqG
# SIb3DQEBCwUAMIGIMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQ
# MA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9u
# MTIwMAYDVQQDEylNaWNyb3NvZnQgUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkg
# MjAxMDAeFw0yMTA5MzAxODIyMjVaFw0zMDA5MzAxODMyMjVaMHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEA5OGmTOe0ciELeaLL1yR5vQ7VgtP97pwHB9KpbE51yMo1V/YBf2xK4OK9uT4X
# YDP/XE/HZveVU3Fa4n5KWv64NmeFRiMMtY0Tz3cywBAY6GB9alKDRLemjkZrBxTz
# xXb1hlDcwUTIcVxRMTegCjhuje3XD9gmU3w5YQJ6xKr9cmmvHaus9ja+NSZk2pg7
# uhp7M62AW36MEBydUv626GIl3GoPz130/o5Tz9bshVZN7928jaTjkY+yOSxRnOlw
# aQ3KNi1wjjHINSi947SHJMPgyY9+tVSP3PoFVZhtaDuaRr3tpK56KTesy+uDRedG
# bsoy1cCGMFxPLOJiss254o2I5JasAUq7vnGpF1tnYN74kpEeHT39IM9zfUGaRnXN
# xF803RKJ1v2lIH1+/NmeRd+2ci/bfV+AutuqfjbsNkz2K26oElHovwUDo9Fzpk03
# dJQcNIIP8BDyt0cY7afomXw/TNuvXsLz1dhzPUNOwTM5TI4CvEJoLhDqhFFG4tG9
# ahhaYQFzymeiXtcodgLiMxhy16cg8ML6EgrXY28MyTZki1ugpoMhXV8wdJGUlNi5
# UPkLiWHzNgY1GIRH29wb0f2y1BzFa/ZcUlFdEtsluq9QBXpsxREdcu+N+VLEhReT
# wDwV2xo3xwgVGD94q0W29R6HXtqPnhZyacaue7e3PmriLq0CAwEAAaOCAd0wggHZ
# MBIGCSsGAQQBgjcVAQQFAgMBAAEwIwYJKwYBBAGCNxUCBBYEFCqnUv5kxJq+gpE8
# RjUpzxD/LwTuMB0GA1UdDgQWBBSfpxVdAF5iXYP05dJlpxtTNRnpcjBcBgNVHSAE
# VTBTMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5odG0wEwYDVR0lBAww
# CgYIKwYBBQUHAwgwGQYJKwYBBAGCNxQCBAweCgBTAHUAYgBDAEEwCwYDVR0PBAQD
# AgGGMA8GA1UdEwEB/wQFMAMBAf8wHwYDVR0jBBgwFoAU1fZWy4/oolxiaNE9lJBb
# 186aGMQwVgYDVR0fBE8wTTBLoEmgR4ZFaHR0cDovL2NybC5taWNyb3NvZnQuY29t
# L3BraS9jcmwvcHJvZHVjdHMvTWljUm9vQ2VyQXV0XzIwMTAtMDYtMjMuY3JsMFoG
# CCsGAQUFBwEBBE4wTDBKBggrBgEFBQcwAoY+aHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraS9jZXJ0cy9NaWNSb29DZXJBdXRfMjAxMC0wNi0yMy5jcnQwDQYJKoZI
# hvcNAQELBQADggIBAJ1VffwqreEsH2cBMSRb4Z5yS/ypb+pcFLY+TkdkeLEGk5c9
# MTO1OdfCcTY/2mRsfNB1OW27DzHkwo/7bNGhlBgi7ulmZzpTTd2YurYeeNg2Lpyp
# glYAA7AFvonoaeC6Ce5732pvvinLbtg/SHUB2RjebYIM9W0jVOR4U3UkV7ndn/OO
# PcbzaN9l9qRWqveVtihVJ9AkvUCgvxm2EhIRXT0n4ECWOKz3+SmJw7wXsFSFQrP8
# DJ6LGYnn8AtqgcKBGUIZUnWKNsIdw2FzLixre24/LAl4FOmRsqlb30mjdAy87JGA
# 0j3mSj5mO0+7hvoyGtmW9I/2kQH2zsZ0/fZMcm8Qq3UwxTSwethQ/gpY3UA8x1Rt
# nWN0SCyxTkctwRQEcb9k+SS+c23Kjgm9swFXSVRk2XPXfx5bRAGOWhmRaw2fpCjc
# ZxkoJLo4S5pu+yFUa2pFEUep8beuyOiJXk+d0tBMdrVXVAmxaQFEfnyhYWxz/gq7
# 7EFmPWn9y8FBSX5+k77L+DvktxW/tM4+pTFRhLy/AsGConsXHRWJjXD+57XQKBqJ
# C4822rpM+Zv/Cuk0+CQ1ZyvgDbjmjJnW4SLq8CdCPSWU5nR0W2rRnj7tfqAxM328
# y+l7vzhwRNGQ8cirOoo6CGJ/2XBjU02N7oJtpQUQwXEGahC0HVUzWLOhcGbyoYID
# WTCCAkECAQEwggEBoYHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25z
# IExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo0MzFBLTA1RTAtRDk0
# NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcG
# BSsOAwIaAxUA94Z+bUJn+nKwBvII6sg0Ny7aPDaggYMwgYCkfjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAOurcZAwIhgPMjAy
# NTA0MTcxMjI0NDhaGA8yMDI1MDQxODEyMjQ0OFowdzA9BgorBgEEAYRZCgQBMS8w
# LTAKAgUA66txkAIBADAKAgEAAgIEFAIB/zAHAgEAAgIY4DAKAgUA66zDEAIBADA2
# BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIB
# AAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQBeoNcOIdNhbJRpdsITb9biSWOK48g2
# qDeZ863um4PhiuBsl+yl9vP48uqArcl1FIfVl/TOQ54dxJVVW49HyZG13AOwOLgv
# OJ/NhP2+22EwBtZHAxOc/fqt0k73moPjWi7XzGWWV5MqyJmOJwRG3pHFZoxqvWRE
# KvQGOZT15bggUSh+ASoAMRhOcmXXNfpiELia/imPAIzGxG1J+/i+ZDShyaCxNEIa
# 5YbFckv04ONIYlU1Uuw7Hprmg7AKH3TdHx9SVTxxhTxukqaCXe/Rd2NPCt3GWFu8
# G8MMXskYP56TEkYiIgRiOTB4louL7oB22hd2eMblbgkqcEvSlIgXobvZMYIEDTCC
# BAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH6+ztE
# 03czxtMAAQAAAfowDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsq
# hkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgfUrCv/hFq8wN/U4jSYE67yFELpij
# DmZI8WmJwtpdz0YwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCB98n8tya8+
# B2jjU/dpJRIwHwHHpco5ogNStYocbkOeVjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAAB+vs7RNN3M8bTAAEAAAH6MCIEIA+ou1umgeIs
# bimRxjz9JxqvWpMuPHhjZLuuAkgZ5s3JMA0GCSqGSIb3DQEBCwUABIICAD0dVC6b
# LFEwvlKHF42xCVJRmSlN+6s7uPMLsZ1HYpjZ55cA0IBXZUG1T3hqOFrBkEYNi4i5
# LhkWMNv6kFm61K+m/NmK2fbYQZc5EEirHlMKr/Jk9OAkeIey305ed1/1sj+C6A4k
# +IIFl7it7Z/UogqCcTR/91VEffjT1Cp7o/fuLiVhaMiLEck1/HGUvYULJSLBSvQu
# 1XM8wD4IH+6gABFpgWKzVE9PIOG+0bQSuZleR2uerXya7dnBd0teibwetYroW6Jn
# gLN4ZIuBodF4NzKFNVDB0R46Dtv6pqtHSc8t6TyAVHRpR7g3XwWzVPzGF8nMlLkS
# FoYuvTUmXlsoxPxWBsILz4cWTxNAxEAtunBAGrOS+UABaWQnR++P+fcbXTw7dhFu
# AED7TimDZbE55O54Xpljl9iydtPwhwOgDZ4CHzDzwxTCk5G2DLFV6z/Vpdx/78lG
# Eb4lTLm/gAMhbLP0wzWo0lt5aP+2/bL31XWh11ZQhH4TWmtqhCROCupeKHmii0uV
# R3TzhZ5N+f7ktnKf6A4d4GugXy06ZLEtvEM/di2XbT+RrR9R823Mp9vzO6bW7as3
# VNWmAPUp6E2Z8RbF9BiKjBwz2cCtpYtil2mfgn+z52XU+4AD1N74TFv/l3IaSVpR
# zFmc9zRgngexIN1qFfycrxYKCq3Ka2AOrvUM
# SIG # End signature block
