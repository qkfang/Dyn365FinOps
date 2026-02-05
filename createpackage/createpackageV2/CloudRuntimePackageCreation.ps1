function Add-CloudRuntimeDeployablePackage {
    [Cmdletbinding()]
	param(
		[Parameter(Mandatory)]
		[string]$buildOutputLocation,
		[Parameter(Mandatory)]
		[string]$platVersionNumber,
        [Parameter(Mandatory)]
		[string]$appVersionNumber,
        [Parameter(Mandatory)]
		[string]$packageOutputLocation
	)

	try
    {
        Write-Host $PSScriptRoot
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\System.Text.Encodings.Web.dll"         #"System.Text.Encodings.Web.6.0.0\lib\net461\System.Text.Encodings.Web.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\System.Threading.Tasks.Extensions.dll" #"System.Threading.Tasks.Extensions.4.5.4\lib\net461\System.Threading.Tasks.Extensions.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\System.Memory.dll"                     #"System.Memory.4.5.4\lib\net461\System.Memory.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Bcl.AsyncInterfaces.dll"     #"Microsoft.Bcl.AsyncInterfaces.6.0.0\lib\net461\Microsoft.Bcl.AsyncInterfaces.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\System.Text.Json.dll"                  #"System.Text.Json.6.0.2\lib\net461\System.Text.Json.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Xrm.Sdk.dll"                 #"Microsoft.CrmSdk.CoreAssemblies.9.0.2.45\lib\net462\Microsoft.Xrm.Sdk.dll"
    }
    catch
    {
        $_.Exception.LoaderExceptions
    }
    try{
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"                          #"Microsoft.IdentityModel.Clients.ActiveDirectory.3.19.8\lib\net45\Microsoft.IdentityModel.Clients.ActiveDirectory.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Xrm.Tooling.PackageDeployment.CrmPackageExtentionBase.dll"          #"Microsoft.CrmSdk.XrmTooling.PackageDeployment.Core.9.1.0.116\lib\net462\Microsoft.Xrm.Tooling.PackageDeployment.CrmPackageExtentionBase.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Xrm.Tooling.PackageDeployment.CrmPackageCore.FinanceOperations.dll" #"Microsoft.CrmSdk.XrmTooling.PackageDeployment.Core.9.1.0.116\lib\net462\Microsoft.Xrm.Tooling.PackageDeployment.CrmPackageCore.FinanceOperations.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Xrm.Tooling.PackageDeployment.CrmPackageCore.dll"                   #"Microsoft.CrmSdk.XrmTooling.PackageDeployment.Core.9.1.0.116\lib\net462\Microsoft.Xrm.Tooling.PackageDeployment.CrmPackageCore.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Dynamics.VSExtension.Shared.dll"                                    #"Microsoft.Dynamics.VSExtension.Shared.7.0.30011\lib\net472\Microsoft.Dynamics.VSExtension.Shared.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.ApplicationInsights.dll"                                            #"Microsoft.ApplicationInsights.2.21.0\lib\net46\Microsoft.ApplicationInsights.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.PowerPlatform.VSShared.Util.dll"                                                   #"PowerPlatSharedLibrary.1.0.0\lib\net472\PowerPlatSharedLibrary.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Xrm.Tooling.Connector.dll"                                          #"Microsoft.CrmSdk.XrmTooling.CoreAssembly.9.1.1.27\lib\net462\Microsoft.Xrm.Tooling.Connector.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Newtonsoft.Json.dll"                                                          #"Newtonsoft.Json.13.0.1\lib\net45\Newtonsoft.Json.dll"
        Add-Type -Path "$PSScriptRoot\CloudRuntimeDlls\Microsoft.Dynamics.AX.DesignTime.Telemetry2.dll"                              #"Microsoft.Dynamics.AX.DesignTime.Telemetry2.7.0.30004\lib\net462\Microsoft.Dynamics.AX.DesignTime.Telemetry2.dll"
    }
    catch
    {
        $_.Exception.LoaderExceptions
    }
    
    $assemblies = ("System", "$PSScriptRoot\CloudRuntimeDlls\Microsoft.PowerPlatform.VSShared.Util.dll")
        
    $id = get-random
    $code = 
@"
    using Microsoft.PowerPlatform.VSShared.Util;
    using System;
    using System.Threading.Tasks;
    namespace PackageCreation
    {
        public class Program$id
        {
            public static async Task<string> MainCreate(string[] args)
            {
                var createPkg = new PipelineOperation();
                var pkgLoc = await createPkg.PerformCreatePackageOperation(args[0], args[1], args[2], Guid.Empty.ToString());
                return pkgLoc;
            }
        }
    }
"@

    try
    { 
        Write-Host "Starting package creation:"
        Add-Type -ReferencedAssemblies $assemblies -TypeDefinition $code -Language CSharp
        [System.AppContext]::SetSwitch('Switch.System.IO.Compression.ZipFile.UseBackslash', $false)
        Invoke-Expression "[PackageCreation.Program$id]::MainCreate(@('$buildOutputLocation', '$platVersionNumber', '$appVersionNumber'))" | Tee-Object -Var packageLocation
        Write-Host $packageLocation.Result
        Write-Host "Ending package creation"
        Write-Host "Placing package to package output location"
        Copy-Item -Path $packageLocation.Result -Destination $packageOutputLocation -Recurse
    }
    catch
    {
        throw
    }
} 

# SIG # Begin signature block
# MIIoNwYJKoZIhvcNAQcCoIIoKDCCKCQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCYiPCO0W8eilmB
# RxfbnKV2sXY2RBvTBv9Xy9EjgfjpYqCCDYUwggYDMIID66ADAgECAhMzAAAEA73V
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
# LwYJKoZIhvcNAQkEMSIEIE6cBAvUY5TLRJj9vLJqVSrFEe5CHjc6732ENL9L46rv
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEATSJ9j16XpxbO
# xb/n6UHCKrIeSlJXOs7oMtf58HmfT2YWJOEtzR6pMADPjhsW+jP3xpmT7DQVvHjC
# My0GlTPeWCQmNMMaRNwApVWxAC1tgs9eC5mghdiDZGx1tlRGDWtFffzbEWSLXahU
# 5N4ngjjUBXdbTpUAibNQVd7JMaoHaMVGWIZo+IIrdMgZfKVzo1nXSsucTgeFZRQS
# jGTBY416Cy7P0la439TCtHxUEjfYcZ9Rj6RLWFxCUzON2rqbqK5CrnAUsPRPORc0
# r2/x5Qu3EM1FduR+Ny76VtqQ3rrux4QX0/VKFhVyvYFspHU0CiJAA+1SSPj/h44o
# aWGKKiEfQaGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCC
# F4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkE
# ggFFMIIBQQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCBNUlDeAqX1
# 86/KdcjTz24Ix/er8sICu/Jyebfi3Z85/wIGZ+0kvag4GBMyMDI1MDQxODAwMjAx
# OC45NDJaMASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMS0wKwYDVQQLEyRNaWNyb3NvZnQgSXJlbGFuZCBPcGVyYXRpb25z
# IExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0
# NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaCCEf4wggco
# MIIFEKADAgECAhMzAAAB+KOhJgwMQEj+AAEAAAH4MA0GCSqGSIb3DQEBCwUAMHwx
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1p
# Y3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMB4XDTI0MDcyNTE4MzEwOFoXDTI1
# MTAyMjE4MzEwOFowgdMxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xLTArBgNVBAsTJE1pY3Jvc29mdCBJcmVsYW5kIE9wZXJhdGlvbnMgTGltaXRl
# ZDEnMCUGA1UECxMeblNoaWVsZCBUU1MgRVNOOjMyMUEtMDVFMC1EOTQ3MSUwIwYD
# VQQDExxNaWNyb3NvZnQgVGltZS1TdGFtcCBTZXJ2aWNlMIICIjANBgkqhkiG9w0B
# AQEFAAOCAg8AMIICCgKCAgEAxR23pXYnD2BuODdeXs2Cu/T5kKI+bAw8cbtN50Cm
# /FArjXyL4RTqMe6laQ/CqeMTxgckvZr1JrW0Mi4F15rx/VveGhKBmob45DmOcV5x
# yx7h9Tk59NAl5PNMAWKAIWf270SWAAWxQbpVIhhPWCnVV3otVvahEad8pMmoSXrT
# 5Z7Nk1RnB70A2bq9Hk8wIeC3vBuxEX2E8X50IgAHsyaR9roFq3ErzUEHlS8YnSq3
# 3ui5uBcrFOcFOCZILuVFVTgEqSrX4UiX0etqi7jUtKypgIflaZcV5cI5XI/eCxY8
# wDNmBprhYMNlYxdmQ9aLRDcTKWtddWpnJtyl5e3gHuYoj8xuDQ0XZNy7ESRwJIK0
# 3+rTZqfaYyM4XSK1s0aa+mO69vo/NmJ4R/f1+KucBPJ4yUdbqJWM3xMvBwLYycvi
# gI/WK4kgPog0UBNczaQwDVXpcU+TMcOvWP8HBWmWJQImTZInAFivXqUaBbo3wAfP
# NbsQpvNNGu/12pg0F8O/CdRfgPHfOhIWQ0D8ALCY+LsiwbzcejbrVl4N9fn2wOg2
# sDa8RfNoD614I0pFjy/lq1NsBo9V4GZBikzX7ZjWCRgd1FCBXGpfpDikHjQ05YOk
# AakdWDT2bGSaUZJGVYtepIpPTAs1gd/vUogcdiL51o7shuHIlB6QSUiQ24XYhRbb
# QCECAwEAAaOCAUkwggFFMB0GA1UdDgQWBBS9zsZzz57QlT5nrt/oitLv1OQ7tjAf
# BgNVHSMEGDAWgBSfpxVdAF5iXYP05dJlpxtTNRnpcjBfBgNVHR8EWDBWMFSgUqBQ
# hk5odHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQl
# MjBUaW1lLVN0YW1wJTIwUENBJTIwMjAxMCgxKS5jcmwwbAYIKwYBBQUHAQEEYDBe
# MFwGCCsGAQUFBzAChlBodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2Nl
# cnRzL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQQ0ElMjAyMDEwKDEpLmNydDAM
# BgNVHRMBAf8EAjAAMBYGA1UdJQEB/wQMMAoGCCsGAQUFBwMIMA4GA1UdDwEB/wQE
# AwIHgDANBgkqhkiG9w0BAQsFAAOCAgEAYfk8GzzpEVnGl7y6oXoytCb42Hx6TOA0
# +dkaBI36ftDE9tLubUa/xMbHB5rcNiRhFHZ93RefdPpc4+FF0DAl5lP8xKAO+293
# RWPKDFOFIxgtZY08t8D9cSQpgGUzyw3lETZebNLEA17A/CTpA2F9uh8j84KygeEb
# j+bidWDiEfayoH2A5/5ywJJxIuLzFVHacvWxSCKoF9hlSrZSG5fXWS3namf4tt69
# 0UT6AGyWLFWe895coFPxm/m0UIMjjp9VRFH7nb3Ng2Q4gPS9E5ZTMZ6nAlmUicDj
# 0NXAs2wQuQrnYnbRAJ/DQW35qLo7Daw9AsItqjFhbMcG68gDc4j74L2KYe/2goBH
# LwzSn5UDftS1HZI0ZRsqmNHI0TZvvUWX9ajm6SfLBTEtoTo6gLOX0UD/9rrhGjdk
# iCw4SwU5osClgqgiNMK5ndk2gxFlDXHCyLp5qB6BoPpc82RhO0yCzoP9gv7zv2Eo
# cAWEsqE5+0Wmu5uarmfvcziLfU1SY240OZW8ld4sS8fnybn/jDMmFAhazV1zH0QE
# RWEsfLSpwkOXaImWNFJ5lmcnf1VTm6cmfasScYtElpjqZ9GooCmk1XFApORPs/PO
# 43IcFmPRwagt00iQSw+rBeIH00KQq+FJT/62SB70g9g/R8TS6k6b/wt2UWhqrW+Q
# 8lw6Xzgex/YwggdxMIIFWaADAgECAhMzAAAAFcXna54Cm0mZAAAAAAAVMA0GCSqG
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
# IExpbWl0ZWQxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjozMjFBLTA1RTAtRDk0
# NzElMCMGA1UEAxMcTWljcm9zb2Z0IFRpbWUtU3RhbXAgU2VydmljZaIjCgEBMAcG
# BSsOAwIaAxUAtkQt/ebWSQ5DnG+aKRzPELCFE9GggYMwgYCkfjB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDANBgkqhkiG9w0BAQsFAAIFAOusEXEwIhgPMjAy
# NTA0MTcyMzQ2NTdaGA8yMDI1MDQxODIzNDY1N1owdzA9BgorBgEEAYRZCgQBMS8w
# LTAKAgUA66wRcQIBADAKAgEAAgINcgIB/zAHAgEAAgISWzAKAgUA661i8QIBADA2
# BgorBgEEAYRZCgQCMSgwJjAMBgorBgEEAYRZCgMCoAowCAIBAAIDB6EgoQowCAIB
# AAIDAYagMA0GCSqGSIb3DQEBCwUAA4IBAQAsiUv5X4zkPnQdqeqYTGweUPG4vb7y
# /Tu7CwkphEvrnYvBbcdQcZVzJyAYYwUf8xQ3CQ+/UxMr3/iEju/GLylHafoE/IOH
# vrxDd7qgIESEAAu4H6bi2upWThwC7VP1L71M7qf4+8X4GGNO4KDmK+Oqq+xXo/tT
# 7Lqf5FKEAc+X/Dz1VOekX1iGC00x6dMAIIRT8nwq7igculAS34ObbW0Gl9gokgXJ
# 8vi04HiRdNSIDMdrOK+eNp9sZ8lQr1JDbipiE8PyvPBEL60ycvaALv4EfeV8XgmI
# Y0J30SQTOUPdSvolwt5MYpAD75ZZ0n1eqGTp+kuM4tQneWkSqTw/BdHwMYIEDTCC
# BAkCAQEwgZMwfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAH4o6Em
# DAxASP4AAQAAAfgwDQYJYIZIAWUDBAIBBQCgggFKMBoGCSqGSIb3DQEJAzENBgsq
# hkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQgMTuGi7zkV8MGxkHDbS8Cmi4/Vk+m
# Eq2hVnUUexjTIO8wgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDvzDPyXw1U
# kAUFYt8bR4UdjM90Qv5xnVaiKD3I0Zz3WjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAAB+KOhJgwMQEj+AAEAAAH4MCIEICZCuso8Jx0X
# GfYWeqhz4EPj7BI63Dxb2kh86JGB1kuaMA0GCSqGSIb3DQEBCwUABIICAE+2PLtD
# PyJuJlPSxaXQIuK20zCgOs0Irr3JxxVP0ADnUmjxfefeomaHLGMi5tTmnKD0Kq+C
# eaB4/xkHQnpd34Cda474PssDe361TBcelrA4JYlyB8sgxZo9CSMufxe8R/f88+39
# SIhsZNbXbX80yi+fWn+mS5rqWPXi+EbOvO9v5hr3knNk+S/gTSeF9siZyrCwDBPg
# /rTFEog+FY8Xr5jhSnnArnFMVclxmp1MkbHilQpyeIGzcomtcuNtgsKlDEOJEjs+
# BvlYZPc39dI5mvzVZCMEW8DY/SuvsoKicf5r7pgkuMOj7kkxpKDvInzW/vxBa0Ej
# ZxaQ6GvurqhUyvTgZoVu5kGvSSQ93CBA1czQhc24IPMqAzEoflL9rpNEZSmuaZm5
# tf8HZuB96ukdDF03tVwYJqooj8fPPkDT9gAsTtFgxCn1YOv7Q+h+8oe36we/DStp
# VnkfhsPPeC1QwAy8H6Nx1MrXeG5KAwKQ5BHQVvPmmRKk5RjUrZFeEnrEJhenskrV
# eTF9Y+xSaiGafuDqFu6ilBpVisuzS5PwjLIv7qhC4YK2sEI1M7IDEkKSDPM6GiJQ
# O5/IOgQOFlvdAvx7nOSOjKTyMpTvL4nB2RaiokLeLD7OUs9nOmImKgmakVIfQ3JA
# HW26It58+ZJa4hwu6sQQCBWsZVhJj1zOr0MX
# SIG # End signature block
