BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-BumpAction.ps1'
    $script:lockfilePester570 = "@{`n    Pester = @{`n        Repository = 'PSGallery'`n        Version = '5.7.0'`n    }`n}"
    $script:lockfilePester571 = "@{`n    Pester = @{`n        Repository = 'PSGallery'`n        Version = '5.7.1'`n    }`n}"
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
        $global:SimulatedLockfileContent = $null

        function global:Update-PSLResource {
            param(
                [string] $Path
            )

            $global:UpdateCalls.Add([pscustomobject]@{
                    Path = $Path
                })

            if ($null -ne $global:SimulatedLockfileContent) {
                $lockfilePath = Join-Path $Path 'psreq.lock.psd1'
                Set-Content -LiteralPath $lockfilePath -Value $global:SimulatedLockfileContent -NoNewline
            }
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

        foreach ($functionName in 'Update-PSLResource', 'git') {
            Remove-Item "Function:\global:$functionName" -ErrorAction SilentlyContinue
        }

        foreach ($variableName in 'UpdateCalls', 'GitRepositoryRoot', 'GitCurrentBranch', 'GitStatusLines', 'SimulatedLockfileContent') {
            Remove-Item "Variable:\global:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'writes changed=false when lockfile content is unchanged' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.psd1') -Value "@{`n    Pester = @{`n        Repository = 'PSGallery'`n    }`n}" -NoNewline
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value $script:lockfilePester571 -NoNewline

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:SimulatedLockfileContent = $script:lockfilePester571

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
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.psd1') -Value "@{`n    Pester = @{`n        Repository = 'PSGallery'`n    }`n}" -NoNewline
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value $script:lockfilePester571 -NoNewline

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        $env:GITHUB_OUTPUT = $outputPath
        $global:SimulatedLockfileContent = $script:lockfilePester571

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
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.psd1') -Value "@{`n    Pester = @{`n        Repository = 'PSGallery'`n    }`n}" -NoNewline
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value $script:lockfilePester570 -NoNewline

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:SimulatedLockfileContent = $script:lockfilePester571

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
        $outputLines | Should -Contain 'bump_branch_name=pslrm-bump/pester'
        $outputLines | Should -Contain 'bump_commit_message=Bump Pester to 5.7.1'
        $outputLines | Should -Contain 'bump_pr_title=Bump Pester to 5.7.1'
        $outputLines | Should -Contain 'bump_pr_body=Automated dependency bump generated by Update-PSLResource. Updated Pester to 5.7.1.'
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
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.psd1') -Value "@{`n    Pester = @{`n        Repository = 'PSGallery'`n    }`n}" -NoNewline
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value $script:lockfilePester571 -NoNewline

        $global:GitCurrentBranch = ''
        $env:DEFAULT_BRANCH = ''
        $env:GITHUB_REF_NAME = ''
        $env:GITHUB_OUTPUT = Join-Path $TestDrive 'github-output.txt'
        $global:SimulatedLockfileContent = $script:lockfilePester571

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
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.psd1') -Value "@{`n    Pester = @{`n        Repository = 'PSGallery'`n    }`n}" -NoNewline
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value $script:lockfilePester570 -NoNewline

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:SimulatedLockfileContent = $script:lockfilePester571
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