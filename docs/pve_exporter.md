# PVE Exporter
At this point the current stack status is:

| Status | Component                  |
| :----: | -------------------------- |
| ✅      | Docker Host                |
| ✅      | Prometheus                 |
| ✅      | Grafana                    |
| ✅      | Node Exporter              |
| ✅      | cAdvisor                   |
| ✅      | Loki                       |
| ✅      | Alloy                      |
| ⏳      | **Proxmox VE Exporter**    |
| ⏳      | OpenMediaVault metrics     |
| ⏳      | Home Assistant metrics     |
| ⏳      | UPS (NUT exporter)         |
| ⏳      | Raspberry Pi Node Exporter |
| ⏳      | Alertmanager               |
| ⏳      | Grafana Alerting           |

---

## Goal
Add **Proxmox VE metrics** to Prometheus. This gives you metrics such as:
- CPU usage
- Memory usage
- Disk usage
- Network traffic
- VM status
- LXC status
- Storage usage
- Cluster information
- Node temperatures (where available)

These metrics come directly from the Proxmox API.

## Which exporter?
I recommend **prometheus-pve-exporter**. It is the standard exporter for Proxmox and is actively maintained. Architecture:
```
                +---------------------+
                |    Prometheus       |
                +----------+----------+
                           |
                     scrape :9221
                           |
                +----------v----------+
                | PVE Exporter        |
                +----------+----------+
                           |
                     HTTPS API
                           |
                +----------v----------+
                | Proxmox VE          |
                +---------------------+
```

## Create a Proxmox API user
On the Proxmox host: `Datacenter > Permissions > Users`, create:
- Username: `prometheus`
- Realm: `pve` or Proxmox VE authentication server

## Create a Token
`Datacenter > Permissions > API Tokens`, create:
- User: prometheus@pve
- Token ID: prometheus
- Privilege Separation: Disabled

After creating it you'll receive something like: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`, save it.

## Permissions
Create a role. `Datacenter > Permissions > Roles`:

- Name: `PrometheusAuditor`
- Privileges:
    - `Sys.Audit`
    - `VM.Audit`
    - `Datastore.Audit`
    - `SDN.Audit`

Then: `Permissions > Add > API Token Permission`:
- Path: `/`
- User: `prometheus@pve`
- Role: `PrometheusAuditor`
- Propagate: Enabled

Do the same for `User Permission`. This keeps the exporter completely read-only.

> [!note]
> API-token permissions are a subset of the corresponding user's permissions. In other words, the effective permission is constrained by both the user and the token. Proxmox explicitly documents this behavior.

Confirm with:
```bash
root@pve:~# pveum acl list
# ┌──────┬───────────────────┬───────┬───────────────────────────┬───────────┐
# │ path │ roleid            │ type  │ ugid                      │ propagate │
# ╞══════╪═══════════════════╪═══════╪═══════════════════════════╪═══════════╡
# │ /    │ PrometheusAuditor │ user  │ prometheus@pve            │ 1         │
# ├──────┼───────────────────┼───────┼───────────────────────────┼───────────┤
# │ /    │ PrometheusAuditor │ token │ prometheus@pve!prometheus │ 1         │
# └──────┴───────────────────┴───────┴───────────────────────────┴───────────┘
```

## Create Docker compose
I'd keep it alongside your existing monitoring stack. Example service:

```yaml
  pve-exporter:
    image: prompve/prometheus-pve-exporter:latest

    restart: unless-stopped

    environment:
      PVE_USER: prometheus@pve
      PVE_TOKEN_NAME: prometheus
      PVE_TOKEN_VALUE: ${PROMETHEUS_PVE_TOKEN}
      PVE_VERIFY_SSL: "false"

    healthcheck:
      test: ["CMD-SHELL", "wget -q --spider http://127.0.0.1:9221/metrics || exit 1"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s

    networks:
      - monitoring
```

## Prometheus
Add another job to your existing `prometheus.yml`:
```yaml
- job_name: proxmox

  static_configs:
    - targets:
        - pve-exporter:9221
```

Start/Update the services:
```bash
docker compose down
docker compose up -d
```

## Verify
Run and check if the containers are healthy:
```bash
docker ps
```

Then in Prometheus `Status > Targets` you should see `proxmox UP`.

## Grafana
Once the exporter is working, we'll import a dashboard that displays:
- Cluster overview
- Host CPU
- Host Memory
- Host Network
- VM CPU
- VM Memory
- LXC statistics
- Storage utilization
- ZFS (if applicable)
- Node health

### One improvement to the deployment
Rather than embedding the API token directly in `compose.yml`, store it in a `.env` file, just as you've done for your Grafana credentials. For example:

```
PVE_USER=prometheus@pve
PVE_TOKEN_NAME=prometheus
PVE_TOKEN_VALUE=<your-token>
PVE_VERIFY_SSL=false
```

Then reference those variables in Compose. This keeps sensitive credentials out of version-controlled configuration.

> Prometheus is on the same Docker network, so it can scrape the exporter using its container name. Unless you specifically want to access `/metrics` from outside Docker, you can omit the `ports:` section entirely. This reduces the exposed attack surface without affecting Prometheus' ability to scrape metrics.










