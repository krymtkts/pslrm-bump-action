<#
.Synopsis
    Invoke-Build tasks
#>

# Build script parameters
[CmdletBinding(DefaultParameterSetName = 'Default')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = 'Variables are used in script blocks and argument completers')]
param(
    [Parameter(Position = 0, ParameterSetName = 'Default')]
    [ValidateSet('Init', 'Clean', 'Lint', 'UnitTest', 'TestAll', 'ReleaseNotes', 'ValidateReleaseMetadata', 'Release')]
    [string[]] $Tasks = @('UnitTest'),

    [Parameter()]
    [switch] $DisableCoverage,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string] $ReleaseTag
)

# If invoked directly (not dot-sourced by Invoke-Build), hand off execution to Invoke-Build through pslrm.
if ($MyInvocation.InvocationName -ne '.') {
    if (-not (Get-Command -Name 'Invoke-PSLResource' -ErrorAction SilentlyContinue)) {
        throw 'Invoke-PSLResource is required to run .build.ps1 directly. Import pslrm first, or invoke this file through Invoke-Build.'
    }

    $invokeBuildArguments = @(
        $Tasks
        $PSCommandPath
    )
    if ($DisableCoverage) {
        $invokeBuildArguments += '-DisableCoverage'
    }
    if ($PSBoundParameters.ContainsKey('ReleaseTag')) {
        $invokeBuildArguments += '-ReleaseTag'
        $invokeBuildArguments += $ReleaseTag
    }

    try {
        Invoke-PSLResource -Path $PSScriptRoot -CommandName 'Invoke-Build' -ArgumentTokens $invokeBuildArguments
        exit 0
    }
    catch {
        Write-Error $_
        exit 1
    }
}

# Required PowerShell version check.
if ($PSVersionTable.PSVersion -lt [Version]'5.1') {
    throw "This build requires PowerShell 5.1+. Current: $($PSVersionTable.PSVersion)."
}

# --- Setup ---

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'tools\Build.Helpers.ps1')
. (Join-Path $PSScriptRoot 'tools\ReleaseNotes.Helpers.ps1')

$ActionMetadataPath = Join-Path $PSScriptRoot 'action.yml'
$ReadmePath = Join-Path $PSScriptRoot 'README.md'
$ChangelogPath = Get-ChangelogPath
$ScriptsPath = Join-Path $PSScriptRoot 'scripts'
$TestsPath = Join-Path $PSScriptRoot 'tests'
$ToolsPath = Join-Path $PSScriptRoot 'tools'
$ArtifactsPath = Join-Path $PSScriptRoot '.artifacts'
$ReleaseNotesPath = Join-Path $ArtifactsPath 'release-notes.md'
$LintPaths = @(
    (Join-Path $PSScriptRoot '.build.ps1')
    $ScriptsPath
    $TestsPath
    $ToolsPath
) | Where-Object { Test-Path -LiteralPath $_ }
$CoveragePaths = @(
    (Join-Path $ScriptsPath '*.ps1')
) | Where-Object { Test-Path -LiteralPath (Split-Path -Parent $_) }

# --- Tasks (Invoke-Build) ---

Task Init {
    Write-Host "Parameters: $($PSBoundParameters | ConvertTo-Json -Compress)" -ForegroundColor Green

    Assert-CommandAvailable -Name 'Invoke-Build'
    Assert-CommandAvailable -Name 'Invoke-ScriptAnalyzer'
    Assert-CommandAvailable -Name 'Invoke-Pester'

    foreach ($path in @($ActionMetadataPath, $ReadmePath, $ChangelogPath, $ScriptsPath, $TestsPath)) {
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Required build input not found: $path"
        }
    }

    New-Item -ItemType Directory -Path $ArtifactsPath -Force | Out-Null
}

Task Clean Init, {
    Write-Host 'Cleaning build artifacts.' -ForegroundColor Yellow

    if (Test-Path -LiteralPath $ArtifactsPath -PathType Container) {
        Remove-Item -LiteralPath $ArtifactsPath -Recurse -Force
    }

    @('testResults*.xml', 'coverage*.xml') | ForEach-Object {
        Get-ChildItem -LiteralPath $PSScriptRoot -Filter $_ -File -ErrorAction SilentlyContinue
    } | Remove-Item -Force
}

Task Lint Init, {
    Write-Host 'Running PSScriptAnalyzer.' -ForegroundColor Yellow

    $issues = @(
        $LintPaths | Invoke-ScriptAnalyzer -Recurse
    )
    if ($issues.Count -gt 0) {
        $issues
        throw 'Invoke-ScriptAnalyzer reported issues.'
    }
}

Task UnitTest Init, {
    Write-Host 'Running unit tests.' -ForegroundColor Yellow

    $Params = @{
        TestPath = 'tests/unit'
        TestResultOutputPath = 'testResults.xml'
    }
    if (-not $DisableCoverage) {
        $Params.CoverageOutputPath = 'coverage.xml'
        $Params.CoveragePaths = $CoveragePaths
    }
    Invoke-TestTask @Params
}

Task TestAll Lint, UnitTest

Task ValidateReleaseMetadata Init, {
    Write-Host 'Validating release metadata.' -ForegroundColor Yellow

    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        throw '-ReleaseTag is required.'
    }
    $version = ConvertFrom-ReleaseTagToVersion -ReleaseTag $ReleaseTag
    Assert-ReleaseInfo -Version $version -ReleaseTag $ReleaseTag
}

Task ReleaseNotes ValidateReleaseMetadata, {
    Write-Host 'Generating GitHub Release notes from CHANGELOG.md.' -ForegroundColor Yellow

    $version = ConvertFrom-ReleaseTagToVersion -ReleaseTag $ReleaseTag
    $releaseNotes = Get-ChangelogEntry -Version $version
    $outputDirectory = Split-Path -Parent $ReleaseNotesPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    Set-Content -LiteralPath $ReleaseNotesPath -Value $releaseNotes -NoNewline
    Write-Host "Release notes written to: $ReleaseNotesPath" -ForegroundColor Green
}

Task Release ReleaseNotes, {
    Write-Host 'Creating or updating draft GitHub Release.' -ForegroundColor Yellow

    if (-not (Test-Path -LiteralPath $ReleaseNotesPath -PathType Leaf)) {
        throw "Release notes file not found: $ReleaseNotesPath"
    }

    Assert-CleanGitWorktree

    $releaseNotes = Get-Content -LiteralPath $ReleaseNotesPath -Raw
    $tagResult = Set-GitReleaseTag -ReleaseTag $ReleaseTag -ReleaseNotes $releaseNotes
    if ($tagResult.TagCreated) {
        Write-Host "Created local release tag '$ReleaseTag'." -ForegroundColor Green
    }
    if ($tagResult.TagPushed) {
        Write-Host "Pushed release tag '$ReleaseTag' to origin." -ForegroundColor Green
    }
    else {
        Write-Host "Release tag '$ReleaseTag' already exists on origin." -ForegroundColor Green
    }

    $draftRelease = Set-GitHubDraftRelease -ReleaseTag $ReleaseTag -ReleaseNotesPath $ReleaseNotesPath -IsPrerelease:$ReleaseTag.Contains('-')
    Write-Host "Draft GitHub release ready: $($draftRelease.url)" -ForegroundColor Green
}

Task . UnitTest
