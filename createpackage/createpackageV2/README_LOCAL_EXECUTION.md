# Running CreatePackage Locally

This guide explains how to run the Dynamics 365 Finance & Operations package creation process locally, outside of an Azure DevOps pipeline.

## Overview

The scripts in this directory allow you to create deployable packages for D365 F&O locally without requiring:
- Azure DevOps pipeline context
- Build agents
- Azure DevOps SDK dependencies

## Prerequisites

### Required Software
- **PowerShell 5.1 or later** (Windows PowerShell or PowerShell Core)
- **.NET Framework 4.7.2 or later** (for creating assemblies)
- **Windows operating system** (required for X++ tools compatibility)

### Required Tools and Files
You need the X++ build tools from one of these sources:

#### Option 1: Copy from D365 Development VM (Recommended)
If you have access to a Dynamics 365 F&O development VM:

1. Copy the entire `Bin` directory from:
   ```
   K:\AosService\PackagesLocalDirectory\Bin
   ```
   To a local directory (e.g., `C:\D365Tools\XppTools`)

2. Key files you need:
   - `CreatePackage.psm1`
   - `Microsoft.Dynamics.AXCreateDeployablePackageBase.dll`
   - `BaseMetadataDeployablePackage.zip`
   - `Microsoft.Dynamics.AX.Metadata.Storage.dll`
   - `Microsoft.Dynamics.ApplicationPlatform.Environment.dll`
   - Other X++ compiler and metadata DLLs

#### Option 2: Download via NuGet (Requires Authentication)
If you have access to Microsoft's internal NuGet feed:

1. Install Azure Artifacts Credential Provider:
   ```powershell
   iex ((New-Object System.Net.WebClient).DownloadString('https://aka.ms/install-artifacts-credprovider.ps1'))
   ```

2. Run the setup script:
   ```powershell
   .\Setup-LocalEnvironment.ps1 -ToolsDirectory "C:\D365Tools"
   ```

## Setup Instructions

### Step 1: Prepare the Environment

Run the setup script to configure your local environment:

```powershell
.\Setup-LocalEnvironment.ps1 -ToolsDirectory "C:\D365Tools"
```

This script will:
- Download NuGet.exe
- Attempt to download X++ compiler packages (if authenticated)
- Create the necessary directory structure
- Provide instructions for manual setup if needed

### Step 2: Create a Test Project (Optional)

To test the package creation process, create a dummy X++ project:

```powershell
.\Create-DummyXppProject.ps1 -OutputPath "C:\Build\Bin" -PackageName "MyTestPackage"
```

This creates a minimal valid X++ package structure for testing.

### Step 3: Run Package Creation

Use the local wrapper script to create packages:

```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "MyTestPackage" `
    -DeployablePackagePath "C:\Output\MyPackage.zip"
```

## Script Reference

### CreatePackageLocal.ps1

Main script for local package creation.

**Parameters:**
- `XppToolsPath` (Required): Path to X++ tools directory
- `XppBinariesPath` (Required): Path containing X++ binaries to package
- `XppBinariesSearch` (Optional): Search pattern for packages (default: "*")
- `DeployablePackagePath` (Required): Output path for the deployable package
- `CreateRegularPackage` (Optional): Create LCS package (default: "true")
- `CreateCloudPackage` (Optional): Create Power Platform package (default: "false")
- `CloudPackagePlatVersion` (Optional): Platform version for cloud package
- `CloudPackageAppVersion` (Optional): App version for cloud package
- `CloudPackageOutputLocation` (Optional): Output location for cloud package

**Example - Single Package:**
```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "MyPackage" `
    -DeployablePackagePath "C:\Output\Package.zip"
```

**Example - Multiple Packages:**
```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "Package1`nPackage2`nPackage3" `
    -DeployablePackagePath "C:\Output\CombinedPackage.zip"
```

**Example - Cloud Package:**
```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "MyPackage" `
    -DeployablePackagePath "C:\Output\Package.zip" `
    -CreateCloudPackage "true" `
    -CloudPackagePlatVersion "7.0.7279.112" `
    -CloudPackageAppVersion "10.0.40.0" `
    -CloudPackageOutputLocation "C:\Output\CloudPackage"
```

### Setup-LocalEnvironment.ps1

Prepares the local environment with necessary tools.

**Parameters:**
- `ToolsDirectory` (Optional): Where to install tools (default: ".\Tools")
- `NuGetSource` (Optional): NuGet package source URL
- `PlatformVersion` (Optional): Specific D365 platform version

**Example:**
```powershell
.\Setup-LocalEnvironment.ps1 -ToolsDirectory "C:\D365Tools"
```

### Create-DummyXppProject.ps1

Creates a dummy X++ project for testing.

**Parameters:**
- `OutputPath` (Required): Where to create the project
- `PackageName` (Optional): Name of the package (default: "TestPackage")
- `Version` (Optional): Version number (default: "1.0.0.0")

**Example:**
```powershell
.\Create-DummyXppProject.ps1 `
    -OutputPath "C:\Build\Bin" `
    -PackageName "MyTestPackage" `
    -Version "1.0.0.0"
```

## Expected X++ Binary Structure

Your X++ binaries directory should have this structure:

```
Bin\
  ├── PackageName1\
  │   ├── bin\
  │   │   ├── Dynamics.AX.PackageName1.dll
  │   │   ├── *.xml.md (metadata files)
  │   │   └── ... (other binaries)
  │   └── Descriptor\
  │       └── PackageName1.xml
  ├── PackageName2\
  │   └── ...
```

**Required in each package:**
- `bin\` folder containing:
  - `Dynamics.AX.<PackageName>.dll` (main assembly)
  - At least one `.md` file (metadata descriptor)
- `Descriptor\<PackageName>.xml` (model manifest)

## Troubleshooting

### Error: "Required parameter 'XppToolsPath' was not provided"
**Solution:** Ensure you're passing all required parameters to CreatePackageLocal.ps1

### Error: "Directory not found: <path>"
**Solution:** Verify the paths exist and are accessible. Use absolute paths when possible.

### Error: "No X++ binary package(s) found"
**Solution:** 
- Check that your XppBinariesPath contains valid X++ packages
- Verify packages have a `bin\` folder with `.md` files
- Check your XppBinariesSearch pattern matches your package names

### Error: "Cannot find path '...\CreatePackage.psm1'"
**Solution:** 
- Ensure XppToolsPath contains the CreatePackage.psm1 module
- Copy it from a D365 VM or download via NuGet

### Error: "Could not load file or assembly..."
**Solution:**
- Ensure all required DLLs are present in XppToolsPath
- Copy the entire Bin directory from a D365 VM
- Check .NET Framework version (4.7.2+ required)

### Warning: "not an X++ binary folder, skipped"
**Solution:** The folder doesn't contain valid X++ binaries. Ensure:
- A `bin\` subfolder exists
- The `bin\` folder contains at least one `.md` file

## Advanced Configuration

### Using with Real X++ Build Output

If you have X++ source code and want to build it:

1. Build your X++ code using the standard D365 build process or Visual Studio
2. Locate the build output (usually in `PackagesLocalDirectory`)
3. Point XppBinariesPath to that location
4. Run CreatePackageLocal.ps1

### Creating Multiple Package Types

You can create both regular and cloud packages in one run:

```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "*" `
    -DeployablePackagePath "C:\Output\LCSPackage.zip" `
    -CreateRegularPackage "true" `
    -CreateCloudPackage "true" `
    -CloudPackagePlatVersion "7.0.7279.112" `
    -CloudPackageAppVersion "10.0.40.0" `
    -CloudPackageOutputLocation "C:\Output\PPPackage"
```

### Integration with CI/CD

You can integrate these scripts into your CI/CD pipeline:

```powershell
# In your build script
.\Create-DummyXppProject.ps1 -OutputPath "$env:BUILD_BINARIESDIRECTORY" -PackageName "MyPackage"

.\CreatePackageLocal.ps1 `
    -XppToolsPath "$env:D365_TOOLS_PATH" `
    -XppBinariesPath "$env:BUILD_BINARIESDIRECTORY" `
    -DeployablePackagePath "$env:BUILD_ARTIFACTSTAGINGDIRECTORY\Package.zip"
```

## Notes

- The original `CreatePackage.ps1` script remains unchanged and continues to work in Azure DevOps pipelines
- `CreatePackageLocal.ps1` wraps the original script and provides mock implementations of Azure DevOps SDK functions
- This approach ensures compatibility and allows the same core logic to run in both environments

## Support and Contributions

For issues or improvements, please refer to the repository's issue tracker.

## References

- [Dynamics 365 F&O Developer Documentation](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/)
- [Build automation using Microsoft-hosted agents](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/dev-tools/hosted-build-automation)
- [Create deployable packages of models](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/deployment/create-apply-deployable-package)
