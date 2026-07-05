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
        $global:FailTreeCreationAccess = $false

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

        function global:gh {
            param(
                [Parameter(ValueFromRemainingArguments)]
                [object[]] $Arguments
            )

            $flatArguments = @(
                foreach ($argument in $Arguments) {
                    if ($argument -is [object[]]) {
                        foreach ($nestedArgument in $argument) {
                            [string] $nestedArgument
                        }
                    }
                    else {
                        [string] $argument
                    }
                }
            )

            $global:LASTEXITCODE = 0
            if (($flatArguments.Count -lt 2) -or ($flatArguments[0] -cne 'api')) {
                throw "Unexpected gh call: $($flatArguments -join ' ')"
            }

            $methodIndex = [array]::IndexOf($flatArguments, '--method')
            if ($methodIndex -lt 0) {
                throw "Unexpected gh api call without --method: $($flatArguments -join ' ')"
            }

            $method = [string] $flatArguments[$methodIndex + 1]
            $inputIndex = [array]::IndexOf($flatArguments, '--input')
            $bodyObject = if ($inputIndex -lt 0) {
                $null
            }
            else {
                Get-Content -LiteralPath ([string] $flatArguments[$inputIndex + 1]) -Raw | ConvertFrom-Json
            }

            $path = [string] (
                $flatArguments |
                    Where-Object { ([string] $_).StartsWith('/repos/') } |
                    Select-Object -Last 1
            )
            if ([string]::IsNullOrWhiteSpace($path)) {
                throw "Unexpected gh api call without repository path: $($flatArguments -join ' ')"
            }

            $global:GitHubApiCalls.Add([pscustomobject]@{
                    Method = $method
                    Uri = "https://api.github.com$path"
                    Body = $bodyObject
                })

            if (($method -ceq 'GET') -and ($path -match '/git/commits/')) {
                '{"tree":{"sha":"basetree"}}'
                return
            }

            if (($method -ceq 'POST') -and ($path -match '/git/trees$')) {
                if ($global:FailTreeCreationAccess) {
                    'HTTP 403: Resource not accessible by integration'
                    $global:LASTEXITCODE = 1
                    return
                }

                '{"sha":"newtree"}'
                return
            }

            if (($method -ceq 'POST') -and ($path -match '/git/commits$')) {
                @"
{"sha":"$global:CreatedCommitSha","verification":{"verified":$($global:CreatedCommitVerified.ToString().ToLowerInvariant()),"reason":"$global:CreatedCommitVerificationReason"}}
"@
                return
            }

            if (($method -ceq 'POST') -and ($path -match '/git/refs$')) {
                @"
{"ref":"refs/heads/pslrm-bump/pocof","object":{"sha":"$global:CreatedCommitSha"}}
"@
                return
            }

            if (($method -ceq 'PATCH') -and ($path -match '/git/refs/')) {
                if ($global:FailRefUpdate) {
                    'Reference update failed.'
                    $global:LASTEXITCODE = 1
                    return
                }

                @"
{"ref":"refs/heads/pslrm-bump/pocof","object":{"sha":"$global:CreatedCommitSha"}}
"@
                return
            }

            throw "Unexpected GitHub API call: $method https://api.github.com$path"
        }

        function global:Invoke-RestMethod {
            throw 'Invoke-RestMethod should not be used.'
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

        foreach ($functionName in 'git', 'gh', 'Invoke-RestMethod', 'Get-RecordedGitCommands', 'Get-RecordedGitHubApiCalls') {
            Remove-Item "Function:\global:$functionName" -ErrorAction SilentlyContinue
        }

        foreach ($variableName in 'GitCommands', 'GitHubApiCalls', 'LocalHeadCommit', 'LocalLockfileBlobId', 'CreatedCommitSha', 'CreatedCommitVerified', 'CreatedCommitVerificationReason', 'RemoteHeadLine', 'RemoteLockfileBlobId', 'FailRefUpdate', 'FailTreeCreationAccess') {
            Remove-Item "Variable:\global:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'creates a signed bump commit and branch when the remote branch does not exist' {
        & $script:scriptPath

        $commands = Get-RecordedGitCommands
        $apiCalls = @(Get-RecordedGitHubApiCalls)
        $outputLines = Get-Content -Path $env:GITHUB_OUTPUT
        $treeCall = $apiCalls | Where-Object { ($_.Method -ceq 'POST') -and ($_.Uri -match '/git/trees$') } | Select-Object -First 1
        $commitCall = $apiCalls | Where-Object { ($_.Method -ceq 'POST') -and ($_.Uri -match '/git/commits$') } | Select-Object -First 1
        $refCall = $apiCalls | Where-Object { ($_.Method -ceq 'POST') -and ($_.Uri -match '/git/refs$') } | Select-Object -First 1

        $treeCall.Body.tree[0].content | Should -BeExactly "@{}`n"
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

    It 'fails with permission guidance when GitHub rejects tree creation' {
        $global:FailTreeCreationAccess = $true

        { & $script:scriptPath } | Should -Throw "*Grant 'contents: write' to GITHUB_TOKEN*"
    }
}
