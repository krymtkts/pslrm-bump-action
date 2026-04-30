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

function Get-NonEmptyStringLines {
    param(
        [AllowNull()]
        [object[]] $Lines
    )

    , @(
        foreach ($line in $Lines) {
            $text = [string] $line
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                $text
            }
        }
    )
}

function run {
    param(
        [Parameter(ValueFromRemainingArguments)]
        [object[]] $Invocation
    )

    if ($Invocation.Count -eq 0) {
        throw 'A command name is required.'
    }

    $commandName = [string] $Invocation[0]
    $arguments = if ($Invocation.Count -eq 1) { @() } else { $Invocation[1..($Invocation.Count - 1)] }

    $output = @(& $commandName @arguments 2>&1)
    $exitCode = $LASTEXITCODE

    [pscustomobject]@{
        ExitCode = $exitCode
        Output = $output
    }
}

function runx {
    param(
        [Parameter(Mandatory, Position = 0)]
        [string] $FailureMessage,

        [Parameter(ValueFromRemainingArguments, Position = 1)]
        [object[]] $Invocation
    )

    $result = run @Invocation
    if ($result.ExitCode -eq 0) {
        return $result
    }

    $details = Get-NonEmptyStringLines -Lines $result.Output
    if ($details.Count -gt 0) {
        throw "$FailureMessage`n$($details -join "`n")"
    }

    throw $FailureMessage
}

function Write-GitOutput {
    param(
        [AllowNull()]
        [object[]] $Lines
    )

    foreach ($text in (Get-NonEmptyStringLines -Lines $Lines)) {
        Write-Host $text
    }
}
