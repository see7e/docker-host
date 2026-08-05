# 1. Download Node Exporter
Follow the [guide](https://prometheus.io/docs/guides/node-exporter/) and on the Docker VM extract:

```bash
tar xvf node_exporter-1.10.0.linux-amd64.tar.gz
```

Move the binary:

```bash
sudo mv node_exporter-1.10.0.linux-amd64/node_exporter/node_exporter /usr/local/bin/ # or the binary download location
```

Verify:
```bash
node_exporter --version
```

# 2. Create dedicated user
```bash
sudo useradd --no-create-home \
             --shell /bin/false \
             node_exporter
```

# 3. Create systemd service
```bash
sudo nano /etc/systemd/system/node_exporter.service
```

Paste:
```ini
[Unit]
Description=Prometheus Node Exporter
After=network-online.target

[Service]
User=node_exporter
Group=node_exporter
Type=simple
ExecStart=/usr/local/bin/node_exporter

Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

Save.

# 4. Enable service
```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
# Created symlink '/etc/systemd/system/multi-user.target.wants/node_exporter.service' → '/etc/systemd/system/node_exporter.service'.
```

# 5. Verify
```bash
systemctl status node_exporter
```

Should show `Active: active (running)`

# 6. Test metrics
From the Docker VM:
```bash
curl http://localhost:9100/metrics
```

You should see hundreds of metrics:
```
node_cpu_seconds_total
node_memory_MemAvailable_bytes
node_filesystem_avail_bytes
...
```

# 7. Open firewall (if using UFW)
If enabled:
```bash
sudo ufw allow 9100/tcp
```

# 8. Add to Prometheus

Edit:

```bash
nano /opt/docker/compose/monitoring/prometheus/prometheus.yml
```

Add:

```yaml
scrape_configs:
  - job_name: prometheus
    static_configs:
      - targets:
          - localhost:9090

  - job_name: node
    static_configs:
      - targets:
          - host.docker.internal:9100
```

Because Prometheus is running in Docker while Node Exporter is running on the host OS, we need Docker to resolve `host.docker.internal`.

---

## 9. Expose the host to containers

Edit your `docker-compose.yml` for the Prometheus service:

```yaml
services:
  prometheus:
    ...
    extra_hosts:
      - "host.docker.internal:host-gateway"
```

Example:

```yaml
prometheus:
  image: prom/prometheus

  extra_hosts:
    - "host.docker.internal:host-gateway"
```

Then restart:

```bash
docker compose up -d
```

---

# 10. Verify in Prometheus

Open:

```
http://YOUR_DOCKER_VM:9090/targets
```

You should see:

```
node
UP
```

---

# 11. Import Grafana Dashboard

The classic dashboard for Node Exporter is:

**Grafana Dashboard ID:** **1860**

It provides:

* CPU utilization
* Load average
* Memory usage
* Swap
* Network throughput
* Disk usage
* Disk I/O
* Filesystem usage
* Temperatures (if available)
* Processes
* System uptime

This is the de facto standard dashboard for Linux hosts.

---

## Expected monitoring stack after this step

```
Docker Host
│
├── Prometheus
├── Grafana
├── Node Exporter
│
└── Docker
     ├── Prometheus
     └── Grafana
```

After Node Exporter is confirmed working, I'd recommend moving to the **Proxmox VE exporter**. That will let Grafana display the Proxmox node, VM CPU/RAM usage, storage pools, and eventually LXC containers alongside the Docker host, giving you a complete infrastructure overview.
