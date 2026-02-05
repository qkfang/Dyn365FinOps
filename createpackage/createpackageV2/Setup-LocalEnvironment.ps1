<#
.SYNOPSIS
    Setup script to prepare local environment for X++ package creation
    
.DESCRIPTION
    This script downloads and configures the necessary tools and dependencies
    required to run the CreatePackage script locally, including:
    - NuGet.exe
    - Microsoft.Dynamics.AX.Platform.CompilerPackage
    - Microsoft.Dynamics.AX.Platform.DevALM.BuildXpp
    - Required X++ tools and assemblies
    
.PARAMETER ToolsDirectory
    Directory where tools will be installed (default: .\Tools)
    
.PARAMETER NuGetSource
    NuGet package source URL (default: https://pkgs.dev.azure.com/msazure/One/_packaging/DynamicsFinanceAndOperations/nuget/v3/index.json)
    
.PARAMETER PlatformVersion
    Dynamics 365 platform version to download (default: latest)
    
.EXAMPLE
    .\Setup-LocalEnvironment.ps1 -ToolsDirectory "C:\D365Tools"
    
.EXAMPLE
    .\Setup-LocalEnvironment.ps1 -PlatformVersion "7.0.7279.112"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$ToolsDirectory = ".\Tools",
    
    [Parameter(Mandatory=$false)]
    [string]$NuGetSource = "https://pkgs.dev.azure.com/msazure/One/_packaging/DynamicsFinanceAndOperations/nuget/v3/index.json",
    
    [Parameter(Mandatory=$false)]
    [string]$PlatformVersion = ""
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "D365 F&O Local Build Environment Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create tools directory
$ToolsDirectory = [System.IO.Path]::GetFullPath($ToolsDirectory)
if (-not (Test-Path -Path $ToolsDirectory)) {
    Write-Host "Creating tools directory: $ToolsDirectory" -ForegroundColor Yellow
    New-Item -Path $ToolsDirectory -ItemType Directory -Force | Out-Null
}

# Download NuGet.exe if not present
$nugetPath = Join-Path -Path $ToolsDirectory -ChildPath "nuget.exe"
if (-not (Test-Path -Path $nugetPath)) {
    Write-Host "Downloading NuGet.exe..." -ForegroundColor Yellow
    $nugetUrl = "https://dist.nuget.org/win-x86-commandline/latest/nuget.exe"
    try {
        Invoke-WebRequest -Uri $nugetUrl -OutFile $nugetPath
        Write-Host "NuGet.exe downloaded successfully" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to download NuGet.exe: $_"
        exit 1
    }
} else {
    Write-Host "NuGet.exe already exists" -ForegroundColor Green
}

# Create packages directory
$packagesDir = Join-Path -Path $ToolsDirectory -ChildPath "packages"
if (-not (Test-Path -Path $packagesDir)) {
    New-Item -Path $packagesDir -ItemType Directory -Force | Out-Null
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "NuGet Package Configuration" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""
Write-Host "NOTE: The default NuGet source requires authentication to Microsoft Azure DevOps."
Write-Host "If you don't have access, you can:" -ForegroundColor Yellow
Write-Host "  1. Use packages from a Dynamics 365 VM (PackagesLocalDirectory)" -ForegroundColor Cyan
Write-Host "  2. Contact Microsoft for access to the package feed" -ForegroundColor Cyan
Write-Host "  3. Use packages from an existing D365 development environment" -ForegroundColor Cyan
Write-Host ""

# Try to download compiler package (may fail if no auth)
Write-Host "Attempting to download Microsoft.Dynamics.AX.Platform.CompilerPackage..." -ForegroundColor Yellow

$versionArg = ""
if (-not [string]::IsNullOrEmpty($PlatformVersion)) {
# Build arguments array for nuget.exe
$nugetArgs = @(
    "install",
    "Microsoft.Dynamics.AX.Platform.CompilerPackage",
    "-OutputDirectory", $packagesDir,
    "-Source", $NuGetSource
)

if (-not [string]::IsNullOrEmpty($PlatformVersion)) {
    $nugetArgs += @("-Version", $PlatformVersion)
    Write-Host "  Specific version requested: $PlatformVersion"
}

Write-Host "  Command: nuget install Microsoft.Dynamics.AX.Platform.CompilerPackage"
Write-Host ""

try {
    & $nugetPath $nugetArgs
    Write-Host "Compiler package downloaded successfully" -ForegroundColor Green
} catch {
    Write-Warning "Could not download NuGet packages automatically."
    Write-Warning "Error: $_"
    Write-Host ""
    Write-Host "Manual Setup Instructions:" -ForegroundColor Yellow
    Write-Host "===========================" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Option 1: Copy from D365 VM" -ForegroundColor Cyan
    Write-Host "  Copy the following directories from a D365 F&O development VM:" -ForegroundColor Cyan
    Write-Host "    Source: K:\AosService\PackagesLocalDirectory\Bin" -ForegroundColor White
    Write-Host "    Target: $ToolsDirectory\XppTools" -ForegroundColor White
    Write-Host ""
    Write-Host "  Required files in XppTools directory:" -ForegroundColor Cyan
    Write-Host "    - CreatePackage.psm1" -ForegroundColor White
    Write-Host "    - Microsoft.Dynamics.AXCreateDeployablePackageBase.dll" -ForegroundColor White
    Write-Host "    - BaseMetadataDeployablePackage.zip" -ForegroundColor White
    Write-Host "    - Microsoft.Dynamics.AX.Metadata.Storage.dll" -ForegroundColor White
    Write-Host "    - Microsoft.Dynamics.ApplicationPlatform.Environment.dll" -ForegroundColor White
    Write-Host "    - And other related X++ compiler DLLs" -ForegroundColor White
    Write-Host ""
    Write-Host "Option 2: Use NuGet with Authentication" -ForegroundColor Cyan
    Write-Host "  Install Azure Artifacts Credential Provider:" -ForegroundColor Cyan
    Write-Host "    iex ((New-Object System.Net.WebClient).DownloadString('https://aka.ms/install-artifacts-credprovider.ps1'))" -ForegroundColor White
    Write-Host "  Then re-run this script" -ForegroundColor Cyan
    Write-Host ""
}

# Create XppTools directory structure
$xppToolsDir = Join-Path -Path $ToolsDirectory -ChildPath "XppTools"
if (-not (Test-Path -Path $xppToolsDir)) {
    New-Item -Path $xppToolsDir -ItemType Directory -Force | Out-Null
    Write-Host "Created XppTools directory: $xppToolsDir" -ForegroundColor Green
}

# Check if compiler package was downloaded
$compilerPackage = Get-ChildItem -Path $packagesDir -Directory -Filter "Microsoft.Dynamics.AX.Platform.CompilerPackage*" -ErrorAction SilentlyContinue | Select-Object -First 1

if ($compilerPackage) {
    Write-Host ""
    Write-Host "Found compiler package: $($compilerPackage.Name)" -ForegroundColor Green
    
    # Copy necessary files to XppTools
    $binPath = Join-Path -Path $compilerPackage.FullName -ChildPath "tools"
    if (Test-Path -Path $binPath) {
        Write-Host "Copying tools to XppTools directory..." -ForegroundColor Yellow
        Copy-Item -Path "$binPath\*" -Destination $xppToolsDir -Recurse -Force
        Write-Host "Tools copied successfully" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Yellow
Write-Host "Environment Status" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
Write-Host ""

# Check for required files
$requiredFiles = @(
    "CreatePackage.psm1",
    "Microsoft.Dynamics.AXCreateDeployablePackageBase.dll",
    "BaseMetadataDeployablePackage.zip"
)

$allFilesPresent = $true
foreach ($file in $requiredFiles) {
    $filePath = Join-Path -Path $xppToolsDir -ChildPath $file
    if (Test-Path -Path $filePath) {
        Write-Host "[OK] $file" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $file" -ForegroundColor Red
        $allFilesPresent = $false
    }
}

Write-Host ""
if ($allFilesPresent) {
    Write-Host "========================================" -ForegroundColor Green
    Write-Host "Setup completed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "XppTools directory: $xppToolsDir" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "You can now run:" -ForegroundColor Yellow
    Write-Host "  .\CreatePackageLocal.ps1 -XppToolsPath `"$xppToolsDir`" -XppBinariesPath `"<your-binaries-path>`" -DeployablePackagePath `"<output-path>`"" -ForegroundColor White
} else {
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "Setup incomplete - manual steps required" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please follow the manual setup instructions above to copy required files." -ForegroundColor Yellow
    Write-Host "Target directory: $xppToolsDir" -ForegroundColor Cyan
}

Write-Host ""
