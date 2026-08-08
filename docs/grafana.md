# Considerations

## Why not a dedicated PostgreSQL database?
When Grafana uses SQLite (the default), it stores its database inside its data directory:

```text
/mnt/omv/.infra/docker/grafana/data/
├── grafana.db
├── plugins/
├── png/
├── sessions/
└── ...
```

The file: `grafana.db` **is the database**. It contains:
- Users
- Password hashes
- Dashboards
- Folders
- Teams
- Datasources
- Alert rules
- Preferences
- Annotations
- API keys

Everything that would otherwise be stored in PostgreSQL.

## Why does Grafana default to SQLite?
Because Grafana is designed to run well as a standalone application.

Unless needed:
- High Availability (multiple Grafana instances)
- Thousands of dashboards/users
- Enterprise clustering

SQLite is the officially supported default.

In fact, if you install Grafana directly on Ubuntu (without Docker), it uses SQLite by default.

While SQLite (recommended for your homelab) pros:
- One less container
- Lower RAM usage
- Simpler backups
- Easier upgrades
- Less maintenance

While PostgreSQL pros:
- Better for HA
- Better for very large deployments

Cons:
- Another container
- Another volume
- Another backup
- Another upgrade cycle
- Another service that can fail

# Dashboards
Great. You're at the point where Grafana becomes useful. I recommend building the dashboards incrementally rather than importing a huge dashboard immediately. That way you'll understand where every metric comes from and troubleshooting becomes much easier.

> [!note] Verify Prometheus is receiving metrics
> In Prometheus (`http://<docker-host-ip>:9090`), go to **Graph** and try a few queries. CPU count:
> ```promql
> machine_cpu_cores
> ```
> Memory:
> ```promql
> node_memory_MemTotal_bytes
> ```
> Filesystem:
> ```promql
> node_filesystem_avail_bytes
> ```
> Network:
> ```promql
> rate(node_network_receive_bytes_total[1m])
> ```
> If those return values, Prometheus is working correctly.

## Add Prometheus as Grafana datasource
You probably already did this, but verify.  **Connections → Data Sources**

1. Datasource: `Prometheus`
2. URL: `http://prometheus:9090`
3. Save & Test

## Create your first dashboard
`Dashboards > New Dashboard > Add visualization` and choose your Prometheus datasource.

## CPU Usage
- Panel:
    - Gauge
    - Time series
- Unit: Percent (0-100)
- Query:
    ```promql
    100 - (
        avg by(instance)(
            rate(node_cpu_seconds_total{mode="idle"}[5m])
        ) * 100
    )
    ```

## Memory Usage
- Unit: Percent
- Visualization
    - Gauge
- Query:
    ```promql
    (
        1 -
        (
            node_memory_MemAvailable_bytes
            /
            node_memory_MemTotal_bytes
        )
    ) * 100
    ```

## Disk Usage
- Visualization
    - Gauge
- Query;
```promql
100 -
(
    node_filesystem_avail_bytes{
        fstype!="tmpfs",
        mountpoint="/"
    }
    /
    node_filesystem_size_bytes{
        fstype!="tmpfs",
        mountpoint="/"
    }
    *100
)
```

## Network Transit
### Receive
- Visualization: Time Series
- Unit: 
- Query: bytes/sec
```promql
rate(node_network_receive_bytes_total{
  device!~"^(lo|docker0|br-.*|veth.*)$"
}[1m])
```

other interface options are:
- `{device="br-c745024f224f", instance="host.docker.internal:9100", job="node-exporter"}`
- `{device="br-e0ea36b4f478", instance="host.docker.internal:9100", job="node-exporter"}`
- `{device="br-faf30614fac8", instance="host.docker.internal:9100", job="node-exporter"}`
- `{device="docker0", instance="host.docker.internal:9100", job="node-exporter"}`
- `{device="ens18", instance="host.docker.internal:9100", job="node-exporter"}`
- `{device="lo", instance="host.docker.internal:9100", job="node-exporter"}`
- `{device="veth4be29ea", instance="host.docker.internal:9100", job="node-exporter"}`
- `{device="vethfc7baa2", instance="host.docker.internal:9100", job="node-exporter"}`

### Transmit
```promql
rate(node_network_transmit_bytes_total[1m])
```


## System Load
represent the system's load average over different time windows (1/5/15mins). The load average is the average number of processes that are:
- Running on the CPU, or
- Waiting for CPU time (and on Linux, also processes waiting in uninterruptible I/O sleep).

```promql
node_load5
```

## Uptime
- Unit: seconds (duration)
```promql
time() - node_boot_time_seconds
```

## Available RAM
- Unit: Bytes (IEC)
```promql
node_memory_MemAvailable_bytes
```

## Free Disk
- Unit: Bytes (IEC)
```promql
node_filesystem_avail_bytes{mountpoint="/"}
```

## Temperature (if available)
Many VMs won't expose these sensors, so it's normal if no data appears.

```promql
node_hwmon_temp_celsius
```

or

```promql
node_thermal_zone_temp
```

## Explore metrics interactively
A very useful trick while learning is to use **Grafana Explore**:
1. Open **Explore**
2. Select Prometheus
3. Type: `node_`

Grafana will autocomplete all available metrics. You'll discover hundreds of metrics, such as:
- node_cpu_seconds_total
- node_memory_MemAvailable_bytes
- node_filesystem_size_bytes
- node_network_receive_bytes_total
- node_disk_read_bytes_total
- node_disk_written_bytes_total
- node_load1
- node_load5
- node_uname_info
- node_boot_time_seconds
- node_os_info
- node_time_seconds
- ...

This is the fastest way to learn what Node Exporter exposes.

## Suggested next steps for your homelab
Based on the architecture you've been building, I'd add monitoring in this order:
1. ✅ Docker Host (completed)
2. **cAdvisor** — per-container CPU, RAM, network, filesystem metrics
3. **Promtail + Loki** — centralized logs
4. **Proxmox VE Exporter** — monitor your hypervisor
5. **OpenMediaVault metrics** — storage health and usage
6. **Home Assistant metrics** — automation and entity insights
7. **UPS (NUT exporter)** — battery level, runtime, and power events
8. **Raspberry Pi Node Exporter** — infrastructure-wide host monitoring

By the end, Grafana can provide a single pane of glass for your entire homelab, showing the physical server, Proxmox, VMs, Docker containers, storage, UPS, and smart home services together.
