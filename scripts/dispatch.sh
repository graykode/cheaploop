#!/usr/bin/env bash

set -u
set -o pipefail

usage() {
  printf '%s\n' "usage: scripts/dispatch.sh -t <task-id> [-y build|research|verify] [-m <model>] [-e low|medium|high|xhigh] [-p <prompt-file>]" >&2
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

require_command codex
require_command python3

if [ "${CHEAPLOOP_SNAPSHOT:-}" != "1" ]; then
  launch_workdir="$(pwd)" || die "cannot resolve launch workdir"
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || die "cannot resolve script dir"
  script_root="$(cd "$script_dir/.." && pwd)" || die "cannot resolve script root"
  export CHEAPLOOP_ROOT="$script_root"
  export CHEAPLOOP_WORKDIR="$launch_workdir"

  snapshot_path="$(mktemp "${TMPDIR:-/tmp}/cheaploop-dispatch.XXXXXX")" || die "cannot create dispatch snapshot"
  cp "${BASH_SOURCE[0]}" "$snapshot_path" || {
    rm -f "$snapshot_path"
    die "cannot copy dispatch snapshot"
  }
  chmod +x "$snapshot_path" || {
    rm -f "$snapshot_path"
    die "cannot make dispatch snapshot executable"
  }
  export CHEAPLOOP_SNAPSHOT=1
  export CHEAPLOOP_SNAPSHOT_PATH="$snapshot_path"
  exec "$snapshot_path" "$@"
  die "cannot exec dispatch snapshot"
fi

prompt_tmp=""
lock_dir=""
lock_acquired=0

cleanup() {
  if [ -n "${prompt_tmp:-}" ]; then
    rm -f "$prompt_tmp"
  fi
  if [ "${lock_acquired:-0}" -eq 1 ] && [ -n "${lock_dir:-}" ] && [ -d "$lock_dir" ]; then
    rm -rf "$lock_dir"
  fi
  if [ -n "${CHEAPLOOP_SNAPSHOT_PATH:-}" ]; then
    rm -f "$CHEAPLOOP_SNAPSHOT_PATH"
  fi
}

on_signal() {
  local signal_number=$1
  cleanup
  exit $((128 + signal_number))
}

trap cleanup EXIT
trap 'on_signal 1' HUP
trap 'on_signal 2' INT
trap 'on_signal 15' TERM

task_id=""
task_type="build"
model=""
effort=""
prompt_file=""
start_dir="$(pwd)"

while getopts ":t:y:m:e:p:" opt; do
  case "$opt" in
    t) task_id="$OPTARG" ;;
    y) task_type="$OPTARG" ;;
    m) model="$OPTARG" ;;
    e) effort="$OPTARG" ;;
    p) prompt_file="$OPTARG" ;;
    :) die "-$OPTARG requires a value" ;;
    \?) die "unknown option -$OPTARG" ;;
  esac
done
shift $((OPTIND - 1))

[ "$#" -eq 0 ] || die "unexpected argument: $1"
if [ -z "$task_id" ]; then
  usage
  die "-t <task-id> is required"
fi

case "$task_id" in
  "."|".."|*/*) die "invalid task id: must match ^[A-Za-z0-9][A-Za-z0-9_-]*-[0-9]{3}$; '.', '..', and '/' are not allowed" ;;
esac
if ! [[ "$task_id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*-[0-9][0-9][0-9]$ ]]; then
  die "invalid task id: must match ^[A-Za-z0-9][A-Za-z0-9_-]*-[0-9]{3}$"
fi

case "$task_type" in
  build) sandbox="workspace-write" ;;
  research|verify) sandbox="read-only" ;;
  *) die "task type must be build, research, or verify" ;;
esac

case "$effort" in
  ""|low|medium|high|xhigh) ;;
  *) die "effort must be low, medium, high, or xhigh" ;;
esac

if [ -n "$prompt_file" ]; then
  case "$prompt_file" in /*) ;; *) prompt_file="$start_dir/$prompt_file" ;; esac
  [ -f "$prompt_file" ] && [ -r "$prompt_file" ] || die "prompt file not readable: $prompt_file"
fi

if [ -n "${CHEAPLOOP_ROOT:-}" ]; then
  script_root="$CHEAPLOOP_ROOT"
else
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || die "cannot resolve script dir"
  script_root="$(cd "$script_dir/.." && pwd)" || die "cannot resolve script root"
fi

if [ -n "${CHEAPLOOP_WORKDIR:-}" ]; then
  workdir="$CHEAPLOOP_WORKDIR"
else
  workdir="$(pwd)" || die "cannot resolve workdir"
fi
cd "$workdir" || die "cannot enter workdir"

result_dir=".cheaploop/results/$task_id"
raw_log="$result_dir/raw.log"
result_json="$result_dir/result.json"
codex_exit="$result_dir/codex_exit"

mkdir -p "$result_dir" || die "cannot create result dir: $result_dir"
lock_dir="$result_dir/.lock"
if ! mkdir "$lock_dir" 2>/dev/null; then
  die "task id already running: $task_id"
fi
lock_acquired=1

if [ -e "$raw_log" ]; then
  prev_dir=""
  while :; do
    prev_dir="$result_dir/prev-$(date +%s)"
    if mkdir "$prev_dir" 2>/dev/null; then
      break
    fi
    sleep 1
  done
  [ ! -e "$raw_log" ] || mv "$raw_log" "$prev_dir/" || die "cannot rotate previous raw.log"
  [ ! -e "$result_json" ] || mv "$result_json" "$prev_dir/" || die "cannot rotate previous result.json"
  [ ! -e "$codex_exit" ] || mv "$codex_exit" "$prev_dir/" || die "cannot rotate previous codex_exit"
else
  rm -f "$result_json" "$codex_exit"
fi

prompt_tmp="$(mktemp "$result_dir/prompt.XXXXXX")" || die "cannot create prompt tempfile"

if [ -n "$prompt_file" ]; then
  cp "$prompt_file" "$prompt_tmp" || die "cannot read prompt file"
else
  cat > "$prompt_tmp" || die "cannot read prompt from stdin"
fi

cmd=(codex exec --sandbox "$sandbox")
[ -z "$model" ] || cmd+=(-m "$model")
[ -z "$effort" ] || cmd+=(-c "model_reasoning_effort=$effort")

"${cmd[@]}" < "$prompt_tmp" > "$raw_log" 2>&1
codex_status=$?
printf '%d\n' "$codex_status" > "$codex_exit" || die "cannot write codex exit status"

if ! python3 - "$raw_log" "$result_json" "$task_id" <<'PY'
import json
import re
import sys

raw_path, result_path, expected_task_id = sys.argv[1:4]
try:
    text = open(raw_path, "r", encoding="utf-8", errors="replace").read()
    blocks = re.findall(r"```json\s*(.*?)```", text, flags=re.DOTALL)
    if not blocks:
        raise ValueError("no json fenced block found")
    payload = blocks[-1].strip()
    data = json.loads(payload)
    if not isinstance(data, dict):
        raise ValueError("result json must be an object")
    required_keys = (
        "task_id",
        "status",
        "summary",
        "files_changed",
        "artifacts",
        "verification",
        "next_steps",
    )
    missing_keys = [key for key in required_keys if key not in data]
    if missing_keys:
        raise ValueError("result json missing required key(s): " + ", ".join(missing_keys))
    if data.get("task_id") != expected_task_id:
        raise ValueError("result task_id mismatch")
    if data.get("status") not in {"success", "failure", "blocked"}:
        raise ValueError("result status is invalid")
    with open(result_path, "w", encoding="utf-8") as result_file:
        result_file.write(payload + "\n")
except json.JSONDecodeError as exc:
    print(f"error: result json does not parse: {exc}", file=sys.stderr)
    sys.exit(1)
except (OSError, ValueError) as exc:
    print(f"error: {exc}", file=sys.stderr)
    sys.exit(1)
PY
then
  exit 1
fi

cat "$result_json"
exit 0
