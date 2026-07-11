# Security model

The connector is designed to pass a security-conscious customer's review. This
documents what it does today and the hardening path to production.

## What the customer's security team is buying

- **No inbound.** The agent only makes outbound TLS connections on 443. There is
  no listening port on the customer side, no firewall change, no exposed DB.
- **Credentials never leave the network.** The data-source DSN (with the DB
  password) lives only in the agent's local config. The control plane only ever
  learns the logical *name* and *kind* of a data source, never the connection
  string.
- **Read-only by construction.** The agent runs every query inside a read-only
  transaction and refuses anything that isn't a single read statement — and you
  point it at a read-only DB user, which is the authoritative guarantee.

## 1. Network path

- All agent traffic is TLS (`wss://`). `insecure_tls` exists only for local dev.
- **Hardening → mTLS.** Issue each agent a client certificate at enrollment and
  require mutual TLS on the tunnel. This authenticates the agent at the transport
  layer (before any application token) and lets you pin the server certificate to
  resist a customer's own TLS-inspection proxy where policy allows.

## 2. Authentication

| Secret | Purpose | Storage |
|--------|---------|---------|
| Enrollment token | One-time bootstrap; 24 h TTL; consumed on first use | SHA-256 hash in the registry |
| Agent token | Durable per-connector identity for reconnects | SHA-256 hash server-side; plaintext only in the agent's 0600 file |
| Admin token | Console/API access | `TAC_ADMIN_TOKEN` — replace with antrika-backend SSO in prod |
| Internal secret | Instance-to-instance forwarding | `TAC_INTERNAL_SECRET` |

The two-phase design (short-lived enrollment token → durable token the agent
persists) means a human copies only a short-lived secret; the long-lived one is
generated machine-to-machine and never displayed.

## 3. Authorization / least privilege

- **Use a dedicated read-only DB user**, scoped to the needed schemas. This is
  the control that actually matters — never give the agent write/DDL rights "to
  make setup easier."
- The agent enforces a per-query **timeout** and a **row cap** (`maxRows`), and
  streams in bounded chunks, so a runaway query can't exhaust memory.
- The `guardReadOnly` check (reject non-`SELECT`/`WITH`/`EXPLAIN`/`SHOW`/`PRAGMA`
  and stacked statements) is **defense in depth**, not the primary control.

## 4. Tenant isolation

Each socket is bound to a single connector (and therefore tenant) at connect
time. A query is routed by `connectorId`; the internal-dispatch endpoint only
serves a connector whose socket the receiving instance actually holds. One
tenant's token can never reach another tenant's agent. In production, scope every
registry lookup and every forward by tenant id.

## 5. Auditability

Every generated SQL statement, the connector it ran on, and the invoking
principal should be written to an append-only audit log (this hooks naturally
into antrika-backend's `AIAgentExecutionStep`). It's both a control and a
selling point — customers can see exactly what ran inside their network.

## 6. Data governance — what actually leaves the network

**Securing the network path does not secure the data.** For TableArth this is the
other half of the story and often the bigger blocker for an enterprise buyer:

- The tunnel returns **result rows** to the control plane, and TableArth's
  question-answering may then send rows (and sampled schema data) to an LLM
  provider. A customer who just arranged an outbound-only tunnel will ask exactly
  where their production data goes next.
- Design the connection and the **egress policy as one feature**. The `QUERY`
  frame already carries a `policy` slot; wire it to per-connection modes:
  - **schema-only** — generate SQL from column names/types, never raw rows;
  - **masked-samples** — column masking before anything leaves the agent;
  - **full** — result rows may leave (default today).
- For the strictest customers, pair this with in-VPC inference (point their
  per-customer model provider at a model in their own account/region) so no rows
  cross the boundary at all.

Column masking is best enforced **in the agent**, before rows cross the boundary.

## Production hardening checklist

- [ ] mTLS on the tunnel (client certs issued at enrollment) + optional cert pinning
- [ ] Admin API delegated to antrika-backend SSO/session auth (drop the static token)
- [ ] Per-connection egress policy (schema-only / masked / full) enforced agent-side
- [ ] DB credentials sourced from the customer's secret manager (Vault/cloud KMS), not plaintext YAML
- [ ] Envelope-encrypt any server-side secrets with per-tenant KMS data keys
- [ ] Credit-based flow control on the tunnel (replace the fixed chunk cap)
- [ ] Append-only query audit log surfaced to the customer
- [ ] Signed release binaries (cosign) so customers verify provenance
- [ ] Rate limits + max message size on the tunnel and the internal-dispatch endpoint
