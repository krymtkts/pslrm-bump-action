BeforeAll {
    $script:repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $script:scriptPath = Join-Path $script:repoRoot 'scripts/Invoke-BumpAction.ps1'
}

Describe 'Invoke-BumpAction' {
    BeforeEach {
        $script:originalGithubOutput = $env:GITHUB_OUTPUT
        $global:UpdateCalls = [System.Collections.Generic.List[object]]::new()
        $global:GitRepositoryRoot = $script:repoRoot
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

            if ($Arguments -contains 'status') {
                $global:GitStatusLines
                return
            }
        }
    }

    AfterEach {
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue

        if ($null -eq $script:originalGithubOutput) {
            Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_OUTPUT = $script:originalGithubOutput
        }

        foreach ($functionName in 'Update-PSLResource', 'git') {
            Remove-Item "Function:\global:$functionName" -ErrorAction SilentlyContinue
        }

        foreach ($variableName in 'UpdateCalls', 'GitRepositoryRoot', 'GitStatusLines', 'SimulatedLockfileContent') {
            Remove-Item "Variable:\global:$variableName" -ErrorAction SilentlyContinue
        }
    }

    It 'writes changed=false when lockfile content is unchanged' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.psd1') -Value "@{`n    Pester = @{`n        Repository = 'PSGallery'`n    }`n}" -NoNewline
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value 'unchanged-lockfile' -NoNewline

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:SimulatedLockfileContent = 'unchanged-lockfile'

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
        $global:UpdateCalls.Count | Should -Be 1
        $global:UpdateCalls[0].Path | Should -Be $projectRoot
    }

    It 'does not require GH_TOKEN for lockfile update and output generation' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.psd1') -Value "@{`n    Pester = @{`n        Repository = 'PSGallery'`n    }`n}" -NoNewline
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value 'unchanged-lockfile' -NoNewline

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        $env:GITHUB_OUTPUT = $outputPath
        $global:SimulatedLockfileContent = 'unchanged-lockfile'

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
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value 'old-lockfile' -NoNewline

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:SimulatedLockfileContent = 'new-lockfile'

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

    It 'fails when files other than the lockfile are modified' {
        $projectRoot = Join-Path $TestDrive 'project'
        New-Item -ItemType Directory -Path $projectRoot -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.psd1') -Value "@{`n    Pester = @{`n        Repository = 'PSGallery'`n    }`n}" -NoNewline
        Set-Content -LiteralPath (Join-Path $projectRoot 'psreq.lock.psd1') -Value 'old-lockfile' -NoNewline

        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GITHUB_OUTPUT = $outputPath
        $global:SimulatedLockfileContent = 'new-lockfile'
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