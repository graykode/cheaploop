# cheaploop

> Claude is the brain, Codex is the hands. One command decides the loop.

cheaploop is a Claude Code-only plugin for pushing execution out of metered Claude subscription tokens and into flat-rate Codex worker runs. Claude stays the boss: it decomposes work, chooses the loop, asks for missing requirements, mediates verification, and integrates results. Codex does the hands-on coding and research, so worker execution is not the thing to economize.

## How it works

cheaploop splits each run into two roles:

- **Boss:** a Claude session without a `TASK_ID`. It reads `AGENTS.md`, chooses the loop level, model, and effort, dispatches workers, and reads only `.cheaploop/results/<task-id>/result.json`.
- **Worker:** a Codex session with a `TASK_ID`. It performs only the assigned task, writes deliverables to the repo or `.cheaploop/results/<task-id>/`, and ends stdout with one fenced `json` block containing the result contract.

The worker result contract is always:

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

The loop levels follow LangChain's [The Art of Loop Engineering](https://www.langchain.com/blog/the-art-of-loop-engineering):

1. **Agent Loop:** one worker executes the task.
2. **Verification Loop:** implementation is followed by adversarial verification, with retries on failure.
3. **Event-Driven Loop:** multiple worker stages are coordinated as an observable pipeline.
4. **Hill Climbing Loop:** repeated attempts are compared and refined toward the best result.

## Install

**Prerequisites:** the [Codex CLI](https://github.com/openai/codex) on your `PATH` and authenticated (`codex login`), plus `python3`. cheaploop dispatches every worker through `codex exec`, so nothing runs without it.

In Claude Code, add the marketplace and install the plugin:

```
/plugin marketplace add graykode/cheaploop
/plugin install cheaploop@graykode
```

To install from a local checkout instead of GitHub, point the marketplace at the path:

```
/plugin marketplace add /path/to/cheaploop
/plugin install cheaploop@graykode
```

Then restart Claude Code when prompted. `/cheaploop` is now available in any project.

## Usage

Run one command inside Claude Code with this plugin loaded. For local development, open Claude Code in this repo.

```text
/cheaploop <task>
```

Claude reads `AGENTS.md`, judges the task, and prints a verdict line plus a Unicode loop diagram immediately before dispatch. If requirements, a rubric, or acceptance criteria are unclear, Claude asks via `AskUserQuestion` before dispatching instead of guessing.

Workers are dispatched through:

```sh
scripts/dispatch.sh -t <task-id> [-y build|research|verify] [-m <model>] [-e low|medium|high|xhigh] [-p <prompt-file>]
```

Manual dispatch reads the worker prompt from `-p <prompt-file>` or stdin; it never waits for an interactive terminal prompt.

Task IDs use the `<slug>-<3-digit>` format, such as `add-auth-002`.

## Observability

Multi-worker plans are mapped onto Claude Code's built-in Workflow tool so progress is visible live in `/workflows`. Single-worker runs may dispatch directly.

`/workflows` nodes are thin Claude wrapper shims, because the harness cannot run OpenAI models as subagents. GPT workers run outside the tree through `codex exec`; the real worker model and token usage are recorded in each task's `raw.log`. Workflow labels should carry the real model name, such as `audit:shell [gpt-5.5]`, because the tree's model column can only show the Claude wrapper.

`raw.log` retention is a deliberate debugging tradeoff. Treat worker logs as sensitive.

## Repo layout

```text
AGENTS.md               # boss rules, worker contract, and repo conventions
CLAUDE.md               # points Claude Code at AGENTS.md
commands/cheaploop.md   # /cheaploop command entry point
scripts/dispatch.sh     # codex exec wrapper and result.json capture
.claude-plugin/         # Claude Code plugin manifest
.cheaploop/             # runtime data such as prompts, verification scratch files, and results
```
