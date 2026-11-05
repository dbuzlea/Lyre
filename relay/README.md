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

## Usage statistics and the dashboard

Lyre's opt-in usage statistics (the app's `UsageStats.swift`) arrive at `POST /v1/usage`
and are kept in Workers Analytics Engine (dataset `lyre_usage`, binding `USAGE`, created on
first deploy). No install ID comes with them; the sender's key or address is only hashed
into a KV key for the daily limit (`USAGE_PER_DAY`), which expires in two days.

The dashboard is at `/dashboard`. It asks for the files token (`~/.lyre-relay/files-token`)
and keeps it in that browser. Its figures come from Analytics Engine's SQL API, which needs
an API token that may read the account's analytics, set once:

    # dash.cloudflare.com → My Profile → API Tokens → Create Token → Custom:
    # Permissions: Account · Account Analytics · Read
    npx wrangler secret put CF_API_TOKEN

Analytics Engine keeps data points for three months.

## Working on it

```sh
npm test            # against fakes: no Jira, KV or R2 is touched
npm run typecheck
npx wrangler dev    # locally, with secrets from .dev.vars (not committed)
```
