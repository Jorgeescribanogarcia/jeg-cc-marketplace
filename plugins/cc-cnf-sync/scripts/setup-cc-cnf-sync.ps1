# setup-cc-cnf-sync.ps1
# Configures the GitHub MCP for Claude Code with a VALIDATED Personal Access Token.
# Called automatically by /setup.
#
# Runs headlessly (no interactive prompt that would hang inside Claude Code):
#   1. Token resolved from -Token, then the GITHUB_PERSONAL_ACCESS_TOKEN user env var.
#   2. Token is validated against the GitHub API (https://api.github.com/user).
#   3. If missing OR rejected by GitHub, a `githubToken.bat` helper is written to the
#      current folder and the script exits with code 2 so /setup can guide the user.
#   4. Only a VALID token gets the GitHub MCP (re)installed.

param(
    [string]$Token = ""
)

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  cc-cnf-sync - Setup" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# ── Helper: validate a token against the GitHub API ───────────────
# Returns the authenticated @login on success, or $null on any failure
# (empty token, bad credentials, missing 'repo' scope, network error).
function Test-GitHubToken {
    param([string]$T)
    if ([string]::IsNullOrWhiteSpace($T)) { return $null }
    try {
        $u = Invoke-RestMethod -Uri "https://api.github.com/user" `
            -Headers @{
                Authorization  = "token $T"
                "User-Agent"   = "cc-cnf-sync"
                Accept         = "application/vnd.github+json"
            } -Method Get -TimeoutSec 20 -ErrorAction Stop
        return $u.login
    } catch {
        return $null
    }
}

# ── Helper: write the token-entry assistant (keeps the secret out of chat) ──
function Write-TokenHelper {
    $workspacePath = (Get-Location).Path
    $batPath = Join-Path $workspacePath "githubToken.bat"
    $bat = @'
@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "Write-Host '================================================' -ForegroundColor Cyan; Write-Host '  GITHUB TOKEN - cc-cnf-sync' -ForegroundColor Cyan; Write-Host '================================================' -ForegroundColor Cyan; Write-Host ''; Write-Host 'Create a token with the ''repo'' scope at:' -ForegroundColor Gray; Write-Host 'https://github.com/settings/tokens' -ForegroundColor Cyan; Write-Host ''; $t = Read-Host 'Paste your GitHub token'; if ([string]::IsNullOrWhiteSpace($t)) { Write-Host 'ERROR: no token entered.' -ForegroundColor Red; Start-Sleep -s 3; exit }; [System.Environment]::SetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', $t, 'User'); Write-Host ''; Write-Host 'Done! Token saved for your user account.' -ForegroundColor Green; Write-Host 'Go back to Claude Code and run /setup again.' -ForegroundColor Yellow; Write-Host ''; Read-Host 'Press Enter to close'"
'@
    Set-Content -Path $batPath -Value $bat -Encoding ASCII -Force
    return $batPath
}

# ── STEP 1: resolve the token (param → user env var) ──────────────
Write-Host "STEP 1/3 - Resolving GitHub token..." -ForegroundColor Yellow
if ([string]::IsNullOrWhiteSpace($Token)) {
    $envUser = [System.Environment]::GetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', 'User')
    if (-not [string]::IsNullOrWhiteSpace($envUser)) {
        $Token = $envUser
        Write-Host "  Found GITHUB_PERSONAL_ACCESS_TOKEN in the user environment." -ForegroundColor DarkGray
    }
}
if ([string]::IsNullOrWhiteSpace($Token) -and -not [string]::IsNullOrWhiteSpace($env:GITHUB_PERSONAL_ACCESS_TOKEN)) {
    $Token = $env:GITHUB_PERSONAL_ACCESS_TOKEN
}
Write-Host ""

# ── STEP 2: validate the token before touching anything ───────────
Write-Host "STEP 2/3 - Validating token with GitHub..." -ForegroundColor Yellow
$login = Test-GitHubToken $Token
if (-not $login) {
    $bat = Write-TokenHelper
    if ([string]::IsNullOrWhiteSpace($Token)) {
        Write-Host "  [REQUIRED] No GitHub token found." -ForegroundColor Red
    } else {
        Write-Host "  [INVALID] GitHub rejected the stored token (bad credentials or missing 'repo' scope)." -ForegroundColor Red
    }
    Write-Host "  A helper was created at:" -ForegroundColor Yellow
    Write-Host "    $bat" -ForegroundColor White
    Write-Host "  Run it, paste a VALID token (scope 'repo'), then run /setup again." -ForegroundColor Yellow
    exit 2
}
Write-Host "  Token validated - authenticated as @$login." -ForegroundColor Green
Write-Host ""

# ── STEP 3: persist token + (re)install the GitHub MCP ────────────
Write-Host "STEP 3/3 - Installing GitHub MCP..." -ForegroundColor Yellow

# Persist so future /setup runs find it without asking again.
[System.Environment]::SetEnvironmentVariable('GITHUB_PERSONAL_ACCESS_TOKEN', $Token, 'User')

# Clean any previous (possibly stale) github MCP, then add fresh.
$MCP_LIST = claude mcp list 2>&1
if ($MCP_LIST -match "github") {
    claude mcp remove github --scope user 2>&1 | Out-Null
    Write-Host "  Removed previous GitHub MCP." -ForegroundColor DarkGray
}

claude mcp add github npx @modelcontextprotocol/server-github --env "GITHUB_PERSONAL_ACCESS_TOKEN=$Token" --scope user
if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERROR: Could not install GitHub MCP." -ForegroundColor Red
    exit 1
}
Write-Host "  GitHub MCP installed successfully." -ForegroundColor Green

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Setup complete! Connected as @$login" -ForegroundColor Green
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "IMPORTANT: restart Claude Code so the MCP reconnects with the new token." -ForegroundColor Yellow
Write-Host "Then you can use:" -ForegroundColor White
Write-Host "  /backup  - Upload your config to GitHub" -ForegroundColor Cyan
Write-Host "  /restore - Restore your config from GitHub" -ForegroundColor Cyan
Write-Host "  /status  - Show status and last backup date" -ForegroundColor Cyan
Write-Host ""
exit 0
