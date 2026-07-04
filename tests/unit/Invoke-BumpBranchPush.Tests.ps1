BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-BumpBranchPush.ps1'
}

Describe 'Invoke-BumpBranchPush' {
    BeforeEach {
        $script:originalBumpBranchName = $env:BUMP_BRANCH_NAME
        $script:originalBumpCommitMessage = $env:BUMP_COMMIT_MESSAGE
        $script:originalGithubOutput = $env:GITHUB_OUTPUT
        $script:originalGitHubToken = $env:GH_TOKEN
        $script:originalLockfilePath = $env:LOCKFILE_PATH
        $script:originalRepositoryRoot = $env:REPOSITORY_ROOT
        $script:originalRepositoryFullName = $env:REPOSITORY_FULL_NAME

        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

        $script:lockfilePath = Join-Path $projectRoot 'psreq.lock.psd1'
        Set-Content -LiteralPath $script:lockfilePath -Value "@{}`n" -NoNewline

        $env:BUMP_BRANCH_NAME = 'pslrm-bump/pocof'
        $env:BUMP_COMMIT_MESSAGE = 'Bump pocof to 0.23.0'
        $env:GH_TOKEN = 'token'
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'github-output.txt'
        $env:LOCKFILE_PATH = $script:lockfilePath
        $env:REPOSITORY_ROOT = $TestDrive
        $env:REPOSITORY_FULL_NAME = 'krymtkts/pslrm-actions-sandbox'

        $global:GitCommands = [System.Collections.Generic.List[string[]]]::new()
        $global:GitHubApiCalls = [System.Collections.Generic.List[object]]::new()
        $global:LocalHeadCommit = 'basecommit'
        $global:LocalLockfileBlobId = 'local-lockfile-blob'
        $global:CreatedCommitSha = 'signedcommit'
        $global:CreatedCommitVerified = $true
        $global:CreatedCommitVerificationReason = 'valid'
        $global:RemoteHeadLine = $null
        $global:RemoteLockfileBlobId = $null
        $global:FailRefUpdate = $false

        function global:git {
            param(
                [Parameter(ValueFromRemainingArguments)]
                [object[]] $Arguments
            )

            $recordedArguments = [string[]] @(
                foreach ($argument in $Arguments) {
                    [string] $argument
                }
            )
            $global:GitCommands.Add($recordedArguments)
            $global:LASTEXITCODE = 0

            if ($Arguments -contains 'hash-object') {
                $global:LocalLockfileBlobId
                return
            }

            if ($Arguments -contains 'ls-remote') {
                if ($null -ne $global:RemoteHeadLine) {
                    $global:RemoteHeadLine
                }

                return
            }

            if ($Arguments -contains 'fetch') {
                return
            }

            if ($Arguments -contains 'rev-parse') {
                if ($Arguments[-1] -ceq 'HEAD') {
                    $global:LocalHeadCommit
                    return
                }

                if ($null -eq $global:RemoteLockfileBlobId) {
                    $global:LASTEXITCODE = 1
                    return
                }

                $global:RemoteLockfileBlobId
                return
            }

        }

        function global:Invoke-RestMethod {
            param(
                [Parameter(Mandatory)]
                [string] $Method,

                [Parameter(Mandatory)]
                [string] $Uri,

                [Parameter()]
                [hashtable] $Headers,

                [Parameter()]
                [string] $ContentType,

                [Parameter()]
                [string] $Body
            )

            $bodyObject = if ([string]::IsNullOrWhiteSpace($Body)) {
                $null
            }
            else {
                $Body | ConvertFrom-Json
            }

            $global:GitHubApiCalls.Add([pscustomobject]@{
                    Method = $Method
                    Uri = $Uri
                    Body = $bodyObject
                })

            if (($Method -ceq 'GET') -and ($Uri -match '/git/commits/')) {
                return [pscustomobject]@{
                    tree = [pscustomobject]@{ sha = 'basetree' }
                }
            }

            if (($Method -ceq 'POST') -and ($Uri -match '/git/trees$')) {
                return [pscustomobject]@{
                    sha = 'newtree'
                }
            }

            if (($Method -ceq 'POST') -and ($Uri -match '/git/commits$')) {
                return [pscustomobject]@{
                    sha = $global:CreatedCommitSha
                    verification = [pscustomobject]@{
                        verified = $global:CreatedCommitVerified
                        reason = $global:CreatedCommitVerificationReason
                    }
                }
            }

            if (($Method -ceq 'POST') -and ($Uri -match '/git/refs$')) {
                return [pscustomobject]@{
                    ref = 'refs/heads/pslrm-bump/pocof'
                    object = [pscustomobject]@{ sha = $global:CreatedCommitSha }
                }
            }

            if (($Method -ceq 'PATCH') -and ($Uri -match '/git/refs/')) {
                if ($global:FailRefUpdate) {
                    throw 'Reference update failed.'
                }

                return [pscustomobject]@{
                    ref = 'refs/heads/pslrm-bump/pocof'
                    object = [pscustomobject]@{ sha = $global:CreatedCommitSha }
                }
            }

            throw "Unexpected GitHub API call: $Method $Uri"
        }

        function Get-RecordedGitCommands {
            @(
                foreach ($commandArguments in $global:GitCommands) {
                    $commandArguments -join ' '
                }
            )
        }

        function Get-RecordedGitHubApiCalls {
            @(
                foreach ($apiCall in $global:GitHubApiCalls) {
                    $apiCall
                }
            )
        }

    }

    AfterEach {
        foreach ($environment in @(
                @{ Name = 'BUMP_BRANCH_NAME'; Value = $script:originalBumpBranchName },
                @{ Name = 'BUMP_COMMIT_MESSAGE'; Value = $script:originalBumpCommitMessage },
                @{ Name = 'GITHUB_OUTPUT'; Value = $script:originalGithubOutput },
                @{ Name = 'GH_TOKEN'; Value = $script:originalGitHubToken },
                @{ Name = 'LOCKFILE_PATH'; Value = $script:originalLockfilePath },
                @{ Name = 'REPOSITORY_ROOT'; Value = $script:originalRepositoryRoot },
                @{ Name = 'REPOSITORY_FULL_NAME'; Value = $script:originalRepositoryFullName }
            )) {
            if ($null -eq $environment.Value) {
                Remove-Item "Env:$($environment.Name)" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$($environment.Name)" -Value $environment.Value
            }
        }

        foreach ($functionName in 'git', 'Invoke-RestMethod', 'Get-RecordedGitCommands', 'Get-RecordedGitHubApiCalls') {
            Remove-Item "Function:\global:$functionName" -ErrorAction SilentlyContinue
        }

        foreach ($variableName in 'GitCommands', 'GitHubApiCalls', 'LocalHeadCommit', 'LocalLockfileBlobId', 'CreatedCommitSha', 'CreatedCommitVerified', 'CreatedCommitVerificationReason', 'RemoteHeadLine', 'RemoteLockfileBlobId', 'FailRefUpdate') {
            Remove-Item "Variable:\global:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'creates a signed bump commit and branch when the remote branch does not exist' {
        & $script:scriptPath

        $commands = Get-RecordedGitCommands
        $apiCalls = @(Get-RecordedGitHubApiCalls)
        $outputLines = Get-Content -Path $env:GITHUB_OUTPUT
        $commitCall = $apiCalls | Where-Object { ($_.Method -ceq 'POST') -and ($_.Uri -match '/git/commits$') } | Select-Object -First 1
        $refCall = $apiCalls | Where-Object { ($_.Method -ceq 'POST') -and ($_.Uri -match '/git/refs$') } | Select-Object -First 1

        $commitCall.Body.message | Should -BeExactly 'Bump pocof to 0.23.0'
        $commitCall.Body.parents | Should -Be @('basecommit')
        $commitCall.Body.PSObject.Properties.Name | Should -Not -Contain 'author'
        $commitCall.Body.PSObject.Properties.Name | Should -Not -Contain 'committer'
        $refCall.Body.ref | Should -BeExactly 'refs/heads/pslrm-bump/pocof'
        $refCall.Body.sha | Should -BeExactly 'signedcommit'
        $outputLines | Should -Contain 'branch_action=created'
        @($commands | Where-Object { $_ -match ' commit ' }).Count | Should -Be 0
        @($commands | Where-Object { $_ -match ' push ' }).Count | Should -Be 0
    }

    It 'reuses the existing remote branch when the lockfile already matches' {
        $global:RemoteHeadLine = "deadbeef`trefs/heads/pslrm-bump/pocof"
        $global:RemoteLockfileBlobId = $global:LocalLockfileBlobId

        & $script:scriptPath

        $commands = Get-RecordedGitCommands
        $apiCalls = @(Get-RecordedGitHubApiCalls)
        $outputLines = Get-Content -Path $env:GITHUB_OUTPUT

        @($commands | Where-Object { $_ -match ' fetch ' }).Count | Should -Be 1
        $outputLines | Should -Contain 'branch_action=noop'
        $apiCalls.Count | Should -Be 0
        @($commands | Where-Object { $_ -match ' commit ' }).Count | Should -Be 0
        @($commands | Where-Object { $_ -match ' push ' }).Count | Should -Be 0
    }

    It 'updates an existing remote branch with a fast-forward ref update when the lockfile differs' {
        $global:RemoteHeadLine = "deadbeef`trefs/heads/pslrm-bump/pocof"
        $global:RemoteLockfileBlobId = 'remote-lockfile-blob'

        & $script:scriptPath

        $commands = Get-RecordedGitCommands
        $apiCalls = @(Get-RecordedGitHubApiCalls)
        $outputLines = Get-Content -Path $env:GITHUB_OUTPUT
        $commitCall = $apiCalls | Where-Object { ($_.Method -ceq 'POST') -and ($_.Uri -match '/git/commits$') } | Select-Object -First 1
        $patchCall = $apiCalls | Where-Object { ($_.Method -ceq 'PATCH') -and ($_.Uri -match '/git/refs/') } | Select-Object -First 1

        $commitCall.Body.parents | Should -Be @('deadbeef')
        $patchCall.Body.sha | Should -BeExactly 'signedcommit'
        $patchCall.Body.force | Should -BeFalse
        $outputLines | Should -Contain 'branch_action=updated'
        @($commands | Where-Object { $_ -match ' commit ' }).Count | Should -Be 0
        @($commands | Where-Object { $_ -match ' push ' }).Count | Should -Be 0
    }

    It 'fails with a clear message when the ref update fails after inspection' {
        $global:RemoteHeadLine = "deadbeef`trefs/heads/pslrm-bump/pocof"
        $global:RemoteLockfileBlobId = 'remote-lockfile-blob'
        $global:FailRefUpdate = $true

        { & $script:scriptPath } | Should -Throw "*Failed to update bump branch 'pslrm-bump/pocof'. The branch may have changed after inspection.*"
    }

    It 'fails when GitHub does not verify the created commit' {
        $global:CreatedCommitVerified = $false
        $global:CreatedCommitVerificationReason = 'unsigned'

        { & $script:scriptPath } | Should -Throw "*GitHub did not verify it. Verification reason: unsigned*"
    }
}
