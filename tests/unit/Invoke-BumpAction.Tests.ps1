BeforeAll {
    $repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $scriptPath = Join-Path $repoRoot 'scripts/Invoke-BumpAction.ps1'
    $fixtureProjectPath = 'tests/fixtures/basic-project'
}

Describe 'Invoke-BumpAction' {
    BeforeEach {
        $script:originalGhToken = $env:GH_TOKEN
        $script:originalGithubOutput = $env:GITHUB_OUTPUT
    }

    AfterEach {
        if ($null -eq $script:originalGhToken) {
            Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        }
        else {
            $env:GH_TOKEN = $script:originalGhToken
        }

        if ($null -eq $script:originalGithubOutput) {
            Remove-Item Env:GITHUB_OUTPUT -ErrorAction SilentlyContinue
        }
        else {
            $env:GITHUB_OUTPUT = $script:originalGithubOutput
        }
    }

    It 'writes changed=false for the skeleton action output' {
        $outputPath = Join-Path $TestDrive 'github-output.txt'
        $env:GH_TOKEN = 'test-token'
        $env:GITHUB_OUTPUT = $outputPath

        Push-Location $repoRoot
        try {
            & $scriptPath -ProjectPath $fixtureProjectPath -TargetPowerShellEdition 'core'
        }
        finally {
            Pop-Location
        }

        Get-Content -Path $outputPath | Should -Contain 'changed=false'
    }

    It 'fails fast when GH_TOKEN is missing' {
        $outputPath = Join-Path $TestDrive 'github-output.txt'
        Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
        $env:GITHUB_OUTPUT = $outputPath

        Push-Location $repoRoot
        try {
            {
                & $scriptPath -ProjectPath $fixtureProjectPath -TargetPowerShellEdition 'core'
            } | Should -Throw 'GH_TOKEN is required*'
        }
        finally {
            Pop-Location
        }
    }
}