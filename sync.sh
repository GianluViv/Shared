#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_DIR"

if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "ERROR: not inside a git repository." >&2
  exit 1
fi

if ! git remote get-url origin &>/dev/null; then
  echo "ERROR: no remote 'origin' configured." >&2
  exit 1
fi

# Stage and commit any local changes before syncing
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo ">>> Committing local changes..."
  git add -A
  git commit -m "sync: local changes at $(date '+%Y-%m-%d %H:%M:%S')"
fi

echo ">>> Fetching from origin..."
git fetch origin

LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/main 2>/dev/null || git rev-parse origin/master 2>/dev/null)
BASE=$(git merge-base HEAD "$REMOTE")

if [ "$LOCAL" = "$REMOTE" ]; then
  echo ">>> Already up to date."
  exit 0
fi

if [ "$BASE" = "$REMOTE" ]; then
  # Remote is behind local — push
  echo ">>> Remote is behind. Pushing local changes..."
  git push origin HEAD
elif [ "$BASE" = "$LOCAL" ]; then
  # Local is behind remote — fast-forward
  echo ">>> Local is behind. Pulling remote changes..."
  git merge --ff-only "$REMOTE"
else
  # Diverged — merge with "newer wins" strategy using merge-ours/theirs per file
  echo ">>> Branches diverged. Merging with recency priority..."

  # Get the list of files that differ between local and remote
  CONFLICT_FILES=$(git diff --name-only HEAD "$REMOTE" 2>/dev/null || true)

  # Perform merge, preferring remote changes but then resolving per-file by mtime
  git merge --no-commit --no-ff "$REMOTE" || true

  # Resolve conflicts: compare commit timestamps and pick the newer side
  LOCAL_TIME=$(git log -1 --format="%ct" HEAD)
  REMOTE_TIME=$(git log -1 --format="%ct" "$REMOTE")

  if git diff --cached --name-only | grep -q ""; then
    CONFLICTED=$(git diff --cached --name-only --diff-filter=U 2>/dev/null || true)
    if [ -n "$CONFLICTED" ]; then
      echo ">>> Resolving $(echo "$CONFLICTED" | wc -l | tr -d ' ') conflicted file(s) by recency..."
      while IFS= read -r file; do
        # Compare last-modified times in each branch for this specific file
        LOCAL_FILE_TIME=$(git log -1 --format="%ct" HEAD -- "$file" 2>/dev/null || echo 0)
        REMOTE_FILE_TIME=$(git log -1 --format="%ct" "$REMOTE" -- "$file" 2>/dev/null || echo 0)

        if [ "$REMOTE_FILE_TIME" -ge "$LOCAL_FILE_TIME" ]; then
          echo "    $file → keeping remote version (newer or equal)"
          git checkout --theirs -- "$file"
        else
          echo "    $file → keeping local version (newer)"
          git checkout --ours -- "$file"
        fi
        git add -- "$file"
      done <<< "$CONFLICTED"
    fi
  fi

  git commit -m "sync: merge with recency resolution at $(date '+%Y-%m-%d %H:%M:%S')" || true
  echo ">>> Pushing merged result..."
  git push origin HEAD
fi

echo ">>> Sync complete."
