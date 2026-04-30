Set-StrictMode -Version Latest

$script:PSLRMBuildRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:PSLRMBuildRoot 'scripts\GitHubActions.Helper.ps1')

function Assert-CommandAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Name
    )

    if (-not (Get-Command -Name $Name -ErrorAction SilentlyContinue)) {
        throw "Required command not available: $Name"
    }
}

function Assert-CleanGitWorktree {
    [CmdletBinding()]
    param()

    $statusLines = (runx 'Failed to inspect git working tree status.' git status --porcelain=v1 --untracked-files=all).Output
    if ($statusLines.Count -gt 0) {
        throw "Git working tree must be clean before release. Remaining changes: $($statusLines -join '; ')"
    }
}

function Get-LocalGitTagState {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TagName
    )

    $tagRef = "refs/tags/$TagName"
    $tagOutput = (runx "Failed to inspect local tag '$TagName'." git for-each-ref '--format=%(objectname)' $tagRef).Output
    if ($tagOutput.Count -eq 0) {
        [pscustomobject]@{
            Exists = $false
            ObjectId = $null
        }
        return
    }

    $tagObjectId = [string] $tagOutput[-1]
    if ([string]::IsNullOrWhiteSpace($tagObjectId)) {
        throw "Failed to resolve local tag '$TagName'."
    }

    [pscustomobject]@{
        Exists = $true
        ObjectId = $tagObjectId.Trim()
    }
}

function Test-LocalGitTagAtHead {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TagName
    )

    (runx "Failed to inspect local tag '$TagName' at HEAD." git tag --points-at HEAD --list $TagName).Output.Count -gt 0
}

function Get-RemoteGitTagState {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TagName,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RemoteName = 'origin'
    )

    $tagRef = "refs/tags/$TagName"
    $remoteTagOutput = (runx "Failed to inspect remote tag '$TagName' on '$RemoteName'." git ls-remote --refs --tags $RemoteName $tagRef).Output
    $remoteTagLine = if ($remoteTagOutput.Count -eq 0) { $null } else { [string] $remoteTagOutput[-1] }
    if ([string]::IsNullOrWhiteSpace($remoteTagLine)) {
        [pscustomobject]@{
            Exists = $false
            ObjectId = $null
        }
        return
    }

    $parts = $remoteTagLine -split "`t", 2
    if (($parts.Count -ne 2) -or ($parts[1].Trim() -cne $tagRef)) {
        throw "Failed to inspect remote tag '$TagName' on '$RemoteName'."
    }

    $tagObjectId = $parts[0].Trim()
    if ([string]::IsNullOrWhiteSpace($tagObjectId)) {
        throw "Failed to resolve remote tag '$TagName' on '$RemoteName'."
    }

    [pscustomobject]@{
        Exists = $true
        ObjectId = $tagObjectId
    }
}

function Set-GitReleaseTag {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal build helper used non-interactively by the Release task.')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ReleaseTag,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $ReleaseNotes,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RemoteName = 'origin'
    )

    $localTag = Get-LocalGitTagState -TagName $ReleaseTag
    $hadLocalTag = $localTag.Exists

    $remoteTag = Get-RemoteGitTagState -TagName $ReleaseTag -RemoteName $RemoteName
    $hadRemoteTag = $remoteTag.Exists

    if ($hadLocalTag) {
        if (-not (Test-LocalGitTagAtHead -TagName $ReleaseTag)) {
            throw "Local tag '$ReleaseTag' already exists, but does not point at HEAD."
        }
    }
    else {
        if ($hadRemoteTag) {
            throw "Remote tag '$ReleaseTag' already exists on '$RemoteName', but the local tag is missing. Fetch it or create a matching local tag before retrying."
        }

        $null = runx "Failed to create signed tag '$ReleaseTag'." git tag --sign --cleanup=verbatim $ReleaseTag --message $ReleaseNotes
        $localTag = Get-LocalGitTagState -TagName $ReleaseTag
        if (-not $localTag.Exists) {
            throw "Signed tag '$ReleaseTag' was created, but could not be reloaded."
        }
    }

    if ($hadRemoteTag) {
        if ($remoteTag.ObjectId -cne $localTag.ObjectId) {
            throw "Remote tag '$ReleaseTag' on '$RemoteName' does not match the local signed tag."
        }
    }
    else {
        $null = runx "Failed to push release tag '$ReleaseTag' to remote '$RemoteName'." git push $RemoteName "refs/tags/$ReleaseTag"
    }

    [pscustomobject]@{
        TagCreated = -not $hadLocalTag
        TagPushed = -not $hadRemoteTag
    }
}

function Get-GitHubReleaseInfo {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ReleaseTag
    )

    $releaseViewResult = run gh release view $ReleaseTag --json 'url,isDraft,isPrerelease,tagName'
    if ($releaseViewResult.ExitCode -ne 0) {
        $errorText = (Get-NonEmptyStringLines -Lines $releaseViewResult.Output) -join "`n"
        if ($errorText -match 'release not found' -or $errorText -match '\b404\b') {
            return $null
        }

        if (-not [string]::IsNullOrWhiteSpace($errorText)) {
            throw "Failed to inspect GitHub release '$ReleaseTag'.`n$errorText"
        }

        throw "Failed to inspect GitHub release '$ReleaseTag'."
    }

    $json = $releaseViewResult.Output -join [System.Environment]::NewLine
    if ([string]::IsNullOrWhiteSpace($json)) {
        throw "GitHub release '$ReleaseTag' was found, but no metadata was returned."
    }

    try {
        $json | ConvertFrom-Json
    }
    catch {
        throw "Failed to parse GitHub release metadata for '$ReleaseTag'. $_"
    }
}

function Set-GitHubDraftRelease {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Internal build helper used non-interactively by the Release task.')]
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ReleaseTag,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ReleaseNotesPath,

        [Parameter()]
        [switch] $IsPrerelease
    )

    if (-not (Test-Path -LiteralPath $ReleaseNotesPath -PathType Leaf)) {
        throw "Release notes file not found: $ReleaseNotesPath"
    }

    $releaseInfo = Get-GitHubReleaseInfo -ReleaseTag $ReleaseTag
    if ($null -eq $releaseInfo) {
        $createArguments = @(
            'release', 'create', $ReleaseTag
            '--verify-tag', '--draft', '--title', $ReleaseTag
            '--notes-file', $ReleaseNotesPath
        )
        if ($IsPrerelease) {
            $createArguments += '--prerelease'
        }

        $null = runx "Failed to create draft GitHub release '$ReleaseTag'." gh @createArguments
        $releaseInfo = Get-GitHubReleaseInfo -ReleaseTag $ReleaseTag
        if ($null -eq $releaseInfo) {
            throw "Draft GitHub release '$ReleaseTag' was created, but could not be reloaded."
        }

        return $releaseInfo
    }

    if (-not $releaseInfo.isDraft) {
        throw "GitHub release '$ReleaseTag' is already published. Update it manually in the GitHub UI."
    }

    $editArguments = @(
        'release', 'edit', $ReleaseTag
        '--title', $ReleaseTag
        '--notes-file', $ReleaseNotesPath
    )
    if ([bool] $releaseInfo.isPrerelease -ne [bool] $IsPrerelease) {
        $editArguments += "--prerelease=$(([bool] $IsPrerelease).ToString().ToLowerInvariant())"
    }

    $null = runx "Failed to update draft GitHub release '$ReleaseTag'." gh @editArguments
    $updatedReleaseInfo = Get-GitHubReleaseInfo -ReleaseTag $ReleaseTag
    if ($null -eq $updatedReleaseInfo) {
        throw "Draft GitHub release '$ReleaseTag' was updated, but could not be reloaded."
    }

    $updatedReleaseInfo
}

function Invoke-TestTask {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '', Justification = 'Build helper intentionally emits visible test progress.')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TestPath,

        [Parameter()]
        [AllowNull()]
        [string] $CoverageOutputPath,

        [Parameter()]
        [string[]] $CoveragePaths,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $TestResultOutputPath,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $WorkingDirectory = $script:PSLRMBuildRoot
    )

    $config = New-PesterConfiguration
    $config.Run.Path = @($TestPath)
    $config.Run.PassThru = $true
    $config.Output.Verbosity = 'Detailed'
    if ($CoverageOutputPath) {
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.Path = @($CoveragePaths)
        $config.CodeCoverage.OutputFormat = 'JaCoCo'
        $config.CodeCoverage.OutputPath = $CoverageOutputPath
    }
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputFormat = 'NUnitXml'
    $config.TestResult.OutputPath = $TestResultOutputPath

    Push-Location $WorkingDirectory

    try {
        Write-Host "Invoking Pester tests at: $WorkingDirectory" -ForegroundColor Yellow
        $pesterResult = Invoke-Pester -Configuration $config

        if ($null -eq $pesterResult) {
            throw 'Invoke-Pester did not return a result object.'
        }

        if ($pesterResult.Result -ne 'Passed') {
            throw "Pester reported test failures. Result=$($pesterResult.Result); FailedCount=$($pesterResult.FailedCount)."
        }
    }
    finally {
        Pop-Location
    }
}
