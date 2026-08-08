# Loki for centralized logs
At this point the monitoring stack is following a very solid architecture.
```
                    +----------------+
                    |    Grafana     |
                    +-------+--------+
                            |
            +---------------+------------------+
            |                                  |
    +-------v--------+                 +-------v------+
    |  Prometheus    |                 |     Alloy    |
    +-------+--------+                 +-------+------+
            |                                  |
            |                                  |
    +-------+--------+                 +-------v------+
    | Node Exporter  |                 |     Loki     |
    | cAdvisor       |                 +-------+------+
    | Exporters...   |                         |
    +-------+--------+                 +-------v------+
                                       |    Grafana   |
                                       +-------v------+
```

> [!note]
> Some informations were sourced from the [Grafana Quick Start](https://grafana.com/docs/loki/latest/get-started/quick-start/quick-start/).

Prometheus handles **metrics** while Loki handles **logs**. Grafana queries both independently, allowing you to jump from a CPU spike directly into the relevant container logs.

## Add Loki
Create the directory structure.
```bash
cd /opt/docker/compose/monitoring

mkdir -p loki
```

The tree will become:
```
monitoring/
├── compose.yml
├── grafana/
├── prometheus/
├── loki/
```

## Loki configuration
The current configuration was adapted from:
> ```bash
> wget https://raw.githubusercontent.com/grafana/loki/main/examples/getting-started/loki-config.yaml -O loki-config.yaml
> ```

```yml
auth_enabled: false

server:
  http_listen_address: 0.0.0.0
  http_listen_port: 3100

common:
  path_prefix: /loki
  replication_factor: 1
  ring:
    kvstore:
      store: inmemory

schema_config:
  configs:
    - from: "2024-01-01"
      store: tsdb
      object_store: filesystem
      schema: v13
      index:
        prefix: index_
        period: 24h

storage_config:
  filesystem:
    directory: /loki/chunks
  tsdb_shipper:
    active_index_directory: /loki/index
    cache_location: /loki/index_cache

ingester:
  wal:
    dir: /loki/wal

limits_config:
  retention_period: 30d

compactor:
  working_directory: /loki/compactor
  retention_enabled: true
  delete_request_store: filesystem

ruler:
  storage:
    type: local
    local:
      directory: /loki/rules
  rule_path: /loki/rules-temp

analytics:
  reporting_enabled: false
```

## Create storage directory
Since the runtime data is being stored under `/opt/docker/data`, keep Loki there too.
```bash
mkdir -p /opt/docker/data/loki
```

Permissions:
```bash
sudo chown -R 10001:10001 /opt/docker/data/loki
# drwxrwsr-x 2 10001       10001       4096 Aug  6 18:18 loki
```

## Add Loki service
Add to your compose:
> updated from:
> ```bash
> wget https://raw.githubusercontent.com/grafana/loki/main/examples/getting-started/docker-compose.yaml -O docker-compose.yaml
> ```
> The template focus on horizontally scalable production clusters, not for a single Docker host. And more important: as the communication hapens via internal Docker (`monitoring`) network, we dont have the need for:
> - `ports`
> - `read`
> - `write`
> - `backend`
> - `gateway`
> - `minio`

```yaml
  loki:
    image: grafana/loki:3.7.6
    restart: unless-stopped

    command:
      - "-config.file=/etc/loki/config.yml"

    volumes:
      - /opt/docker/data/loki:/loki
      - ./loki/config.yml:/etc/loki/config.yml:ro

    healthcheck:
      test: ["CMD", "/usr/bin/loki", "-health"]
      start_period: 30s
      interval: 30s
      timeout: 10s
      retries: 5

    logging:
      driver: local
      options:
        max-size: "10m"
        max-file: "5"

    networks:
      - monitoring
```

> [!note]
> Also added a condition for Grafana wait for Loki to be ready.

## Add Grafana provisioning for Loki
Grafana already provisions Prometheus. Add another datasource under: `grafana/provisioning/datasources/`, Example:
```yml
apiVersion: 1

datasources:
  - name: Loki
    uid: loki
    type: loki
    access: proxy
    url: http://loki:3100
    isDefault: false
```
No manual configuration in the UI.

---
# Alloy
The configuration will be used without updates:
```bash
wget https://raw.githubusercontent.com/grafana/loki/main/examples/getting-started/alloy-local-config.yaml -O alloy-local-config.yaml
```

> [!warning]
> Loki is sitting on `http_listen_address: 0.0.0.0` so is important to change the default `gateway` to the correct IP.

There's no data directory for Alloy because it's essentially stateless for your use case; Loki is where the persistent log storage lives.

And update `compose.yml` with Alloy service:
```yml
  alloy:
    image: grafana/alloy:v1.11.4
    restart: unless-stopped

    command:
      - run
      - --server.http.listen-addr=0.0.0.0:12345
      - --storage.path=/var/lib/alloy
      - /etc/alloy/config.alloy

    volumes:
      - ./alloy/config.alloy:/etc/alloy/config.alloy:ro

      # Persistent Alloy state (positions, WAL, etc.)
      - /opt/docker/data/alloy:/var/lib/alloy

      # Docker discovery
      - /var/run/docker.sock:/var/run/docker.sock:ro

      # Host logs
      - /var/log:/var/log:ro

    depends_on:
      loki:
        condition: service_healthy

    healthcheck:
      test: ["CMD", "wget", "--spider", "-q", "http://localhost:12345/-/ready"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 30s

    logging:
      driver: local
      options:
        max-size: "10m"
        max-file: "5"

    networks:
      - monitoring
```

---

# Start everything
```bash
docker compose pull
docker compose up -d
```

Verify:
```bash
docker compose ps
```

You should see all containers healthy.

> [!warning]
> Prometheus does **not** scrape Loki. Metrics and logs remain separate.

Now go to Explore and run:
- `{job="docker"}`
- `{job="syslog"}`

> The dasboard will be created later.


> [!error] (unhealthy) monitoring-alloy-1
> ```bash
> dockeradmin@docker-host:/opt/docker/compose/monitoring$ docker inspect monitoring-alloy-1 \
>   --format '{{json .State.Health}}' | jq
> {
>   "Status": "unhealthy",
>   "FailingStreak": 88,
>   "Log": [
>     {
>       "Start": "2026-08-07T23:56:37.256192723Z",
>       "End": "2026-08-07T23:56:37.295271668Z",
>       "ExitCode": -1,
>       "Output": "OCI runtime exec failed: exec failed: unable to start container process: exec: \"wget\": executable file not found in $PATH"
>     },
>     {
>       "Start": "2026-08-07T23:57:07.295992667Z",
>       "End": "2026-08-07T23:57:07.336796654Z",
>       "ExitCode": -1,
>       "Output": "OCI runtime exec failed: exec failed: unable to start container process: exec: \"wget\": executable file not found in $PATH"
>     },
>     {
>       "Start": "2026-08-07T23:57:37.337629168Z",
>       "End": "2026-08-07T23:57:37.374041985Z",
>       "ExitCode": -1,
>       "Output": "OCI runtime exec failed: exec failed: unable to start container process: exec: \"wget\": executable file not found in $PATH"
>     },
>     {
>       "Start": "2026-08-07T23:58:07.374505135Z",
>       "End": "2026-08-07T23:58:07.417286929Z",
>       "ExitCode": -1,
>       "Output": "OCI runtime exec failed: exec failed: unable to start container process: exec: \"wget\": executable file not found in $PATH"
>     },
>     {
>       "Start": "2026-08-07T23:58:37.418138929Z",
>       "End": "2026-08-07T23:58:37.458637794Z",
>       "ExitCode": -1,
>       "Output": "OCI runtime exec failed: exec failed: unable to start container process: exec: \"wget\": executable file not found in $PATH"
>     }
>   ]
> }
> ```
> 