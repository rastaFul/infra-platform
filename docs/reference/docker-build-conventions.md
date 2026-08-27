# Docker Build Conventions

Rules derived from real failures found closing the Batch 1 `docker build` gate (2026-08-27, `.specs/audit/execution.md`). All 8 Dockerfiles were written on 2026-08-12 but the gate was never actually run (Docker Desktop was offline) — these bugs sat undetected for two weeks. Follow these rules to avoid reintroducing them.

## 1. Monorepo build context is always the repo root

Dockerfiles under `apps/*/Dockerfile` in a monorepo (`artists-booking`, `rastafinancas`) that `COPY` workspace manifests (`package.json`, `pnpm-workspace.yaml`, `packages/shared/`) **must be built with the monorepo root as context**, not the app subdirectory:

```bash
# correct
docker build -f apps/api/Dockerfile -t api:latest .   # from repo root

# wrong — will fail with "not found" on every COPY of a root-level path
docker build -f apps/api/Dockerfile -t api:latest apps/api
```

Document the correct build context next to each Dockerfile (or in the CI workflow that invokes it) — don't rely on memory.

## 2. Pin `pnpm` version explicitly, never `pnpm@latest`

`corepack prepare pnpm@latest --activate` breaks under `--frozen-lockfile`: pnpm 10+ hard-fails with `ERR_PNPM_IGNORED_BUILDS` when a dependency needs to run an install script (`esbuild`, `unrs-resolver`, native bindings) and isn't explicitly allow-listed. Options: allow-list every such dependency in `pnpm.onlyBuiltDependencies`, or — simpler, what this repo does — pin a known-good version:

```dockerfile
RUN corepack enable && corepack prepare pnpm@9 --activate
```

`pnpm@9` is the version already validated for `artists-booking` (see `DECISIONS.md` D-2026-08-25-2). Do not bump without re-running the `docker build` gate.

## 3. Copy every file a `tsconfig.json` extends

If `apps/*/tsconfig.json` has `"extends": "../../tsconfig.base.json"`, the Dockerfile must `COPY tsconfig.base.json ./` (or wherever it resolves to inside the build context) **before** running the TypeScript build. If it's missing, `tsc` silently falls back to compiler defaults (no `esModuleInterop`, old `target`) instead of failing with a clear "file not found" — the resulting errors look unrelated (e.g. third-party `.d.ts` type errors) and are easy to misdiagnose.

## 4. `node_modules` location depends on the package manager

- **npm workspaces** (`npm ci --workspaces`): dependencies hoist to the **repo root** `node_modules`. There is no per-app `node_modules` unless a dependency can't be hoisted. Runtime stages must `COPY --from=builder /app/node_modules ./node_modules` (root), not `/app/apps/<name>/node_modules`.
- **pnpm workspaces**: pnpm keeps a per-app `node_modules` (symlinked into the pnpm store) — copying `/app/apps/<name>/node_modules` is correct there.

Don't copy-paste a Dockerfile pattern across projects using different package managers without checking this.

## 5. Build-time env vars for eager config validation

If application code throws on import when a required env var (e.g. `DATABASE_URL`) is missing — common with Prisma client wrappers — `next build`'s page-data collection step will fail even though no real DB connection happens at build time. Fix with a placeholder, scoped to the build stage only:

```dockerfile
# Placeholder for build-time only — no real connection happens here.
# Runtime uses the real value injected via env/secret at container start.
ENV DATABASE_URL="postgresql://build:build@localhost:5432/build_placeholder"
RUN npm run build
```

Never let this placeholder leak into the runtime stage — it must only appear in the builder stage's `ENV`, never `COPY`'d or referenced after.

## Gate discipline

None of the above are hypothetical — all 5 were real failures in this repo. The lesson isn't the specific fixes, it's: **`docker build` was skipped for two weeks because Docker Desktop was offline, and nobody treated that as blocking.** Per the harness rule ("no external verification, no trust"), a blocked gate is not a passed gate — it must be re-run and closed explicitly, which is what surfaced these bugs. See ADR references in `.specs/project/DECISIONS.md` D-2026-08-27-{1..4}.
