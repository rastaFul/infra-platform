# snip — Token Filter

CLI proxy that compresses shell output before it reaches the model context. Installed automatically by `install.sh`.

## How It Works

snip installs a `PreToolUse` hook in `~/.claude/settings.json`. Every time Claude Code runs a `Bash` command, snip rewrites it transparently:

```
npm test  →  /home/user/.local/bin/snip -- npm test
```

The output is filtered before entering the model context. Full logs are saved to `~/.local/share/snip/tee/` when filtering is active.

## Covered Commands

| Command | Raw output | With snip |
|---------|-----------|-----------|
| `npm test` / `jest` | full verbose log | failing suites + summary |
| `npx tsc --noEmit` | full errors | `file:line: error TSxxxx: msg` |
| `npm run lint` | full eslint log | errors grouped by file |
| `git status` | verbose | `N changes: M (X files)` |
| `git diff` | full patch | `X files changed, N insertions` |
| `npx vitest run` | full verbose | summary + failures only |
| `npm audit` | full JSON | critical/high counts |

## Setup (handled by install.sh)

```bash
# Binary installed at:
~/.local/bin/snip

# Hook registered in:
~/.claude/settings.json  →  PreToolUse → Bash

# Custom filters directory (optional):
~/.config/snip/filters/
```

Manual setup if needed:
```bash
# Install binary
curl -fsSL "https://github.com/edouard-claude/snip/releases/download/v0.15.0/snip_0.15.0_linux_amd64.tar.gz" | tar xz -C ~/.local/bin

# Register hook
snip init --agent claude-code
```

## Useful Commands

```bash
# Token savings report
snip gain

# Detailed: top commands by savings
snip gain --top 10

# Recent hook activity (requires SNIP_HOOK_AUDIT=1)
snip hook-audit

# Scan sessions for missed savings opportunities
snip discover

# Financial impact by API tier
snip cc-economics
```

## Custom Filters

Place YAML filter files in `~/.config/snip/filters/` to add patterns for project-specific commands:

```yaml
# ~/.config/snip/filters/my-project.yaml
filters:
  - command: "my-build-tool"
    patterns:
      - match: "^Compiling.*"
        action: drop
      - match: "^Build (PASSED|FAILED)"
        action: keep
```

Trust the file after creation:
```bash
snip trust ~/.config/snip/filters/my-project.yaml
```

## Version

snip v0.15.0 — avg 97.6% token reduction on npm/npx/git commands.
