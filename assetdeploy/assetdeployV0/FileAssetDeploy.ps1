<#
.SYNOPSIS
    Import this module to get functions to handle deploying software deployable packages.
    
.DESCRIPTION
    This script can be imported to enable cmdlets to trigger an LCS deployment of a software
    deployable package (from asset library) to a specific environment in an LCS project.

.NOTES
    This library depends on RESTHelpers.ps1

    Copyright © 2020 Microsoft. All rights reserved.
#>

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to deploy a software deployable package
#>
function Deploy-LCSFileAsset
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The asset's ID in the asset library")]
        [string]$AssetId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the environment to deploy to")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient

    $deployFileAssetUri = "$LCSAPI/environment/servicing/v1/applyupdate/$($ProjectId)?assetId=$AssetId&environmentId=$EnvironmentId"

    $request = New-JsonRequestMessage -Uri $deployFileAssetUri -BearerTokenHeader $BearerTokenHeader

    $result = Get-AsyncResult -task $client.SendAsync($request)

    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $deployFailure = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if (($deployFailure) -and ($deployFailure.Message))
        {
            if ($deployFailure.ActivityId)
            {
                throw "Error '$($deployFailure.LcsErrorCode)' in request to deploy file asset: '$($deployFailure.Message)' (Activity Id: '$($deployFailure.ActivityId)')"
            }
            else
            {
                throw "Error '$($deployFailure.LcsErrorCode)' in request to deploy file asset: '$($deployFailure.Message)'"
            }
        }
        elseif ($deployFailure.ActivityId)
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase) (Activity Id: '$($deployFailure.ActivityId)')"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    }

    $activity = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    return $activity
}

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to deploy a software deployable package
#>
function Deploy-LCSFileAssetV2
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The asset's ID in the asset library")]
        [string]$AssetId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the environment to deploy to")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The name for the deployment")]
        [string]$UpdateName,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient

    $deployFileAssetUri = "$LCSAPI/environment/v2/applyupdate/project/$($ProjectId)/environment/$($EnvironmentId)/asset/$($AssetId)?updateName=$($UpdateName)"

    $request = New-JsonRequestMessage -Uri $deployFileAssetUri -BearerTokenHeader $BearerTokenHeader

    $result = Get-AsyncResult -task $client.SendAsync($request)

    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $deployFailure = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if (($deployFailure) -and ($deployFailure.ErrorMessage))
        {
            if ($deployFailure.OperationActivityId)
            {
                throw "Error in request to deploy file asset: '$($deployFailure.ErrorMessage)' (Operation Activity Id: '$($deployFailure.OperationActivityId)')"
            }
            else
            {
                throw "Error in request to deploy file asset: '$($deployFailure.ErrorMessage)'"
            }
        }
        elseif ($deployFailure.OperationActivityId)
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase) (Operation Activity Id: '$($deployFailure.OperationActivityId)')"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    }

    $activity = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if ($activity.IsSuccess -ne $True)
    {
        if ($activity.ErrorMessage)
        {
            if ($activity.OperationActivityId)
            {
                throw "Error in request to deploy file asset: '$($activity.ErrorMessage)' (Operation Activity Id: '$($activity.OperationActivityId)')"
            }
            else
            {
                throw "Error in request to deploy file asset: '$($activity.ErrorMessage)'"
            }
        }
        elseif ($activity.OperationActivityId)
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase) (Operation Activity Id: '$($activity.OperationActivityId)')"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    }

    return $activity
}


<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to deploy a software deployable package
#>
function Get-LCSEnvironmentActionStatus
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the environment to deploy to")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The action ID of the servicing request")]
        [string]$ActionId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient

    $deployFileAssetUri = "$LCSAPI/environment/servicing/v1/monitorupdate/$($ProjectId)?environmentId=$EnvironmentId&actionHistoryId=$ActionId"

    $request = New-JsonRequestMessage -Uri $deployFileAssetUri -BearerTokenHeader $BearerTokenHeader -HttpMethod ([System.Net.Http.HttpMethod]::Get)

    $result = Get-AsyncResult -task $client.SendAsync($request)

    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $deployFailure = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if (($deployFailure) -and ($deployFailure.Message))
        {
            if ($deployFailure.ActivityId)
            {
                throw "Error $($deployFailure.LcsErrorCode) in request for status of environment servicing action: '$($deployFailure.Message)' (Activity Id: '$($deployFailure.ActivityId)')"
            }
            else
            {
                throw "Error $($deployFailure.LcsErrorCode) in request for status of environment servicing action: '$($deployFailure.Message)'"
            }
        }
        elseif ($deployFailure.ActivityId)
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase) (Activity Id: '$($deployFailure.ActivityId)')"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    } 

    $activity = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if (!($activity.LcsEnvironmentActionStatus))
    {
        if ($activity.Message)
        {
            throw "Error in request for status of environment servicing action: '$($activity.Message)' (Activity Id: '$($activity.ActivityId)')"
        }
        elseif ($activity.ActivityId)
        {
            throw "Error in request for status of environment servicing action. Activity Id: '$($activity.ActivityId)'"
        }
        else
        {
            throw "Unknown error in request for status of environment servicing action"
        }
    }

    return $activity
}

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to deploy a software deployable package
#>
function Get-LCSEnvironmentActivityIdStatus
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the environment to deploy to")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The activity ID of the servicing request")]
        [string]$ActivityId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient

    $environmentActivityStatus = "$LCSAPI/environment/v2/fetchstatus/project/$($ProjectId)/environment/$($EnvironmentId)/operationactivity/$($ActivityId)"
    $request = New-JsonRequestMessage -Uri $environmentActivityStatus -BearerTokenHeader $BearerTokenHeader -HttpMethod ([System.Net.Http.HttpMethod]::Get)

    $result = Get-AsyncResult -task $client.SendAsync($request)

    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $deployFailure = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if ($deployFailure)
        {
            if ($deployFailure.ActivityId)
            {
                throw "Error in request for status of environment servicing action: '$($deployFailure.ErrorMessage)' (Activity Id: '$($deployFailure.ActivityId)')"
            }
            else
            {
                throw "Error in request for status of environment servicing action: '$($deployFailure.ErrorMessage)'"
            }
        }
        elseif ($deployFailure.ActivityId)
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase) (Activity Id: '$($deployFailure.ActivityId)')"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    } 

    $activity = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if (!($activity.OperationStatus))
    {
        if ($activity.ErrorMessage)
        {
            throw "Error in request for status of environment servicing action: '$($activity.ErrorMessage)' (Activity Id: '$($activity.ActivityId)')"
        }
        elseif ($activity.ActivityId)
        {
            throw "Error in request for status of environment servicing action. Activity Id: '$($activity.ActivityId)'"
        }
        else
        {
            throw "Unknown error in request for status of environment servicing action"
        }
    }

    return $activity
}

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to deploy e-Commerce package
#>
function Deploy-EcommerceFileAsset
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The asset's ID in the asset library")]
        [string]$AssetId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the LCS environment where e-Commerce exists")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The e-Commerce ID of the environment to deploy to")]
        [string]$EcommerceEnvironmentId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient

    $deployFileAssetUri = "$LCSAPI/environment/v2/applyupdate/project/$($ProjectId)/environment/$($EnvironmentId)/ecommerce/$($EcommerceEnvironmentId)/asset/$($AssetId)"

    do
    {
        $retry = $false
        $request = New-JsonRequestMessage -Uri $deployFileAssetUri -BearerTokenHeader $BearerTokenHeader

        $result = Get-AsyncResult -task $client.SendAsync($request)

        if ($result.StatusCode -eq 429)
        {
            Write-Host "Reached the maximum number of e-Commerce deployments for the LCS environment: $($EnvironmentId)."

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
                $deployFailure = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
            }
            catch { }

            if ($deployFailure)
            {
                if ($deployFailure.ErrorMessage)
                {
                    if ($deployFailure.OperationActivityId)
                    {
                        throw "Error in deploying e-Commerce file asset - '$($activity.ErrorMessage)' (Operation Activity Id: '$($activity.OperationActivityId)')"
                    }
                    else
                    {
                        throw "Error in deploying e-Commerce file asset - '$($activity.ErrorMessage)'"
                    }
                }
                elseif ($deployFailure.OperationActivityId)
                {
                    throw "API return code - $($result.StatusCode): $($result.ReasonPhrase) (Operation Activity Id - '$($deployFailure.OperationActivityId)')"
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
            throw "Error in deploying e-Commerce file asset - '$($activity.ErrorMessage)' (Operation Activity Id: '$($activity.OperationActivityId)')"
        }
        elseif ($activity.OperationActivityId)
        {
            throw "Error in deploying e-Commerce file asset (Operation Activity Id: '$($activity.OperationActivityId)')"
        }
        else
        {
            throw "Exceptions occurred in deploying e-Commerce file asset."
        }
    }

    return $activity
}

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to get e-Commerce asset deployment status
#>
function Get-EcommerceEnvironmentDeploymentStatus
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the LCS environment where e-Commerce exists")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The e-Commerce ID of the environment")]
        [string]$EcommerceEnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The deployment ID of the servicing request")]
        [string]$DeploymentId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient

    $environmentActivityStatus = "$LCSAPI/environment/v2/fetchstatus/project/$($ProjectId)/environment/$($EnvironmentId)/ecommerce/$($EcommerceEnvironmentId)/deploymentactivity/$($DeploymentId)"
    $request = New-JsonRequestMessage -Uri $environmentActivityStatus -BearerTokenHeader $BearerTokenHeader -HttpMethod ([System.Net.Http.HttpMethod]::Get)

    $result = Get-AsyncResult -task $client.SendAsync($request)

    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $deployFailure = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if ($deployFailure)
        {
            if ($deployFailure.ErrorMessage)
            {
                if ($deployFailure.ActivityId)
                {
                    throw "Error in api call for retrieving status of e-Commerce deployment action: '$($deployFailure.ErrorMessage)' (Activity Id: '$($deployFailure.ActivityId)')"
                }
                else
                {
                    throw "Error in api capp for retrieving status of e-Commerce deployment action: '$($deployFailure.ErrorMessage)'"
                }
            }
            elseif ($deployFailure.ActivityId)
            {
                throw "API return code - $($result.StatusCode): $($result.ReasonPhrase) (Activity Id - '$($deployFailure.ActivityId)')"
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
            throw "Not able to retrieve the status of e-Commerce deployment: '$($activity.ErrorMessage)' (Activity Id: '$($activity.ActivityId)')"
        }
        elseif ($activity.ActivityId)
        {
            throw "Not able to retrieve the status of e-Commerce deployment. (Activity Id: '$($activity.ActivityId)')"
        }
        else
        {
            throw "Exceptions occurred in retrieving the status of e-Commerce deployment."
        }
    }

    return $activity
}

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to deploy an onprem environment that has been successfully prepared.
#>
function Deploy-PreparedOnpremEnvironment
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the environment to deploy to")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$true, HelpMessage="The activity Id of the deploy file asset command that prepared the environment for deployment.")]
        [string]$PreparationActivityId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient
    
    $finalizeUpdateUri = "$LCSAPI/environment/v2/finalizeupdate/project/$($ProjectId)/environment/$($EnvironmentId)/preparationactivityid/$($PreparationActivityId)"

    $request = New-JsonRequestMessage -Uri $finalizeUpdateUri -BearerTokenHeader $BearerTokenHeader

    $result = Get-AsyncResult -task $client.SendAsync($request)

    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $failure = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if (($failure) -and ($failure.ErrorMessage))
        {
            if ($failure.OperationActivityId)
            {
                throw "Error in request to deploy file asset: '$($failure.ErrorMessage)' (Operation Activity Id: '$($failure.OperationActivityId)')"
            }
            else
            {
                throw "Error in request to deploy file asset: '$($failure.ErrorMessage)'"
            }
        }
        elseif ($failure.OperationActivityId)
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase) (Operation Activity Id: '$($failure.OperationActivityId)')"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    }

    $activity = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if ($activity.IsSuccess -ne $True)
    {
        if ($activity.ErrorMessage)
        {
            if ($activity.OperationActivityId)
            {
                throw "Error in request to deploy file asset: '$($activity.ErrorMessage)' (Operation Activity Id: '$($activity.OperationActivityId)')"
            }
            else
            {
                throw "Error in request to deploy file asset: '$($activity.ErrorMessage)'"
            }
        }
        elseif ($activity.OperationActivityId)
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase) (Operation Activity Id: '$($activity.OperationActivityId)')"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    }

    return $activity
}

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to check deployment progress of onprem environments
#>
function Get-LCSOnpremEnvironmentStatus
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The ID of the environment to deploy to")]
        [string]$EnvironmentId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )
    
    $client = New-HttpClient

    $environmentActivityStatus = "$LCSAPI/environment/v2/fetchstatus/project/$($ProjectId)/environment/$($EnvironmentId)/onprem"
    $request = New-JsonRequestMessage -Uri $environmentActivityStatus -BearerTokenHeader $BearerTokenHeader -HttpMethod ([System.Net.Http.HttpMethod]::Get)

    $result = Get-AsyncResult -task $client.SendAsync($request)

    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $failure = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if ($failure)
        {
            if ($failure.ActivityId)
            {
                throw "Error in request for status of onprem environment servicing action: '$($failure.ErrorMessage)' (Activity Id: '$($failure.ActivityId)')"
            }
            else
            {
                throw "Error in request for status of onprem environment servicing action: '$($failure.ErrorMessage)'"
            }
        }
        elseif ($failure.ActivityId)
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase) (Activity Id: '$($failure.ActivityId)')"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    } 

    $activity = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if (!($activity.OperationStatus))
    {
        if ($activity.ErrorMessage)
        {
            throw "Error in request for status of onprem environment servicing action: '$($activity.ErrorMessage)' (Activity Id: '$($activity.ActivityId)')"
        }
        elseif ($activity.ActivityId)
        {
            throw "Error in request for status of onprem environment servicing action. Activity Id: '$($activity.ActivityId)'"
        }
        else
        {
            throw "Unknown error in request for status of onprem environment servicing action"
        }
    }

    return $activity
}
# SIG # Begin signature block
# MIIoDwYJKoZIhvcNAQcCoIIoADCCJ/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAFZa640si96Wac
# KpLSFMbxWvhYxDd9rE1mlfEHM5qrMqCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IG3MVTEdxIkUbBkKlx1BI9a77a7G9HAgJdXmVG/0ugHeMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAC97eC0odjMKVlnRxLy//0GTBeb/V1adk
# IO8Xeb/ueze4Wpk2qE1SWu3t2fpd6mfMSiES/pSVW/FVg3t/bJ+qAXN0RE5o49Ab
# Mbjjwkj+IJJfHGtRE+GBQFGHVzqGgMmmGbo0T8nm8gVh6sGLeDpcZ1eO/N69Mzi9
# 0g5c1TDYE8S3bb074iQNQ+bXw2HdG1jSGV4c9MCsBVA4C/xszz3zUet+VdkIscti
# SigdLzbBd2DYwiJ1JOGCalIyG7x+hhLKALddIvKQhU1LT3Xu4csp4RjEDNUtonTq
# dDsbsw2BzxLzO5ITu2gaoDljsE3HYDPN1cYq43paONhDG/57+znHTKGCF5cwgheT
# BgorBgEEAYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCArV+GD1TtvJiZO4TgUAj9UVOFYv9N
# Av8BjxQVvzjoNQIGZ/f5EksOGBMyMDI1MDQxODAwMTkxNi40MDRaMASAAgH0oIHR
# pIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046REMwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIBAgITMwAAAgO7HlwAOGx0
# ygABAAACAzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yNTAxMzAxOTQyNDZaFw0yNjA0MjIxOTQyNDZaMIHLMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQg
# QW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046REMw
# MC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQChl0MH5wAnOx8Uh8Rt
# idF0J0yaFDHJYHTpPvRR16X1KxGDYfT8PrcGjCLCiaOu3K1DmUIU4Rc5olndjapp
# NuOgzwUoj43VbbJx5PFTY/a1Z80tpqVP0OoKJlUkfDPSBLFgXWj6VgayRCINtLsU
# asy0w5gysD7ILPZuiQjace5KxASjKf2MVX1qfEzYBbTGNEijSQCKwwyc0eavr4Fo
# 3X/+sCuuAtkTWissU64k8rK60jsGRApiESdfuHr0yWAmc7jTOPNeGAx6KCL2ktpn
# GegLDd1IlE6Bu6BSwAIFHr7zOwIlFqyQuCe0SQALCbJhsT9y9iy61RJAXsU0u0TC
# 5YYmTSbEI7g10dYx8Uj+vh9InLoKYC5DpKb311bYVd0bytbzlfTRslRTJgotnfCA
# IGMLqEqk9/2VRGu9klJi1j9nVfqyYHYrMPOBXcrQYW0jmKNjOL47CaEArNzhDBia
# 1wXdJANKqMvJ8pQe2m8/cibyDM+1BVZquNAov9N4tJF4ACtjX0jjXNDUMtSZoVFQ
# H+FkWdfPWx1uBIkc97R+xRLuPjUypHZ5A3AALSke4TaRBvbvTBYyW2HenOT7nYLK
# TO4jw5Qq6cw3Z9zTKSPQ6D5lyiYpes5RR2MdMvJS4fCcPJFeaVOvuWFSQ/EGtVBS
# hhmLB+5ewzFzdpf1UuJmuOQTTwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFLIpWUB+
# EeeQ29sWe0VdzxWQGJJ9MB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNy
# bDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCQEMbesD6T
# C08R0oYCdSC452AQrGf/O89GQ54CtgEsbxzwGDVUcmjXFcnaJSTNedBKVXkBgawR
# onP1LgxH4bzzVj2eWNmzGIwO1FlhldAPOHAzLBEHRoSZ4pddFtaQxoabU/N1vWyI
# CiN60It85gnF5JD4MMXyd6pS8eADIi6TtjfgKPoumWa0BFQ/aEzjUrfPN1r7crK+
# qkmLztw/ENS7zemfyx4kGRgwY1WBfFqm/nFlJDPQBicqeU3dOp9hj7WqD0Rc+/4V
# Z6wQjesIyCkv5uhUNy2LhNDi2leYtAiIFpmjfNk4GngLvC2Tj9IrOMv20Srym5J/
# Fh7yWAiPeGs3yA3QapjZTtfr7NfzpBIJQ4xT/ic4WGWqhGlRlVBI5u6Ojw3ZxSZC
# Lg3vRC4KYypkh8FdIWoKirjidEGlXsNOo+UP/YG5KhebiudTBxGecfJCuuUspIdR
# hStHAQsjv/dAqWBLlhorq2OCaP+wFhE3WPgnnx5pflvlujocPgsN24++ddHrl3O1
# FFabW8m0UkDHSKCh8QTwTkYOwu99iExBVWlbYZRz2qOIBjL/ozEhtCB0auKhfTLL
# euNGBUaBz+oZZ+X9UAECoMhkETjb6YfNaI1T7vVAaiuhBoV/JCOQT+RYZrgykyPp
# zpmwMNFBD1vdW/29q9nkTWoEhcEOO0L9NzCCB3EwggVZoAMCAQICEzMAAAAVxedr
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
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkRDMDAt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQDNrxRX/iz6ss1lBCXG8P1LFxD0e6CBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA66ux
# bzAiGA8yMDI1MDQxNzE2NTcxOVoYDzIwMjUwNDE4MTY1NzE5WjB3MD0GCisGAQQB
# hFkKBAExLzAtMAoCBQDrq7FvAgEAMAoCAQACAhHVAgH/MAcCAQACAhJKMAoCBQDr
# rQLvAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMH
# oSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAHGJpCbs8+NdFYBq4L6R
# 2tbmaLrtcZWGIqO32GTltXMYL408GvCm3DaOyEF/XytviMEPJ9/SWncDRAMH6rsV
# ICHcrXJs9oWMUjggUK/xzgKwRRoXLAEBmR1c+gqC0rUPmSU7KZKfEaz4BcDaUy04
# 3v1annaNVupKhVqCN/Ou5IiomtVMI3I5tWwtC5/9P1VHTiTTO50q5spaTCzjdYP5
# Cj4UQkfYPD0nCCWp801cgLH3lW/hemuqefAT7XmvDRYPqEmSLCbMWlmmCajQQzfb
# dQOLcPqKqfnjK9jtvR8WQfVOuFfRtt9Tj51u5Unnmly5HG/V/yZKEFKAXEJ4wjdG
# jGkxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGlu
# Z3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBv
# cmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAIT
# MwAAAgO7HlwAOGx0ygABAAACAzANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcN
# AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAj4X0Tu9j2RD+ralMl
# bpZds8QvBICg/2OWiZhbRpf5RjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0E
# IEsD3RtxlvaTxFOZZnpQw0DksPmVduo5SyK9h9w++hMtMIGYMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIDux5cADhsdMoAAQAAAgMwIgQg
# Ucqh1v2zp4VGQQYs9Oi+yhTm1FVQB0sQWitVOFh019gwDQYJKoZIhvcNAQELBQAE
# ggIAFYLx6GvcE3z/sjpPbf2sGBWgbZmQVUxvDURsPmO9yKxA65zPGyPjBXHtChH/
# euzObTx88zZzRFHxUyCd6MjaVJpqQ8ylIQ4I9RrG3OlgSxylv309XqZhNTIG0tsb
# zxe1Kx9k10aE9FMDrpDx8d9MNsxkN85xKW1g1P95oSmpDnmBjBzBP2fIr4DI/7/f
# oH9LjmEC+mcOWCBLHTEmk+SPGR3s4rFZdaufwVgcBKHY/6L7LIn59NKx7MxcAtBP
# gRl5mgG46uILUIT9V/zbdI9XJYf3pcaUKsxkIaQ1aGybDNIp3HlElRi22h+N+0Dy
# SftSMiqtiEljjMIzxG2deElba7ErNfPLTlBICmcFr8Tj9JTRESZbaYckv5M+TTVk
# J3ccFZZoPiBw3P6EQ/yiYRTO5kRk51E00kYmdedT4bWpv+D/CmH1lX/uPdn+P/u1
# yzpFPVNTaVVgNG7ghB+KbKmyzog/MWyJo522j1G63CC5krbA7JExXoaSxcsO6mMX
# jApANOI7Bzv0g6Detpii5OnwK9AgMZgt2dj9KgOJ/Ee06L9Suor9fzY6ZDmxMlQQ
# dy8xaOHLhBjEgMDfrjvtjtHdYy663TJHvDbtxkeiDzG8NsUyVNYS4DwkJCwfRILx
# teELp7QoQ7FffPGYo1o6J8GRSvy51VjqS7oyOkTlv/e1s7A=
# SIG # End signature block
