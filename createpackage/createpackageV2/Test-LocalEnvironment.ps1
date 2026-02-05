<#
.SYNOPSIS
    Validates that the local environment is properly configured for package creation
    
.DESCRIPTION
    This script checks all prerequisites and dependencies needed to run
    CreatePackageLocal.ps1 successfully. It provides diagnostic information
    and recommendations for fixing any issues found.
    
.PARAMETER XppToolsPath
    Path to the X++ Tools directory to validate
    
.EXAMPLE
    .\Test-LocalEnvironment.ps1 -XppToolsPath "C:\D365Tools\XppTools"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$XppToolsPath = ""
)

$ErrorActionPreference = "Continue"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  D365 F&O Local Environment Validation" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

$allChecksPassed = $true

# Check 1: PowerShell Version
Write-Host "[1] Checking PowerShell Version..." -ForegroundColor Yellow
$psVersion = $PSVersionTable.PSVersion
Write-Host "    Version: $($psVersion.Major).$($psVersion.Minor).$($psVersion.Build)" -ForegroundColor Gray

if ($psVersion.Major -ge 5) {
    Write-Host "    [OK] PowerShell version is sufficient" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] PowerShell 5.1 or later is required" -ForegroundColor Red
    $allChecksPassed = $false
}
Write-Host ""

# Check 2: .NET Framework
Write-Host "[2] Checking .NET Framework..." -ForegroundColor Yellow
try {
    $dotNetVersion = (Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full' -ErrorAction SilentlyContinue).Release
    if ($dotNetVersion) {
        if ($dotNetVersion -ge 461808) { # .NET 4.7.2
            Write-Host "    [OK] .NET Framework 4.7.2 or later is installed" -ForegroundColor Green
        } else {
            Write-Host "    [WARN] .NET Framework 4.7.2 or later recommended" -ForegroundColor Yellow
            Write-Host "    Current version code: $dotNetVersion" -ForegroundColor Gray
        }
    } else {
        Write-Host "    [WARN] Could not detect .NET Framework version" -ForegroundColor Yellow
    }
} catch {
    Write-Host "    [WARN] Could not check .NET Framework version" -ForegroundColor Yellow
}
Write-Host ""

# Check 3: Operating System
Write-Host "[3] Checking Operating System..." -ForegroundColor Yellow
$os = Get-CimInstance -ClassName Win32_OperatingSystem
Write-Host "    OS: $($os.Caption)" -ForegroundColor Gray
Write-Host "    Version: $($os.Version)" -ForegroundColor Gray

if ($os.Caption -like "*Windows*") {
    Write-Host "    [OK] Running on Windows" -ForegroundColor Green
} else {
    Write-Host "    [FAIL] Windows OS is required for X++ tools" -ForegroundColor Red
    $allChecksPassed = $false
}
Write-Host ""

# Check 4: Script Files
Write-Host "[4] Checking Required Scripts..." -ForegroundColor Yellow
$scriptPath = $PSScriptRoot
$requiredScripts = @(
    "CreatePackageLocal.ps1",
    "Setup-LocalEnvironment.ps1",
    "Create-DummyXppProject.ps1",
    "CreatePackage.ps1",
    "CloudRuntimePackageCreation.ps1"
)

foreach ($script in $requiredScripts) {
    $scriptFile = Join-Path -Path $scriptPath -ChildPath $script
    if (Test-Path -Path $scriptFile) {
        Write-Host "    [OK] $script" -ForegroundColor Green
    } else {
        Write-Host "    [FAIL] $script not found" -ForegroundColor Red
        $allChecksPassed = $false
    }
}
Write-Host ""

# Check 5: XppTools Directory (if provided)
if (-not [string]::IsNullOrEmpty($XppToolsPath)) {
    Write-Host "[5] Checking XppTools Directory..." -ForegroundColor Yellow
    Write-Host "    Path: $XppToolsPath" -ForegroundColor Gray
    
    if (Test-Path -Path $XppToolsPath) {
        Write-Host "    [OK] Directory exists" -ForegroundColor Green
        
        # Check for critical files
        $criticalFiles = @(
            "CreatePackage.psm1",
            "Microsoft.Dynamics.AXCreateDeployablePackageBase.dll",
            "BaseMetadataDeployablePackage.zip"
        )
        
        Write-Host ""
        Write-Host "    Checking critical files:" -ForegroundColor Gray
        $missingFiles = @()
        
        foreach ($file in $criticalFiles) {
            $filePath = Join-Path -Path $XppToolsPath -ChildPath $file
            if (Test-Path -Path $filePath) {
                Write-Host "      [OK] $file" -ForegroundColor Green
            } else {
                Write-Host "      [MISSING] $file" -ForegroundColor Red
                $missingFiles += $file
                $allChecksPassed = $false
            }
        }
        
        if ($missingFiles.Count -gt 0) {
            Write-Host ""
            Write-Host "    Missing files must be copied from D365 VM:" -ForegroundColor Yellow
            Write-Host "      Source: K:\AosService\PackagesLocalDirectory\Bin" -ForegroundColor Cyan
            Write-Host "      Target: $XppToolsPath" -ForegroundColor Cyan
        }
    } else {
        Write-Host "    [FAIL] Directory does not exist" -ForegroundColor Red
        Write-Host "    Run Setup-LocalEnvironment.ps1 to create it" -ForegroundColor Yellow
        $allChecksPassed = $false
    }
    Write-Host ""
} else {
    Write-Host "[5] XppTools Directory Check Skipped" -ForegroundColor Gray
    Write-Host "    (Provide -XppToolsPath to validate tools directory)" -ForegroundColor Gray
    Write-Host ""
}

# Check 6: CloudRuntimeDlls
Write-Host "[6] Checking CloudRuntimeDlls..." -ForegroundColor Yellow
$dllsPath = Join-Path -Path $scriptPath -ChildPath "CloudRuntimeDlls"
if (Test-Path -Path $dllsPath) {
    $dllCount = (Get-ChildItem -Path $dllsPath -Filter "*.dll" -ErrorAction SilentlyContinue).Count
    Write-Host "    [OK] CloudRuntimeDlls directory exists" -ForegroundColor Green
    Write-Host "    Found $dllCount DLL files" -ForegroundColor Gray
} else {
    Write-Host "    [FAIL] CloudRuntimeDlls directory not found" -ForegroundColor Red
    $allChecksPassed = $false
}
Write-Host ""

# Check 7: VstsTaskSdk Module
Write-Host "[7] Checking VstsTaskSdk Module..." -ForegroundColor Yellow
$vstsTaskSdkPath = Join-Path -Path $scriptPath -ChildPath "ps_modules\VstsTaskSdk"
if (Test-Path -Path $vstsTaskSdkPath) {
    Write-Host "    [OK] VstsTaskSdk module found" -ForegroundColor Green
    
    $psmFile = Join-Path -Path $vstsTaskSdkPath -ChildPath "VstsTaskSdk.psm1"
    if (Test-Path -Path $psmFile) {
        Write-Host "    [OK] VstsTaskSdk.psm1 exists" -ForegroundColor Green
    } else {
        Write-Host "    [WARN] VstsTaskSdk.psm1 not found" -ForegroundColor Yellow
    }
} else {
    Write-Host "    [FAIL] VstsTaskSdk module not found" -ForegroundColor Red
    $allChecksPassed = $false
}
Write-Host ""

# Check 8: Execution Policy
Write-Host "[8] Checking PowerShell Execution Policy..." -ForegroundColor Yellow
$executionPolicy = Get-ExecutionPolicy
Write-Host "    Current policy: $executionPolicy" -ForegroundColor Gray

if ($executionPolicy -eq "Restricted") {
    Write-Host "    [WARN] Execution policy is Restricted" -ForegroundColor Yellow
    Write-Host "    You may need to run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser" -ForegroundColor Yellow
} else {
    Write-Host "    [OK] Execution policy allows script execution" -ForegroundColor Green
}
Write-Host ""

# Summary
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Validation Summary" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

if ($allChecksPassed) {
    Write-Host "[SUCCESS] All critical checks passed!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your environment is ready for local package creation." -ForegroundColor Green
    Write-Host ""
    if ([string]::IsNullOrEmpty($XppToolsPath)) {
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "  1. Run Setup-LocalEnvironment.ps1 to configure XppTools" -ForegroundColor White
        Write-Host "  2. Run this script again with -XppToolsPath to validate tools" -ForegroundColor White
        Write-Host "  3. Run QuickStart-Example.ps1 to test package creation" -ForegroundColor White
    } else {
        Write-Host "Next steps:" -ForegroundColor Yellow
        Write-Host "  1. Run QuickStart-Example.ps1 to test package creation" -ForegroundColor White
        Write-Host "  2. Or use CreatePackageLocal.ps1 with your own X++ binaries" -ForegroundColor White
    }
} else {
    Write-Host "[FAILED] Some checks did not pass" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please address the issues above before proceeding." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Common solutions:" -ForegroundColor Yellow
    Write-Host "  - Run Setup-LocalEnvironment.ps1 to configure the environment" -ForegroundColor White
    Write-Host "  - Copy required files from a D365 VM" -ForegroundColor White
    Write-Host "  - Ensure you're running on Windows with PowerShell 5.1+" -ForegroundColor White
    Write-Host ""
    Write-Host "For detailed help, see README_LOCAL_EXECUTION.md" -ForegroundColor Cyan
}

Write-Host ""
