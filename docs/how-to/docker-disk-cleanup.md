# How to Reclaim Disk Space from Docker (WSL2 backend)

**Context:** on WSL2, Docker Desktop stores all images/containers/volumes/build-cache inside one
dynamic virtual disk file: `C:\Users\<user>\AppData\Local\Docker\wsl\disk\docker_data.vhdx`. This
file **grows but never shrinks on its own**, even after `docker system prune`. It only shrinks after
an explicit host-level compaction. Left unchecked, it silently eats the Windows C: drive while every
`docker` command inside WSL keeps reporting a small, healthy `df -h /`. This runbook exists because
that's exactly what happened on 2026-09-21: C: at 9.1GB free / 477GB, root cause was an 88GB
`docker_data.vhdx` nobody had ever compacted. Full incident: `.specs/audit/execution.md`
("docker-disk-cleanup", 2026-09-21) and D-2026-09-21-1 in `.specs/project/DECISIONS.md`.

## When to run this

- `df -h /mnt/c` (from WSL) or Windows' own disk-space UI shows C: critically low.
- Preventively: this should be a periodic check, not a fire drill — see "Turning this into a habit"
  at the end.

## 1. Diagnose first — don't guess

```bash
# Docker Desktop must be running for these; start it if `docker version` fails:
# powershell.exe -NoProfile -Command "Start-Process 'C:\Program Files\Docker\Docker\Docker Desktop.exe'"

docker system df --format '{{json .}}'   # per-type reclaimable (Images/Containers/Volumes/Build Cache)
docker system df -v                       # full breakdown, if you need per-image/volume detail
ls -lh "/mnt/c/Users/$USER/AppData/Local/Docker/wsl/disk/docker_data.vhdx"   # the actual host file size
df -h /mnt/c                              # actual free space on the Windows C: drive
```

Note: this CLI's `docker` commands sometimes print empty stdout in this environment for no
reason (observed repeatedly during the 2026-09-21 session) — redirect to a file and `cat`/`Read`
it back if a command looks like it silently did nothing.

## 2. Safe cleanup (always fine, no data loss)

```bash
docker image prune -f       # only dangling (untagged) images
docker builder prune -af    # build cache — safe when "Active": "0" in system df
docker container prune -f   # only stopped containers (no-op if everything is Up)
```

None of this touches tagged images or volumes. Do this first, every time, no need to ask.

## 3. Riskier cleanup — ask before running

```bash
docker image prune -a -f    # removes ALL images not referenced by a running container,
                             # INCLUDING tagged ones (e.g. manual rollback tags like
                             # "myapp:pre-spec77-rollback"). Check `docker images` first —
                             # if a tag looks like an intentional rollback/backup, confirm
                             # with the human before deleting it.

docker volume prune -f      # removes dangling volumes. Check names first
                             # (`docker volume ls -f dangling=true`) — a volume can hold real
                             # data from a project that's just not running right now.
```

## 4. The step that actually frees Windows disk space: compact the VHDX

Steps 2-3 only free space *inside* the ext4 filesystem inside `docker_data.vhdx`. The `.vhdx` file
itself on the Windows NTFS side stays the same size — it's a dynamically-expanding disk with no
automatic shrink-on-idle in this Docker Desktop/WSL version (`--set-sparse` exists but is disabled
by Microsoft by default "due to potential data corruption" — do **not** force it with
`--allow-unsafe` just to save disk space).

```powershell
# 1. Fully quit Docker Desktop (not just close the window) and stop its WSL distro.
#    From WSL:
powershell.exe -NoProfile -Command "Stop-Process -Name 'Docker Desktop' -Force -ErrorAction SilentlyContinue; Stop-Process -Name 'com.docker.backend' -Force -ErrorAction SilentlyContinue"
wsl.exe --terminate docker-desktop

# 2. Compact the vdisk (requires an ELEVATED/Administrator PowerShell or Command Prompt).
#    Save as a .txt and run: diskpart /s <path>.txt
select vdisk file="C:\Users\<user>\AppData\Local\Docker\wsl\disk\docker_data.vhdx"
attach vdisk readonly
compact vdisk
detach vdisk
exit

# 3. Restart Docker Desktop — containers with `restart: always` (this repo's convention,
#    see platform/docker-compose.yml and per-project composes) come back up on their own.
```

### Known failure mode: "the process cannot access the file because it is being used by another process"

Hit this on 2026-09-21 even after stopping `Docker Desktop.exe`, `com.docker.backend.exe`, the
`com.docker.service` Windows service, AND `wsl --terminate docker-desktop`. Root cause not
conclusively isolated (leading candidate: WSL2's single shared lightweight utility VM keeps a
handle on every registered distro's `.vhdx`, or Defender real-time scan on a freshly-rewritten
88GB file). The only thing that reliably clears it is `wsl --shutdown` (stops **every** WSL distro,
not just Docker's) or a full Windows restart, run the diskpart script once, **then** restart
Docker Desktop.

**If you're running this from inside a WSL-hosted terminal/agent (e.g. this very Claude Code CLI
session): do not run `wsl --shutdown` from within it.** It kills the WSL VM the session itself runs
in, terminating the session instantly with no chance to finish reporting. Do the shutdown +
compaction from a step outside the session that needs to survive it — a plain Windows
PowerShell/cmd window, or after closing the WSL-hosted session deliberately, then reopen and
resume.

## This is now automated — `scripts/docker-disk-guard.sh`

Implemented 2026-09-21 per `.specs/features/docker-disk-lifecycle/spec.md`. Runs daily via cron
(`35 3 * * *`, right after `backup.sh`), logs to `~/logs/docker-disk-guard.log`:

1. Safe prune every run (`docker image prune -f` + `docker builder prune -af`) — steps 2 in this
   doc, automatic now, no need to run manually unless you want it sooner.
2. WARNs (doesn't act) if `docker_data.vhdx` >= 40GB or C: free space <= 20GB — that's your signal
   to run step 4 (compaction) manually. The guard deliberately does **not** attempt compaction
   itself (see D4 in the spec — unattended Admin-elevated disk operations that stop your running
   containers are not something a cron job should do without you watching).
3. Flags (never deletes) tagged images matching `*-rollback`/`*-pre-*` older than 14 days — check
   the log, delete with `docker rmi <tag>` yourself once you've confirmed you don't need them.

If `~/logs/docker-disk-guard.log` shows a WARN, that's when you come back to steps 1-4 above.

## Ready-to-run script on the Desktop

There's a pre-made `.bat` on the Windows Desktop (`C:\Users\rodri\OneDrive\Area de Trabalho\`)
that does the whole sequence in step 4 automatically: stop Docker Desktop, `wsl --shutdown`,
diskpart compact, restart Docker Desktop.

- `compactar_docker.bat` — the script itself. Must be run elevated (right-click > "Executar como
  administrador"). Requires Admin because `diskpart` needs it.
- `LEIA-ME_compactar_docker.txt` — instructions in the same folder, same language as the script's
  own comments (pt-BR): when to run it, what it does, and the explicit warning that `wsl --shutdown`
  inside it kills every WSL distro, not just Docker's (so close/save any WSL-hosted session first,
  including a Claude Code session running from inside WSL).

Confirmed working end-to-end on 2026-09-21: `docker_data.vhdx` 88GB -> 30.7GB, C: free 5GB ->
76.8GB. This is now the preferred way to run step 4 — the manual diskpart-script-in-Temp procedure
above still works as a fallback if the `.bat` is ever missing or edited.

## What's deliberately still manual/out of scope

- **VHDX compaction itself** — see "Known failure mode" above and D4 in the spec. Always manual.
- **Grafana/Prometheus alerting on this** — no host-level (Windows/WSL2) metrics exporter exists in
  this stack today; adding one is a separate future project, not required for the guard script to
  do its job via log file.
- **Rollback-tag deletion** — always a human call, the guard only flags candidates.
