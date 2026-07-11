# TableArth Connector — downloads & docs

Query **production databases inside your private network** from TableArth —
with **no inbound firewall changes**. A lightweight **agent** runs next to your
database and dials out to TableArth over TLS; queries are pushed down that
tunnel and only result rows come back. Your database credentials never leave
your network.

This repo hosts the **prebuilt binaries** and **documentation** for the TableArth
database connector.

📖 **Docs:** [Install](docs/INSTALL.md) · [Architecture](docs/ARCHITECTURE.md) · [Security](docs/SECURITY.md) · [API](docs/API.md)

---

## Download the agent (v0.1.0)

Single static binary, no dependencies. Pick your platform:

| OS | x86-64 (Intel/AMD) | ARM64 (Apple Silicon / Graviton) |
|----|--------------------|----------------------------------|
| **Linux** | [tac-agent-linux-amd64](bin/tac-agent-linux-amd64) | [tac-agent-linux-arm64](bin/tac-agent-linux-arm64) |
| **macOS** | [tac-agent-darwin-amd64](bin/tac-agent-darwin-amd64) | [tac-agent-darwin-arm64](bin/tac-agent-darwin-arm64) |
| **Windows** | [tac-agent-windows-amd64.exe](bin/tac-agent-windows-amd64.exe) | [tac-agent-windows-arm64.exe](bin/tac-agent-windows-arm64.exe) |

Verify with [`bin/SHA256SUMS`](bin/SHA256SUMS).

## Quick install

**macOS / Linux**

```sh
curl -fsSL https://raw.githubusercontent.com/Antrika-Technologies-LLP/table-arth-connector/main/scripts/install.sh | sh
```

**Windows** (PowerShell, as Administrator)

```powershell
irm https://raw.githubusercontent.com/Antrika-Technologies-LLP/table-arth-connector/main/scripts/install.ps1 | iex
```

Then create your config and run the agent — full per-OS steps (systemd,
launchd, Windows service, Docker) are in **[docs/INSTALL.md](docs/INSTALL.md)**.

A minimal config:

```yaml
server_url: wss://connect.tablearth.com/ws/agent
enrollment_token: tac_enroll_xxxxxxxx      # one-time token from the TableArth console
data_sources:
  - name: prod
    kind: postgres
    # The DSN — with credentials — stays on this host and is never sent to
    # TableArth. Use a READ-ONLY database user.
    dsn: "postgres://readonly:PASSWORD@10.0.0.5:5432/proddb?sslmode=require"
```

## How it works (30 seconds)

1. A TableArth admin (or you) creates a **connector** in the console and gets a
   one-time **enrollment token**.
2. You install this agent next to your database, drop the token + your
   read-only DSN into its config, and start it.
3. The agent dials **out** to TableArth (no inbound ports), trades the token for
   a durable credential, and shows **online**.
4. Your analysts then ask questions in TableArth and get answers from the live
   database — read-only, through the tunnel.

See **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** and
**[docs/SECURITY.md](docs/SECURITY.md)** for the full model.

## Control plane (self-hosting the gateway)

TableArth normally runs the control-plane gateway for you. If you self-host it,
prebuilt binaries are in `bin/tac-control-*`, and `deploy/` has a
`docker-compose.yaml` (Mongo + 2 instances + nginx), a systemd unit, a launchd
plist, and an `nginx.conf`. Details in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).
