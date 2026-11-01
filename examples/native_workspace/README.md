# Viewer Workspace examples

`no_hook.gxtxt-viewer` is a plain Builder interface with text, numeric and Boolean
fields and a Workspace component. Open it in Viewer Interface Builder and build
into a new source/output directory. The generated Viewer needs no persistence
handler. With a Session open, its Workspace menu provides Save, Save As, Close
and reopening through Session Workspaces. GUI values, interface definition and
geometry are captured through CORE's native typed Workspace service.

`typed_sdk` is a complete C++ Viewer Development project. Copy it into a new
writable development directory, open it in Viewer Development, then Validate,
Build and Preview with a Session open. Accept note records a typed custom model
and typed properties through `host.workspace()`. The facade reads an immutable
event snapshot and submits owning-thread CORE commands; the example handles no
SQL, paths, IPC, storage tables or internal transaction handles. The built-in
native `gx::State` envelope is persisted automatically too.

`cpp_hooks` supplies the optional C++ capture, validate, restore and committed
hooks for a small native note model. Open its copied project through the same
Development route. The trusted adapter captures and validates after each event,
restores on opening or explicit CORE restoration, and delivers committed only
after native durability. The author supplies no storage or IPC callbacks.

`typed_hooks.tcl` demonstrates optional host-side capture, validate, restore and
committed hooks. A connector may source it and pass
`workspace_hooks [::WorkspaceExample::hooks]` in the public Compose context.
Capture returns a typed `{kind value}` object. Restore must restore a captured
prior model as compensation if an incoming restoration fails. An uncompensatable
failure retains the prior snapshot and blocks Save until explicit recovery or
reopening. Committed receives a durable native receipt; asynchronous Save calls
it later on the owning GUI thread. Hook code supplies model logic only.

See the public `NATIVE_WORKSPACE_API_v1` and Viewer Workspace facade reference for
identity, revisions, durability, cancellation, scope and resource contracts.
