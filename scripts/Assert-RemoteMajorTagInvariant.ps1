[CmdletBinding()]
param(
    [Parameter()]
    [string] $ReleaseTag,

    [Parameter()]
    [string] $MajorTag,

    [Parameter()]
    [string] $RemoteName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GitHubActions.Helper.ps1')

function Get-RemoteTagState {
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
        return [pscustomobject]@{
            Exists = $false
            ObjectId = $null
        }
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

function Assert-RemoteMajorTagInvariant {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ReleaseTag,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $MajorTag,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $RemoteName = 'origin'
    )

    $releaseTagMatch = [System.Text.RegularExpressions.Regex]::Match($ReleaseTag, '^v(?<Major>\d+)\.\d+\.\d+(?:-[A-Za-z0-9.-]+)?$')
    if (-not $releaseTagMatch.Success) {
        throw "Release tag must be vX.Y.Z or vX.Y.Z-prerelease: $ReleaseTag"
    }

    $expectedMajorTag = "v$($releaseTagMatch.Groups['Major'].Value)"
    if ($MajorTag -cne $expectedMajorTag) {
        throw "Expected mutable major tag '$expectedMajorTag' for release tag '$ReleaseTag', but got '$MajorTag'."
    }

    $releaseTagState = Get-RemoteTagState -TagName $ReleaseTag -RemoteName $RemoteName
    if (-not $releaseTagState.Exists) {
        throw "Remote exact release tag '$ReleaseTag' does not exist on '$RemoteName'."
    }

    $majorTagState = Get-RemoteTagState -TagName $MajorTag -RemoteName $RemoteName
    if (-not $majorTagState.Exists) {
        throw "Remote mutable major tag '$MajorTag' does not exist on '$RemoteName'."
    }

    if ($majorTagState.ObjectId -cne $releaseTagState.ObjectId) {
        throw "Remote mutable major tag '$MajorTag' does not match exact release tag '$ReleaseTag' on '$RemoteName'. Exact=$($releaseTagState.ObjectId) Major=$($majorTagState.ObjectId)"
    }

    [pscustomobject]@{
        ReleaseTag = $ReleaseTag
        MajorTag = $MajorTag
        RemoteName = $RemoteName
        ReleaseObjectId = $releaseTagState.ObjectId
        MajorObjectId = $majorTagState.ObjectId
    }
}

if ($MyInvocation.InvocationName -ne '.') {
    $invokeParams = @{
        ReleaseTag = if ($PSBoundParameters.ContainsKey('ReleaseTag')) {
            $ReleaseTag
        }
        else {
            Get-RequiredEnvironmentVariable -Name 'RELEASE_TAG' -Purpose 'identify the exact release tag to validate'
        }
        MajorTag = if ($PSBoundParameters.ContainsKey('MajorTag')) {
            $MajorTag
        }
        else {
            Get-RequiredEnvironmentVariable -Name 'MAJOR_TAG' -Purpose 'identify the mutable major tag to validate'
        }
        RemoteName = if ($PSBoundParameters.ContainsKey('RemoteName')) {
            $RemoteName
        }
        elseif ([string]::IsNullOrWhiteSpace($env:REMOTE_NAME)) {
            'origin'
        }
        else {
            $env:REMOTE_NAME
        }
    }

    $result = Assert-RemoteMajorTagInvariant @invokeParams
    Write-Output "Validated remote tag invariant: '$($result.MajorTag)' mirrors '$($result.ReleaseTag)' at '$($result.ReleaseObjectId)'."
}
