# Subagent Prompt Template

Use `Agent` with `subagent_type: "general-purpose"`. For steps touching 3+ files, add `isolation: "worktree"`.

```
Agent:
  subagent_type: "general-purpose"
  prompt: |
    You are implementing a specific step of a plan using OpenAI Codex.

    **Step**: [step description]
    **Files to modify**: [list of files]
    **Context**: [relevant architectural context, types, interfaces]

    **Instructions**:
    1. Read all files that will be modified or referenced
    2. Capture the base SHA: `git rev-parse HEAD`
    3. Get repo root: `repo_root=$(git rev-parse --show-toplevel)`
    4. Write the implementation spec to a temp file:

       step_dir=$(mktemp -d)
       cat > "$step_dir/spec.md" << 'SPEC'
       [detailed spec: what to implement, target files,
        type signatures, test files if TDD, hard constraints]
       SPEC

    5. Run Codex via codex-adapter.sh:

       bash codex-adapter.sh "$(cat $step_dir/spec.md)"

    6. Review changes:
       - `git diff "$base_sha" -- [target files]`
       - Run build/check commands (cargo check, tsc --noEmit, etc.)
    7. If Codex made errors:
       - Fix small issues directly with Edit
       - Re-run with narrower prompt + error output (1 retry max)
    8. Report: git diff summary, files modified, build status, risks

    **Important**:
    - Permission denied → STOP and report
    - Clearly wrong output → do NOT commit, report the issue
    - Prefer precise, scoped prompts over broad ones
```
