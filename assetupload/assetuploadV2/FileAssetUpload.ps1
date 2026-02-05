<#
.SYNOPSIS
    Import this module to get functions to handle file uploads to the asset library.
    
.DESCRIPTION
    This script can be imported to enable cmdlets to create a file asset, upload to blob storage,
    and commit the file asset to the asset library.

.NOTES
    This library depends on the Azure PowerShell module "Az". It handles the dependencies it has to 
    Azure Storage. Attempt is made to install specific components if not present.

    This library also depends on RESTHelpers.ps1

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
    Make REST API call to Dynamics Lifecycle Services to create a new file asset, and return the file asset object
#>
function New-LCSFileAsset
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="Asset type")]
        [int]$FileType,
        [Parameter(Mandatory=$true, HelpMessage="Full file path of the asset to upload")]
        [string]$FilePath,
        [Parameter(Mandatory=$false, HelpMessage="Name for the new asset, defaults to the filename")]
        [string]$AssetName,
        [Parameter(Mandatory=$false, HelpMessage="Optional description for the asset")]
        [string]$AssetDescription,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )

    $fileName = Split-Path $FilePath -Leaf
    if (!$AssetName)
    {
        $AssetName = $fileName
    }
    if (!$AssetDescription)
    {
        $jsonAssetDescription = "null"
    }
    else
    {
        $jsonAssetDescription = "`"$AssetDescription`""
    }

    $fileAssetJson = "{ `"Name`": `"$AssetName`", `"FileName`": `"$fileName`", `"FileDescription`": $jsonAssetDescription, `"SizeByte`": 0, `"FileType`": $FileType }"

    $client = New-HttpClient

    $createFileAssetUri = "$LCSAPI/box/fileasset/CreateFileAsset/$ProjectId"

    $request = New-JsonRequestMessage -Uri $createFileAssetUri -Content $fileAssetJson -BearerTokenHeader $BearerTokenHeader

    $result = Get-AsyncResult -task $client.SendAsync($request)
    
    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $asset = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if (($asset) -and ($asset.Message))
        {
            throw "Error creating new file asset: '$($asset.Message)'"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    } 

    $asset = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if (!($asset.Id))
    {
        if ($asset.Message)
        {
            throw "Error creating new file asset: '$($asset.Message)'"
        }
        else
        {
            throw "Unknown error creating new file asset"
        }
    }

    return $asset
}

<#
.SYNOPSIS
    Upload file to blob storage URL returned by the Dynamics Lifecycle Services File Asset API
#>
function Send-FileToBlob
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Full file path of the asset to upload")]
        [string]$FilePath,
        [Parameter(Mandatory=$true, HelpMessage="Block blob URL to upload to")]
        [System.Uri]$BlockBlobUri
    )

    try
    {
        Import-Module Azure.Storage
        $cloudblob = New-Object -TypeName Microsoft.WindowsAzure.Storage.Blob.CloudBlockBlob -ArgumentList @($BlockBlobUri)
    }
    catch
    {
        Write-Host "retrying"
        #adding as one branch pipeline not recognizing this
        Install-Module -Name Azure.Storage -Scope CurrentUser -AllowCLobber -Force
        Import-Module Azure.Storage
        $cloudblob = New-Object -TypeName Microsoft.WindowsAzure.Storage.Blob.CloudBlockBlob -ArgumentList @($BlockBlobUri)
    }

    $version = Get-AssemblyVersion $cloudblob
    if ($version -ge "7.0.0.0")
    {
        # New versions of the Azure Blob Storage API only require the path to the file to upload
        $uploadResult = Get-AsyncResult -task $cloudblob.UploadFromFileAsync([System.String]$FilePath)
    }
    else
    {
        # Older versions of the Azure Blob Storage API also require the FileMode
        $uploadResult = Get-AsyncResult -task $cloudblob.UploadFromFileAsync([System.String]$FilePath, [System.IO.FileMode]::Open)
    }
}

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to commit the uploaded file asset
#>
function Confirm-FileAssetUpload
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$true, HelpMessage="The asset's ID in the asset library")]
        [string]$AssetId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI
    )
    
    $client = New-HttpClient

    $commitFileAssetUri = "$LCSAPI/box/fileasset/CommitFileAsset/$($ProjectId)?assetId=$AssetId"

    $request = New-JsonRequestMessage -Uri $commitFileAssetUri -BearerTokenHeader $BearerTokenHeader
    
    $commitResult = Get-AsyncResult -task $client.SendAsync($request)

    if (($commitResult.StatusCode -ne [System.Net.HttpStatusCode]::NoContent) -and ($commitResult.StatusCode -ne [System.Net.HttpStatusCode]::OK))
    {
        throw "API Call returned $($commitResult.StatusCode): $($commitResult.ReasonPhrase)"
    }

    return $commitResult
}

<#
.SYNOPSIS
    Make REST API call to Dynamics Lifecycle Services to get the status of a file asset
#>
function Get-LCSFileAssetStatus
{
    [Cmdletbinding()]
    param(
        [Parameter(Mandatory=$true, HelpMessage="Azure Active Directory authorization bearer token header")]
        [string]$BearerTokenHeader,
        [Parameter(Mandatory=$true, HelpMessage="Dynamics Lifecycle Services project ID")]
        [int]$ProjectId,
        [Parameter(Mandatory=$false, HelpMessage="ID of the asset to check")]
        [string]$AssetId,
        [Parameter(Mandatory=$false, HelpMessage="LCS API URL")]
        [string]$LCSAPI = "https://lcsapi.lcs.dynamics.com"
    )

    $client = New-HttpClient

    $createFileAssetUri = "$LCSAPI/box/fileasset/GetFileAssetValidationStatus/$($ProjectId)?assetId=$AssetId"

    $request = New-JsonRequestMessage -Uri $createFileAssetUri -BearerTokenHeader $BearerTokenHeader -HttpMethod ([System.Net.Http.HttpMethod]::Get)

    $result = Get-AsyncResult -task $client.SendAsync($request)
    
    if ($result.StatusCode -ne [System.Net.HttpStatusCode]::OK)
    {
        try
        {
            $asset = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json -ErrorAction SilentlyContinue
        }
        catch { }

        if (($asset) -and ($asset.Message))
        {
            throw "Error getting file asset status: '$($asset.Message)'"
        }
        else
        {
            throw "API Call returned $($result.StatusCode): $($result.ReasonPhrase)"
        }
    } 

    $asset = Get-AsyncResult -task $result.Content.ReadAsStringAsync() | ConvertFrom-Json

    if (!($asset.Id))
    {
        if ($asset.Message)
        {
            throw "Error getting file asset status: '$($asset.Message)'"
        }
        else
        {
            throw "Unknown error getting file asset status"
        }
    }

    return $asset
}
# SIG # Begin signature block
# MIIoDAYJKoZIhvcNAQcCoIIn/TCCJ/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCcV9kDTlV+TBtl
# QcdZMT3sBpyI5LaVBmsSbykocZCPh6CCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# ILNTXSLgs4pRdp3Uc4FSlMyIpC4DDQa57V7Wf0bm/k3UMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAkBSFl1QclhmCzQ8J8tTrsMcobXb2iGgR
# KHhq7IdjIK8tvEKtG5D3+7YD5vCLe2vhn/VAYVAqinNw7kc5CRxM2Yk/Oc5dxVW/
# gdXARda3VlE4sI5yJ/+tJ5p8KcINIHo5qXiK5DsWP9DYvzxzmQNlVW7ePb2xJAnI
# MkT06nTt6B7c6vGUt1DTomg81plmzELu2DxUfTP9+dh5QOrIJTd/s+af/s8W9znO
# avtW/HsogZO9I/SdWEflQf0uxjEuUk1KVxJ1jicEAx/Sx8fgrOt2RPk+wjww//UV
# Y2K0Jl2AjewHDVXAmRF18SzZb7JOe3O2V8X9rJiNrCD/j/g6LWLgWaGCF5QwgheQ
# BgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDKlSPPc9eo2gUJzcCVC/F6UeBXru6a
# nC5elNJ9MNCMwwIGZ/fVkqEwGBMyMDI1MDQxODAwMjAxNS42NjRaMASAAgH0oIHR
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
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBZn8y/iG5+7VdPrMZWhpBV
# AMyJPx61huxBwUjiwXk4/DCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EII//
# jm8JHa2W1O9778t9+Ft2Z5NmKqttPk6Q+9RRpmepMIGYMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIIeJ1YXZLH2VIAAQAAAggwIgQg4TnI
# KP+IV/R8in9i4lsy3mMQAxN6dnWjyETrR7GyAi0wDQYJKoZIhvcNAQELBQAEggIA
# K6EIwlxAwN5tbwDnT+ZyTBB+58FbJbs0XjJbjcdOXjxs73ITsbBWySLgCuXZDPHL
# o//dETdYVmXi0BAKaophyrH/m1LV4j/GnLgs67buv/3RQJdQZPFQE5yUjYdw9j+N
# dsEioMLmKlBvA0nNlKrWbVV/ezz/rK25o2/MLRn3hqx7pX14Nayv2+WhW7/AlpKa
# UbMx1MbMrByPSoSSREfmjR2snrnl+yjzfpmLet+uINTs0O6V2YMG9bR8sscGgQGq
# 6iGsOZkIkQdOX7okL01eJw1k5c6CWeCGVvRr5FuNXb+oNCci2g2B7cygEtBDs0eH
# 1SdwXG5unaGXPmsTl3pDbVJ47WGGk/uP8ZnS0mT+zna0YZ3wtvuWcSugZ8tPOakU
# PNGTfDCi0RWjL7YqfyHn87OGxKno9lzAJbGSvlUALGzSmJpBPzWhJ8C7ZsKRLjPj
# +LfJvYFCM5veSJY+bE9bTTOU9EhitO6CmSLIoxHik7SjKosWVxEBCf+yIHSS81WS
# fbt6i1duGZZUn0PIa2aD6BxNhIQ65X6csCbfqcXr6cBj98DQHVXBapQPPQVtuljV
# bBxUmr5R/bldStSBBLHY9juBKSvdn+BSH5OWXzRptJcaXDr62K08jObp8m0paROH
# EJ72v8F/rrBaFDqmSB0JBiikp8Rq9R5xyt8OnBXAoQE=
# SIG # End signature block
