<#
.SYNOPSIS
Gets assembly reference information.

.DESCRIPTION
Not supported for use during task execution. This function is only intended to help developers resolve the minimal set of DLLs that need to be bundled when consuming the VSTS REST SDK or TFS Extended Client SDK. The interface and output may change between patch releases of the VSTS Task SDK.

Only a subset of the referenced assemblies may actually be required, depending on the functionality used by your task. It is best to bundle only the DLLs required for your scenario.

Walks an assembly's references to determine all of it's dependencies. Also walks the references of the dependencies, and so on until all nested dependencies have been traversed. Dependencies are searched for in the directory of the specified assembly. NET Framework assemblies are omitted.

See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER LiteralPath
Assembly to walk.

.EXAMPLE
Get-VstsAssemblyReference -LiteralPath C:\nuget\microsoft.teamfoundationserver.client.14.102.0\lib\net45\Microsoft.TeamFoundation.Build2.WebApi.dll
#>
function Get-AssemblyReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LiteralPath)

    $ErrorActionPreference = 'Stop'
    Write-Warning "Not supported for use during task execution. This function is only intended to help developers resolve the minimal set of DLLs that need to be bundled when consuming the VSTS REST SDK or TFS Extended Client SDK. The interface and output may change between patch releases of the VSTS Task SDK."
    Write-Output ''
    Write-Warning "Only a subset of the referenced assemblies may actually be required, depending on the functionality used by your task. It is best to bundle only the DLLs required for your scenario."
    $directory = [System.IO.Path]::GetDirectoryName($LiteralPath)
    $hashtable = @{ }
    $queue = @( [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($LiteralPath).GetName() )
    while ($queue.Count) {
        # Add a blank line between assemblies.
        Write-Output ''

        # Pop.
        $assemblyName = $queue[0]
        $queue = @( $queue | Select-Object -Skip 1 )

        # Attempt to find the assembly in the same directory.
        $assembly = $null
        $path = "$directory\$($assemblyName.Name).dll"
        if ((Test-Path -LiteralPath $path -PathType Leaf)) {
            $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($path)
        } else {
            $path = "$directory\$($assemblyName.Name).exe"
            if ((Test-Path -LiteralPath $path -PathType Leaf)) {
                $assembly = [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($path)
            }
        }

        # Make sure the assembly full name matches, not just the file name.
        if ($assembly -and $assembly.GetName().FullName -ne $assemblyName.FullName) {
            $assembly = $null
        }

        # Print the assembly.
        if ($assembly) {
            Write-Output $assemblyName.FullName
        } else {
            if ($assemblyName.FullName -eq 'Newtonsoft.Json, Version=6.0.0.0, Culture=neutral, PublicKeyToken=30ad4fe6b2a6aeed') {
                Write-Warning "*** NOT FOUND $($assemblyName.FullName) *** This is an expected condition when using the HTTP clients from the 15.x VSTS REST SDK. Use Get-VstsVssHttpClient to load the HTTP clients (which applies a binding redirect assembly resolver for Newtonsoft.Json). Otherwise you will need to manage the binding redirect yourself."
            } else {
                Write-Warning "*** NOT FOUND $($assemblyName.FullName) ***"
            }
    
            continue
        }

        # Walk the references.
        $refAssemblyNames = @( $assembly.GetReferencedAssemblies() )
        for ($i = 0 ; $i -lt $refAssemblyNames.Count ; $i++) {
            $refAssemblyName = $refAssemblyNames[$i]

            # Skip framework assemblies.
            $fxPaths = @(
                "$env:windir\Microsoft.Net\Framework64\v4.0.30319\$($refAssemblyName.Name).dll"
                "$env:windir\Microsoft.Net\Framework64\v4.0.30319\WPF\$($refAssemblyName.Name).dll"
            )
            $fxPath = $fxPaths |
                Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
                Where-Object { [System.Reflection.Assembly]::ReflectionOnlyLoadFrom($_).GetName().FullName -eq $refAssemblyName.FullName }
            if ($fxPath) {
                continue
            }

            # Print the reference.
            Write-Output "    $($refAssemblyName.FullName)"

            # Add new references to the queue.
            if (!$hashtable[$refAssemblyName.FullName]) {
                $queue += $refAssemblyName
                $hashtable[$refAssemblyName.FullName] = $true
            }
        }
    }
}

<#
.SYNOPSIS
Gets a credentials object that can be used with the TFS extended client SDK.

.DESCRIPTION
The agent job token is used to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

Refer to Get-VstsTfsService for a more simple to get a TFS service object.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER OMDirectory
Directory where the extended client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.EXAMPLE
#
# Refer to Get-VstsTfsService for a more simple way to get a TFS service object.
#
$credentials = Get-VstsTfsClientCredentials
Add-Type -LiteralPath "$PSScriptRoot\Microsoft.TeamFoundation.VersionControl.Client.dll"
$tfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection(
    (Get-VstsTaskVariable -Name 'System.TeamFoundationCollectionUri' -Require),
    $credentials)
$versionControlServer = $tfsTeamProjectCollection.GetService([Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer])
$versionControlServer.GetItems('$/*').Items | Format-List
#>
function Get-TfsClientCredentials {
    [CmdletBinding()]
    param([string]$OMDirectory)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Get the endpoint.
        $endpoint = Get-Endpoint -Name SystemVssConnection -Require

        # Validate the type can be found.
        $null = Get-OMType -TypeName 'Microsoft.TeamFoundation.Client.TfsClientCredentials' -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Construct the credentials.
        $credentials = New-Object Microsoft.TeamFoundation.Client.TfsClientCredentials($false) # Do not use default credentials.
        $credentials.AllowInteractive = $false
        $credentials.Federated = New-Object Microsoft.TeamFoundation.Client.OAuthTokenCredential([string]$endpoint.auth.parameters.AccessToken)
        return $credentials
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a TFS extended client service.

.DESCRIPTION
Gets an instance of an ITfsTeamProjectCollectionObject.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER TypeName
Namespace-qualified type name of the service to get.

.PARAMETER OMDirectory
Directory where the extended client object model DLLs are located. If the DLLs for the types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the TFS extended client SDK from a task.

.PARAMETER Uri
URI to use when initializing the service. If not specified, defaults to System.TeamFoundationCollectionUri.

.PARAMETER TfsClientCredentials
Credentials to use when initializing the service. If not specified, the default uses the agent job token to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

.EXAMPLE
$versionControlServer = Get-VstsTfsService -TypeName Microsoft.TeamFoundation.VersionControl.Client.VersionControlServer
$versionControlServer.GetItems('$/*').Items | Format-List
#>
function Get-TfsService {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [string]$OMDirectory,

        [string]$Uri,

        $TfsClientCredentials)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Default the URI to the collection URI.
        if (!$Uri) {
            $Uri = Get-TaskVariable -Name System.TeamFoundationCollectionUri -Require
        }

        # Default the credentials.
        if (!$TfsClientCredentials) {
            $TfsClientCredentials = Get-TfsClientCredentials -OMDirectory $OMDirectory
        }

        # Validate the project collection type can be loaded.
        $null = Get-OMType -TypeName 'Microsoft.TeamFoundation.Client.TfsTeamProjectCollection' -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Load the project collection object.
        $tfsTeamProjectCollection = New-Object Microsoft.TeamFoundation.Client.TfsTeamProjectCollection($Uri, $TfsClientCredentials)

        # Validate the requested type can be loaded.
        $type = Get-OMType -TypeName $TypeName -OMKind 'ExtendedClient' -OMDirectory $OMDirectory -Require

        # Return the service object.
        return $tfsTeamProjectCollection.GetService($type)
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a credentials object that can be used with the VSTS REST SDK.

.DESCRIPTION
The agent job token is used to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project service build/release identity).

Refer to Get-VstsVssHttpClient for a more simple to get a VSS HTTP client.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.PARAMETER OMDirectory
Directory where the REST client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.EXAMPLE
#
# Refer to Get-VstsTfsService for a more simple way to get a TFS service object.
#
# This example works using the 14.x .NET SDK. A Newtonsoft.Json 6.0 to 8.0 binding
# redirect may be required when working with the 15.x SDK. Or use Get-VstsVssHttpClient
# to avoid managing the binding redirect.
#
$vssCredentials = Get-VstsVssCredentials
$collectionUrl = New-Object System.Uri((Get-VstsTaskVariable -Name 'System.TeamFoundationCollectionUri' -Require))
Add-Type -LiteralPath "$PSScriptRoot\Microsoft.TeamFoundation.Core.WebApi.dll"
$projectHttpClient = New-Object Microsoft.TeamFoundation.Core.WebApi.ProjectHttpClient($collectionUrl, $vssCredentials)
$projectHttpClient.GetProjects().Result
#>
function Get-VssCredentials {
    [CmdletBinding()]
    param([string]$OMDirectory)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Get the endpoint.
        $endpoint = Get-Endpoint -Name SystemVssConnection -Require

        # Check if the VssOAuthAccessTokenCredential type is available.
        if ((Get-OMType -TypeName 'Microsoft.VisualStudio.Services.OAuth.VssOAuthAccessTokenCredential' -OMKind 'WebApi' -OMDirectory $OMDirectory)) {
            # Create the federated credential.
            $federatedCredential = New-Object Microsoft.VisualStudio.Services.OAuth.VssOAuthAccessTokenCredential($endpoint.auth.parameters.AccessToken)
        } else {
            # Validate the fallback type can be loaded.
            $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.Client.VssOAuthCredential' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require

            # Create the federated credential.
            $federatedCredential = New-Object Microsoft.VisualStudio.Services.Client.VssOAuthCredential($endpoint.auth.parameters.AccessToken)
        }

        # Return the credentials.
        return New-Object Microsoft.VisualStudio.Services.Common.VssCredentials(
            (New-Object Microsoft.VisualStudio.Services.Common.WindowsCredential($false)), # Do not use default credentials.
            $federatedCredential,
            [Microsoft.VisualStudio.Services.Common.CredentialPromptType]::DoNotPrompt)
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a VSS HTTP client.

.DESCRIPTION
Gets an instance of an VSS HTTP client.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

.PARAMETER TypeName
Namespace-qualified type name of the HTTP client to get.

.PARAMETER OMDirectory
Directory where the REST client object model DLLs are located. If the DLLs for the credential types are not already loaded, an attempt will be made to automatically load the required DLLs from the object model directory.

If not specified, defaults to the directory of the entry script for the task.

*** DO NOT USE Agent.ServerOMDirectory *** See https://github.com/Microsoft/vsts-task-lib/tree/master/powershell/Docs/UsingOM.md for reliable usage when working with the VSTS REST SDK from a task.

# .PARAMETER Uri
# URI to use when initializing the HTTP client. If not specified, defaults to System.TeamFoundationCollectionUri.

# .PARAMETER VssCredentials
# Credentials to use when initializing the HTTP client. If not specified, the default uses the agent job token to construct the credentials object. The identity associated with the token depends on the scope selected in the build/release definition (either the project collection build/release service identity, or the project build/release service identity).

# .PARAMETER WebProxy
# WebProxy to use when initializing the HTTP client. If not specified, the default uses the proxy configuration agent current has.

# .PARAMETER ClientCert
# ClientCert to use when initializing the HTTP client. If not specified, the default uses the client certificate agent current has.

# .PARAMETER IgnoreSslError
# Skip SSL server certificate validation on all requests made by this HTTP client. If not specified, the default is to validate SSL server certificate.

.EXAMPLE
$projectHttpClient = Get-VstsVssHttpClient -TypeName Microsoft.TeamFoundation.Core.WebApi.ProjectHttpClient
$projectHttpClient.GetProjects().Result
#>
function Get-VssHttpClient {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [string]$OMDirectory,

        [string]$Uri,

        $VssCredentials,
        
        $WebProxy = (Get-WebProxy),
        
        $ClientCert = (Get-ClientCertificate),
        
        [switch]$IgnoreSslError)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Default the URI to the collection URI.
        if (!$Uri) {
            $Uri = Get-TaskVariable -Name System.TeamFoundationCollectionUri -Require
        }

        # Cast the URI.
        [uri]$Uri = New-Object System.Uri($Uri)

        # Default the credentials.
        if (!$VssCredentials) {
            $VssCredentials = Get-VssCredentials -OMDirectory $OMDirectory
        }

        # Validate the type can be loaded.
        $null = Get-OMType -TypeName $TypeName -OMKind 'WebApi' -OMDirectory $OMDirectory -Require

        # Update proxy setting for vss http client
        [Microsoft.VisualStudio.Services.Common.VssHttpMessageHandler]::DefaultWebProxy = $WebProxy
        
        # Update client certificate setting for vss http client
        $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.Common.VssHttpRequestSettings' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
        $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.WebApi.VssClientHttpRequestSettings' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
        [Microsoft.VisualStudio.Services.Common.VssHttpRequestSettings]$Settings = [Microsoft.VisualStudio.Services.WebApi.VssClientHttpRequestSettings]::Default.Clone()

        if ($ClientCert) {
            $null = Get-OMType -TypeName 'Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager' -OMKind 'WebApi' -OMDirectory $OMDirectory -Require
            $null = [Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager]::Instance.ClientCertificates.Add($ClientCert)
            
            $Settings.ClientCertificateManager = [Microsoft.VisualStudio.Services.WebApi.VssClientCertificateManager]::Instance
        }        

        # Skip SSL server certificate validation
        [bool]$SkipCertValidation = (Get-TaskVariable -Name Agent.SkipCertValidation -AsBool) -or $IgnoreSslError
        if ($SkipCertValidation) {
            if ($Settings.GetType().GetProperty('ServerCertificateValidationCallback')) {
                Write-Verbose "Ignore any SSL server certificate validation errors.";
                $Settings.ServerCertificateValidationCallback = [VstsTaskSdk.VstsHttpHandlerSettings]::UnsafeSkipServerCertificateValidation
            }
            else {
                # OMDirectory has older version of Microsoft.VisualStudio.Services.Common.dll
                Write-Verbose "The version of 'Microsoft.VisualStudio.Services.Common.dll' does not support skip SSL server certificate validation."
            }
        }

        # Try to construct the HTTP client.
        Write-Verbose "Constructing HTTP client."
        try {
            return New-Object $TypeName($Uri, $VssCredentials, $Settings)
        } catch {
            # Rethrow if the exception is not due to Newtonsoft.Json DLL not found.
            if ($_.Exception.InnerException -isnot [System.IO.FileNotFoundException] -or
                $_.Exception.InnerException.FileName -notlike 'Newtonsoft.Json, *') {

                throw
            }

            # Default the OMDirectory to the directory of the entry script for the task.
            if (!$OMDirectory) {
                $OMDirectory = [System.IO.Path]::GetFullPath("$PSScriptRoot\..\..")
                Write-Verbose "Defaulted OM directory to: '$OMDirectory'"
            }

            # Test if the Newtonsoft.Json DLL exists in the OM directory.
            $newtonsoftDll = [System.IO.Path]::Combine($OMDirectory, "Newtonsoft.Json.dll")
            Write-Verbose "Testing file path: '$newtonsoftDll'"
            if (!(Test-Path -LiteralPath $newtonsoftDll -PathType Leaf)) {
                Write-Verbose 'Not found. Rethrowing exception.'
                throw
            }

            # Add a binding redirect and try again. Parts of the Dev15 preview SDK have a
            # dependency on the 6.0.0.0 Newtonsoft.Json DLL, while other parts reference
            # the 8.0.0.0 Newtonsoft.Json DLL.
            Write-Verbose "Adding assembly resolver."
            $onAssemblyResolve = [System.ResolveEventHandler] {
                param($sender, $e)

                if ($e.Name -like 'Newtonsoft.Json, *') {
                    Write-Verbose "Resolving '$($e.Name)'"
                    return [System.Reflection.Assembly]::LoadFrom($newtonsoftDll)
                }

                Write-Verbose "Unable to resolve assembly name '$($e.Name)'"
                return $null
            }
            [System.AppDomain]::CurrentDomain.add_AssemblyResolve($onAssemblyResolve)
            try {
                # Try again to construct the HTTP client.
                Write-Verbose "Trying again to construct the HTTP client."
                return New-Object $TypeName($Uri, $VssCredentials, $Settings)
            } finally {
                # Unregister the assembly resolver.
                Write-Verbose "Removing assemlby resolver."
                [System.AppDomain]::CurrentDomain.remove_AssemblyResolve($onAssemblyResolve)
            }
        }
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a VstsTaskSdk.VstsWebProxy

.DESCRIPTION
Gets an instance of a VstsTaskSdk.VstsWebProxy that has same proxy configuration as Build/Release agent.

VstsTaskSdk.VstsWebProxy implement System.Net.IWebProxy interface.

.EXAMPLE
$webProxy = Get-VstsWebProxy
$webProxy.GetProxy(New-Object System.Uri("https://github.com/Microsoft/vsts-task-lib"))
#>
function Get-WebProxy {
    [CmdletBinding()]
    param()

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Min agent version that supports proxy
        Assert-Agent -Minimum '2.105.7'

        $proxyUrl = Get-TaskVariable -Name Agent.ProxyUrl
        $proxyUserName = Get-TaskVariable -Name Agent.ProxyUserName
        $proxyPassword = Get-TaskVariable -Name Agent.ProxyPassword
        $proxyBypassListJson = Get-TaskVariable -Name Agent.ProxyBypassList
        [string[]]$ProxyBypassList = ConvertFrom-Json -InputObject $ProxyBypassListJson
        
        return New-Object -TypeName VstsTaskSdk.VstsWebProxy -ArgumentList @($proxyUrl, $proxyUserName, $proxyPassword, $proxyBypassList)
    }
    finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Gets a client certificate for current connected TFS instance

.DESCRIPTION
Gets an instance of a X509Certificate2 that is the client certificate Build/Release agent used.

.EXAMPLE
$x509cert = Get-ClientCertificate
WebRequestHandler.ClientCertificates.Add(x509cert)
#>
function Get-ClientCertificate {
    [CmdletBinding()]
    param()

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Min agent version that supports client certificate
        Assert-Agent -Minimum '2.122.0'

        [string]$clientCert = Get-TaskVariable -Name Agent.ClientCertArchive
        [string]$clientCertPassword = Get-TaskVariable -Name Agent.ClientCertPassword
        
        if ($clientCert -and (Test-Path -LiteralPath $clientCert -PathType Leaf)) {
            return New-Object -TypeName System.Security.Cryptography.X509Certificates.X509Certificate2 -ArgumentList @($clientCert, $clientCertPassword)
        }        
    }
    finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

########################################
# Private functions.
########################################
function Get-OMType {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,

        [ValidateSet('ExtendedClient', 'WebApi')]
        [Parameter(Mandatory = $true)]
        [string]$OMKind,

        [string]$OMDirectory,

        [switch]$Require)

    Trace-EnteringInvocation -InvocationInfo $MyInvocation
    try {
        # Default the OMDirectory to the directory of the entry script for the task.
        if (!$OMDirectory) {
            $OMDirectory = [System.IO.Path]::GetFullPath("$PSScriptRoot\..\..")
            Write-Verbose "Defaulted OM directory to: '$OMDirectory'"
        }

        # Try to load the type.
        $errorRecord = $null
        Write-Verbose "Testing whether type can be loaded: '$TypeName'"
        $ErrorActionPreference = 'Ignore'
        try {
            # Failure when attempting to cast a string to a type, transfers control to the
            # catch handler even when the error action preference is ignore. The error action
            # is set to Ignore so the $Error variable is not polluted.
            $type = [type]$TypeName

            # Success.
            Write-Verbose "The type was loaded successfully."
            return $type
        } catch {
            # Store the error record.
            $errorRecord = $_
        }

        $ErrorActionPreference = 'Stop'
        Write-Verbose "The type was not loaded."

        # Build a list of candidate DLL file paths from the namespace.
        $dllPaths = @( )
        $namespace = $TypeName
        while ($namespace.LastIndexOf('.') -gt 0) {
            # Trim the next segment from the namespace.
            $namespace = $namespace.SubString(0, $namespace.LastIndexOf('.'))

            # Derive potential DLL file paths based on the namespace and OM kind (i.e. extended client vs web API).
            if ($OMKind -eq 'ExtendedClient') {
                if ($namespace -like 'Microsoft.TeamFoundation.*') {
                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.dll")
                }
            } else {
                if ($namespace -like 'Microsoft.TeamFoundation.*' -or
                    $namespace -like 'Microsoft.VisualStudio.Services' -or
                    $namespace -like 'Microsoft.VisualStudio.Services.*') {

                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.WebApi.dll")
                    $dllPaths += [System.IO.Path]::Combine($OMDirectory, "$namespace.dll")
                }
            }
        }

        foreach ($dllPath in $dllPaths) {
            # Check whether the DLL exists.
            Write-Verbose "Testing leaf path: '$dllPath'"
            if (!(Test-Path -PathType Leaf -LiteralPath "$dllPath")) {
                Write-Verbose "Not found."
                continue
            }

            # Load the DLL.
            Write-Verbose "Loading assembly: $dllPath"
            try {
                Add-Type -LiteralPath $dllPath
            } catch {
                # Write the information to the verbose stream and proceed to attempt to load the requested type.
                #
                # The requested type may successfully load now. For example, the type used with the 14.0 Web API for the
                # federated credential (VssOAuthCredential) resides in Microsoft.VisualStudio.Services.Client.dll. Even
                # though loading the DLL results in a ReflectionTypeLoadException when Microsoft.ServiceBus.dll (approx 3.75mb)
                # is not present, enough types are loaded to use the VssOAuthCredential federated credential with the Web API
                # HTTP clients.
                Write-Verbose "$($_.Exception.GetType().FullName): $($_.Exception.Message)"
                if ($_.Exception -is [System.Reflection.ReflectionTypeLoadException]) {
                    for ($i = 0 ; $i -lt $_.Exception.LoaderExceptions.Length ; $i++) {
                        $loaderException = $_.Exception.LoaderExceptions[$i]
                        Write-Verbose "LoaderExceptions[$i]: $($loaderException.GetType().FullName): $($loaderException.Message)"
                    }
                }
            }

            # Try to load the type.
            Write-Verbose "Testing whether type can be loaded: '$TypeName'"
            $ErrorActionPreference = 'Ignore'
            try {
                # Failure when attempting to cast a string to a type, transfers control to the
                # catch handler even when the error action preference is ignore. The error action
                # is set to Ignore so the $Error variable is not polluted.
                $type = [type]$TypeName

                # Success.
                Write-Verbose "The type was loaded successfully."
                return $type
            } catch {
                $errorRecord = $_
            }

            $ErrorActionPreference = 'Stop'
            Write-Verbose "The type was not loaded."
        }

        # Check whether to propagate the error.
        if ($Require) {
            Write-Error $errorRecord
        }
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

# SIG # Begin signature block
# MIIoNwYJKoZIhvcNAQcCoIIoKDCCKCQCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDHnexhTvdi65ta
# GC2EoafY//c7J46ZI88EwI2sfoBaAqCCDYUwggYDMIID66ADAgECAhMzAAAEA73V
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
# LwYJKoZIhvcNAQkEMSIEIJAV63SWFcZVvVnr0T28lK3RByUsmBGNhGgmI2WJNdcR
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAWnQ5GTk/YawO
# 9ABksDj8MXDlyzGkJYTiPynTzZvoUv1NAKtM9YWUpGAbZR00z9o/VdKIOtTBDJIf
# i95C9LF4PLeS54X35TnSFCrN4MpFBy3tLhkDa93MzDf+oWK64Uzy+1M8kn5RSF70
# xsf0St+RKwKqVmlaYGqc7kg34VKzCQGWdWzlNR3GdS/QWAtbl82CC5YQV2B+U4cb
# 0HlbXk2PtpxKYjBlHb8l2AyGRFGtBlfatC+dJUxul/SnQ87/6dnHz5hjLHXMW9Jv
# M3m7wdNhClqiqg5TLa0HJS5TMP8ZqHaipU7eusSJkpoSO4UWPy7YCDvfssmNzYQ6
# NFn3GJFiXaGCF7AwghesBgorBgEEAYI3AwMBMYIXnDCCF5gGCSqGSIb3DQEHAqCC
# F4kwgheFAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFaBgsqhkiG9w0BCRABBKCCAUkE
# ggFFMIIBQQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCA0/AXODbCs
# X7wLyQUxkhuBsM6ra9clNB8NZb0lNh1SQgIGZ+0kvaepGBMyMDI1MDQxODAwMjAx
# MC40ODJaMASAAgH0oIHZpIHWMIHTMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
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
# hkiG9w0BCRABBDAvBgkqhkiG9w0BCQQxIgQguZnHOmmwJdUW22Am6tz9yOqGcklI
# eAjtedpP/WAFlkcwgfoGCyqGSIb3DQEJEAIvMYHqMIHnMIHkMIG9BCDvzDPyXw1U
# kAUFYt8bR4UdjM90Qv5xnVaiKD3I0Zz3WjCBmDCBgKR+MHwxCzAJBgNVBAYTAlVT
# MRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1l
# LVN0YW1wIFBDQSAyMDEwAhMzAAAB+KOhJgwMQEj+AAEAAAH4MCIEICZCuso8Jx0X
# GfYWeqhz4EPj7BI63Dxb2kh86JGB1kuaMA0GCSqGSIb3DQEBCwUABIICAAd71sqg
# NouiutvkCdeOHHSWNXp230BFzVEokXnnAEXH092QTkwM/nCIZRPSTxwPeRCMML7k
# 5co7Y7rjO86o8hDCaGZfZ+UBsbE3lsw3iMLIrSLGRx1y6inU9DQaaQ+lLqxwRh3X
# /2jr5vU1580nXeB53vzvDmKCKnt/51n5P1WyGf6uf4TCwiRgPt7sS26PdtxDSH/v
# fbGsl1cO6qQ7GNGYK+lMGVEQQRZ7SGCUA09Gcqi+W1u68kqr+JhGIij7k4oor000
# WxhPlIBGDnlAw3siFActQ2qILZESaeLtep0r+LJqqq8obwSZ6+5Vb3zwwx3xgBMZ
# 7WBBiqtCVbi9eEtT7EW8VMnl6ZB8kK8Q8cIcumwxubWIaSvPE52g1XQn80XYT6hn
# D69Zwzem0/oJ+xG63ImBeQkA41REbu7K8M/K00BDR41n/6xXptwNQza34CKHL9Qa
# T8ECg52SDVY0KNjnnQLdzvs67o1W6awMUm9xiRag1s0Lj+6fvBm2yqqwnCy50is8
# hLt5pJG1BRQqfpmOFWHr5/g86n4aCwbWDkVIHEHtVpwnXJU5WReVOMOMgQ9UnTnj
# ZNTKzLl2Nu83wxAepsEyJaY8F6kL3+xwZpom9ZNE+OmF0NNT1b9iRehZ+G3WdIj3
# 3JX022RCJBUL06gGxi0aXgdhaerPPynvqz4r
# SIG # End signature block
