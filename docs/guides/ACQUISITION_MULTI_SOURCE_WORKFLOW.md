# Acquisition multi-source workflow — GX-TXT v0.9.0

For an acquisition plug-in declaring `supports_batch=1`, the normal workflow is now:

```text
Browse... first source
        ↓
framework enables source batch
        ↓
row #1: Use=ON, Pending
        ↓
+ Add source / Add sources...
        ↓
additional Pending rows
        ↓
PHASE 1
        ↓
one new session + every enabled row imported
```

After that session exists:

```text
+ Add source
        ↓
new Pending row(s)
        ↓
Import enabled pending into current session
        ↓
current session is preserved
```

Only rows with `Use=ON` are imported. `Pending`/`Imported` status and Dataset Registry updates remain framework-owned.

If the plug-in declares `group_proc`, **Add sources...** may collapse multiple selected RAW files into one logical Pending acquisition row. This does not perform any scientific join/interpolation.
