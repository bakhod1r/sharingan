# Sharingan Jira OAuth token broker

A tiny Cloudflare Worker that holds the Atlassian **client secret** so the app
doesn't have to. Atlassian's 3LO has no PKCE and its token endpoint needs the
secret; embedding it in a desktop app makes it extractable. This Worker takes
the token request from the app *without* the secret, injects it server-side,
and forwards to Atlassian.

With the broker deployed and its URL baked into the app, Sharingan ships with an
**empty** client secret and nothing sensitive is recoverable from the bundle.

## What it is / isn't
- It **only** proxies the two OAuth token grants (`authorization_code`,
  `refresh_token`) to `https://auth.atlassian.com/oauth/token`. Any other
  request is refused, so it can't become an open relay.
- It does **not** see or store user tokens beyond forwarding one response. No
  database, no logs of secrets.
- The `state`/CSRF check and the loopback callback stay in the app — the broker
  is not in that path.

## Deploy (once, ~5 minutes)

Prereqs: a free [Cloudflare](https://dash.cloudflare.com/sign-up) account and
Node. From this directory:

```sh
cd broker
npx wrangler login                       # opens the browser once
npx wrangler secret put JIRA_CLIENT_SECRET   # paste the Atlassian client secret
npx wrangler secret put JIRA_CLIENT_ID       # optional: locks the broker to your app
npx wrangler deploy
```

`deploy` prints the Worker URL, e.g.
`https://sharingan-jira-broker.<your-subdomain>.workers.dev`. Its token endpoint
is that URL (the Worker treats any path as the token endpoint). Use the base URL
or append `/token` — both work.

## Point the app at it

Set `JIRA_BROKER_URL` when building the release so it's baked into `Info.plist`
(see `Scripts/make-app.sh`), alongside `JIRA_CLIENT_ID`. Once a broker URL is
present the app sends **no** client secret, so you can leave `JIRA_CLIENT_SECRET`
empty in `.env.release`:

```sh
JIRA_CLIENT_ID=your-atlassian-client-id
JIRA_CLIENT_SECRET=                       # can be blank when a broker is set
JIRA_BROKER_URL=https://sharingan-jira-broker.<your-subdomain>.workers.dev
```

## Verify

```sh
curl -sS -X POST "$JIRA_BROKER_URL" \
  -H 'Content-Type: application/json' \
  -d '{"grant_type":"refresh_token","refresh_token":"not-a-real-token"}'
```

A healthy broker forwards to Atlassian and returns
`{"error":"invalid_grant", ...}` (400) — proof it reached Atlassian *with* a
secret. `server_misconfigured` (500) means `JIRA_CLIENT_SECRET` isn't set.

## Rotating the secret
`npx wrangler secret put JIRA_CLIENT_SECRET` again, then `npx wrangler deploy`.
Existing user refresh tokens keep working; only the app↔Atlassian trust changes.
