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
  *[!A-Za-z0-9._-]*) die "task id may contain only letters, numbers, dot, underscore, and dash" ;;
esac

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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || die "cannot resolve script dir"
repo_root="$(cd "$script_dir/.." && pwd)" || die "cannot resolve repo root"
cd "$repo_root" || die "cannot enter repo root"

result_dir=".cheaploop/results/$task_id"
raw_log="$result_dir/raw.log"
result_json="$result_dir/result.json"
codex_exit="$result_dir/codex_exit"
prompt_tmp="$result_dir/prompt.$$"

mkdir -p "$result_dir" || die "cannot create result dir: $result_dir"
rm -f "$raw_log" "$result_json" "$codex_exit" "$prompt_tmp"
trap 'rm -f "$prompt_tmp"' EXIT HUP INT TERM

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
