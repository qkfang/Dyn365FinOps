<#
.SYNOPSIS
    This file calls the LCS functions to deploy an asset from the asset library to an environment. This depends on VSTS Task SDK
    and cannot be used outside of VSTS.
    
    Copyright © 2022 Microsoft. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Trace-VstsEnteringInvocation $MyInvocation
try
{
    Write-Host "##vso[task.logissue type=warning]New task version available. Please upgrade to latest to avoid disruption."
    Import-Module "$PSScriptRoot\LifecycleServices.psm1"

    $projectId = Get-VstsInput -Name "projectId" -Require
    $fileAssetId = Get-VstsInput -Name "fileAssetId" -Require
    $environmentId = Get-VstsInput -Name "environmentId" -Require
    $deploymentType = Get-VstsInput -Name "deploymentType" -Require

    $serviceConnectionName = Get-VstsInput -Name 'serviceConnectionName' -Require
    $connectedServiceEndpoint = Get-VstsEndpoint -Name $serviceConnectionName -Require

    if ($connectedServiceEndpoint.Auth.Scheme -eq "UserNamePassword")
    {
        $authParams = $connectedServiceEndpoint.Auth.Parameters
    }

    Write-Host "Authenticating with MSAL on $($connectedServiceEndpoint.url) for API $($connectedServiceEndpoint.Data.apiurl)"
    $expiration = [System.DateTimeOffset]::Now
    $securePwd = $authParams.password | ConvertTo-SecureString -AsPlainText -Force
    $bearerTokenHeader = Get-MSALAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $securePwd -ExpirationData ([ref]$expiration)
    
    switch ($deploymentType)
    {
        'hq'
        {
            $waitForCompletion = Get-VstsInput -Name "waitForCompletion"
            $releaseName = Get-VstsInput -Name "releaseName" -Require

            Write-Host "Deploying asset '$fileAssetId' to environment '$environmentId' of project '$projectId'"
            $activity = Deploy-LCSFileAssetV2 -BearerTokenHeader $bearerTokenHeader -Projectid $projectId -EnvironmentId $environmentId -AssetId $fileAssetId -UpdateName $releaseName -LCSAPI $connectedServiceEndpoint.Data.apiurl

            # This activity id variable name is hardcoded in task.json as per the output variables setup in tasks
            Write-Output "##vso[task.setvariable variable=ActivityId;]$($activity.OperationActivityId)"

            Write-Host "Successfully started deployment of asset '$fileAssetId' to environment '$environmentId' with activity id '$($activity.OperationActivityId)'"

            if ($waitForCompletion -eq "true")
            {
                Write-Host "Waiting for deployment to complete..."

                # Ping environment status every 5 minutes until it's no longer InProgress, NotStarted or PreparingEnvironment, or some other exception occurred
                do
                {
                    Start-Sleep -Seconds 300

                    # If less than a minute before token expiration, re-authenticate
                    if (($expiration - [System.DateTimeOffset]::Now).TotalMinutes -lt 1)
                    {
                        Write-Host "Re-Authenticating with MSAL"
                        $bearerTokenHeader = Get-MSALAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $securePwd -ExpirationData ([ref]$expiration)
                    }

                    $status = Get-LCSEnvironmentActivityIdStatus -BearerTokenHeader $bearerTokenHeader -ProjectId $projectId -EnvironmentId $environmentId -ActivityId $activity.OperationActivityId -LCSAPI $connectedServiceEndpoint.Data.apiurl

                    Write-Host "Status: $($status.OperationStatus)"
                }
                while (($status.OperationStatus -eq "InProgress") -or ($status.OperationStatus -eq "NotStarted"))

                # Only report success if status shows completed or signed off (which can happen when someone signs off before our sleep loop gets the next status)
                if (($status.OperationStatus -eq "Completed") -or ($status.OperationStatus -eq "SignedOff"))
                {
                    Write-Host "Successfully deployed asset '$fileAssetId' to environment '$environmentId' with activity id '$($activity.OperationActivityId)'"
                }
                else
                {
                    throw "Asset not successfully deployed."
                }
            }
        }
        'hqonprem'
        {
            $waitForCompletion = Get-VstsInput -Name "waitForCompletion"
            $releaseName = Get-VstsInput -Name "releaseName" -Require

            Write-Host "Deploying asset '$fileAssetId' to environment '$environmentId' of project '$projectId'"
            $activity = Deploy-LCSFileAssetV2 -BearerTokenHeader $bearerTokenHeader -Projectid $projectId -EnvironmentId $environmentId -AssetId $fileAssetId -UpdateName $releaseName -LCSAPI $connectedServiceEndpoint.Data.apiurl

            # This activity id variable name is hardcoded in task.json as per the output variables setup in tasks
            Write-Output "##vso[task.setvariable variable=ActivityId;]$($activity.OperationActivityId)"

            Write-Host "Successfully started preparation of asset '$fileAssetId' on environment '$environmentId' with activity id '$($activity.OperationActivityId)'"

            Write-Host "Waiting for preparation to complete..."

            # Ping environment status every 5 minutes until it's no longer NotStarted or PreparingEnvironment, or some other exception occurred
            do
            {
                Start-Sleep -Seconds 300

                # If less than a minute before token expiration, re-authenticate
                if (($expiration - [System.DateTimeOffset]::Now).TotalMinutes -lt 1)
                {
                    Write-Host "Re-Authenticating with MSAL"
                    $bearerTokenHeader = Get-MSALAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $securePwd -ExpirationData ([ref]$expiration)
                }

                $status = Get-LCSOnpremEnvironmentStatus -BearerTokenHeader $bearerTokenHeader -ProjectId $projectId -EnvironmentId $environmentId -LCSAPI $connectedServiceEndpoint.Data.apiurl

                Write-Host "Status: $($status.OperationStatus)"
            }
            while (($status.OperationStatus -eq "PreparingEnvironment") -or ($status.OperationStatus -eq "Downloading"))

            if(($status.OperationStatus -ne "PreparationSucceeded"))
            {
                throw "Asset not successfully prepared for deployment: $($status.OperationStatus)"
            }

            # If less than a minute before token expiration, re-authenticate
            if (($expiration - [System.DateTimeOffset]::Now).TotalMinutes -lt 1)
            {
                Write-Host "Re-Authenticating with MSAL"
                $bearerTokenHeader = Get-MSALAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $securePwd -ExpirationData ([ref]$expiration)
            }

            #Give some buffer time so the backend has time to sync all status.
            Start-Sleep 60

            Write-Host "Initiate deployment of asset '$fileAssetId' on environment '$environmentId' with activity id '$($activity.OperationActivityId)'"

            $activity = Deploy-PreparedOnpremEnvironment -BearerTokenHeader $bearerTokenHeader -Projectid $projectId -EnvironmentId $environmentId -PreparationActivityId $activity.OperationActivityId -LCSAPI $connectedServiceEndpoint.Data.apiurl

            Write-Host "Successfully started deployment of asset '$fileAssetId' on environment '$environmentId' with activity id '$($activity.OperationActivityId)'"

            if ($waitForCompletion -eq "true")
            {
                Write-Host "Waiting for deployment to complete..."

                # Ping environment status every 5 minutes until it's no longer PreparationSucceeded or InProgress, or some other exception occurred
                do
                {
                    Start-Sleep -Seconds 300

                    # If less than a minute before token expiration, re-authenticate
                    if (($expiration - [System.DateTimeOffset]::Now).TotalMinutes -lt 1)
                    {
                        Write-Host "Re-Authenticating with MSAL"
                        $bearerTokenHeader = Get-MSALAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $securePwd -ExpirationData ([ref]$expiration)
                    }

                    $status = Get-LCSOnpremEnvironmentStatus -BearerTokenHeader $bearerTokenHeader -ProjectId $projectId -EnvironmentId $environmentId -LCSAPI $connectedServiceEndpoint.Data.apiurl

                    Write-Host "Status: $($status.OperationStatus)"
                }
                while (($status.OperationStatus -eq "PreparationSucceeded") -or ($status.OperationStatus -eq "Deploying"))

                # Only report success if status shows deployed
                if (($status.OperationStatus -eq "Deployed"))
                {
                    Write-Host "Successfully deployed asset '$fileAssetId' to environment '$environmentId' with activity id '$($activity.OperationActivityId)'"
                }
                else
                {
                    throw "Asset not successfully deployed: $($status.OperationStatus)"
                }
            }
        }
        'csu'
        {
            $scaleUnitName = Get-VstsInput -Name "scaleUnitName" -Require

            Write-Host "Deploying asset id -'$fileAssetId' to Commerce Cloud Scale Unit -'$scaleUnitName' in LCS environment -'$environmentId' and project -'$projectId'"
            $activity = Deploy-CommerceScaleUnit -BearerTokenHeader $bearerTokenHeader -Projectid $projectId -EnvironmentId $environmentId -ScaleUnitName $scaleUnitName -AssetId $fileAssetId -LCSAPI $connectedServiceEndpoint.Data.apiurl

            # This activity id variable name is hardcoded in task.json as per the output variables setup in tasks
            Write-Output "##vso[task.setvariable variable=ActivityId;]$($activity.OperationActivityId)"

            Write-Host "Started asset id -'$fileAssetId' deployment to Commerce Cloud Scale Unit -'$scaleUnitName' in LCS environment -'$environmentId' and project -'$projectId'. Activity id -'$($activity.OperationActivityId)'"
            Write-Host "Deployment in-progress..."

            # Ping environment status every 2 minutes until it's no longer InProgress, Queued or NotStarted, or some other exception occurred
            do
            {
                Start-Sleep -Seconds 120

                # If less than a minute before token expiration, re-authenticate
                if (($expiration - [System.DateTimeOffset]::Now).TotalMinutes -lt 1)
                {
                    Write-Host "Re-Authenticating with MSAL"
                    $bearerTokenHeader = Get-MSALAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $securePwd -ExpirationData ([ref]$expiration)
                }

                $status = Get-CommerceScaleUnitStatus -BearerTokenHeader $bearerTokenHeader -ProjectId $projectId -EnvironmentId $environmentId -ScaleUnitName $scaleUnitName -LCSAPI $connectedServiceEndpoint.Data.apiurl

                Write-Host "Deployment status: $($status.OperationStatus), $($status.CurrentStep)"
            }
            while (($status.OperationStatus -eq "Running") -or ($status.OperationStatus -eq "Queued") -or ($status.OperationStatus -eq "NotStarted"))

            # Only report success if status shows succeeded
            if (($status.OperationStatus -eq "Succeeded"))
            {
                Write-Host "Successfully deployed asset id -'$fileAssetId' to Commerce Cloud Scale Unit -'$scaleUnitName'. Activity id -'$($activity.OperationActivityId)'"
            }
            else
            {
                throw "Failed to deploy the asset. Activity Id -'$($activity.OperationActivityId)'"
            }
        }
        'ecom'
        {
            $ecommerceEnvironmentId = Get-VstsInput -Name "ecommerceEnvironmentId" -Require

            Write-Host "Deploying e-Commerce asset id -'$fileAssetId' to e-Commerce environment -'$ecommerceEnvironmentId' in LCS environment -'$environmentId' and project -'$projectId'"
            $activity = Deploy-EcommerceFileAsset -BearerTokenHeader $bearerTokenHeader -Projectid $projectId -EnvironmentId $environmentId -EcommerceEnvironmentId $ecommerceEnvironmentId -AssetId $fileAssetId -LCSAPI $connectedServiceEndpoint.Data.apiurl

            # This activity id variable name is hardcoded in task.json as per the output variables setup in tasks
            Write-Output "##vso[task.setvariable variable=ActivityId;]$($activity.OperationActivityId)"

            Write-Host "Started e-Commerce asset id -'$fileAssetId' deployment to e-Commerce environment -'$ecommerceEnvironmentId' in LCS environment -'$environmentId' and project -'$projectId'. Activity id -'$($activity.OperationActivityId)' and Deployment id -'$($activity.DeploymentId)'"
            Write-Host "Deployment in-progress..."

            # Ping environment status every 2 minutes until it's either failed or succeeded, or some other exception occurred
            do
            {
                Start-Sleep -Seconds 120

                # If less than a minute before token expiration, re-authenticate
                if (($expiration - [System.DateTimeOffset]::Now).TotalMinutes -lt 1)
                {
                    Write-Host "Re-Authenticating with MSAL"
                    $bearerTokenHeader = Get-MSALAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $securePwd -ExpirationData ([ref]$expiration)
                }

                $status = Get-EcommerceEnvironmentDeploymentStatus -BearerTokenHeader $bearerTokenHeader -ProjectId $projectId -EnvironmentId $environmentId -EcommerceEnvironmentId $ecommerceEnvironmentId -DeploymentId $activity.DeploymentId -LCSAPI $connectedServiceEndpoint.Data.apiurl

                Write-Host "Deployment status: $($status.OperationStatus)"
            }
            while (($status.OperationStatus -ne "Succeeded") -and ($status.OperationStatus -ne "Failed"))

            # Only report success if status shows completed or signed off (which can happen when someone signs off before our sleep loop gets the next status)
            if ($status.OperationStatus -eq "Succeeded")
            {
                Write-Host "Successfully deployed e-Commerce asset id -'$fileAssetId' to e-Commerce environment -'$ecommerceEnvironmentId' in LCS environment -'$environmentId' and project -'$projectId'. Activity id -'$($activity.OperationActivityId)' and Deployment id -'$($activity.DeploymentId)'"
            }
            else
            {
                throw "Failed to deploy the asset. Activity Id -'$($activity.OperationActivityId)' and Deployment Id -'$($activity.DeploymentId)')"
            }
        }
        Default
        {
            throw "Selected Deployment Type '$deploymentType' is not supported"
        }
    }
}
finally
{
    Trace-VstsLeavingInvocation $MyInvocation
}

# SIG # Begin signature block
# MIIoDwYJKoZIhvcNAQcCoIIoADCCJ/wCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBfKP8CRz+GogFP
# 7LJURV+pDcRYVCqxcPfyAr8UMICXEKCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IAB6dk/cuJvF2TsVaGpTmKFdpoyCUGLOjlNsA3xmLuDyMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAk6AXycMsO8XtMdAThkEFaCExsAiVcYsc
# uDRpw7qZ5chOoUzJ3OU5wcf6SCsWTb2FIawiUVHxj6b77vFA4Mu2sePxcTtMHn8a
# akak7EfaUTwxaEMZGFTybkm5mbjhDxigG2vDtVQsFJGeHbAaGRuHaphCyIlmy0lD
# fDzgN91zI4koqLUhixkkQjvwtci2rIvtFGYCLgSw1C8AcKTwUFhinZrT4xKtEOx2
# supdAjv5ORPc3d8Xo/hTEDogvw6ZhJp9CdjAXXUXlr5EUM5Qz8v9SS8kQtUnjqGt
# lDdkuW78ZlZmc5iPNT/+JO9tqHSEV1jnZ0/87lCKQPiGHHy9AI3tzKGCF5cwgheT
# BgorBgEEAYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCCF3AwghdsAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBFfFDaBMyhY6EPMXnIlWh/IbIbwu/+
# 6yEKy6m4EWU6jwIGZ/g0cGLAGBMyMDI1MDQxODAwMjAwNi44OThaMASAAgH0oIHR
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
# AQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAyGB+rpPQbJXZShvBA
# avIwpKPL8cMBG8nUho5BqVfs3zCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0E
# IIANAz3ceY0umhdWLR2sJpq0OPqtJDTAYRmjHVkwEW9IMIGYMIGApH4wfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIFPHVsgkSHzf4AAQAAAgUwIgQg
# yeBq2JnTypbh+6amUPqsU7YvJEpE+fqce8Bu+5O+1v4wDQYJKoZIhvcNAQELBQAE
# ggIAh8ojqK5+dJ9hLIyfWLNqBaVzi36sbERGJcqNd8HKphlhcUiZCluiz8/VQQ5m
# Vfr8BPbe3E/KGFILJb4mgSDkDaG9Adsqs87C/XRQyN0rjc0EvWPeZ6lf5uFWyAB3
# x0XCFqeOs049/ib4Nov3j25iz1PymCaqaAizWsXyI8ds/MER6Y70/KAWvQngqEfA
# +j4fEzJmNYWuq9Ga0pG8KsKAiULnBZoCqBNTONlSZSoO8rpqyQ1IvZcDUfFWQk56
# G9wLJ2TwmO5HdxJFt5dkXGj1wrZWMMm5SpwfB0ZKYOSvMjnmjWJ22zfByJHQdZWT
# uW3B34wmeGHYySd3CX+7M/Z/i5ZVX847CHTvjBXZ5hjUApRK3WCPbf+S+Oi3jraP
# pwIW/OsozTGB5ZsCryiDzXeHMs4l+0K+2SrurSkfWlTKzA9Zq6QxAi94DMGPktXY
# PKuuvW3g6Y/T9Hmulvvj7vhn58IQYB+HQuCxF0c//BglTHk7Tnfv5FjCOX69AmCw
# lwj8uwc+ZBMvpHFak+n/7raQCpmHid9Pxc97g8l2neYij3h7Ad752KtgzGR7mLGw
# yjgVQSNlwVo15PPob1pltNjF4l99DoSSI32wMV0Wxtx7ped1+BBRKXqUOoxkAasF
# Tqtd4J2QvtUKUbiiw+Moxm34Tqsf8wvmqJr579tNZqqjl8U=
# SIG # End signature block
