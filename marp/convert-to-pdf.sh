#!/usr/bin/env zsh

# Convert Marp markdown files to PDF in parallel.
#
# By default, only Marp markdown files that have uncommitted changes
# (staged, unstaged, or untracked) are converted.
#
# All Marp markdown files are converted in either of these cases:
#   - No markdown files have uncommitted changes
#   - Any file inside the marp/ folder (theme CSS, engine.js, etc.) has
#     uncommitted changes — a change there can affect every PDF
cd "$(dirname "$(dirname "${(%):-%x}")")"

# Helper: collect all Marp markdown files in the repository
collect_all_marp_files() {
  local -a files
  files=()
  while IFS= read -r file; do
    files+=("$file")
  done < <(find . -name node_modules -prune -o -name .github -prune -o -name "*.md" -type f -print0 | xargs -0 -P 12 grep -l "marp: true" 2>/dev/null)
  printf '%s\n' "${files[@]}"
}

# Helper: list uncommitted file paths (staged, unstaged, untracked) relative to repo root
list_changed_paths() {
  git status --porcelain=v1 -z --untracked-files=all 2>/dev/null | \
    python3 -c '
import sys
data = sys.stdin.buffer.read()
i = 0
while i < len(data):
    # Each record: "XY <path>\0" (and for renames: "XY <new>\0<old>\0")
    end = data.find(b"\0", i)
    if end == -1:
        break
    record = data[i:end].decode("utf-8", errors="replace")
    i = end + 1
    if len(record) < 4:
        continue
    xy = record[:2]
    path = record[3:]
    print(path)
    # If rename/copy, skip the old-name entry that follows
    if xy[0] in ("R", "C") or xy[1] in ("R", "C"):
        end2 = data.find(b"\0", i)
        if end2 != -1:
            i = end2 + 1
'
}

# Decide which Marp markdown files to convert
marp_files=()
mode="changed"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not inside a git work tree — converting all Marp markdown files."
  mode="all"
else
  changed_paths=()
  while IFS= read -r p; do
    [[ -n "$p" ]] && changed_paths+=("$p")
  done < <(list_changed_paths)

  changed_md=()
  marp_folder_changed=0
  for p in "${changed_paths[@]}"; do
    case "$p" in
      marp/*) marp_folder_changed=1 ;;
    esac
    if [[ "$p" == *.md ]]; then
      # Only Marp markdown files (must contain `marp: true`)
      if [[ -f "$p" ]] && grep -q "marp: true" "$p" 2>/dev/null; then
        changed_md+=("$p")
      fi
    fi
  done

  if (( marp_folder_changed )); then
    echo "Detected uncommitted changes in marp/ — converting all Marp markdown files."
    mode="all"
  elif (( ${#changed_md[@]} == 0 )); then
    echo "No uncommitted Marp markdown changes — converting all Marp markdown files."
    mode="all"
  else
    echo "Found ${#changed_md[@]} uncommitted Marp markdown file(s) — converting only those."
    # Normalize paths to start with ./ to match the all-files form
    for f in "${changed_md[@]}"; do
      [[ "$f" == ./* ]] || f="./$f"
      marp_files+=("$f")
    done
  fi
fi

if [[ "$mode" == "all" ]]; then
  while IFS= read -r file; do
    [[ -n "$file" ]] && marp_files+=("$file")
  done < <(collect_all_marp_files)
fi

# Sort the files alphabetically (and de-duplicate)
marp_files=("${(@on)marp_files}")
typeset -U marp_files

total=${#marp_files[@]}

if (( total == 0 )); then
  echo "No Marp markdown files to convert."
  exit 0
fi

MAX_PARALLEL=12
printf "Converting %d Marp markdown file(s) in parallel (max %d concurrent)...\n\n" "$total" "$MAX_PARALLEL"

# Counter for completed files
completed_lock="/tmp/marp_convert_$$"
echo "0" > "$completed_lock"

# Semaphore via FIFO: pre-fill with MAX_PARALLEL tokens. Each job reads a token
# before starting and writes one back when done. This bounds concurrency hard,
# regardless of how `jobs -r -p` reports state.
sem_fifo="/tmp/marp_convert_sem_$$"
mkfifo "$sem_fifo"
# Open FD 9 for read+write so writers don't block when no reader is waiting
exec 9<>"$sem_fifo"
rm "$sem_fifo"
for ((i = 0; i < MAX_PARALLEL; i++)); do
  echo >&9
done

# Convert files in parallel, bounded by the semaphore
for mdfile in "${marp_files[@]}"; do
  # Acquire a token (blocks until one is available)
  read -u 9

  (
    dir=$(dirname "$mdfile")
    filename=$(basename "$mdfile")
    depth=$(echo "$dir" | tr -cd '/' | wc -c)
    theme_path=$(printf '../%.0s' $(seq 1 $depth))marp/oblicum-marp-theme.css
    lab_theme_path=$(printf '../%.0s' $(seq 1 $depth))marp/oblicum-marp-lab-theme.css
    engine_path=$(printf '../%.0s' $(seq 1 $depth))marp/engine.js

    echo "▶ Starting PDF: $mdfile"

    # Convert to PDF - suppress marp-cli output
    if (cd "$dir" && npx @marp-team/marp-cli --engine "$engine_path" --theme-set "$theme_path" "$lab_theme_path" --allow-local-files --pdf "$filename" < /dev/null) &>/dev/null; then
      result="✓ Completed"
    else
      result="✗ Failed"
    fi

    # Update counter with simple file-based locking (macOS compatible)
    lockfile="$completed_lock.lock"
    while ! mkdir "$lockfile" 2>/dev/null; do
      sleep 0.01
    done
    current=$(($(cat "$completed_lock") + 1))
    echo "$current" > "$completed_lock"
    rmdir "$lockfile"
    echo "  $result ($current/$total): $dir/${filename%.md}.pdf"

    # Release token
    echo >&9
  ) &
done

# Wait for all remaining jobs to complete
wait

# Close semaphore and clean up
exec 9>&-
rm -f "$completed_lock"
rmdir "$completed_lock.lock" 2>/dev/null

echo ""
echo "Conversion complete! Processed $total files."
