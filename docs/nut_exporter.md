# NUT Exporter
> ```bash
> root@pve:~# upsc ups
> # Init SSL without certificate database
> # battery.charge: 100
> # battery.charge.low: 10
> # battery.runtime: 7200
> # battery.type: PbAC
> # device.mfr:           
> # device.model:                     
> # device.serial:                      
> # device.type: ups
> # driver.debug: 0
> # driver.flag.allow_killpower: 0
> # driver.name: usbhid-ups
> # driver.parameter.pollfreq: 30
> # driver.parameter.pollinterval: 5
> # driver.parameter.port: auto
> # driver.parameter.productid: 0001
> # driver.parameter.synchronous: auto
> # driver.parameter.vendorid: 0463
> # driver.state: quiet
> # driver.version: 2.8.1
> # driver.version.data: MGE HID 1.46
> # driver.version.internal: 0.52
> # driver.version.usb: libusb-1.0.28 (API: 0x100010a)
> # input.frequency: 50.0
> # input.voltage: 236.6
> # outlet.1.status: on
> # output.voltage: 236.2
> # ups.firmware:           
> # ups.load: 12
> # ups.mfr:           
> # ups.model:                     
> # ups.productid: 0001
> # ups.serial:                      
> # ups.status: OL
> # ups.vendorid: 0463
> # root@pve:~# hostname -I
> # 192.168.1.200
> ```
>
> ```bash
> dockeradmin@docker-host:/opt/docker/compose/monitoring$ nc -zv 192.168.1.200 3493
> # nc: connect to 192.168.1.200 port 3493 (tcp) failed: Connection refused
> ```
>
> ```bash
> root@pve:~# ss -lntp | grep 3493
> # LISTEN 0      16         127.0.0.1:3493      0.0.0.0:*    users:(("upsd",pid=1170,fd=5))                                                                                                                                                       >
> # LISTEN 0      16             [::1]:3493         [::]:*    users:(("upsd",pid=1170,fd=4))                                                                                                                                                       > 
> root@pve:~# systemctl status nut-server --no-pager
> # ● nut-server.service - Network UPS Tools - power devices information server
> #      Loaded: loaded (/usr/lib/systemd/system/nut-server.service; enabled; preset: enabled)
> #      Active: active (running) since Sun 2026-08-02 12:56:19 WEST; 5 days ago
> root@pve:~# systemctl status nut-driver@ups --no-pager
> # ● nut-driver@ups.service - Network UPS Tools - device driver for NUT device 'ups'
> #      Loaded: loaded (/usr/lib/systemd/system/nut-driver@.service; enabled; preset: enabled)
> #     Drop-In: /etc/systemd/system/nut-driver@ups.service.d
> #              └─nut-driver-enumerator-generated-checksum.conf, nut-driver-enumerator-generated.conf
> #      Active: active (running) since Sun 2026-08-02 12:56:16 WEST; 5 days ago
> root@pve:~# cat /etc/nut/upsd.users
> # [monuser]
> # upsmon primary
> root@pve:~# cat /etc/nut/nut.conf
> #MODE=standalone
> ```

## Now that the connection to PVE NUT was fixed.
The exporter will be the NUT client. Before installing it, we need to make sure the **`monuser` credentials actually work remotely**. The TCP test only proved that port 3493 is reachable.

On `docker-host`, let's first create the exporter configuration using your existing NUT account.

Your architecture is now:
```text
Proxmox
192.168.1.200
    │
    │ NUT :3493
    ▼
nut-exporter
    │
    ▼
Prometheus
    │
    ▼
Grafana
```

### Create a credentials file
On `docker-host`:
```bash
cd /opt/docker/compose/monitoring
mkdir -p nut-exporter
vim nut-exporter/config.yml
```

### Configuration
We'll configure it with [hon95/prometheus-nut-exporter](https://github.com/hon95/prometheus-nut-exporter). 

To `compose.yml`:
```yml
  nut-exporter:
    # Stable v1
    image: hon95/prometheus-nut-exporter:1
    environment:
      - TZ=Europe/Oslo
      - HTTP_PATH=/metrics
      # Defaults
      #- RUST_LOG=info
      #- HTTP_PORT=9995
      #- HTTP_PATH=/nut
      #- LOG_REQUESTS_CONSOLE=false
      #- PRINT_METRICS_AND_EXIT=false
    networks:
      - monitoring
```

and in `prometheus.yml`:
```yml
  - job_name: "nut"
    static_configs:
      - targets:
          - "192.168.1.200:3493"

    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target

      - source_labels: [__param_target]
        target_label: instance

      - target_label: __address__
        replacement: nut-exporter:9995
```
