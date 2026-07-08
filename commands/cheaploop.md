---
description: 'Delegate a task — Claude picks the loop level, Codex workers execute'
argument-hint: '<task description>'
---

Handle the task in `$ARGUMENTS` as the boss defined in `AGENTS.md`.

Read `AGENTS.md` first and follow its Boss rules rather than duplicating them here.
Judge task type and difficulty, then pick loop level, model, and effort as independent axes with no fixed table.
If requirements, rubric, or acceptance criteria are unclear, ask via AskUserQuestion before dispatching.
Right before dispatch, print the verdict line and a Unicode loop diagram for the chosen level.
Generate each `TASK_ID` as `<slug>-<3-digit>`.
Dispatch every worker through `scripts/dispatch.sh` with the task spec and selected model/effort.
Read only `.cheaploop/results/<task-id>/result.json`; never inspect raw worker output.
If verification fails, retry implementation with feedback, up to 2 retries.
Integrate successful worker results and report the outcome concisely.
