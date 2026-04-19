# Utilities

| Script                                                     | Purpose                                                                                                                                              |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`backup-attachments.sh`](./backup-attachments.sh)         | Copy attachment blobs **from a running** Synkronus container to the host (current `/app/data/attachments` and legacy `/app/attachments` if present). |
| [`backup-db.sh`](./backup-db.sh)                           | **`pg_dump`** of the Postgres database from a **running** `db` / `postgres` container to a `.sql` file on the host.                                  |
| [`migrate-synkronus-data.sh`](./migrate-synkronus-data.sh) | Migrate **volume** layout on disk (`app-bundles/` → `app-bundle/active/`, etc.). Run with the **stack stopped**.                                     |

See **[upgrade-path.md](../upgrade-path.md)** for migration context and when to use each.
