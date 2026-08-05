# Considerations

## Why not a dedicated PostgreSQL database?
When Grafana uses SQLite (the default), it stores its database inside its data directory:

```text
/mnt/omv/.infra/docker/grafana/data/
├── grafana.db
├── plugins/
├── png/
├── sessions/
└── ...
```

The file: `grafana.db` **is the database**. It contains:
- Users
- Password hashes
- Dashboards
- Folders
- Teams
- Datasources
- Alert rules
- Preferences
- Annotations
- API keys

Everything that would otherwise be stored in PostgreSQL.

## Why does Grafana default to SQLite?
Because Grafana is designed to run well as a standalone application.

Unless needed:
- High Availability (multiple Grafana instances)
- Thousands of dashboards/users
- Enterprise clustering

SQLite is the officially supported default.

In fact, if you install Grafana directly on Ubuntu (without Docker), it uses SQLite by default.

While SQLite (recommended for your homelab) pros:
- One less container
- Lower RAM usage
- Simpler backups
- Easier upgrades
- Less maintenance

While PostgreSQL pros:
- Better for HA
- Better for very large deployments

Cons:
- Another container
- Another volume
- Another backup
- Another upgrade cycle
- Another service that can fail
