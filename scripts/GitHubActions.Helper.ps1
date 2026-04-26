function Start-LogGroup {
    param(
        [Parameter(Mandatory)]
        [string] $Title
    )

    Write-Host "::group::${Title}"
}

function Stop-LogGroup {
    Write-Host '::endgroup::'
}

function Invoke-InLogGroup {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $Title,

        [Parameter(Mandatory, Position = 1)]
        [scriptblock] $ScriptBlock
    )

    Start-LogGroup -Title $Title
    try {
        & $ScriptBlock
    }
    finally {
        Stop-LogGroup
    }
}

function Write-GitHubAnnotation {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Notice', 'Error', 'Warning')]
        [string] $Label,

        [Parameter(Mandatory)]
        [string] $Message
    )

    Write-Host "::${Label}::$Message"
}

function Get-RequiredEnvironmentVariable {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Purpose
    )

    $value = [System.Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$Name is required to $Purpose."
    }

    $value
}

function Set-ActionOutput {
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($env:GITHUB_OUTPUT)) {
        Write-Host "Output $Name=$Value"
    }
    else {
        "${Name}=${Value}" | Out-File -FilePath $env:GITHUB_OUTPUT -Encoding utf8 -Append
    }
}