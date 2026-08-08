# Promtrail

> [!note]
> Alloy is Grafana's unified telemetry agent that can collect:
> - Logs (replacement for Promtail)
> - Metrics (replacement for Grafana Agent)
> - Traces (OpenTelemetry)
> - Profiles (Pyroscope)
> Eventually, one Alloy instance can replace multiple separate collectors.
>
> Given the roadmap (Docker host, Proxmox, OMV, Raspberry Pi, Home Assistant, UPS, and likely more services in the future), I would skip Promtail entirely and adopt Alloy now.
> Advantages:
> - One agent for logs, metrics, and traces.
> - This is the direction Grafana Labs is investing in.
> - Better long-term support and new features.
> - Easier to extend as the infrastructure grows.

So, based on this decision will add Alloy documentation into [Loki](./loki.md).
