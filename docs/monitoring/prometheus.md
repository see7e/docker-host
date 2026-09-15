# Still on the configurations
At the moment there's two yml files, one to build the service with Docker and the other one to configure the Prometheus.

- [compose.yml](../compose/monitoring/compose.yml)
- [prometheus.yml](../compose/monitoring/prometheus/prometheus.yml)

The configuration we've been building is **pull-based**, which is one of the core design principles of Prometheus.

# Pull vs Push models
## Pull model

```text
                   Prometheus
                        │
       every 15 seconds │ GET /metrics
                        ▼
        ┌─────────────────────────────────┐
        │ node-exporter                   │
        │ cadvisor                        │
        │ proxmox-exporter                │
        │ nut-exporter                    │
        │ postgres-exporter               │
        └─────────────────────────────────┘
```

The `scrape_configs` in `prometheus.yml` tell Prometheus **where to pull metrics from**.

For example:
```yaml
scrape_configs:
  - job_name: node-exporter
    static_configs:
      - targets:
          - node-exporter:9100
```

Every 15 seconds (or whatever `scrape_interval` is), Prometheus sends an HTTP request to:

```text
http://node-exporter:9100/metrics
```

The exporter responds with plain text metrics, and Prometheus stores them.

## Why pull?
Prometheus was designed this way because it offers several advantages:
* **Service discovery:** Prometheus can automatically find new targets (Docker, Kubernetes, Consul, etc.).
* **Health monitoring:** If a target stops responding, Prometheus immediately knows it is **DOWN**.
* **Centralized control:** Only Prometheus needs to know the scrape interval and retention settings.
* **No credentials on exporters:** Exporters don't need permission to push data anywhere.

## When is push used?
Some workloads can't be scraped directly, such as:
* Short-lived batch jobs
* Cron jobs
* One-time scripts

For those, Prometheus provides the **Pushgateway**.

Example:

```text
Backup Script
      │
      └── Push metrics
               │
               ▼
        Pushgateway
               ▲
               │
        Prometheus scrapes
```

Notice that even here, **Prometheus still pulls**—it scrapes the Pushgateway. The application pushes only to the intermediary.

## The homelab
Everything you've planned fits naturally into the pull model:

| Component           | Model                                |
| ------------------- | ------------------------------------ |
| Prometheus          | Pull                                 |
| Node Exporter       | Pulled                               |
| cAdvisor            | Pulled                               |
| Proxmox Exporter    | Pulled                               |
| NUT Exporter        | Pulled                               |
| PostgreSQL Exporter | Pulled                               |
| Loki                | Not a metrics source (logs)          |
| Promtail            | Pushes logs to Loki (not Prometheus) |

So your architecture will look like this:

```text
                 +-------------------+
                 |    Prometheus     |
                 +-------------------+
                   ↑      ↑      ↑
                   │      │      │
             HTTP /metrics pulls
                   │      │      │
        +----------+------+------+
        |          |             |
 Node Exporter  cAdvisor  Proxmox Exporter
        |          |             |
 Docker VM     Containers     Proxmox Host

                     ↓

                 Grafana
                     │
     Queries Prometheus (metrics)
     Queries Loki (logs)
```

This is exactly the architecture Prometheus was designed for and scales well from a single Docker VM to much larger environments.
