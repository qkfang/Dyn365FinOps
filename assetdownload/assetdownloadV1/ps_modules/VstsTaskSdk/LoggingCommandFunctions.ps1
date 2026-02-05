$script:loggingCommandPrefix = '##vso['
$script:loggingCommandEscapeMappings = @( # TODO: WHAT ABOUT "="? WHAT ABOUT "%"?
    New-Object psobject -Property @{ Token = ';' ; Replacement = '%3B' }
    New-Object psobject -Property @{ Token = "`r" ; Replacement = '%0D' }
    New-Object psobject -Property @{ Token = "`n" ; Replacement = '%0A' }
    New-Object psobject -Property @{ Token = "]" ; Replacement = '%5D' }
)
# TODO: BUG: Escape % ???
# TODO: Add test to verify don't need to escape "=".

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AddAttachment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'addattachment' -Data $Path -Properties @{
            'type' = $Type
            'name' = $Name
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'uploadsummary' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetEndpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Field,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setendpoint' -Data $Value -Properties @{
            'id' = $Id
            'field' = $Field
            'key' = $Key
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AddBuildTag {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'addbuildtag' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-AssociateArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [hashtable]$Properties,
        [switch]$AsOutput)

    $p = @{ }
    if ($Properties) {
        foreach ($key in $Properties.Keys) {
            $p[$key] = $Properties[$key]
        }
    }

    $p['artifactname'] = $Name
    $p['artifacttype'] = $Type
    Write-LoggingCommand -Area 'artifact' -Event 'associate' -Data $Path -Properties $p -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-LogDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [guid]$Id,
        $ParentId,
        [string]$Type,
        [string]$Name,
        $Order,
        $StartTime,
        $FinishTime,
        $Progress,
        [ValidateSet('Unknown', 'Initialized', 'InProgress', 'Completed')]
        [Parameter()]
        $State,
        [ValidateSet('Succeeded', 'SucceededWithIssues', 'Failed', 'Cancelled', 'Skipped')]
        [Parameter()]
        $Result,
        [string]$Message,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'logdetail' -Data $Message -Properties @{
            'id' = $Id
            'parentid' = $ParentId
            'type' = $Type
            'name' = $Name
            'order' = $Order
            'starttime' = $StartTime
            'finishtime' = $FinishTime
            'progress' = $Progress
            'state' = $State
            'result' = $Result
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetProgress {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 100)]
        [Parameter(Mandatory = $true)]
        [int]$Percent,
        [string]$CurrentOperation,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setprogress' -Data $CurrentOperation -Properties @{
            'value' = $Percent
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetResult {
    [CmdletBinding(DefaultParameterSetName = 'AsOutput')]
    param(
        [ValidateSet("Succeeded", "SucceededWithIssues", "Failed", "Cancelled", "Skipped")]
        [Parameter(Mandatory = $true)]
        [string]$Result,
        [string]$Message,
        [Parameter(ParameterSetName = 'AsOutput')]
        [switch]$AsOutput,
        [Parameter(ParameterSetName = 'DoNotThrow')]
        [switch]$DoNotThrow)

    Write-LoggingCommand -Area 'task' -Event 'complete' -Data $Message -Properties @{
            'result' = $Result
        } -AsOutput:$AsOutput
    if ($Result -eq 'Failed' -and !$AsOutput -and !$DoNotThrow) {
        # Special internal exception type to control the flow. Not currently intended
        # for public usage and subject to change.
        throw (New-Object VstsTaskSdk.TerminationException($Message))
    }
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setsecret' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-SetVariable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Value,
        [switch]$Secret,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'setvariable' -Data $Value -Properties @{
            'variable' = $Name
            'issecret' = $Secret
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskDebug {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsOutput)

    Write-TaskDebug_Internal @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskError {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput)

    Write-LogIssue -Type error @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskVerbose {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsOutput)

    Write-TaskDebug_Internal @PSBoundParameters -AsVerbose
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-TaskWarning {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput)

    Write-LogIssue -Type warning @PSBoundParameters
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'uploadfile' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-PrependPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'task' -Event 'prependpath' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UpdateBuildNumber {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'updatebuildnumber' -Data $Value -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadArtifact {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ContainerFolder,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'artifact' -Event 'upload' -Data $Path -Properties @{
            'containerfolder' = $ContainerFolder
            'artifactname' = $Name
        } -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UploadBuildLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'build' -Event 'uploadlog' -Data $Path -AsOutput:$AsOutput
}

<#
.SYNOPSIS
See https://github.com/Microsoft/vsts-tasks/blob/master/docs/authoring/commands.md

.PARAMETER AsOutput
Indicates whether to write the logging command directly to the host or to the output pipeline.
#>
function Write-UpdateReleaseName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [switch]$AsOutput)

    Write-LoggingCommand -Area 'release' -Event 'updatereleasename' -Data $Name -AsOutput:$AsOutput
}

########################################
# Private functions.
########################################
function Format-LoggingCommandData {
    [CmdletBinding()]
    param([string]$Value, [switch]$Reverse)

    if (!$Value) {
        return ''
    }

    if (!$Reverse) {
        foreach ($mapping in $script:loggingCommandEscapeMappings) {
            $Value = $Value.Replace($mapping.Token, $mapping.Replacement)
        }
    } else {
        for ($i = $script:loggingCommandEscapeMappings.Length - 1 ; $i -ge 0 ; $i--) {
            $mapping = $script:loggingCommandEscapeMappings[$i]
            $Value = $Value.Replace($mapping.Replacement, $mapping.Token)
        }
    }

    return $Value
}

function Format-LoggingCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Area,
        [Parameter(Mandatory = $true)]
        [string]$Event,
        [string]$Data,
        [hashtable]$Properties)

    # Append the preamble.
    [System.Text.StringBuilder]$sb = New-Object -TypeName System.Text.StringBuilder
    $null = $sb.Append($script:loggingCommandPrefix).Append($Area).Append('.').Append($Event)

    # Append the properties.
    if ($Properties) {
        $first = $true
        foreach ($key in $Properties.Keys) {
            [string]$value = Format-LoggingCommandData $Properties[$key]
            if ($value) {
                if ($first) {
                    $null = $sb.Append(' ')
                    $first = $false
                } else {
                    $null = $sb.Append(';')
                }

                $null = $sb.Append("$key=$value")
            }
        }
    }

    # Append the tail and output the value.
    $Data = Format-LoggingCommandData $Data
    $sb.Append(']').Append($Data).ToString()
}

function Write-LoggingCommand {
    [CmdletBinding(DefaultParameterSetName = 'Parameters')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Parameters')]
        [string]$Area,
        [Parameter(Mandatory = $true, ParameterSetName = 'Parameters')]
        [string]$Event,
        [Parameter(ParameterSetName = 'Parameters')]
        [string]$Data,
        [Parameter(ParameterSetName = 'Parameters')]
        [hashtable]$Properties,
        [Parameter(Mandatory = $true, ParameterSetName = 'Object')]
        $Command,
        [switch]$AsOutput)

    if ($PSCmdlet.ParameterSetName -eq 'Object') {
        Write-LoggingCommand -Area $Command.Area -Event $Command.Event -Data $Command.Data -Properties $Command.Properties -AsOutput:$AsOutput
        return
    }

    $command = Format-LoggingCommand -Area $Area -Event $Event -Data $Data -Properties $Properties
    if ($AsOutput) {
        $command
    } else {
        Write-Host $command
    }
}

function Write-LogIssue {
    [CmdletBinding()]
    param(
        [ValidateSet('warning', 'error')]
        [Parameter(Mandatory = $true)]
        [string]$Type,
        [string]$Message,
        [string]$ErrCode,
        [string]$SourcePath,
        [string]$LineNumber,
        [string]$ColumnNumber,
        [switch]$AsOutput)

    $command = Format-LoggingCommand -Area 'task' -Event 'logissue' -Data $Message -Properties @{
            'type' = $Type
            'code' = $ErrCode
            'sourcepath' = $SourcePath
            'linenumber' = $LineNumber
            'columnnumber' = $ColumnNumber
        }
    if ($AsOutput) {
        return $command
    }

    if ($Type -eq 'error') {
        $foregroundColor = $host.PrivateData.ErrorForegroundColor
        $backgroundColor = $host.PrivateData.ErrorBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Red
            $backgroundColor = [System.ConsoleColor]::Black
        }
    } else {
        $foregroundColor = $host.PrivateData.WarningForegroundColor
        $backgroundColor = $host.PrivateData.WarningBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Yellow
            $backgroundColor = [System.ConsoleColor]::Black
        }
    }

    Write-Host $command -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
}

function Write-TaskDebug_Internal {
    [CmdletBinding()]
    param(
        [string]$Message,
        [switch]$AsVerbose,
        [switch]$AsOutput)

    $command = Format-LoggingCommand -Area 'task' -Event 'debug' -Data $Message
    if ($AsOutput) {
        return $command
    }

    if ($AsVerbose) {
        $foregroundColor = $host.PrivateData.VerboseForegroundColor
        $backgroundColor = $host.PrivateData.VerboseBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::Cyan
            $backgroundColor = [System.ConsoleColor]::Black
        }
    } else {
        $foregroundColor = $host.PrivateData.DebugForegroundColor
        $backgroundColor = $host.PrivateData.DebugBackgroundColor
        if ($foregroundColor -isnot [System.ConsoleColor] -or $backgroundColor -isnot [System.ConsoleColor]) {
            $foregroundColor = [System.ConsoleColor]::DarkGray
            $backgroundColor = [System.ConsoleColor]::Black
        }
    }

    Write-Host -Object $command -ForegroundColor $foregroundColor -BackgroundColor $backgroundColor
}

# SIG # Begin signature block
# MIIoHgYJKoZIhvcNAQcCoIIoDzCCKAsCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCB0+boANff5ASRR
# lhXMjVOuhUVZV+d7kPDe8VZeK1FniqCCDYUwggYDMIID66ADAgECAhMzAAAEA73V
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
# cVZOSEXAQsmbdlsKgEhr/Xmfwb1tbWrJUnMTDXpQzTGCGe8wghnrAgEBMIGVMH4x
# CzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRt
# b25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKDAmBgNVBAMTH01p
# Y3Jvc29mdCBDb2RlIFNpZ25pbmcgUENBIDIwMTECEzMAAAQDvdWVXQ87GK0AAAAA
# BAMwDQYJYIZIAWUDBAIBBQCggZAwGQYJKoZIhvcNAQkDMQwGCisGAQQBgjcCAQQw
# LwYJKoZIhvcNAQkEMSIEIBAakg8X1pTUZLy5FMZXlHZ7vw5Lk4vizHJi3F87Blin
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAFnuwFDZHI8n3
# Wm+gVYnGFxUwqFoqkg8LhxdMLemfqhp8EAWIGMPhB6UmVDmuxQSMTTbvN2Ea9n6H
# EdJTKnnkjbpqStj6TiopDiBHY/lHxx22gaMzqVBbRNNWLZXKd5Be/cML7EB2K0Rj
# GQfjbK1WVB99rFOZaogqbkE46hbGBwBIN58P21K4MR3dJXH2clTRDYopPmF1JGs+
# N+X+sTW3EYQ+9SYEkNF2WV+YjTvriHKUuH6trS/p6Xl8HptJGA+2uDaNT2zbIIes
# vYOzBX2RFMAJoB1NJI4TegcSm1iVpBXJBXD+yD7rGVT+91YNT61ALcEcOcG805s/
# Z2RlY2w0gaGCF5cwgheTBgorBgEEAYI3AwMBMYIXgzCCF38GCSqGSIb3DQEHAqCC
# F3AwghdsAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEE
# ggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCC37gylgl37
# vEhgeaySBN6ZBMs14aEFiQzgCVIkr2IVxQIGZ/g/gJHlGBMyMDI1MDQxODAwMTkx
# MS4zMDVaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046RTAwMi0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHtMIIHIDCCBQigAwIB
# AgITMwAAAgsRnVYpkvm/hQABAAACCzANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNThaFw0yNjA0MjIxOTQy
# NThaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046RTAwMi0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQCqrPitRjAXqFh2IHzQYD3uykDPyJF+79e5CkY4aYsb93QVun4fZ3Ju/0WHrtAF
# 3JswSiAVl7p1H2zFKrvyhaVuRYcSc7YuyP0GHEVq7YVS5uF3YLlLeoyGOPKSXGs6
# agW60CqVBhPQ+2n49e6YD9wGv6Y0HmBKmnQqY/AKJijgUiRulb1ovNEcTZmTNRu1
# mY+0JjiEus+eF66VNoBv1a2MW0JPYbFBhPzFHlddFXcjf2qIkb5BYWsFL7QlBjXA
# pf2HmNrPzG36g1ybo/KnRjSgIRpHeYXxBIaCEGtR1EmpJ90OSFHxUu7eIjVfenqn
# Vtag0yAQY7zEWSXMN6+CHjv3SBNtm5ZIRyyCsUZG8454K+865bw7FwuH8vk5Q+07
# K5lFY02eBDw3UKzWjWvqTp2pK8MTa4kozvlKgrSGp5sh57GnkjlvNvt78NXbZTVI
# rwS7xcIGjbvS/2r5lRDT+Q3P2tT+g6KDPdLntlcbFdHuuzyJyx0WfCr8zHv8wGCB
# 3qPObRXK4opAInSQ4j5iS28KATJGwQabRueZvhvd9Od0wcFYOb4orUv1dD5XwFyK
# lGDPMcTPOQr0gxmEQVrLiJEoLyyW8EV/aDFUXToxyhfzWZ6Dc0l9eeth1Et2NQ3A
# /qBR5x33pjKdHJVJ5xpp2AI3ZzNYLDCqO1lthz1GaSz+PQIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFGZcLIjfr+l6WeMuhE9gsxe98j/+MB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQCaKPVn6GLcnkbPEdM0R9q4Zm0+7JfG05+pmqP6nA4SwT26k9HlJQjq
# w/+WkiQLD4owJxooIr9MDZbiZX6ypPhF+g1P5u8BOEXPYYkOWpzFGLRLtlZHvfxp
# qAIa7mjLGHDzKr/102AXaD4mGydEwaLGhUn9DBGdMm5dhiisWAqb/LN4lm4OuX4Y
# LqKcW/0yScHKgprGgLY+6pqv0zPU74j7eCr+PDTNYM8tFJ/btUnBNLyOE4WZwBIq
# 4tnvXjd2cCOtgUnoQjFU1ZY7ZWdny3BJbf3hBrb3NB2IU4nu622tVrb1fNkwdvT5
# 01WRUBMd9oFf4xifj2j2Clbv1XGljXmd6yJjvt+bBuvJLUuc9m+vMKOWyRwUdvOl
# /E5a8zV3MrjCnY6fIrLQNzBOZ6klICPCi+2GqbViM0CI6CbZypei5Rr9hJbH8rZE
# zjaYWLnr/XPsU0wr2Tn6L9dJx2q/LAoK+oviAInj0aP4iRrMyUSO6KL2KwY6zJc6
# SDxbHkwYHdQRrPNP3SutMg6LgBSvtmfqwgaXIHkCoiUFEAz9cGIqvgjGpGppKTcT
# uoo3EEgp/zRd0wxW0QqmV3ygYGicen30KAWHrKFC8Sbwc6qC4podVZYJZmirHBP/
# uo7sQne5H0xtdvDmXDUfy5gNjLljQIUsJhQSyyXbSjSb2a5jhOUfxzCCB3EwggVZ
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
# Yn/ZcGNTTY3ugm2lBRDBcQZqELQdVTNYs6FwZvKhggNQMIICOAIBATCB+aGB0aSB
# zjCByzELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcT
# B1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UE
# CxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVs
# ZCBUU1MgRVNOOkUwMDItMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQCoQndUJN3Ppq2xh8RhtsR3
# 5NCZwaCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBCwUAAgUA66v35jAiGA8yMDI1MDQxNzIxNTc1OFoYDzIwMjUwNDE4MjE1
# NzU4WjB3MD0GCisGAQQBhFkKBAExLzAtMAoCBQDrq/fmAgEAMAoCAQACAg/UAgH/
# MAcCAQACAhL7MAoCBQDrrUlmAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQB
# hFkKAwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEB
# AA+yd1QSLktmV1vap/pdarAQ+DXVaqnLVwepb7Mb+pm+TrIVwqliomfDRCMv+gNp
# OKvXxPwGmf2a/nHfOLTgZ1kHsc2OT0LJi/dDcsxZusoTn6tmb2Tf+tGF0dhvx/S+
# fFe0ZgmDmFzPc9fKpytt50YiVq/uoo3CmIEwXhwsHCFND3JZPaDVDeIR4bC9GdaY
# qaqOcm2Nxyg9B/5IaaU/2BoKbkXJWuhBH3PTX6dzYhOC9F1Ejcr9iXayp4Mlvzm1
# NLuapLBfyeMnkn0dxYBuyGPKpbreH19zdFfe9ma8Fb4FSCVHvlGsq1K0IoOW2F5Q
# kZO3q7boX2ksHfWn8fDEVdExggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzET
# MBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMV
# TWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1T
# dGFtcCBQQ0EgMjAxMAITMwAAAgsRnVYpkvm/hQABAAACCzANBglghkgBZQMEAgEF
# AKCCAUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEi
# BCDTx78Y6C5LLqQtBi4xvN4Xknj6JrfrGuDAhvaQhr5O/zCB+gYLKoZIhvcNAQkQ
# Ai8xgeowgecwgeQwgb0EIDTVdKu6N77bh0wdOyF+ogRN8vKJcw5jnf2/EussYkoz
# MIGYMIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAO
# BgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEm
# MCQGA1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAILEZ1W
# KZL5v4UAAQAAAgswIgQgS2mMemsbLcidDhqz/xfD7dYySRrzYk+gnDp1FGKMdLUw
# DQYJKoZIhvcNAQELBQAEggIATagzLeVjo6X9BEKf/qY3tRePXxPSYwcx+bnmom0P
# hcm1aAFG8g7rY5nZuEVljX4EwftLYv4EeWeiT3U2eb3FGnr12r/7m8bDqaRMyxHD
# 3hfKYkz2Pvxb0zcifA/d4PjKhtJaY5F1fJE6Zqy0wHhwN52QM7lT8TC4phI0NZs0
# H8BUlISI8HzkNc8VHKF+0CyneXPY8Ncin1ABMRT8mFQafXOAMO7M2RVwQ6mC1YT7
# RRbN27Nal/Cr1+DqySyeXoUwwjdr90Wsu3HzyQGjFPnwuS+QPDr07LrVCmTxt91n
# +j0B/ECioGm67Jkas4w06td3t6pp8uhajMJyd7h9AOn/2/iE5OVEMBWT1YRdS0Br
# g9FEm3ahRXXSWvvQ0CFAUgy2YuqbnlpUljaW8hMoPoNhCSkdU7rnDCO/GrxqbfMF
# LpTxbPJuLJOUdfhVBzCCUcgWB4/SvdnuVwgVqD0HIn818Gc6J3fby0lI9zr3jAC/
# xsn31LUoMbubh5ufx3hApwvFGZP34dZEGxn2SxxeT2Lbazbjth5IbG8rpS/J2Yu4
# nXIRxxe++/BUMy4xxrjASMXwehLVErq40HS+vZvNUckt5fpUrxc3rplRv1sEGaUe
# xcyNVTj1OHC8UP7ERbOHdbf3oRABnvpB62EdCk3hYgF4WJjkEusXkG2SCNflUdTt
# 0uU=
# SIG # End signature block
