# AlertManager
Given the current stack, I'd configure it in this order:
1. **Deploy Alertmanager** in the existing monitoring Compose stack.
2. **Configure Prometheus → Alertmanager**.
3. Add a small initial set of useful alerts:
   - Docker host down
   - Prometheus target down
   - High CPU
   - High RAM
   - High disk usage
   - High filesystem/inode usage
   - UPS on battery
   - UPS battery critically low
   - Proxmox/OMV/HA targets down

4. Verify alerts through Prometheus' **Alerts** page.
5. Verify Alertmanager receives them.
6. Configure a notification receiver afterward (email, Telegram, Discord, etc.).
7. Finally, add Grafana alerting only where it provides something Prometheus alerts don't.

I would **not** start with Grafana alerting yet. For infrastructure health, Prometheus + Alertmanager gives you a cleaner and more centralized setup.

Since your monitoring stack is already running in `/opt/docker/compose/monitoring`, the first step should be checking your current `compose.yml` and Prometheus configuration so we don't overwrite anything you've already customized.

## Configuration
One important thing first: **your NUT exporter is already being scraped through the `nut-exporter` container**, so we'll build the UPS alerts against the metrics Prometheus is already receiving rather than changing that configuration.

### 1. Add Alertmanager to `compose.yml`
Add this service alongside Prometheus/Grafana:

```yaml
  alertmanager:
    image: prom/alertmanager:v0.29.0
    restart: unless-stopped

    command:
      - "--config.file=/etc/alertmanager/alertmanager.yml"
      - "--storage.path=/alertmanager"

    volumes:
      - /opt/docker/data/alertmanager:/alertmanager
      - ./alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro

    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:9093/-/healthy"]
      interval: 30s
      timeout: 5s
      retries: 3

    networks:
      - monitoring
```

> [!note]
> Alertmanager will run at `:9093` but we don't need to expose it outside of the `monitoring` network.

I'd keep the Alertmanager data outside the Compose directory, consistent with your Prometheus/Grafana/Loki setup: `/opt/docker/data/alertmanager`.
```bash
mkdir -p /opt/docker/compose/monitoring/alertmanager
mkdir -p /opt/docker/data/alertmanager
```

### 2. Create the initial Alertmanager configuration
For now, don't configure email/Telegram/etc. We'll first get the **Prometheus → Alertmanager pipeline** working. Create `alertmanager/alertmanager.yml` with:
```yaml
global:
  resolve_timeout: 5m

route:
  group_by:
    - alertname
    - instance
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: default

receivers:
  - name: default
```

This **intentionally** has no external notification receiver yet. Alertmanager can still receive, group, and display alerts.

### 3. Tell Prometheus where Alertmanager is
Add this **before `scrape_configs:`** in `prometheus.yml`:
```yaml
global:
  ...

alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

scrape_configs:
  ...
```

The important detail is that we're using: `alertmanager:9093` not `localhost:9093`, because Prometheus and Alertmanager are separate containers on the `monitoring` Docker network.

### 4. Add Prometheus alert rules
I'd keep the rules in a separate file rather than putting them directly into `prometheus.yml`. Create `prometheus/alerts.yml` and start with these:
```yaml
groups:
  - name: infrastructure
    interval: 30s

    rules:

      # ------------------------------------------------------------
      # Targets
      # ------------------------------------------------------------

      - alert: TargetDown
        expr: up == 0
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "Prometheus target is down"
          description: "{{ $labels.job }} target {{ $labels.instance }} has been down for more than 2 minutes."

      # ------------------------------------------------------------
      # Docker host
      # ------------------------------------------------------------

      - alert: HostHighCPU
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High CPU usage on {{ $labels.instance }}"
          description: "CPU usage has been above 85% for more than 10 minutes."

      - alert: HostCriticalCPU
        expr: 100 - (avg by (instance) (rate(node_cpu_seconds_total{mode="idle"}[5m])) * 100) > 95
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Critical CPU usage on {{ $labels.instance }}"
          description: "CPU usage has been above 95% for more than 5 minutes."

      - alert: HostHighMemory
        expr: |
          (
            1 -
            node_memory_MemAvailable_bytes /
            node_memory_MemTotal_bytes
          ) * 100 > 90
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "High memory usage on {{ $labels.instance }}"
          description: "Memory usage has been above 90% for more than 10 minutes."

      # ------------------------------------------------------------
      # Filesystems
      # ------------------------------------------------------------

      - alert: HostDiskAlmostFull
        expr: |
          (
            1 -
            node_filesystem_avail_bytes{
              fstype!~"tmpfs|overlay|squashfs"
            }
            /
            node_filesystem_size_bytes{
              fstype!~"tmpfs|overlay|squashfs"
            }
          ) * 100 > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "Disk usage high on {{ $labels.instance }}"
          description: "Filesystem {{ $labels.mountpoint }} is more than 85% full."

      - alert: HostDiskCritical
        expr: |
          (
            1 -
            node_filesystem_avail_bytes{
              fstype!~"tmpfs|overlay|squashfs"
            }
            /
            node_filesystem_size_bytes{
              fstype!~"tmpfs|overlay|squashfs"
            }
          ) * 100 > 95
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Disk critically full on {{ $labels.instance }}"
          description: "Filesystem {{ $labels.mountpoint }} is more than 95% full."

      # ------------------------------------------------------------
      # UPS / NUT
      # ------------------------------------------------------------

      - alert: UPSOnBattery
        expr: nut_ups_status{status="OB"} == 1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "UPS is running on battery"
          description: "UPS {{ $labels.instance }} has been running on battery for more than 2 minutes."

      - alert: UPSBatteryLow
        expr: nut_battery_charge_percent < 30
        for: 2m
        labels:
          severity: critical
        annotations:
          summary: "UPS battery is low"
          description: "UPS battery charge is below 30%."

      - alert: UPSBatteryCritical
        expr: nut_battery_charge_percent < 15
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "UPS battery critically low"
          description: "UPS battery charge is below 15%."
```

> **One caveat:** NUT exporter metric names can differ depending on the exporter/version and labels. Before enabling the UPS rules, we'll verify the exact metrics you're currently getting. I don't want to guess here, especially since your NUT setup is already working.

### 5. Tell Prometheus to load the rules
Add this after `global:` and before `alerting:`:
```yaml
global:
  ...

rule_files:
  - /etc/prometheus/alerts.yml

alerting:
  ...

scrape_configs:
  ...
```

And add the volume to your Prometheus service:
```yaml
volumes:
  - /opt/docker/data/prometheus:/prometheus
  - ./prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
  - ./prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro # <--
  - ./prometheus/secrets:/etc/prometheus/secrets:ro
```

### 6. Validate before restarting
This is worth doing before `docker compose up -d`. From your monitoring directory:
```bash
docker compose config
```

Then validate the Prometheus configuration:

```bash
docker run --rm \
  --entrypoint=/bin/promtool \
  -v "$PWD/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro" \
  -v "$PWD/prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro" \
  -v "$PWD/prometheus/secrets:/etc/prometheus/secrets:ro" \
  prom/prometheus:v3.5.0 \
  check config /etc/prometheus/prometheus.yml
```

And:

```bash
docker run --rm \
  --entrypoint=/bin/promtool \
  -v "$PWD/prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro" \
  prom/prometheus:v3.5.0 \
  check rules /etc/prometheus/alerts.yml
```

You want:
```bash
SUCCESS: ... rule files found
```

### 7. Start Alertmanager
Then:
```bash
docker compose up -d alertmanager
```

Check:
```bash
docker compose ps | grep alertmanager
```

You should see:
```bash
monitoring-alertmanager-1   ...   Up (healthy)
```

Then:
```bash
docker compose up -d prometheus
```

And check the logs:
```bash
docker compose logs --tail=50 alertmanager
docker compose logs --tail=50 prometheus
```

### 8. Verify the pipeline
Open: `Prometheus → Status → Rules`, should see the `infrastructure` rule group.

Then: `Prometheus → Alerts` and will see alerts such as `TargetDown`, `HostHighCPU`, etc.


The important architecture is now:
```text
                    ┌───────────────┐
                    │   Exporters   │
                    │ node / PVE /  │
                    │ NUT / cAdvisor│
                    └───────┬───────┘
                            │
                            ▼
                    ┌───────────────┐
                    │   Prometheus  │
                    │               │
                    │ scrape metrics│
                    │ evaluate rules│
                    └───────┬───────┘
                            │
                     firing alerts
                            │
                            ▼
                    ┌───────────────┐
                    │  Alertmanager │
                    │               │
                    │ group/silence │
                    │ route/notify  │
                    └───────┬───────┘
                            │
                            ▼
                     Email / Telegram
                       / Discord / ...
```

## UPS Alerts
**I would stop before configuring the notification channel.** First let's get the Alertmanager pipeline working and verify your actual NUT metric names. Once that's confirmed, we can build the notification routing around `critical` vs `warning` alerts rather than having everything notify you equally.

```bash
dockeradmin@docker-host:/opt/docker/compose/monitoring$ docker run --rm \
  --network monitoring \
  busybox \
  wget -qO- 'http://nut-exporter:9995/metrics?target=192.168.1.200:3493'

# # TYPE nut_exporter_info info
# # UNIT nut_exporter_info
# # HELP nut_exporter_info Metadata about the exporter.
# nut_exporter_info{version="1.2.1"} 1
# # TYPE nut_server_info info
# # UNIT nut_server_info
# # HELP nut_server_info Metadata about the NUT server.
# nut_server_info{version="2.8.1"} 1
# # TYPE nut_ups_info info
# # UNIT nut_ups_info
# # HELP nut_ups_info Metadata about the UPS.
# nut_ups_info{ups="ups",description="Master Power 650VA",device_type="ups",manufacturer="          ",model="                    ",battery_type="PbAC",driver="usbhid-ups",driver_version="2.8.1",driver_version_internal="0.52",driver_version_data="MGE HID 1.46",usb_vendor_id="0463",usb_product_id="0001",ups_firmware="          ",type="ups",nut_version="2.8.1"} 1
# # TYPE nut_info info
# # UNIT nut_info
# # HELP nut_info Metadata about the NUT server. (Deprecated, use nut_server_info instead.)
# nut_info{version="2.8.1"} 1
# # TYPE nut_ups_status stateset
# # UNIT nut_ups_status
# # HELP nut_ups_status UPS status. Check for a specific status with the "status" label. ("ups.status")
# nut_ups_status{ups="ups",status="OL"} 1
# nut_ups_status{ups="ups",status="OB"} 0
# nut_ups_status{ups="ups",status="LB"} 0
# nut_ups_status{ups="ups",status="CHRG"} 0
# nut_ups_status{ups="ups",status="RB"} 0
# nut_ups_status{ups="ups",status="FSD"} 0
# nut_ups_status{ups="ups",status="BYPASS"} 0
# nut_ups_status{ups="ups",status="SD"} 0
# nut_ups_status{ups="ups",status="CP"} 0
# nut_ups_status{ups="ups",status="BOOST"} 0
# nut_ups_status{ups="ups",status="OFF"} 0
# # TYPE nut_load gauge
# # UNIT nut_load
# # HELP nut_load Load. (0-1) ("ups.load")
# nut_load{ups="ups"} 0.12000000000000000
# # TYPE nut_battery_charge gauge
# # UNIT nut_battery_charge
# # HELP nut_battery_charge Battery level. (0-1) ("battery.charge")
# nut_battery_charge{ups="ups"} 1.00000000000000000
# # TYPE nut_battery_charge_low gauge
# # UNIT nut_battery_charge_low
# # HELP nut_battery_charge_low Battery level threshold for low state. (0-1) ("battery.charge.low")
# nut_battery_charge_low{ups="ups"} 0.10000000000000001
# # TYPE nut_battery_runtime_seconds gauge
# # UNIT nut_battery_runtime_seconds seconds
# # HELP nut_battery_runtime_seconds Battery runtime. ("battery.runtime")
# nut_battery_runtime_seconds{ups="ups"} 7200
# # TYPE nut_input_voltage_volts gauge
# # UNIT nut_input_voltage_volts volts
# # HELP nut_input_voltage_volts Input voltage. ("input.voltage")
# nut_input_voltage_volts{ups="ups"} 237.00000000000000000
# # TYPE nut_input_frequency_hertz gauge
# # UNIT nut_input_frequency_hertz hertz
# # HELP nut_input_frequency_hertz Input frequency. ("input.frequency")
# nut_input_frequency_hertz{ups="ups"} 50.10000000000000142
# # TYPE nut_output_voltage_volts gauge
# # UNIT nut_output_voltage_volts volts
# # HELP nut_output_voltage_volts Output voltage. ("output.voltage")
# nut_output_voltage_volts{ups="ups"} 237.09999999999999432
# # TYPE nut_status gauge
# # UNIT nut_status
# # HELP nut_status UPS status. Unknown (0), on line (1, "OL"), on battery (2, "OB"), or low battery (3, "LB"). (Deprecated, use nut_ups_status instead.) ("ups.status")
# nut_status{ups="ups"} 1
# # TYPE nut_input_volts gauge
# # UNIT nut_input_volts volts
# # HELP nut_input_volts Input voltage. (Deprecated, use nut_input_voltage_volts instead.) ("input.voltage")
# nut_input_volts{ups="ups"} 237.00000000000000000
# # TYPE nut_output_volts gauge
# # UNIT nut_output_volts volts
# # HELP nut_output_volts Output voltage. (Deprecated, use nut_output_voltage_volts instead.) ("output.voltage")
# nut_output_volts{ups="ups"} 237.09999999999999432
# # EOF
```

| Metric                        |     Value | Meaning         |
| ----------------------------- | --------: | --------------- |
| `nut_ups_status{status="OL"}` |       `1` | Online          |
| `nut_ups_status{status="OB"}` |       `0` | Not on battery  |
| `nut_ups_status{status="LB"}` |       `0` | Battery not low |
| `nut_battery_charge`          |     `1.0` | 100%            |
| `nut_battery_runtime_seconds` |    `7200` | ~2 hours        |
| `nut_load`                    |    `0.12` | 12%             |
| `nut_input_voltage_volts`     |   `237 V` | Input           |
| `nut_output_voltage_volts`    | `237.1 V` | Output          |
| `nut_input_frequency_hertz`   | `50.1 Hz` | Input frequency |

Then validate with:
```bash
dockeradmin@docker-host:/opt/docker/compose/monitoring$ docker run --rm \
  --entrypoint=/bin/promtool \
  -v "$PWD/prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro" \
  prom/prometheus:v3.5.0 \
  check rules /etc/prometheus/alerts.yml
# Checking /etc/prometheus/alerts.yml
#   SUCCESS: 13 rules found
```

## Test with a temporary alert
Add this temporarily to `prometheus/alerts.yml`:
```yaml
  - alert: AlertmanagerTest
    expr: vector(1)
    for: 30s
    labels:
      severity: warning
    annotations:
      summary: "Alertmanager integration test"
      description: "Testing Prometheus to Alertmanager alert delivery."
```

Validate:
```bash
docker run --rm \
  --entrypoint=/bin/promtool \
  -v "$PWD/prometheus/alerts.yml:/etc/prometheus/alerts.yml:ro" \
  prom/prometheus:v3.5.0 \
  check rules /etc/prometheus/alerts.yml
```

Then reload Prometheus:
```bash
curl -X POST http://localhost:9090/-/reload
```

Wait ~30–60 seconds and check:
```bash
curl -s http://localhost:9090/api/v1/alerts \
  | jq '.data.alerts[] | select(.labels.alertname=="AlertmanagerTest")'
```

It should show: `state: "firing"`. Then open Alertmanager internally from the Docker network:
```bash
docker run --rm \
  --network monitoring \
  curlimages/curl:latest \
  http://alertmanager:9093/api/v2/alerts
```

If everything is correct, you'll see `AlertmanagerTest` there. Once we've confirmed that, **remove the test alert** and reload Prometheus again. Then we'll have proven: **Prometheus → Alertmanager works**, and we can move on to the interesting part: deciding how you want notifications delivered and routing `critical` vs `warning` alerts.

## Confituring Notification Routing
**Won't configure the external notification receiver yet**.

The good news is that Alertmanager itself does **not need to be exposed externally**. We can keep it entirely inside your Docker monitoring network and let only its outbound connections reach the Internet.

```text
                    LAN
                     │
        ┌────────────┴────────────┐
        │                         │
   Docker Host                Raspberry Pi
        │                    Firewall / VPN
        │                         │
   monitoring                  Gateway
   network                        │
        │                         │
   ┌────┴─────┐                   │
   │          │                   │
Prometheus  Alertmanager ─────────┘
                  │
                  │ outbound HTTPS
                  ▼
             Notification
              provider
```

### For now, I'd stop at Alertmanager
We can safely configure and test: `Prometheus -> Alertmanager` without allowing Alertmanager to communicate externally.

### Then secure the outbound path later
Once configured the RaspberryPi as the network/security layer, I'd separate the concerns:

**Docker monitoring network**
- Prometheus → exporters
- Prometheus → Alertmanager
- Grafana → Prometheus/Loki
- Alertmanager → Internet notification API

**Network security**
- Firewall rules
- Egress filtering
- VPN
- Reverse proxy where appropriate
- DNS filtering through AdGuard
- Possibly dedicated VLAN for IoT/homelab services

For Alertmanager specifically, the important thing is **egress**, not inbound exposure.

You can eventually make the firewall policy something like:

```text
Alertmanager
    │
    ├── DNS → allowed DNS server
    │
    └── HTTPS/443 → notification provider
```
and deny everything else.

