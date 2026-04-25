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