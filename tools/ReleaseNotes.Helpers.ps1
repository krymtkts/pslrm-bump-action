Set-StrictMode -Version Latest

$script:PSLRMBuildRoot = Split-Path -Parent $PSScriptRoot

function Get-ChangelogSectionList {
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-ChangelogPath)
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Changelog not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $headerPattern = '(?m)^## \[(?<Name>[^\]]+)\](?<Suffix>(?: - .+)?)\r?$'
    $headerMatches = [System.Text.RegularExpressions.Regex]::Matches($content, $headerPattern)
    $sections = [System.Collections.Generic.List[object]]::new()

    for ($index = 0; $index -lt $headerMatches.Count; $index++) {
        $headerMatch = $headerMatches[$index]
        $bodyStartIndex = $headerMatch.Index + $headerMatch.Length
        $bodyEndIndex = $content.Length

        if ($index + 1 -lt $headerMatches.Count) {
            $bodyEndIndex = $headerMatches[$index + 1].Index
        }

        $rawBody = $content.Substring($bodyStartIndex, $bodyEndIndex - $bodyStartIndex).TrimStart("`r", "`n")
        $footerMatch = [System.Text.RegularExpressions.Regex]::Match($rawBody, '(?m)^---\s*\r?$')
        if ($footerMatch.Success) {
            $rawBody = $rawBody.Substring(0, $footerMatch.Index)
        }

        $sections.Add([pscustomobject]@{
                Version = $headerMatch.Groups['Name'].Value
                Heading = $headerMatch.Value.TrimEnd("`r", "`n")
                Body = $rawBody.TrimEnd("`r", "`n")
            })
    }

    $sections.ToArray()
}

function Get-ChangelogPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()

    Join-Path $script:PSLRMBuildRoot 'CHANGELOG.md'
}

function Get-ChangelogSection {
    [CmdletBinding()]
    [OutputType([object])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-ChangelogPath),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Version
    )

    $section = Get-ChangelogSectionList -Path $Path |
        Where-Object { $_.Version -eq $Version } |
        Select-Object -First 1

    if (-not $section) {
        throw "Changelog entry not found for version: $Version"
    }

    $section
}

function Get-ChangelogEntry {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-ChangelogPath),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Version
    )

    (Get-ChangelogSection -Path $Path -Version $Version).Body
}

function ConvertFrom-ReleaseTagToVersion {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $ReleaseTag
    )

    $normalizedTag = $ReleaseTag -replace '^refs/tags/', ''
    $match = [System.Text.RegularExpressions.Regex]::Match($normalizedTag, '^v(?<Version>.+)$')
    if (-not $match.Success) {
        throw "Release tag must use the form v<version>: $ReleaseTag"
    }

    $match.Groups['Version'].Value
}

function Assert-ReleaseInfo {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string] $Path = (Get-ChangelogPath),

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string] $Version,

        [Parameter()]
        [AllowNull()]
        [string] $ReleaseTag
    )

    # NOTE: assert changelog entry exists for the version, the content is not important for this assertion.
    Get-ChangelogSection -Path $Path -Version $Version | Out-Null

    if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
        return
    }

    $tagVersion = ConvertFrom-ReleaseTagToVersion -ReleaseTag $ReleaseTag
    if ($tagVersion -ne $Version) {
        throw "Release tag version does not match manifest version. Tag: $tagVersion, Manifest: $Version"
    }
}