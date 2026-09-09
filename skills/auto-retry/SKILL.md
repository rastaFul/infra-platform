# auto-retry — Rate Limit Resume for Autonomous Sessions

Resumes `autonomous` runs (harness rule 9) after a Claude subscription rate-limit window (5h rolling / weekly) hits, so an unattended session doesn't sit stuck until a human notices. Installed by `install.sh`.

## Why

- There's no proactive alert when the limit approaches — Claude Code only reports it reactively, when a request fails mid-run.
- The 5h window is rolling (anchored to the first prompt of the session), not a fixed clock time — a static recurring cron cannot align with it reliably.
- An unattended session left waiting for a keypress after reset can stay stuck indefinitely (see `anthropics/claude-code#78930`). Never assume "wait for reset" resumes itself.

## How It Works

`claude-auto-retry` wraps the `claude` binary via a shell function (injected into `.bashrc`/`.zshrc` by `claude-auto-retry install`). It runs the session inside tmux, polls the pane every `pollIntervalSeconds`, parses the "resets Xpm" message (timezone/DST-aware), waits `+ marginSeconds` past reset, then `tmux send-keys` a configured retry message into the pane.

Safeguard: it only sends if the foreground process in the pane is `node`/`claude` — won't inject into vim/bash by accident.

**Known limitation**: it cannot distinguish a special confirmation prompt (e.g. arrow-key selection) from normal idle input — it sends plain text once idle is detected. Its "continue" is a best-effort nudge, not a guaranteed context-perfect resume.

## Mandatory pairing with harness checkpoints

Because the injected message isn't guaranteed to line up with exact conversational state, `retryMessage` (in `~/.claude-auto-retry.json`) forces a re-grounding read instead of a blind "continue":

```json
{
  "retryMessage": "Rate limit reset. Re-read .specs/project/STATE.md and .specs/audit/execution.md before continuing, then resume from the last checkpoint.",
  "maxRetries": 5,
  "pollIntervalSeconds": 10,
  "marginSeconds": 90
}
```

This makes the tool's imperfect keystroke injection safe: worst case, the agent re-grounds itself exactly like a fresh session start (rule 1) instead of guessing where it left off. Checkpoints every 3 steps / 15 minutes (rule 9) keep `STATE.md` current enough for this to always work.

## Remote Control requirement (mobile follow-along)

Any `claude` invocation that starts or restarts autonomous work MUST include `--remote-control` (optionally `--name <project>-autonomous`):

```bash
claude --agent harness-infra --remote-control --name myproject-autonomous
```

- `claude-auto-retry` injects keystrokes into the *same* tmux pane/process — remote-control set at launch stays active across a rate-limit resume automatically. No extra action needed for the common case.
- If the process actually dies and needs a **hard relaunch** (crash, host reboot, lost tmux pane) — not just a rate-limit pause — the relaunch command must ALSO include `--remote-control`. A hard-relaunch after a crash is exactly the moment nobody's watching the terminal, which is the whole point of the phone follow-along.

## Setup (handled by install.sh)

```bash
npm install -g claude-auto-retry
claude-auto-retry install         # injects shell wrapper into .bashrc/.zshrc
```

Config file: `~/.claude-auto-retry.json` (see block above, written by `install.sh` if absent — won't overwrite an existing one).

## Verification

```bash
claude-auto-retry status
claude-auto-retry logs
```

## Limitations — test before trusting on a real run

- Requires tmux ≥2.1 (auto-installed if missing), Node ≥18. No native Windows support (WSL2 OK).
- If Node is managed via `nvm`: the shell wrapper resolves the launcher path to the active Node version at install time. Switching Node versions breaks it silently — re-run `claude-auto-retry install` after any `nvm use`/version change.
- Wraps the `claude` binary only — does not wrap arbitrary commands (`docker compose run`, etc). Fine for this harness: autonomous `claude` processes run on the host, not inside the gate-runner sandbox container.
- Test on a low-blast-radius task first (dry-run / `--check` scope, non-prod target) before relying on it for a real long autonomous infra run.

## Reference

- Upstream: https://github.com/cheapestinference/claude-auto-retry
- Related: `.claude/agents/harness-infra.md` and `harness-dev.md`, section 9 (Autonomous execution)
