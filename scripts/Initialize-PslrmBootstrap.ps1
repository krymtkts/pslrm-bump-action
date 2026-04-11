[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('core', 'desktop')]
    [string] $TargetPowerShellEdition,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $PslrmVersionPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $PslrmVersionPath -PathType Leaf)) {
    throw "Bundled pslrm version file not found: $PslrmVersionPath"
}

$resolvedPslrmVersionPath = (Resolve-Path -LiteralPath $PslrmVersionPath).Path
$pslrmVersionData = Import-PowerShellDataFile -Path $resolvedPslrmVersionPath
$pslrmVersion = $pslrmVersionData.pslrm
if ([string]::IsNullOrWhiteSpace($pslrmVersion)) {
    throw "The bundled pslrm version is not defined in $resolvedPslrmVersionPath."
}

# NOTE: act smoke needs a newer PSResourceGet on core to avoid PSGallery ApiVersion V2 failures.
Install-Module -Name Microsoft.PowerShell.PSResourceGet -Force -Scope CurrentUser -Repository PSGallery -SkipPublisherCheck -AllowPrerelease

$psResourceGetModule = Get-Module -ListAvailable -Name Microsoft.PowerShell.PSResourceGet |
    Sort-Object Version -Descending |
    Select-Object -First 1
if ($null -eq $psResourceGetModule) {
    throw 'Microsoft.PowerShell.PSResourceGet was not found after installation.'
}

Import-Module $psResourceGetModule.Path -ErrorAction Stop -Force
# NOTE: Normalize PSGallery before Install-PSResource; act smoke can start with a missing repository store.
Get-PSResourceRepository -Name PSGallery | Out-Null
Set-PSResourceRepository -Name PSGallery -Trusted -ApiVersion V2
Install-PSResource -Name pslrm -Version $pslrmVersion -Prerelease -Scope CurrentUser -Repository PSGallery -TrustRepository

if ($pslrmVersion -notmatch '^(?<Version>\d+\.\d+\.\d+)(?:-(?<Prerelease>.+))?$') {
    throw "Unsupported bundled pslrm version format: $pslrmVersion"
}

$installedPslrmModules = @(
    Get-InstalledPSResource -Name pslrm |
        Where-Object {
            $_.Version.ToString() -eq $Matches.Version -and
            ($_.Prerelease ?? '') -eq ($Matches.Prerelease ?? '')
        }
)
if ($installedPslrmModules.Count -eq 0) {
    throw "Installed bundled pslrm module was not found: $pslrmVersion"
}

$installedPslrmModule = $installedPslrmModules[0]
# NOTE: Return the installed manifest path because prerelease labels are outside ModuleVersion.
$pslrmModulePath = Join-Path $installedPslrmModule.InstalledLocation "pslrm/$($installedPslrmModule.Version)/pslrm.psd1"
if (-not (Test-Path -LiteralPath $pslrmModulePath -PathType Leaf)) {
    throw "Installed bundled pslrm module manifest was not found: $pslrmModulePath"
}

$pslrmModulePath
