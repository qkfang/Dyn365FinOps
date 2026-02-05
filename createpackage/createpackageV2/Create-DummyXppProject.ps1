<#
.SYNOPSIS
    Creates a dummy X++ project structure for testing package creation
    
.DESCRIPTION
    This script creates a minimal but valid X++ binary structure that can be used
    to test the CreatePackage functionality locally without requiring a full
    Dynamics 365 build environment.
    
.PARAMETER OutputPath
    Path where the dummy project will be created
    
.PARAMETER PackageName
    Name of the dummy package (default: TestPackage)
    
.PARAMETER Version
    Version number for the package (default: 1.0.0.0)
    
.EXAMPLE
    .\Create-DummyXppProject.ps1 -OutputPath "C:\Build\Bin" -PackageName "MyTestPackage"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,
    
    [Parameter(Mandatory=$false)]
    [string]$PackageName = "TestPackage",
    
    [Parameter(Mandatory=$false)]
    [string]$Version = "1.0.0.0"
)

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Creating Dummy X++ Project" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Create output directory
$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$packagePath = Join-Path -Path $OutputPath -ChildPath $PackageName

if (Test-Path -Path $packagePath) {
    Write-Host "Package directory already exists: $packagePath" -ForegroundColor Yellow
    $response = Read-Host "Do you want to overwrite it? (Y/N)"
    if ($response -ne 'Y' -and $response -ne 'y') {
        Write-Host "Aborted." -ForegroundColor Red
        exit 0
    }
    Remove-Item -Path $packagePath -Recurse -Force
}

Write-Host "Creating package directory: $packagePath" -ForegroundColor Yellow
New-Item -Path $packagePath -ItemType Directory -Force | Out-Null

# Create bin directory
$binPath = Join-Path -Path $packagePath -ChildPath "bin"
New-Item -Path $binPath -ItemType Directory -Force | Out-Null

Write-Host "Creating dummy X++ binaries..." -ForegroundColor Yellow

# Create a dummy DLL with version info
$dllPath = Join-Path -Path $binPath -ChildPath "Dynamics.AX.$PackageName.dll"

# Create a minimal .NET assembly using Add-Type
$code = @"
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

[assembly: AssemblyTitle("Dynamics.AX.$PackageName")]
[assembly: AssemblyDescription("Dummy X++ Package for testing")]
[assembly: AssemblyConfiguration("")]
[assembly: AssemblyCompany("Test Company")]
[assembly: AssemblyProduct("Dynamics.AX.$PackageName")]
[assembly: AssemblyCopyright("Copyright © 2024")]
[assembly: AssemblyTrademark("")]
[assembly: AssemblyCulture("")]
[assembly: AssemblyVersion("$Version")]
[assembly: AssemblyFileVersion("$Version")]

namespace Dynamics.AX.$PackageName
{
    public class DummyClass
    {
        public string GetMessage()
        {
            return "This is a dummy X++ package for testing";
        }
    }
}
"@

try {
    Add-Type -TypeDefinition $code -OutputAssembly $dllPath -OutputType Library
    Write-Host "Created DLL: $dllPath" -ForegroundColor Green
}
catch {
    Write-Warning "Could not create .NET assembly: $_"
    Write-Host "Creating placeholder DLL file..." -ForegroundColor Yellow
    # Create a minimal file if Add-Type fails
    "Dummy DLL placeholder" | Out-File -FilePath $dllPath -Encoding ASCII
}

# Create dummy metadata files (.md files are required for X++ validation)
Write-Host "Creating metadata files..." -ForegroundColor Yellow

# Create dummy metadata descriptor file
$metadataFiles = @(
    "AxClass_$PackageName.xml",
    "AxTable_$PackageName`Table.xml",
    "AxForm_$PackageName`Form.xml"
)

foreach ($mdFile in $metadataFiles) {
    $mdFilePath = Join-Path -Path $binPath -ChildPath "$mdFile.md"
    
    $metadataContent = @"
<?xml version="1.0" encoding="utf-8"?>
<AxClass xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
  <Name>$PackageName</Name>
  <SourceCode>
    <Declaration><![CDATA[
/// <summary>
/// Dummy X++ class for testing package creation
/// </summary>
class $PackageName
{
}
]]></Declaration>
    <Methods>
      <Method>
        <Name>main</Name>
        <Source><![CDATA[
public static void main(Args _args)
{
    info("Dummy package: $PackageName");
}
]]></Source>
      </Method>
    </Methods>
  </SourceCode>
</AxClass>
"@
    
    $metadataContent | Out-File -FilePath $mdFilePath -Encoding UTF8
    Write-Host "  Created: $mdFile.md" -ForegroundColor Gray
}

# Create package manifest
Write-Host "Creating package manifest..." -ForegroundColor Yellow
$manifestPath = Join-Path -Path $packagePath -ChildPath "Descriptor"
New-Item -Path $manifestPath -ItemType Directory -Force | Out-Null

$modelManifestPath = Join-Path -Path $manifestPath -ChildPath "$PackageName.xml"
$manifestContent = @"
<?xml version="1.0" encoding="utf-8"?>
<AxModelInfo xmlns:i="http://www.w3.org/2001/XMLSchema-instance">
  <AppliedUpdates xmlns:d2p1="http://schemas.microsoft.com/2003/10/Serialization/Arrays" />
  <Customization>DoNotAllow</Customization>
  <Description>Dummy test package for local build testing</Description>
  <DisplayName>$PackageName</DisplayName>
  <Id>12345678-1234-1234-1234-123456789012</Id>
  <Layer>ISV</Layer>
  <Layering>AllowCustomizationsAndExtensions</Layering>
  <ModuleReferences xmlns:d2p1="http://schemas.microsoft.com/2003/10/Serialization/Arrays" />
  <Name>$PackageName</Name>
  <Publisher>Test Publisher</Publisher>
  <Signed>false</Signed>
  <VersionBuildNumber>0</VersionBuildNumber>
  <VersionMajor>1</VersionMajor>
  <VersionMinor>0</VersionMinor>
  <VersionRevision>0</VersionRevision>
</AxModelInfo>
"@

$manifestContent | Out-File -FilePath $modelManifestPath -Encoding UTF8
Write-Host "Created manifest: $modelManifestPath" -ForegroundColor Green

# Create package-level descriptor
$packageDescriptorPath = Join-Path -Path $packagePath -ChildPath "Descriptor\$PackageName.Package.xml"
$packageDescriptorContent = @"
<?xml version="1.0" encoding="utf-8"?>
<PackageDescriptor>
  <Name>$PackageName</Name>
  <Description>Dummy test package</Description>
  <Version>$Version</Version>
</PackageDescriptor>
"@

$packageDescriptorContent | Out-File -FilePath $packageDescriptorPath -Encoding UTF8

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "Dummy X++ Project Created Successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Package Location: $packagePath" -ForegroundColor Cyan
Write-Host "Package Name: $PackageName" -ForegroundColor Cyan
Write-Host "Version: $Version" -ForegroundColor Cyan
Write-Host ""
Write-Host "Structure created:" -ForegroundColor Yellow
Write-Host "  $PackageName\" -ForegroundColor White
Write-Host "    bin\" -ForegroundColor White
Write-Host "      Dynamics.AX.$PackageName.dll" -ForegroundColor Gray
Write-Host "      *.xml.md (metadata files)" -ForegroundColor Gray
Write-Host "    Descriptor\" -ForegroundColor White
Write-Host "      $PackageName.xml" -ForegroundColor Gray
Write-Host ""
Write-Host "You can now use this with CreatePackageLocal.ps1:" -ForegroundColor Yellow
Write-Host "  -XppBinariesPath `"$OutputPath`"" -ForegroundColor White
Write-Host "  -XppBinariesSearch `"$PackageName`"" -ForegroundColor White
Write-Host ""
