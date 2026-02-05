# Windows Testing Guide

This document provides instructions for testing the local execution scripts on Windows with actual D365 F&O tools.

## Prerequisites for Windows Testing

### Required Software
- Windows 10 or Windows Server
- PowerShell 5.1 or later
- .NET Framework 4.7.2 or later
- Access to a Dynamics 365 F&O development VM

### Required Tools
From your D365 development VM, copy the following directory:
```
Source: K:\AosService\PackagesLocalDirectory\Bin
Target: C:\D365Tools\XppTools
```

**Critical files needed:**
- `CreatePackage.psm1`
- `Microsoft.Dynamics.AXCreateDeployablePackageBase.dll`
- `BaseMetadataDeployablePackage.zip`
- `Microsoft.Dynamics.AX.Metadata.Storage.dll`
- `Microsoft.Dynamics.ApplicationPlatform.Environment.dll`
- All related X++ compiler DLLs

## Test Procedure

### 1. Environment Setup Test

Open PowerShell as Administrator and run:

```powershell
cd createpackage\createpackageV2

# Run environment validation
.\Test-LocalEnvironment.ps1 -XppToolsPath "C:\D365Tools\XppTools"
```

**Expected Result:** All checks should pass with green [OK] messages.

### 2. Dummy Project Creation Test

```powershell
# Create a test project
.\Create-DummyXppProject.ps1 `
    -OutputPath "C:\TestBuild\Bin" `
    -PackageName "MyTestPackage" `
    -Version "1.0.0.0"
```

**Expected Result:**
- Directory created at `C:\TestBuild\Bin\MyTestPackage`
- `bin\` folder contains DLL and .md files
- `Descriptor\` folder contains XML manifest

**Verify Structure:**
```powershell
tree /F C:\TestBuild\Bin\MyTestPackage
```

Should show:
```
MyTestPackage
├── bin
│   ├── Dynamics.AX.MyTestPackage.dll
│   ├── AxClass_MyTestPackage.xml.md
│   ├── AxForm_MyTestPackageForm.xml.md
│   └── AxTable_MyTestPackageTable.xml.md
└── Descriptor
    ├── MyTestPackage.xml
    └── MyTestPackage.Package.xml
```

### 3. Package Creation Test (Dummy Project)

```powershell
# Create a deployable package from the dummy project
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\TestBuild\Bin" `
    -XppBinariesSearch "MyTestPackage" `
    -DeployablePackagePath "C:\TestOutput\MyTestPackage.zip"
```

**Expected Result:**
- Package created at `C:\TestOutput\MyTestPackage.zip`
- Console output shows:
  - Found X++ binary package
  - Creating binary packages
  - Creating deployable package
  - Success message

**Verify Package:**
```powershell
# Check package exists and size
Get-Item C:\TestOutput\MyTestPackage.zip | Select-Object Name, Length
```

### 4. Package Creation Test (Real Project)

If you have actual X++ build output:

```powershell
# Use with real X++ binaries
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "K:\AosService\PackagesLocalDirectory" `
    -XppBinariesSearch "YourModelName" `
    -DeployablePackagePath "C:\Output\YourModel.zip"
```

**Expected Result:**
- Package created successfully
- Package contains your model's deployable artifacts
- Can be deployed to D365 environment

### 5. Multiple Package Test

```powershell
# Create package with multiple models
$models = @"
Model1
Model2
Model3
"@

.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "K:\AosService\PackagesLocalDirectory" `
    -XppBinariesSearch $models `
    -DeployablePackagePath "C:\Output\CombinedPackage.zip"
```

**Expected Result:**
- All specified models included in package
- Single deployable package created
- Console shows processing for each model

### 6. Cloud Package Test

```powershell
# Create both regular and cloud package
.\CreatePackageLocal.ps1 `
    -XppToolsPath "C:\D365Tools\XppTools" `
    -XppBinariesPath "C:\TestBuild\Bin" `
    -XppBinariesSearch "MyTestPackage" `
    -DeployablePackagePath "C:\Output\Regular.zip" `
    -CreateRegularPackage "true" `
    -CreateCloudPackage "true" `
    -CloudPackagePlatVersion "7.0.7279.112" `
    -CloudPackageAppVersion "10.0.40.0" `
    -CloudPackageOutputLocation "C:\Output\CloudPackage"
```

**Expected Result:**
- Regular package at `C:\Output\Regular.zip`
- Cloud package directory at `C:\Output\CloudPackage`
- Both packages created successfully

### 7. QuickStart Example Test

```powershell
# Run the complete workflow
.\QuickStart-Example.ps1
```

**Expected Result:**
- Automatic setup of LocalTools directory
- Dummy project created
- Package created successfully
- Clear success message with file size

## Validation Checklist

After running tests, verify:

- [ ] All scripts execute without PowerShell syntax errors
- [ ] Test-LocalEnvironment.ps1 passes all checks on Windows
- [ ] Create-DummyXppProject.ps1 creates valid structure
- [ ] CreatePackageLocal.ps1 accepts all parameters correctly
- [ ] Deployable package is created (check file size > 0)
- [ ] Package can be extracted (test with 7-Zip or WinRAR)
- [ ] Mock functions work correctly
- [ ] Error messages are clear and actionable
- [ ] Documentation matches actual behavior

## Common Test Issues and Solutions

### Issue: "Cannot find path 'CreatePackage.psm1'"
**Solution:** Ensure XppToolsPath points to the correct Bin directory from D365 VM.

### Issue: "Could not load file or assembly"
**Solution:** 
- Ensure all DLLs from D365 VM are present
- Check .NET Framework version (4.7.2+ required)
- Run as Administrator if permission issues

### Issue: "No X++ binary package(s) found"
**Solution:**
- Verify package has `bin\` folder with `.md` files
- Check XppBinariesSearch pattern matches folder name
- Use absolute paths

### Issue: Package size is very small (< 1 KB)
**Solution:**
- This may indicate mock/test mode
- Verify actual D365 tools are being used
- Check for errors in console output

## Performance Benchmarks

Expected execution times (varies by hardware):

| Operation | Time (approx) |
|-----------|---------------|
| Create dummy project | < 5 seconds |
| Validate environment | < 2 seconds |
| Create small package (1 model) | 30-60 seconds |
| Create large package (10+ models) | 2-5 minutes |

## Screenshot Checklist

When documenting test results, capture:

1. ✅ Test-LocalEnvironment.ps1 output showing all green checks
2. ✅ Created dummy project directory structure
3. ✅ CreatePackageLocal.ps1 successful execution
4. ✅ Created package file properties (name, size, date)
5. ✅ Contents of package (extracted view)

## Reporting Test Results

When reporting test results, include:

```
Environment:
- OS Version: [e.g., Windows 10 Pro, Version 21H2]
- PowerShell Version: [e.g., 5.1.19041.2364]
- .NET Framework Version: [e.g., 4.8]
- D365 Platform Version: [e.g., 7.0.7279.112]

Tests Run:
✓ Environment validation
✓ Dummy project creation
✓ Single package creation
✓ Multiple package creation
✓ Cloud package creation

Results:
- All tests passed
- Package created: [size in MB]
- Execution time: [time in seconds]

Issues Found:
[None or list of issues]
```

## Integration with CI/CD

To integrate with CI/CD on Windows:

```powershell
# Example Azure Pipeline script
- task: PowerShell@2
  inputs:
    targetType: 'inline'
    script: |
      cd $(Build.Repository.LocalPath)\createpackage\createpackageV2
      
      # Load configuration
      . .\local-config.ps1
      
      # Create package
      .\CreatePackageLocal.ps1 `
        -XppToolsPath $XppToolsPath `
        -XppBinariesPath $XppBinariesPath `
        -XppBinariesSearch $XppBinariesSearch `
        -DeployablePackagePath $DeployablePackagePath
      
      # Verify package was created
      if (Test-Path $DeployablePackagePath) {
          Write-Host "Package created successfully"
          exit 0
      } else {
          Write-Error "Package creation failed"
          exit 1
      }
```

## Next Steps After Testing

1. Document any issues found
2. Create GitHub issues for bugs
3. Update documentation with any clarifications
4. Share test results with team
5. Deploy packages to test environment

## Support

For issues during testing:
- Check [README_LOCAL_EXECUTION.md](README_LOCAL_EXECUTION.md) for troubleshooting
- Review [GETTING_STARTED.md](GETTING_STARTED.md) for quick fixes
- Ensure you're using the latest version of the scripts
