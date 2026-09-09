# axe-core injection into an existing Playwright MCP flow

Not a standalone script — axe-core needs a live page context, which `playwright-mcp` already opens for the functional E2E gate. Injecting it separately would mean a second browser session for no reason.

## Where to add it

In the same Playwright test/flow already required by `steering/visual-automation.md`, after the functional assertions pass, add:

```ts
import { injectAxe, checkA11y } from 'axe-playwright';

// ... existing playwright-mcp navigation/assertions ...

await injectAxe(page);
await checkA11y(page, undefined, {
  detailedReport: true,
  detailedReportOptions: { html: true },
  axeOptions: {
    // default: fails on 'critical' and 'serious' impact — tool default, not a business threshold, kept as-is
  },
});
```

## Dependency

`npm install -D axe-playwright` (wraps `@axe-core/playwright`) — added by `install.sh` alongside the existing `@playwright/mcp` global install.

## Result

`checkA11y` throws on violations at critical/serious impact by default — surfaces as a normal Playwright test failure, so it flows through the exact same PASS/FAIL reporting `playwright-mcp` already uses. No new result format needed.
