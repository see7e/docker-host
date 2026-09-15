# HAOS Exporter
Perfect. Since we're deliberately keeping HA configuration minimal, **metrics can be one of the first things we configure**.

Home Assistant has a built-in Prometheus integration. It exposes HA entities through `/api/prometheus`, which our existing Prometheus server can scrape. ([Home Assistant][1])

The architecture will be:

```text
Home Assistant OS (VM 102)
        │
        │ /api/prometheus
        ▼
   Prometheus
        │
        ▼
     Grafana
```

## Step 1 — Enable Prometheus in HA

In Home Assistant, we need to add this to `configuration.yaml`:

```yaml
prometheus:
```

The official integration requires YAML configuration and a restart after changing the file. ([Home Assistant][1])

### Easiest way on HAOS
Since this is a fresh installation, install the **Studio Code Server** app from: **Settings → Apps → App store**. Then open it and edit:
```text
/config/configuration.yaml
```

Add:
```yaml
prometheus:
```

> If `configuration.yaml` already contains other configuration, **just add the `prometheus:` line** rather than replacing the file.

## Step 2 — Create Profile and a Long-Lived Access Token
We should use authentication rather than exposing the Prometheus endpoint anonymously.

In HA: **Profile → People -> Add person**:
| Setting           | Value        |
| ----------------- | ------------ |
| Username          | `prometheus` |
| **Allow login**   | **Yes**      |
| **Administrator** | **No**       |
| Local access only | **Yes**      |


In HA: **Profile → Long-Lived Access Tokens → Create Token**
Give it a name such as:
```text
prometheus
```

Copy the token somewhere safe.

**Don't paste the token here.**

The current Home Assistant documentation specifically supports using a Long-Lived Access Token with the Prometheus scrape configuration. ([Home Assistant][1])

---

## Step 3 — Restart Home Assistant

After saving `configuration.yaml`:

**Developer Tools → YAML → Check configuration**

If it passes:

**Settings → System → Restart Home Assistant**

---

## Step 4 — Test the endpoint

Once HA has restarted, from your **Docker host** run:

```bash
curl -I http://<HA_IP>:8123/api/prometheus
```

We expect an authentication response, probably:

```text
HTTP/1.1 401 Unauthorized
```

That's actually good at this stage — it means the endpoint exists but requires authentication.

Then test with your token:

```bash
curl \
  -H "Authorization: Bearer YOUR_TOKEN" \
  http://<HA_IP>:8123/api/prometheus | head -30
```

You should see Prometheus-format output such as:

```text
# HELP ...
# TYPE ...
...
```

---

# Step 5 — Add HA to our existing Prometheus
This is where your existing monitoring configuration comes in. In your Prometheus configuration, we'll add:
```yaml
- job_name: "homeassistant"
  scrape_interval: 60s
  metrics_path: /api/prometheus
  authorization:
    credentials_file: /etc/prometheus/secrets/ha_token
  static_configs:
    - targets:
        - "192.168.1.111:80"
```

And create the secret file with the following permissions:
```bash
sudo chown 65534:65534 prometheus/secrets/ha_token
sudo chmod 400 prometheus/secrets/ha_token
```

## What we'll get
Once Prometheus is scraping HA, you'll have metrics for supported HA domains including:
- sensors
- binary sensors
- lights
- switches
- climate
- covers
- locks
- device trackers
- automations
- updates
- persons
- etc. ([Home Assistant][1])

It also exposes useful metadata such as:
```text
entity_info
area_info
floor_info
```

which will eventually let us build Grafana queries such as **temperature by room/area**, rather than just displaying raw entity IDs. ([Home Assistant][1])

---

### Let's do this incrementally

Don't touch Prometheus yet.

**First, enable:**

```yaml
prometheus:
```

in HA's `configuration.yaml`, restart HA, and tell me when that's done.

Then we'll test:

```text
Docker Host → HAOS → /api/prometheus
```

before modifying your working Prometheus configuration.

[1]: https://www.home-assistant.io/integrations/prometheus?utm_source=chatgpt.com "Prometheus - Home Assistant"
