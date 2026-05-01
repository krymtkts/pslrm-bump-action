BeforeAll {
    $script:scriptPath = Join-Path $PSScriptRoot '..\..\scripts\Assert-RemoteMajorTagInvariant.ps1'
    . $script:scriptPath
}

Describe 'Assert-RemoteMajorTagInvariant script' {
    BeforeEach {
        $script:originalReleaseTag = $env:RELEASE_TAG
        $script:originalMajorTag = $env:MAJOR_TAG
        $script:originalRemoteName = $env:REMOTE_NAME
        $script:GitCommands = [System.Collections.Generic.List[string[]]]::new()
        $script:RemoteTagObjectIds = @{}

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
            $global:LASTEXITCODE = 0

            if ($recordedArguments[0] -ceq 'ls-remote') {
                $tagRef = $recordedArguments[4]
                if ($script:RemoteTagObjectIds.ContainsKey($tagRef)) {
                    "$($script:RemoteTagObjectIds[$tagRef])`t$tagRef"
                }

                return
            }
        }
    }

    AfterEach {
        foreach ($environment in @(
                @{ Name = 'RELEASE_TAG'; Value = $script:originalReleaseTag },
                @{ Name = 'MAJOR_TAG'; Value = $script:originalMajorTag },
                @{ Name = 'REMOTE_NAME'; Value = $script:originalRemoteName }
            )) {
            if ($null -eq $environment.Value) {
                Remove-Item "Env:$($environment.Name)" -ErrorAction SilentlyContinue
            }
            else {
                Set-Item "Env:$($environment.Name)" -Value $environment.Value
            }
        }

        Remove-Item Function:\global:git -ErrorAction SilentlyContinue
        foreach ($variableName in 'GitCommands', 'RemoteTagObjectIds') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'returns matching remote tag state when the mutable major tag mirrors the exact release tag' {
        $script:RemoteTagObjectIds['refs/tags/v0.0.1-alpha'] = 'tag-object-id'
        $script:RemoteTagObjectIds['refs/tags/v0'] = 'tag-object-id'

        $result = Assert-RemoteMajorTagInvariant -ReleaseTag 'v0.0.1-alpha' -MajorTag 'v0'

        $result.ReleaseObjectId | Should -Be 'tag-object-id'
        $result.MajorObjectId | Should -Be 'tag-object-id'
        $script:GitCommands[0] | Should -Be @(
            'ls-remote',
            '--refs',
            '--tags',
            'origin',
            'refs/tags/v0.0.1-alpha'
        )
        $script:GitCommands[1] | Should -Be @(
            'ls-remote',
            '--refs',
            '--tags',
            'origin',
            'refs/tags/v0'
        )
    }

    It 'uses a custom remote name when one is provided' {
        $script:RemoteTagObjectIds['refs/tags/v0.0.1-alpha'] = 'tag-object-id'
        $script:RemoteTagObjectIds['refs/tags/v0'] = 'tag-object-id'

        $result = Assert-RemoteMajorTagInvariant -ReleaseTag 'v0.0.1-alpha' -MajorTag 'v0' -RemoteName 'upstream'

        $result.RemoteName | Should -Be 'upstream'
        $script:GitCommands[0] | Should -Be @(
            'ls-remote',
            '--refs',
            '--tags',
            'upstream',
            'refs/tags/v0.0.1-alpha'
        )
        $script:GitCommands[1] | Should -Be @(
            'ls-remote',
            '--refs',
            '--tags',
            'upstream',
            'refs/tags/v0'
        )
    }

    It 'fails when the release tag format is invalid' {
        { Assert-RemoteMajorTagInvariant -ReleaseTag 'main' -MajorTag 'v0' } | Should -Throw '*Release tag must be vX.Y.Z or vX.Y.Z-prerelease*'
    }

    It 'fails when the major tag does not match the release major' {
        { Assert-RemoteMajorTagInvariant -ReleaseTag 'v0.0.1-alpha' -MajorTag 'v1' } | Should -Throw "*Expected mutable major tag 'v0'*"
    }

    It 'fails when the exact release tag is missing from the remote' {
        $script:RemoteTagObjectIds['refs/tags/v0'] = 'tag-object-id'

        { Assert-RemoteMajorTagInvariant -ReleaseTag 'v0.0.1-alpha' -MajorTag 'v0' } | Should -Throw "*Remote exact release tag 'v0.0.1-alpha' does not exist*"
    }

    It 'fails when the mutable major tag is missing from the remote' {
        $script:RemoteTagObjectIds['refs/tags/v0.0.1-alpha'] = 'tag-object-id'

        { Assert-RemoteMajorTagInvariant -ReleaseTag 'v0.0.1-alpha' -MajorTag 'v0' } | Should -Throw "*Remote mutable major tag 'v0' does not exist*"
    }

    It 'fails when the mutable major tag points to a different object' {
        $script:RemoteTagObjectIds['refs/tags/v0.0.1-alpha'] = 'exact-tag-object-id'
        $script:RemoteTagObjectIds['refs/tags/v0'] = 'major-tag-object-id'

        { Assert-RemoteMajorTagInvariant -ReleaseTag 'v0.0.1-alpha' -MajorTag 'v0' } | Should -Throw "*does not match exact release tag*"
    }
}
