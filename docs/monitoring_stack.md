Rather than immediately writing a `compose.yml`, I'd spend a few minutes designing the stack so it stays maintainable over the years.

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

---

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

---

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

---

# Deployment Order

Don't start all six containers at once.

I recommend this sequence:

### Phase 1

* Prometheus
* Grafana

Verify:

* Grafana UI
* Prometheus UI
* Prometheus datasource

---

### Phase 2

Add:

* Node Exporter

Confirm host metrics appear.

---

### Phase 3

Add:

* cAdvisor

Confirm container metrics appear.

---

### Phase 4

Add:

* Loki
* Promtail

Confirm logs arrive in Grafana.

---

This staged approach makes troubleshooting much easier than deploying everything in one go.

---

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

---

# Ports

Only expose services you actually use from your workstation.

Initially:

| Service    | Port |
| ---------- | ---- |
| Grafana    | 3000 |
| Prometheus | 9090 |

Loki, Promtail, Node Exporter, and cAdvisor don't need to be directly accessible from your LAN. They only need to communicate within the `monitoring` Docker network.

---

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

---

## My suggestion for the next step

Instead of writing a single large `compose.yml`, I'd build this stack incrementally. We'll start with **Prometheus and Grafana only**, verify they're working correctly, and then layer in the remaining components. By the end, you'll have a monitoring stack that also serves as the template for every future Compose project in your homelab.
