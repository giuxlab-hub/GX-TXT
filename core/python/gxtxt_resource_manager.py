"""CORE framework resource accounting; never a scientific-data authority.

SPDX-License-Identifier: GPL-3.0-or-later
Only allocations created by this authority can be deleted. Observed legacy,
publication, document and renderer resources are inspection-only. A dead process
does not authorize deletion of another authority's recovery material.
"""
from __future__ import annotations

import argparse
import contextlib
import json
import os
from pathlib import Path
import sqlite3
import stat
import sys
import time
import uuid

STATES = {"active", "cache_reusable", "temporary", "retained_diagnostic",
          "protected_authoritative", "verified_orphan", "unknown_legacy"}
MAX_SCAN_ENTRIES = 100000


def process_identity(pid):
    """Linux PID reuse/reboot-safe lease; unknown backends stay protected.

    FUTURE WINDOWS PORTING REQUIREMENT: use the same LOCAL resource authority
    with native process creation identity. A missing /proc adapter must never
    classify live Windows resources as orphans. No remote supervisor is involved.
    """
    try:
        value = Path(f"/proc/{int(pid)}/stat").read_text()
        fields = value[value.rfind(")") + 2:].split()
        if fields[0] == "Z":
            return "dead"
        boot = Path("/proc/sys/kernel/random/boot_id").read_text().strip()
        return f"{boot}:{fields[19]}"
    except (FileNotFoundError, ProcessLookupError):
        return "dead" if sys.platform.startswith("linux") else "unknown"
    except (OSError, ValueError, IndexError):
        return "unknown"


def _safe_directory(path, create=False):
    """Open each component without following links; reject writable owner root."""
    path = Path(os.path.abspath(os.fspath(path)))
    fd = os.open("/", os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in path.parts[1:]:
            if create:
                try:
                    os.mkdir(part, 0o700, dir_fd=fd)
                except FileExistsError:
                    pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            os.close(fd)
            fd = child
        st = os.fstat(fd)
        if st.st_uid != os.getuid() or st.st_mode & 0o022:
            raise ValueError("Resource authority directory must be owned and not group/world writable")
        return fd
    except BaseException:
        os.close(fd)
        raise


def _identity(st):
    return [st.st_dev, st.st_ino]


def _scan_fd(fd, device, budget):
    size = count = 0
    for name in os.listdir(fd):
        budget[0] += 1
        if budget[0] > MAX_SCAN_ENTRIES:
            raise ValueError("Inventory limit reached; resource remains protected")
        st = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if st.st_dev != device or stat.S_ISLNK(st.st_mode):
            raise ValueError("Linked or cross-filesystem resource is protected")
        if stat.S_ISREG(st.st_mode):
            if st.st_nlink != 1:
                raise ValueError("Hard-linked resource is protected")
            size += st.st_size
            count += 1
        elif stat.S_ISDIR(st.st_mode):
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            try:
                if _identity(os.fstat(child)) != _identity(st):
                    raise ValueError("Resource changed during inspection")
                a, b = _scan_fd(child, device, budget)
                size += a
                count += b
            finally:
                os.close(child)
        else:
            raise ValueError("Special filesystem object is protected")
    return size, count


def _remove_contents(fd, device):
    # The owner has released its lease before this code runs. All paths remain
    # relative to open directory descriptors; replacement symlinks are refused.
    for name in os.listdir(fd):
        st = os.stat(name, dir_fd=fd, follow_symlinks=False)
        if st.st_dev != device or stat.S_ISLNK(st.st_mode):
            raise ValueError("Resource changed to a link or mount")
        if stat.S_ISDIR(st.st_mode):
            child = os.open(name, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=fd)
            try:
                if _identity(os.fstat(child)) != _identity(st):
                    raise ValueError("Resource directory identity changed")
                _remove_contents(child, device)
            finally:
                os.close(child)
            if _identity(os.stat(name, dir_fd=fd, follow_symlinks=False)) != _identity(st):
                raise ValueError("Resource changed before removal")
            os.rmdir(name, dir_fd=fd)
        elif stat.S_ISREG(st.st_mode) and st.st_nlink == 1:
            if _identity(os.stat(name, dir_fd=fd, follow_symlinks=False)) != _identity(st):
                raise ValueError("Resource changed before unlink")
            os.unlink(name, dir_fd=fd)
        else:
            raise ValueError("Special or shared resource is protected")


class ResourceManager:
    def __init__(self, root=None, storage_root=None, caller_pid=None):
        default = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "gxtxt_pipeline/resources"
        self.root = Path(os.path.abspath(root or os.environ.get("GXTXT_RESOURCE_ROOT", default)))
        self.caller_pid = int(caller_pid or os.getpid())
        self._lease_cache = None
        fd = _safe_directory(self.root, True)
        os.close(fd)
        db = self.root / "registry.sqlite3"
        if db.is_symlink():
            raise ValueError("Resource registry cannot be a symlink")
        self.db = sqlite3.connect(db, timeout=10, isolation_level=None)
        os.chmod(db, 0o600)
        self.db.execute("PRAGMA journal_mode=WAL")
        self.db.execute("PRAGMA synchronous=FULL")
        self.db.execute("CREATE TABLE IF NOT EXISTS resources (id TEXT PRIMARY KEY, record TEXT NOT NULL)")
        self.db.execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)")
        self.db.execute("CREATE TABLE IF NOT EXISTS audit (time REAL, resource_id TEXT, category TEXT, path TEXT, bytes INTEGER, result TEXT)")
        requested = storage_root or os.environ.get("GXTXT_RESOURCE_STORAGE")
        with self._transaction():
            saved = self.db.execute("SELECT value FROM settings WHERE key='storage_root'").fetchone()
            # Existing allocations retain the original root if preferences change.
            self.storage = Path(saved[0] if saved else os.path.abspath(requested or self.root / "objects"))
            fd = _safe_directory(self.storage, True)
            os.close(fd)
            self.db.execute("INSERT OR IGNORE INTO settings VALUES ('storage_root',?)", (str(self.storage),))
            self.db.execute("INSERT OR IGNORE INTO settings VALUES ('max_bytes','10737418240')")
            self.db.execute("INSERT OR IGNORE INTO settings VALUES ('retention_seconds','604800')")

    def close(self):
        self.db.close()

    @contextlib.contextmanager
    def _transaction(self):
        self.db.execute("BEGIN IMMEDIATE")
        try:
            yield
            self.db.execute("COMMIT")
        except BaseException:
            self.db.execute("ROLLBACK")
            raise

    def _put(self, record):
        self.db.execute("INSERT OR REPLACE INTO resources VALUES (?,?)", (record["id"], json.dumps(record, sort_keys=True)))

    def _get(self, resource_id):
        row = self.db.execute("SELECT record FROM resources WHERE id=?", (resource_id,)).fetchone()
        if row is None:
            raise ValueError("Unknown resource ID")
        return json.loads(row[0])

    def policy(self, **changes):
        with self._transaction():
            for key, value in changes.items():
                if key not in {"max_bytes", "retention_seconds"} or int(value) < 0:
                    raise ValueError("Invalid resource policy")
                self.db.execute("UPDATE settings SET value=? WHERE key=?", (str(int(value)), key))
            return {key: int(value) for key, value in self.db.execute("SELECT key,value FROM settings") if key != "storage_root"}

    def _base(self, subsystem, category, job_id, session, dataset_id, lifetime, retention_seconds, owner_pid):
        if not subsystem or category not in STATES:
            raise ValueError("Resource subsystem and valid category are required")
        pid = int(owner_pid or self.caller_pid)
        if pid < 1 or int(retention_seconds) < 0:
            raise ValueError("Invalid resource owner/retention")
        now = time.time()
        return dict(id="resource-" + uuid.uuid4().hex, subsystem=str(subsystem), category=category,
                    state=category, job_id=str(job_id), session=str(session), dataset_id=str(dataset_id),
                    lifetime=str(lifetime), retention_seconds=int(retention_seconds), producer=str(subsystem),
                    owner_pid=pid, owner_identity=process_identity(pid), created=now, last_access=now,
                    last_verified=now, released=False, recovery_required=False, bytes=0, count=0,
                    eligible=False, reason="Owner has not released the resource", removed=False)

    def allocate(self, subsystem, category="temporary", kind="directory", job_id="", session="",
                 dataset_id="", lifetime="job", retention_seconds=None, owner_pid=None, suffix="", expected_bytes=0,
                 descendant_lease=False):
        if kind not in {"directory", "file"} or any(c not in ".-_abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" for c in suffix):
            raise ValueError("Invalid allocation kind or suffix")
        if category in {"protected_authoritative", "unknown_legacy"}:
            raise ValueError("Authoritative/legacy resources must use observe")
        if retention_seconds is None:
            retention_seconds = self.policy()["retention_seconds"] if category == "retained_diagnostic" else 0
        record = self._base(subsystem, category, job_id, session, dataset_id, lifetime, retention_seconds, owner_pid)
        with self._transaction():
            limit = int(self.db.execute("SELECT value FROM settings WHERE key='max_bytes'").fetchone()[0])
            known = sum(max(r.get("bytes", 0), r.get("expected_bytes", 0)) for (raw,) in self.db.execute("SELECT record FROM resources") for r in [json.loads(raw)] if r["managed"] and not r.get("removed"))
            if expected_bytes < 0 or (limit and known + int(expected_bytes) > limit):
                raise ValueError("Temporary resource budget exhausted; release or inspect eligible resources")
            parent = _safe_directory(self.storage)
            try:
                os.mkdir(record["id"], 0o700, dir_fd=parent)
                st = os.stat(record["id"], dir_fd=parent, follow_symlinks=False)
            finally:
                os.close(parent)
            envelope = self.storage / record["id"]
            path = envelope if kind == "directory" else envelope / ("data" + suffix)
            if kind == "file":
                fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
                os.close(fd)
            record.update(path=str(path), envelope=str(envelope), identity=_identity(st), managed=True,
                          kind=kind, expected_bytes=int(expected_bytes), descendant_lease=bool(descendant_lease))
            self._put(record)
        return record

    def observe(self, path, subsystem, category="protected_authoritative", job_id="", session="",
                dataset_id="", owner_pid=None, recovery_required=True, lifetime="owner", retention_seconds=0):
        """Inventory an existing owner resource without acquiring deletion rights."""
        path = os.path.abspath(os.fspath(path))
        record = self._base(subsystem, category, job_id, session, dataset_id, lifetime, retention_seconds, owner_pid)
        record.update(path=path, envelope="", identity=[], managed=False, kind="external",
                      recovery_required=bool(recovery_required), reason="External owner must release/collect this resource")
        with self._transaction():
            for row in self.db.execute("SELECT record FROM resources"):
                old = json.loads(row[0])
                if not old["managed"] and old["path"] == path and old["subsystem"] == subsystem:
                    record["id"] = old["id"]
                    record["created"] = old["created"]
                    break
            self._refresh(record, True)
            self._put(record)
        return record

    def release(self, resource_id, state="verified_orphan", retention_seconds=None):
        if state not in {"verified_orphan", "cache_reusable", "retained_diagnostic"}:
            raise ValueError("Invalid released resource state")
        with self._transaction():
            record = self._get(resource_id)
            self._lease_cache = None
            if record.get("descendant_lease") and self._descendant_alive(record) is not False:
                raise ValueError("Live or unverifiable child still holds this resource lease")
            live = process_identity(record["owner_pid"])
            if record["owner_pid"] != self.caller_pid and (live == "unknown" or live == record["owner_identity"] and live != "dead"):
                raise ValueError("Only the live owning process can release a resource")
            if not record["managed"] or record["recovery_required"]:
                raise ValueError("External or recovery resources require their owning authority")
            record.update(released=True, state=state, last_access=time.time(), expected_bytes=0)
            if retention_seconds is not None:
                if int(retention_seconds) < 0:
                    raise ValueError("Retention cannot be negative")
                record["retention_seconds"] = int(retention_seconds)
            self._refresh(record, True)
            self._put(record)
        return record

    def _descendant_alive(self, record):
        """Check explicitly inherited job scratch leases only after owner loss.

        The guardian sets GXTXT_RESOURCE_LEASE before spawning its runtime. This
        is an ownership capability inside the protected local job context, not a
        process-name or age heuristic. A single inventory shares one /proc scan.
        Permission uncertainty protects resources rather than declaring orphans.
        """
        if not record.get("descendant_lease"):
            return False
        try:
            boot, started = record["owner_identity"].rsplit(":", 1)
            started = int(started)
            if Path("/proc/sys/kernel/random/boot_id").read_text().strip() != boot:
                return False
        except (OSError, ValueError):
            return None
        if self._lease_cache is None:
            entries = []
            try:
                paths = list(Path("/proc").iterdir())
            except OSError:
                return None
            for path in paths:
                if not path.name.isdigit():
                    continue
                try:
                    if path.stat().st_uid != os.getuid():
                        continue
                    fields = (path / "stat").read_text().rsplit(")", 1)[1].split()
                    if fields[0] == "Z":
                        continue
                    child_start = int(fields[19])
                    try:
                        env = (path / "environ").read_bytes().split(b"\0")
                        entries.append((child_start, env, False))
                    except PermissionError:
                        entries.append((child_start, [], True))
                except (FileNotFoundError, ProcessLookupError):
                    pass
                except (PermissionError, ValueError, IndexError):
                    entries.append((None, [], True))
            self._lease_cache = entries
        token = ("GXTXT_RESOURCE_LEASE=" + record["id"]).encode()
        root = ("GXTXT_RESOURCE_ROOT=" + str(self.root)).encode()
        uncertain = False
        for child_start, env, unknown in self._lease_cache:
            if child_start is not None and child_start < started:
                continue
            if token in env and root in env:
                return True
            uncertain |= unknown
        return None if uncertain else False

    def _refresh(self, record, rescan=False):
        record["eligible"] = False
        if record["removed"]:
            return
        now = time.time()
        live = process_identity(record["owner_pid"])
        record["owner_alive"] = live == record["owner_identity"] and live not in {"dead", "unknown"}
        descendant = False
        if not record["owner_alive"] and record.get("descendant_lease"):
            descendant = self._descendant_alive(record)
            if descendant is True:
                record["owner_alive"] = True
        record["last_verified"] = now
        if not record["released"] and record["managed"]:
            if record["owner_alive"]:
                record["state"] = "active"
            elif live == "unknown" or record["owner_identity"] == "unknown" or descendant is None:
                record["state"] = "unknown_legacy"
            elif not record["recovery_required"]:
                if record["category"] in {"retained_diagnostic", "cache_reusable"}:
                    record.update(state=record["category"], released=True, last_access=now)
                else:
                    record["state"] = "verified_orphan"
        elif not record["managed"] and record["state"] == "active" and not record["owner_alive"]:
            record["state"] = "unknown_legacy"
        record["reason"] = "External resource: cleanup remains with its owner"
        if record["managed"]:
            record["reason"] = "Active owner lease or retained resource"
            if record["state"] == "verified_orphan":
                record["eligible"] = not record["recovery_required"] and (record["released"] or not record["owner_alive"])
            elif record["released"] and record["state"] in {"cache_reusable", "retained_diagnostic"}:
                # Cache retention of zero means keep indefinitely, never an
                # invitation to erase the renderer's warm cache.
                retention = record["retention_seconds"]
                record["eligible"] = retention > 0 and now >= record["last_access"] + retention
            if record["eligible"]:
                record["reason"] = "Verified released allocation; selected cleanup is permitted"
        if rescan:
            try:
                target = record["envelope"] if record["managed"] else record["path"]
                st = os.lstat(target)
                if record["managed"] and _identity(st) != record["identity"]:
                    raise ValueError("Allocation directory identity changed")
                if stat.S_ISLNK(st.st_mode):
                    raise ValueError("Linked resource is protected")
                if stat.S_ISDIR(st.st_mode):
                    fd = _safe_directory(target)
                    try:
                        record["bytes"], record["count"] = _scan_fd(fd, st.st_dev, [0])
                    finally:
                        os.close(fd)
                elif stat.S_ISREG(st.st_mode):
                    record["bytes"], record["count"] = st.st_size, 1
                else:
                    raise ValueError("Special filesystem resource")
                record["scan_error"] = ""
            except FileNotFoundError:
                record.update(bytes=0, count=0, scan_error="Resource is absent", eligible=False)
            except (OSError, ValueError) as exc:
                record.update(scan_error=str(exc), eligible=False)
            record["last_scan"] = now
        if record.get("scan_error"):
            record["eligible"] = False
            record["reason"] = record["scan_error"]

    def inventory(self, rescan=False):
        self._lease_cache = None
        with self._transaction():
            records = [json.loads(row[0]) for row in self.db.execute("SELECT record FROM resources")]
            summary = dict(bytes=0, count=0, resources=0, reclaimable_bytes=0, categories={}, subsystems={})
            for record in records:
                self._refresh(record, rescan)
                self._put(record)
            # Owner observations can overlap (for example protected publication
            # directory and its active writer). Count the actual storage union;
            # descendants subtract from their nearest recorded ancestor only.
            active = [r for r in records if not r["removed"]]
            unique = {}
            for record in sorted(active, key=lambda r: (not r["managed"], r["created"])):
                path = os.path.normpath(record["path"])
                record["accounted_bytes"] = record["bytes"] if path not in unique else 0
                record["accounted_count"] = record["count"] if path not in unique else 0
                if path not in unique:
                    unique[path] = record
            for path, record in unique.items():
                ancestors = [p for p in unique if path.startswith(p + os.sep)]
                if ancestors:
                    parent = unique[max(ancestors, key=len)]
                    parent["accounted_bytes"] = max(0, parent["accounted_bytes"] - record["bytes"])
                    parent["accounted_count"] = max(0, parent["accounted_count"] - record["count"])
            for record in records:
                if record["removed"]:
                    continue
                summary["bytes"] += record["accounted_bytes"]
                summary["count"] += record["accounted_count"]
                summary["resources"] += 1
                if record["eligible"]:
                    summary["reclaimable_bytes"] += record["accounted_bytes"]
                for key, name in (("categories", record["state"]), ("subsystems", record["subsystem"])):
                    item = summary[key].setdefault(name, dict(resources=0, bytes=0))
                    item["resources"] += 1
                    item["bytes"] += record["accounted_bytes"]
            return dict(resources=[r for r in records if not r["removed"]], summary=summary,
                        root=str(self.root), storage_root=str(self.storage), scanned=bool(rescan))

    def reconcile(self):
        return self.inventory(rescan=True)

    def cleanup(self, ids):
        results = []
        with self._transaction():
            for resource_id in ids:
                self._lease_cache = None
                record = self._get(resource_id)
                self._refresh(record, True)
                result = "already_removed" if record["removed"] else "refused"
                size = record["bytes"]
                if record["eligible"]:
                    try:
                        parent = _safe_directory(self.storage)
                        try:
                            fd = os.open(resource_id, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=parent)
                            try:
                                st = os.fstat(fd)
                                if _identity(st) != record["identity"]:
                                    raise ValueError("Allocation changed before cleanup")
                                _scan_fd(fd, st.st_dev, [0])
                                _remove_contents(fd, st.st_dev)
                            finally:
                                os.close(fd)
                            if _identity(os.stat(resource_id, dir_fd=parent, follow_symlinks=False)) != record["identity"]:
                                raise ValueError("Allocation changed before directory cleanup")
                            os.rmdir(resource_id, dir_fd=parent)
                        finally:
                            os.close(parent)
                        record.update(removed=True, bytes=0, count=0, eligible=False)
                        result = "removed"
                    except (OSError, ValueError) as exc:
                        record["reason"] = str(exc)
                        result = "refused: " + str(exc)
                self._put(record)
                self.db.execute("INSERT INTO audit VALUES (?,?,?,?,?,?)", (time.time(), resource_id, record["state"], record["path"], size, result))
                results.append(dict(id=resource_id, path=record["path"], bytes=size, result=result, reason=record["reason"]))
        return results


def _tcl_word(value):
    text = str(value)
    if not text:
        return "{}"
    return "".join({" ": "\\ ", "\t": "\\t", "\n": "\\n", "\r": "\\r", "\\": "\\\\"}.get(c, "\\" + c if c in "{}[]$;\"" else c) for c in text)


def tcl_value(value):
    if isinstance(value, dict):
        return " ".join(_tcl_word(k) + " " + _tcl_word(tcl_value(v)) for k, v in value.items())
    if isinstance(value, (tuple, list)):
        return " ".join(_tcl_word(tcl_value(v)) for v in value)
    if isinstance(value, bool):
        return "1" if value else "0"
    return "" if value is None else str(value)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root")
    parser.add_argument("--storage-root")
    parser.add_argument("--caller-pid", type=int)
    parser.add_argument("--tcl", action="store_true")
    parser.add_argument("operation", choices=["allocate", "observe", "release", "inventory", "reconcile", "cleanup", "policy"])
    parser.add_argument("arguments", nargs="*")
    args = parser.parse_args()
    manager = ResourceManager(args.root, args.storage_root, args.caller_pid)
    try:
        if args.operation == "cleanup":
            result = manager.cleanup(args.arguments)
        else:
            if len(args.arguments) % 2:
                raise ValueError("Arguments must be key/value pairs")
            values = dict(zip(args.arguments[::2], args.arguments[1::2]))
            for key in {"owner_pid", "retention_seconds", "expected_bytes", "max_bytes"} & values.keys():
                values[key] = int(values[key])
            for key in {"rescan", "recovery_required", "descendant_lease"} & values.keys():
                values[key] = values[key].lower() in {"1", "true", "yes"}
            result = getattr(manager, args.operation)(**values)
        print(tcl_value(result) if args.tcl else json.dumps(result, sort_keys=True))
    finally:
        manager.close()


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, sqlite3.Error) as exc:
        print(str(exc), file=sys.stderr)
        sys.exit(1)
