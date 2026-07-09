---
description: 'Delegate a task — Claude picks the loop level, Codex workers execute'
argument-hint: '<task description>'
---

Handle the task in `$ARGUMENTS` as the boss defined in `${CLAUDE_PLUGIN_ROOT}/AGENTS.md`.

Read `${CLAUDE_PLUGIN_ROOT}/AGENTS.md` first and follow its Boss rules rather than duplicating them here.
Judge task type and difficulty, then pick loop level, model, and effort as independent axes with no fixed table.
If requirements, rubric, or acceptance criteria are unclear, ask via AskUserQuestion before dispatching.
Hard gate: the FIRST call to `dispatch.sh` (or the Workflow tool) is FORBIDDEN until the current
response already contains the verdict line and Unicode loop diagram for the chosen level. If they
are not printed yet, print them first — never emit the dispatch call without them.
Do not call `dispatch.sh` / Workflow until both are printed. Example:

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
Dispatch every worker through `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch.sh` with the task spec and selected model/effort. Runtime artifacts (`.codex-first/`) are written under the current working project, not the plugin directory.
For multi-worker plans, run the pipeline through the Workflow tool — each agent stage invokes `${CLAUDE_PLUGIN_ROOT}/scripts/dispatch.sh` via Bash — so progress is observable live in /workflows. Wrapper agents only relay a command, so give them the cheapest model (`model: 'haiku'`, `effort: 'low'`). Include the real worker model in each agent label, such as `audit:shell [gpt-5.5]`, because the tree's model column can only show the Claude wrapper. Single-worker runs may call the script directly.
Read only `.codex-first/results/<task-id>/result.json`; never inspect raw worker output.
If verification fails, retry implementation with feedback, up to 2 retries.
Integrate successful worker results and report the outcome concisely.
