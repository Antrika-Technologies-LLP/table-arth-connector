# Installing the connector agent

The agent is a single static binary with **no runtime dependencies**. It makes
only **outbound** HTTPS/WSS connections, so no inbound firewall rule is needed.

Supported: **Ubuntu/Debian, RHEL/Rocky/Alma, macOS, Windows** (amd64 + arm64),
and any container runtime.

Before you start, create a connector in the console (**New connector**) and copy
its one-time **enrollment token**. On first connect the agent exchanges it for a
durable credential it stores locally, so you only ever paste the short-lived
token.

> **Always point the agent at a read-only database user.** That is the
> authoritative control that keeps it read-only. See [SECURITY.md](SECURITY.md).

---

## Ubuntu / Debian

```bash
# 1. Install (adds a systemd service)
curl -fsSL https://get.tablearth.com/connector/install.sh | sudo bash

# 2. Configure
sudo mkdir -p /etc/table-arth-connector
sudo tee /etc/table-arth-connector/config.yaml >/dev/null <<'EOF'
server_url: wss://connect.tablearth.com/ws/agent
enrollment_token: tac_enroll_xxxxxxxx
credentials_path: /var/lib/table-arth-connector/credentials.json
data_sources:
  - name: prod
    kind: postgres
    dsn: "postgres://readonly:PASSWORD@10.0.0.5:5432/proddb?sslmode=require"
EOF

# 3. Install the service unit and start it
sudo useradd --system --no-create-home tac || true
sudo cp deploy/systemd/table-arth-connector.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now table-arth-connector
sudo systemctl status table-arth-connector
journalctl -u table-arth-connector -f
```

## RHEL / Rocky / Alma

Identical to Ubuntu. If SELinux is enforcing, no extra policy is required — the
agent only makes **outbound** connections and writes to its own state dir. To
confirm outbound egress on 443 is allowed:

```bash
sudo dnf install -y nc || sudo yum install -y nc
nc -zv connect.tablearth.com 443
```

## macOS

```bash
# 1. Install the binary
curl -fsSL https://get.tablearth.com/connector/install.sh | sh

# 2. Configure
mkdir -p ~/.table-arth-connector
cat > ~/.table-arth-connector/config.yaml <<'EOF'
server_url: wss://connect.tablearth.com/ws/agent
enrollment_token: tac_enroll_xxxxxxxx
data_sources:
  - name: prod
    kind: postgres
    dsn: "postgres://readonly:PASSWORD@10.0.0.5:5432/proddb?sslmode=require"
EOF

# 3a. Run in the foreground
tac-agent -config ~/.table-arth-connector/config.yaml

# 3b. …or run at login as a LaunchAgent
sudo cp deploy/launchd/com.tablearth.connector.plist /Library/LaunchDaemons/
sudo mkdir -p /usr/local/etc/table-arth-connector
sudo cp ~/.table-arth-connector/config.yaml /usr/local/etc/table-arth-connector/config.yaml
sudo launchctl load /Library/LaunchDaemons/com.tablearth.connector.plist
```

## Windows

PowerShell, **as Administrator**:

```powershell
# 1. Install the service
irm https://get.tablearth.com/connector/install.ps1 | iex

# 2. Configure
New-Item -ItemType Directory -Force C:\ProgramData\table-arth-connector | Out-Null
@'
server_url: wss://connect.tablearth.com/ws/agent
enrollment_token: tac_enroll_xxxxxxxx
credentials_path: C:\ProgramData\table-arth-connector\credentials.json
data_sources:
  - name: prod
    kind: postgres
    dsn: "postgres://readonly:PASSWORD@10.0.0.5:5432/proddb?sslmode=require"
'@ | Set-Content -Encoding UTF8 C:\ProgramData\table-arth-connector\config.yaml

# 3. Start
Start-Service TableArthConnector
Get-Service TableArthConnector
```

No installer? Run the binary directly — it works the same:

```powershell
tac-agent.exe -config C:\ProgramData\table-arth-connector\config.yaml
```

## Docker

```bash
docker run -d --name tac-agent --restart unless-stopped \
  -v "$PWD/config.yaml:/etc/tac/config.yaml:ro" \
  -v tac-creds:/var/lib/table-arth-connector \
  ghcr.io/tablearth/connector-agent:latest \
  -config /etc/tac/config.yaml
```

The image is `distroless/static:nonroot` — it contains only the binary.

## Build from source

```bash
make build                 # ./dist/tac-agent, ./dist/tac-control (host OS)
make release               # cross-compile the agent for every OS/arch → dist/release/
```

Cross-compiling needs no C toolchain (the agent is CGO-free): it is a pure
`GOOS/GOARCH` matrix.

## Configuration reference

| Key | Env override | Notes |
|-----|--------------|-------|
| `server_url` | `TAC_SERVER_URL` | `wss://…/ws/agent` (control-plane tunnel endpoint) |
| `enrollment_token` | `TAC_ENROLLMENT_TOKEN` | One-time; only needed until enrolled |
| `credentials_path` | — | Where the durable credential is stored (mode 0600) |
| `insecure_tls` | `TAC_INSECURE_TLS=true` | Dev only — skip TLS verification |
| `data_sources[]` | — | `name`, `kind`, `dsn` (all stay local — see below) |

## Supported databases

Set each source's `kind` and give a `dsn` for a **read-only** database user. The
DSN — including credentials — never leaves the agent host.

| `kind` | Database | DSN example |
|--------|----------|-------------|
| `postgres` | PostgreSQL | `postgres://readonly:PASSWORD@host:5432/db?sslmode=require` |
| `supabase` | Supabase (Postgres) | `postgres://readonly.REF:PASSWORD@aws-0-region.pooler.supabase.com:5432/postgres?sslmode=require` |
| `mysql` | MySQL / MariaDB | `readonly:PASSWORD@tcp(host:3306)/db?tls=preferred&parseTime=true` |
| `sqlserver` | SQL Server | `sqlserver://readonly:PASSWORD@host:1433?database=db&encrypt=true` |
| `clickhouse` | ClickHouse | `clickhouse://readonly:PASSWORD@host:9000/db?secure=true` |
| `snowflake` | Snowflake | `readonly:PASSWORD@org-acct/DB/SCHEMA?warehouse=WH&role=READONLY` |
| `oracle` | Oracle | `oracle://readonly:PASSWORD@host:1521/SERVICE` |
| `sqlite` | SQLite (local / testing) | `file:/var/data/app.db?mode=ro` |

A full config showing every database is in
[examples/agent.config.example.yaml](../examples/agent.config.example.yaml).
(MongoDB is non-SQL and uses a separate path; BigQuery is not yet in the agent.)

## Verifying

- Agent log prints `CONNECTED: connector=… session=…`.
- The console shows the connector as **Online** with the agent's hostname.
- `tac-agent -version` prints the build version.
