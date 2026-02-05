# GETTING STARTED - Quick Reference

This is a quick reference guide to get you started with local X++ package creation.

## Prerequisites Check

Run this first to verify your environment:
```powershell
cd createpackage/createpackageV2
.\Test-LocalEnvironment.ps1
```

## Option 1: Quick Test (No D365 VM Required)

Perfect for testing the scripts without real X++ tools:

```powershell
# Run the complete quick start example
.\QuickStart-Example.ps1
```

**Note:** This will fail at the package creation step without real XppTools, but it will:
- Set up the directory structure
- Create a dummy X++ project
- Show you what's missing

## Option 2: Full Setup (Requires D365 VM Access)

If you have access to a Dynamics 365 F&O development VM:

### Step 1: Copy XppTools from D365 VM

From your D365 VM, copy:
```
Source: K:\AosService\PackagesLocalDirectory\Bin
Target: C:\D365Tools\XppTools  (or your preferred location)
```

**Required files include:**
- CreatePackage.psm1
- Microsoft.Dynamics.AXCreateDeployablePackageBase.dll
- BaseMetadataDeployablePackage.zip
- Microsoft.Dynamics.AX.Metadata.Storage.dll
- All related DLLs

### Step 2: Create Test Project

```powershell
.\Create-DummyXppProject.ps1 `
    -OutputPath "C:\Build\Bin" `
    -PackageName "MyTestPackage"
```

### Step 3: Build Package

```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "MyTestPackage" `
    -DeployablePackagePath "C:\Output\Package.zip"
```

## Option 3: Use with Real X++ Build Output

If you have actual X++ source code and build output:

```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "K:\AosService\PackagesLocalDirectory" `
    -XppBinariesSearch "MyModel" `
    -DeployablePackagePath "C:\Output\MyModel.zip"
```

## Using Configuration Files

### Step 1: Create config file
```powershell
# Copy the example config
Copy-Item local-config.example.ps1 local-config.ps1

# Edit local-config.ps1 with your paths
notepad local-config.ps1
```

### Step 2: Use the config
```powershell
# Load configuration
. .\local-config.ps1

# Run with loaded config
.\CreatePackageLocal.ps1 `
    -XppToolsPath $XppToolsPath `
    -XppBinariesPath $XppBinariesPath `
    -XppBinariesSearch $XppBinariesSearch `
    -DeployablePackagePath $DeployablePackagePath
```

## Common Commands

### Validate Environment
```powershell
.\Test-LocalEnvironment.ps1 -XppToolsPath "C:\D365Tools\XppTools"
```

### Setup Tools
```powershell
.\Setup-LocalEnvironment.ps1 -ToolsDirectory "C:\D365Tools"
```

### Create Test Project
```powershell
.\Create-DummyXppProject.ps1 -OutputPath "C:\Build\Bin" -PackageName "TestPkg"
```

### Build Package (Single)
```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "Package1" `
    -DeployablePackagePath "C:\Output\Package1.zip"
```

### Build Package (Multiple)
```powershell
$searchPattern = @"
Package1
Package2
Package3
"@

.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch $searchPattern `
    -DeployablePackagePath "C:\Output\Combined.zip"
```

### Build Cloud Package
```powershell
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\Tools\XppTools" `
    -XppBinariesPath "C:\Build\Bin" `
    -XppBinariesSearch "MyPackage" `
    -DeployablePackagePath "C:\Output\Regular.zip" `
    -CreateRegularPackage "true" `
    -CreateCloudPackage "true" `
    -CloudPackagePlatVersion "7.0.7279.112" `
    -CloudPackageAppVersion "10.0.40.0" `
    -CloudPackageOutputLocation "C:\Output\Cloud"
```

## Troubleshooting Quick Fixes

### Error: "Required parameter 'XppToolsPath' was not provided"
**Fix:** Make sure you're providing all required parameters

### Error: "Directory not found"
**Fix:** Check paths exist, use absolute paths:
```powershell
$XppToolsPath = (Resolve-Path "C:\Tools\XppTools").Path
```

### Error: "No X++ binary package(s) found"
**Fix:** Verify package structure:
```powershell
# Check if package exists
Test-Path "C:\Build\Bin\MyPackage\bin\*.md"
```

### Error: "Cannot find path '...\CreatePackage.psm1'"
**Fix:** Copy from D365 VM:
```
Source: K:\AosService\PackagesLocalDirectory\Bin\CreatePackage.psm1
Target: C:\D365Tools\XppTools\CreatePackage.psm1
```

## Next Steps

1. **Read the full documentation:**
   - [README_LOCAL_EXECUTION.md](README_LOCAL_EXECUTION.md) - Complete guide
   - [../README.md](../README.md) - Repository overview

2. **Explore examples:**
   - Check [local-config.example.ps1](local-config.example.ps1) for configuration options
   - Run [QuickStart-Example.ps1](QuickStart-Example.ps1) to see the full workflow

3. **Integrate with CI/CD:**
   - Add scripts to your build pipeline
   - Use configuration files for different environments
   - Automate package creation

## Help & Support

For detailed troubleshooting, see:
- [README_LOCAL_EXECUTION.md - Troubleshooting Section](README_LOCAL_EXECUTION.md#troubleshooting)

For issues or improvements:
- Check the repository's issue tracker
- Review recent commits for updates

## Quick File Reference

| Script | Purpose |
|--------|---------|
| `CreatePackageLocal.ps1` | Main script for local package creation |
| `Setup-LocalEnvironment.ps1` | Configure tools and dependencies |
| `Create-DummyXppProject.ps1` | Generate test X++ project |
| `QuickStart-Example.ps1` | Complete end-to-end example |
| `Test-LocalEnvironment.ps1` | Validate environment setup |
| `local-config.example.ps1` | Configuration template |
| `README_LOCAL_EXECUTION.md` | Complete documentation |

## Tips

- Always use absolute paths to avoid confusion
- Run `Test-LocalEnvironment.ps1` after any configuration changes
- Keep your XppTools directory up to date with the latest version from your D365 environment
- Use configuration files to manage different environments (dev, test, prod)
- The original `CreatePackage.ps1` still works in Azure DevOps without any changes

---

**Ready to start?** Run `.\QuickStart-Example.ps1` now!
