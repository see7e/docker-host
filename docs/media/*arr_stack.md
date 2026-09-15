# *arr Stack — Current Setup & Security Notes
## Goal
The objective is to build a private, Docker-based media management stack focused initially on:
- Jellyfin for media playback.
- Bazarr for subtitle management.
- Existing movies and TV shows.
- No torrent/download client for now.
- No applications exposed directly to the internet.
- Docker networking for container-to-container communication.
- Loki/Grafana monitoring where possible.

The eventual *arr stack can include Sonarr and Radarr, but they do not need a torrent client. Sonarr/Radarr can be used to manage/index an existing library without downloading anything.

## Current Architecture
Recommended architecture:
```
                         LAN
                          │
                 ┌────────▼────────┐
                 │     Jellyfin    │
                 │      :8096      │
                 └────────┬────────┘
                          │
                   Docker media network
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
   ┌────▼────┐       ┌────▼────┐      ┌────▼────┐
   │  Sonarr │       │  Radarr │      │  Bazarr │
   │  :8989  │       │  :7878  │      │  :6767  │
   └─────────┘       └─────────┘      └────┬────┘
                                           │
                                    Subtitle providers
                                           │
                                       Internet
```

Initially: Jellyfin + Bazarr
Later: Jellyfin + Sonarr + Radarr + Bazarr

A torrent/download client is not required unless downloads are added later.

## Docker Networking
Use a user-defined Docker bridge network:
```yml
networks:
  media:
    driver: bridge
```

Attach the relevant containers:
```yml
services:

  jellyfin:
    networks:
      - media

  sonarr:
    networks:
      - media

  radarr:
    networks:
      - media

  bazarr:
    networks:
      - media
```

bridge does not mean internet exposure. It creates a Docker network that allows containers on that network to communicate.

Containers can communicate using their Compose service names:
```bash
http://jellyfin:8096
http://sonarr:8989
http://radarr:7878
http://bazarr:6767
```

No host port mapping is required for container-to-container communication.

## Port Exposure
A `ports`: mapping publishes a container port on the Docker host. For example:
```yml
ports:
  - "8096:8096"
```

allows access to Jellyfin through the host.

For Bazarr, the port was temporarily exposed for initial configuration:
```yml
ports:
  - "6767:6767"
```

After configuration, remove it.

Bazarr will still listen on port 6767 internally and remain accessible to other containers on the Docker network.

If temporary LAN access is required, a safer alternative is:
```yml
ports:
  - "127.0.0.1:6767:6767"
```

which restricts access to the Docker host itself.


> [!note] Jellyfin
> - Current Jellyfin container: `jellyfin/jellyfin:latest`
> - Current host mapping: `0.0.0.0:8096 -> 8096/tcp`
>
> Jellyfin can remain published on 8096 if LAN access is required. For container-to-container communication, Bazarr should use: `http://jellyfin:8096` rather than the host's IP address.
> ### Recreating Jellyfin
> Adding a Docker network may require recreating the container.
> This is normally safe provided Jellyfin's configuration and media are stored in volumes/bind mounts.
> The container itself is disposable; the persistent data should survive recreation.
> ```bash
> # To force recreation:
> docker compose up -d --force-recreate jellyfin
> # Verify network membership with:
> docker network inspect media_media
> ```
> Both Jellyfin and Bazarr should appear under Containers.

## Bazarr
Bazarr is intended to automatically find and download subtitles.

It is generally safe when kept updated and properly isolated, but it has had security vulnerabilities in older versions.

Important security practices:
- Keep Bazarr updated.
- Don't expose Bazarr directly to the internet.
- Use authentication.
- Give Bazarr only the filesystem access it needs.
- Don't run it as root unnecessarily.
- Use only subtitle providers you trust.

The LinuxServer image being used is:
```bash
lscr.io/linuxserver/bazarr:latest
```

### Bazarr Authentication
There are two different types of credentials:

### Bazarr UI authentication
This protects the Bazarr web interface.

Enable Bazarr's authentication/security settings and configure a strong username/password.

### API keys
An API key configured for Jellyfin allows Bazarr to authenticate to Jellyfin. It is not the same as Bazarr's own login protection.

## Bazarr Filesystem Permissions
Movies and shows should be mounted separately:
```yml
volumes:
  - /path/to/bazarr:/config
  - /path/to/movies:/movies
  - /path/to/shows:/shows
```

This is preferable to giving Bazarr broad access such as: `/media:/media` if `/media` contains unrelated data.

### Read/write requirements
Bazarr needs to write subtitle files, so:
```yml
- /path/to/movies:/movies
- /path/to/shows:/shows
```

should normally be read/write.

Jellyfin, by comparison, can use read-only mounts:
```yml
- /path/to/movies:/movies:ro
- /path/to/shows:/shows:ro
```

This prevents Jellyfin from modifying the media. The resulting permission model is:
```
                 Movies       Shows
Jellyfin           RO           RO
Bazarr             RW           RW
```

Bazarr should not receive access to:
- `downloads/`
- `documents/`
- `backups/`
- `secrets/`
- other unrelated host directories

unless genuinely required.

## Bazarr User/Group
Avoid running Bazarr as root unless necessary. With the LinuxServer image, configure the appropriate PUID and PGID, for example:
```yml
environment:
  - PUID=1000
  - PGID=1000
  - TZ=${TZ}
```

Do not blindly assume 1000 is correct. Check the user that owns the media and inspect permissions:
```bash
id yourusername
ls -ln /path/to/movies
ls -ln /path/to/shows
```

Bazarr needs permission to:
- Read the video files.
- Write subtitle files.
- Read/write its /config directory.
- Bazarr and Jellyfin

The Jellyfin API key was added to Bazarr. However, the important distinction is: *Bazarr does not use Jellyfin as its normal primary media-library source.* The current Bazarr workflow expects Sonarr and Radarr for its normal automated media inventory.

Jellyfin integration is useful for things such as refreshing Jellyfin libraries/items after subtitle changes, but it does not replace Sonarr/Radarr for Bazarr's normal library-management workflow.

Therefore, trying to make Bazarr independently scan the Jellyfin library is not the recommended architecture.

## Sonarr and Radarr
Sonarr and Radarr can be added without adding a torrent/download client.  They can be used to manage/index existing media.  The intended architecture can therefore be:
```
Existing Movies ──► Radarr ──┐
                             │
                             ├──► Bazarr ──► Subtitles
                             │
Existing Shows ───► Sonarr ──┘
```

Jellyfin continues to provide playback.

### No torrent client is required
A torrent/download client is only needed if downloads are eventually automated.

For the current objective:
- Sonarr      ✓
- Radarr      ✓
- Bazarr      ✓
- Jellyfin    ✓
- Torrent     ✗

This allows the *arr stack to be introduced without immediately creating a download pipeline.

### Sonarr/Radarr Network Access
If all services are in the same Compose project:
```yml
services:
  jellyfin:
    networks:
      - media

  sonarr:
    networks:
      - media

  radarr:
    networks:
      - media

  bazarr:
    networks:
      - media

networks:
  media:
    driver: bridge
```

Bazarr can then use:
- http://sonarr:8989
- http://radarr:7878


No host port mapping is required for these connections.

If Sonarr/Radarr are managed by separate Compose projects, use a shared external Docker network rather than moving everything into one Compose file.

### Internet Exposure
The goal is to avoid exposing any media-management application directly to the internet.  Recommended:
```
Internet
   │
   ✕
   │
Docker host
   │
   └── private Docker network
         ├── Jellyfin
         ├── Sonarr
         ├── Radarr
         └── Bazarr
```

Possible LAN-only access:
```
LAN
 │
 ├── Jellyfin :8096
 ├── Sonarr   :8989
 ├── Radarr   :7878
 └── Bazarr   :6767
```

But ideally Bazarr/Sonarr/Radarr do not need published ports if their interfaces are only accessed through an appropriate local management method.

If remote access is eventually required, use a VPN or properly authenticated reverse proxy rather than directly forwarding the application ports.

### Subtitle Providers
Start with only providers you actually trust and need. OpenSubtitles has been configured.

In Bazarr: Settings → Providers. Enable only the providers you intend to use.

Subtitle files are external content downloaded from third parties, so restricting Bazarr's filesystem access is particularly important.


## Loki/Grafana Monitoring
cAdvisor and Loki serve different purposes.

### cAdvisor
Provides container metrics:
- CPU
- Memory
- Network
- Filesystem
- Container status

### Loki
Provides logs. A suitable architecture is:
```
Docker containers
       │
       ▼
Grafana Alloy
       │
       ▼
     Loki
       │
       ▼
    Grafana
```

Alloy can collect Docker container logs without modifying Bazarr.

The current Alloy configuration uses:
```ini
discovery.docker "flog_scrape" {
    host             = "unix:///var/run/docker.sock"
    refresh_interval = "5s"
}

discovery.relabel "flog_scrape" {
    targets = []

    rule {
        source_labels = ["__meta_docker_container_name"]
        regex         = "/(.*)"
        target_label  = "container"
    }
}

loki.source.docker "flog_scrape" {
    host             = "unix:///var/run/docker.sock"
    targets          = discovery.docker.flog_scrape.targets
    forward_to       = [loki.write.default.receiver]
    relabel_rules    = discovery.relabel.flog_scrape.rules
    refresh_interval = "5s"
}

loki.write "default" {
    endpoint {
        url       = "http://loki:3100/loki/api/v1/push"
        tenant_id = "tenant1"
    }

    external_labels = {}
}
```

This configuration does not explicitly filter out Bazarr.

Docker's logging driver for both Jellyfin and Bazarr is: `local`. Bazarr is producing stdout logs successfully, for example:
```log
Bazarr starting child process
Scheduler will use this timezone
BAZARR is started and waiting for requests
```

Therefore, if Bazarr does not appear in Loki, the remaining troubleshooting path is Docker → Alloy → Loki rather than Bazarr's own logging.

Useful Loki query based on the configured container label:
```bash
{container="media-bazarr-1"}
# or
{container=~".*bazarr.*"}
```

## Security Model
The desired security posture is:
- Jellyfin
    - LAN-accessible if required.
    - Media mounts preferably read-only.
    - Docker network enabled.
- Bazarr
    - Private Docker network.
    - /movies read/write.
    - /shows read/write.
    - /config read/write.
    - Non-root user.
    - Authentication enabled.
    - Trusted subtitle providers only.
    - No internet-facing port after initial configuration.
- Sonarr/Radarr
    - Private Docker network.
    - No torrent/download client initially.
    - No direct internet exposure.
    - Used primarily to manage/index existing media.
- Loki
    - Internal Docker network.
    - Do not expose directly to the internet.
- Grafana
    - LAN/private access or protected through an appropriate authentication layer.
    - Do not expose unnecessarily.

## Recommended End State
For the current phase:
```
                 ┌───────────────┐
                 │    Jellyfin   │
                 │     :8096     │
                 └───────┬───────┘
                         │
                 Docker media network
                         │
             ┌───────────┼───────────┐
             │           │           │
        ┌────▼────┐ ┌────▼────┐ ┌────▼────┐
        │ Sonarr  │ │ Radarr  │ │ Bazarr  │
        │  :8989  │ │  :7878  │ │  :6767  │
        └─────────┘ └─────────┘ └────┬────┘
                                     │
                              Subtitle providers
```

No torrent client is needed.

Monitoring:
```
Jellyfin ─┐
Sonarr ───┤
Radarr ───┼──► Alloy ──► Loki ──► Grafana
Bazarr ───┘
```
All containers ──► cAdvisor ──► Prometheus ──► Grafana


The overall principle is least privilege + private networking: containers communicate internally by Docker DNS, only genuinely necessary services publish host ports, media directories are mounted only where needed, and download infrastructure is postponed until there is a deliberate need for it.