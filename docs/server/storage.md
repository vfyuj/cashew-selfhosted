# File storage: the three namespaces

File: `server/lib/src/storage.dart` (`UserFileStore`), used by the sync, backup and attachment
routers. Replaces Google Drive's `appDataFolder`.

## Layout

Everything lives under `DATA_DIR` (`/data` in the image):

```
<DATA_DIR>/
  db.sqlite              the server's own database -- see database.md
  sync/<datasetId>/      device snapshots (Stage 1 transport, still the fallback)
  backup/<userId>/       manual and automatic backups
  attachments/<datasetId>/  receipt photos and picked files
```

`UserFileStore(dataDir, namespace, id)` is the only thing that builds a path. Callers pass a
namespace and an id and never a path, and `_safePath` rejects any filename that is not a bare
basename — separators, `.`, `..` — with `400`. A client-supplied name can therefore never escape its
own directory.

`deleteAll()` removes a whole namespace directory. It is used when an administrator deletes an
account: otherwise the files would linger, and a later account allocated the same numeric id would
inherit them.

## Why the third namespace exists

Attachments could not share `sync/`. The snapshot transport lists every file in its namespace and
treats each as a peer device's database — a receipt photo dropped in there would be read as one.

## Per-user vs per-dataset — the split that looks like a bug

**Sync and attachments follow the dataset. Backups stay per-user.** This is deliberate, and there is
a test pinning it. Do not "fix" it for consistency.

*Attachments must be dataset-scoped*: the app bakes this server's attachment URL into the
transaction's note, and that note syncs. Scoped per user, a receipt added by one household member
would `404` for the other.

*Backups must not be*, for two reasons:

- **Filenames collide.** A backup is named `db-v<schema>-<deviceName>`, and the device name strips
  clientID's millisecond suffix down to the device model. Two same-model phones in one household
  would silently overwrite each other's backups. Sync snapshots keep the suffix, which is exactly why
  `sync/` can be shared safely.
- **Retention crosses over.** Pruning to `backupLimit` runs over the whole listing, so one member's
  automatic backup would evict another's.

Each member keeping their own history costs nothing — they are snapshots of the same shared database,
so either member's restores the household.

The same asymmetry drives account deletion (`DELETE /admin/users/<id>`): the user's `backup/` goes
unconditionally, while `sync/` and `attachments/` are deleted only once the removed account was the
dataset's last member.

## Backup targets

The own-server namespace above is the default. Nextcloud/WebDAV is the alternative, configured and
spoken **entirely client-side** — this server never proxies it and does not know it exists.

---

Why: `specs/03-stage-1-kill-google.md` (replacing Drive; the attachments namespace),
`specs/06-shared-household-data.md` (datasets, and why backups stayed per-user).
