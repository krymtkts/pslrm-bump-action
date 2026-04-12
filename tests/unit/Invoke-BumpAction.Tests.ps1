BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-BumpAction.ps1'
    $script:singleDependencyRequirementsFixture = @'
@{
    pocof = @{
        Repository = 'PSGallery'
    }
}
'@
    $script:singleDependencyLockfileBeforeUpdateFixture = @'
@{
    pocof = @{
        Repository = 'PSGallery'
        Version = '0.1.0'
    }
}
'@
    $script:singleDependencyLockfileAfterUpdateFixture = @'
@{
    pocof = @{
        Repository = 'PSGallery'
        Version = '0.2.0'
    }
}
'@
}

Describe 'Invoke-BumpAction' {
    BeforeEach {
        $script:originalDefaultBranch = $env:DEFAULT_BRANCH
        $script:originalGithubRefName = $env:GITHUB_REF_NAME
        $script:originalGithubOutput = $env:GITHUB_OUTPUT
        $global:UpdateCalls = [System.Collections.Generic.List[object]]::new()
        $global:GitRepositoryRoot = $script:repoRoot
        $global:GitCurrentBranch = 'main'
        $global:GitStatusLines = @()
        $global:UpdatedLockfileFixture = $null

        function global:Update-PSLResource {
            param(
                [string] $Path
            )

            $global:UpdateCalls.Add([pscustomobject]@{
                    Path = $Path
                })

            if ($null -ne $global:UpdatedLockfileFixture) {
                $lockfilePath = Join-Path $Path 'psreq.lock.psd1'
                Set-Content -LiteralPath $lockfilePath -Value $global:UpdatedLockfileFixture -NoNewline
            }
        }

        function Set-TestProjectFiles {
            param(
                [Parameter(Mandatory)]
                [string] $ProjectRoot,

                [Parameter(Mandatory)]
                [string] $RequirementsContent,

                [Parameter(Mandatory)]
                [string] $LockfileContent
            )

            Set-Content -LiteralPath (Join-Path $ProjectRoot 'psreq.psd1') -Value $RequirementsContent -NoNewline
            Set-Content -LiteralPath (Join-Path $ProjectRoot 'psreq.lock.psd1') -Value $LockfileContent -NoNewline
        }

        function global:git {
            param(
                [Parameter(ValueFromRemainingArguments)]
                [object[]] $Arguments
            )

            $global:LASTEXITCODE = 0
            if ($Arguments -contains '--show-toplevel') {
                $global:GitRepositoryRoot
                return
            }

            if ($Arguments -contains '--show-current') {
                $global:GitCurrentBranch
                return
            }

            if ($Arguments -contains 'status') {
                $global:GitStatusLines
                return
            }
        }
    }

    AfterEach {
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue

        if ($null -eq $script:originalDefaultBranch) {
            Remove-Item Env:DEFAULT_BRANCH -ErrorAction SilentlyContinue
        }
        else {
            $env:DEFAULT_BRANCH = $script:originalDefaultBranch
        }

        if ($null -eq $script:originalGithubRefName) {
            Remove-Item Env:GITHUB_REF_NAME -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_REF_NAME = $script:originalGithubRefName
        }

        if ($null -eq $script:originalGithubOutput) {
            Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_OUTPUT = $script:originalGithubOutput
        }

        foreach ($functionName in 'Set-TestProjectFiles', 'Update-PSLResource', 'git') {
            Remove-Item "Function:\global:$functionName" -ErrorAction SilentlyContinue
        }

        foreach ($variableName in 'UpdateCalls', 'GitRepositoryRoot', 'GitCurrentBranch', 'GitStatusLines', 'UpdatedLockfileFixture') {
            Remove-Item "Variable:\global:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'writes changed=false when lockfile content is unchanged' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-TestProjectFiles -ProjectRoot $projectRoot -RequirementsContent $script:singleDependencyRequirementsFixture -LockfileContent $script:singleDependencyLockfileAfterUpdateFixture

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:UpdatedLockfileFixture = $script:singleDependencyLockfileAfterUpdateFixture

        Push-Location $script:repoRoot
        try {
            & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
        }
        finally {
            Pop-Location
        }

        $outputLines = Get-Content -Path $outputPath

        $outputLines | Should -Contain 'changed=false'
        $outputLines | Should -Contain "project_root=$projectRoot"
        $outputLines | Should -Contain "repository_root=$script:repoRoot"
        $outputLines | Should -Contain "lockfile_path=$(Join-Path $projectRoot 'psreq.lock.psd1')"
        $outputLines | Should -Contain 'base_branch=main'
        $global:UpdateCalls.Count | Should -Be 1
        $global:UpdateCalls[0].Path | Should -Be $projectRoot
    }

    It 'does not require GH_TOKEN for lockfile update and output generation' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-TestProjectFiles -ProjectRoot $projectRoot -RequirementsContent $script:singleDependencyRequirementsFixture -LockfileContent $script:singleDependencyLockfileAfterUpdateFixture

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        $env:GITHUB_OUTPUT = $outputPath
        $global:UpdatedLockfileFixture = $script:singleDependencyLockfileAfterUpdateFixture

        Push-Location $script:repoRoot
        try {
            & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
        }
        finally {
            Pop-Location
        }

        Get-Content -Path $outputPath | Should -Contain 'changed=false'
    }

    It 'writes changed=true when lockfile content changes' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-TestProjectFiles -ProjectRoot $projectRoot -RequirementsContent $script:singleDependencyRequirementsFixture -LockfileContent $script:singleDependencyLockfileBeforeUpdateFixture

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:UpdatedLockfileFixture = $script:singleDependencyLockfileAfterUpdateFixture

        Push-Location $script:repoRoot
        try {
            & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
        }
        finally {
            Pop-Location
        }

        $outputLines = Get-Content -Path $outputPath

        $outputLines | Should -Contain 'changed=true'
        $outputLines | Should -Contain "project_root=$projectRoot"
        $outputLines | Should -Contain "repository_root=$script:repoRoot"
        $outputLines | Should -Contain "lockfile_path=$(Join-Path $projectRoot 'psreq.lock.psd1')"
        $outputLines | Should -Contain 'base_branch=main'
        $outputLines | Should -Contain 'bump_branch_name=pslrm-bump/pocof'
        $outputLines | Should -Contain 'bump_commit_message=Bump pocof to 0.2.0'
        $outputLines | Should -Contain 'bump_pr_title=Bump pocof to 0.2.0'
        $outputLines | Should -Contain 'bump_pr_body=Automated dependency bump generated by Update-PSLResource. Updated pocof to 0.2.0.'
    }

    It 'falls back to GITHUB_REF_NAME when the current branch is unavailable' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-TestProjectFiles -ProjectRoot $projectRoot -RequirementsContent $script:singleDependencyRequirementsFixture -LockfileContent $script:singleDependencyLockfileAfterUpdateFixture

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $env:GITHUB_REF_NAME = 'feature/source-branch'
        $env:DEFAULT_BRANCH = 'main'
        $global:GitCurrentBranch = ''
        $global:UpdatedLockfileFixture = $script:singleDependencyLockfileAfterUpdateFixture

        Push-Location $script:repoRoot
        try {
            & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
        }
        finally {
            Pop-Location
        }

        Get-Content -Path $outputPath | Should -Contain 'base_branch=feature/source-branch'
    }

    It 'falls back to DEFAULT_BRANCH when git and GITHUB_REF_NAME cannot resolve the base branch' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-TestProjectFiles -ProjectRoot $projectRoot -RequirementsContent $script:singleDependencyRequirementsFixture -LockfileContent $script:singleDependencyLockfileAfterUpdateFixture

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $env:GITHUB_REF_NAME = ''
        $env:DEFAULT_BRANCH = 'main'
        $global:GitCurrentBranch = ''
        $global:UpdatedLockfileFixture = $script:singleDependencyLockfileAfterUpdateFixture

        Push-Location $script:repoRoot
        try {
            & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
        }
        finally {
            Pop-Location
        }

        Get-Content -Path $outputPath | Should -Contain 'base_branch=main'
    }

    It 'derives multi-dependency bump metadata when more than one direct dependency changes' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-TestProjectFiles -ProjectRoot $projectRoot -RequirementsContent @'
@{
    pocof = @{
        Repository = 'PSGallery'
    }
    'Get-GzipContent' = @{
        Repository = 'PSGallery'
    }
}
'@ -LockfileContent @'
@{
    pocof = @{
        Repository = 'PSGallery'
        Version = '0.1.0'
    }
    'Get-GzipContent' = @{
        Repository = 'PSGallery'
        Version = '0.3.0'
    }
}
'@

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:UpdatedLockfileFixture = @'
@{
    pocof = @{
        Repository = 'PSGallery'
        Version = '0.2.0'
    }
    'Get-GzipContent' = @{
        Repository = 'PSGallery'
        Version = '0.4.0'
    }
}
'@

        Push-Location $script:repoRoot
        try {
            & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
        }
        finally {
            Pop-Location
        }

        $outputLines = Get-Content -Path $outputPath

        $outputLines | Should -Contain 'changed=true'
        $outputLines | Should -Contain 'bump_branch_name=pslrm-bump/get-gzipcontent-pocof'
        $outputLines | Should -Contain 'bump_commit_message=Bump Get-GzipContent and 1 more dependencies'
        $outputLines | Should -Contain 'bump_pr_title=Bump Get-GzipContent and 1 more dependencies'
        $outputLines | Should -Contain 'bump_pr_body=Automated dependency bump generated by Update-PSLResource. Updated dependencies: Get-GzipContent 0.4.0, pocof 0.2.0.'
    }

    It 'fails when project root cannot be resolved' {
        $projectRoot = Join-Path $TestDrive 'missing-project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath

        Push-Location $script:repoRoot
        try {
            {
                & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
            } | Should -Throw 'Project root not found*'
        }
        finally {
            Pop-Location
        }
    }

    It 'fails when the base branch cannot be resolved' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-TestProjectFiles -ProjectRoot $projectRoot -RequirementsContent $script:singleDependencyRequirementsFixture -LockfileContent $script:singleDependencyLockfileAfterUpdateFixture

        $global:GitCurrentBranch = ''
        $env:DEFAULT_BRANCH = ''
        $env:GITHUB_REF_NAME = ''
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'github-output.txt'
        $global:UpdatedLockfileFixture = $script:singleDependencyLockfileAfterUpdateFixture

        Push-Location $script:repoRoot
        try {
            {
                & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
            } | Should -Throw 'Failed to resolve the base branch*'
        }
        finally {
            Pop-Location
        }
    }

    It 'fails when files other than the lockfile are modified' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-TestProjectFiles -ProjectRoot $projectRoot -RequirementsContent $script:singleDependencyRequirementsFixture -LockfileContent $script:singleDependencyLockfileBeforeUpdateFixture

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:UpdatedLockfileFixture = $script:singleDependencyLockfileAfterUpdateFixture
        $global:GitStatusLines = @(' M unexpected.txt')

        Push-Location $script:repoRoot
        try {
            {
                & $script:scriptPath -ProjectPath $projectRoot -TargetPowerShellEdition 'core'
            } | Should -Throw 'Unexpected changes detected outside psreq.lock.psd1*'
        }
        finally {
            Pop-Location
        }
    }
}