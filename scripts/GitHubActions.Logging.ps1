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