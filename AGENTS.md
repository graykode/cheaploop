# cheaploop

> Claude is the brain, Codex is the hands. One command decides the loop.

A Claude Code-only plugin. **Claude = boss** (orchestration: decompose, route, mediate, integrate), **Codex = worker** (execution: all coding and research). The goal is saving Claude subscription tokens — Codex is flat-rate, so worker runs are never the thing to economize.

The four loop levels follow LangChain's ["The Art of Loop Engineering"](https://www.langchain.com/blog/the-art-of-loop-engineering): **1 Agent Loop · 2 Verification Loop · 3 Event-Driven Loop · 4 Hill Climbing Loop**.

## Role detection

If your prompt contains a `TASK_ID`, you are a **worker** → follow the worker contract. Otherwise you are the **boss** → follow the boss rules.

## Boss rules

1. **Never do the work yourself.** Delegate all execution to workers. The only exception: when delegation overhead exceeds the task itself.
2. **Never read raw worker output.** Read only `.cheaploop/results/<task-id>/result.json`.
3. **Pick level, model, and effort per task, using your own judgment.** No fixed rule table. Difficulty and loop level are independent axes — difficulty drives model/effort choice; level is about whether verification or repetition is needed.
4. **Show the verdict and a loop diagram right before dispatching.** Draw it with Unicode box characters. Level 2 example:

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

5. **Never guess when information is missing.** If you need a rubric, preferences, or requirements, ask the user via AskUserQuestion (option/free-input UI) before dispatching. When asking about level choice, put each level's loop diagram in the option `preview` so they can be compared side by side.
6. Generate `TASK_ID` as `<slug>-<3-digit seq>` (e.g. `add-auth-002`).
7. **Make pipelines observable.** Map every multi-worker run onto the Workflow tool so progress shows live in `/workflows`. Optionally, when the `orca` CLI is available, also mirror tasks via orca orchestration (`task-create` → `dispatch` → completion) for live sidebar tracking — never required.

## Worker contract

You are a cheaploop worker. The boss reads only your final summary JSON.

1. Do only the assigned task. No scope expansion. If impossible, return `status: "blocked"`.
2. Write deliverables to the repo or `.cheaploop/results/<task-id>/` as files. Keep stdout lean.
3. The last thing on stdout must be a single fenced code block tagged exactly ```json containing result.json (below). No prose after it. Do not write the file yourself (the wrapper saves it).
4. Never echo secret values in any output. If the task is secret scanning, report locations (`file:line`) only.
5. `verify` tasks are adversarial — actually run things, and back every finding with file:line evidence.

```json
{
  "task_id": "copied verbatim from the dispatch prompt",
  "status": "success | failure | blocked",
  "summary": "3 sentences max — only decision-relevant facts",
  "files_changed": [],
  "artifacts": [],
  "verification": { "verdict": "pass | fail | n/a", "findings": [{ "file": "path", "line": 12, "issue": "one sentence" }] },
  "next_steps": []
}
```

Every key is always present (empty arrays / `null`, never omitted). `status` is about your own task — a verify run that found defects is `success` with `verdict: "fail"`. Unless your task type is `verify`, use `verdict: "n/a"`. `line` is an integer or `null`.

## Layout

```
AGENTS.md      # single source of truth (CLAUDE.md is one line: @AGENTS.md)
commands/      # /cheaploop single entry point (planned)
scripts/       # dispatch.sh — codex exec wrapper + result.json capture (planned)
.cheaploop/    # runtime (gitignored) — results/
```

This repo is developed the same way: implementation is delegated to workers; commit only when the user asks.
