# Calendar Database

PostgreSQL database backups for the calendar application. This repository stores versioned database dumps used for backup and restore of the calendar app's data.

## Backup File Format

Files follow the naming convention:

```
calendar_db-v<postgres_version>-<date>[-<sequence>].tar
```

Example: `calendar_db-v18.3-2026-04-06.tar`

## Restore

To restore a backup into a running PostgreSQL instance:

```bash
pg_restore -U <user> -d <database> calendar_db-v18.3-<date>.tar
```

## Related Projects

- [calendar-app](../calendar-app) — Frontend calendar application
- [raspi-finance-database](../raspi-finance-database) — Finance app database backups
