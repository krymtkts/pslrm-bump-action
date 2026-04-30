Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GitHubActions.Helper.ps1')

function Invoke-BumpPullRequest {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'BaseBranch', Justification = 'Used in nested script blocks passed to Invoke-InLogGroup.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'BumpBranchName', Justification = 'Used in nested script blocks passed to Invoke-InLogGroup.')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RepositoryFullName', Justification = 'Used in nested script blocks passed to Invoke-InLogGroup.')]
    param(
        [Parameter(Mandatory)]
        [string] $BaseBranch,

        [Parameter(Mandatory)]
        [string] $BumpBranchName,

        [Parameter(Mandatory)]
        [string] $PullRequestBody,

        [Parameter(Mandatory)]
        [string] $PullRequestTitle,

        [Parameter(Mandatory)]
        [string] $RepositoryFullName
    )

    $existingPullRequestState = Invoke-InLogGroup 'Inspect existing bump pull request' {
        Write-Host "Looking for an open pull request from '$BumpBranchName' into '$BaseBranch'."
        $existingPullRequestListResult = runx 'Failed to query existing bump pull requests.' gh pr list --repo $RepositoryFullName --base $BaseBranch --head $BumpBranchName --state open --json number --jq '.[0].number'
        $existingPullRequestNumber = if ($existingPullRequestListResult.Output.Count -eq 0) { '' } else { [string] $existingPullRequestListResult.Output[-1] }

        if ([string]::IsNullOrWhiteSpace($existingPullRequestNumber)) {
            [pscustomobject]@{
                Body = ''
                Number = ''
                Title = ''
            }

            return
        }

        $existingPullRequestViewResult = runx "Failed to inspect bump pull request #$existingPullRequestNumber." gh pr view $existingPullRequestNumber --repo $RepositoryFullName --json 'title,body'
        $existingPullRequestJson = $existingPullRequestViewResult.Output -join [System.Environment]::NewLine
        if ([string]::IsNullOrWhiteSpace($existingPullRequestJson)) {
            throw "Failed to inspect bump pull request #$existingPullRequestNumber."
        }

        $existingPullRequest = $existingPullRequestJson | ConvertFrom-Json
        [pscustomobject]@{
            Body = [string] $existingPullRequest.body
            Number = [string] $existingPullRequestNumber
            Title = [string] $existingPullRequest.title
        }
    }

    $pullRequestAction = ''
    $pullRequestNumber = ''

    if ([string]::IsNullOrWhiteSpace($existingPullRequestState.Number)) {
        $pullRequestNumber = Invoke-InLogGroup 'Create bump pull request' {
            Write-Host "Creating a new bump pull request with title '$PullRequestTitle'."
            $null = runx 'Failed to create the bump pull request.' gh pr create --repo $RepositoryFullName --base $BaseBranch --head $BumpBranchName --title $PullRequestTitle --body $PullRequestBody

            $createdPullRequestListResult = runx 'Failed to resolve the created bump pull request number.' gh pr list --repo $RepositoryFullName --base $BaseBranch --head $BumpBranchName --state open --json number --jq '.[0].number'
            $createdPullRequestNumber = if ($createdPullRequestListResult.Output.Count -eq 0) { '' } else { [string] $createdPullRequestListResult.Output[-1] }
            if ([string]::IsNullOrWhiteSpace($createdPullRequestNumber)) {
                throw 'Failed to resolve the created bump pull request number.'
            }

            Write-Host "Bump pull request #$createdPullRequestNumber created."
            [string] $createdPullRequestNumber
        }

        $pullRequestAction = 'created'
    }
    else {
        $pullRequestNumber = $existingPullRequestState.Number
        if (($existingPullRequestState.Title -ceq $PullRequestTitle) -and ($existingPullRequestState.Body -ceq $PullRequestBody)) {
            $pullRequestAction = 'noop'
            Write-Host "Bump pull request #$pullRequestNumber already matches the expected title and body."
        }
        else {
            Invoke-InLogGroup 'Update bump pull request' {
                Write-Host "Updating existing bump pull request #$pullRequestNumber."
                $null = runx "Failed to update bump pull request #$pullRequestNumber." gh pr edit $pullRequestNumber --repo $RepositoryFullName --title $PullRequestTitle --body $PullRequestBody

                Write-Host "Bump pull request #$pullRequestNumber updated."
            }

            $pullRequestAction = 'updated'
        }
    }

    Set-ActionOutput -Name 'pull_request_action' -Value $pullRequestAction
    Set-ActionOutput -Name 'pull_request_number' -Value $pullRequestNumber
}

$null = Get-RequiredEnvironmentVariable -Name 'GH_TOKEN' -Purpose 'authenticate GitHub CLI pull request operations'

$invokeParams = @{
    BaseBranch = Get-RequiredEnvironmentVariable -Name 'BASE_BRANCH' -Purpose 'identify the pull request base branch'
    BumpBranchName = Get-RequiredEnvironmentVariable -Name 'BUMP_BRANCH_NAME' -Purpose 'identify the bump pull request head branch'
    PullRequestBody = Get-RequiredEnvironmentVariable -Name 'PR_BODY' -Purpose 'populate the bump pull request body'
    PullRequestTitle = Get-RequiredEnvironmentVariable -Name 'PR_TITLE' -Purpose 'populate the bump pull request title'
    RepositoryFullName = Get-RequiredEnvironmentVariable -Name 'REPOSITORY_FULL_NAME' -Purpose 'query bump pull requests'
}

Invoke-BumpPullRequest @invokeParams
