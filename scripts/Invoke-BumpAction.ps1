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

function Set-ActionOutput {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        Write-Host "Output $Name=$Value"
        return
    }

    "$Name=$Value" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
}

$resolvedProjectPath = [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $ProjectPath))

Start-LogGroup -Title 'Bootstrap'
try {
    Write-Host "Project path: '${resolvedProjectPath}' Target PowerShell edition: '${TargetPowerShellEdition}'"

    if ([string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        throw @'GH_TOKEN is required. Provide github-token so the action can push changes and create or update a CI-ready pull request.'
    }

    Write-Host 'GitHub token: available'
}
finally {
    Stop-LogGroup
}

Start-LogGroup -Title 'Outputs'
try {
    Set-ActionOutput -Name 'changed' -Value 'false'
    Write-Host 'Skeleton action completed. Lockfile update logic is not implemented yet.'
}
finally {
    Stop-LogGroup
}