BeforeAll {
    $script:helperPath = Join-Path $PSScriptRoot '..\..\tools\Build.Helpers.ps1'
    . $script:helperPath
}

Describe 'Assert-CleanGitWorktree' {
    BeforeEach {
        $script:GitCommands = [System.Collections.Generic.List[string[]]]::new()
        $script:GitStatusOutput = @()

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

            switch ($recordedArguments[0]) {
                'status' {
                    $script:GitStatusOutput
                    return
                }
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:git -ErrorAction SilentlyContinue
        foreach ($variableName in 'GitCommands', 'GitStatusOutput') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'inspects plain git status' {
        Assert-CleanGitWorktree

        $script:GitCommands[0] | Should -Be @(
            'status',
            '--porcelain=v1',
            '--untracked-files=all'
        )
    }

    It 'fails when changes remain' {
        $script:GitStatusOutput = @(
            ' M README.md'
        )

        { Assert-CleanGitWorktree } | Should -Throw '*README.md*'
    }
}

Describe 'Get-LocalGitTagState' {
    BeforeEach {
        $script:GitCommands = [System.Collections.Generic.List[string[]]]::new()
        $script:LocalTagObjectId = $null

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

            if ($recordedArguments[0] -ceq 'for-each-ref') {
                if ($null -ne $script:LocalTagObjectId) {
                    $script:LocalTagObjectId
                }

                return
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:git -ErrorAction SilentlyContinue
        foreach ($variableName in 'GitCommands', 'LocalTagObjectId') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'returns a missing state when the local tag does not exist' {
        $state = Get-LocalGitTagState -TagName 'v0.0.1-alpha'

        $state.Exists | Should -BeFalse
        $state.ObjectId | Should -Be $null
        $script:GitCommands[0] | Should -Be @(
            'for-each-ref',
            '--format=%(objectname)',
            'refs/tags/v0.0.1-alpha'
        )
    }

    It 'returns an existing state and object id when the local tag exists' {
        $script:LocalTagObjectId = 'tag-object-id'

        $state = Get-LocalGitTagState -TagName 'v0.0.1-alpha'

        $state.Exists | Should -BeTrue
        $state.ObjectId | Should -Be 'tag-object-id'
    }
}

Describe 'Get-RemoteGitTagState' {
    BeforeEach {
        $script:GitCommands = [System.Collections.Generic.List[string[]]]::new()
        $script:RemoteTagObjectId = $null

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
                if ($null -ne $script:RemoteTagObjectId) {
                    "$($script:RemoteTagObjectId)`t$($recordedArguments[4])"
                }

                return
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:git -ErrorAction SilentlyContinue
        foreach ($variableName in 'GitCommands', 'RemoteTagObjectId') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'returns a missing state when the remote tag does not exist' {
        $state = Get-RemoteGitTagState -TagName 'v0.0.1-alpha'

        $state.Exists | Should -BeFalse
        $state.ObjectId | Should -Be $null
        $script:GitCommands[0] | Should -Be @(
            'ls-remote',
            '--refs',
            '--tags',
            'origin',
            'refs/tags/v0.0.1-alpha'
        )
    }

    It 'returns an existing state and object id when the remote tag exists' {
        $script:RemoteTagObjectId = 'tag-object-id'

        $state = Get-RemoteGitTagState -TagName 'v0.0.1-alpha'

        $state.Exists | Should -BeTrue
        $state.ObjectId | Should -Be 'tag-object-id'
    }
}

Describe 'Get-GitReleaseTagPlan' {
    BeforeEach {
        $script:GitCommands = [System.Collections.Generic.List[string[]]]::new()
        $script:LocalTagObjectId = $null
        $script:RemoteTagObjectId = $null
        $script:LocalTagPointsAtHead = $false

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

            switch ($recordedArguments[0]) {
                'for-each-ref' {
                    if ($null -eq $script:LocalTagObjectId) {
                        return
                    }

                    $script:LocalTagObjectId
                    return
                }
                'tag' {
                    if ($recordedArguments[1] -ceq '--points-at') {
                        if ($script:LocalTagPointsAtHead) {
                            $recordedArguments[-1]
                        }

                        return
                    }
                }
                'ls-remote' {
                    if ($null -ne $script:RemoteTagObjectId) {
                        "$($script:RemoteTagObjectId)`t$($recordedArguments[4])"
                    }

                    return
                }
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:git -ErrorAction SilentlyContinue
        foreach ($variableName in 'GitCommands', 'LocalTagObjectId', 'RemoteTagObjectId', 'LocalTagPointsAtHead') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'plans to create and push a release tag when no tag exists yet' {
        $plan = Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha'

        $plan.CreateLocalTag | Should -BeTrue
        $plan.PushRemoteTag | Should -BeTrue
        $plan.LocalTagExists | Should -BeFalse
        $plan.RemoteTagExists | Should -BeFalse
    }

    It 'plans to reuse the local tag and push it when the remote tag is missing' {
        $script:LocalTagObjectId = 'tag-object-id'
        $script:LocalTagPointsAtHead = $true

        $plan = Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha'

        $plan.CreateLocalTag | Should -BeFalse
        $plan.PushRemoteTag | Should -BeTrue
    }

    It 'plans no tag changes when matching local and remote tags already exist' {
        $script:LocalTagObjectId = 'tag-object-id'
        $script:LocalTagPointsAtHead = $true
        $script:RemoteTagObjectId = 'tag-object-id'

        $plan = Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha'

        $plan.CreateLocalTag | Should -BeFalse
        $plan.PushRemoteTag | Should -BeFalse
    }

    It 'fails when the local tag does not point at HEAD' {
        $script:LocalTagObjectId = 'tag-object-id'

        { Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha' } | Should -Throw '*does not point at HEAD*'
    }

    It 'fails when the remote tag does not match the local tag' {
        $script:LocalTagObjectId = 'local-tag-object-id'
        $script:LocalTagPointsAtHead = $true
        $script:RemoteTagObjectId = 'remote-tag-object-id'

        { Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha' } | Should -Throw '*does not match the local signed tag*'
    }
}

Describe 'Set-GitReleaseTag' {
    BeforeEach {
        $script:GitCommands = [System.Collections.Generic.List[string[]]]::new()
        $script:LocalTagObjectId = $null
        $script:RemoteTagObjectId = $null
        $script:LocalTagPointsAtHead = $false

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

            switch ($recordedArguments[0]) {
                'for-each-ref' {
                    if ($null -eq $script:LocalTagObjectId) {
                        return
                    }

                    $script:LocalTagObjectId
                    return
                }
                'tag' {
                    if ($recordedArguments[1] -ceq '--points-at') {
                        if ($script:LocalTagPointsAtHead) {
                            $recordedArguments[-1]
                        }

                        return
                    }

                    $script:LocalTagObjectId = 'tag-object-id'
                    $script:LocalTagPointsAtHead = $true
                    return
                }
                'ls-remote' {
                    if ($null -ne $script:RemoteTagObjectId) {
                        "$($script:RemoteTagObjectId)`t$($recordedArguments[4])"
                    }

                    return
                }
                'push' {
                    $script:RemoteTagObjectId = $script:LocalTagObjectId
                    return
                }
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:git -ErrorAction SilentlyContinue
        foreach ($variableName in 'GitCommands', 'LocalTagObjectId', 'RemoteTagObjectId', 'LocalTagPointsAtHead') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'creates and pushes a signed tag when the release tag does not exist yet' {
        $plan = Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha'

        $result = Set-GitReleaseTag -ReleaseTag 'v0.0.1-alpha' -ReleaseNotes 'Body text.' -Plan $plan

        $result.TagCreated | Should -BeTrue
        $result.TagPushed | Should -BeTrue

        $tagCommand = @($script:GitCommands | Where-Object { $_[0] -ceq 'tag' })[0]
        $pushCommand = @($script:GitCommands | Where-Object { $_[0] -ceq 'push' })[0]

        $tagCommand | Should -Be @(
            'tag',
            '--sign',
            '--cleanup=verbatim',
            'v0.0.1-alpha',
            '--message',
            'Body text.'
        )
        $pushCommand | Should -Be @(
            'push',
            'origin',
            'refs/tags/v0.0.1-alpha'
        )
    }

    It 'applies a precomputed release tag plan without re-reading the remote tag state' {
        $plan = Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha'

        $result = Set-GitReleaseTag -ReleaseTag 'v0.0.1-alpha' -ReleaseNotes 'Body text.' -Plan $plan

        $result.TagCreated | Should -BeTrue
        $result.TagPushed | Should -BeTrue
        @($script:GitCommands | Where-Object { $_[0] -ceq 'ls-remote' }).Count | Should -Be 1
        @($script:GitCommands | Where-Object { $_[0] -ceq 'tag' -and $_[1] -ceq '--sign' }).Count | Should -Be 1
        @($script:GitCommands | Where-Object { $_[0] -ceq 'push' }).Count | Should -Be 1
    }

    It 'reuses an existing local tag and only pushes it when the remote tag is missing' {
        $script:LocalTagObjectId = 'tag-object-id'
        $script:LocalTagPointsAtHead = $true

        $plan = Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha'

        $result = Set-GitReleaseTag -ReleaseTag 'v0.0.1-alpha' -ReleaseNotes 'Body text.' -Plan $plan

        $result.TagCreated | Should -BeFalse
        $result.TagPushed | Should -BeTrue
        @($script:GitCommands | Where-Object { $_[0] -ceq 'tag' -and $_[1] -ceq '--sign' }).Count | Should -Be 0
        @($script:GitCommands | Where-Object { $_[0] -ceq 'tag' -and $_[1] -ceq '--points-at' }).Count | Should -Be 1
        @($script:GitCommands | Where-Object { $_[0] -ceq 'push' }).Count | Should -Be 1
    }

    It 'reuses matching local and remote tags without recreating or pushing' {
        $script:LocalTagObjectId = 'tag-object-id'
        $script:LocalTagPointsAtHead = $true
        $script:RemoteTagObjectId = 'tag-object-id'

        $plan = Get-GitReleaseTagPlan -ReleaseTag 'v0.0.1-alpha'

        $result = Set-GitReleaseTag -ReleaseTag 'v0.0.1-alpha' -ReleaseNotes 'Body text.' -Plan $plan

        $result.TagCreated | Should -BeFalse
        $result.TagPushed | Should -BeFalse
        @($script:GitCommands | Where-Object { $_[0] -ceq 'tag' -and $_[1] -ceq '--sign' }).Count | Should -Be 0
        @($script:GitCommands | Where-Object { $_[0] -ceq 'push' }).Count | Should -Be 0
    }
}

Describe 'Get-GitHubDraftReleasePlan' {
    BeforeEach {
        $script:GhCommands = [System.Collections.Generic.List[string[]]]::new()
        $script:ExistingRelease = $null

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
            $global:LASTEXITCODE = 0

            if (($recordedArguments[0] -ceq 'release') -and ($recordedArguments[1] -ceq 'view')) {
                if ($null -eq $script:ExistingRelease) {
                    $global:LASTEXITCODE = 1
                    'release not found'
                    return
                }

                $script:ExistingRelease | ConvertTo-Json -Compress
                return
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
        foreach ($variableName in 'GhCommands', 'ExistingRelease') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'plans to create a draft release when no GitHub release exists yet' {
        $plan = Get-GitHubDraftReleasePlan -ReleaseTag 'v0.0.1-alpha'

        $plan.Action | Should -Be 'Create'
        $plan.IsPrerelease | Should -BeTrue
        $plan.Url | Should -Be $null
    }

    It 'derives a non-prerelease plan from an exact release tag' {
        $plan = Get-GitHubDraftReleasePlan -ReleaseTag 'v0.0.1'

        $plan.Action | Should -Be 'Create'
        $plan.IsPrerelease | Should -BeFalse
    }

    It 'plans to update an existing draft release' {
        $script:ExistingRelease = [pscustomobject]@{
            url = 'https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha'
            isDraft = $true
            isPrerelease = $true
            tagName = 'v0.0.1-alpha'
        }

        $plan = Get-GitHubDraftReleasePlan -ReleaseTag 'v0.0.1-alpha'

        $plan.Action | Should -Be 'Update'
        $plan.Url | Should -BeExactly 'https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha'
        $plan.PrereleaseStateChanged | Should -BeFalse
    }

    It 'fails when the GitHub release is already published' {
        $script:ExistingRelease = [pscustomobject]@{
            url = 'https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha'
            isDraft = $false
            isPrerelease = $true
            tagName = 'v0.0.1-alpha'
        }

        { Get-GitHubDraftReleasePlan -ReleaseTag 'v0.0.1-alpha' } | Should -Throw '*already published*'
    }
}

Describe 'Get-ReleaseDryRunMessages' {
    It 'returns create-oriented dry-run messages when the release tag and draft release do not exist yet' {
        $tagPlan = [pscustomobject]@{
            ReleaseTag = 'v0.0.1-alpha'
            CreateLocalTag = $true
            PushRemoteTag = $true
        }
        $draftReleasePlan = [pscustomobject]@{
            ReleaseTag = 'v0.0.1-alpha'
            Action = 'Create'
            IsPrerelease = $true
            PrereleaseStateChanged = $false
            Url = $null
        }

        $messages = Get-ReleaseDryRunMessages -ReleaseTag 'v0.0.1-alpha' -TagPlan $tagPlan -DraftReleasePlan $draftReleasePlan

        $messages | Should -Be @(
            "local release tag 'v0.0.1-alpha': would be created."
            "remote release tag 'v0.0.1-alpha': would be pushed to origin."
            "draft GitHub release 'v0.0.1-alpha': would be created."
        )
    }

    It 'returns update-oriented dry-run messages when the draft release would be updated' {
        $tagPlan = [pscustomobject]@{
            ReleaseTag = 'v0.0.1-alpha'
            CreateLocalTag = $false
            PushRemoteTag = $false
        }
        $draftReleasePlan = [pscustomobject]@{
            ReleaseTag = 'v0.0.1-alpha'
            Action = 'Update'
            IsPrerelease = $false
            PrereleaseStateChanged = $true
            Url = 'https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha'
        }

        $messages = Get-ReleaseDryRunMessages -ReleaseTag 'v0.0.1-alpha' -TagPlan $tagPlan -DraftReleasePlan $draftReleasePlan

        $messages | Should -Be @(
            "local release tag 'v0.0.1-alpha': already exists."
            "remote release tag 'v0.0.1-alpha': already exists on origin."
            "draft GitHub release 'v0.0.1-alpha': would be updated and prerelease would be set to False: https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha."
        )
    }
}

Describe 'Set-GitHubDraftRelease' {
    BeforeEach {
        $script:GhCommands = [System.Collections.Generic.List[string[]]]::new()
        $script:ExistingRelease = $null
        $script:releaseNotesPath = Join-Path $TestDrive 'release-notes.md'
        Set-Content -LiteralPath $script:releaseNotesPath -Value 'Example release notes.' -NoNewline

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
            $global:LASTEXITCODE = 0

            if (($recordedArguments[0] -ceq 'release') -and ($recordedArguments[1] -ceq 'view')) {
                if ($null -eq $script:ExistingRelease) {
                    $global:LASTEXITCODE = 1
                    'release not found'
                    return
                }

                $script:ExistingRelease | ConvertTo-Json -Compress
                return
            }

            if (($recordedArguments[0] -ceq 'release') -and ($recordedArguments[1] -ceq 'create')) {
                $script:ExistingRelease = [pscustomobject]@{
                    url = "https://github.com/krymtkts/pslrm-bump-action/releases/tag/$($recordedArguments[2])"
                    isDraft = $true
                    isPrerelease = ($recordedArguments -contains '--prerelease')
                    tagName = $recordedArguments[2]
                }

                $script:ExistingRelease.url
                return
            }

            if (($recordedArguments[0] -ceq 'release') -and ($recordedArguments[1] -ceq 'edit')) {
                $prereleaseArgument = $recordedArguments | Where-Object { $_ -like '--prerelease=*' } | Select-Object -First 1
                if ($recordedArguments -contains '--prerelease') {
                    $script:ExistingRelease.isPrerelease = $true
                }
                elseif (-not [string]::IsNullOrWhiteSpace($prereleaseArgument)) {
                    $script:ExistingRelease.isPrerelease = [bool]::Parse(($prereleaseArgument -split '=', 2)[1])
                }

                return
            }
        }
    }

    AfterEach {
        Remove-Item Function:\global:gh -ErrorAction SilentlyContinue
        foreach ($variableName in 'GhCommands', 'ExistingRelease') {
            Remove-Item "Variable:\script:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'creates a draft prerelease when no GitHub release exists yet' {
        $plan = Get-GitHubDraftReleasePlan -ReleaseTag 'v0.0.1-alpha'

        $result = Set-GitHubDraftRelease -ReleaseTag 'v0.0.1-alpha' -ReleaseNotesPath $script:releaseNotesPath -Plan $plan

        $result.isDraft | Should -BeTrue
        $result.isPrerelease | Should -BeTrue

        $createCommand = @($script:GhCommands | Where-Object { $_[0] -ceq 'release' -and $_[1] -ceq 'create' })[0]
        $createCommand | Should -Be @(
            'release',
            'create',
            'v0.0.1-alpha',
            '--verify-tag',
            '--draft',
            '--title',
            'v0.0.1-alpha',
            '--notes-file',
            $script:releaseNotesPath,
            '--prerelease'
        )
    }

    It 'applies a precomputed draft release plan without re-reading the initial release state' {
        $plan = Get-GitHubDraftReleasePlan -ReleaseTag 'v0.0.1-alpha'

        $result = Set-GitHubDraftRelease -ReleaseTag 'v0.0.1-alpha' -ReleaseNotesPath $script:releaseNotesPath -Plan $plan

        $result.isDraft | Should -BeTrue
        $result.isPrerelease | Should -BeTrue
        @($script:GhCommands | Where-Object { $_[0] -ceq 'release' -and $_[1] -ceq 'view' }).Count | Should -Be 2
        @($script:GhCommands | Where-Object { $_[0] -ceq 'release' -and $_[1] -ceq 'create' }).Count | Should -Be 1
    }

    It 'updates an existing draft release' {
        $script:ExistingRelease = [pscustomobject]@{
            url = 'https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha'
            isDraft = $true
            isPrerelease = $true
            tagName = 'v0.0.1-alpha'
        }

        $plan = Get-GitHubDraftReleasePlan -ReleaseTag 'v0.0.1-alpha'

        $result = Set-GitHubDraftRelease -ReleaseTag 'v0.0.1-alpha' -ReleaseNotesPath $script:releaseNotesPath -Plan $plan

        $result.url | Should -BeExactly 'https://github.com/krymtkts/pslrm-bump-action/releases/tag/v0.0.1-alpha'
        @($script:GhCommands | Where-Object { $_[0] -ceq 'release' -and $_[1] -ceq 'create' }).Count | Should -Be 0
        @($script:GhCommands | Where-Object { $_[0] -ceq 'release' -and $_[1] -ceq 'edit' }).Count | Should -Be 1
    }
}
