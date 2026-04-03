---
name: codex-implement
description: Delegate code implementation to OpenAI Codex subagents. Use after plan approval to have Codex write the code. Use this whenever the user wants to parallelize implementation, delegate coding to Codex, or execute a multi-file plan.
license: MIT
allowed-tools: Bash Read Glob Grep Task Edit Write Skill
---

# Codex Implement

Delegate code implementation to OpenAI Codex via subagents.

## Host Check

If the current host IS Codex, this skill is unnecessary — implement the plan
directly rather than delegating through an extra layer. This skill exists for
Claude Code to orchestrate Codex workers, not for Codex to call itself.

## Transport

Always invoke Codex through [codex-adapter.sh](codex-adapter.sh). The adapter
prefers the companion plugin (HTTP transport to Codex app-server — persistent
connection, thread resume, better error handling) and falls back to
`codex exec < /dev/null` with a timeout. Never call `codex exec` directly —
it hangs in subagent environments where stdin is an open pipe.

## Usage

`/codex-implement` — reads the current plan from context and delegates implementation steps to Codex subagents.

If no plan is in context, ask the user what to implement.

## When NOT to Use

- **Single-file changes** — just implement directly, spawning subagents adds overhead
- **Exploratory work** — Codex needs clear intent; use for implementation, not investigation
- **Test-only changes** — write tests yourself where you can verify behavior inline

## Context Layering

Do not stuff all context into the prompt. Pass it in layers:

1. **Repo norms** — maintain an `AGENTS.md` at the repo root with coding conventions, style rules, and architecture notes. Codex reads these automatically before each task.
2. **Task spec** — for non-trivial steps, write a brief spec to a temp file (e.g. `tmp/codex-step-N.md`) and reference it in the prompt rather than inlining everything.
3. **File scope** — list target files, tests to run, and files NOT to touch explicitly in the prompt.
4. **Hard constraints** — state them directly: "no new deps", "preserve public API", "stop after minimal fix".

## Protocol

### 1. Consider TDD-First

Before delegating implementation, consider writing tests first:
- Opus writes tests based on the architectural plan (it understands intent better)
- Codex implements code to make those tests pass (it has a concrete success criterion)
- When using TDD-first, include the test files in the spec so Codex can read them as its behavioral contract
- This is optional for trivial steps but strongly recommended for core logic

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

Each subagent should follow this pattern (use `Agent` with `subagent_type: "general-purpose"`; for steps touching 3+ files, add `isolation: "worktree"`):

```
Agent:
  subagent_type: "general-purpose"
  prompt: |
    You are implementing a specific step of a plan using OpenAI Codex.

    **Step**: [step description]
    **Files to modify**: [list of files]
    **Context**: [relevant architectural context, types, interfaces]
    **Codex transport**: [plugin or cli]

    **Instructions**:
    1. First, read all files that will be modified or referenced using the Read tool
    2. Capture the base SHA: run `git rev-parse HEAD`
    3. Determine the repo root: `repo_root=$(git rev-parse --show-toplevel)`
    4. Write the implementation spec to a temp file:

       step_dir=$(mktemp -d)
       cat > "$step_dir/spec.md" << 'SPEC'
       [detailed spec including:
        - what to implement
        - which files to create/modify
        - relevant type signatures and interfaces
        - if TDD-first: reference the test files Codex should make pass
        - hard constraints: no new deps, preserve API, etc.]
       SPEC

    5. Run Codex using the detected transport:

       **If plugin available:**
       node "[companion script path]" task \
         --cwd "$repo_root" \
         --write \
         --json \
         "$(cat $step_dir/spec.md)"

       **If CLI fallback:**
       codex -a never exec \
         -C "$repo_root" \
         --sandbox workspace-write \
         --ephemeral \
         -o "$step_dir/output.txt" \
         - < "$step_dir/spec.md"

    6. After Codex completes, review the changes:
       - Run `git diff "$base_sha" -- [target files]` to see exactly what changed
       - Run any relevant build/check commands (cargo check, tsc --noEmit, etc.)
    7. If Codex made errors, either:
       - Fix them directly with Edit tool for small issues
       - Re-run Codex with a narrower prompt that includes the error output (1 retry max)
    8. Report back: the git diff summary, files modified, build status, and any risks

    **Important**:
    - If Codex fails with permission denied, STOP and report the error
    - If Codex produces clearly wrong output, do NOT commit it — report the issue
    - Prefer precise, scoped prompts over broad "implement everything" prompts
```

### 5. Verify All Changes

After all subagents complete:

1. Run `git diff` from before the first subagent to see the full picture
2. Run the project's build command to verify compilation
3. Run tests if they exist
4. **If the Codex plugin is installed**, run `/codex:review` for a Codex-native review of all changes. This catches issues that the build/test pass might miss.
5. Summarize all changes made across all steps
6. Flag any steps that failed or produced suspicious output

For high-stakes implementations, consider `/codex:adversarial-review` instead —
it actively challenges design decisions and surfaces hidden assumptions.

### 6. Report

Present a summary to the user:

```
## Codex Implementation Summary

### Steps Completed
- [x] Step 1: [description] — [files changed]
- [x] Step 2: [description] — [files changed]
- [ ] Step 3: [description] — FAILED: [reason]

### Build Status
[pass/fail + details]

### Codex Review
[summary from /codex:review if available, or "Plugin not installed — manual review"]

### Files Modified
- `path/to/file.rs` — [what changed]
- `path/to/other.rs` — [what changed]

### Issues
- [any problems encountered]
```

## Error Handling

| Error | Action |
|-------|--------|
| Permission denied on codex | STOP — tell user to add `"Bash(codex *)"` to permissions |
| Codex produces wrong code | Retry once with narrower prompt + error output as context, then report |
| Build fails after codex changes | Report failure with error details; subagent may attempt small Edit fixes but should not re-run codex |
| Step dependency missing | Serialize that step after its dependency completes |
| Repo trust / git check failure | Ensure `-C "$repo_root"` points to a valid git repo, or add `--skip-git-repo-check` |
| Auth / network failure | Verify API key is set and network is reachable; codex needs network even in workspace-write sandbox |
| Timeout / hang | Use codex-adapter.sh — it handles stdin redirection and timeouts. Never call `codex exec` directly in subagent contexts |
| Plugin companion not found | Fall back to `codex exec` CLI transport |

## Notes

- Codex runs with `--sandbox workspace-write` (CLI) or `--write` (plugin) so it writes files directly to the repo — verify changes via `git diff` after each step
- Each subagent has its own context window — use the Context Layering approach (AGENTS.md + temp spec files + scoped prompts) rather than inlining everything
- Sandboxed commands lack network, but Codex itself needs network to reach the OpenAI API — this is a hard prerequisite
- `codex exec` expects a git repo unless you pass `--skip-git-repo-check`
- When using CLI transport: use `--ephemeral` to prevent session file accumulation; the global approval flag (`-a never`) goes **before** the `exec` subcommand
- When using plugin transport: the companion script manages the app server connection; multiple subagents share the broker for connection reuse
