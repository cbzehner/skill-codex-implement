# Codex Implement

Delegate code implementation to OpenAI Codex (gpt-5.4) via parallel subagents.

## What It Does

Takes an approved plan and breaks it into independent implementation steps, each delegated to a Codex subagent running in parallel. Verifies changes, runs builds, and reports results.

## Usage

```
/codex-implement
```

Reads the current plan from conversation context and delegates implementation. If no plan is in context, asks what to implement.

## When to Use

- Multi-file implementation after plan approval
- Parallelizing independent code changes across files
- Delegating mechanical coding to Codex while Claude orchestrates

## When NOT to Use

- Single-file changes (just implement directly)
- Exploratory work (Codex needs clear intent)
- Test-only changes (write tests where you can verify inline)

## Installation

### From Marketplace

```bash
/plugin marketplace add cbzehner/skill-codex-implement
/plugin install codex-implement@cbzehner
```

### Manual Installation

```bash
cd ~/.claude/skills/
git clone https://github.com/cbzehner/skill-codex-implement.git codex-implement
```

## Requirements

- OpenAI Codex CLI (`npm install -g @openai/codex && codex login`)
- `"Bash(codex *)"` in `.claude/settings.local.json` permissions

## License

MIT
