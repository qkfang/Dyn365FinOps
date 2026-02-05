<#
.SYNOPSIS
    Quick start example for local X++ package creation
    
.DESCRIPTION
    This script demonstrates a complete end-to-end example of:
    1. Setting up the local environment
    2. Creating a dummy X++ project
    3. Building a deployable package
    
    Use this as a reference or starting point for your own scripts.
    
.EXAMPLE
    .\QuickStart-Example.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  D365 F&O Local Package Creation - Quick Start Example  " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This script will:" -ForegroundColor Yellow
Write-Host "  1. Setup a local tools directory" -ForegroundColor White
Write-Host "  2. Create a dummy X++ project" -ForegroundColor White
Write-Host "  3. Attempt to create a deployable package" -ForegroundColor White
Write-Host ""

# Configuration - modify these paths as needed
$baseDir = $PSScriptRoot
$toolsDir = Join-Path -Path $baseDir -ChildPath "LocalTools"
$buildDir = Join-Path -Path $baseDir -ChildPath "Build"
$outputDir = Join-Path -Path $baseDir -ChildPath "Output"
$xppToolsPath = Join-Path -Path $toolsDir -ChildPath "XppTools"

Write-Host "Configuration:" -ForegroundColor Yellow
Write-Host "  Base Directory: $baseDir" -ForegroundColor Gray
Write-Host "  Tools Directory: $toolsDir" -ForegroundColor Gray
Write-Host "  Build Directory: $buildDir" -ForegroundColor Gray
Write-Host "  Output Directory: $outputDir" -ForegroundColor Gray
Write-Host ""

# Create directories
foreach ($dir in @($toolsDir, $buildDir, $outputDir)) {
    if (-not (Test-Path -Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

# Step 1: Setup local environment
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "STEP 1: Setting up local environment" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$setupScript = Join-Path -Path $PSScriptRoot -ChildPath "Setup-LocalEnvironment.ps1"
if (Test-Path -Path $setupScript) {
    Write-Host "Running Setup-LocalEnvironment.ps1..." -ForegroundColor Yellow
    & $setupScript -ToolsDirectory $toolsDir
} else {
    Write-Error "Setup-LocalEnvironment.ps1 not found!"
    exit 1
}

Write-Host ""
Write-Host "Checking if XppTools are ready..." -ForegroundColor Yellow

# Check for critical files
$createPackageModule = Join-Path -Path $xppToolsPath -ChildPath "CreatePackage.psm1"
$hasTools = Test-Path -Path $createPackageModule

if (-not $hasTools) {
    Write-Host ""
    Write-Warning "XppTools not fully configured. Manual setup required."
    Write-Host ""
    Write-Host "To continue, you need to:" -ForegroundColor Yellow
    Write-Host "  1. Copy files from a D365 VM (K:\AosService\PackagesLocalDirectory\Bin)" -ForegroundColor White
    Write-Host "     to: $xppToolsPath" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  OR" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  2. Install Azure Artifacts Credential Provider and re-run Setup-LocalEnvironment.ps1" -ForegroundColor White
    Write-Host ""
    Write-Host "After completing the setup, run this script again." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 0
}

# Step 2: Create dummy X++ project
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "STEP 2: Creating dummy X++ project" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$dummyProjectScript = Join-Path -Path $PSScriptRoot -ChildPath "Create-DummyXppProject.ps1"
if (Test-Path -Path $dummyProjectScript) {
    Write-Host "Running Create-DummyXppProject.ps1..." -ForegroundColor Yellow
    & $dummyProjectScript -OutputPath $buildDir -PackageName "TestPackage" -Version "1.0.0.0"
} else {
    Write-Error "Create-DummyXppProject.ps1 not found!"
    exit 1
}

# Step 3: Create deployable package
Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "STEP 3: Creating deployable package" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$packagePath = Join-Path -Path $outputDir -ChildPath "TestPackage_$(Get-Date -Format 'yyyyMMdd_HHmmss').zip"

$createPackageScript = Join-Path -Path $PSScriptRoot -ChildPath "CreatePackageLocal.ps1"
if (Test-Path -Path $createPackageScript) {
    Write-Host "Running CreatePackageLocal.ps1..." -ForegroundColor Yellow
    Write-Host ""
    
    try {
        & $createPackageScript `
            -XppToolsPath $xppToolsPath `
            -XppBinariesPath $buildDir `
            -XppBinariesSearch "TestPackage" `
            -DeployablePackagePath $packagePath `
            -CreateRegularPackage "true" `
            -CreateCloudPackage "false"
        
        Write-Host ""
        Write-Host "==========================================================" -ForegroundColor Green
        Write-Host "SUCCESS! Package created successfully" -ForegroundColor Green
        Write-Host "==========================================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Package Location: $packagePath" -ForegroundColor Cyan
        
        if (Test-Path -Path $packagePath) {
            $fileSize = (Get-Item $packagePath).Length / 1MB
            Write-Host "Package Size: $([math]::Round($fileSize, 2)) MB" -ForegroundColor Cyan
        }
        
        Write-Host ""
        Write-Host "You can now:" -ForegroundColor Yellow
        Write-Host "  - Deploy this package to your D365 environment" -ForegroundColor White
        Write-Host "  - Use it with Lifecycle Services (LCS)" -ForegroundColor White
        Write-Host "  - Test it in your deployment pipeline" -ForegroundColor White
    }
    catch {
        Write-Host ""
        Write-Host "==========================================================" -ForegroundColor Red
        Write-Host "ERROR: Package creation failed" -ForegroundColor Red
        Write-Host "==========================================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "Error details:" -ForegroundColor Yellow
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host ""
        Write-Host "Stack trace:" -ForegroundColor Yellow
        Write-Host $_.ScriptStackTrace -ForegroundColor Gray
        Write-Host ""
        Write-Host "Please check:" -ForegroundColor Yellow
        Write-Host "  1. XppTools directory is properly configured" -ForegroundColor White
        Write-Host "  2. All required DLLs are present" -ForegroundColor White
        Write-Host "  3. .NET Framework 4.7.2+ is installed" -ForegroundColor White
        Write-Host ""
        Write-Host "See README_LOCAL_EXECUTION.md for troubleshooting." -ForegroundColor Cyan
        Write-Host ""
        exit 1
    }
} else {
    Write-Error "CreatePackageLocal.ps1 not found!"
    exit 1
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "Quick Start Example Completed" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""
