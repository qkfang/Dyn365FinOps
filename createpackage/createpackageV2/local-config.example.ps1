# Local Build Configuration Example
# Copy this file to local-config.ps1 and customize for your environment

# Path to X++ tools (from D365 VM or NuGet)
$XppToolsPath = "C:\D365Tools\XppTools"

# Path to your X++ binaries/packages
$XppBinariesPath = "C:\Build\Bin"

# Search pattern for packages (use * for all, or specify package names)
# For multiple packages, separate with line breaks:
# $XppBinariesSearch = @"
# Package1
# Package2
# Package3
# "@
$XppBinariesSearch = "*"

# Output path for the deployable package
$DeployablePackagePath = "C:\Output\DeployablePackage.zip"

# Create regular LCS package? (true/false)
$CreateRegularPackage = "true"

# Create Power Platform cloud package? (true/false)
$CreateCloudPackage = "false"

# Cloud package versions (only used if CreateCloudPackage = true)
$CloudPackagePlatVersion = "7.0.7279.112"
$CloudPackageAppVersion = "10.0.40.0"
$CloudPackageOutputLocation = "C:\Output\CloudPackage"

# Example usage:
# Load this configuration file in your scripts:
# . .\local-config.ps1
#
# Then run:
# .\CreatePackageLocal.ps1 `
#     -XppToolsPath $XppToolsPath `
#     -XppBinariesPath $XppBinariesPath `
#     -XppBinariesSearch $XppBinariesSearch `
#     -DeployablePackagePath $DeployablePackagePath `
#     -CreateRegularPackage $CreateRegularPackage `
#     -CreateCloudPackage $CreateCloudPackage `
#     -CloudPackagePlatVersion $CloudPackagePlatVersion `
#     -CloudPackageAppVersion $CloudPackageAppVersion `
#     -CloudPackageOutputLocation $CloudPackageOutputLocation
