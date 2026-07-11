# API reference

## Admin / console REST API

Base URL = the control plane (e.g. `http://localhost:8080`). All `/api/*`
endpoints require `Authorization: Bearer <TAC_ADMIN_TOKEN>`.

### `POST /api/connectors`
Create a connector and mint a one-time enrollment token (returned **once**).

```jsonc
// request
{ "name": "Prod Postgres — Mumbai DC" }

// 201
{
  "connector":       { "id": "con_…", "name": "…", "status": "pending", … },
  "enrollmentToken": "tac_enroll_…",
  "serverWsUrl":     "wss://connect.tablearth.com/ws/agent"
}
```

### `GET /api/connectors`
List connectors with derived status.

```jsonc
{ "connectors": [ {
  "id": "con_…", "name": "…",
  "status": "online",              // pending | online | offline
  "hostname": "192.168.1.11", "os": "linux", "agentVersion": "0.1.0",
  "dataSources": [ { "name": "prod", "kind": "postgres" } ],
  "holderInstanceId": "control-a",
  "lastSeen": "2026-07-11T01:16:37Z", "createdAt": "…"
} ] }
```

### `GET /api/connectors/{id}` · `DELETE /api/connectors/{id}`
Fetch one, or delete (also drops the live socket if held here).

### `POST /api/connectors/{id}/query`
Run a read-only query through the tunnel. Routed to the socket holder
(locally or forwarded).

```jsonc
// request
{ "dataSource": "prod", "sql": "SELECT country, count(*) FROM customers GROUP BY country" }

// 200
{ "columns": ["country","count(*)"], "rows": [["US",3],["UK",1]],
  "rowCount": 2, "truncated": false, "elapsedMs": 2 }
```

Errors: `401` unauthorized · `404` unknown connector · `503` connector offline ·
`502` query failed (body: `{ "error": "…" }`).

### `GET /healthz`
`{ "ok": true, "instance": "control-a", "version": "0.1.0" }` — unauthenticated.

### `POST /internal/dispatch` (instance-to-instance)
Used by peer instances to run a query on the socket-holding instance. Requires
`X-Internal-Secret: <TAC_INTERNAL_SECRET>`. Not for external callers.

---

## Tunnel protocol (agent ↔ control plane)

One WebSocket at `/ws/agent`. Envelope: `{ "type": string, "payload": object }`.
Full definitions in [`protocol/protocol.go`](../protocol/protocol.go).

| Type | Dir | Payload (key fields) |
|------|-----|----------------------|
| `ENROLL` | a→c | `enrollmentToken` **or** `agentToken`, `hostname`, `os`, `agentVersion`, `dataSources[]` |
| `WELCOME` | c→a | `connectorId`, `agentToken` (first enroll only), `sessionId`, `heartbeatSec`, `maxRows` |
| `AUTH_FAIL` | c→a | `reason` |
| `HEARTBEAT` | a→c | `inFlight` |
| `HEARTBEAT_ACK` | c→a | — |
| `QUERY` | c→a | `requestId`, `dataSource`, `sql`, `maxRows`, `timeoutMs` |
| `ROWS` | a→c | `requestId`, `seq`, `columns` (seq 0), `rows[][]` |
| `RESULT_END` | a→c | `requestId`, `rowCount`, `truncated`, `elapsedMs` |
| `QUERY_ERROR` | a→c | `requestId`, `code`, `message` |

---

## Control-plane configuration (env)

| Variable | Default | Purpose |
|----------|---------|---------|
| `TAC_LISTEN_ADDR` | `:8080` | HTTP/WS listen address |
| `TAC_INSTANCE_ID` | hostname+rand | Unique per instance |
| `TAC_INSTANCE_ADDR` | `http://127.0.0.1:<port>` | URL peers use to forward to this instance |
| `TAC_MONGO_URI` | *(empty)* | Set → MongoDB multi-instance; empty → in-memory single-instance |
| `TAC_MONGO_DB` | `tablearth_connector` | Mongo database name |
| `TAC_ADMIN_TOKEN` | `dev-admin-token` | Bearer token for `/api/*` |
| `TAC_INTERNAL_SECRET` | `dev-internal-secret` | Shared secret for `/internal/dispatch` |
| `TAC_PUBLIC_WS_URL` | derived | `wss://…/ws/agent` shown in install snippets |
| `TAC_HEARTBEAT_SEC` | `15` | Heartbeat cadence (read deadline = 3×) |
| `TAC_MAX_ROWS` | `10000` | Server-side row cap per query |
| `TAC_STALE_AFTER_SEC` | `45` | Online iff `lastSeen` within this window |
| `TAC_WEB_DIR` | *(empty)* | Optional: serve the built console from this dir |

## Agent configuration (env overrides)

`TAC_SERVER_URL`, `TAC_ENROLLMENT_TOKEN`, `TAC_INSECURE_TLS` override the
corresponding YAML keys. See [INSTALL.md](INSTALL.md) for the full config file.
