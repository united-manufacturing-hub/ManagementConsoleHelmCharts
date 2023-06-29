param (
    [Parameter(Mandatory=$true)][string]$pat
)

# Ask user if he really intended to create a new version
$confirmation = Read-Host "Are you sure you want to create a new release? (y/n)"
if ($confirmation -ne "y") {
    exit 0
}

$ErrorActionPreference = "Stop"

$scriptPath = $PSScriptRoot
$parentPath = (Get-Item $scriptPath).Parent
$companionPath = Join-Path -Path $parentPath -ChildPath "ManagementConsoleCompanion"
$deployerPath =  Join-Path -Path $parentPath -ChildPath "MgmtConsoleDatasourceDeployer"
$helmChartPath = $scriptPath

## Goto ManagementConsoleHelmCharts repo
Set-Location $helmChartPath

# Get the current version
$currentVersion = (Get-Content deployment\mgmt-companion\Chart.yaml) -match '^version: \d+\.\d+\.\d+'
Write-Host "Current version: $currentVersion"

# Remove version: from string by replacing it with nothing
$currentVersion = $currentVersion -replace 'version: ', ''

# Trim whitespace
$currentVersion = $currentVersion.Trim()

# Increment patch version
$currentVersionX = $currentVersion -split '\.'


$patch = [int]::Parse($currentVersionX[2])+ 1

$releaseVersionX = $currentVersionX[0] + "." + $currentVersionX[1] + "." + $patch

Write-Host "Release version: $releaseVersionX"

(Get-Content deployment\mgmt-companion\Chart.yaml) `
    -replace '^version: \d+\.\d+\.\d+', "version: $releaseVersionX" `
    -replace '^appVersion: "\d+\.\d+\.\d+"', "appVersion: `"$releaseVersionX`"" |
        Out-File deployment\mgmt-companion\Chart.yaml

(Get-Content deployment\mgmt-companion\values.yaml) `
    -replace '^    tag: ".*"', "    tag: `"$releaseVersionX`"" |
        Out-File deployment\mgmt-companion\values.yaml


# Helm dep upgrade
Set-Location deployment\mgmt-companion
helm dependency update
Set-Location ..\..

# Create release
Set-Location deployment\helm-repo
helm package ../mgmt-companion/
Set-Location ..\..

# Update repo index
Set-Location deployment\helm-repo
helm repo index --url https://raw.githubusercontent.com/united-manufacturing-hub/ManagementConsoleHelmCharts/main/deployment/helm-repo/ --merge index.yaml .
Set-Location ..\..

# Commit and push changes
git add .
git commit -m "release: $releaseVersionX"
git push --no-verify

# For $companionPath & deployerPath
$paths = $companionPath, $deployerPath

foreach ($xPath in $paths)
{

    Set-Location $xPath
    # Build and push container
    Invoke-Expression "& .\build_and_push_container.ps1 -tag $releaseVersionX"
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "Build failed"
        exit 1
    }
    Invoke-Expression "& .\build_and_push_container.ps1 -tag latest"
    if ($LASTEXITCODE -ne 0)
    {
        Write-Host "Build failed"
        exit 1
    }

    ## Commit and push changes
    git add .
    git commit -m "release: $releaseVersionX"
    git push

    # Cleanup vendor folder
    Remove-Item -Recurse -Force vendor
    Set-Location $helmChartPath
}

# Display version
Write-Host "New version: $releaseVersionX"
