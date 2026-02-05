<#
.SYNOPSIS
    This file calls the LCS functions to upload to the asset library. This depends on VSTS Task SDK
    and cannot be used outside of VSTS.
    
    Copyright © 2018 Microsoft. All rights reserved.
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
    $assetType = Get-VstsInput -Name "assetType" -Require
    $assetPath = Get-VstsInput -Name "assetPath" -Require
    $assetName = Get-VstsInput -Name "assetName"
    $assetDescription = Get-VstsInput -Name "assetDescription"
    $waitForValidation = Get-VstsInput -Name "waitForValidation"

    Assert-VstsPath -LiteralPath $assetPath -PathType Leaf

    $serviceConnectionName = Get-VstsInput -Name 'serviceConnectionName' -Require
    $connectedServiceEndpoint = Get-VstsEndpoint -Name $serviceConnectionName -Require

    if ($connectedServiceEndpoint.Auth.Scheme -eq "UserNamePassword")
    {
        $authParams = $connectedServiceEndpoint.Auth.Parameters
    }

    Write-Host "Uploading '$assetPath' as '$assetType' to asset library of project '$projectId'"

    Write-Host "Authenticating with AAD on $($connectedServiceEndpoint.url) for API $($connectedServiceEndpoint.Data.apiurl)"
    $expiration = [System.DateTimeOffset]::Now
    $bearerTokenHeader = Get-AADAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $authParams.password -ExpirationData ([ref]$expiration)

    Write-Host "Creating library entry for asset"
    $asset = New-LCSFileAsset -BearerTokenHeader $bearerTokenHeader -Projectid $projectId -FileType $assetType -FilePath $assetPath -AssetName $assetName -AssetDescription $assetDescription -LCSAPI $connectedServiceEndpoint.Data.apiurl

    Write-Host "Uploading '$assetPath'"
    Send-FileToBlob -FilePath $assetPath -BlockBlobUri $asset.FileLocation

    # If less than a minute before token expiration, re-authenticate
    if (($expiration - [System.DateTimeOffset]::Now).TotalMinutes -lt 1)
    {
        Write-Host "Re-Authenticating with AAD"
        $bearerTokenHeader = Get-AADAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $authParams.password -ExpirationData ([ref]$expiration)
    }

    Write-Host "Committing library entry for asset"
    $commitRequest = Confirm-FileAssetUpload -BearerTokenHeader $bearerTokenHeader -ProjectId $projectId -AssetId $asset.Id -LCSAPI $connectedServiceEndpoint.Data.apiurl

    # This FileAssetId variable name is hardcoded in task.json as per the output variables setup in tasks
    Write-Output "##vso[task.setvariable variable=FileAssetId;]$($asset.Id)"

    Write-Host "Successfully uploaded asset '$($asset.Name)' as artifact '$($asset.Id)'"

    if ($waitForValidation -eq "true")
    {
        Write-Host "Waiting for asset validation..."

        # Ping validation status every 1 minute until it's no longer Process
        do
        {
            Start-Sleep -Seconds 60

            # If less than a minute before token expiration, re-authenticate
            if (($expiration - [System.DateTimeOffset]::Now).TotalMinutes -lt 1)
            {
                Write-Host "Re-Authenticating with AAD"
                $bearerTokenHeader = Get-AADAuthHeader -AuthProviderUri $connectedServiceEndpoint.url -ClientId $authParams.clientid -LCSAPI $connectedServiceEndpoint.Data.apiurl -UserName $authParams.username -Password $authParams.password -ExpirationData ([ref]$expiration)
            }
            
            $status = Get-LCSFileAssetStatus -BearerTokenHeader $bearerTokenHeader -ProjectId $projectId -AssetId $asset.Id -LCSAPI $connectedServiceEndpoint.Data.apiurl

			if ($status.DisplayStatus -eq "Unknown")
			{
				Write-Host "Validation Status: Not Started"
				Start-Sleep -Seconds 240
			}
			else
			{
				Write-Host "Validation Status: $($status.DisplayStatus)"
			}
        }
        while (($status.DisplayStatus -eq "Process") -or ($status.DisplayStatus -eq "Unknown"))

        # Only report success if status shows completed
        if ($status.DisplayStatus -eq "Done")
        {
            Write-Host "Successfully uploaded validated asset '$($asset.Id)'"
        }
        else
        {
            throw "Asset failed validation."
        }
    }
}
finally
{
    Trace-VstsLeavingInvocation $MyInvocation
}

# SIG # Begin signature block
# MIIoGwYJKoZIhvcNAQcCoIIoDDCCKAgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBy7VwbNraNzDz4
# fOUpkIlLlDMbXNWx+nnXMZFi1n+ENaCCDYUwggYDMIID66ADAgECAhMzAAAEA73V
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGewwghnoAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAQDvdWVXQ87GK0AAAAA
# BAMwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# LwYJKoZIhvcNAQkEMSIEINIAJcC1HNP9bDLg5rUyGJrEgf66TrGO9gM1Zl36MowC
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEASTWWaLyErL6w
# T4w/Nrc4n+ye9HF6FIGlAVuyf1i9Qsv2m0tTulo0F7iszn4R/lXe25WbyqcTzlDQ
# NthXRN5DPZI42K2KWSZqCwoSYAbJ1W8ARN5L9TcL/GwUQtbEWvGWn1AQaiYJqAQp
# UDjwzBNlg19INxJXElBymEyE3RNI4luXRtEUH97VvAjhGJoWnOgDwi5cFUSsBZhh
# zySRV3WxOtc73X/GV48wAQDwa87TCgmCmy5pWF4JvQ4YqmQp1vsyyxHzzA9AajM7
# vlFG4M9raKUMGy20TDpqBq4AqSIjKg3JSp1C99QNAn8nq63RhrxQpF95gkQe87Hf
# tSAlifBEUKGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCC
# F20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEE
# ggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDKbHf396D9
# I8uXE8knmjm0FyBHw6rPN3nNQEnyuJ1VMwIGZ/gcXNqSGBMyMDI1MDQxODAwMTkx
# Mi4xODhaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046MzcwMy0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIB
# AgITMwAAAgpHshTZ7rKzDwABAAACCjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNTdaFw0yNjA0MjIxOTQy
# NTdaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046MzcwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCy7NzwEpb7BpwAk9LJ00Xq30TcTjcwNZ80TxAtAbhSaJ2kwnJA1Au/Do9/fEBj
# AHv6Mmtt3fmPDeIJnQ7VBeIq8RcfjcjrbPIg3wA5v5MQflPNSBNOvcXRP+fZnAy0
# ELDzfnJHnCkZNsQUZ7GF7LxULTKOYY2YJw4TrmcHohkY6DjCZyxhqmGQwwdbjoPW
# RbYu/ozFem/yfJPyjVBql1068bcVh58A8c5CD6TWN/L3u+Ny+7O8+Dver6qBT44E
# y7pfPZMZ1Hi7yvCLv5LGzSB6o2OD5GIZy7z4kh8UYHdzjn9Wx+QZ2233SJQKtZhp
# I7uHf3oMTg0zanQfz7mgudefmGBrQEg1ox3n+3Tizh0D9zVmNQP9sFjsPQtNGZ9I
# D9H8A+kFInx4mrSxA2SyGMOQcxlGM30ktIKM3iqCuFEU9CHVMpN94/1fl4T6PonJ
# +/oWJqFlatYuMKv2Z8uiprnFcAxCpOsDIVBO9K1vHeAMiQQUlcE9CD536I1YLnmO
# 2qHagPPmXhdOGrHUnCUtop21elukHh75q/5zH+OnNekp5udpjQNZCviYAZdHsLnk
# U0NfUAr6r1UqDcSq1yf5RiwimB8SjsdmHll4gPjmqVi0/rmnM1oAEQm3PyWcTQQi
# bYLiuKN7Y4io5bJTVwm+vRRbpJ5UL/D33C//7qnHbeoWBQIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFAKvF0EEj4AyPfY8W/qrsAvftZwkMB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQCwk3PW0CyjOaqXCMOusTde7ep2CwP/xV1J3o9KAiKSdq8a2UR5RCHY
# hnJseemweMUH2kNefpnAh2Bn8H2opDztDJkj8OYRd/KQysE12NwaY3KOwAW8Rg8O
# dXv5fUZIsOWgprkCQM0VoFHdXYExkJN3EzBbUCUw3yb4gAFPK56T+6cPpI8MJLJC
# QXHNMgti2QZhX9KkfRAffFYMFcpsbI+oziC5Brrk3361cJFHhgEJR0J42nqZTGSg
# UpDGHSZARGqNcAV5h+OQDLeF2p3URx/P6McUg1nJ2gMPYBsD+bwd9B0c/XIZ9Mt3
# ujlELPpkijjCdSZxhzu2M3SZWJr57uY+FC+LspvIOH1Opofanh3JGDosNcAEu9yU
# MWKsEBMngD6VWQSQYZ6X9F80zCoeZwTq0i9AujnYzzx5W2fEgZejRu6K1GCASmzt
# NlYJlACjqafWRofTqkJhV/J2v97X3ruDvfpuOuQoUtVAwXrDsG2NOBuvVso5KdW5
# 4hBSsz/4+ORB4qLnq4/GNtajUHorKRKHGOgFo8DKaXG+UNANwhGNxHbILSa59PxE
# xMgCjBRP3828yGKsquSEzzLNWnz5af9ZmeH4809fwIttI41JkuiY9X6hmMmLYv8O
# Y34vvOK+zyxkS+9BULVAP6gt+yaHaBlrln8Gi4/dBr2y6Srr/56g0DCCB3EwggVZ
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
# Yn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNNMIICNQIBATCB+aGB0aSB
# zjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UE
# CxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOjM3MDMtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQDRAMVJlA6bKq93Vnu3UkJg
# m5HlYaCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBCwUAAgUA66vUvjAiGA8yMDI1MDQxNzE5Mjc1OFoYDzIwMjUwNDE4MTky
# NzU4WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDrq9S+AgEAMAcCAQACAjT+MAcC
# AQACAhqoMAoCBQDrrSY+AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAFJ5
# PtNDa4aB1G6rj4bSpX2iIjyArwHqYz+Smk9kYsm4RUpwGh2vIQNef8NNAJRkJzLa
# zrCDWybLfHbZcGuF5AXhlpLXlUZou58MwnsLR9UNgnJyvZy+gjQXqWiMdBVOlYfa
# S42HMg0EBfmhfX0e59qpNImgXcHxnIyoXj0CqAOqnw13cadbVrdP6NiUjXNvrIUj
# Dclm/QvlZpGVanzLWuRU/kunB5mqiXbkEGxAZYEZtNtxuQq/5NkjP0/TxCUnF697
# U7RIG8Gv4vv+2GRitY40cZuvHowr1yjB/WFF9XDhj0kclFUZRzSs8RF6lZOojC4h
# 3jADiKhtVy3bcHql8fUxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMAITMwAAAgpHshTZ7rKzDwABAAACCjANBglghkgBZQMEAgEFAKCC
# AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCAQ
# Hs7ZB+hk7TtabJxJ8h27h6YBKI8yT69yqyWViCzA9zCB+gYLKoZIhvcNAQkQAi8x
# geowgecwgeQwgb0EIE2ay/y0epK/X3Z03KTcloqE8u9IXRtdO7Mex0hw9+SaMIGY
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIKR7IU2e6y
# sw8AAQAAAgowIgQgDRaK3Ohk+Zwm39fM3jBl2Cf6gN1erFkhdc9QLdvsApgwDQYJ
# KoZIhvcNAQELBQAEggIAmoxzxDzbjLDJ4UqGGTfuhkBMX6OfR3LwlOwTfdrXGUnx
# zd6ZY4am+pRzaoDHmRMwmn9VW2GgBjku+PoWcBR5L7Lr72Xk6dNBPI5wXMryjLiE
# jQ5Awl4L/hCGFkUeXyijFnEcF48p1y4Qot/eardUIVVNERufxmDnUQkBjPxiMX5H
# ZDh2WMFRKgo7Lt7V6eIkZ72oMiGwwWwU48Gwrssr6VL0hDR1rEZAR6J2zWde1JOz
# uRBEjhQRDoVKiX5/RlrceAS8FrjeFyUdiRFwE1M3EG+h7Wh0PKkYnzpDCde4kVSO
# hjrgHbroMmSCjyGNE9hMUDQUeIgx4oy3fStcjyTwaKLc+itFxxOVASQ2Pi6pjFtA
# j5QOjOS3xBIQK3dMnUZBKKCaZRPkesnPyLUS3FZWZwH6ThNSn260PnT8u/MdV3TU
# 9myDAk1Z24wmGdbY7YqkqYcg05rXXlBvPUms749iHaiNcSL4T0iuvEpaUmFfQKMR
# sKwQzO5iMxPmFMLYTKfjNbJC4imlp4dEJATVCykmKM+/HxaIkjrepjrH50rQv1Q3
# o8JOnWkbcE0UmNDvOl4ucEM/1xzoGIiyFVNsnKp+/pKtRUCBCNdocQghkJdCOvYP
# ga3juAZpCEEKOEGWGVq7Ef1rPigyGR41FTeFTjyC8oEXd6jxMeeFeBEMmKO0rSQ=
# SIG # End signature block
