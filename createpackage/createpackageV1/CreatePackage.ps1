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
    Write-Host "##vso[task.logissue type=warning]New task version available. Please upgrade to latest to avoid disruption."
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
    $packages = @()
    if ($potentialPackages.Length -gt 0)
    {
        $createRegularPackage = Get-VstsInput -Name "CreateRegularPackage" -Require
        if ($createRegularPackage -eq "true")
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

            $artifactDirectory = [System.IO.Path]::GetDirectoryName($deployablePackagePath)
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

                Write-Host "Creating deployable package"
                Add-Type -Path "$xppToolsPath\Microsoft.Dynamics.AXCreateDeployablePackageBase.dll"
                try
                {
                    Write-Host "  - Creating combined metadata package"
                    [Microsoft.Dynamics.AXCreateDeployablePackageBase.BuildDeployablePackages]::CreateMetadataPackage($outputDir, $tempCombinedPackage)
                    Write-Host "  - Creating merged deployable package"
                    [Microsoft.Dynamics.AXCreateDeployablePackageBase.BuildDeployablePackages]::MergePackage("$xppToolsPath\BaseMetadataDeployablePackage.zip", $tempCombinedPackage, $deployablePackagePath, $true, [String]::Empty)

                    Write-Host "Deployable package '$deployablePackagePath' successfully created."
                }
                catch
                {
                    Write-Host "Error Occured"
                    Write-Host $_
                    Write-Host $_.Exception
                    throw $_.Exception
                }
            }
            finally
            {
                if (Test-Path -Path $outputDir)
                {
                    Remove-Item -Path $outputDir -Recurse -Force
                }
                if (Test-Path -Path $tempCombinedPackage)
                {
                    Remove-Item -Path $tempCombinedPackage -Force
                }
            }
        }
        $createCloudPackage = Get-VstsInput -Name "CreateCloudPackage" -Require
        if ($createCloudPackage -eq "true")
        {
            # include $packages that match pattern in a folder and send that folder to library
            $tempDirRoot = Join-Path -Path $xppBinPath -ChildPath ((New-Guid).ToString())
            New-Item -Path $tempDirRoot -ItemType Directory > $null
            # create a temporary folder that has matching pattern and send that as input to library
            Write-Host "Found $($potentialPackages.Length) potential folders to include:"
            foreach($package in $potentialPackages)
            {
                $packageBinPath = Join-Path -Path $package -ChildPath "bin"
                # If there is a bin folder and it contains *.MD files, assume it's a valid X++ binary
                if ((Test-Path -Path $packageBinPath) -and ((Get-ChildItem -Path $packageBinPath -Filter *.md).Count -gt 0))
                {
                    Write-Host "  - $package"
                    Copy-Item -Path $package -Destination $tempDirRoot -Recurse
                }
                else
                {
                    Write-Warning "  - $package (not an X++ binary folder, skipped)"
                }
            }

            $directoryCount = (Get-ChildItem -Path $tempDirRoot -Directory | Measure-Object).Count
            if(0 -eq $directoryCount)
            {
                throw "No valid package directories found. Please ensure the packages are present in the binaries path."
            }
            Write-Host "Number of valid directories found: $directoryCount. Proceeding."

            $cloudPackagePlatVersion = Get-VstsInput -Name "CloudPackagePlatVersion" -Require
            $cloudPackageAppVersion = Get-VstsInput -Name "CloudPackageAppVersion" -Require
            $cloudPackageOutputLocation = Get-VstsInput -Name "CloudPackageOutputLocation" -Require
            
                try{
                    Write-Host "Creating cloud runtime deployable package"
                    $PSVersionTable
                    Import-Module "$PSScriptRoot\CloudRuntimePackageCreation.ps1" -Force
                    Add-CloudRuntimeDeployablePackage -buildOutputLocation "$tempDirRoot" -platVersionNumber "$cloudPackagePlatVersion" -appVersionNumber "$cloudPackageAppVersion" -packageOutputLocation "$cloudPackageOutputLocation"
                }
                catch{
                    throw $_.Exception
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
    if (($null -ne $tempDirRoot) -and (Test-Path $tempDirRoot)) {
        Write-Host "$tempDirRoot exists, deleting."
        Remove-Item $tempDirRoot -Recurse -Force
    }
    Trace-VstsLeavingInvocation $MyInvocation
}
# SIG # Begin signature block
# MIIoKAYJKoZIhvcNAQcCoIIoGTCCKBUCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDS93pn2yIIjFXd
# 0OO2J6s07OrzUoKM/iQbz9+MyfuwO6CCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IO3IGZzpp+kLkEsOM+8q/+hDDNwFyCwY04sMgXKvJq+GMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAOeJM0dZiAES5ihygA7zYLeqSXGqO3YEg
# /Og5huWEW4vTU10E2eSDuOh5q8pymN0xiNG23C5/8IyWv5IELANMCNXufDXDNXw9
# 8YWdJebo3jUmTa2nwsPQX2678taSTvMbXRdw0Ls5icv8yzF6Lf+45FeFzYXbNif+
# /176oS+OQNuNDN80ljxYAvxiolqUmwDrFwrOO6Rq3X0m8TO3UjIeSKtZzUH0+iHt
# CiKcr/CMN3rLOkXO1FIkK+o6z8ZOWBJRKFvWUAv5lBtbSj3/tWtFu0hCbd5l625R
# Q12Gh6EUi9gWdE0bWYaoDD37fvbCF4jV0Yew54zV4NWdgdR/AUKvL6GCF7Awghes
# BgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCCF4kwgheFAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkEggFFMIIBQQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCDE5dmnyRD9/YCxJ8eWUoW1/0J+Ivue
# 0xKXmlG77WdgyAIGZ+0r46FTGBMyMDI1MDQxODAwMTk0OC41ODJaMASAAgH0oIHZ
# pIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMS0wKwYD
# VQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25zIExpbWl0ZWQxJzAlBgNV
# BAsTHm5TaGllbGQgVFNTIEVTTjozNjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggcoMIIFEKADAgECAhMzAAAB
# 91ggdQTK+8L0AAEAAAH3MA0GCSqGSIb3DQEBCwUAMHwxCzAJBgNVBAYTAlVTMRMw
# EQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0
# YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzEwNloXDTI1MTAyMjE4MzEwNlowgdMx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xLTArBgNVBAsTJE1p
# Y3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRlZDEnMCUGA1UECxMeblNo
# aWVsZCBUU1MgRVNOOjM2MDUtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQg
# VGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKC
# AgEA0OdHTBNom6/uXKaEKP9rPITkT6QxF11tjzB0Nk1byDpPrFTHha3hxwSdTcr8
# Y0a3k6EQlwqy6ROz42e0R5eDW+dCoQapipDIFUOYp3oNuqwX/xepATEkY17MyXFx
# 6rQW2NcWUJW3Qo2AuJ0HOtblSpItQZPGmHnGqkt/DB45Fwxk6VoSvxNcQKhKETku
# zrt8U6DRccQm1FdhmPKgDzgcfDPM5o+GnzbiMu6y069A4EHmLMmkecSkVvBmcZ8V
# nzFHTDkGLdpnDV5FXjVObAgbSM0cnqYSGfRp7VGHBRqyoscvR4bcQ+CV9pDjbJ6S
# 5rZn1uA8hRhj09Hs33HRevt4oWAVYGItgEsG+BrCYbpgWMDEIVnAgPZEiPAaI8wB
# GemE4feEkuz7TAwgkRBcUzLgQ4uvPqRD1A+Jkt26+pDqWYSn0MA8j0zacQk9q/Av
# ciPXD9It2ez+mqEzgFRRsJGLtcf9HksvK8Jsd6I5zFShlqi5bpzf1Y4NOiNOh5Qw
# W1pIvA5irlal7qFhkAeeeZqmop8+uNxZXxFCQG3R3s5pXW89FiCh9rmXrVqOCwgc
# XFIJQAQkllKsI+UJqGq9rmRABJz5lHKTFYmFwcM52KWWjNx3z6odwz2h+sxaxewT
# oe9GqtDx3/aU+yqNRcB8w0tSXUf+ylN4uk5xHEpLpx+ZNNsCAwEAAaOCAUkwggFF
# MB0GA1UdDgQWBBTfRqQzP3m9PZWuLf1p8/meFfkmmDAfBgNVHSMEGDAWgBSfpxVd
# AF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQhk5odHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBUaW1lLVN0YW1wJTIw
# UENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBeMFwGCCsGAQUFBzAChlBo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAMBgNVHRMBAf8EAjAAMBYG
# A1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQEAwIHgDANBgkqhkiG9w0B
# AQsFAAOCAgEAN0ajafILeL6SQIMIMAXM1Qd6xaoci2mOrpR8vKWyyTsL3b83A7XG
# LiAbQxTrqnXvVWWeNst5YQD8saO+UTgOLJdTdfUADhLXoK+RlwjfndimIJT9MH9t
# UYXLzJXKhZM09ouPwNsrn8YOLIpdAi5TPyN8Cl11OGZSlP9r8JnvomW00AoJ4Pl9
# rlg0G5lcQknAXqHa9nQdWp1ZxXqNd+0JsKmlR8tcANX33ClM9NnaClJExLQHiKeH
# UUWtqyLMl65TW6wRM7XlF7Y+PTnC8duNWn4uLng+ON/Z39GO6qBj7IEZxoq4o3av
# Eh9ba43UU6TgzVZaBm8VaA0wSwUe/pqpTOYFWN62XL3gl/JC2pzfIPxP66XfRLIx
# afjBVXm8KVDn2cML9IvRK02s941Y5+RR4gSAOhLiQQ6A03VNRup+spMa0k+XTPAi
# +2aMH5xa1Zjb/K8u9f9M05U0/bUMJXJDP++ysWpJbVRDiHG7szaca+r3HiUPjQJy
# Ql2NiOcYTGV/DcLrLCBK2zG503FGb04N5Kf10XgAwFaXlod5B9eKh95PnXKx2LNB
# gLwG85anlhhGxxBQ5mFsJGkBn0PZPtAzZyfr96qxzpp2pH9DJJcjKCDrMmZziXaz
# pa5VVN36CO1kDU4ABkSYTXOM8RmJXuQm7mUF3bWmj+hjAJb4pz6hT5UwggdxMIIF
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
# BAsTHm5TaGllbGQgVFNTIEVTTjozNjA1LTA1RTAtRDk0NzElMCMGA1UEAxMcTWlj
# cm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcGBSsOAwIaAxUAb28KDG/x
# XbNBjmM7/nqw3bgrEOaggYMwgYCkfjB8MQswCQYDVQQGEwJVUzETMBEGA1UECBMK
# V2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0
# IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFtcCBQQ0Eg
# MjAxMDANBgkqhkiG9w0BAQsFAAIFAOusGJcwIhgPMjAyNTA0MTgwMDE3MjdaGA8y
# MDI1MDQxOTAwMTcyN1owdzA9BgorBgEEAYRZCgQBMS8wLTAKAgUA66wYlwIBADAK
# AgEAAgI1nwIB/zAHAgEAAgISuzAKAgUA661qFwIBADA2BgorBgEEAYRZCgQCMSgw
# JjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIBAAIDAYagMA0GCSqGSIb3
# DQEBCwUAA4IBAQBkN/YVE5/msJnS7fxReP1K2ziaiB74GhgZ70Oj/NDK3bgCseS9
# MmteJYYJMYftVroL/TMOL//uhqcSQIeh6fFF8ZwSLXHGqkpr75TayrsBosWwA/n/
# MadRv0bjvymIxrlco8WNRJJ1w3A19ha9RAZ5J8O671j7GLgvbWPdObo/+NZ3n/Q9
# rZ3LRJwmpJdJI/HkH9Y580klPL9Meg/fhsd0kHda3L9bjtjshC8UpSFr2BgBmEZ3
# xp/C7HYpxNbejao5Y2mIhOsJfFLSJ8DBzf4m/kMEsXpMhkhNwOPXAGZgruFd/1ve
# GTHhT3wSWYRP9AGzcTxvLO/UQci7jj2FkJvCMYIEDTCCBAkCAQEwgZMwfDELMAkG
# A1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQx
# HjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9z
# b2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH3WCB1BMr7wvQAAQAAAfcwDQYJ
# YIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsqhkiG9w0BCRABBDAvBgkq
# hkiG9w0BCQQxIgQgOx7b//IM9kc1AwVb06XL9sTfSlN9hin7xhpACyuWFLwwgfoG
# CyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCAh2pjaa3ca0ecYuhu60uYHP/IKnPbe
# dbVQJ5SoIH5Z4jCBmDCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNo
# aW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29y
# cG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEw
# AhMzAAAB91ggdQTK+8L0AAEAAAH3MCIEIKt0+a/EHBvCTEBGFTVgViu3f3loPwRq
# GeVn5fIF0pSjMA0GCSqGSIb3DQEBCwUABIICAB89tqNIQ2+xg49QG8WrLZluOI6N
# 8QyCCf4ZeE6T5OUi65Qkr3DhbYA6xFQVybQ7xeJvm78ZqI9Yegs45qfLp4tgmCnR
# ny9mVLFP0YwQvbJfhyxnDgQaMgz5TJZ40JxWf78HHQTjj/SfzRCIYEwbqsEImpiU
# Rhky2xKb93qEp2KNo0BdrIEhm1Rm1TUHHVN8qxy7L3w8DQBCdAi+A7FXCzPU4Wvj
# g6ITTKxEBMIAZvf5WN7i1XZtB/zN/FLBZXEtDZIp4vS70pIMUvpzKXYzzbCMl8ZJ
# 5XX8B2SEGvPuNN/mp6t5kGSykeFkLLf+Yvw8Hib4gBYw8KqByi5z+DFYUStgWnLw
# Qx/31rrztVrnlQNxhYg1JtsqCaDd6QYEJutsYQtfErDFfZB4mCYc58DgQLwmdC7T
# a/DTrUmDxuhyw5IPeqChSYn0hk5tXXOde6FxP6OXBcaEPaadkAO+E7VQxX1ulPzP
# Mzh+UWaXBcCV+WSXCDiw4yajFLWAjZx9sI8y8J7i/GxiAe+LtWdmAMT3Pi+i4Hex
# 9rYW92clMJn/SS3E2md+LwQBtu4mEf3dmbnDy95QkYiiSoW2LANJric1xUEkn1Qx
# Q8rmpOXV6Pal6N1aI2s/0zb3O9xY7qlPNoIH2SMUJH2gZm/7Vm7ADsDnVT3CVKq9
# V5rqvytHYvflVYEd
# SIG # End signature block
