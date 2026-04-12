[CmdletBinding()]
param(
    [Parameter()]
    [string] $ProjectPath = '.',

    [Parameter()]
    [ValidateSet('core', 'desktop')]
    [string] $TargetPowerShellEdition = 'core'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RequirementsFileName = 'psreq.psd1'
$script:LockfileFileName = 'psreq.lock.psd1'

function Start-LogGroup {
    param(
        [Parameter(Mandatory)]
        [string] $Title
    )

    Write-Host "::group::${Title}"
}

function Stop-LogGroup {
    Write-Host '::endgroup::'
}

function Find-ProjectRoot {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    $cursor = $Path

    if (Test-Path -LiteralPath $cursor -PathType Leaf) {
        $cursor = Split-Path -Parent -Path $cursor
    }

    if (-not (Test-Path -LiteralPath $cursor -PathType Container)) {
        throw "Path not found or not a directory: $Path"
    }

    $cursor = (Resolve-Path -LiteralPath $cursor).Path

    while ($true) {
        $requirementsPath = Join-Path $cursor $script:RequirementsFileName
        if (Test-Path -LiteralPath $requirementsPath -PathType Leaf) {
            return $cursor
        }

        $parent = Split-Path -Parent -Path $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $cursor)) {
            break
        }

        $cursor = $parent
    }

    throw "Project root not found. Missing psreq.psd1 from: $Path"
}

function Get-FileContent {
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $Path).Path)
}

function Set-ActionOutput {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        Write-Host "Output $Name=$Value"
        return
    }

    "${Name}=${Value}" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}

$resolvedProjectPath = if ([System.IO.Path]::IsPathRooted($ProjectPath)) {
    [System.IO.Path]::GetFullPath($ProjectPath)
}
else {
    [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $ProjectPath))
}
$projectRoot = $null
$lockfileChanged = $false
$repositoryRoot = $null
$lockfilePath = $null

Start-LogGroup -Title 'Bootstrap'
try {
    Write-Host "Project path: '${resolvedProjectPath}' Target PowerShell edition: '${TargetPowerShellEdition}'"

    $projectRoot = Find-ProjectRoot -Path $resolvedProjectPath
    Write-Host "Project root: '${projectRoot}'"

    if (-not (Get-Command -Name 'Update-PSLResource' -ErrorAction SilentlyContinue)) {
        throw 'Update-PSLResource is not available. Ensure the action bootstrap imported pslrm before invoking the script.'
    }

    Write-Host 'Project validation completed.'
}
finally {
    Stop-LogGroup
}

Start-LogGroup -Title 'Update lockfile'
try {
    $lockfilePath = Join-Path $projectRoot $script:LockfileFileName
    $lockfileBefore = Get-FileContent -Path $lockfilePath

    Update-PSLResource -Path $projectRoot

    $lockfileAfter = Get-FileContent -Path $lockfilePath
    if ($null -eq $lockfileAfter) {
        throw "Lockfile was not created or updated: $lockfilePath"
    }

    $lockfileChanged = $lockfileBefore -cne $lockfileAfter

    # NOTE: The action is only allowed to modify the lockfile. Scope git status to the
    # target project so unexpected changes in the same checkout fail the run immediately.
    $repositoryRootResult = @(& git -C $projectRoot rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -ne 0 -or $repositoryRootResult.Count -eq 0) {
        throw 'Failed to resolve the git repository root. Ensure actions/checkout has run before invoking this action.'
    }

    $repositoryRoot = $repositoryRootResult[-1]

    $statusLines = @(& git -C $repositoryRoot status --porcelain --untracked-files=all -- $projectRoot 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to inspect git status under: $projectRoot"
    }

    $changedPaths = foreach ($line in $statusLines) {
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $pathText = $line.Substring(3).Trim()
        if ($pathText.StartsWith('"') -and $pathText.EndsWith('"')) {
            $pathText = $pathText.Trim('"')
        }

        $pathText
    }

    $unexpectedPaths = [string[]] @($changedPaths | Where-Object { $_ -notmatch '(^|[\\/])psreq\.lock\.psd1$' })
    if ($unexpectedPaths.Count -gt 0) {
        throw "Unexpected changes detected outside psreq.lock.psd1: $($unexpectedPaths -join ', ')"
    }

    Write-Host "Lockfile changed: $lockfileChanged"
}
finally {
    Stop-LogGroup
}

Start-LogGroup -Title 'Outputs'
try {
    $changedValue = if ($lockfileChanged) { 'true' } else { 'false' }

    Set-ActionOutput -Name 'changed' -Value $changedValue
    Set-ActionOutput -Name 'project_root' -Value $projectRoot
    Set-ActionOutput -Name 'repository_root' -Value $repositoryRoot
    Set-ActionOutput -Name 'lockfile_path' -Value $lockfilePath
}
finally {
    Stop-LogGroup
}