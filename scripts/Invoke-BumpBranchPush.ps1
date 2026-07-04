Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GitHubActions.Helper.ps1')

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

function Invoke-GitHubApiCommand {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $GitHubToken,

        [Parameter()]
        [AllowNull()]
        [string] $BodyFilePath
    )

    $originalGitHubToken = $env:GH_TOKEN
    try {
        $env:GH_TOKEN = $GitHubToken
        $params = '--method', $Method, '-H', 'Accept: application/vnd.github+json', '-H', 'X-GitHub-Api-Version: 2022-11-28', $Path
        if (-not [string]::IsNullOrWhiteSpace($BodyFilePath)) {
            $params += '--input', $BodyFilePath
        }
        run gh api @params
    }
    finally {
        if ($null -eq $originalGitHubToken) {
            Remove-Item Env:\GH_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GH_TOKEN = $originalGitHubToken
        }
    }
}

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH')]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [string] $GitHubToken,

        [Parameter()]
        [AllowNull()]
        [object] $Body
    )

    $bodyFilePath = $null
    if ($null -ne $Body) {
        $bodyFilePath = [System.IO.Path]::GetTempFileName()
        $json = $Body | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText($bodyFilePath, $json, [System.Text.UTF8Encoding]::new($false))
    }

    Write-Host "GitHub API: $Method $Path"
    try {
        $result = Invoke-GitHubApiCommand -Method $Method -Path $Path -GitHubToken $GitHubToken -BodyFilePath $bodyFilePath
    }
    finally {
        if ($null -ne $bodyFilePath) {
            Remove-Item -LiteralPath $bodyFilePath -ErrorAction SilentlyContinue
        }
    }

    $output = @(Get-NonEmptyStringLines -Lines @($result.Output))
    if ($result.ExitCode -ne 0) {
        $message = $output -join "`n"
        if ($message -match 'Resource not accessible by integration|HTTP 403|status.?code.?403|\"status\":\s*\"403\"') {
            throw "GitHub API request failed because the token cannot write repository contents. Grant 'contents: write' to GITHUB_TOKEN, or pass a PAT/GitHub App token with Contents write permission. Request: $Method $Path`n$message"
        }

        if ($output.Count -gt 0) {
            throw "GitHub API request failed. Request: $Method $Path`n$message"
        }

        throw "GitHub API request failed. Request: $Method $Path"
    }

    if ($output.Count -eq 0) {
        return $null
    }

    $json = $output -join "`n"
    try {
        $json | ConvertFrom-Json
    }
    catch {
        throw "GitHub API request returned invalid JSON. Request: $Method $Path`n$json"
    }
}

function Split-GitHubRepositoryFullName {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryFullName
    )

    $parts = $RepositoryFullName -split '/', 2
    if (($parts.Count -ne 2) -or [string]::IsNullOrWhiteSpace($parts[0]) -or [string]::IsNullOrWhiteSpace($parts[1])) {
        throw "Repository full name must be '<owner>/<repo>': $RepositoryFullName"
    }

    [pscustomobject]@{
        Owner = $parts[0]
        Repo = $parts[1]
    }
}

function New-GitHubSignedCommitForLockfile {
    param(
        [Parameter(Mandatory)]
        [string] $BumpBranchName,

        [Parameter(Mandatory)]
        [string] $BumpCommitMessage,

        [Parameter(Mandatory)]
        [string] $GitHubToken,

        [Parameter(Mandatory)]
        [string] $GitRelativeLockfilePath,

        [Parameter(Mandatory)]
        [string] $LockfilePath,

        [Parameter(Mandatory)]
        [string] $ParentCommitSha,

        [Parameter(Mandatory)]
        [string] $RepositoryFullName
    )

    $repository = Split-GitHubRepositoryFullName -RepositoryFullName $RepositoryFullName
    $repositoryPath = "/repos/$($repository.Owner)/$($repository.Repo)"
    $encodedParentCommitSha = [System.Uri]::EscapeDataString($ParentCommitSha)

    $parentCommit = Invoke-GitHubApi -Method GET -Path "$repositoryPath/git/commits/$encodedParentCommitSha" -GitHubToken $GitHubToken
    $baseTreeSha = [string] $parentCommit.tree.sha
    if ([string]::IsNullOrWhiteSpace($baseTreeSha)) {
        throw "Failed to resolve the base tree for parent commit '$ParentCommitSha'."
    }

    $lockfileContent = Get-Content -LiteralPath $LockfilePath -Raw
    $tree = Invoke-GitHubApi -Method POST -Path "$repositoryPath/git/trees" -GitHubToken $GitHubToken -Body @{
        base_tree = $baseTreeSha
        tree = @(
            @{
                path = $GitRelativeLockfilePath
                mode = '100644'
                type = 'blob'
                content = $lockfileContent
            }
        )
    }

    $treeSha = [string] $tree.sha
    if ([string]::IsNullOrWhiteSpace($treeSha)) {
        throw "Failed to create a tree for bump branch '$BumpBranchName'."
    }

    # Omit author and committer so GitHub can create a verified commit for the token identity.
    $commit = Invoke-GitHubApi -Method POST -Path "$repositoryPath/git/commits" -GitHubToken $GitHubToken -Body @{
        message = $BumpCommitMessage
        tree = $treeSha
        parents = @($ParentCommitSha)
    }

    $commitSha = [string] $commit.sha
    if ([string]::IsNullOrWhiteSpace($commitSha)) {
        throw "Failed to create bump commit '$BumpCommitMessage'."
    }

    $verification = $commit.verification
    if (($null -ne $verification) -and (-not [bool] $verification.verified)) {
        $reason = [string] $verification.reason
        if (-not [string]::IsNullOrWhiteSpace($reason)) {
            throw "Created bump commit '$commitSha', but GitHub did not verify it. Verification reason: $reason"
        }

        throw "Created bump commit '$commitSha', but GitHub did not verify it."
    }

    $commitSha
}

function Set-GitHubBumpBranchRef {
    param(
        [Parameter(Mandatory)]
        [string] $BumpBranchName,

        [Parameter()]
        [AllowNull()]
        [string] $ExistingRemoteCommit,

        [Parameter(Mandatory)]
        [string] $GitHubToken,

        [Parameter(Mandatory)]
        [string] $NewCommitSha,

        [Parameter(Mandatory)]
        [string] $RepositoryFullName
    )

    $repository = Split-GitHubRepositoryFullName -RepositoryFullName $RepositoryFullName
    $repositoryPath = "/repos/$($repository.Owner)/$($repository.Repo)"
    $refName = "refs/heads/$BumpBranchName"

    if ([string]::IsNullOrWhiteSpace($ExistingRemoteCommit)) {
        Invoke-GitHubApi -Method POST -Path "$repositoryPath/git/refs" -GitHubToken $GitHubToken -Body @{
            ref = $refName
            sha = $NewCommitSha
        } | Out-Null

        return
    }

    $encodedRef = [System.Uri]::EscapeDataString("heads/$BumpBranchName")
    Invoke-GitHubApi -Method PATCH -Path "$repositoryPath/git/refs/$encodedRef" -GitHubToken $GitHubToken -Body @{
        sha = $NewCommitSha
        force = $false
    } | Out-Null
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
        # NOTE: A PAT can trigger subsequent workflows here; the default GITHUB_TOKEN usually cannot.
        & git -C $RepositoryRoot remote set-url origin "https://x-access-token:$GitHubToken@github.com/$RepositoryFullName.git"

        $localLockfileBlobResult = runx "Failed to hash '$gitRelativeLockfilePath'." git -C $RepositoryRoot hash-object -- $gitRelativeLockfilePath
        $localHeadResult = runx 'Failed to resolve the local HEAD commit.' git -C $RepositoryRoot rev-parse HEAD
        [pscustomobject]@{
            LocalLockfileBlob = [string] ($localLockfileBlobResult.Output | Select-Object -Last 1)
            LocalHeadCommit = [string] ($localHeadResult.Output | Select-Object -Last 1)
        }
    }

    $localLockfileBlob = $prepareState.LocalLockfileBlob
    $localHeadCommit = $prepareState.LocalHeadCommit

    $remoteInspectionState = Invoke-InLogGroup 'Inspect remote bump branch' {
        $remoteHeadResult = runx "Failed to inspect remote branch '$BumpBranchName' before push." git -C $RepositoryRoot ls-remote --heads origin "refs/heads/$BumpBranchName"

        $existingRemoteCommit = $null
        $reuseExistingBranch = $false
        $remoteHead = [string] ($remoteHeadResult.Output | Select-Object -Last 1)
        if ([string]::IsNullOrWhiteSpace($remoteHead)) {
            Write-Host "Remote branch '$BumpBranchName' does not exist yet."
        }
        else {
            $existingRemoteCommit = ($remoteHead -split "`t", 2)[0]
            Write-Host "Remote branch '$BumpBranchName' exists at '$existingRemoteCommit'."

            $remoteTrackingRef = "refs/remotes/origin/$BumpBranchName"
            $null = runx "Failed to fetch remote branch '$BumpBranchName' for comparison." git -C $RepositoryRoot fetch --no-tags --depth=1 origin "refs/heads/${BumpBranchName}:$remoteTrackingRef"

            $remoteLockfileBlobResult = run git -C $RepositoryRoot rev-parse "${remoteTrackingRef}:$gitRelativeLockfilePath"
            if (($remoteLockfileBlobResult.ExitCode -eq 0) -and ([string] ($remoteLockfileBlobResult.Output | Select-Object -Last 1) -ceq $localLockfileBlob)) {
                Write-Host "Remote branch '$BumpBranchName' already contains the desired lockfile update. Reusing it."
                Write-GitHubAnnotation -Label Notice -Message "Remote branch '$BumpBranchName' already contains the desired lockfile update. Skipping commit and push."
                $reuseExistingBranch = $true
            }
        }

        [pscustomobject]@{
            ExistingRemoteCommit = $existingRemoteCommit
            ReuseExistingBranch = $reuseExistingBranch
        }
    }

    if ($remoteInspectionState.ReuseExistingBranch) {
        Set-ActionOutput -Name 'branch_action' -Value 'noop'
        Write-Host 'Bump branch push skipped.'
        return
    }

    $existingRemoteCommit = $remoteInspectionState.ExistingRemoteCommit
    $branchAction = if ([string]::IsNullOrWhiteSpace($existingRemoteCommit)) {
        'created'
    }
    else {
        'updated'
    }

    $parentCommitSha = if ([string]::IsNullOrWhiteSpace($existingRemoteCommit)) {
        $localHeadCommit
    }
    else {
        $existingRemoteCommit
    }

    $newCommitSha = Invoke-InLogGroup 'Create signed bump commit' {
        Write-Host "Creating bump commit '$BumpCommitMessage' on GitHub."
        $commitSha = New-GitHubSignedCommitForLockfile -BumpBranchName $BumpBranchName -BumpCommitMessage $BumpCommitMessage -GitHubToken $GitHubToken -GitRelativeLockfilePath $gitRelativeLockfilePath -LockfilePath $LockfilePath -ParentCommitSha $parentCommitSha -RepositoryFullName $RepositoryFullName
        Write-Host "Created bump commit '$commitSha'."
        $commitSha
    }

    Invoke-InLogGroup 'Update bump branch' {
        Write-Host "Updating bump branch '$BumpBranchName' on '$RepositoryFullName'."
        try {
            Set-GitHubBumpBranchRef -BumpBranchName $BumpBranchName -ExistingRemoteCommit $existingRemoteCommit -GitHubToken $GitHubToken -NewCommitSha $newCommitSha -RepositoryFullName $RepositoryFullName
        }
        catch {
            $message = "Failed to update bump branch '$BumpBranchName'. The branch may have changed after inspection."
            Write-GitHubAnnotation -Label Error -Message $message
            throw "$message`n$($_.Exception.Message)"
        }

        Set-ActionOutput -Name 'branch_action' -Value $branchAction
        Write-Host 'Bump branch update completed.'
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
