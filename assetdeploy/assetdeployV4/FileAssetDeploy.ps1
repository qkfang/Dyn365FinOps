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
function Publish-LCSFileAsset
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
function Publish-LCSFileAssetV2
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
function Publish-EcommerceFileAsset
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
function Publish-PreparedOnpremEnvironment
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
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAW9n77jO5zHZPx
# ePgh+/1Q2y/7JtDLyGpW0CrvOJfbzaCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IHDQeo60rAh6kLVNhZw7D93Itp5Iw+i8fDf7lL9i0LpFMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAq0x7BopzCFg0TmKXtYzHpvWCz6+dtIcA
# Le+zWQ+yDav01cq0nTrvvZH9Zq6gX0BoyiVgSxP2t9pbQ0ze9BLYhc5M+Zbimsee
# GuW2JjhHJgjGaWrX8hWdeNv9Etjvd6nYVSHCXVF10IFmdD6cc/OTcNWGrXRNdrei
# hCMhDNxNhV82Aj8dgJDnZJr+xUYHt0rnPiRyJy0PwvA79GF0QZXeuraMWTbWnm9I
# L+0PxPMP+FIMawdrGqGH5PHxK82dWnHpDr3dXo71bYB9YglC3GTv7mTvzyB0U7fc
# khQ0xHWT4+MFJfgYW1bbw8IDQ5+nFNf+6mDIp0TfEhejk8fl3gwtPaGCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDKgaHkCDVdUJhjfoKJojKn2bLKKFWk
# Jlod1GYlFy6s4wIGZ+03K3r0GBMyMDI1MDQxODAwMjAyNS45NDVaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjo0MDFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB
# /tCowns0IQsBAAEAAAH+MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzExOFoXDTI1MTAyMjE4MzExOFowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjQwMUEtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEAvLwhFxWlqA43olsE4PCegZ4mSfsH2YTSKEYv8Gn3362Bmaycdf5T3tQxpP3N
# Wm62YHUieIQXw+0u4qlay4AN3IonI+47Npi9fo52xdAXMX0pGrc0eqW8RWN3bfzX
# PKv07O18i2HjDyLuywYyKA9FmWbePjahf9Mwd8QgygkPtwDrVQGLyOkyM3VTiHKq
# hGu9BCGVRdHW9lmPMrrUlPWiYV9LVCB5VYd+AEUtdfqAdqlzVxA53EgxSqhp6Jbf
# EKnTdcfP6T8Mir0HrwTTtV2h2yDBtjXbQIaqycKOb633GfRkn216LODBg37P/xwh
# odXT81ZC2aHN7exEDmmbiWssjGvFJkli2g6dt01eShOiGmhbonr0qXXcBeqNb6Qo
# F8jX/uDVtY9pvL4j8aEWS49hKUH0mzsCucIrwUS+x8MuT0uf7VXCFNFbiCUNRTof
# xJ3B454eGJhL0fwUTRbgyCbpLgKMKDiCRub65DhaeDvUAAJT93KSCoeFCoklPavb
# gQyahGZDL/vWAVjX5b8Jzhly9gGCdK/qi6i+cxZ0S8x6B2yjPbZfdBVfH/NBp/1L
# n7xbeOETAOn7OT9D3UGt0q+KiWgY42HnLjyhl1bAu5HfgryAO3DCaIdV2tjvkJay
# 2qOnF7Dgj8a60KQT9QgfJfwXnr3ZKibYMjaUbCNIDnxz2ykCAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBRvznuJ9SU2g5l/5/b+5CBibbHF3TAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEAiT4NUvO2lw+0dDMtsBuxmX2o3lVQqnQkuITAGIGCgI+sl7ZqZOTD
# d8LqxsH4GWCPTztc3tr8AgBvsYIzWjFwioCjCQODq1oBMWNzEsKzckHxAzYo5Sze
# 7OPkMA3DAxVq4SSR8y+TRC2GcOd0JReZ1lPlhlPl9XI+z8OgtOPmQnLLiP9qzpTH
# wFze+sbqSn8cekduMZdLyHJk3Niw3AnglU/WTzGsQAdch9SVV4LHifUnmwTf0i07
# iKtTlNkq3bx1iyWg7N7jGZABRWT2mX+YAVHlK27t9n+WtYbn6cOJNX6LsH8xPVBR
# YAIRVkWsMyEAdoP9dqfaZzwXGmjuVQ931NhzHjjG+Efw118DXjk3Vq3qUI1re34z
# MMTRzZZEw82FupF3viXNR3DVOlS9JH4x5emfINa1uuSac6F4CeJCD1GakfS7D5ay
# NsaZ2e+sBUh62KVTlhEsQRHZRwCTxbix1Y4iJw+PDNLc0Hf19qX2XiX0u2SM9CWT
# Tjsz9SvCjIKSxCZFCNv/zpKIlsHx7hQNQHSMbKh0/wwn86uiIALEjazUszE0+X6r
# cObDfU4h/O/0vmbF3BMR+45rAZMAETJsRDPxHJCo/5XGhWdg/LoJ5XWBrODL44YN
# rN7FRnHEAAr06sflqZ8eeV3FuDKdP5h19WUnGWwO1H/ZjUzOoVGiV3gwggdxMIIF
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
# BAsTHm5TaGllbGQgVFNTIEVTTjo0MDFBLTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAhGNHD/a7
# Q0bQLWVG9JuGxgLRXseggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOureyAwIhgPMjAyNTA0MTcxMzA1MzZaGA8y
# MDI1MDQxODEzMDUzNlowdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA66t7IAIBADAK
# AgEAAgIKuQIB/zAHAgEAAgIUbjAKAgUA66zMoAIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBCwUAA4IBAQCnG5V4DLt1wnlZjmqWcI1SAQxhybKcIz5po+9yv9UaSHwvDAv/
# RQcjUo4gzwQ8l+ge5cK/aM6tWP78eDesplh8askU02g+BIkVet9Bi7NmMh/rJpSY
# WSqrT/7f/dFDQGyVyZwspCmZPBsPRAe9CGfoc3qZj038Q3UwqXnoL3FWYAfFyzH4
# C41YetQAvn81UXgN05ir5JpG30btGOamUlwNQFus558uimATKqgGZ1ih859F6K5h
# Vkwh3tXCchFkHuRZbR+sYZuROD6FD7vozlwg9zNV+0UhoMSPAPxh944q52SvPp97
# Iz45Rce/QpVeW9B5lA5P5DVtZYqLh1/NRl1SMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH+0KjCezQhCwEAAQAAAf4wDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQg7mcAAtwfilg61JbQu3kJC8ySCpcV22OjbZmTgxCY8nIwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCARhczd/FPInxjR92m2hPWqc+vGOG1+
# /I0WtkCstyh0eTCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB/tCowns0IQsBAAEAAAH+MCIEIPAn5mkCZ+rvuSWQjK8lh9FCEh2zVnt8
# u6dHLXODHjDXMA0GCSqGSIb3DQEBCwUABIICADdEERLdivfVBhfkGt/coFVvcla4
# zspvWOvLWc1ooLf7Yo0GH1HlFU6veZsxTgY4lYStivxa2rUIeMTMi7c7UCvWju4+
# jSQYF8B2zxfVRM4+KLw27G3+6mKLjnzcS8FXGlB4HuiBYPMIIa0X1BSkk+RB7t9R
# ZlP9Qv2AHmQsJFVpZF0+Ul71VfB9bCuo+CsCXxHs6uvd2qLgqrbgNjcZIrFtv52A
# 5G4An1btS4QnspiZsE6BKj8+ithGNPV+QEvmxwym/q/PsuCW6YqXm+dGU3OKIa8R
# H59fjzjNGC3pIFXcWoCllpaNMjqhnUgCPl70YRZrKgNVLNCzqWWqsWvHLO6qy8BL
# jEnk6VT5sG0+en47JgWQUopwlIn58thqsjaAK68TeKSIIJmNlWfIWyBNUL5lDXOr
# ouW1E2L1kbWNDQPzh8ht8Lj1M0xPJD9PidIWDAxpR5RjZT5RZwkzjNSy6Bg3HIax
# g8aNXukj2OWjmB2HWwX8PGWxR7hDiwOTd9b3hlzD1sT4YDjDUM9qFW1+wUN7UH4x
# LzvgwJzbBkKohe+WLnKdT+ixz+DHV97VaKeUNtf8NA65puBrfT4BbtyIbTx6yNS3
# 17IG6nG9tExwHtttDGLeSvpRMMi1DmuiDvqGLHjpUU+CbFE986ACLKB2J3EJOuvF
# fuz3jmGeOZ3W62Re
# SIG # End signature block
