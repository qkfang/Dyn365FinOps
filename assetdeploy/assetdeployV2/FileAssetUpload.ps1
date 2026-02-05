<#
.SYNOPSIS
    Import this module to get functions to handle file uploads to the asset library.
    
.DESCRIPTION
    This script can be imported to enable cmdlets to create a file asset, upload to blob storage,
    and commit the file asset to the asset library.

.NOTES
    This library depends on the Azure PowerShell module "AzureRM". It handles different versions
    of the dependencies it has to Azure Storage. Attempt is made to install specific components if not present.

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
# MIIoHQYJKoZIhvcNAQcCoIIoDjCCKAoCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDD2yDL/RLKF735
# WU1c/teqxT/2SgxpaB+K+doLlZYYS6CCDYUwggYDMIID66ADAgECAhMzAAAEA73V
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGe4wghnqAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAQDvdWVXQ87GK0AAAAA
# BAMwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# LwYJKoZIhvcNAQkEMSIEIKVhjVf367SBCstq+ElC+J9jImXt5fY+wVfAj5ldImMl
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAjmIw7PJ7Yu3K
# 6YJ07yg04oLNWbIxSvwPugnSGoOyQ8vzRu50qENgleaoLZsBdwemY/0eqfVEFqiS
# lR1haG0sgbcNwgkMcj5AboSq4tzkRjGNSzETRvf7sKUAHb7EZHelms5e4Yhq8qtp
# LBqrvpZ5EfrUTKEmuEH0RevfyWEyNsi1Fj7kgDfFRzDDTSEoMJ7X4SxupWTqLP71
# lE8SL46cscz6eu/cPUlI92LHGvdcxw6o9t36nL2b4HsDug24COdfxp1g/cihgaey
# +htn5G40Udr6N3e7qK4XXJz/ACWvGgktkz/XDtJHXPLCyAl6zkbB0DsJhpNXwAZe
# uaqb181lIaGCF5YwgheSBgorBgEEAYI3AwMBMYIXgjCCF34GCSqGSIb3DQEHAqCC
# F28wghdrAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFRBgsqhkiG9w0BCRABBKCCAUAE
# ggE8MIIBOAIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBp9yCI3Ing
# b/rbIS+DSy0VABATGzadLmMpWo+GCwnVyAIGZ/hMBOygGBIyMDI1MDQxODAwMjAx
# NS40N1owBIACAfSggdGkgc4wgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMx
# JzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMzAzLTA1RTAtRDk0NzElMCMGA1UE
# AxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEe0wggcgMIIFCKADAgEC
# AhMzAAACD1eaRxRA5kbmAAEAAAIPMA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYT
# AlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI1MDEzMDE5NDMwNFoXDTI2MDQyMjE5NDMw
# NFowgcsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNV
# BAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjozMzAzLTA1RTAtRDk0NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRp
# bWUtU3RhbXAgU2VydmljZTCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIB
# AKXoNO6vF/rqjvcbQDbIqjX+di8hMFCx3nQXnZJDOjZxKu34QMQUIOVLFnNYkPu6
# NDVnV0xsxPpiErslS/DFD4uRBe/aT/e/fHDzEnaaFe7BtP6zVY4vT72D0A4QAAzp
# YaMLMj8tmrf+3MevnqKf9n76j/aygaHIaEowPBaXgngvUWfyd22gzVIGJs92qbCY
# 9ekH1C1o/5MI4LW8BoZA52ypdDwB2UrpW6T3Jb23LtLSRE/WdeQWx4zfc3MG7/+5
# tqgkdvVx5g9nhTgQ5cEeL/aDT1ZEv1BYi0eM8YliO4nRyTKs4bWSx8BlY/4G7w9c
# CrizUFr+H+deFcDC7FOGm9oVvhPRs6Ng7+HYs9Ft0Mxwx9L1luGrXSFc/pkUdHRF
# En6uvkDwgP2XRSChS7+A28KocIyjDP3u52jt5Y4MDstpW/zUUcdjDdfkNJNSonqn
# A/7/SXFq3FqNtIaybbrvOpU2y7NSgXYXM8z5hQjCI6mBC++NggGQH4pTBl/a9Eg9
# aaEATNZkAZOjH/S+Ph4eDHARH1+lOFyxtkZLHHScvngfP4vfoonIRWKj6glW9TGb
# vlgQRJpOHVGcvQOWz3WwHDqa8qs7Y740JtS1/H5xBdhLQlxZl5/zXQFb0Gf94i+j
# DcpzHR1W6oN8hZ9buKZ5MsAr1AAST6hkInNRRO+GHaFhAgMBAAGjggFJMIIBRTAd
# BgNVHQ4EFgQUmdQxDY63ICEtH8wPaq0n2UpE/1kwHwYDVR0jBBgwFoAUn6cVXQBe
# Yl2D9OXSZacbUzUZ6XIwXwYDVR0fBFgwVjBUoFKgUIZOaHR0cDovL3d3dy5taWNy
# b3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3JsMGwGCCsGAQUFBwEBBGAwXjBcBggrBgEFBQcwAoZQaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBU
# aW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcnQwDAYDVR0TAQH/BAIwADAWBgNV
# HSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMCB4AwDQYJKoZIhvcNAQEL
# BQADggIBAFOjBujVtQTt9dPL65b2bnyoYRdEEZUwRCIUR9K6LV+E3uNL6RKI3RJH
# kqXcC5Xj3E7GAej34Yid7kymDmfg1Lk9bydYhYaP/yOQTel0llK8BlqtcPiXjeIw
# 3EOF0FmpUKQBhx0VVmfF3L7bkxFjpF9obCSKeOdg0UDoNgv/VzHDphrixfJXsWA9
# 0ybFWl9+c8QMW/iZxXHeO89mh3uCqINxQdvJXWBo0Pc96PInUwZ8FhsBDGzKctfU
# VSxYvAqw09EmPKfCXMFP85BvGfOSMuJuLiHh07Bw34fibIO1RKdir1d/hi8WVn6Y
# mzli3HhT0lULJb9YRG0gSJ5O9NGC8BiP/gyHUXYSV/xx0guDOL17Oph5/F2wEPxW
# LHfnIwLktOcNSjJVW6VR54MAljz7pgFu1ci3LimEiSKGIgezJZXFbZgYboDpRZ6e
# 7BjrP2gE428weWq0PftnIufSHWQKSSnmRwgiEy2nMRw+R+qWRsNWiAyhbLzTG6XG
# 3rg/j7VgjORGG3fNM76Ms427WmYG37wRSHsNVy3/fe25bk05LHnqNdDVN050UGmB
# xbwe8mKLyyZDVNA/jYc0gogljlqIyQr0zYejFitDLYygc04/JKw7OveV7/hIN1fr
# u6hsaRQ16uUkrMqlNHllTRJ40C7mgLINvqB21OJo3nSUILqbjixeMIIHcTCCBVmg
# AwIBAgITMwAAABXF52ueAptJmQAAAAAAFTANBgkqhkiG9w0BAQsFADCBiDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWljcm9z
# b2Z0IFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9yaXR5IDIwMTAwHhcNMjEwOTMwMTgy
# MjI1WhcNMzAwOTMwMTgzMjI1WjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAx
# MDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBAOThpkzntHIhC3miy9ck
# eb0O1YLT/e6cBwfSqWxOdcjKNVf2AX9sSuDivbk+F2Az/1xPx2b3lVNxWuJ+Slr+
# uDZnhUYjDLWNE893MsAQGOhgfWpSg0S3po5GawcU88V29YZQ3MFEyHFcUTE3oAo4
# bo3t1w/YJlN8OWECesSq/XJprx2rrPY2vjUmZNqYO7oaezOtgFt+jBAcnVL+tuhi
# JdxqD89d9P6OU8/W7IVWTe/dvI2k45GPsjksUZzpcGkNyjYtcI4xyDUoveO0hyTD
# 4MmPfrVUj9z6BVWYbWg7mka97aSueik3rMvrg0XnRm7KMtXAhjBcTyziYrLNueKN
# iOSWrAFKu75xqRdbZ2De+JKRHh09/SDPc31BmkZ1zcRfNN0Sidb9pSB9fvzZnkXf
# tnIv231fgLrbqn427DZM9ituqBJR6L8FA6PRc6ZNN3SUHDSCD/AQ8rdHGO2n6Jl8
# P0zbr17C89XYcz1DTsEzOUyOArxCaC4Q6oRRRuLRvWoYWmEBc8pnol7XKHYC4jMY
# ctenIPDC+hIK12NvDMk2ZItboKaDIV1fMHSRlJTYuVD5C4lh8zYGNRiER9vcG9H9
# stQcxWv2XFJRXRLbJbqvUAV6bMURHXLvjflSxIUXk8A8FdsaN8cIFRg/eKtFtvUe
# h17aj54WcmnGrnu3tz5q4i6tAgMBAAGjggHdMIIB2TASBgkrBgEEAYI3FQEEBQID
# AQABMCMGCSsGAQQBgjcVAgQWBBQqp1L+ZMSavoKRPEY1Kc8Q/y8E7jAdBgNVHQ4E
# FgQUn6cVXQBeYl2D9OXSZacbUzUZ6XIwXAYDVR0gBFUwUzBRBgwrBgEEAYI3TIN9
# AQEwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9w
# cy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUFBwMIMBkGCSsG
# AQQBgjcUAgQMHgoAUwB1AGIAQwBBMAsGA1UdDwQEAwIBhjAPBgNVHRMBAf8EBTAD
# AQH/MB8GA1UdIwQYMBaAFNX2VsuP6KJcYmjRPZSQW9fOmhjEMFYGA1UdHwRPME0w
# S6BJoEeGRWh0dHA6Ly9jcmwubWljcm9zb2Z0LmNvbS9wa2kvY3JsL3Byb2R1Y3Rz
# L01pY1Jvb0NlckF1dF8yMDEwLTA2LTIzLmNybDBaBggrBgEFBQcBAQROMEwwSgYI
# KwYBBQUHMAKGPmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2kvY2VydHMvTWlj
# Um9vQ2VyQXV0XzIwMTAtMDYtMjMuY3J0MA0GCSqGSIb3DQEBCwUAA4ICAQCdVX38
# Kq3hLB9nATEkW+Geckv8qW/qXBS2Pk5HZHixBpOXPTEztTnXwnE2P9pkbHzQdTlt
# uw8x5MKP+2zRoZQYIu7pZmc6U03dmLq2HnjYNi6cqYJWAAOwBb6J6Gngugnue99q
# b74py27YP0h1AdkY3m2CDPVtI1TkeFN1JFe53Z/zjj3G82jfZfakVqr3lbYoVSfQ
# JL1AoL8ZthISEV09J+BAljis9/kpicO8F7BUhUKz/AyeixmJ5/ALaoHCgRlCGVJ1
# ijbCHcNhcy4sa3tuPywJeBTpkbKpW99Jo3QMvOyRgNI95ko+ZjtPu4b6MhrZlvSP
# 9pEB9s7GdP32THJvEKt1MMU0sHrYUP4KWN1APMdUbZ1jdEgssU5HLcEUBHG/ZPkk
# vnNtyo4JvbMBV0lUZNlz138eW0QBjloZkWsNn6Qo3GcZKCS6OEuabvshVGtqRRFH
# qfG3rsjoiV5PndLQTHa1V1QJsWkBRH58oWFsc/4Ku+xBZj1p/cvBQUl+fpO+y/g7
# 5LcVv7TOPqUxUYS8vwLBgqJ7Fx0ViY1w/ue10CgaiQuPNtq6TPmb/wrpNPgkNWcr
# 4A245oyZ1uEi6vAnQj0llOZ0dFtq0Z4+7X6gMTN9vMvpe784cETRkPHIqzqKOghi
# f9lwY1NNje6CbaUFEMFxBmoQtB1VM1izoXBm8qGCA1AwggI4AgEBMIH5oYHRpIHO
# MIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMH
# UmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQL
# ExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxk
# IFRTUyBFU046MzMwMy0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFNlcnZpY2WiIwoBATAHBgUrDgMCGgMVAF60jOPYL8yR2IjTcTI2wK1I
# 4x1aoIGDMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24x
# EDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlv
# bjEmMCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTAwDQYJKoZI
# hvcNAQELBQACBQDrrARsMCIYDzIwMjUwNDE3MjI1MTI0WhgPMjAyNTA0MTgyMjUx
# MjRaMHcwPQYKKwYBBAGEWQoEATEvMC0wCgIFAOusBGwCAQAwCgIBAAICFBgCAf8w
# BwIBAAICEicwCgIFAOutVewCAQAwNgYKKwYBBAGEWQoEAjEoMCYwDAYKKwYBBAGE
# WQoDAqAKMAgCAQACAwehIKEKMAgCAQACAwGGoDANBgkqhkiG9w0BAQsFAAOCAQEA
# gaNN+N41ZzHJQ+BjmSh1qrXT5ZREcl8UoKWKFEkC2coqkCeI+stz9qR6T8mQzabq
# ehEGqGjqzLU/MLw6buLW0VzAnk+JBMzNAoHpnOUoMxqVWDvRgWxi9+oUNM3WSQf7
# Cs2ZeKhDBq+KXxBfifzqtCfSKdjev4lpZi2IcgPbdq+aQgVVCNWkGabxzEAkaHyJ
# EIuY9VeoXFrjOhH/7X9kxaVhwqm8QQhTqq+JQfFtIQQ29wuEfNW0pHjR1XfzGjYN
# 9rdyKH5Ak/1T1hl4VTlxmu6T92xYHF78PrsIB8NkXCek/iYr1Yz+MS4/dVDnQf+h
# vLNngyobUuI54u2hKBxr2TGCBA0wggQJAgEBMIGTMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwAhMzAAACD1eaRxRA5kbmAAEAAAIPMA0GCWCGSAFlAwQCAQUA
# oIIBSjAaBgkqhkiG9w0BCQMxDQYLKoZIhvcNAQkQAQQwLwYJKoZIhvcNAQkEMSIE
# IKOJopqHbI5q/CihSy/kLjx7B3sKbxp8ROaFO72FwU0AMIH6BgsqhkiG9w0BCRAC
# LzGB6jCB5zCB5DCBvQQg3Ud3lSYqebsVbvE/eeIax8cm3jFHxe74zGBddzSKqfgw
# gZgwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4G
# A1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYw
# JAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAAAg9XmkcU
# QOZG5gABAAACDzAiBCCb3E1vVGiKfungfq6M/vg7U7BuAddUanm2GCGnPcYU9DAN
# BgkqhkiG9w0BAQsFAASCAgBHOUKzQbnz5MN4pa4c2YIX+bQpNA2iQrFHuXMVNC1S
# DQs7GWkGz120zNDhOsn1Qvdbp3MoorgYcjNBkoW9andLiwx/+3PfoKf4p8uoO4oR
# fTa9YZjyV52kTDOVlaRhftV8OzTlTdqpSbiGM3jMYqNlbsApMbn+ybCLIJG4X7Su
# dOBfFjgimwT1o+PV8OKWf4jFze+wg3se6MMSC09upLy0+xPL2vkhSBIkyCpcCu5d
# YbmcUTXwpOE9W+KuhNr0HKZmb/7vLiu7DxtVoVyjUnDXbGt7q7i25AFlj8YOmvYM
# YxzdV3g4s0s9na+KHYrTZNCCsPbUVS05I7EfkcNCi2PtqfWatEP7yy5rk6iUCP1g
# ssgwQFEkPHvprpgykK06piyzE5WOavjuXY2blesWtCME2IstiOnag0/ovgMu/nTY
# +gYeBfYal1xCcf8x4+T1CtK5HTkQKhGstrYrV/peS+JQ+Sp1mlyNRHyCcl+hs8HP
# 2Rdfvkavv254HZ9ClDxoEhhwh3B3+/CyKJRFjVN2p+TPgW6z0FL1k5SGV0ABsmQM
# nxJJpx9HlgUWkj8IeHYg8LbcEpv6tHU2ME/cTx034zkosCbwKiU3qiJ1jC+TBZO7
# FY74hwk6BBJcOiDesIV/AWiUp4f8XZ/4KzYrftx4UNCbi/W6FH8lQqkI23cUZJYW
# Xg==
# SIG # End signature block
