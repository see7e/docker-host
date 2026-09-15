# Jellyfin
At `/opt/docker/compose/media/compose.yml`
```yml
services:
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped

    ports:
      - "8096:8096"

    volumes:
      - /opt/docker/data/jellyfin/config:/config
      - /opt/docker/data/jellyfin/cache:/cache

      - /mnt/omv/shared/media/movies:/media/movies:ro
      - /mnt/omv/shared/media/shows:/media/shows:ro
      - /mnt/omv/shared/media/music:/media/music:ro
      - /mnt/omv/shared/media/photos:/media/photos:ro
      - /mnt/omv/shared/media/books:/media/books:ro

    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8096/health"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
```

```bash
mkdir -p /opt/docker/data/jellyfin/config
mkdir -p /opt/docker/data/jellyfin/cache
```

Validate:
```bash
docker compose config
```

If that is clean:
```bash
docker compose up -d
```

Then:
```bash
docker ps --filter name=jellyfin
```

and:
```bash
docker logs jellyfin --tail 50
```

### One thing we're intentionally *not* doing yet
- memory limits
- GPU/transcoding configuration
- reverse proxy
- external access
- special networking
- Bookshelf
- libraries

We'll get Jellyfin running first, access the web UI on:

```text
http://192.168.1.108:8096
```

and then go through the initial wizard. After that we'll install **Bookshelf** and configure the five libraries properly.

The read-only NFS mounts are a good security choice here: **Jellyfin can consume your media, but it cannot modify/delete the underlying media through those mounts.**
