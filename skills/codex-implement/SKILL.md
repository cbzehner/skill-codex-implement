---
name: codex-implement
description: >-
  Delegate code implementation to the OpenAI Codex CLI as an external
  subprocess. Use when the user explicitly wants Codex, GPT-5, an OpenAI coding
  model, a non-Claude model, or codex-adapter.sh to implement code or execute a
  plan. Prefer this over Claude subagents for Codex-specific delegation. Do not
  use merely because the task mentions OpenAI APIs, docs, or products.
license: MIT
effort: high
allowed-tools: Bash Read Glob Grep Task Edit Write Skill
---

# Codex Implement

## Host Check

If the current host IS Codex, implement the plan directly — do not delegate through an extra layer.

## Transport

Always invoke Codex through [codex-adapter.sh](codex-adapter.sh) (prefers companion plugin, falls back to CLI with timeout). Never call `codex exec` directly — it hangs when stdin is an open pipe.

## Usage

`/codex-implement` — reads the current plan from context and delegates implementation steps to Codex subagents.

If no plan is in context, ask the user what to implement.

## When NOT to Use

- **Single-file changes** — just implement directly, spawning subagents adds overhead
- **Exploratory work** — Codex needs clear intent; use for implementation, not investigation
- **Test-only changes** — write tests yourself where you can verify behavior inline

## Context Layering

Do not stuff all context into the prompt. Layer it:

1. **Repo norms** — `AGENTS.md` at repo root (Codex reads this automatically)
2. **Task spec** — write to a temp file (`tmp/codex-step-N.md`), reference in prompt
3. **File scope** — list target files, tests, and files NOT to touch
4. **Hard constraints** — state directly: "no new deps", "preserve public API", etc.

## Protocol

### 1. Consider TDD-First

For non-trivial steps, write tests first — Codex then implements against a concrete success criterion. Include the test files in the spec so Codex reads them as its behavioral contract.

### 2. Extract Implementation Steps

Read the plan from the current conversation context. Break it into independent implementation steps. Each step should be a self-contained unit of work that modifies a small set of files.

### 3. Spawn Subagents

For each implementation step, spawn a **Task subagent** (`subagent_type: "general-purpose"`) that:

1. Reads relevant existing files for context
2. Runs Codex with the step's prompt (via plugin or CLI)
3. Reviews the `git diff` to verify changes
4. Runs build/check commands
5. Reports what was changed

**Maximize parallelism** — launch independent steps concurrently. Only serialize steps that have dependencies.

**Worktree isolation** — for steps touching 3+ files, use `isolation: "worktree"` on the Agent call to give Codex an isolated git worktree. This prevents race conditions when parallel subagents touch adjacent files or shared manifests.

### 4. Subagent Prompt Template

Follow the template in [references/subagent-prompt.md](references/subagent-prompt.md). Key points: use `codex-adapter.sh` (not raw `codex exec`), capture base SHA before running, review `git diff` after, 1 retry max on errors.

### 5. Verify All Changes

Your job is to try to break it, not confirm it works. If you catch yourself writing an explanation instead of running a command, stop and run the command.

**Anti-rationalization check** — recognize these excuses and do the opposite:
- "The code looks correct from the diff" — reading is not verification. Run the build.
- "Codex's own tests pass" — its tests may be circular. Verify independently.
- "This is probably fine" — probably is not verified. Run it.
- "This would take too long" — not your call. The user asked for implementation, not a guess.

**Required steps:**

1. `git diff` from before the first subagent to see the full picture
2. Build command — broken build is an automatic failure
3. Full test suite — failing tests are an automatic failure
4. Linters/type-checkers if configured
5. At least one adversarial probe: boundary inputs, error paths, or idempotency
6. `/codex:review` if the Codex plugin is installed

For each check, state the exact command run and its observed result. End with: `VERIFICATION: PASS`, `VERIFICATION: FAIL`, or `VERIFICATION: PARTIAL`.

### 6. Report

Summarize for the user: steps completed with their status (with files changed), build/test status, verification result, and any issues. Include the `/codex:review` summary if the plugin was available.

## Error Handling

- **Permission denied** → STOP, tell user to add `"Bash(codex *)"` to permissions
- **Wrong code** → retry once with narrower prompt + error output, then report
- **Build fails** → report failure; subagent may attempt small Edit fixes but should not re-run Codex
- **Auth / network failure** → Codex needs network even in workspace-write sandbox; verify API key is set

## Notes

- Codex writes files directly to the repo — always verify via `git diff`
- CLI transport: use `--ephemeral` to prevent session file accumulation; `-a never` goes **before** the `exec` subcommand
- `codex exec` expects a git repo unless you pass `--skip-git-repo-check`
