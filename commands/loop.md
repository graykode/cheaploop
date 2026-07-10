---
description: 'Delegate a task — Claude picks the loop level, Codex workers execute'
argument-hint: '<task description>'
---

Handle the task in `$ARGUMENTS` as the boss defined in `${CLAUDE_PLUGIN_ROOT}/AGENTS.md`.

Read `${CLAUDE_PLUGIN_ROOT}/AGENTS.md` first and follow its Boss rules rather than duplicating them here.
Judge task type and difficulty, then pick loop level, model, and effort as independent axes with no fixed table.
If requirements, rubric, or acceptance criteria are unclear, ask via AskUserQuestion before dispatching.
Hard gate: the Workflow call is FORBIDDEN until the response text immediately before it contains
the verdict line and Unicode loop diagram for the chosen level. This applies to every level,
including Level 1 single-worker runs. If they are not printed yet, print them first — never emit
the Workflow call without them. Level 1 and Level 2 examples:
The plugin `PreToolUse` hook technically enforces this gate by denying dispatch calls when the verdict and diagram are missing.

```
→ Verdict: Level 1, 1 worker (implement high)

     ┏━━ agent loop ── worker A (codex) ━━┓
     ┃  implement ⇄ sandbox tools         ┃
     ┃       ▼ diff + result.json         ┃
     ┗━━━━━━━┿━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
             ▼
          integrate
```

```
→ Verdict: Level 2, 2 workers (implement high + verify medium)

     ┏━━ agent loop ── worker A (codex) ━━┓
     ┃  implement ⇄ sandbox tools         ┃
     ┃       ▼ diff + result.json         ┃
     ┗━━━━━━━┿━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
             ▼
╭──▶ worker B: verify ── pass ──▶ integrate
╰── retry with feedback ◀─ fail (≤2)
```

Re-show the diagram when the plan changes level or worker count mid-session.
Generate each `TASK_ID` as `<slug>-<3-digit>`.
Dispatch every worker through `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch.sh` with the task spec and selected model/effort/service tier. Every dispatch must pass `-m` and `-e` explicitly, plus `-s` when the tier should differ from standard judgment — never rely on `~/.codex/config.toml` defaults. Runtime artifacts (`.codex-first/`) are written under the current working project, not the plugin directory.
Run every worker run through the Workflow tool so progress is observable live in /workflows; a single-worker run is a one-stage workflow. Each agent stage invokes `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch.sh` via Bash. Wrapper agents only relay a command, so give them the cheapest model (`model: 'haiku'`, `effort: 'low'`). Include the real worker model in each agent label, such as `audit:shell [gpt-5.5]`, because the tree's model column can only show the Claude wrapper.
Read only `.codex-first/results/<task-id>/result.json`; never inspect raw worker output.
If verification fails, retry implementation with feedback, up to 2 retries.
Integrate successful worker results and report the outcome concisely.
