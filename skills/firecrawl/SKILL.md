# Firecrawl

Web scraping and structured extraction for research inputs. Gathers external design references, component documentation, and research for specs. Source: https://docs.firecrawl.dev/sdks/cli

## Setup

```bash
npm install -g firecrawl
export FIRECRAWL_API_KEY="your-key"   # or: firecrawl auth
```

## Commands

```bash
# Single page → markdown or JSON
firecrawl scrape <url> --format markdown

# Full site crawl (always set --depth)
firecrawl crawl <url> --depth 2 --limit 20

# Discover all URLs in a site
firecrawl map <url>

# Web search with structured output
firecrawl search "<query>"

# Natural language page interaction
firecrawl interact "<prompt>" <url>

# Multi-source AI research job
firecrawl agent "<research task>"
```

## Trigger

Activate when: full page content needed, multiple pages from same domain, structured extraction, systematic site crawl, multi-source research job.

Trigger keywords: scrape, extract, map site, external reference, how does [site] do X, crawl.

Do NOT activate for: single factual lookup (→ WebSearch), single known URL (→ WebFetch), tasks without external research need.

## Files

| File | Access | Purpose |
|------|--------|---------|
| `.specs/features/[feature]/research/` | Write | Scraped content per source |
| `.specs/features/[feature]/research/references.md` | Write | Source index with URLs and summaries |
| `steering/research-extraction.md` | Read | Depth limits, allowed/blocked domains |
| `.claude/napkin.md` | Write | Record patterns/surprises from crawl |

## Output Protocol

1. Save raw output to `research/[source-slug].md` before any processing
2. Update `research/references.md` with: URL, summary, date, pages scraped
3. Never process ephemeral data — always persist first

## Rules

1. Always set `--depth` — never open-ended crawl
2. API key via `FIRECRAWL_API_KEY` env only — never hardcoded, never committed
3. One crawl at a time — no parallel crawls
4. Report page count and scope to user before crawls > 10 pages
5. If crawl fails → log to napkin.md → fallback to WebFetch for single pages
6. Respect `steering/research-extraction.md` domain boundaries
