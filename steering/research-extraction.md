# Research & Extraction — Firecrawl

> Configure allowed domains and limits to match your project.

## When to Use Firecrawl

| Need | Tool |
|------|------|
| Single factual lookup | WebSearch |
| Single known URL | WebFetch |
| Full page content | Firecrawl scrape |
| Multiple pages from same domain | Firecrawl crawl |
| Structured data extraction | Firecrawl scrape --format json |
| Full site URL map | Firecrawl map |
| Multi-source research | Firecrawl agent |

## Crawl Limits

| Parameter | Default | Max |
|-----------|---------|-----|
| --depth | 2 | 4 |
| --limit | 20 pages | 50 pages |
| Parallel crawls | 1 | 1 |

Report page count to user before crawls > 10 pages.

## Authentication

```bash
export FIRECRAWL_API_KEY="your-key"
# or: firecrawl auth
```

Never commit API key. Never hardcode in scripts. Use env var only.

## Output Location

```
.specs/features/[feature]/research/
├── references.md            # Source index: URL + summary + date scraped
└── [source-slug].md         # Full extracted content per source
```

Save output BEFORE processing. Never process ephemeral data.

## Allowed Domains (configure per project)

```
# Add domains relevant to your stack:
# - radix-ui.com
# - ui.shadcn.com
# - tailwindcss.com
# - nextjs.org
# - (add your own)
```

## Blocked Domains (never crawl without explicit user request)

```
# - login-walled content
# - paid/subscription-only content
# - (add project-specific blocked domains)
```

## On Failure

If crawl fails → log to `.claude/napkin.md` → fallback to WebFetch for single pages.
