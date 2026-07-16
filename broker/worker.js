// Sharingan Jira OAuth token broker (Cloudflare Worker).
//
// Why this exists: Atlassian's OAuth 2.0 (3LO) has no PKCE and its token
// endpoint requires the client secret. A desktop app either embeds that secret
// (extractable from the bundle) or proxies token calls through a server that
// holds it. This Worker is that server: the app POSTs the token request WITHOUT
// the secret, the Worker injects it from an encrypted environment variable and
// forwards to Atlassian, then returns Atlassian's response verbatim.
//
// The secret lives only here, set with:
//   wrangler secret put JIRA_CLIENT_SECRET
// and never in the app, the repo, or any client.
//
// Deploy: see broker/README.md. Then bake the Worker URL into the app as
// JIRA_BROKER_URL (Scripts/make-app.sh reads it) so the shipped build ships an
// EMPTY client secret.

const ATLASSIAN_TOKEN_URL = "https://auth.atlassian.com/oauth/token";

// Only these grants are ever forwarded — the Worker is a token proxy, nothing
// else. Anything else is refused so it can't be turned into an open relay.
const ALLOWED_GRANTS = new Set(["authorization_code", "refresh_token"]);

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: "method_not_allowed" }, 405);
    }
    if (!env.JIRA_CLIENT_SECRET) {
      // Misconfiguration, not a client error — fail loudly rather than leak a
      // confusing "invalid_client" from Atlassian.
      return json({ error: "server_misconfigured", error_description: "JIRA_CLIENT_SECRET is not set on the broker." }, 500);
    }

    let body;
    try {
      body = await request.json();
    } catch {
      return json({ error: "invalid_request", error_description: "Body must be JSON." }, 400);
    }

    const grant = body.grant_type;
    if (!ALLOWED_GRANTS.has(grant)) {
      return json({ error: "unsupported_grant_type" }, 400);
    }

    // Optional hardening: if JIRA_CLIENT_ID is configured, only broker for that
    // client. Keeps the Worker from minting tokens for someone else's app.
    if (env.JIRA_CLIENT_ID && body.client_id && body.client_id !== env.JIRA_CLIENT_ID) {
      return json({ error: "unauthorized_client" }, 403);
    }

    // Rebuild the upstream body from known fields only, then add the secret.
    // Never trust a client-supplied client_secret — the whole point is the
    // client doesn't have one.
    const upstream = {
      grant_type: grant,
      client_id: env.JIRA_CLIENT_ID || body.client_id,
      client_secret: env.JIRA_CLIENT_SECRET,
    };
    if (grant === "authorization_code") {
      upstream.code = body.code;
      upstream.redirect_uri = body.redirect_uri;
    } else {
      upstream.refresh_token = body.refresh_token;
    }

    const atlassian = await fetch(ATLASSIAN_TOKEN_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Accept": "application/json" },
      body: JSON.stringify(upstream),
    });

    // Pass Atlassian's status and JSON straight back — the app already knows how
    // to read both the success shape and the {error, error_description} shape.
    const text = await atlassian.text();
    return new Response(text, {
      status: atlassian.status,
      headers: { "Content-Type": "application/json" },
    });
  },
};

function json(obj, status) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
