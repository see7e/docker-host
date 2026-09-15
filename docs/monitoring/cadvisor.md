# cAdvisor
is a great next step because it complements Node Exporter rather than replacing it.
- **node exporter** → host (cpu, ram, disks, network interfaces)
- **cadvisor** → containers (cpu, memory, filesystem, network, restarts)

The architecture will become:
```text
Docker Host
├── Prometheus
├── Grafana
├── Node Exporter
└── cAdvisor
         │
         ├── Grafana
         ├── Prometheus
         ├── Jellyfin
         ├── Immich
         ├── ...
```

## Add cAdvisor to docker-compose.yml
Inside your monitoring compose, add:
```yaml
  cadvisor:
    image: gcr.io/cadvisor/cadvisor:v0.53.0
    container_name: cadvisor
    restart: unless-stopped

    ports:
      - "8080:8080"

    volumes:
      - /:/rootfs:ro
      - /var/run:/var/run:ro
      - /sys:/sys:ro
      - /var/lib/docker:/var/lib/docker:ro
      - /dev/disk:/dev/disk:ro

    privileged: true

    devices:
      - /dev/kmsg

    command:
      - "--docker_only=true"
      - "--housekeeping_interval=30s"
      - "--max_housekeeping_interval=35s"
      - "--store_container_labels=false"

    networks:
      - monitoring
```

## Start it
```bash
docker compose down
docker compose up -d 
```

Verify:
```bash
docker ps
```

Should see something similar to: `cadvisor    Up`

## Test the endpoint
Open: `http://docker-host-ip:8080/metrics` or from the server: `curl localhost:8080/metrics` and should see thousands of lines beginning with metrics like:
- `container_cpu_usage_seconds_total`
- `container_memory_usage_bytes`
- `container_network_receive_bytes_total`
- ...

## Configure Prometheus
Add a new scrape job to `prometheus.yml`:
```yaml
scrape_configs:
  ...

  - job_name: cadvisor
    static_configs:
      - targets:
          - cadvisor:8080
```

Because Prometheus and cAdvisor are on the same Docker network, `cadvisor:8080` should resolve correctly.

Restart Prometheus:
```bash
docker compose down prometheus
docker compose up -d prometheus
```

## Verify Prometheus
Open: `http://<prometheus-ip>:9090/targets` and should see:

| Job           | State |
| ------------- | ----- |
| prometheus    | UP    |
| node-exporter | UP    |
| cadvisor      | UP    |

## Verify metrics
Go to **Prometheus → Graph** and try:

- `container_last_seen`
- `container_cpu_usage_seconds_total`
- `container_memory_usage_bytes`

If you see data points, cAdvisor is working correctly.

## Add a Grafana dashboard
The community has several excellent Docker/cAdvisor dashboards. A commonly used starting point is **Docker and System Monitoring** (dashboard ID **893**), which combines Node Exporter and cAdvisor metrics into a single view. Another popular option focused on containers is **Docker Container & Host Metrics** (dashboard ID **19792**).

Once imported, you should immediately see panels for:
- CPU usage per container
- Memory usage per container
- Network throughput
- Filesystem usage
- Container uptime
- Running container count

> [!warning]
> **One recommendation**: Since we're building this homelab to be maintainable, I'd make one small improvement now rather than later.
> Instead of exposing every exporter to your LAN, only expose services you actually access directly:
>
> | Service    | Expose Port?     | Reason                            |
> | ---------- | ---------------- | --------------------------------- |
> | Grafana    | ✅ Yes            | You use the UI                    |
> | Prometheus | ✅ Yes (optional) | Useful for troubleshooting        |
> | cAdvisor   | ❌ No             | Prometheus accesses it internally |
> | Loki       | ❌ No             | Internal service                  |
> | Alloy      | ❌ No             | Internal service                  |
> | Exporters  | ❌ No             | Internal service                  |
>
> So for cAdvisor, I'd actually recommend not publishing port 8080 once you've confirmed it's working, remove this:
> ```yml
> ports:
>   - "8080:8080"
> ```
> Prometheus can still scrape cadvisor:8080 over the monitoring network, and you reduce the attack surface of your Docker host.

> [!note]
> **cAdvisor itself doesn't need persistent storage**. Unlike Grafana or Prometheus, cAdvisor is stateless.
> So you don't need to create something like: `/opt/docker/data/cadvisor`. 
> There is nothing to persist. If you remove and recreate the container, nothing is lost because Prometheus is responsible for storing the historical metrics.

> [!info]
> The current cAdvisor dashboard is sourced from [this template](https://grafana.com/grafana/dashboards/19724-y0nei-s-cadvisor-exporter/).
