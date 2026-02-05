<#
.SYNOPSIS
Finds files using match patterns.

.DESCRIPTION
Determines the find root from a list of patterns. Performs the find and then applies the glob patterns. Supports interleaved exclude patterns. Unrooted patterns are rooted using defaultRoot, unless matchOptions.matchBase is specified and the pattern is a basename only. For matchBase cases, the defaultRoot is used as the find root.

.PARAMETER DefaultRoot
Default path to root unrooted patterns. Falls back to System.DefaultWorkingDirectory or current location.

.PARAMETER Pattern
Patterns to apply. Supports interleaved exclude patterns.

.PARAMETER FindOptions
When the FindOptions parameter is not specified, defaults to (New-VstsFindOptions -FollowSymbolicLinksTrue). Following soft links is generally appropriate unless deleting files.

.PARAMETER MatchOptions
When the MatchOptions parameter is not specified, defaults to (New-VstsMatchOptions -Dot -NoBrace -NoCase).
#>
function Find-Match {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$DefaultRoot,
        [Parameter()]
        [string[]]$Pattern,
        $FindOptions,
        $MatchOptions)

    Trace-EnteringInvocation $MyInvocation -Parameter None
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'

        # Apply defaults for parameters and trace.
        if (!$DefaultRoot) {
            $DefaultRoot = Get-TaskVariable -Name 'System.DefaultWorkingDirectory' -Default (Get-Location).Path
        }

        Write-Verbose "DefaultRoot: '$DefaultRoot'"
        if (!$FindOptions) {
            $FindOptions = New-FindOptions -FollowSpecifiedSymbolicLink -FollowSymbolicLinks
        }

        Trace-FindOptions -Options $FindOptions
        if (!$MatchOptions) {
            $MatchOptions = New-MatchOptions -Dot -NoBrace -NoCase
        }

        Trace-MatchOptions -Options $MatchOptions
        Add-Type -LiteralPath $PSScriptRoot\Minimatch.dll

        # Normalize slashes for root dir.
        $DefaultRoot = ConvertTo-NormalizedSeparators -Path $DefaultRoot

        $results = @{ }
        $originalMatchOptions = $MatchOptions
        foreach ($pat in $Pattern) {
            Write-Verbose "Pattern: '$pat'"

            # Trim and skip empty.
            $pat = "$pat".Trim()
            if (!$pat) {
                Write-Verbose 'Skipping empty pattern.'
                continue
            }

            # Clone match options.
            $MatchOptions = Copy-MatchOptions -Options $originalMatchOptions

            # Skip comments.
            if (!$MatchOptions.NoComment -and $pat.StartsWith('#')) {
                Write-Verbose 'Skipping comment.'
                continue
            }

            # Set NoComment. Brace expansion could result in a leading '#'.
            $MatchOptions.NoComment = $true

            # Determine whether pattern is include or exclude.
            $negateCount = 0
            if (!$MatchOptions.NoNegate) {
                while ($negateCount -lt $pat.Length -and $pat[$negateCount] -eq '!') {
                    $negateCount++
                }

                $pat = $pat.Substring($negateCount) # trim leading '!'
                if ($negateCount) {
                    Write-Verbose "Trimmed leading '!'. Pattern: '$pat'"
                }
            }

            $isIncludePattern = $negateCount -eq 0 -or
                ($negateCount % 2 -eq 0 -and !$MatchOptions.FlipNegate) -or
                ($negateCount % 2 -eq 1 -and $MatchOptions.FlipNegate)

            # Set NoNegate. Brace expansion could result in a leading '!'.
            $MatchOptions.NoNegate = $true
            $MatchOptions.FlipNegate = $false

            # Trim and skip empty.
            $pat = "$pat".Trim()
            if (!$pat) {
                Write-Verbose 'Skipping empty pattern.'
                continue
            }

            # Expand braces - required to accurately interpret findPath.
            $expanded = $null
            $preExpanded = $pat
            if ($MatchOptions.NoBrace) {
                $expanded = @( $pat )
            } else {
                # Convert slashes on Windows before calling braceExpand(). Unfortunately this means braces cannot
                # be escaped on Windows, this limitation is consistent with current limitations of minimatch (3.0.3).
                Write-Verbose "Expanding braces."
                $convertedPattern = $pat -replace '\\', '/'
                $expanded = [Minimatch.Minimatcher]::BraceExpand(
                    $convertedPattern,
                    (ConvertTo-MinimatchOptions -Options $MatchOptions))
            }

            # Set NoBrace.
            $MatchOptions.NoBrace = $true

            foreach ($pat in $expanded) {
                if ($pat -ne $preExpanded) {
                    Write-Verbose "Pattern: '$pat'"
                }

                # Trim and skip empty.
                $pat = "$pat".Trim()
                if (!$pat) {
                    Write-Verbose "Skipping empty pattern."
                    continue
                }

                if ($isIncludePattern) {
                    # Determine the findPath.
                    $findInfo = Get-FindInfoFromPattern -DefaultRoot $DefaultRoot -Pattern $pat -MatchOptions $MatchOptions
                    $findPath = $findInfo.FindPath
                    Write-Verbose "FindPath: '$findPath'"

                    if (!$findPath) {
                        Write-Verbose "Skipping empty path."
                        continue
                    }

                    # Perform the find.
                    Write-Verbose "StatOnly: '$($findInfo.StatOnly)'"
                    [string[]]$findResults = @( )
                    if ($findInfo.StatOnly) {
                        # Simply stat the path - all path segments were used to build the path.
                        if ((Test-Path -LiteralPath $findPath)) {
                            $findResults += $findPath
                        }
                    } else {
                        $findResults = Get-FindResult -Path $findPath -Options $FindOptions
                    }

                    Write-Verbose "Found $($findResults.Count) paths."

                    # Apply the pattern.
                    Write-Verbose "Applying include pattern."
                    if ($findInfo.AdjustedPattern -ne $pat) {
                        Write-Verbose "AdjustedPattern: '$($findInfo.AdjustedPattern)'"
                        $pat = $findInfo.AdjustedPattern
                    }

                    $matchResults = [Minimatch.Minimatcher]::Filter(
                        $findResults,
                        $pat,
                        (ConvertTo-MinimatchOptions -Options $MatchOptions))

                    # Union the results.
                    $matchCount = 0
                    foreach ($matchResult in $matchResults) {
                        $matchCount++
                        $results[$matchResult.ToUpperInvariant()] = $matchResult
                    }

                    Write-Verbose "$matchCount matches"
                } else {
                    # Check if basename only and MatchBase=true.
                    if ($MatchOptions.MatchBase -and
                        !(Test-Rooted -Path $pat) -and
                        ($pat -replace '\\', '/').IndexOf('/') -lt 0) {

                        # Do not root the pattern.
                        Write-Verbose "MatchBase and basename only."
                    } else {
                        # Root the exclude pattern.
                        $pat = Get-RootedPattern -DefaultRoot $DefaultRoot -Pattern $pat
                        Write-Verbose "After Get-RootedPattern, pattern: '$pat'"
                    }

                    # Apply the pattern.
                    Write-Verbose 'Applying exclude pattern.'
                    $matchResults = [Minimatch.Minimatcher]::Filter(
                        [string[]]$results.Values,
                        $pat,
                        (ConvertTo-MinimatchOptions -Options $MatchOptions))

                    # Subtract the results.
                    $matchCount = 0
                    foreach ($matchResult in $matchResults) {
                        $matchCount++
                        $results.Remove($matchResult.ToUpperInvariant())
                    }

                    Write-Verbose "$matchCount matches"
                }
            }
        }

        $finalResult = @( $results.Values | Sort-Object )
        Write-Verbose "$($finalResult.Count) final results"
        return $finalResult
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

<#
.SYNOPSIS
Creates FindOptions for use with Find-VstsMatch.

.DESCRIPTION
Creates FindOptions for use with Find-VstsMatch. Contains switches to control whether to follow symlinks.

.PARAMETER FollowSpecifiedSymbolicLink
Indicates whether to traverse descendants if the specified path is a symbolic link directory. Does not cause nested symbolic link directories to be traversed.

.PARAMETER FollowSymbolicLinks
Indicates whether to traverse descendants of symbolic link directories.
#>
function New-FindOptions {
    [CmdletBinding()]
    param(
        [switch]$FollowSpecifiedSymbolicLink,
        [switch]$FollowSymbolicLinks)

    return New-Object psobject -Property @{
        FollowSpecifiedSymbolicLink = $FollowSpecifiedSymbolicLink.IsPresent
        FollowSymbolicLinks = $FollowSymbolicLinks.IsPresent
    }
}

<#
.SYNOPSIS
Creates MatchOptions for use with Find-VstsMatch and Select-VstsMatch.

.DESCRIPTION
Creates MatchOptions for use with Find-VstsMatch and Select-VstsMatch. Contains switches to control which pattern matching options are applied.
#>
function New-MatchOptions {
    [CmdletBinding()]
    param(
        [switch]$Dot,
        [switch]$FlipNegate,
        [switch]$MatchBase,
        [switch]$NoBrace,
        [switch]$NoCase,
        [switch]$NoComment,
        [switch]$NoExt,
        [switch]$NoGlobStar,
        [switch]$NoNegate,
        [switch]$NoNull)

    return New-Object psobject -Property @{
        Dot = $Dot.IsPresent
        FlipNegate = $FlipNegate.IsPresent
        MatchBase = $MatchBase.IsPresent
        NoBrace = $NoBrace.IsPresent
        NoCase = $NoCase.IsPresent
        NoComment = $NoComment.IsPresent
        NoExt = $NoExt.IsPresent
        NoGlobStar = $NoGlobStar.IsPresent
        NoNegate = $NoNegate.IsPresent
        NoNull = $NoNull.IsPresent
    }
}

<#
.SYNOPSIS
Applies match patterns against a list of files.

.DESCRIPTION
Applies match patterns to a list of paths. Supports interleaved exclude patterns.

.PARAMETER ItemPath
Array of paths.

.PARAMETER Pattern
Patterns to apply. Supports interleaved exclude patterns.

.PARAMETER PatternRoot
Default root to apply to unrooted patterns. Not applied to basename-only patterns when Options.MatchBase is true.

.PARAMETER Options
When the Options parameter is not specified, defaults to (New-VstsMatchOptions -Dot -NoBrace -NoCase).
#>
function Select-Match {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string[]]$ItemPath,
        [Parameter()]
        [string[]]$Pattern,
        [Parameter()]
        [string]$PatternRoot,
        $Options)


    Trace-EnteringInvocation $MyInvocation -Parameter None
    $originalErrorActionPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Stop'
        if (!$Options) {
            $Options = New-MatchOptions -Dot -NoBrace -NoCase
        }

        Trace-MatchOptions -Options $Options
        Add-Type -LiteralPath $PSScriptRoot\Minimatch.dll

        # Hashtable to keep track of matches.
        $map = @{ }

        $originalOptions = $Options
        foreach ($pat in $Pattern) {
            Write-Verbose "Pattern: '$pat'"

            # Trim and skip empty.
            $pat = "$pat".Trim()
            if (!$pat) {
                Write-Verbose 'Skipping empty pattern.'
                continue
            }

            # Clone match options.
            $Options = Copy-MatchOptions -Options $originalOptions

            # Skip comments.
            if (!$Options.NoComment -and $pat.StartsWith('#')) {
                Write-Verbose 'Skipping comment.'
                continue
            }

            # Set NoComment. Brace expansion could result in a leading '#'.
            $Options.NoComment = $true

            # Determine whether pattern is include or exclude.
            $negateCount = 0
            if (!$Options.NoNegate) {
                while ($negateCount -lt $pat.Length -and $pat[$negateCount] -eq '!') {
                    $negateCount++
                }

                $pat = $pat.Substring($negateCount) # trim leading '!'
                if ($negateCount) {
                    Write-Verbose "Trimmed leading '!'. Pattern: '$pat'"
                }
            }

            $isIncludePattern = $negateCount -eq 0 -or
                ($negateCount % 2 -eq 0 -and !$Options.FlipNegate) -or
                ($negateCount % 2 -eq 1 -and $Options.FlipNegate)

            # Set NoNegate. Brace expansion could result in a leading '!'.
            $Options.NoNegate = $true
            $Options.FlipNegate = $false

            # Expand braces - required to accurately root patterns.
            $expanded = $null
            $preExpanded = $pat
            if ($Options.NoBrace) {
                $expanded = @( $pat )
            } else {
                # Convert slashes on Windows before calling braceExpand(). Unfortunately this means braces cannot
                # be escaped on Windows, this limitation is consistent with current limitations of minimatch (3.0.3).
                Write-Verbose "Expanding braces."
                $convertedPattern = $pat -replace '\\', '/'
                $expanded = [Minimatch.Minimatcher]::BraceExpand(
                    $convertedPattern,
                    (ConvertTo-MinimatchOptions -Options $Options))
            }

            # Set NoBrace.
            $Options.NoBrace = $true

            foreach ($pat in $expanded) {
                if ($pat -ne $preExpanded) {
                    Write-Verbose "Pattern: '$pat'"
                }

                # Trim and skip empty.
                $pat = "$pat".Trim()
                if (!$pat) {
                    Write-Verbose "Skipping empty pattern."
                    continue
                }

                # Root the pattern when all of the following conditions are true:
                if ($PatternRoot -and               # PatternRoot is supplied
                    !(Test-Rooted -Path $pat) -and  # AND pattern is not rooted
                    #                               # AND MatchBase=false or not basename only
                    (!$Options.MatchBase -or ($pat -replace '\\', '/').IndexOf('/') -ge 0)) {

                    # Root the include pattern.
                    $pat = Get-RootedPattern -DefaultRoot $PatternRoot -Pattern $pat
                    Write-Verbose "After Get-RootedPattern, pattern: '$pat'"
                }

                if ($isIncludePattern) {
                    # Apply the pattern.
                    Write-Verbose 'Applying include pattern against original list.'
                    $matchResults = [Minimatch.Minimatcher]::Filter(
                        $ItemPath,
                        $pat,
                        (ConvertTo-MinimatchOptions -Options $Options))

                    # Union the results.
                    $matchCount = 0
                    foreach ($matchResult in $matchResults) {
                        $matchCount++
                        $map[$matchResult] = $true
                    }

                    Write-Verbose "$matchCount matches"
                } else {
                    # Apply the pattern.
                    Write-Verbose 'Applying exclude pattern against original list'
                    $matchResults = [Minimatch.Minimatcher]::Filter(
                        $ItemPath,
                        $pat,
                        (ConvertTo-MinimatchOptions -Options $Options))

                    # Subtract the results.
                    $matchCount = 0
                    foreach ($matchResult in $matchResults) {
                        $matchCount++
                        $map.Remove($matchResult)
                    }

                    Write-Verbose "$matchCount matches"
                }
            }
        }

        # return a filtered version of the original list (preserves order and prevents duplication)
        $result = $ItemPath | Where-Object { $map[$_] }
        Write-Verbose "$($result.Count) final results"
        $result
    } catch {
        $ErrorActionPreference = $originalErrorActionPreference
        Write-Error $_
    } finally {
        Trace-LeavingInvocation -InvocationInfo $MyInvocation
    }
}

################################################################################
# Private functions.
################################################################################

function Copy-MatchOptions {
    [CmdletBinding()]
    param($Options)

    return New-Object psobject -Property @{
        Dot = $Options.Dot -eq $true
        FlipNegate = $Options.FlipNegate -eq $true
        MatchBase = $Options.MatchBase -eq $true
        NoBrace = $Options.NoBrace -eq $true
        NoCase = $Options.NoCase -eq $true
        NoComment = $Options.NoComment -eq $true
        NoExt = $Options.NoExt -eq $true
        NoGlobStar = $Options.NoGlobStar -eq $true
        NoNegate = $Options.NoNegate -eq $true
        NoNull = $Options.NoNull -eq $true
    }
}

function ConvertTo-MinimatchOptions {
    [CmdletBinding()]
    param($Options)

    $opt = New-Object Minimatch.Options
    $opt.AllowWindowsPaths = $true
    $opt.Dot = $Options.Dot -eq $true
    $opt.FlipNegate = $Options.FlipNegate -eq $true
    $opt.MatchBase = $Options.MatchBase -eq $true
    $opt.NoBrace = $Options.NoBrace -eq $true
    $opt.NoCase = $Options.NoCase -eq $true
    $opt.NoComment = $Options.NoComment -eq $true
    $opt.NoExt = $Options.NoExt -eq $true
    $opt.NoGlobStar = $Options.NoGlobStar -eq $true
    $opt.NoNegate = $Options.NoNegate -eq $true
    $opt.NoNull = $Options.NoNull -eq $true
    return $opt
}

function ConvertTo-NormalizedSeparators {
    [CmdletBinding()]
    param([string]$Path)

    # Convert slashes.
    $Path = "$Path".Replace('/', '\')

    # Remove redundant slashes.
    $isUnc = $Path -match '^\\\\+[^\\]'
    $Path = $Path -replace '\\\\+', '\'
    if ($isUnc) {
        $Path = '\' + $Path
    }

    return $Path
}

function Get-FindInfoFromPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefaultRoot,
        [Parameter(Mandatory = $true)]
        [string]$Pattern,
        [Parameter(Mandatory = $true)]
        $MatchOptions)

    if (!$MatchOptions.NoBrace) {
        throw "Get-FindInfoFromPattern expected MatchOptions.NoBrace to be true."
    }

    # For the sake of determining the find path, pretend NoCase=false.
    $MatchOptions = Copy-MatchOptions -Options $MatchOptions
    $MatchOptions.NoCase = $false

    # Check if basename only and MatchBase=true
    if ($MatchOptions.MatchBase -and
        !(Test-Rooted -Path $Pattern) -and
        ($Pattern -replace '\\', '/').IndexOf('/') -lt 0) {

        return New-Object psobject -Property @{
            AdjustedPattern = $Pattern
            FindPath = $DefaultRoot
            StatOnly = $false
        }
    }

    # The technique applied by this function is to use the information on the Minimatch object determine
    # the findPath. Minimatch breaks the pattern into path segments, and exposes information about which
    # segments are literal vs patterns.
    #
    # Note, the technique currently imposes a limitation for drive-relative paths with a glob in the
    # first segment, e.g. C:hello*/world. It's feasible to overcome this limitation, but is left unsolved
    # for now.
    $minimatchObj = New-Object Minimatch.Minimatcher($Pattern, (ConvertTo-MinimatchOptions -Options $MatchOptions))

    # The "set" field is a two-dimensional enumerable of parsed path segment info. The outer enumerable should only
    # contain one item, otherwise something went wrong. Brace expansion can result in multiple items in the outer
    # enumerable, but that should be turned off by the time this function is reached.
    #
    # Note, "set" is a private field in the .NET implementation but is documented as a feature in the nodejs
    # implementation. The .NET implementation is a port and is by a different author.
    $setFieldInfo = $minimatchObj.GetType().GetField('set', 'Instance,NonPublic')
    [object[]]$set = $setFieldInfo.GetValue($minimatchObj)
    if ($set.Count -ne 1) {
        throw "Get-FindInfoFromPattern expected Minimatch.Minimatcher(...).set.Count to be 1. Actual: '$($set.Count)'"
    }

    [string[]]$literalSegments = @( )
    [object[]]$parsedSegments = $set[0]
    foreach ($parsedSegment in $parsedSegments) {
        if ($parsedSegment.GetType().Name -eq 'LiteralItem') {
            # The item is a LiteralItem when the original input for the path segment does not contain any
            # unescaped glob characters.
            $literalSegments += $parsedSegment.Source;
            continue
        }

        break;
    }

    # Join the literal segments back together. Minimatch converts '\' to '/' on Windows, then squashes
    # consequetive slashes, and finally splits on slash. This means that UNC format is lost, but can
    # be detected from the original pattern.
    $joinedSegments = [string]::Join('/', $literalSegments)
    if ($joinedSegments -and ($Pattern -replace '\\', '/').StartsWith('//')) {
        $joinedSegments = '/' + $joinedSegments # restore UNC format
    }

    # Determine the find path.
    $findPath = ''
    if ((Test-Rooted -Path $Pattern)) { # The pattern is rooted.
        $findPath = $joinedSegments
    } elseif ($joinedSegments) { # The pattern is not rooted, and literal segements were found.
        $findPath = [System.IO.Path]::Combine($DefaultRoot, $joinedSegments)
    } else { # The pattern is not rooted, and no literal segements were found.
        $findPath = $DefaultRoot
    }

    # Clean up the path.
    if ($findPath) {
        $findPath = [System.IO.Path]::GetDirectoryName(([System.IO.Path]::Combine($findPath, '_'))) # Hack to remove unnecessary trailing slash.
        $findPath = ConvertTo-NormalizedSeparators -Path $findPath
    }

    return New-Object psobject -Property @{
        AdjustedPattern = Get-RootedPattern -DefaultRoot $DefaultRoot -Pattern $Pattern
        FindPath = $findPath
        StatOnly = $literalSegments.Count -eq $parsedSegments.Count
    }
}

function Get-FindResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Options)

    if (!(Test-Path -LiteralPath $Path)) {
        Write-Verbose 'Path not found.'
        return
    }

    $Path = ConvertTo-NormalizedSeparators -Path $Path

    # Push the first item.
    [System.Collections.Stack]$stack = New-Object System.Collections.Stack
    $stack.Push((Get-Item -LiteralPath $Path))

    $count = 0
    while ($stack.Count) {
        # Pop the next item and yield the result.
        $item = $stack.Pop()
        $count++
        $item.FullName

        # Traverse.
        if (($item.Attributes -band 0x00000010) -eq 0x00000010) { # Directory
            if (($item.Attributes -band 0x00000400) -ne 0x00000400 -or # ReparsePoint
                $Options.FollowSymbolicLinks -or
                ($count -eq 1 -and $Options.FollowSpecifiedSymbolicLink)) {

                $childItems = @( Get-DirectoryChildItem -Path $Item.FullName -Force )
                [System.Array]::Reverse($childItems)
                foreach ($childItem in $childItems) {
                    $stack.Push($childItem)
                }
            }
        }
    }
}

function Get-RootedPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DefaultRoot,
        [Parameter(Mandatory = $true)]
        [string]$Pattern)

    if ((Test-Rooted -Path $Pattern)) {
        return $Pattern
    }

    # Normalize root.
    $DefaultRoot = ConvertTo-NormalizedSeparators -Path $DefaultRoot

    # Escape special glob characters.
    $DefaultRoot = $DefaultRoot -replace '(\[)(?=[^\/]+\])', '[[]' # Escape '[' when ']' follows within the path segment
    $DefaultRoot = $DefaultRoot.Replace('?', '[?]')     # Escape '?'
    $DefaultRoot = $DefaultRoot.Replace('*', '[*]')     # Escape '*'
    $DefaultRoot = $DefaultRoot -replace '\+\(', '[+](' # Escape '+('
    $DefaultRoot = $DefaultRoot -replace '@\(', '[@]('  # Escape '@('
    $DefaultRoot = $DefaultRoot -replace '!\(', '[!]('  # Escape '!('

    if ($DefaultRoot -like '[A-Z]:') { # e.g. C:
        return "$DefaultRoot$Pattern"
    }

    # Ensure root ends with a separator.
    if (!$DefaultRoot.EndsWith('\')) {
        $DefaultRoot = "$DefaultRoot\"
    }

    return "$DefaultRoot$Pattern"
}

function Test-Rooted {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path)

    $Path = ConvertTo-NormalizedSeparators -Path $Path
    return $Path.StartsWith('\') -or # e.g. \ or \hello or \\hello
        $Path -like '[A-Z]:*'        # e.g. C: or C:\hello
}

function Trace-MatchOptions {
    [CmdletBinding()]
    param($Options)

    Write-Verbose "MatchOptions.Dot: '$($Options.Dot)'"
    Write-Verbose "MatchOptions.FlipNegate: '$($Options.FlipNegate)'"
    Write-Verbose "MatchOptions.MatchBase: '$($Options.MatchBase)'"
    Write-Verbose "MatchOptions.NoBrace: '$($Options.NoBrace)'"
    Write-Verbose "MatchOptions.NoCase: '$($Options.NoCase)'"
    Write-Verbose "MatchOptions.NoComment: '$($Options.NoComment)'"
    Write-Verbose "MatchOptions.NoExt: '$($Options.NoExt)'"
    Write-Verbose "MatchOptions.NoGlobStar: '$($Options.NoGlobStar)'"
    Write-Verbose "MatchOptions.NoNegate: '$($Options.NoNegate)'"
    Write-Verbose "MatchOptions.NoNull: '$($Options.NoNull)'"
}

function Trace-FindOptions {
    [CmdletBinding()]
    param($Options)

    Write-Verbose "FindOptions.FollowSpecifiedSymbolicLink: '$($FindOptions.FollowSpecifiedSymbolicLink)'"
    Write-Verbose "FindOptions.FollowSymbolicLinks: '$($FindOptions.FollowSymbolicLinks)'"
}

# SIG # Begin signature block
# MIIoGwYJKoZIhvcNAQcCoIIoDDCCKAgCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCDIRFb/1JF2TcDl
# 1y9vI7RyqKZwe1TaVI4tyUqT2jGTLKCCDYUwggYDMIID66ADAgECAhMzAAAEA73V
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
# LwYJKoZIhvcNAQkEMSIEIJu76bxptLbv5SqXKlOhGYvpZyGVu8E5cubub+yQRML0
# MEIGCisGAQQBgjcCAQwxNDAyoBSAEgBNAGkAYwByAG8AcwBvAGYAdKEagBhodHRw
# Oi8vd3d3Lm1pY3Jvc29mdC5jb20wDQYJKoZIhvcNAQEBBQAEggEAL9ghPRU/rRqH
# 7Oj6mKVyBFsMBIX1MTH553PI+GAKJ8Y592mrEXMmu+esT2DhSyOgjqLB0O02gyS9
# wIBNUFZ3nTSX9DUPb59WkKIZSGCyloWcb5+/OinHBv4HaBp9jYohi6fFEk9KNc9/
# 7SaHoysSQXR+NdLkzrdOQ2X8P9RyQ2ISgQU7/0m/HMWNOksacnJyp2Y+/IlbSmba
# hHBXAhmCUA/YTll6me0/OIZAmKcWVzlhn2X2mOHy4mrVNjrJSJBcRcOFQG48lnOz
# 8cUSeMstY+fL7lehFgRDNU9P/4rMKgcMwgJ/wnaFTw+YkVqy6y333M4Mrr6F8M+7
# R03k05rHxaGCF5QwgheQBgorBgEEAYI3AwMBMYIXgDCCF3wGCSqGSIb3DQEHAqCC
# F20wghdpAgEDMQ8wDQYJYIZIAWUDBAIBBQAwggFSBgsqhkiG9w0BCRABBKCCAUEE
# ggE9MIIBOQIBAQYKKwYBBAGEWQoDATAxMA0GCWCGSAFlAwQCAQUABCAq6SI08ZIB
# 13J3d8SaeINxVriv6up5iFLy3rqhz0Ob/AIGZ/gogeNgGBMyMDI1MDQxODAwMTkx
# MC4xNjlaMASAAgH0oIHRpIHOMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2Fz
# aGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENv
# cnBvcmF0aW9uMSUwIwYDVQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25z
# MScwJQYDVQQLEx5uU2hpZWxkIFRTUyBFU046OTYwMC0wNUUwLUQ5NDcxJTAjBgNV
# BAMTHE1pY3Jvc29mdCBUaW1lLVN0YW1wIFNlcnZpY2WgghHqMIIHIDCCBQigAwIB
# AgITMwAAAgTY4A4HlzJYmAABAAACBDANBgkqhkiG9w0BAQsFADB8MQswCQYDVQQG
# EwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwG
# A1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQg
# VGltZS1TdGFtcCBQQ0EgMjAxMDAeFw0yNTAxMzAxOTQyNDdaFw0yNjA0MjIxOTQy
# NDdaMIHLMQswCQYDVQQGEwJVUzETMBEGA1UECBMKV2FzaGluZ3RvbjEQMA4GA1UE
# BxMHUmVkbW9uZDEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSUwIwYD
# VQQLExxNaWNyb3NvZnQgQW1lcmljYSBPcGVyYXRpb25zMScwJQYDVQQLEx5uU2hp
# ZWxkIFRTUyBFU046OTYwMC0wNUUwLUQ5NDcxJTAjBgNVBAMTHE1pY3Jvc29mdCBU
# aW1lLVN0YW1wIFNlcnZpY2UwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoIC
# AQDw3Sbcee2d66vkWGTIXhfGqqgQGxQXTnq44XlUvNzFSt7ELtO4B939jwZFX7Dr
# Rt/4fpzGNkFdGpc7EL5S86qKYv360eXjW+fIv1lAqDD31d/p8Ai9/AZz8M95zo0r
# DpK2csz9WAyR9FtUDx52VOs9qP3/pgpHvgUvD8s6/3KNITzms8QC1tJ3TMw1cRn9
# CZgVIYzw2iD/ZvOW0sbF/DRdgM8UdtxjFIKTXTaI/bJhsQge3TwayKQ2j85RafFF
# VCR5/ChapkrBQWGwNFaPzpmYN46mPiOvUxriISC9nQ/GrDXUJWzLDmchrmr2baAB
# Jevvw31UYlTlLZY6zUmjkgaRfpozd+Glq9TY2E3Dglr6PtTEKgPu2hM6v8NiU5nT
# vxhDnxdmcf8UN7goeVlELXbOm7j8yw1xM9IyyQuUMWkorBaN/5r9g4lvYkMohRXE
# YB0tMaOPt0FmZmQMLBFpNRVnXBTa4haXvn1adKrvTz8VlfnHxkH6riA/h2AlqYWh
# v0YULsEcHnaDWgqA29ry+jH097MpJ/FHGHxk+d9kH2L5aJPpAYuNmMNPB7FDTPWA
# x7Apjr/J5MhUx0i07gV2brAZ9J9RHi+fMPbS+Qm4AonC5iOTj+dKCttVRs+jKKuO
# 63CLwqlljvnUCmuSavOX54IXOtKcFZkfDdOZ7cE4DioP1QIDAQABo4IBSTCCAUUw
# HQYDVR0OBBYEFBp1dktAcGpW/Km6qm+vu4M1GaJfMB8GA1UdIwQYMBaAFJ+nFV0A
# XmJdg/Tl0mWnG1M1GelyMF8GA1UdHwRYMFYwVKBSoFCGTmh0dHA6Ly93d3cubWlj
# cm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29mdCUyMFRpbWUtU3RhbXAlMjBQ
# Q0ElMjAyMDEwKDEpLmNybDBsBggrBgEFBQcBAQRgMF4wXAYIKwYBBQUHMAKGUGh0
# dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIw
# VGltZS1TdGFtcCUyMFBDQSUyMDIwMTAoMSkuY3J0MAwGA1UdEwEB/wQCMAAwFgYD
# VR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeAMA0GCSqGSIb3DQEB
# CwUAA4ICAQBecv6sRw2HTLMyUC1WJJ+FR+DgA9Jkv0lGsIt4y69CmOj8R63oFbhS
# mcdpakxqNbr8v9dyTb4RDyNqtohiiXbtrXmQK5X7y/Q++F0zMotTtTpTPvG3elty
# V/LvO15mrLoNQ7W4VH58aLt030tORxs8VnAQQF5BmQQMOua+EQgH4f1F4uF6rl3E
# C17JBSJ0wjHSea/n0WYiHPR0qkz/NRAf8lSUUV0gbIMawGIjn7+RKyCr+8l1xdNk
# K/F0UYuX3hG0nE+9Wc0L4A/enluUN7Pa9vOV6Vi3BOJST0RY/ax7iZ45leM8kqCw
# 7BFPcTIkWzxpjr2nCtirnkw7OBQ6FNgwIuAvYNTU7r60W421YFOL5pTsMZcNDOOs
# A01xv7ymCF6zknMGpRHuw0Rb2BAJC9quU7CXWbMbAJLdZ6XINKariSmCX3/MLdzc
# W5XOycK0QhoRNRf4WqXRshEBaY2ymJvHO48oSSY/kpuYvBS3ljAAuLN7Rp8jWS7t
# 916paGeE7prmrP9FJsoy1LFKmFnW+vg43ANhByuAEXq9Cay5o7K2H5NFnR5wj/SL
# RKwK1iyUX926i1TEviEiAh/PVyJbAD4koipig28p/6HDuiYOZ0wUkm/a5W8orIjo
# OdU3XsJ4i08CfNp5I73CsvB5QPYMcLpF9NO/1LvoQAw3UPdL55M5HTCCB3EwggVZ
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
# ZCBUU1MgRVNOOjk2MDAtMDVFMC1EOTQ3MSUwIwYDVQQDExxNaWNyb3NvZnQgVGlt
# ZS1TdGFtcCBTZXJ2aWNloiMKAQEwBwYFKw4DAhoDFQC6PYHRw9+9SH+1pwy6qzVG
# 3k9lbqCBgzCBgKR+MHwxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9u
# MRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRp
# b24xJjAkBgNVBAMTHU1pY3Jvc29mdCBUaW1lLVN0YW1wIFBDQSAyMDEwMA0GCSqG
# SIb3DQEBCwUAAgUA66vg5DAiGA8yMDI1MDQxNzIwMTk0OFoYDzIwMjUwNDE4MjAx
# OTQ4WjB0MDoGCisGAQQBhFkKBAExLDAqMAoCBQDrq+DkAgEAMAcCAQACAiF5MAcC
# AQACAhQWMAoCBQDrrTJkAgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkK
# AwKgCjAIAgEAAgMHoSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAHlv
# GE0hxYGy+hmr/Qq61ZDukaEy3SuvSQyRcWm0IfgTNxfDoleU24/n7jnV62DWpeQN
# IYvScYj8N3RNkuyKn3ibegEawhoE+HG1X3b/jUiB9z3VJAQjAX5GlqhivRRwIYAU
# UXP5aXGS9DcYLIN6C/cVKCRvyoSHwYOd9D2uTmVm/uqZ8YmzU6SBHkv+Sq+Flqcy
# Sb90qSyLspHAmnwj7SM4ulLxztDdYvkt5YveNZ6bqOK4z1SmaJaylTFMp8NMcqfX
# 8oRNGnY/Qv7a/JwzGe/8kCTtn2R786IGnYfZ3yU560dG3xGvXNgv2c8Xkt5wopSO
# uFBX4gVpeWJaxyAaCpcxggQNMIIECQIBATCBkzB8MQswCQYDVQQGEwJVUzETMBEG
# A1UECBMKV2FzaGluZ3RvbjEQMA4GA1UEBxMHUmVkbW9uZDEeMBwGA1UEChMVTWlj
# cm9zb2Z0IENvcnBvcmF0aW9uMSYwJAYDVQQDEx1NaWNyb3NvZnQgVGltZS1TdGFt
# cCBQQ0EgMjAxMAITMwAAAgTY4A4HlzJYmAABAAACBDANBglghkgBZQMEAgEFAKCC
# AUowGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEEMC8GCSqGSIb3DQEJBDEiBCBm
# APW9Ty9eiMYL3AYUSatzxELAiFLijJyR040dmbbAbjCB+gYLKoZIhvcNAQkQAi8x
# geowgecwgeQwgb0EIPnteGX9Wwq8VdJM6mjfx1GEJsu7/6kU6l0SS5rcebn+MIGY
# MIGApH4wfDELMAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNV
# BAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEmMCQG
# A1UEAxMdTWljcm9zb2Z0IFRpbWUtU3RhbXAgUENBIDIwMTACEzMAAAIE2OAOB5cy
# WJgAAQAAAgQwIgQgCP437pWmzS5DpWmj+0TKWGDSlL09wZ4AOK9J3IjKY10wDQYJ
# KoZIhvcNAQELBQAEggIAGH6npHcbQD1XCQhLOdPsAGCBKuGMJ4KMUmqSPrZmyX0I
# vRRf/fJUlJIzqpbjKZTKSIPwmFlNzpMfirAJAl7JWVWvDSKaf5G2NzOW0LP6mzQ/
# uNSpRxRIQ7oiX9ru3S0DUWeYl7oEl+/ySSNcUFh5AXVN1LSbQIcx83Dmu3vDJ3X9
# YrLZPB00h19/DdWp0aH9qytayCznbnUd0mXFxHfsb1hqDBjuMLH4RTqJnd/gnQGY
# dNeT+Exw8yK86sB2Wz9BXps9N0uoQKS3xbUS7v1mH5vdK0eqAIHseJxr6HOLWa46
# 7RIKknECdY3AYt1IYdOZ6F4AbAO4tjAIyPRa8HhNXyLi5MwlrV9AXUlFhSZKPPj1
# RER7K+0nS7UE7jd7kukl23Q3G1WPetqJ3kPhTxAnn1C9JJ6Bf0LDp+5UQgfb3P3u
# RYPYeugonDKi6HBix4RMD+DhXYODAM76FgXDMrVih3YxftIXqMU+/RfAdkFw4tii
# QsNxPVUwyfztE85xItLTwtAG7hIUTBk2cbzioQttmqadWqdHuQBPriTj+4ttppOP
# BqxUz4K8B4wfU7KD6iRMNNB1WxA0fY31eeW3o7GTJqKxzjAxl3Dic/FadCpnGHGG
# 7YHz3oDutpewArqyOp6IIN+mnI+RMXMNHM0Qn5MCw0Mi7aKC8hR8/lmjHHcs5NY=
# SIG # End signature block
