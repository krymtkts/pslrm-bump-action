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
        $global:LocalLockfileBlobId = 'local-lockfile-blob'
        $global:RemoteHeadLine = $null
        $global:RemoteLockfileBlobId = $null
        $global:PushExitCode = 0
        $global:PushOutput = @(
            'branch pushed'
        )

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
                if ($null -eq $global:RemoteLockfileBlobId) {
                    $global:LASTEXITCODE = 1
                    return
                }

                $global:RemoteLockfileBlobId
                return
            }

            if ($Arguments -contains 'push') {
                $global:LASTEXITCODE = $global:PushExitCode
                foreach ($line in @($global:PushOutput)) {
                    $line
                }

                return
            }

            if ($Arguments -contains 'commit') {
                '[pslrm-bump/pocof abc1234] Bump pocof to 0.23.0'
                return
            }

            if ($Arguments -contains 'switch') {
                'Switched branch.'
                return
            }
        }

        function Get-RecordedGitCommands {
            @(
                foreach ($commandArguments in $global:GitCommands) {
                    $commandArguments -join ' '
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

        foreach ($functionName in 'git', 'Get-RecordedGitCommands') {
            Remove-Item "Function:\global:$functionName" -ErrorAction SilentlyContinue
        }

        foreach ($variableName in 'GitCommands', 'LocalLockfileBlobId', 'RemoteHeadLine', 'RemoteLockfileBlobId', 'PushExitCode', 'PushOutput') {
            Remove-Item "Variable:\global:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'uses an empty-expect lease when the remote branch does not exist' {
        & $script:scriptPath

        $commands = Get-RecordedGitCommands
        $pushCommand = $commands | Where-Object { $_ -match ' push ' } | Select-Object -First 1
        $outputLines = Get-Content -Path $env:GITHUB_OUTPUT

        $pushCommand | Should -Match ([regex]::Escape('--force-with-lease=refs/heads/pslrm-bump/pocof:'))
        $outputLines | Should -Contain 'branch_action=created'
        @($commands | Where-Object { $_ -match ' commit ' }).Count | Should -Be 1
    }

    It 'reuses the existing remote branch when the lockfile already matches' {
        $global:RemoteHeadLine = "deadbeef`trefs/heads/pslrm-bump/pocof"
        $global:RemoteLockfileBlobId = $global:LocalLockfileBlobId

        & $script:scriptPath

        $commands = Get-RecordedGitCommands
        $outputLines = Get-Content -Path $env:GITHUB_OUTPUT

        @($commands | Where-Object { $_ -match ' fetch ' }).Count | Should -Be 1
        $outputLines | Should -Contain 'branch_action=noop'
        @($commands | Where-Object { $_ -match ' switch ' }).Count | Should -Be 0
        @($commands | Where-Object { $_ -match ' commit ' }).Count | Should -Be 0
        @($commands | Where-Object { $_ -match ' push ' }).Count | Should -Be 0
    }

    It 'updates an existing remote branch with an explicit lease when the lockfile differs' {
        $global:RemoteHeadLine = "deadbeef`trefs/heads/pslrm-bump/pocof"
        $global:RemoteLockfileBlobId = 'remote-lockfile-blob'

        & $script:scriptPath

        $commands = Get-RecordedGitCommands
        $pushCommand = $commands | Where-Object { $_ -match ' push ' } | Select-Object -First 1
        $outputLines = Get-Content -Path $env:GITHUB_OUTPUT

        $pushCommand | Should -Match ([regex]::Escape('--force-with-lease=refs/heads/pslrm-bump/pocof:deadbeef'))
        $outputLines | Should -Contain 'branch_action=updated'
        @($commands | Where-Object { $_ -match ' commit ' }).Count | Should -Be 1
    }

    It 'fails with a clear message when the explicit lease detects a stale remote branch' {
        $global:RemoteHeadLine = "deadbeef`trefs/heads/pslrm-bump/pocof"
        $global:RemoteLockfileBlobId = 'remote-lockfile-blob'
        $global:PushExitCode = 1
        $global:PushOutput = @(
            '! [rejected] pslrm-bump/pocof -> pslrm-bump/pocof (stale info)',
            "error: failed to push some refs to 'https://github.com/krymtkts/pslrm-actions-sandbox.git'"
        )

        { & $script:scriptPath } | Should -Throw "*Remote branch 'pslrm-bump/pocof' changed after inspection*"
    }
}