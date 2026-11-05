# Lyre's problem-report relay

A Cloudflare Worker between Lyre and Jira. Lyre sends it problem reports (a listener's
own, from Report a Problem, and, if they've opted in, ones Lyre catches itself); the
relay files them in Jira project LYRE. The Jira credentials live here as Worker
secrets, never in the app.

- A new problem becomes a Bug labelled `auto-report`, `needs-triage` and
  `report-<kind>`, never `claude`: add that after reviewing it, and `/jira-triage` picks
  it up.
- A problem already filed (same kind, version, and signature or stack frames) gets a
  comment and a count instead of another issue. A listener's own reports are each filed.
- The evidence (build and binary UUID, device, stack, the diagnostics log's last lines)
  goes in the issue's text. Larger files are kept in R2 and linked
  (`/v1/files/<key>?token=…`).
- Each phone may send `REPORTS_PER_HOUR` reports an hour.

## Setting it up (once)

Node 22 or newer (`brew install node@22`), then from this folder:

```sh
npm install
npx wrangler kv namespace create LYRE_REPORTS   # put its id in wrangler.toml
npx wrangler r2 bucket create lyre-reports
npx wrangler secret put JIRA_EMAIL              # the Atlassian account's email
npx wrangler secret put JIRA_TOKEN              # id.atlassian.com → Security → API tokens
npx wrangler secret put APP_KEY                 # any long random string; the app sends it
npx wrangler secret put FILES_TOKEN             # another, for reading files back
npx wrangler deploy
```

## Working on it

```sh
npm test            # against fakes: no Jira, KV or R2 is touched
npm run typecheck
npx wrangler dev    # locally, with secrets from .dev.vars (not committed)
```
