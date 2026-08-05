# Stack Architecture
```text
flowchart TB
    subgraph DockerHost["Docker Host"]
        subgraph MonitoringNetwork["monitoring network"]
            NE["Node Exporter"]
            CA["cAdvisor"]
            PR["Prometheus"]
            PT["Promtail"]
            GF["Grafana"]
            LK["Loki"]
        end
    end

    NE -->|metrics| PR
    CA -->|metrics| PR
    PR -->|metrics| GF

    PT -->|Docker logs| LK
    LK --> GF
```

Each component has a single responsibility:

| Service       | Purpose                                      |
| ------------- | -------------------------------------------- |
| Node Exporter | Host metrics (CPU, RAM, filesystem, network) |
| cAdvisor      | Container metrics                            |
| Prometheus    | Time-series database                         |
| Loki          | Log storage                                  |
| Promtail      | Log collection                               |
| Grafana       | Dashboards and visualization                 |

# Directory Layout
Since we've standardized storage, I'd use:

```text
/mnt/omv/.infra/docker/
├── grafana/
│   ├── data/
│   └── provisioning/
│       ├── dashboards/
│       └── datasources/
├── prometheus/
│   ├── data/
│   └── prometheus.yml
├── loki/
│   ├── data/
│   └── config.yml
├── promtail/
│   └── config.yml
└── cadvisor/
```

Notice that each service owns its own configuration and persistent data. That makes backups and migrations straightforward.

# Compose Layout
Under `/opt/docker`:
```text
compose/
└── monitoring/
    ├── compose.yml
    ├── .env
    ├── README.md
    └── Makefile
```

This pattern can be reused for `media`, `finance`, `home`, and so on.

# Deployment Order
Don't start all six containers at once. I recommend this sequence:

> [!tip]
> Always check the if the settings are valid with: `docker compose config`. If it succeeds, continue with:
> ```bash
> docker compose pull
> docker compose up -d
> ```

### Phase 1
* Prometheus
* Grafana

Verify:
* Grafana UI
* Prometheus UI
* Prometheus datasource

> Based on the problem had with the NFS (`root_squash`) permissions, will need to make some modifications.
I think that's the right long-term architecture. It follows the principle of keeping stateful databases on local storage while using network storage for durable backups. Updated storage layout:

```text
Proxmox
│
├── OMV VM
│   └── Shared Storage (NFS)
│       ├── backups/
│       │   ├── prometheus/
│       │   ├── grafana/
│       │   ├── loki/
│       │   └── docker-host/
│       └── ...
│
└── Docker Host VM
    ├── OS Disk
    │
    ├── /var/lib/prometheus      ← TSDB (local)
    ├── /var/lib/grafana         ← SQLite DB (local)
    ├── /var/lib/loki            ← Log index (local)
    ├── /opt/docker/compose
    └── /mnt/omv                 ← NFS mount (backups only)
```

Why this is better:

| Component          | Storage                 | Reason                                        |
| ------------------ | ----------------------- | --------------------------------------------- |
| Prometheus TSDB    | Local SSD/virtual disk  | High write rate, mmap files, best performance |
| Grafana DB         | Local                   | Small SQLite database, low latency            |
| Loki               | Local                   | Lots of sequential writes                     |
| Dashboards/Configs | Git + Compose directory | Easy to version control                       |
| Backups            | OMV NFS                 | Centralized, redundant storage                |

This separates **live application data** from **backup storage**, which is a common production pattern.

The [**backup job**](../scripts/prometheus_backup_job.sh) will be scheduled with `cron` timer to run overnight.  Grafana can follow the same pattern. Since it's much smaller than the TSDB, the backup is quick.

The applications data will be stored at:
```bash
/opt/docker/data
total 16
drwxrwsr-x 4 dockeradmin dockeradmin 4096 Aug  5 08:35 .
drwxr-sr-x 9 dockeradmin dockeradmin 4096 Aug  5 08:35 ..
drwxrwsr-x 2 472         472         4096 Aug  5 08:35 grafana
drwxrwsr-x 2 nobody      nogroup     4096 Aug  5 08:35 prometheus
```

> `472` is Grafana's container user and `nobody` is from Prometheus service: `uid=65534(nobody) gid=65534(nogroup)`.













### Phase 2
Add:
* Node Exporter

Confirm host metrics appear.

### Phase 3
Add:
* cAdvisor

Confirm container metrics appear.

### Phase 4
Add:
* Loki
* Promtail

Confirm logs arrive in Grafana.

This staged approach makes troubleshooting much easier than deploying everything in one go.

# Versions
I recommend pinning images to major versions rather than using `latest`.

For example:
```yaml
grafana/grafana:12
prom/prometheus:v3
grafana/loki:3
grafana/promtail:3
gcr.io/cadvisor/cadvisor:v0.53
prom/node-exporter:v1.10
```

This reduces the chance of unexpected breaking changes while still allowing minor and patch updates.

# Ports
Only expose services you actually use from your workstation. Initially:

| Service    | Port |
| ---------- | ---- |
| Grafana    | 3000 |
| Prometheus | 9090 |

Loki, Promtail, Node Exporter, and cAdvisor don't need to be directly accessible from your LAN. They only need to communicate within the `monitoring` Docker network.

# Configuration Strategy
I'd also keep configuration under version control:
```text
compose/monitoring/
├── compose.yml
├── grafana/
│   └── provisioning/
├── prometheus/
│   └── prometheus.yml
├── loki/
│   └── config.yml
└── promtail/
    └── config.yml
```

Then mount those files into the containers while keeping the persistent databases on OMV:
* Configuration → Git (`/opt/docker`)
* Persistent data → NFS (`/mnt/omv/.infra/docker/...`)

This separation is valuable because rebuilding the monitoring stack becomes as simple as:
1. Clone the repository.
2. Mount the NFS shares.
3. Run `docker compose up -d`.

All your dashboards, metrics, and logs remain on the NAS.

## My suggestion for the next step
Instead of writing a single large `compose.yml`, I'd build this stack incrementally. We'll start with **Prometheus and Grafana only**, verify they're working correctly, and then layer in the remaining components. By the end, you'll have a monitoring stack that also serves as the template for every future Compose project in your homelab.
