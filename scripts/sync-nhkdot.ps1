param(
    [string]$RepoPath = (Split-Path -Parent $PSScriptRoot),
    [int]$MinimumDays = 5,
    [int]$NetworkRetries = 4,
    [int]$RetryDelaySeconds = 20
)

$ErrorActionPreference = "Stop"

$stateDirectory = Join-Path $env:LOCALAPPDATA "NHK-DOT-AutoSync"
$lastSuccessFile = Join-Path $stateDirectory "last-success.txt"
$logFile = Join-Path $stateDirectory "sync.log"

New-Item -ItemType Directory -Path $stateDirectory -Force | Out-Null

function Write-SyncLog {
    param([string]$Message)

    $line = "{0} {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
}

function Invoke-Git {
    param([Parameter(Mandatory)][string[]]$Arguments)

    Write-SyncLog ("git " + ($Arguments -join " "))
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git -C $RepoPath @Arguments 2>&1
        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    foreach ($line in $output) {
        Write-SyncLog ([string]$line)
    }
    if ($exitCode -ne 0) {
        throw "git command failed with exit code ${exitCode}: git $($Arguments -join ' ')"
    }
    return $output
}

try {
    Write-SyncLog "Auto-sync check started for $RepoPath"

    if (-not (Test-Path -LiteralPath (Join-Path $RepoPath ".git"))) {
        throw "Not a Git repository: $RepoPath"
    }

    if (Test-Path -LiteralPath $lastSuccessFile) {
        $lastSuccessText = (Get-Content -LiteralPath $lastSuccessFile -Raw).Trim()
        $lastSuccess = [DateTimeOffset]::ParseExact(
            $lastSuccessText,
            "o",
            [Globalization.CultureInfo]::InvariantCulture
        )
        $elapsed = [DateTimeOffset]::Now - $lastSuccess
        if ($elapsed.TotalDays -lt $MinimumDays) {
            Write-SyncLog ("Skipped: last successful sync was {0:N2} days ago." -f $elapsed.TotalDays)
            exit 0
        }
    }

    $fetchSucceeded = $false
    for ($attempt = 1; $attempt -le $NetworkRetries; $attempt++) {
        try {
            Invoke-Git -Arguments @("fetch", "origin", "main") | Out-Null
            $fetchSucceeded = $true
            break
        }
        catch {
            Write-SyncLog "Fetch attempt $attempt of $NetworkRetries failed: $($_.Exception.Message)"
            if ($attempt -lt $NetworkRetries) {
                Start-Sleep -Seconds $RetryDelaySeconds
            }
        }
    }
    if (-not $fetchSucceeded) {
        throw "Network or authentication was unavailable after $NetworkRetries attempts."
    }

    $status = @(& git -C $RepoPath status --porcelain=v1)
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to inspect the repository status."
    }

    if ($status.Count -gt 0) {
        Invoke-Git -Arguments @("add", "--all") | Out-Null
        $commitMessage = "chore: automatic local sync {0}" -f (Get-Date -Format "yyyy-MM-dd")
        Invoke-Git -Arguments @("commit", "-m", $commitMessage) | Out-Null
    }
    else {
        Write-SyncLog "No local changes to commit."
    }

    try {
        Invoke-Git -Arguments @("pull", "--rebase", "origin", "main") | Out-Null
    }
    catch {
        Write-SyncLog "Pull/rebase failed; attempting to restore the pre-rebase state."
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & git -C $RepoPath rebase --abort 2>&1 | ForEach-Object { Write-SyncLog ([string]$_) }
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        throw
    }

    Invoke-Git -Arguments @("push", "origin", "main") | Out-Null

    [DateTimeOffset]::Now.ToString("o") | Set-Content -LiteralPath $lastSuccessFile -Encoding ASCII
    Write-SyncLog "Auto-sync completed successfully."
    exit 0
}
catch {
    Write-SyncLog "Auto-sync failed: $($_.Exception.Message)"
    exit 1
}
