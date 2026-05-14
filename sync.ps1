#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $RepoDir

# Verify we are inside a git repo
try { git rev-parse --is-inside-work-tree 2>$null | Out-Null }
catch {
    Write-Error "ERROR: not inside a git repository."
    exit 1
}

$remote = git remote get-url origin 2>$null
if (-not $remote) {
    Write-Error "ERROR: no remote 'origin' configured."
    exit 1
}

# Stage and commit any local changes before syncing
$status = git status --porcelain
if ($status) {
    Write-Host ">>> Committing local changes..."
    git add -A
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "sync: local changes at $timestamp"
}

Write-Host ">>> Fetching from origin..."
git fetch origin

$local  = git rev-parse HEAD
$remote = $null
foreach ($branch in @('origin/main', 'origin/master')) {
    $r = git rev-parse $branch 2>$null
    if ($r) { $remote = $r; break }
}
if (-not $remote) {
    Write-Error "ERROR: could not resolve remote branch (origin/main or origin/master)."
    exit 1
}

$base = git merge-base HEAD $remote

if ($local -eq $remote) {
    Write-Host ">>> Already up to date."
    exit 0
}

if ($base -eq $remote) {
    # Remote is behind local — push
    Write-Host ">>> Remote is behind. Pushing local changes..."
    git push origin HEAD
}
elseif ($base -eq $local) {
    # Local is behind remote — fast-forward
    Write-Host ">>> Local is behind. Pulling remote changes..."
    git merge --ff-only $remote
}
else {
    # Diverged — merge and resolve conflicts by recency
    Write-Host ">>> Branches diverged. Merging with recency priority..."

    git merge --no-commit --no-ff $remote
    if ($LASTEXITCODE -ne 0) {
        # Merge left conflicts — resolve them
    }

    $conflicted = git diff --cached --name-only --diff-filter=U 2>$null
    if ($conflicted) {
        $lines = $conflicted -split "`n" | Where-Object { $_ -ne '' }
        Write-Host ">>> Resolving $($lines.Count) conflicted file(s) by recency..."
        $backupTag = Get-Date -Format "yyyyMMdd_HHmmss"

        foreach ($file in $lines) {
            $localTime  = git log -1 --format="%ct" HEAD -- $file 2>$null
            $remoteTime = git log -1 --format="%ct" $remote -- $file 2>$null
            if (-not $localTime)  { $localTime  = 0 }
            if (-not $remoteTime) { $remoteTime = 0 }

            # Back up the side being discarded before overwriting
            $backupPath = "$file.backup_$backupTag"
            if ([long]$remoteTime -ge [long]$localTime) {
                Write-Host "    $file → keeping remote version (newer or equal)"
                # Save current local content from git before checking out theirs
                git show HEAD:"$file" 2>$null | Set-Content -Encoding UTF8 "$backupPath"
                Write-Host "      backup: $backupPath"
                git checkout --theirs -- $file
            }
            else {
                Write-Host "    $file → keeping local version (newer)"
                # Save remote content before discarding it
                git show "${remote}:${file}" 2>$null | Set-Content -Encoding UTF8 "$backupPath"
                Write-Host "      backup: $backupPath"
                git checkout --ours -- $file
            }
            git add -- $file
        }
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    git commit -m "sync: merge with recency resolution at $timestamp" 2>$null
    Write-Host ">>> Pushing merged result..."
    git push origin HEAD
}

Write-Host ">>> Sync complete."
