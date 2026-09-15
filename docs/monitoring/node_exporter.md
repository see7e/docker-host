# Node Exporter
```text
                    ┌──────────────────────┐
                    │      Proxmox VE       │
                    │     192.168.1.200     │
                    └──────────┬───────────┘
                               │
             ┌─────────────────┴─────────────────┐
             │                                   │
     ┌───────▼────────┐                  ┌───────▼────────┐
     │  OMV VM         │                  │ Docker Host VM │
     │  OpenMediaVault │                  │ Ubuntu 26.04   │
     │                 │                  │                │
     │ Node Exporter   │                  │ Node Exporter  │
     └───────┬─────────┘                  └───────┬────────┘
             │                                    │
             │ :9100                              │ :9100
             └────────────────┬───────────────────┘
                              │
                       ┌──────▼──────┐
                       │ Prometheus  │
                       └──────┬──────┘
                              │
                       ┌──────▼──────┐
                       │   Grafana   │
                       └─────────────┘
```

# In Docker Host
## Download Node Exporter
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

## Create dedicated user
```bash
sudo useradd --no-create-home \
             --shell /bin/false \
             node_exporter
```

## Create systemd service
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

## Enable service
```bash
sudo systemctl daemon-reload
sudo systemctl enable node_exporter
sudo systemctl start node_exporter
# Created symlink '/etc/systemd/system/multi-user.target.wants/node_exporter.service' → '/etc/systemd/system/node_exporter.service'.
```

## Verify
```bash
systemctl status node_exporter --no-pager
```

Should show `Active: active (running)`

## Test metrics
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

## Open firewall (if using UFW)
If enabled:
```bash
sudo ufw allow 9100/tcp
```

## Add to Prometheus
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

## Expose the host to containers
Edit `compose.yml` for the Prometheus service:
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

## Verify in Prometheus
Open: `http://YOUR_DOCKER_VM:9090/targets` You should see: `node UP`

## Import Grafana Dashboard
The classic dashboard for Node Exporter is: **Grafana Dashboard ID:** **1860**

It provides:
- CPU utilization
- Load average
- Memory usage
- Swap
- Network throughput
- Disk usage
- Disk I/O
- Filesystem usage
- Temperatures (if available)
- Processes
- System uptime

This is the de facto standard dashboard for Linux hosts.

### Expected monitoring stack after this step
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

# In OMV
This is preferable to trying to make OMV expose some special OMV-specific metric endpoint. **Node Exporter gives us the underlying Linux/storage/network metrics**, which is exactly what we need.

## 1. First, check the OMV VM
SSH into the OMV VM and run:

```bash
hostname
hostname -I
cat /etc/os-release
uname -a
```

Then check whether Node Exporter is already installed:

```bash
systemctl status node_exporter
```

and:

```bash
ss -lntp | grep 9100
```

If both return nothing useful, we'll install it.

### 2. What we'll monitor

For OMV, I suggest we build the monitoring in this order:

**Host**

* CPU utilization
* Load
* RAM utilization
* Swap
* Uptime

**Storage**

* `/` filesystem
* `/srv/dev-disk-by-uuid-...`
* RAID1 filesystem usage
* Disk read/write throughput
* Disk IOPS
* Disk latency
* Disk space
* inode usage

**Network**

* Interface traffic
* RX/TX errors
* dropped packets

**Important for your OMV setup**

* RAID status
* RAID degraded state
* Disk health/SMART later
* NFS activity
* system temperature if exposed

And eventually:

```text
OMV
├── Node Exporter
│   ├── CPU
│   ├── RAM
│   ├── filesystem
│   ├── network
│   └── disk I/O
│
├── RAID monitoring
│   └── md127
│
├── SMART monitoring
│   └── physical disks
│
└── NFS monitoring
```

The **RAID and SMART portions are separate from basic Node Exporter**, so I would not complicate the initial setup with them.

### 3. Important detail about your RAID

From our previous setup, your OMV storage currently looks roughly like:

```text
OMV VM
├── OS disk
│   └── ~16 GiB
│
└── Data disks
    ├── ~3.64 TiB
    └── ~3.64 TiB
          │
          ▼
        md127
          │
          ▼
    RAID1 filesystem
```

So once Node Exporter is running, we'll specifically verify that Prometheus can see the filesystem mounted under:

```text
/srv/dev-disk-by-uuid-5a2a7709-6542-4c38-8ec0-9fdbafc3af54
```

That will let us create useful alerts such as:

```text
OMV filesystem > 80%     → warning
OMV filesystem > 90%     → critical
RAID degraded             → critical
OMV host down             → critical
Disk errors increasing    → critical
```

### Let's start with OMV

Run these **on the OMV VM**, and paste the output:

```bash
hostname
hostname -I
cat /etc/os-release
systemctl status node_exporter --no-pager
ss -lntp | grep 9100 || true
```

Then we'll install/configure Node Exporter if necessary, add the OMV target to your existing Prometheus configuration, verify it is **UP**, and only then move on to the OMV Grafana dashboard.