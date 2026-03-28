---
name: codex-implement
description: Delegate code implementation to OpenAI Codex subagents. Use after plan approval to have gpt-5.4 write the code. Use this whenever the user wants to parallelize implementation, delegate coding to Codex, or execute a multi-file plan.
allowed-tools: Bash, Read, Glob, Grep, Task, Edit, Write
---

# Codex Implement

Delegate code implementation to OpenAI Codex (gpt-5.4) via subagents.

## Usage

`/codex-implement` — reads the current plan from context and delegates implementation steps to Codex subagents.

If no plan is in context, ask the user what to implement.

## When NOT to Use

- **Single-file changes** — just implement directly, spawning subagents adds overhead
- **Exploratory work** — Codex needs clear intent; use for implementation, not investigation
- **Test-only changes** — write tests yourself where you can verify behavior inline

## Protocol

### 1. Extract Implementation Steps

Read the plan from the current conversation context. Break it into independent implementation steps. Each step should be a self-contained unit of work that modifies a small set of files.

### 2. Spawn Subagents

For each implementation step, spawn a **Task subagent** (`subagent_type: "general-purpose"`) that:

1. Reads relevant existing files for context
2. Runs `codex exec` with the step's prompt
3. Verifies the changes (file exists, no syntax errors)
4. Reports what was changed

**Maximize parallelism** — launch independent steps concurrently. Only serialize steps that have dependencies.

### 3. Subagent Prompt Template

Each Task subagent should follow this pattern:

```
Task:
  subagent_type: "general-purpose"
  prompt: |
    You are implementing a specific step of a plan using OpenAI Codex.

    **Step**: [step description]
    **Files to modify**: [list of files]
    **Context**: [relevant architectural context, types, interfaces]

    **Instructions**:
    1. First, read all files that will be modified or referenced using the Read tool
    2. Run this Bash command to have Codex implement the changes:

       codex exec -m gpt-5.4 --sandbox full-auto -- "[detailed prompt including:
         - what to implement
         - which files to create/modify
         - relevant type signatures and interfaces
         - coding conventions to follow
         - DO NOT include test files unless explicitly part of this step
           (tests need to verify behavior, which requires the implementation to exist first)]"

    3. After codex completes, verify the changes:
       - Read modified files to confirm they exist and look correct
       - Run any relevant build/check commands (cargo check, tsc --noEmit, etc.)
    4. If codex made errors, either:
       - Fix them directly with Edit tool for small issues
       - Re-run codex with a more specific prompt for larger issues
    5. Report back: which files were modified and a brief summary of changes

    **Important**:
    - If codex exec fails with permission denied, STOP and report the error
    - If codex produces clearly wrong output, do NOT commit it — report the issue
    - Prefer precise, scoped prompts over broad "implement everything" prompts
```

### 4. Verify All Changes

After all subagents complete:

1. Run the project's build command to verify compilation
2. Run tests if they exist
3. Summarize all changes made across all steps
4. Flag any steps that failed or produced suspicious output

### 5. Report

Present a summary to the user:

```
## Codex Implementation Summary

### Steps Completed
- [x] Step 1: [description] — [files changed]
- [x] Step 2: [description] — [files changed]
- [ ] Step 3: [description] — FAILED: [reason]

### Build Status
[pass/fail + details]

### Files Modified
- `path/to/file.rs` — [what changed]
- `path/to/other.rs` — [what changed]

### Issues
- [any problems encountered]
```

## Error Handling

| Error | Action |
|-------|--------|
| Permission denied on codex exec | STOP — tell user to add `"Bash(codex *)"` to permissions |
| Codex produces wrong code | Retry with more specific prompt (1 retry max), then report |
| Build fails after codex changes | Report failure with error details, do not attempt auto-fix |
| Step dependency missing | Serialize that step after its dependency completes |

## Notes

- Codex runs with `--sandbox full-auto` so it writes files directly to the repo — verify changes after each step
- Each subagent has its own context window, so pass sufficient context (types, interfaces, conventions) in the prompt rather than assuming it knows the codebase
