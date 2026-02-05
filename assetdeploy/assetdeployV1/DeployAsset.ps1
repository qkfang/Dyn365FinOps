<#
.SYNOPSIS
    This file calls the LCS functions to deploy an asset from the asset library to an environment. This depends on VSTS Task SDK
    and cannot be used outside of VSTS.
    
    Copyright © 2019 Microsoft. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Trace-VstsEnteringInvocation $MyInvocation
try
{
    Write-Host "##vso[task.logissue type=warning]New task version available. Please upgrade to latest to avoid disruption. For existing service connections, the Authentication Endpoint setting in the service connection must be updated as outlined in 'Update existing service connections' section of https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/dev-tools/pipeline-lcs-connection-update."
    Import-Module "$PSScriptRoot\LifecycleServices.psm1"

    $projectId = Get-VstsInput -Name "projectId" -Require
    $fileAssetId = Get-VstsInput -Name "fileAssetId" -Require
    $environmentId = Get-VstsInput -Name "environmentId" -Require
    $waitForCompletion = Get-VstsInput -Name "waitForCompletion"
    $releaseName = Get-VstsInput -Name "releaseName" -Require

    $serviceConnectionName = Get-VstsInput -Name 'serviceConnectionName' -Require
    $connectedServiceEndpoint = Get-VstsEndpoint -Name $serviceConnectionName -Require

    if ($connectedServiceEndpoint.Auth.Scheme -eq "UserNamePassword")
    {
        $authParams = $connectedServiceEndpoint.Auth.Parameters
    }

    Write-Host "Deploying asset '$fileAssetId' to environment '$environmentId' of project '$projectId'"

    Write-Host "Authenticating with AAD on $($connectedServiceEndpoint.url) for API $($connectedServiceEndpoint.Data.apiurl)"
    $expiration = [System.DateTimeOffset]::Now
    $bearerTokenHeader = Get-AADAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $authParams.password -ExpirationData ([ref]$expiration)

    Write-Host "Start deployment V2"
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
                Write-Host "Re-Authenticating with AAD"
                $bearerTokenHeader = Get-AADAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $authParams.password -ExpirationData ([ref]$expiration)
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
finally
{
    Trace-VstsLeavingInvocation $MyInvocation
}

# SIG # Begin signature block
# MIIoDAYJKoZIhvcNAQcCoIIn/TCCJ/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB85HM69jybv/84
# F2meB4lOVvV0PoVfE9eU5FnRneWG16CCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# INr35etzRAQvHlOvxS5QscJAL+SRITA2bgDGgOp0ZhPSMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAcANjGlqbG1s5ByJHL3NOPN1aJ28nXYHm
# yhYhg0poPDf+eXlaSOMMuu8G5Cw8YWamwDsbJuaMPCfEGFfuoK8pZy8tGGE/WQFJ
# Lmac4xq0rBXIN1Jda65R2QF/VEm+Ak/6o88m45l/GtB2t+GodZKs4INT8heijvat
# f01USY9PCeM0oCbg0gankmtMlSA1tUDtcWCt1K6faJAbbOXbCFzLSH6YeHj44KgD
# OpfihsGHwEod1QG2hNpfVfjlKhXreOpeFsY8BpfI2OBI/nmZe3ruCDeOcI1pHfTt
# 9eS7vG4lDN26El7l3HoAtRoPnfHrTQc9XRkXcd9+YMJ/dTO0TQHQWqGCF5QwgheQ
# BgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBY/Xy/3TKNLpMZ8orZgW3eYGgOaEbk
# V+yrBZz+tNeewQIGZ/gQe5GCGBMyMDI1MDQxODAwMTkxMC45NzdaMASAAgH0oIHR
# pIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046ODkwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAg4syyh9lSB1
# YwABAAACDjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yNTAxMzAxOTQzMDNaFw0yNjA0MjIxOTQzMDNaMIHLMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQg
# QW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046ODkw
# MC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCs5t7iRtXt0hbeo9ME
# 78ZYjIo3saQuWMBFQ7X4s9vooYRABTOf2poTHatx+EwnBUGB1V2t/E6MwsQNmY5X
# pM/75aCrZdxAnrV9o4Tu5sBepbbfehsrOWRBIGoJE6PtWod1CrFehm1diz3jY3H8
# iFrh7nqefniZ1SnbcWPMyNIxuGFzpQiDA+E5YS33meMqaXwhdb01Cluymh/3EKvk
# nj4dIpQZEWOPM3jxbRVAYN5J2tOrYkJcdDx0l02V/NYd1qkvUBgPxrKviq5kz7E6
# AbOifCDSMBgcn/X7RQw630Qkzqhp0kDU2qei/ao9IHmuuReXEjnjpgTsr4Ab33IC
# AKMYxOQe+n5wqEVcE9OTyhmWZJS5AnWUTniok4mgwONBWQ1DLOGFkZwXT334IPCq
# d4/3/Ld/ItizistyUZYsml/C4ZhdALbvfYwzv31Oxf8NTmV5IGxWdHnk2Hhh4bnz
# TKosEaDrJvQMiQ+loojM7f5bgdyBBnYQBm5+/iJsxw8k227zF2jbNI+Ows8HLeZG
# t8t6uJ2eVjND1B0YtgsBP0csBlnnI+4+dvLYRt0cAqw6PiYSz5FSZcbpi0xdAH/j
# d3dzyGArbyLuo69HugfGEEb/sM07rcoP1o3cZ8eWMb4+MIB8euOb5DVPDnEcFi4N
# DukYM91g1Dt/qIek+rtE88VS8QIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFIVxRGlS
# EZE+1ESK6UGI7YNcEIjbMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNy
# bDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQB14L2TL+L8
# OXLxnGSal2h30mZ7FsBFooiYkUVOY05F9pnwPTVufEDGWEpNNy2OfaUHWIOoQ/9/
# rjwO0hS2SpB0BzMAk2gyz92NGWOpWbpBdMvrrRDpiWZi/uLS4ZGdRn3P2DccYmlk
# NP+vaRAXvnv+mp27KgI79mJ9hGyCQbvtMIjkbYoLqK7sF7Wahn9rLjX1y5QJL4lv
# Ey3QmA9KRBj56cEv/lAvzDq7eSiqRq/pCyqyc8uzmQ8SeKWyWu6DjUA9vi84QsmL
# jqPGCnH4cPyg+t95RpW+73snhew1iCV+wXu2RxMnWg7EsD5eLkJHLszUIPd+XClD
# +FTvV03GfrDDfk+45flH/eKRZc3MUZtnhLJjPwv3KoKDScW4iV6SbCRycYPkqoWB
# rHf7SvDA7GrH2UOtz1Wa1k27sdZgpG6/c9CqKI8CX5vgaa+A7oYHb4ZBj7S8u8sg
# xwWK7HgWDRByOH3CiJu4LJ8h3TiRkRArmHRp0lbNf1iAKuL886IKE912v0yq55t8
# jMxjBU7uoLsrYVIoKkzh+sAkgkpGOoZL14+dlxVM91Bavza4kODTUlwzb+SpXsSq
# Vx8nuB6qhUy7pqpgww1q4SNhAxFnFxsxiTlaoL75GNxPR605lJ2WXehtEi7/+YfJ
# qvH+vnqcpqCjyQ9hNaVzuOEHX4MyuqcjwjCCB3EwggVZoAMCAQICEzMAAAAVxedr
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
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjg5MDAt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQBK6HY/ZWLnOcMEQsjkDAoB/JZWCKCBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA66vI
# 2zAiGA8yMDI1MDQxNzE4MzcxNVoYDzIwMjUwNDE4MTgzNzE1WjB0MDoGCisGAQQB
# hFkKBAExLDAqMAoCBQDrq8jbAgEAMAcCAQACAgtwMAcCAQACAhK5MAoCBQDrrRpb
# AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSCh
# CjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBANi0g/03MEpPeMoI0oARID7/
# iZN3HQYV+QXiqET/NSAftGAZeFGlM1iNrN02uhi0gbeiCfOkyUvoCdvlLhYxQ6RU
# E3V8OHwyr2DVPi0S1FnarWG18O7QC7r/AVgHdmcuOSCq+HFoTbcxGpRb+TEAZqyS
# YIHUQeKT9CT1VdHnKs+Q6S1u3oVkBbmHUmWzOzNwifdG+c3QuEkJx8AnxRRTpTj5
# yx021hbkPcNJiJ/1b/xXXWDNC7v8axX0ijz/Ehavszokp2QySdIuNwz4bGU3Wwxq
# gCwlGIMmMvlPASzkuc+MYSQ2O+2IXhVViLfr9w7ZpwWs5X135uW1T7qchBeE4NMx
# ggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# Ag4syyh9lSB1YwABAAACDjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCDB7HwrGzhJwnkN9gemh8D1
# +w0Ntv7Zp/xGaSg2Q4DcNTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIAF0
# HXMl8OmBkK267mxobKSihwOdP0eUNXQMypPzTxKGMIGYMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIOLMsofZUgdWMAAQAAAg4wIgQg3w3/
# uB+L0dl8mW8skWDAEQdQnhVIIpaDVWNeKdy238gwDQYJKoZIhvcNAQELBQAEggIA
# nPWTAkH7ukWtuprCpsqPUsKLEvoBydL87os6GUbq9Ldv2HVBZ2Ui/mFrpGdzq1rJ
# WYogTSfEjiAxK5TZzKfUmYmsFs0yZQIU1i61A7mWmW6l44wj2Me4gHh8s6yx042m
# V2EIT8SDVWz0Dx+uTJ/WEGLu5l4unMQmqCTPJxlPUWFBAswbfF+y1H4KsOclsAal
# R70I1ZAKQToXfeWtwGnP/1i53HQBJpbFgyZ0k7BzEGiryYmig6nqwf5bPqXPCXQ5
# FV7ho/829V0tOlS28xjBw2URF+fmgYW4N4AiiXIAB9AzGv2tZqvh7DdtIVeYWJ0H
# dde8pf/YLp4mcH1NAFnkVzU4hOwBfgkUl44MQv72ZefBs+ezHMRhbpkFUTUUszxl
# X1xE8edK8ViU1B6r58lOVDisDUk3bPShflnT2wfgMJslJHJ2/ke5Pi0rqLw0BhxH
# nW4cxOfhOkLBJG/e8HWGx5N4plY9pjl9x/JhVx5sTuP7d3BrFoDKazGKZpx3FQ3a
# PwI4MEOXNZXaDC/4srilJ4/ET7V6r0aMNww1N7+Dy6IrSfZB214xqc+BGSUhvQHx
# 0zn+fxeic9uU7W/lwl2qrTFtLvFNDnKseWJNPLCmSnAQrT3bCs+e6Y1A/LJfmKoM
# VGbcfGaO638+dXRHJZJPB9y7kJI+4BdDbF8y9QhHGE8=
# SIG # End signature block
