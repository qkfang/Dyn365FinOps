# Hash table of known variable info. The formatted env var name is the lookup key.
#
# The purpose of this hash table is to keep track of known variables. The hash table
# needs to be maintained for multiple reasons:
#  1) to distinguish between env vars and job vars
#  2) to distinguish between secret vars and public
#  3) to know the real variable name and not just the formatted env var name.
$script:knownVariables = @{ }
$script:vault = @{ }

<#
.SYNOPSIS
Gets an endpoint.

.DESCRIPTION
Gets an endpoint object for the specified endpoint name. The endpoint is returned as an object with three properties: Auth, Data, and Url.

The Data property requires a 1.97 agent or higher.

.PARAMETER Require
Writes an error to the error pipeline if the endpoint is not found.
#>
function Get-Endpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$Require)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Get the URL.
        $description = Get-LocString -Key PSLIB_EndpointUrl0 -ArgumentList $Name
        $key = "ENDPOINT_URL_$Name"
        $url = Get-VaultValue -Description $description -Key $key -Require:$Require

        # Get the auth object.
        $description = Get-LocString -Key PSLIB_EndpointAuth0 -ArgumentList $Name
        $key = "ENDPOINT_AUTH_$Name"
        if ($auth = (Get-VaultValue -Description $description -Key $key -Require:$Require)) {
            $auth = ConvertFrom-Json -InputObject $auth
        }

        # Get the data.
        $description = "'$Name' service endpoint data"
        $key = "ENDPOINT_DATA_$Name"
        if ($data = (Get-VaultValue -Description $description -Key $key)) {
            $data = ConvertFrom-Json -InputObject $data
        }

        # Return the endpoint.
        if ($url -or $auth -or $data) {
            New-Object -TypeName psobject -Property @{
                Url = $url
                Auth = $auth
                Data = $data
            }
        }
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    }
}

<#
.SYNOPSIS
Gets a secure file ticket.

.DESCRIPTION
Gets the secure file ticket that can be used to download the secure file contents.

.PARAMETER Id
Secure file id.

.PARAMETER Require
Writes an error to the error pipeline if the ticket is not found.
#>
function Get-SecureFileTicket {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [switch]$Require)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        $description = Get-LocString -Key PSLIB_Input0 -ArgumentList $Id
        $key = "SECUREFILE_TICKET_$Id"
        
        Get-VaultValue -Description $description -Key $key -Require:$Require
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    }
}

<#
.SYNOPSIS
Gets a secure file name.

.DESCRIPTION
Gets the name for a secure file.

.PARAMETER Id
Secure file id.

.PARAMETER Require
Writes an error to the error pipeline if the ticket is not found.
#>
function Get-SecureFileName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [switch]$Require)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        $description = Get-LocString -Key PSLIB_Input0 -ArgumentList $Id
        $key = "SECUREFILE_NAME_$Id"
        
        Get-VaultValue -Description $description -Key $key -Require:$Require
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    }
}

<#
.SYNOPSIS
Gets an input.

.DESCRIPTION
Gets the value for the specified input name.

.PARAMETER AsBool
Returns the value as a bool. Returns true if the value converted to a string is "1" or "true" (case insensitive); otherwise false.

.PARAMETER AsInt
Returns the value as an int. Returns the value converted to an int. Returns 0 if the conversion fails.

.PARAMETER Default
Default value to use if the input is null or empty.

.PARAMETER Require
Writes an error to the error pipeline if the input is null or empty.
#>
function Get-Input {
    [CmdletBinding(DefaultParameterSetName = 'Require')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(ParameterSetName = 'Default')]
        $Default,
        [Parameter(ParameterSetName = 'Require')]
        [switch]$Require,
        [switch]$AsBool,
        [switch]$AsInt)

    # Get the input from the vault. Splat the bound parameters hashtable. Splatting is required
    # in order to concisely invoke the correct parameter set.
    $null = $PSBoundParameters.Remove('Name')
    $description = Get-LocString -Key PSLIB_Input0 -ArgumentList $Name
    $key = "INPUT_$($Name.Replace(' ', '_').ToUpperInvariant())"
    Get-VaultValue @PSBoundParameters -Description $description -Key $key
}

<#
.SYNOPSIS
Gets a task variable.

.DESCRIPTION
Gets the value for the specified task variable.

.PARAMETER AsBool
Returns the value as a bool. Returns true if the value converted to a string is "1" or "true" (case insensitive); otherwise false.

.PARAMETER AsInt
Returns the value as an int. Returns the value converted to an int. Returns 0 if the conversion fails.

.PARAMETER Default
Default value to use if the input is null or empty.

.PARAMETER Require
Writes an error to the error pipeline if the input is null or empty.
#>
function Get-TaskVariable {
    [CmdletBinding(DefaultParameterSetName = 'Require')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(ParameterSetName = 'Default')]
        $Default,
        [Parameter(ParameterSetName = 'Require')]
        [switch]$Require,
        [switch]$AsBool,
        [switch]$AsInt)

    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'
        $description = Get-LocString -Key PSLIB_TaskVariable0 -ArgumentList $Name
        $variableKey = Get-VariableKey -Name $Name
        if ($script:knownVariables.$variableKey.Secret) {
            # Get secret variable. Splatting is required to concisely invoke the correct parameter set.
            $null = $PSBoundParameters.Remove('Name')
            $vaultKey = "SECRET_$variableKey"
            Get-VaultValue @PSBoundParameters -Description $description -Key $vaultKey
        } else {
            # Get public variable.
            $item = $null
            $path = "Env:$variableKey"
            if ((Test-Path -LiteralPath $path) -and ($item = Get-Item -LiteralPath $path).Value) {
                # Intentionally empty. Value was successfully retrieved.
            } elseif (!$script:nonInteractive) {
                # The value wasn't found and the module is running in interactive dev mode.
                # Prompt for the value.
                Set-Item -LiteralPath $path -Value (Read-Host -Prompt $description)
                if (Test-Path -LiteralPath $path) {
                    $item = Get-Item -LiteralPath $path
                }
            }

            # Get the converted value. Splatting is required to concisely invoke the correct parameter set.
            $null = $PSBoundParameters.Remove('Name')
            Get-Value @PSBoundParameters -Description $description -Key $variableKey -Value $item.Value
        }
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    }
}

<#
.SYNOPSIS
Gets all job variables available to the task. Requires 2.104.1 agent or higher.

.DESCRIPTION
Gets a snapshot of the current state of all job variables available to the task.
Requires a 2.104.1 agent or higher for full functionality.

Returns an array of objects with the following properties:
    [string]Name
    [string]Value
    [bool]Secret

Limitations on an agent prior to 2.104.1:
 1) The return value does not include all public variables. Only public variables
    that have been added using setVariable are returned.
 2) The name returned for each secret variable is the formatted environment variable
    name, not the actual variable name (unless it was set explicitly at runtime using
    setVariable).
#>
function Get-TaskVariableInfo {
    [CmdletBinding()]
    param()

    foreach ($info in $script:knownVariables.Values) {
        New-Object -TypeName psobject -Property @{
            Name = $info.Name
            Value = Get-TaskVariable -Name $info.Name
            Secret = $info.Secret
        }
    }
}

<#
.SYNOPSIS
Sets a task variable.

.DESCRIPTION
Sets a task variable in the current task context as well as in the current job context. This allows the task variable to retrieved by subsequent tasks within the same job.
#>
function Set-TaskVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Value,
        [switch]$Secret)

    # Once a secret always a secret.
    $variableKey = Get-VariableKey -Name $Name
    [bool]$Secret = $Secret -or $script:knownVariables.$variableKey.Secret
    if ($Secret) {
        $vaultKey = "SECRET_$variableKey"
        if (!$Value) {
            # Clear the secret.
            Write-Verbose "Set $Name = ''"
            $script:vault.Remove($vaultKey)
        } else {
            # Store the secret in the vault.
            Write-Verbose "Set $Name = '********'"
            $script:vault[$vaultKey] = New-Object System.Management.Automation.PSCredential(
                $vaultKey,
                (ConvertTo-SecureString -String $Value -AsPlainText -Force))
        }

        # Clear the environment variable.
        Set-Item -LiteralPath "Env:$variableKey" -Value ''
    } else {
        # Set the environment variable.
        Write-Verbose "Set $Name = '$Value'"
        Set-Item -LiteralPath "Env:$variableKey" -Value $Value
    }

    # Store the metadata.
    $script:knownVariables[$variableKey] = New-Object -TypeName psobject -Property @{
            Name = $name
            Secret = $Secret
        }

    # Persist the variable in the task context.
    Write-SetVariable -Name $Name -Value $Value -Secret:$Secret
}

########################################
# Private functions.
########################################
function Get-VaultValue {
    [CmdletBinding(DefaultParameterSetName = 'Require')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(ParameterSetName = 'Require')]
        [switch]$Require,
        [Parameter(ParameterSetName = 'Default')]
        [object]$Default,
        [switch]$AsBool,
        [switch]$AsInt)

    # Attempt to get the vault value.
    $value = $null
    if ($psCredential = $script:vault[$Key]) {
        $value = $psCredential.GetNetworkCredential().Password
    } elseif (!$script:nonInteractive) {
        # The value wasn't found. Prompt for the value if running in interactive dev mode.
        $value = Read-Host -Prompt $Description
        if ($value) {
            $script:vault[$Key] = New-Object System.Management.Automation.PSCredential(
                $Key,
                (ConvertTo-SecureString -String $value -AsPlainText -Force))
        }
    }

    Get-Value -Value $value @PSBoundParameters
}

function Get-Value {
    [CmdletBinding(DefaultParameterSetName = 'Require')]
    param(
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [string]$Description,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(ParameterSetName = 'Require')]
        [switch]$Require,
        [Parameter(ParameterSetName = 'Default')]
        [object]$Default,
        [switch]$AsBool,
        [switch]$AsInt)

    $result = $Value
    if ($result) {
        if ($Key -like 'ENDPOINT_AUTH_*') {
            Write-Verbose "$($Key): '********'"
        } else {
            Write-Verbose "$($Key): '$result'"
        }
    } else {
        Write-Verbose "$Key (empty)"

        # Write error if required.
        if ($Require) {
            Write-Error "$(Get-LocString -Key PSLIB_Required0 $Description)"
            return
        }

        # Fallback to the default if provided.
        if ($PSCmdlet.ParameterSetName -eq 'Default') {
            $result = $Default
            $OFS = ' '
            Write-Verbose " Defaulted to: '$result'"
        } else {
            $result = ''
        }
    }

    # Convert to bool if specified.
    if ($AsBool) {
        if ($result -isnot [bool]) {
            $result = "$result" -in '1', 'true'
            Write-Verbose " Converted to bool: $result"
        }

        return $result
    }

    # Convert to int if specified.
    if ($AsInt) {
        if ($result -isnot [int]) {
            try {
                $result = [int]"$result"
            } catch {
                $result = 0
            }

            Write-Verbose " Converted to int: $result"
        }

        return $result
    }

    return $result
}

function Initialize-Inputs {
    # Store endpoints, inputs, and secret variables in the vault.
    foreach ($variable in (Get-ChildItem -Path Env:ENDPOINT_?*, Env:INPUT_?*, Env:SECRET_?*, Env:SECUREFILE_?*)) {
        # Record the secret variable metadata. This is required by Get-TaskVariable to
        # retrieve the value. In a 2.104.1 agent or higher, this metadata will be overwritten
        # when $env:VSTS_SECRET_VARIABLES is processed.
        if ($variable.Name -like 'SECRET_?*') {
            $variableKey = $variable.Name.Substring('SECRET_'.Length)
            $script:knownVariables[$variableKey] = New-Object -TypeName psobject -Property @{
                # This is technically not the variable name (has underscores instead of dots),
                # but it's good enough to make Get-TaskVariable work in a pre-2.104.1 agent
                # where $env:VSTS_SECRET_VARIABLES is not defined.
                Name = $variableKey
                Secret = $true
            }
        }

        # Store the value in the vault.
        $vaultKey = $variable.Name
        if ($variable.Value) {
            $script:vault[$vaultKey] = New-Object System.Management.Automation.PSCredential(
                $vaultKey,
                (ConvertTo-SecureString -String $variable.Value -AsPlainText -Force))
        }

        # Clear the environment variable.
        Remove-Item -LiteralPath "Env:$($variable.Name)"
    }

    # Record the public variable names. Env var added in 2.104.1 agent.
    if ($env:VSTS_PUBLIC_VARIABLES) {
        foreach ($name in (ConvertFrom-Json -InputObject $env:VSTS_PUBLIC_VARIABLES)) {
            $variableKey = Get-VariableKey -Name $name
            $script:knownVariables[$variableKey] = New-Object -TypeName psobject -Property @{
                Name = $name
                Secret = $false
            }
        }

        $env:VSTS_PUBLIC_VARIABLES = ''
    }

    # Record the secret variable names. Env var added in 2.104.1 agent.
    if ($env:VSTS_SECRET_VARIABLES) {
        foreach ($name in (ConvertFrom-Json -InputObject $env:VSTS_SECRET_VARIABLES)) {
            $variableKey = Get-VariableKey -Name $name
            $script:knownVariables[$variableKey] = New-Object -TypeName psobject -Property @{
                Name = $name
                Secret = $true
            }
        }

        $env:VSTS_SECRET_VARIABLES = ''
    }
}

function Get-VariableKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name)

    if ($Name -ne 'agent.jobstatus') {
        $Name = $Name.Replace('.', '_')
    }

    $Name.ToUpperInvariant()
}

# SIG # Begin signature block
# MIIoDAYJKoZIhvcNAQcCoIIn/TCCJ/kCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCBbqQXYs0XjHxpR
# oVUQXMXqm82JS7ioyoz7KfWP6suubqCCDXYwggX0MIID3KADAgECAhMzAAAEBGx0
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
# IMa5m4zRRGS16pCxk189hJF63LwMNL1HuUTMGrD/e2ObMEIGCisGAQQBgjcCAQwx
# NDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRwOi8vd3d3Lm1pY3Jvc29m
# dC5jb20wDQYJKoZIhvcNAQEBBQAEggEAqfqIzWq9Vbv2sero+yVxDtdIECw6aHYl
# +oxKTVkjoyi0oTes6nMz0UdkJlm0ia/uGTw65zpTPf/tIaRvhbjE5ucq4Ln8kLWj
# sY53fhKsW6zoBaj4yPw9sxQX9dTZyEW2mNfQlXuIPYkVZTKm3OQcPVI04nuJvhU/
# W1BVjJCFCrJC0t2pXnc5xZeeSYemNu4IgQOhUcGSKaHkZHUk4rnasPHGMRGwocDe
# QWFw3CqTYeMEfHkllvFTGeEYIBJcfdIOH+EIXXJLT3fyJaFjH0HaWU6Jw5SZgWu3
# XeWC7lJtsd/QWp+LMjyltGa+CaoMaYLfzk4dRvMzBQ8e5zJ3Xd2vzqGCF5QwgheQ
# BgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCCF20wghdpAgEDMQ8wDQYJ
# YIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEEggE9MIIBOQIBAQYKKwYB
# BAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCA8nTBKiEPzYMWMG4Hea4nPiyr84usV
# 32PufThUtEKHXAIGZ/fVkpuUGBMyMDI1MDQxODAwMTkxMC4wOTlaMASAAgH0oIHR
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
# MQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCD8xrXOnv2NAHdkIkode1uS
# e28PGsxaIhrR6FRyAzTkGTCB+gYLKoZIhvcNAQkQAi8xgeowgecwgeQwgb0EII//
# jm8JHa2W1O9778t9+Ft2Z5NmKqttPk6Q+9RRpmepMIGYMIGApH4wfDELMAkGA1UE
# BhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQGA1UEAxMdTWljcm9zb2Z0
# IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIIeJ1YXZLH2VIAAQAAAggwIgQg4TnI
# KP+IV/R8in9i4lsy3mMQAxN6dnWjyETrR7GyAi0wDQYJKoZIhvcNAQELBQAEggIA
# VDw7uWanBafQ7yQYTXMig4L9B7bvJKFSZz3o+etxO1HPRIp8Nk2jxMYy/7ZCahUC
# gI+KSFZZCKXAqrlFwwuorda4vkfEdRItdjHwtmOXYsMK/FOEZbuJLBxHjJWSsj8o
# nDP0lnCOY+MXwO4yCUho4g6+vTwYwO6iVSh7t50CAtWpTaS3B/RjIa27HS4R8Q0h
# zv9OQ0NMJCcRlJJjFNAn/Qw1t4OpNTJTsaUbJLaMQqSioQzq8jv3P9WzrWHxehph
# yCgNaGL8qGiC61TtEc8ZfaZOi9zH+WIpD24M69dAmrOKgqKvM8HEJlB+XxvtlNWn
# eO2sIxXA3jnj/7nwVO6FlBTyYFbPE4S93fPGgAbjoNMvey74LsPLv05CaLjgYhXw
# Ahdj3hMFEzsTF6QJcS7bKf9UsbL7rS290FwWD8jdvece4veeTCkdxDoC814n0frO
# mMTPpZyiU0wApLgEWIZSK2kz+DKN3ZMhwCoixPe0mGEDrC3Kv63k8+fmuCDBhIpM
# 8XFnqtVNBPu7rsnQelC7oib+nZYh3aPv2aXnd9A3h28ZQQ+gEGh9h+N3SR7+VNCH
# MZGiAlLvLBv+nQwjBFgii6fLFvPYRrtehzJeqLZn8UwlI96g9uGE3UuI9SR5y/jH
# 2Jq3sEkeusTPj1kD5hyhJB986Pq0I0ff8/IqxlTY40E=
# SIG # End signature block
