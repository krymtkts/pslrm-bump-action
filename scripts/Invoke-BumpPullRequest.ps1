Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'GitHubActions.Helper.ps1')

function Get-RepositoryLabelNames {
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryFullName
    )

    $labelListResult = runx 'Failed to query repository labels.' gh label list --repo $RepositoryFullName --limit 1000 --json name
    $labelListJson = $labelListResult.Output -join "`n"
    if (-not [string]::IsNullOrWhiteSpace($labelListJson)) {
        $labelList = ConvertFrom-Json -InputObject $labelListJson
        foreach ($label in $labelList) {
            [string] $label.name
        }
    }
}

function Initialize-BumpPullRequestLabels {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSReviewUnusedParameter', 'RepositoryFullName', Justification = 'Used in a nested script block passed to Invoke-InLogGroup.')]
    param(
        [Parameter(Mandatory)]
        [string] $RepositoryFullName
    )

    $labelDefinitions = @(
        [pscustomobject]@{
            Name = 'dependencies'
            Color = '0366d6'
            Description = 'Pull requests that update dependencies'
        }
        [pscustomobject]@{
            Name = 'pslrm'
            Color = '012456'
            Description = 'Pull requests created by pslrm-bump-action'
        }
    )

    try {
        Invoke-InLogGroup 'Ensure bump pull request labels' {
            $repositoryLabelNames = @(Get-RepositoryLabelNames -RepositoryFullName $RepositoryFullName)
            $failedLabelCreations = @(
                foreach ($label in $labelDefinitions) {
                    if ($repositoryLabelNames -notcontains $label.Name) {
                        Write-Host "Creating repository label '$($label.Name)'."
                        $result = run gh label create $label.Name --repo $RepositoryFullName --color $label.Color --description $label.Description
                        if ($result.ExitCode -eq 0) {
                            $repositoryLabelNames += $label.Name
                        }
                        else {
                            [pscustomobject]@{
                                Name = $label.Name
                                Result = $result
                            }
                        }
                    }
                }
            )

            if ($failedLabelCreations.Count -gt 0) {
                $repositoryLabelNames = @(Get-RepositoryLabelNames -RepositoryFullName $RepositoryFullName)
                foreach ($failure in $failedLabelCreations) {
                    if ($repositoryLabelNames -notcontains $failure.Name) {
                        Write-GitHubAnnotation -Label Warning -Message "Failed to create repository label '$($failure.Name)'. The pull request will continue without this label."
                        Write-GitOutput -Lines $failure.Result.Output
                    }
                }
            }

            foreach ($label in $labelDefinitions) {
                if ($repositoryLabelNames -contains $label.Name) {
                    $label.Name
                }
            }
        }
    }
    catch {
        Write-GitHubAnnotation -Label Warning -Message 'Failed to query repository labels. The pull request will continue without labels.'
        Write-GitOutput -Lines $_
    }
}

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

    $availableLabelNames = [string[]] @(Initialize-BumpPullRequestLabels -RepositoryFullName $RepositoryFullName)

    $existingPullRequestState = Invoke-InLogGroup 'Inspect existing bump pull request' {
        Write-Host "Looking for an open pull request from '$BumpBranchName' into '$BaseBranch'."
        $existingPullRequestListResult = runx 'Failed to query existing bump pull requests.' gh pr list --repo $RepositoryFullName --base $BaseBranch --head $BumpBranchName --state open --json number --jq '.[0].number'
        $existingPullRequestNumber = if ($existingPullRequestListResult.Output.Count -eq 0) { '' } else { [string] $existingPullRequestListResult.Output[-1] }

        if ([string]::IsNullOrWhiteSpace($existingPullRequestNumber)) {
            [pscustomobject]@{
                Body = ''
                Labels = [string[]] @()
                Number = ''
                Title = ''
            }

            return
        }

        $existingPullRequestViewResult = runx "Failed to inspect bump pull request #$existingPullRequestNumber." gh pr view $existingPullRequestNumber --repo $RepositoryFullName --json 'title,body,labels'
        $existingPullRequestJson = $existingPullRequestViewResult.Output -join "`n"
        if ([string]::IsNullOrWhiteSpace($existingPullRequestJson)) {
            throw "Failed to inspect bump pull request #$existingPullRequestNumber."
        }

        $existingPullRequest = $existingPullRequestJson | ConvertFrom-Json
        [pscustomobject]@{
            Body = [string] $existingPullRequest.body
            Labels = [string[]] @($existingPullRequest.labels.name)
            Number = [string] $existingPullRequestNumber
            Title = [string] $existingPullRequest.title
        }
    }

    $pullRequestAction = ''
    $pullRequestNumber = ''

    if ([string]::IsNullOrWhiteSpace($existingPullRequestState.Number)) {
        $pullRequestNumber = Invoke-InLogGroup 'Create bump pull request' {
            Write-Host "Creating a new bump pull request with title '$PullRequestTitle'."
            $createArguments = @('pr', 'create', '--repo', $RepositoryFullName, '--base', $BaseBranch, '--head', $BumpBranchName, '--title', $PullRequestTitle, '--body', $PullRequestBody)
            foreach ($labelName in $availableLabelNames) {
                $createArguments += @('--label', $labelName)
            }

            $null = runx 'Failed to create the bump pull request.' gh @createArguments

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
        $missingLabels = [string[]] @(
            foreach ($labelName in $availableLabelNames) {
                if ($existingPullRequestState.Labels -notcontains $labelName) {
                    $labelName
                }
            }
        )

        if (($existingPullRequestState.Title -ceq $PullRequestTitle) -and ($existingPullRequestState.Body -ceq $PullRequestBody) -and ($missingLabels.Count -eq 0)) {
            $pullRequestAction = 'noop'
            Write-Host "Bump pull request #$pullRequestNumber already matches the expected title, body, and labels."
        }
        else {
            Invoke-InLogGroup 'Update bump pull request' {
                Write-Host "Updating existing bump pull request #$pullRequestNumber."
                $editArguments = @('pr', 'edit', $pullRequestNumber, '--repo', $RepositoryFullName, '--title', $PullRequestTitle, '--body', $PullRequestBody)
                foreach ($labelName in $missingLabels) {
                    $editArguments += @('--add-label', $labelName)
                }

                $null = runx "Failed to update bump pull request #$pullRequestNumber." gh @editArguments

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
