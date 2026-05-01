BeforeAll {
    $script:helperPath = Join-Path $PSScriptRoot '..\..\scripts\GitHubActions.Helper.ps1'
    . $script:helperPath
}

Describe 'run wrappers with git' {
    BeforeEach {
        $script:GitCommandOutput = @()
        $script:GitCommandErrorOutput = @()
        $script:GitExitCode = 0
        $script:GitCommands = [System.Collections.Generic.List[string[]]]::new()

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
            $script:GitCommands.Add($recordedArguments)
            $global:LASTEXITCODE = $script:GitExitCode

            foreach ($line in $script:GitCommandErrorOutput) {
                Write-Error -Message $line
            }

            foreach ($line in $script:GitCommandOutput) {
                $line
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:git -ErrorAction SilentlyContinue
        foreach ($variableName in 'GitCommandOutput', 'GitCommandErrorOutput', 'GitExitCode', 'GitCommands') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'returns result objects from run' {
        $script:GitCommandOutput = @('line 1', 'line 2')
        $script:GitExitCode = 7

        $result = run git status --short

        $result.ExitCode | Should -Be 7
        $result.Output | Should -Be @('line 1', 'line 2')
        $script:GitCommands[0] | Should -Be @('status', '--short')
    }

    It 'passes option-like arguments through run' {
        $null = run git -C 'C:\repo' status --short

        $script:GitCommands[0] | Should -Be @('-C', 'C:\repo', 'status', '--short')
    }

    It 'preserves null output entries from commands' {
        $script:GitCommandOutput = @($null, 'line 2')

        $result = run git status --short

        $result.Output.Count | Should -Be 2
        $result.Output[0] | Should -Be $null
        $result.Output[1] | Should -Be 'line 2'
    }

    It 'throws with command output details from runx' {
        $script:GitCommandOutput = @('fatal: bad things happened')
        $script:GitExitCode = 1

        { runx 'Git command failed.' git status --short } | Should -Throw "*Git command failed.*bad things happened*"
    }

    It 'passes option-like arguments through runx' {
        $script:GitCommandOutput = @('fatal: bad things happened')
        $script:GitExitCode = 1

        { runx 'Git command failed.' git -C 'C:\repo' status --short } | Should -Throw "*Git command failed.*bad things happened*"
        $script:GitCommands[0] | Should -Be @('-C', 'C:\repo', 'status', '--short')
    }

    It 'keeps successful error-stream output non-fatal under Stop' {
        $script:GitCommandErrorOutput = @("Switched to a new branch 'pslrm-bump/test'")
        $script:GitExitCode = 0

        $originalErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Stop'

            $result = runx 'Git command failed.' git switch --force-create pslrm-bump/test

            $result.ExitCode | Should -Be 0
            $result.Output | Should -Be @("Switched to a new branch 'pslrm-bump/test'")
            $ErrorActionPreference | Should -Be 'Stop'
            $script:GitCommands[0] | Should -Be @('switch', '--force-create', 'pslrm-bump/test')
        }
        finally {
            $ErrorActionPreference = $originalErrorActionPreference
        }
    }
}

Describe 'run wrappers with gh' {
    BeforeEach {
        $script:GhCommandOutput = @()
        $script:GhExitCode = 0
        $script:GhCommands = [System.Collections.Generic.List[string[]]]::new()

        function global:gh {
            param(
                [Parameter(ValueFromRemainingArguments)]
                [object[]] $Arguments
            )

            $recordedArguments = [string[]] @(
                foreach ($argument in $Arguments) {
                    [string] $argument
                }
            )
            $script:GhCommands.Add($recordedArguments)
            $global:LASTEXITCODE = $script:GhExitCode

            foreach ($line in $script:GhCommandOutput) {
                $line
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
        foreach ($variableName in 'GhCommandOutput', 'GhExitCode', 'GhCommands') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'returns result objects from run' {
        $script:GhCommandOutput = @('{"number":7}')
        $script:GhExitCode = 0

        $result = run gh pr view 7 --json number

        $result.ExitCode | Should -Be 0
        $result.Output | Should -Be @('{"number":7}')
        $script:GhCommands[0] | Should -Be @('pr', 'view', '7', '--json', 'number')
    }

    It 'throws with command output details from runx' {
        $script:GhCommandOutput = @('HTTP 403: forbidden')
        $script:GhExitCode = 1

        { runx 'GitHub CLI command failed.' gh pr list --state open } | Should -Throw "*GitHub CLI command failed.*HTTP 403: forbidden*"
    }
}
