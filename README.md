# Dynamics 365 Finance & Operations Build Tools

Azure DevOps extension for building and deploying Dynamics 365 Finance & Operations packages.

## Overview

This repository contains Azure DevOps pipeline extensions for Dynamics 365 Finance & Operations, including:
- Package creation and deployment
- Asset management (upload/download)
- Unit testing
- License management
- Model version updates

## Local Execution Support

The CreatePackage task now supports **local execution** outside of Azure DevOps pipelines!

### Quick Start (Local Execution)

Run the CreatePackage script locally on your development machine:

```powershell
cd createpackage/createpackageV2
.\QuickStart-Example.ps1
```

This will:
1. Set up the local tools environment
2. Create a dummy X++ project for testing
3. Generate a deployable package

For detailed instructions, see: [createpackage/createpackageV2/README_LOCAL_EXECUTION.md](createpackage/createpackageV2/README_LOCAL_EXECUTION.md)

## Repository Structure

```
.
├── addlicensetopackage/     - Add license files to packages
├── assetdeploy/             - Deploy assets to D365 environments
├── assetdownload/           - Download assets from LCS
├── assetupload/             - Upload assets to LCS
├── createpackage/           - Create deployable packages
│   └── createpackageV2/     - Latest version with local execution support
├── lcsserviceendpoint/      - LCS service endpoint configuration
├── runcloudruntimeunittest/ - Run X++ unit tests
└── updatemodelversion/      - Update model version numbers
```

## Features

### CreatePackage (Local & Azure DevOps)

Create deployable packages from X++ binaries:
- **Local execution** - Run on any Windows machine
- **Azure DevOps integration** - Works in build pipelines
- **Multiple package types**:
  - Lifecycle Services (LCS) Software Deployable Package
  - Power Platform Unified Package
- **Flexible packaging** - Single or multiple models

#### Local Usage Example

```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "MyPackage" `
    -DeployablePackagePath "C:\Output\Package.zip"
```

#### Azure DevOps Usage

Add the task to your pipeline:

```yaml
- task: XppCreatePackage@2
  inputs:
    XppToolsPath: '$(Pipeline.Workspace)/XppTools'
    XppBinariesPath: '$(Build.BinariesDirectory)'
    XppBinariesSearch: '*'
    DeployablePackagePath: '$(Build.ArtifactStagingDirectory)/Package.zip'
```

## Requirements

### For Local Execution
- Windows operating system
- PowerShell 5.1 or later
- .NET Framework 4.7.2 or later
- X++ build tools (from D365 VM or NuGet)

### For Azure DevOps
- Azure DevOps Services or Server
- Windows build agent
- Dynamics 365 F&O development environment or tools

## Getting Started

### Option 1: Local Development

1. Clone this repository
2. Navigate to `createpackage/createpackageV2`
3. Run `.\Setup-LocalEnvironment.ps1` to configure tools
4. Run `.\QuickStart-Example.ps1` to test the setup

### Option 2: Azure DevOps Extension

1. Install the extension from Visual Studio Marketplace
2. Add tasks to your build pipeline
3. Configure service connections to LCS (if needed)

## Documentation

- **Local Execution Guide**: [createpackage/createpackageV2/README_LOCAL_EXECUTION.md](createpackage/createpackageV2/README_LOCAL_EXECUTION.md)
- **Azure DevOps Documentation**: [overview.md](overview.md)
- **Microsoft Docs**: [Build automation using Microsoft-hosted agents](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/dev-tools/hosted-build-automation)

## Scripts Overview

### CreatePackageLocal.ps1
Wrapper script that allows running CreatePackage.ps1 locally without Azure DevOps SDK dependencies.

### Setup-LocalEnvironment.ps1
Downloads and configures required tools and dependencies for local execution.

### Create-DummyXppProject.ps1
Creates a minimal valid X++ project structure for testing package creation.

### QuickStart-Example.ps1
End-to-end example demonstrating the complete local build process.

## Troubleshooting

### Common Issues

**"Required parameter 'XppToolsPath' was not provided"**
- Ensure all required parameters are passed to the script
- Use absolute paths when possible

**"No X++ binary package(s) found"**
- Verify your binaries path contains valid X++ packages
- Check that packages have a `bin\` folder with `.md` files
- Verify your search pattern matches your package names

**"Cannot find path '...\CreatePackage.psm1'"**
- Copy the file from a D365 VM: `K:\AosService\PackagesLocalDirectory\Bin`
- Or download via NuGet with proper authentication

For more troubleshooting help, see the [README_LOCAL_EXECUTION.md](createpackage/createpackageV2/README_LOCAL_EXECUTION.md) file.

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## References

- [Dynamics 365 F&O Developer Documentation](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/)
- [Create deployable packages](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/deployment/create-apply-deployable-package)
- [Package Deployer tool](https://learn.microsoft.com/en-us/power-platform/alm/package-deployer-tool)

## License

Copyright © Microsoft Corporation. All rights reserved.