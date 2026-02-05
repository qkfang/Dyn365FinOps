<#
.SYNOPSIS
Finds files or directories.

.DESCRIPTION
Finds files or directories using advanced pattern matching.

.PARAMETER LiteralDirectory
Directory to search.

.PARAMETER LegacyPattern
Proprietary pattern format. The LiteralDirectory parameter is used to root any unrooted patterns.

Separate multiple patterns using ";". Escape actual ";" in the path by using ";;".
"?" indicates a wildcard that represents any single character within a path segment.
"*" indicates a wildcard that represents zero or more characters within a path segment.
"**" as the entire path segment indicates a recursive search.
"**" within a path segment indicates a recursive intersegment wildcard.
"+:" (can be omitted) indicates an include pattern.
"-:" indicates an exclude pattern.

The result is from the command is a union of all the matches from the include patterns, minus the matches from the exclude patterns.

.PARAMETER IncludeFiles
Indicates whether to include files in the results.

If neither IncludeFiles or IncludeDirectories is set, then IncludeFiles is assumed.

.PARAMETER IncludeDirectories
Indicates whether to include directories in the results.

If neither IncludeFiles or IncludeDirectories is set, then IncludeFiles is assumed.

.PARAMETER Force
Indicates whether to include hidden items.

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\Is?Match.txt"

Given:
C:\Directory\Is1Match.txt
C:\Directory\Is2Match.txt
C:\Directory\IsNotMatch.txt

Returns:
C:\Directory\Is1Match.txt
C:\Directory\Is2Match.txt

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\Is*Match.txt"

Given:
C:\Directory\IsOneMatch.txt
C:\Directory\IsTwoMatch.txt
C:\Directory\NonMatch.txt

Returns:
C:\Directory\IsOneMatch.txt
C:\Directory\IsTwoMatch.txt

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\**\Match.txt"

Given:
C:\Directory\Match.txt
C:\Directory\NotAMatch.txt
C:\Directory\SubDir\Match.txt
C:\Directory\SubDir\SubSubDir\Match.txt

Returns:
C:\Directory\Match.txt
C:\Directory\SubDir\Match.txt
C:\Directory\SubDir\SubSubDir\Match.txt

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\**"

Given:
C:\Directory\One.txt
C:\Directory\SubDir\Two.txt
C:\Directory\SubDir\SubSubDir\Three.txt

Returns:
C:\Directory\One.txt
C:\Directory\SubDir\Two.txt
C:\Directory\SubDir\SubSubDir\Three.txt

.EXAMPLE
Find-VstsFiles -LegacyPattern "C:\Directory\Sub**Match.txt"

Given:
C:\Directory\IsNotAMatch.txt
C:\Directory\SubDir\IsAMatch.txt
C:\Directory\SubDir\IsNot.txt
C:\Directory\SubDir\SubSubDir\IsAMatch.txt
C:\Directory\SubDir\SubSubDir\IsNot.txt

Returns:
C:\Directory\SubDir\IsAMatch.txt
C:\Directory\SubDir\SubSubDir\IsAMatch.txt
#>
function Find-Files {
    [CmdletBinding()]
    param(
        [ValidateNotNullOrEmpty()]
        [Parameter()]
        [string]$LiteralDirectory,
        [Parameter(Mandatory = $true)]
        [string]$LegacyPattern,
        [switch]$IncludeFiles,
        [switch]$IncludeDirectories,
        [switch]$Force)

    # Note, due to subtle implementation details of Get-PathPrefix/Get-PathIterator,
    # this function does not appear to be able to search the root of a drive and other
    # cases where Path.GetDirectoryName() returns empty. More details in Get-PathPrefix.

    Trace-EnteringInvocation $MyInvocation
    if (!$IncludeFiles -and !$IncludeDirectories) {
        $IncludeFiles = $true
    }

    $includePatterns = New-Object System.Collections.Generic.List[string]
    $excludePatterns = New-Object System.Collections.Generic.List[System.Text.RegularExpressions.Regex]
    $LegacyPattern = $LegacyPattern.Replace(';;', "`0")
    foreach ($pattern in $LegacyPattern.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $pattern = $pattern.Replace("`0", ';')
        $isIncludePattern = Test-IsIncludePattern -Pattern ([ref]$pattern)
        if ($LiteralDirectory -and !([System.IO.Path]::IsPathRooted($pattern))) {
            # Use the root directory provided to make the pattern a rooted path.
            $pattern = [System.IO.Path]::Combine($LiteralDirectory, $pattern)
        }

        # Validate pattern does not end with a \.
        if ($pattern[$pattern.Length - 1] -eq [System.IO.Path]::DirectorySeparatorChar) {
            throw (Get-LocString -Key PSLIB_InvalidPattern0 -ArgumentList $pattern)
        }

        if ($isIncludePattern) {
            $includePatterns.Add($pattern)
        } else {
            $excludePatterns.Add((Convert-PatternToRegex -Pattern $pattern))
        }
    }

    $count = 0
    foreach ($path in (Get-MatchingItems -IncludePatterns $includePatterns -ExcludePatterns $excludePatterns -IncludeFiles:$IncludeFiles -IncludeDirectories:$IncludeDirectories -Force:$Force)) {
        $count++
        $path
    }

    Write-Verbose "Total found: $count"
    Trace-LeavingInvocation $MyInvocation
}

########################################
# Private functions.
########################################
function Convert-PatternToRegex {
    [CmdletBinding()]
    param([string]$Pattern)

    $Pattern = [regex]::Escape($Pattern.Replace('\', '/')). # Normalize separators and regex escape.
        Replace('/\*\*/', '((/.+/)|(/))'). # Replace directory globstar.
        Replace('\*\*', '.*'). # Replace remaining globstars with a wildcard that can span directory separators.
        Replace('\*', '[^/]*'). # Replace asterisks with a wildcard that cannot span directory separators.
        # bug: should be '[^/]' instead of '.'
        Replace('\?', '.') # Replace single character wildcards.
    New-Object regex -ArgumentList "^$Pattern`$", ([System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

function Get-FileNameFilter {
    [CmdletBinding()]
    param([string]$Pattern)

    $index = $Pattern.LastIndexOf('\')
    if ($index -eq -1 -or # Pattern does not contain a backslash.
        !($Pattern = $Pattern.Substring($index + 1)) -or # Pattern ends in a backslash.
        $Pattern.Contains('**')) # Last segment contains an inter-segment wildcard.
    {
        return '*'
    }

    # bug? is this supposed to do substring?
    return $Pattern
}

function Get-MatchingItems {
    [CmdletBinding()]
    param(
        [System.Collections.Generic.List[string]]$IncludePatterns,
        [System.Collections.Generic.List[regex]]$ExcludePatterns,
        [switch]$IncludeFiles,
        [switch]$IncludeDirectories,
        [switch]$Force)

    Trace-EnteringInvocation $MyInvocation
    $allFiles = New-Object System.Collections.Generic.HashSet[string]
    foreach ($pattern in $IncludePatterns) {
        $pathPrefix = Get-PathPrefix -Pattern $pattern
        $fileNameFilter = Get-FileNameFilter -Pattern $pattern
        $patternRegex = Convert-PatternToRegex -Pattern $pattern
        # Iterate over the directories and files under the pathPrefix.
        Get-PathIterator -Path $pathPrefix -Filter $fileNameFilter -IncludeFiles:$IncludeFiles -IncludeDirectories:$IncludeDirectories -Force:$Force |
            ForEach-Object {
                # Normalize separators.
                $normalizedPath = $_.Replace('\', '/')
                # **/times/** will not match C:/fun/times because there isn't a trailing slash.
                # So try both if including directories.
                $alternatePath = "$normalizedPath/" # potential bug: it looks like this will result in a false
                                                    # positive if the item is a regular file and not a directory

                $isMatch = $false
                if ($patternRegex.IsMatch($normalizedPath) -or ($IncludeDirectories -and $patternRegex.IsMatch($alternatePath))) {
                    $isMatch = $true

                    # Test whether the path should be excluded.
                    foreach ($regex in $ExcludePatterns) {
                        if ($regex.IsMatch($normalizedPath) -or ($IncludeDirectories -and $regex.IsMatch($alternatePath))) {
                            $isMatch = $false
                            break
                        }
                    }
                }

                if ($isMatch) {
                    $null = $allFiles.Add($_)
                }
            }
    }

    Trace-Path -Path $allFiles -PassThru
    Trace-LeavingInvocation $MyInvocation
}

function Get-PathIterator {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Filter,
        [switch]$IncludeFiles,
        [switch]$IncludeDirectories,
        [switch]$Force)

    if (!$Path) {
        return
    }

    # bug: this returns the dir without verifying whether exists
    if ($IncludeDirectories) {
        $Path
    }

    Get-DirectoryChildItem -Path $Path -Filter $Filter -Force:$Force -Recurse |
        ForEach-Object {
            if ($_.Attributes.HasFlag([VstsTaskSdk.FS.Attributes]::Directory)) {
                if ($IncludeDirectories) {
                    $_.FullName
                }
            } elseif ($IncludeFiles) {
                $_.FullName
            }
        }
}

function Get-PathPrefix {
    [CmdletBinding()]
    param([string]$Pattern)

    # Note, unable to search root directories is a limitation due to subtleties of this function
    # and downstream code in Get-PathIterator that short-circuits when the path prefix is empty.
    # This function uses Path.GetDirectoryName() to determine the path prefix, which will yield
    # empty in some cases. See the following examples of Path.GetDirectoryName() input => output:
    #       C:/             =>
    #       C:/hello        => C:\
    #       C:/hello/       => C:\hello
    #       C:/hello/world  => C:\hello
    #       C:/hello/world/ => C:\hello\world
    #       C:              =>
    #       C:hello         => C:
    #       C:hello/        => C:hello
    #       /               =>
    #       /hello          => \
    #       /hello/         => \hello
    #       //hello         =>
    #       //hello/        =>
    #       //hello/world   =>
    #       //hello/world/  => \\hello\world

    $index = $Pattern.IndexOfAny([char[]]@('*'[0], '?'[0]))
    if ($index -eq -1) {
        # If no wildcards are found, return the directory name portion of the path.
        # If there is no directory name (file name only in pattern), this will return empty string.
        return [System.IO.Path]::GetDirectoryName($Pattern)
    }

    [System.IO.Path]::GetDirectoryName($Pattern.Substring(0, $index))
}

function Test-IsIncludePattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ref]$Pattern)

    # Include patterns start with +: or anything except -:
    # Exclude patterns start with -:
    if ($Pattern.value.StartsWith("+:")) {
        # Remove the prefix.
        $Pattern.value = $Pattern.value.Substring(2)
        $true
    } elseif ($Pattern.value.StartsWith("-:")) {
        # Remove the prefix.
        $Pattern.value = $Pattern.value.Substring(2)
        $false
    } else {
        # No prefix, so leave the string alone.
        $true;
    }
}

# SIG # Begin signature block
# MIIoGwYJKoZIhvcNAQcCoIIoDDCCKAgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCCEgoqbR1JnXZQk
# uBUjU9+jNFOek9RcM71csGRMs2EuZaCCDYUwggYDMIID66ADAgECAhMzAAAEA73V
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
# LwYJKoZIhvcNAQkEMSIEILTvhbGnn2pPqE5VzN66QwmeqZtUrdYz4FAugQHIeTPQ
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAcbDHJg3fSUbu
# H32XbRfURZ5S3uyFKQrU0usD93FrJG/Hu022pjWkK//LU7HaUkGTHKIrUCiILseJ
# 3G/uov1Tbb0OUEwPuBI61XyVvB0KPSz0XSyECCmnRGcpNFqc8RIwbjJ7mF+O6Q4W
# Gco3nu1iFWB8F1MvFv+Y7AlpN4EBmRh3aRV79Vr0o4obFSll6y83XQ6SSf9aBbio
# oSlIWZavVi9qgNKqHeKlLa+Ka5c034YX3lp3E3acOEgq55zXDDUr6AvaKDQdZUXc
# PyowL8KqWwBDUaJ9cyZt6Ia/LDNDSB6XvyN3PCxHVE0vapP4qsxkyzq3K8m+01aj
# lceEhYM2o6GCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCC
# F20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEE
# ggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCCYigZv8b11
# 6ehrEgF4WlLSempvyOteYsgxKsYaIAReswIGZ/gcXNpxGBMyMDI1MDQxODAwMTkx
# MC44NDlaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
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
# AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCCM
# 9Ae5vP4CLKWI8ghvan+fMymqN7SHbKqH6bNR1E95/jCB+gYLKoZIhvcNAQkQAi8x
# geowgecwgeQwgb0EIE2ay/y0epK/X3Z03KTcloqE8u9IXRtdO7Mex0hw9+SaMIGY
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIKR7IU2e6y
# sw8AAQAAAgowIgQgDRaK3Ohk+Zwm39fM3jBl2Cf6gN1erFkhdc9QLdvsApgwDQYJ
# KoZIhvcNAQELBQAEggIAK6KhwmHqiaCDFUPxhDMd4+VMJCf86y/Z2QjRLjsdfUtA
# OQTM3nBiTYsospPC+2mxl7GAUQIeDDz6kHXfX/DTd9h3+tMFfrVA4WTID9uK+nYc
# c8MnUkxp3W5ftl3tOMouuoiI78aRwWrfN5LavKbO7ipMgWi05FQtp7wNQZ3O4tCG
# QJeSMKUnDtBVAQPjJUCntujgbsH1WB7h4KjDOhvXKr1hqCUxLnj6lIv4/QwIVSdx
# 4T5LImtVV655Buz3wMGIt+mQjP4FQgjp3gpWJWOKQXr90fMBSQhpiW+cOHbNq+vF
# t7jsc2DeM9Way3FWfT5BCKmJ5lWPjvFkgsvRlBT2d8umzgdS1sWs5e0uEqnh5sNI
# QenP/RQkGQi72jYyN9qg3x8/dsJlANB2SgEQi+25+c+gzEo4TAzAfrlDL67uHy+L
# bfOtsaSmknfitWk2m6X2GtkXvkhZCkUHlMl20qpYHjPMz1z4HOX4qJ2IgxNmwf/V
# rdegqcauH2So0Oi/JkK/uxz1kNHmyewbg+ey1Ki/TpLuDm1tPzjoXWgwO8PrG4oM
# UccfvUD1/1HsXjsLpsHBGiYNePTKvVNzkqhCveqn0/CTkqL6duBQnYki4ipPMXSQ
# D5tN4DhDHsV8g/H+awgWUUmzncMKPoOI6LSqUnRhbcADzyW+wdedM41A6b1nxhQ=
# SIG # End signature block
