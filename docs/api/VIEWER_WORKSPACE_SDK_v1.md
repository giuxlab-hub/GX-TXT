# Viewer Workspace SDK v1

The public `gx::Host::workspace()` facade uses `NATIVE_WORKSPACE_API_v1`.
Declare a Workspace component in the Viewer design. Builder registers its
provider and typed GUI schema automatically. Entry, field, toggle, choice,
selection, visibility and window geometry use the shared host's capture and
restore. An author needs no persistence handler for these controls. Scientific
components use their declared scientific owners and explicit schema codecs.

Examples live in `examples/native_workspace`: `no_hook.gxtxt-viewer` uses the
ordinary Builder route; `typed_sdk` and `cpp_hooks` are normal Development
projects with `project.json`, design and authored C++ handlers.

`gx::WorkspaceValue` distinguishes null, text, boolean, signed integer, finite
number, object, array and managed resource. Use `workspace_text`,
`workspace_integer`, `workspace_number`, `workspace_flag`, `workspace_object`,
`workspace_array` and `workspace_resource` to construct values. Scientific text
such as `001 {a b}` stays text. Managed resource descriptors retain their owner,
generation, hash and size; factories do not grant arbitrary file access.

| Facade method | Behavior |
|---|---|
| `state()` | Immutable typed custom-state snapshot for this event |
| `property(name)` | Immutable author property snapshot |
| `status()` | Identity, accepted/durable revisions, dirty/pending/failure status |
| `query()` | Provider-scoped metadata snapshot, at most 1000 entries |
| `set_state(value)` | Stage a typed object as custom state |
| `set_property(name,value)` | Stage a typed author property |
| `save(asynchronous=false)` | Submit the completed event state for persistence |
| `save_as(name)` | Create and adopt a distinct Workspace from the current draft |
| `rename(name)` | Rename the bound identity using its expected revision |
| `open(id)` | Provider-checked Open with the host's dirty review |
| `close()` | Dirty review and durable close barrier |

Declare the operations actually used under `required_apis` in `project.json`.
Reading snapshots requires native `get`; typed mutation and Save require their
named operations. Optional hooks require native `get` and `save`. The API
Browser discovers signatures; discovery does not grant execution privileges.
There is no generic SQL, file-path or arbitrary family dispatch method.

Calls that mutate the Workspace are deferred until `on_event` completes
successfully. The host first adopts the event's completed native State and
captured custom model, then applies commands in order. A failed callback drops
its deferred commands. A returned SDK boolean acknowledges command submission,
not disk durability. `status()` and `query()` remain immutable for that event;
read the next event snapshot or use `on_workspace_committed` for completion.
Open and Close can replace/destroy a window; no later command from the old
window lifetime is applied to its replacement.

Authors may implement any of these declared functions in namespace `gx`:

```cpp
WorkspaceValue on_workspace_capture();
void on_workspace_validate(const WorkspaceValue& state);
void on_workspace_restore(const WorkspaceValue& state);
void on_workspace_committed(const WorkspaceStatus& status);
```

Capture returns an object, and validation runs before the captured state is
accepted. Capture hooks own custom state exclusively: do not combine them with
`set_state` or another host capture hook. Restore validates before adoption.
Prepare a replacement model before mutating the current one. On rejection the
host attempts restoration of the prior snapshot; if compensation also fails it
retains recovery evidence and refuses Save until recovery/reopen. Hooks execute
in the managed compiled Viewer worker. They never execute on the persistence
worker and must not access Tk. The trusted host alone projects GUI changes.

The committed callback receives an acknowledgement only after its accepted
revision is durable. Synchronous Save waits; asynchronous Save returns pending
and completion is delivered later on the GUI thread through the managed worker.
Normal Close drains accepted work and delivers pending completions before
disposing the Viewer. A completion-hook error after a durable commit is reported
as `POST_COMMIT_HOOK_FAILED`; it does not undo saved data. A native storage
failure retains the draft and prior valid durable data and reports failed status.
Cancel leaves identity, unsaved state and window intact.

Trusted Tcl hosts can supply `workspace_hooks` in Compose context. `capture`
takes a window and returns `{object typedFields}`; `validate` takes typed state;
`restore` takes window and typed state; `committed` takes window and a durable receipt. These are
owning-thread host callbacks, not a second persistence authority. See
`examples/native_workspace/typed_hooks.tcl`.

The simple direct native `save_as` service currently rejects retained resources,
notes and named archives pending complete portable adoption. It never silently
borrows another owner's managed files. Scientific client migration, portable
transfer and History menu integration remain separately tracked incomplete work.
