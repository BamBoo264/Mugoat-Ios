# Nova Internet avatar relay

Cloudflare Workers Free + SQLite Durable Objects; no paid subscription enabled.
Endpoint: `wss://mugoat-nova-relay.hutaolee264.workers.dev`.

`npm ci`; `npx wrangler dev`; `node test-relay.mjs`.
Deploy under your own account: replace account_id in wrangler.jsonc, `npx wrangler login`, `npx wrangler deploy`; then change NovaRelayURL in app/project.yml.
Production test: `node test-relay.mjs wss://YOUR-WORKER.workers.dev`.
Credentials never belong in repository or app. The app needs only the public WSS URL.

Room codes are private invitation capabilities: share only with intended players. A host must remain connected; foreground Internet access is required. There is no host migration or seamless reconnect; rejoin the code while host remains present. Empty rooms do not retain player data. Host-close terminates guests. Only avatar/position synchronization is implemented; no complete mission/vehicle/damage replication and no verified GTAV-v10.1 interoperability.
Free quotas are finite and can stop service at quota exhaustion. See Cloudflare Durable Objects pricing. Public endpoint abuse can consume quota; monitor usage before a large public rollout. No game data, saves, auth tokens or real-world location are transmitted by relay tests.
