# Architecture

## The problem

TableArth is SaaS. A customer's production databases sit inside *their* private
network — a VPC, on-prem, or behind a firewall with no public ingress. We need
to query them without asking the customer to expose anything inbound, because
"open your DB (or SSH) port to our IPs" is rejected by every serious security
review.

## The one principle

**The connection is always initiated *outbound* from inside the customer
network.** Nothing on the customer side ever listens for inbound traffic. That
single rule is what makes this deployable in locked-down environments, and it
drives every design choice below.

## Components

| Component | Runs where | Responsibility |
|-----------|-----------|----------------|
| **Agent** (`tac-agent`) | Inside the customer network, next to the DB | Hold the outbound tunnel; run read-only SQL locally; stream rows back |
| **Control plane** (`tac-control`) | TableArth cloud (N instances behind an LB) | Terminate tunnels; admin/registration API; route queries to the socket holder |
| **Registry** | MongoDB (prod) / in-memory (dev) | Durable connector identity + live presence (which instance holds each socket) |
| **Console** (`web/`) | TableArth cloud | Register connectors, watch status, run queries |

The agent is intentionally **thin**: authenticate, hold the tunnel, execute SQL,
enforce caps, stream rows. All query *generation* stays server-side. This
minimizes what runs (and must be vetted and updated) inside the customer network
and keeps the binary a clean, dependency-free static artifact.

## The tunnel

One long-lived connection per connector, opened by the agent to
`wss://…/ws/agent`.

**Transport.** The reference implementation uses **WebSocket + JSON** because it
traverses corporate proxies and TLS-inspecting middleboxes on port 443, needs no
code generation, and is trivially debuggable. The message envelope maps 1:1 onto
**gRPC bidi streaming** (protobuf over HTTP/2), which is the intended fast path
wherever clean HTTP/2 is guaranteed (same-cloud, Cloudflare/Envoy-fronted). The
decision per environment is simply *"can HTTP/2 survive the path?"* — if yes,
gRPC; if unknown, WebSocket. Both carry the same frames, so the app layer is
transport-agnostic.

### Frames

All frames are `{ "type": ..., "payload": ... }`. See
[`protocol/protocol.go`](../protocol/protocol.go).

```
agent → control                     control → agent
  ENROLL       (bootstrap|reconnect)  WELCOME     (issues durable token once)
  HEARTBEAT    (every N s)            AUTH_FAIL
  ROWS         (chunked results)      HEARTBEAT_ACK
  RESULT_END                          QUERY       (requestId, sql, dataSource, caps)
  QUERY_ERROR
```

### Query lifecycle

1. Console/API asks instance X to run a query on a connector.
2. X sends `QUERY {requestId, sql, maxRows, timeoutMs}` down the socket.
3. Agent runs it read-only, streams `ROWS` chunks (columns on the first), then
   `RESULT_END` (or `QUERY_ERROR`).
4. X correlates by `requestId`, assembles the (row-capped) result, returns it.

## Enrollment & authentication

Two-phase so a human never handles the long-lived secret:

1. **Bootstrap.** The console mints a one-time **enrollment token** (24 h TTL).
   The agent presents it on first connect; the control plane consumes it and
   issues a durable **agent token**, returned once in `WELCOME`. The agent
   persists it (`credentials_path`, mode 0600).
2. **Reconnect.** Thereafter the agent presents the durable token. It is stored
   only as a SHA-256 hash server-side.

Admin/console calls use a bearer token (`TAC_ADMIN_TOKEN`) — in production this
delegates to antrika-backend's existing SSO/session auth. Instance-to-instance
calls use a shared `TAC_INTERNAL_SECRET`.

## Liveness: heartbeat & reconnect

- The agent sends `HEARTBEAT` every `heartbeatSec` (default 15); the control
  plane replies `HEARTBEAT_ACK`. Each side sets a read deadline of `3×
  heartbeat`, so a dead socket is detected within ~45 s even when idle. The
  heartbeat cadence must beat the shortest idle timeout in the path — note an
  AWS ALB idle-timeouts at 60 s, nginx at 60 s (we set 3600 s in `nginx.conf`).
- On any failure the agent reconnects with **exponential backoff + full jitter**
  (1 s → 30 s). In-flight queries fail and are simply retried — safe because the
  DB user is **read-only**, so re-running a `SELECT` needs no exactly-once
  machinery.

## Multi-instance routing

A WebSocket is pinned to exactly one control-plane instance, but queries arrive
at any instance via the load balancer. Resolving that is the crux of horizontal
scaling (and the classic "which of N instances holds the state" bug).

```
① agent connects to instance A  → A writes {connectorId → A, addr, lastSeen} to Mongo
② query lands on instance B      → B looks up the holder in Mongo (freshness-checked)
③ B forwards to A's addr          → POST /internal/dispatch (shared secret)
④ A runs it on its local socket   → returns the assembled result to B → to caller
```

- **Registry = MongoDB** (we don't run Redis). Presence is folded into the
  durable connector document; `Touch` updates `holderInstanceId/Addr/lastSeen`
  on connect and every heartbeat. The upsert is keyed on the connector id, so a
  reconnect to a different instance atomically overwrites the holder
  (last-writer-wins failover).
- **Liveness is a freshness check, not existence.** A connector is *online* only
  if `lastSeen` is within the stale window (`TAC_STALE_AFTER_SEC`, default 45 s).
  We deliberately do **not** TTL-delete the record when the agent goes offline —
  a registered connector persists and simply shows "offline". (If you prefer an
  ephemeral presence doc with a Mongo TTL index instead, note the TTL reaper only
  runs ~every 60 s, so you must still freshness-check on read; folding presence
  into the record avoids that entirely.)
- **Forwarding is direct instance-to-instance HTTP.** Results are already
  row-capped, so payloads are bounded. If your instances *cannot* address each
  other directly, swap `forwardToHolder` for a MongoDB **change-streams** bus —
  same registry, no mesh required.

## Backpressure

Results stream in bounded chunks (500 rows/frame) and every query is capped at
`maxRows`, so a huge result can't blow up memory on either side. The production
step is **credit-based flow control** (server grants row/byte windows) — with
gRPC you get HTTP/2 flow control for this for free; over WebSocket you implement
the credit window. This is the documented next hardening item.

## Failure modes

| Event | Behavior |
|-------|----------|
| Agent process dies | Graceful `ClearHolder` → connector offline immediately; queries return `503`. |
| Holder instance crashes | `lastSeen` goes stale → freshness check treats connector offline within the stale window; agent reconnects (to any instance) and re-registers. |
| Network blip | Agent reconnects with backoff+jitter; durable token → no re-enrollment. |
| DB unreachable | Agent returns `QUERY_ERROR`; connector stays online (tunnel is healthy). |
| Non-SELECT SQL | Rejected by the agent's read-only guard before it reaches the DB. |
