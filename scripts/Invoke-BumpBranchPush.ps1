Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GitHubActions.Logging.ps1')

function Get-RequiredEnvironmentVariable {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Purpose
    )

    $value = [System.Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$Name is required to $Purpose."
    }

    $value
}

function Invoke-GitResult {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [object[]] $Arguments
    )

    $output = @(& git @Arguments 2>&1)
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $FailureMessage,

        [Parameter(ValueFromRemainingArguments, Position = 1)]
        [object[]] $Arguments
    )

    $result = Invoke-GitResult @Arguments
    if ($result.ExitCode -eq 0) {
        return $result
    }

    $details = @(
        foreach ($line in @($result.Output)) {
            if (-not [string]::IsNullOrWhiteSpace([string] $line)) {
                [string] $line
            }
        }
    )

    if ($details.Count -gt 0) {
        throw "$FailureMessage`n$($details -join "`n")"
    }

    throw $FailureMessage
}

function Write-GitOutput {
    param(
        [AllowNull()]
        [object[]] $Lines
    )

    foreach ($line in @($Lines)) {
        if ($null -eq $line) {
            continue
        }

        $text = [string] $line
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        Write-Host $text
    }
}

function Get-RelativePath {
    param(
        [Parameter(Mandatory)]
        [string] $BasePath,

        [Parameter(Mandatory)]
        [string] $Path
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
    $pathFullPath = [System.IO.Path]::GetFullPath($Path)

    $baseUriText = $baseFullPath.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $baseUriText = $baseUriText + [System.IO.Path]::DirectorySeparatorChar

    $baseUri = [System.Uri]::new($baseUriText)
    $pathUri = [System.Uri]::new($pathFullPath)
    $relativeUri = $baseUri.MakeRelativeUri($pathUri)

    [System.Uri]::UnescapeDataString($relativeUri.ToString()).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

function Invoke-BumpBranchPush {
    param(
        [Parameter(Mandatory)]
        [string] $BumpBranchName,

        [Parameter(Mandatory)]
        [string] $BumpCommitMessage,

        [Parameter(Mandatory)]
        [string] $GitHubToken,

        [Parameter(Mandatory)]
        [string] $LockfilePath,

        [Parameter(Mandatory)]
        [string] $RepositoryRoot,

        [Parameter(Mandatory)]
        [string] $RepositoryFullName
    )

    $gitRelativeLockfilePath = Get-RelativePath -BasePath $RepositoryRoot -Path $LockfilePath
    if ($gitRelativeLockfilePath.StartsWith('..')) {
        throw "Lockfile path '$LockfilePath' is not under repository root '$RepositoryRoot'."
    }

    $gitRelativeLockfilePath = $gitRelativeLockfilePath.Replace('\', '/')

    $prepareState = Invoke-InLogGroup 'Prepare git context' {
        & git -C $RepositoryRoot config user.name 'github-actions[bot]'
        & git -C $RepositoryRoot config user.email '41898282+github-actions[bot]@users.noreply.github.com'

        # NOTE: Use an authenticated HTTPS remote so the push runs as the supplied token identity.
        # NOTE: A PAT can trigger follow-up workflows here; the default GITHUB_TOKEN usually cannot.
        & git -C $RepositoryRoot remote set-url origin "https://x-access-token:$GitHubToken@github.com/$RepositoryFullName.git"

        $localLockfileBlobResult = Invoke-Git "Failed to hash '$gitRelativeLockfilePath'." -C $RepositoryRoot hash-object -- $gitRelativeLockfilePath
        [pscustomobject]@{
            LocalLockfileBlob = [string] ($localLockfileBlobResult.Output | Select-Object -Last 1)
        }
    }

    $localLockfileBlob = $prepareState.LocalLockfileBlob

    $remoteInspectionState = Invoke-InLogGroup 'Inspect remote bump branch' {
        $remoteHeadResult = Invoke-Git "Failed to inspect remote branch '$BumpBranchName' before push." -C $RepositoryRoot ls-remote --heads origin "refs/heads/$BumpBranchName"

        $existingRemoteCommit = $null
        $reuseExistingBranch = $false
        $remoteHead = [string] ($remoteHeadResult.Output | Select-Object -Last 1)
        if (-not [string]::IsNullOrWhiteSpace($remoteHead)) {
            $existingRemoteCommit = ($remoteHead -split "`t", 2)[0]
            Write-Host "Remote branch '$BumpBranchName' exists at '$existingRemoteCommit'."

            $remoteTrackingRef = "refs/remotes/origin/$BumpBranchName"
            $null = Invoke-Git "Failed to fetch remote branch '$BumpBranchName' for comparison." -C $RepositoryRoot fetch --no-tags --depth=1 origin "refs/heads/${BumpBranchName}:$remoteTrackingRef"

            $remoteLockfileBlobResult = Invoke-GitResult -C $RepositoryRoot rev-parse "${remoteTrackingRef}:$gitRelativeLockfilePath"
            if (($remoteLockfileBlobResult.ExitCode -eq 0) -and ([string] ($remoteLockfileBlobResult.Output | Select-Object -Last 1) -ceq $localLockfileBlob)) {
                Write-Host "Remote branch '$BumpBranchName' already contains the desired lockfile update. Reusing it."
                Write-GitHubAnnotation -Label Notice -Message "Remote branch '$BumpBranchName' already contains the desired lockfile update. Skipping commit and push."
                $reuseExistingBranch = $true
            }
        }
        else {
            Write-Host "Remote branch '$BumpBranchName' does not exist yet."
        }

        [pscustomobject]@{
            ExistingRemoteCommit = $existingRemoteCommit
            ReuseExistingBranch = $reuseExistingBranch
        }
    }

    if ($remoteInspectionState.ReuseExistingBranch) {
        Write-Host 'Bump branch push skipped.'
        return
    }

    $existingRemoteCommit = $remoteInspectionState.ExistingRemoteCommit

    Invoke-InLogGroup 'Commit updated lockfile' {
        Write-Host "Preparing bump branch '$BumpBranchName'."
        $switchToLocalBranchResult = Invoke-Git "Failed to prepare bump branch '$BumpBranchName'." -C $RepositoryRoot switch --force-create $BumpBranchName
        Write-GitOutput -Lines $switchToLocalBranchResult.Output

        Write-Host "Staging updated lockfile '$gitRelativeLockfilePath'."
        & git -C $RepositoryRoot add -- $gitRelativeLockfilePath

        Write-Host "Creating bump commit '$BumpCommitMessage'."
        $commitResult = Invoke-Git "Failed to create bump commit '$BumpCommitMessage'." -C $RepositoryRoot commit --message $BumpCommitMessage
        Write-GitOutput -Lines $commitResult.Output
    }

    $leaseArgument = if ([string]::IsNullOrWhiteSpace($existingRemoteCommit)) {
        "--force-with-lease=refs/heads/${BumpBranchName}:"
    }
    else {
        "--force-with-lease=refs/heads/${BumpBranchName}:$existingRemoteCommit"
    }

    Invoke-InLogGroup 'Push bump branch' {
        Write-Host "Pushing bump branch '$BumpBranchName' to '$RepositoryFullName'."
        $pushResult = Invoke-GitResult -C $RepositoryRoot push $leaseArgument --set-upstream origin $BumpBranchName
        Write-GitOutput -Lines $pushResult.Output
        if ($pushResult.ExitCode -ne 0) {
            $pushErrorText = (@($pushResult.Output) -join "`n")
            if ($pushErrorText -match 'stale info') {
                $message = "Remote branch '$BumpBranchName' changed after inspection. Treating this as a real bump-branch conflict."
                Write-GitHubAnnotation -Label Error -Message $message
                throw $message
            }

            $details = @(
                foreach ($line in @($pushResult.Output)) {
                    if (-not [string]::IsNullOrWhiteSpace([string] $line)) {
                        [string] $line
                    }
                }
            )

            if ($details.Count -gt 0) {
                throw "Failed to push bump branch '$BumpBranchName'.`n$($details -join "`n")"
            }

            throw "Failed to push bump branch '$BumpBranchName'."
        }

        Write-Host 'Bump branch push completed.'
    }
}

$invokeParams = @{
    BumpBranchName = Get-RequiredEnvironmentVariable -Name 'BUMP_BRANCH_NAME' -Purpose 'identify the bump branch'
    BumpCommitMessage = Get-RequiredEnvironmentVariable -Name 'BUMP_COMMIT_MESSAGE' -Purpose 'create the bump commit'
    GitHubToken = Get-RequiredEnvironmentVariable -Name 'GH_TOKEN' -Purpose 'commit and push the updated lockfile'
    LockfilePath = Get-RequiredEnvironmentVariable -Name 'LOCKFILE_PATH' -Purpose 'stage the updated lockfile'
    RepositoryRoot = Get-RequiredEnvironmentVariable -Name 'REPOSITORY_ROOT' -Purpose 'run git commands in the repository'
    RepositoryFullName = Get-RequiredEnvironmentVariable -Name 'REPOSITORY_FULL_NAME' -Purpose 'push the bump branch to GitHub'
}

Invoke-BumpBranchPush @invokeParams