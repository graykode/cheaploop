#!/usr/bin/env python3

import json
import sys
from pathlib import Path


BOX_CHARACTERS = frozenset("┏┓┗┛━┃╭╮╰╯")
DENY_OUTPUT = (
    '{"hookSpecificOutput": {"hookEventName": "PreToolUse", '
    '"permissionDecision": "deny", "permissionDecisionReason": '
    '"codex-first gate: print the verdict line (\'→ Verdict: ...\') and the Unicode '
    'loop diagram in your response text BEFORE dispatching, then retry this exact call."}}'
)


def is_dispatch(payload):
    tool_name = payload["tool_name"]
    tool_input = payload["tool_input"]

    if tool_name == "Bash":
        return "dispatch.sh" in tool_input["command"]
    if tool_name != "Workflow":
        return False
    if "dispatch.sh" in tool_input.get("script", ""):
        return True
    if "scriptPath" not in tool_input:
        return False

    try:
        script = Path(tool_input["scriptPath"]).read_text(encoding="utf-8")
    except OSError:
        return False
    return "dispatch.sh" in script


def is_genuine_user(entry):
    if entry.get("type") != "user" or entry.get("isMeta") is True:
        return False
    content = entry["message"]["content"]
    if isinstance(content, str):
        return True
    return any(
        isinstance(block, dict) and block.get("type") == "text"
        for block in content
    )


def has_gate(transcript_path):
    with Path(transcript_path).open(encoding="utf-8") as transcript:
        entries = [json.loads(line) for line in transcript]

    last_user = next(
        (
            index
            for index in range(len(entries) - 1, -1, -1)
            if is_genuine_user(entries[index])
        ),
        None,
    )
    if last_user is None:
        return False

    text_parts = []
    for entry in entries[last_user + 1 :]:
        if entry.get("type") != "assistant" or entry.get("isMeta") is True:
            continue
        for block in entry["message"]["content"]:
            if block.get("type") == "text":
                text_parts.append(block["text"])

    response_text = "".join(text_parts)
    return "Verdict:" in response_text and any(
        character in response_text for character in BOX_CHARACTERS
    )


def main():
    try:
        payload = json.load(sys.stdin)
        if not is_dispatch(payload):
            return
        if has_gate(payload["transcript_path"]):
            return
        print(DENY_OUTPUT)
    except Exception:
        return


if __name__ == "__main__":
    main()
