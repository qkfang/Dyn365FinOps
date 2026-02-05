<#
.SYNOPSIS
    This file calls the packaging scripts and assemblies to produce a deployable package from X++ binaries
    
    Copyright © 2019 Microsoft. All rights reserved.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Trace-VstsEnteringInvocation $MyInvocation
try
{

    $xppToolsPath = Get-VstsInput -Name "XppToolsPath" -Require
    $xppBinPath = Get-VstsInput -Name "XppBinariesPath" -Require
    $xppBinSearch = Get-VstsInput -Name "XppBinariesSearch" -Default "*"
    if ($xppBinSearch.Contains("`n"))
    {
        [string[]]$xppBinSearch = $xppBinSearch -split "`n"
    }
    $deployablePackagePath = Get-VstsInput -Name "DeployablePackagePath" -Require

    
    Assert-VstsPath -LiteralPath $xppToolsPath -PathType Container
    Assert-VstsPath -LiteralPath $xppBinPath -PathType Container

    $potentialPackages = Find-VstsMatch -DefaultRoot $xppBinPath -Pattern $xppBinSearch | Where-Object { (Test-Path -LiteralPath $_ -PathType Container) }
    $leafFolderNames = $potentialPackages | ForEach-Object { [System.IO.Path]::GetFileName($_) }
    $duplicateFolders = $leafFolderNames | Group-Object | Where-Object { $_.Count -gt 1 }
    if ($duplicateFolders)
    {
        try
        {
            Write-Host $($potentialPackages -join "`n")
        }
        catch{}
        throw "Multiple entries with the same module folder name detected. Please modify the 'Search Pattern' field to ensure unique packages to avoid issues. Refer: https://go.microsoft.com/fwlink/?linkid=2128586#examples-of-search-patterns"
    }

    $packages = @()
    if ($potentialPackages.Length -gt 0)
    {
        Write-Host "Found $($potentialPackages.Length) potential folders to include:"
        foreach($package in $potentialPackages)
        {
            $packageBinPath = Join-Path -Path $package -ChildPath "bin"
            # If there is a bin folder and it contains *.MD files, assume it's a valid X++ binary
            if ((Test-Path -Path $packageBinPath) -and ((Get-ChildItem -Path $packageBinPath -Filter *.md).Count -gt 0))
            {
                Write-Host "  - $package"
                $packages += $package
            }
            else
            {
                Write-Warning "  - $package (not an X++ binary folder, skipped)"
            }
        }

        $createRegularPackage = Get-VstsInput -Name "CreateRegularPackage" -Require
        $createCloudPackage = Get-VstsInput -Name "CreateCloudPackage" -Require
        if ($createRegularPackage -eq "true")
        {
            $artifactDirectory = [System.IO.Path]::GetDirectoryName($deployablePackagePath)
        }
        else
        {
            if ($createCloudPackage -eq "true")
            {
                $tempPathForCloudPackage = [System.IO.Path]::GetTempPath()
                $artifactDirectory = Join-Path -Path $tempPathForCloudPackage -ChildPath ((New-Guid).ToString())
                Write-Host "Using temporary base directory path: $artifactDirectory"
            }
            else # no option selected
            {
                Write-Host "No package type selected exiting."
                continue
            }
        }


        if (!(Test-Path -Path $artifactDirectory))
        {
            # The reason to use System.IO.Directory.CreateDirectory is it creates any directories missing in the whole path
            # whereas New-Item would only create the top level directory
            [System.IO.Directory]::CreateDirectory($artifactDirectory)
        }

        Import-Module (Join-Path -Path $xppToolsPath -ChildPath "CreatePackage.psm1")
        $outputDir = Join-Path -Path $artifactDirectory -ChildPath ((New-Guid).ToString())
        $tempCombinedPackage = Join-Path -Path $artifactDirectory -ChildPath "$((New-Guid).ToString()).zip"
        try
        {
            New-Item -Path $outputDir -ItemType Directory > $null

            Write-Host "Creating binary packages"
            foreach($packagePath in $packages)
            {
                $packageName = (Get-Item $packagePath).Name
                Write-Host "  - '$packageName'"

                $version = ""
                $packageDll = Join-Path -Path $packagePath -ChildPath "bin\Dynamics.AX.$packageName.dll"
                if (Test-Path $packageDll)
                {
                    $version = (Get-Item $packageDll).VersionInfo.FileVersion
                }
                
                if (!$version)
                {
                    $version = "1.0.0.0"
                }

                New-XppRuntimePackage -packageName $packageName -packageDrop $packagePath -outputDir $outputDir -metadataDir $xppBinPath -packageVersion $version -binDir $xppToolsPath -enforceVersionCheck $True
            }
            if($createRegularPackage -eq "true")
            {
                try
                {
                    Write-Host "Creating deployable package"
                    Add-Type -Path "$xppToolsPath\Microsoft.Dynamics.AXCreateDeployablePackageBase.dll"
                    Write-Host "  - Creating combined metadata package"
                    [Microsoft.Dynamics.AXCreateDeployablePackageBase.BuildDeployablePackages]::CreateMetadataPackage($outputDir, $tempCombinedPackage)
                    Write-Host "  - Creating merged deployable package"
                    [Microsoft.Dynamics.AXCreateDeployablePackageBase.BuildDeployablePackages]::MergePackage("$xppToolsPath\BaseMetadataDeployablePackage.zip", $tempCombinedPackage, $deployablePackagePath, $true, [String]::Empty)              
                }
                catch
                {
                    Write-Host "Error Occured"
                    Write-Host $_
                    Write-Host $_.Exception
                    throw $_.Exception
                }

                Write-Host "Deployable package '$deployablePackagePath' successfully created."
            }

            if ($createCloudPackage -eq "true")
            {
                if($packages.Count -eq 0)
                {
                    throw "No valid X++ binary package(s) found. Exiting."
                }
                # include $packages that match pattern in a folder and send that folder to library
                $tempPathForCloudPackage = [System.IO.Path]::GetTempPath()
                $tempDirRoot = Join-Path -Path $tempPathForCloudPackage -ChildPath ((New-Guid).ToString())
                New-Item -Path $tempDirRoot -ItemType Directory > $null
                $copyDir = [System.IO.Path]::Combine($outputDir, "files")

                # Define regex patterns
                $regexInit = [System.Text.RegularExpressions.Regex]::new("dynamicsax-(.+?)(?=\.\d+\.\d+\.\d+\.\d+$)")

                # Process each zip file in the directory
                $ziplist = Get-ChildItem -Path $copyDir -Filter "*.zip"
                foreach ($zipFileentry in $ziplist) 
                {
                    $modelZipFile = $zipFileentry.FullName
                    $modelDirNewName = [System.IO.Path]::GetFileNameWithoutExtension($modelZipFile) # rename pattern: dynamicsax-fleetmanagement.7.0.5030.16453
                    $modelOrgDirName = $modelDirNewName
                    if ($modelDirNewName -match $regexInit) {
                        $modelDirNewName = $matches[1]
                        Write-Output $modelDirNewName
                    }
                    try 
                    {
                        $destinationPath = [System.IO.Path]::Combine($tempDirRoot, $modelDirNewName)
                        if (Test-Path -Path $destinationPath -PathType Container) 
                        {
                            throw [System.Exception]::new("Duplicate model directory: $modelOrgDirName")
                        }
                        else 
                        {
                            Expand-Archive -Path $modelZipFile -DestinationPath $destinationPath
                        }
                    }
                    catch 
                    {
                        Write-Host "Exception extracting: $modelZipFile"
                        Write-Host $_.Exception.Message
                        throw
                    }
                }

                $cloudPackagePlatVersion = Get-VstsInput -Name "CloudPackagePlatVersion" -Require
                $cloudPackageAppVersion = Get-VstsInput -Name "CloudPackageAppVersion" -Require
                $regexVersion = '^\d+\.\d+\.\d+\.\d+$'
                if ($cloudPackagePlatVersion -notmatch $regexVersion) 
                {
                    throw "Invalid platform version: $cloudPackagePlatVersion"
                }
                if ($cloudPackageAppVersion -notmatch $regexVersion) 
                {
                    throw "Invalid application version: $cloudPackageAppVersion"
                }

                $cloudPackageOutputLocation = Get-VstsInput -Name "CloudPackageOutputLocation" -Require
                if (!(Test-Path -Path $cloudPackageOutputLocation -PathType Container))
                {
                    # The reason to use System.IO.Directory.CreateDirectory is it creates any directories missing in the whole path
                    # whereas New-Item would only create the top level directory
                    [System.IO.Directory]::CreateDirectory($cloudPackageOutputLocation)
                    # remove the last folder since copy item createss it
                    Remove-Item -Path $cloudPackageOutputLocation -Recurse -Force
                }
            
                try
                {
                    Write-Host "Creating cloud runtime deployable package"
                    $PSVersionTable
                    Import-Module "$PSScriptRoot\CloudRuntimePackageCreation.ps1" -Force
                    Add-CloudRuntimeDeployablePackage -buildOutputLocation "$tempDirRoot" -platVersionNumber "$cloudPackagePlatVersion" -appVersionNumber "$cloudPackageAppVersion" -packageOutputLocation "$cloudPackageOutputLocation"
                }
                catch
                {
                    throw
                }
            }   
        }
        finally
        {
            if (($null -ne $outputDir) -and (Test-Path -Path $outputDir))
            {
                Remove-Item -Path $outputDir -Recurse -Force
            }
            if (($null -ne $tempCombinedPackage) -and (Test-Path -Path $tempCombinedPackage))
            {
                Remove-Item -Path $tempCombinedPackage -Force
            }
            if(($null -ne $tempDirRoot) -and (Test-Path -Path $tempDirRoot))
            {
                Remove-Item -Path $tempDirRoot -Recurse -Force
            }
        }
    }
    else
    {
        throw "No X++ binary package(s) found"
    }
}
finally
{
    Trace-VstsLeavingInvocation $MyInvocation
}
# SIG # Begin signature block
# MIIoDAYJKoZIhvcNAQcCoIIn/TCCJ/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCA7G2YC2WqeZTlA
# r3RXDpKcB4cP7i7syGXnF65Uc1yLOaCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IDJpgyhnXwwrem6YBIzz0cCylUY2C248H384OOfOjWOZMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAFR6No/0+f6xmw6ooCY7gG2lQenauq69T
# y8ErUC4/ks1iikosdac6CMZQi8BhDzBZSU3JWSKehfBEBfKnuQK8bU4FJhw4VHRo
# rvTL6qvdlmDdqp45g3q5lVsW0OTmtLcs02DquGcQvh6PeThNze8/guhP3pREDuTl
# nYz82HRiYXVbl6Egl4u3X+ceOe6K6NRjw9ROSOmVGvDWsuWOHLZu54grPZQOGTqP
# rSRTCVOLaJWbzBOjOvIFfChg7jbo1kxU95afI8k4cP6zsXn3WwwbqFFfjgTINTU+
# CgsI0gxpuVzOWOctDohltGcg64wgCxQ7zqdOT3U2i9TN3mwittUnqqGCF5QwgheQ
# BgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBYOvKja6EqncYNyDQStBRuXeDxCI2x
# eDcTmJM2Z94rBgIGZ/eupyOqGBMyMDI1MDQxODAwMjAxNi44NDVaMASAAgH0oIHR
# pIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046QTQwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIBAgITMwAAAgJ5UHQhFH24
# oQABAAACAjANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDAeFw0yNTAxMzAxOTQyNDRaFw0yNjA0MjIxOTQyNDRaMIHLMQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQg
# QW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046QTQw
# MC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZp
# Y2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQC3eSp6cucUGOkcPg4v
# KWKJfEQeshK2ZBsYU1tDWvQu6L9lp+dnqrajIdNeH1HN3oz3iiGoJWuN2HVNZkcO
# t38aWGebM0gUUOtPjuLhuO5d67YpQsHBJAWhcve/MVdoQPj1njiAjSiOrL8xFarF
# LI46RH8NeDhAPXcJpWn7AIzCyIjZOaJ2DWA+6QwNzwqjBgIpf1hWFwqHvPEedy0n
# otXbtWfT9vCSL9sdDK6K/HH9HsaY5wLmUUB7SfuLGo1OWEm6MJyG2jixqi9NyRoy
# pdF8dRyjWxKRl2JxwvbetlDTio66XliTOckq2RgM+ZocZEb6EoOdtd0XKh3Lzx29
# AhHxlk+6eIwavlHYuOLZDKodPOVN6j1IJ9brolY6mZboQ51Oqe5nEM5h/WJX28GL
# ZioEkJN8qOe5P5P2Yx9HoOqLugX00qCzxq4BDm8xH85HKxvKCO5KikopaRGGtQlX
# jDyusMWlrHcySt56DhL4dcVnn7dFvL50zvQlFZMhVoehWSQkkWuUlCCqIOrTe7Rb
# mnbdJosH+7lC+n53gnKy4OoZzuUeqzCnSB1JNXPKnJojP3De5xwspi5tUvQFNflf
# GTsjZgQAgDBdg/DO0TGgLRDKvZQCZ5qIuXpQRyg37yc51e95z8U2mysU0XnSpWei
# gHqkyOAtDfcIpq5Gv7HV+da2RwIDAQABo4IBSTCCAUUwHQYDVR0OBBYEFNoGubUP
# jP2f8ifkIKvwy1rlSHTZMB8GA1UdIwQYMBaAFJ+nFV0AXmJdg/Tl0mWnG1M1Gely
# MF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNy
# bDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwVGltZS1TdGFtcCUyMFBD
# QSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYB
# BQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEBCwUAA4ICAQCD83aFQUxN
# 37HkOoJDM1maHFZVUGcqTQcPnOD6UoYRMmDKv0GabHlE82AYgLPuVlukn7HtJPF2
# z0jnTgAfRMn26JFLPG7O/XbKK25hrBPJ30lBuwjATVt58UA1BWo7lsmnyrur/6h8
# AFzrXyrXtlvzQYqaRYY9k0UFY5GM+n9YaEEK2D268e+a+HDmWe+tYL2H+9O4Q1MQ
# Lag+ciNwLkj/+QlxpXiWou9KvAP0tIk+fH8F3ww5VOTi9aZ9+qPjszw31H4ndtiv
# BZaH5s5boJmH2JbtMuf2y7hSdJdE0UW2B0FEZPLImemlKhslJNVqEO7RPgl7c81Q
# uVSO58ffpmbwtSxhYrES3VsPglXn9ODF7DqmPMG/GysB4o/QkpNUq+wS7bORTNzq
# HMtH+ord2YSma+1byWBr/izIKggOCdEzaZDfym12GM6a4S+Iy6AUIp7/KIpAmfWf
# XrcMK7V7EBzxoezkLREEWI4XtPwpEBntOa1oDH3Z/+dRxsxL0vgya7jNfrO7oizT
# Aln/2ZBYB9ioUeobj5AGL45m2mcKSk7HE5zUReVkILpYKBQ5+X/8jFO1/pZyqzQe
# I1/oJ/RLoic1SieLXfET9EWZIBjZMZ846mDbp1ynK9UbNiCjSwmTF509Yn9M47VQ
# sxsv1olQu51rVVHkSNm+rTrLwK1tvhv0mTCCB3EwggVZoAMCAQICEzMAAAAVxedr
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
# ZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOkE0MDAt
# MDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNl
# oiMKAQEwBwYFKw4DAhoDFQBJiUhpCWA/3X/jZyIy0ye6RJwLzqCBgzCBgKR+MHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqGSIb3DQEBCwUAAgUA66wP
# tzAiGA8yMDI1MDQxNzIzMzkzNVoYDzIwMjUwNDE4MjMzOTM1WjB0MDoGCisGAQQB
# hFkKBAExLDAqMAoCBQDrrA+3AgEAMAcCAQACAgSkMAcCAQACAhJnMAoCBQDrrWE3
# AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMHoSCh
# CjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBACTdnfIQlaUgESu5WAdvwDwx
# WX3UtFzQK45cq/Gdv8J9C+BhuniVLTvS3J9Km+v3LQxBpy8RfAHHjWGacoVX/nFW
# CTAuHWYy+4SPS4LIx+NdW8IsaJ3S9Lu9IS9MoTLdqn9kDIZ6Rvn/GaEqWKTHIstq
# s0XynGLkQvCPMUPx/m3p2Q0eJLvto3tQ0Ue7MFiJ8hSTWZBhS/ZMwcrfKAApiK63
# mf56lQLCjYQBOexNJbj6ZlAwaMP5x2hfNRyNMQxP92bsKDs11KqmUX8waRD7wyZS
# ZzmBUDR1zcMYY2Ie2q/njltVMV33eQYsn9Zem3jafLDZFvAnUupqHIP2PkVOEMwx
# ggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3Rv
# bjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0
# aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0EgMjAxMAITMwAA
# AgJ5UHQhFH24oQABAAACAjANBglghkgBZQMEAgEFAKCCAUowGgYJKoZIhvcNAQkD
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBZNmA2gFz03SXLixGmvxPM
# gvtZ3khJ+uSDwgsif55vqjCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EIPON
# 6gEYB5bLzXLWuUmL8Zd8xXAsqXksedFyolfMlF/sMIGYMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAICeVB0IRR9uKEAAQAAAgIwIgQg2iSA
# EFNrkSqcjwyfscqsX3z6o47R2o1O1c3Vr7IohF4wDQYJKoZIhvcNAQELBQAEggIA
# eOMcIHqhQvNkM6JMKwQ0QoLOHZGcqQkNlDXaHxtcGwC4nx8Xjjtgv/BQRal049hZ
# X1a9OeWjhzVDiB02NkmwEkIoWlTnUpeCF/9GZBLANEEjKmaQGH7u4K5Ru4Xe/7h4
# wuGPfk1ikGOFXuJ5YjLNfqxewY3SAoqfsexVsPf3uD6ubqFLTuD9IxcC0Sya/7Tl
# jxKgyhvdiEp3K857k1fBZWoSYkZWkhnI6eka3HjJ/r/hkqjf3i8FhyyKAbE/X/Q6
# qR+bAGByvXmUNXSK1CBPdL9n7+4obhSVsamGJdx3bomU5TvQGG1HxgdoBy1GpYNp
# 7wWYlJFmD7VEiPVPHy04qAC+8bA7+n29M2JFKgd8fsKxixPbqhBwoVczTFUombZk
# VB3pY6Z+5SSzJXrp/t+A5546/1P/zbh6ScqncqZZxsO5VVV5g0F8tt4JH6Uco6eh
# GIWUhaNmAlJmzrMlO2HUXCKf+W8dx+YIp1t+xmpbq0qA2D6fitmYWEBskKOFoVbp
# nSvK/ssMOvqXFIB6gMwQCyHekTVutOXZeKuUCBatPQJr5hTwMQlE38rKCBbKjhQQ
# H94/wHri2t3teBgLmUb+zPoxD0M61bD78IIVIPtupNZ4aRUvK0EPoXY3Q5Hj3jnl
# a6/TiTfwPD3y9gH0OioSQAHYWDOZwEOq8G479S4G9pc=
# SIG # End signature block
