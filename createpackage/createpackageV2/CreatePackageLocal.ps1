<#
.SYNOPSIS
    Local wrapper script to run CreatePackage without Azure DevOps dependencies
    
.DESCRIPTION
    This script allows running the CreatePackage script locally without requiring Azure DevOps pipeline context.
    It bypasses the VstsTaskSdk dependencies and provides parameter input directly.
    
.PARAMETER XppToolsPath
    Path to the X++ Tools directory containing CreatePackage.psm1 and related DLLs
    
.PARAMETER XppBinariesPath
    Path to the X++ binaries to package
    
.PARAMETER XppBinariesSearch
    Search pattern for binaries to package (default: *)
    
.PARAMETER DeployablePackagePath
    Output path for the deployable package
    
.PARAMETER CreateRegularPackage
    Create a regular LCS Software Deployable Package (default: true)
    
.PARAMETER CreateCloudPackage
    Create a Power Platform Unified Package (default: false)
    
.PARAMETER CloudPackagePlatVersion
    Platform version for cloud package (default: 7.0.0.0)
    
.PARAMETER CloudPackageAppVersion
    Application version for cloud package (default: 10.0.0.0)
    
.PARAMETER CloudPackageOutputLocation
    Output location for cloud package
    
.EXAMPLE
    .\CreatePackageLocal.ps1 -XppToolsPath "C:\Tools\XppTools" -XppBinariesPath "C:\Build\Bin" -DeployablePackagePath "C:\Output\Package.zip"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$XppToolsPath,
    
    [Parameter(Mandatory=$true)]
    [string]$XppBinariesPath,
    
    [Parameter(Mandatory=$false)]
    [string]$XppBinariesSearch = "*",
    
    [Parameter(Mandatory=$true)]
    [string]$DeployablePackagePath,
    
    [Parameter(Mandatory=$false)]
    [string]$CreateRegularPackage = "true",
    
    [Parameter(Mandatory=$false)]
    [string]$CreateCloudPackage = "false",
    
    [Parameter(Mandatory=$false)]
    [string]$CloudPackagePlatVersion = "7.0.0.0",
    
    [Parameter(Mandatory=$false)]
    [string]$CloudPackageAppVersion = "10.0.0.0",
    
    [Parameter(Mandatory=$false)]
    [string]$CloudPackageOutputLocation = ""
)

$ErrorActionPreference = "Stop"

# Mock VstsTaskSdk functions for local execution
function Get-VstsInput {
    param(
        [string]$Name,
        [switch]$Require,
        [string]$Default
    )
    
    $value = $null
    switch ($Name) {
        "XppToolsPath" { $value = $XppToolsPath }
        "XppBinariesPath" { $value = $XppBinariesPath }
        "XppBinariesSearch" { $value = $XppBinariesSearch }
        "DeployablePackagePath" { $value = $DeployablePackagePath }
        "CreateRegularPackage" { $value = $CreateRegularPackage }
        "CreateCloudPackage" { $value = $CreateCloudPackage }
        "CloudPackagePlatVersion" { $value = $CloudPackagePlatVersion }
        "CloudPackageAppVersion" { $value = $CloudPackageAppVersion }
        "CloudPackageOutputLocation" { $value = $CloudPackageOutputLocation }
    }
    
    if ([string]::IsNullOrEmpty($value) -and $Default) {
        $value = $Default
    }
    
    if ($Require -and [string]::IsNullOrEmpty($value)) {
        throw "Required parameter '$Name' was not provided"
    }
    
    return $value
}

function Assert-VstsPath {
    param(
        [string]$LiteralPath,
        [string]$PathType
    )
    
    if ($PathType -eq "Container") {
        if (-not (Test-Path -LiteralPath $LiteralPath -PathType Container)) {
            throw "Directory not found: $LiteralPath"
        }
    } else {
        if (-not (Test-Path -LiteralPath $LiteralPath)) {
            throw "Path not found: $LiteralPath"
        }
    }
}

function Find-VstsMatch {
    param(
        [string]$DefaultRoot,
        [string[]]$Pattern
    )
    
    $results = @()
    foreach ($p in $Pattern) {
        $searchPath = Join-Path -Path $DefaultRoot -ChildPath $p
        $found = Get-ChildItem -Path $searchPath -ErrorAction SilentlyContinue
        if ($found) {
            $results += $found | ForEach-Object { $_.FullName }
        }
    }
    return $results
}

function Trace-VstsEnteringInvocation {
    param($Invocation)
    Write-Host "Entering: $($Invocation.MyCommand)"
}

function Trace-VstsLeavingInvocation {
    param($Invocation)
    Write-Host "Leaving: $($Invocation.MyCommand)"
}

# Set up environment
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Local X++ Package Creation Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  XppToolsPath: $XppToolsPath"
Write-Host "  XppBinariesPath: $XppBinariesPath"
Write-Host "  XppBinariesSearch: $XppBinariesSearch"
Write-Host "  DeployablePackagePath: $DeployablePackagePath"
Write-Host "  CreateRegularPackage: $CreateRegularPackage"
Write-Host "  CreateCloudPackage: $CreateCloudPackage"
Write-Host ""

# Execute the main CreatePackage script with mocked functions in scope
try {
    # Dot source the main script to execute it with our mock functions available
    . "$PSScriptRoot\CreatePackage.ps1"
}
catch {
    Write-Error "Error executing CreatePackage.ps1: $_"
    Write-Error $_.Exception.Message
    Write-Error $_.ScriptStackTrace
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Package creation completed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
