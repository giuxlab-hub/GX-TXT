# Optional GX-TXT MCP adapter

The adapter uses an existing GX-TXT installation with compatible public Bridge contracts. It owns MCP
transport/authentication/client contexts and local diagnostic staging. The
installed Script Bridge, Registry, Projects, Job Supervisor, debugger, Dataset,
Workspace and Resource services retain their existing authority.

The tested SDK is `mcp==2.3.0`; the reference handshake protocol is `2025-11-25`.
The official [transport specification](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports)
and [Python SDK documentation](https://py.sdk.modelcontextprotocol.io/) describe
the protocol and SDK. Both local stdio and authenticated loopback Streamable
HTTP are supported. No tunnel, remote listener or cloud connection is created.

`gxtxt-mcp init /absolute/installed/framework` creates one protected user-local
configuration, with the service OFF and no clients. `info` reports actual local
state; `check` verifies actual installed public declarations independently of framework release labels.
An enabled stdio service is ready for a client to launch, rather than a daemon.
`start`/`stop` manage only the optional HTTP adapter process, preserving accepted
Jobs under the original supervisor. The CLI and Configuration MCP interface
use the same configuration authority. Default storage is
`$XDG_CONFIG_HOME/gxtxt-mcp` (or the normal user config directory); directories
must be0700 and files0600. `GXTXT_MCP_HOME` selects an explicit local test/profile
directory. Never share it with another user.

Create a local client with `client-add CLIENT_ID`. The credential is displayed
once and only its SHA-256 is retained. A new client has Read only, no Session,
and no general direct invocation, Author or Run grant. `grant` and `revoke`
are explicit local owner actions. Session grants use exact selected canonical
Session identities. Stdio reads the credential from
`GXTXT_MCP_CLIENT_TOKEN`; HTTP requires a Bearer credential and validates the
Host, optional Origin, protocol header, body budget and connection ownership.
Secrets never belong in command arguments, reports, Session snapshots or logs.

Read-only API discovery uses the original live Bridge in a selected authorized
context. The standard `gxtxt_scientific_workflow` Prompt and tool descriptions
recommend existing scientific APIs before replacement numerical code. The
catalog resource template is `gxtxt://bridge/catalog/{scope}`, with
`scope=current`; exact descriptors use `gxtxt://bridge/api/{api_id}`.

`gxtxt_bridge_call` forwards exact API ID, operation and the original typed
argument envelopes. It returns the original success/error envelope unchanged
under `bridge_response`, including error identifiers. It creates no temporary
Script or source digest. There is no scientific API/provider allowlist.
An explicit general invocation grant authorizes this boundary; original owners
still validate provider activation, Session, source, arguments and lifetime.
Authorized User metadata mutations use the existing User metadata owner rather
than impersonating an installed module. Registered module calls retain their
original contributor restrictions. Module-owned private writes and publication
still require their genuine original producer context.

Large arrays retain original typed binary descriptors. Read bounded opaque
bytes through `gxtxt://bridge/buffer/{resource_id}/{offset}/{count}` in the same
client context. The original binary-buffer owner validates identities and
sizes. A result budget/timeout is explicit and never silently truncates a
scientific result or replays a mutation. Ending a context releases only its
transport resources, not accepted supervised Jobs.

Author and Run remain distinct. Before source authoring, review an exact typed
API request and use `approve-request CLIENT_ID REQUEST.json`; authoring also
requires the Author grant. Before execution, use `approve-source CLIENT_ID
IDENTITY.json` with the original Registry reference, source SHA, revision,
record SHA and owner context. Pass `approved_reference` to the generic call;
the original scripting owner checks that exact identity. Source review uses
the original editors/Script Library and source snapshots. Python execution is
not an OS sandbox. The native Octave debugger does not support asynchronous
Pause; its actual capability/error is preserved.

Issue reporting accepts only public identities, controlled observations and
provisional classifications. Reports include the actual API/provider versions
and SHA-256 revisions of the exact public API and operation descriptors when
available; unavailable metadata is explicitly unknown. Default reports omit arguments, raw logs, paths,
hostnames, credentials, source and Session/Dataset contents. Preview is
read-only. Persistence requires separate local approval of the exact report
digest with `approve-report`; `export-report` is an explicit local action.
The adapter never publishes reports, opens GitHub issues, sends messages or
uploads data automatically.

Install and configure (Debian 13 amd64, Python 3.13):

```
sudo apt install ./gxtxt-mcp-server_0.2.0-1_amd64.deb
gxtxt-mcp init /absolute/existing/GX-TXT
gxtxt-mcp check
gxtxt-mcp info
```

To upgrade adapter0.1.0, close its stdio clients and stop its HTTP process with
`gxtxt-mcp stop` before replacing the package. If a user unit was explicitly
started, stop that unit as the same user too. Keep the protected existing profile;
do not run `init` again for an unchanged installation path. Install0.2.0, then
run `check`, `info` and an authenticated `test --token-stdin` with an explicitly
granted private test Session. Existing credentials, grants and configuration
revision remain with their original owner. Restart only the transport the owner
explicitly wants. Accepted Supervisor Jobs keep their original lifetime.

Local `info` and server metadata use `protocol_version` for the adapter reference
profile. The actual negotiated connection version is in the standard MCP
initialize result and the Test result. It is separate from GX-TXT API and release
compatibility. Framework patch changes do not require profile reinitialization.

Installation performs no service activation, creates no clients and grants no
Session access. `init` records the selected installation with `enabled=false`.
`Configuration → MCP` projects this same protected CLI/configuration. It remains
usable when the independent package is absent. The framework's ordinary Save
user defaults does not copy MCP configuration or secrets.

Use `client-add CLIENT` locally to display a new credential once. Save it in the
MCP client's protected settings; it is never returned by `info`. Use `grant`
with explicit `--read`, `--author`, `--run`, `--invoke`, and exact `--session`
paths. `--clear-sessions` removes all Session admission. `revoke CLIENT` removes
the credential and grants; live calls recheck admission after queuing. Review
source in the existing Script Library/editor. The GUI's request/source review
pins the review file SHA so changing that file before approval is refused.

Tighter response limits apply to every request, including existing contexts.
After increasing transport limits, explicitly reselect the authorized Session
to allocate a new context. An oversized or unresolved outcome is never replayed
automatically.

Enable with `configure --expected-revision REV --enabled true`. Select
`--transport streamable-http --port PORT` while stopped, then `start`. For stdio,
the authorized client launches `gxtxt-mcp serve --transport stdio` with the
credential in `GXTXT_MCP_CLIENT_TOKEN`. HTTP clients use the endpoint shown in
the GUI and `Authorization: Bearer TOKEN`; no token belongs in argv.

`gxtxt-mcp test --token-stdin [--session /exact/authorized/Session]` accepts a
credential through stdin and performs a real SDK-negotiated handshake, required
tools/Prompt/catalog Resource discovery and authenticated server-info call.
An optional Session also tests the original live Bridge catalog. `check` only
verifies installed declarations independently of framework release labels; it does not claim
runtime provider availability. `info` separates process state from Test health.
Boundary diagnostics contain bounded status codes/times/counts only.

`stop` terminates only the recorded adapter process, preserving accepted
Supervisor Jobs. `cleanup` stops that adapter and removes only abandoned
transport directories whose protected exclusive leases are free; active stdio
contexts are preserved. It retains configuration, credentials and deliberately
persisted reports. Before removing the package run `gxtxt-mcp cleanup` as the
same ordinary user. If you explicitly enabled the optional user unit, first run
`systemctl --user disable --now gxtxt-mcp.service`. Then remove the package with
the normal Debian package manager. There are no root daemon or automatic
maintainer-script actions. Package removal deletes only packaged adapter files;
user-selected scientific installations and user data are outside the package.

The optional user unit uses `KillMode=process` and is never enabled by package
installation. Choose CLI-managed Start/Stop or the user unit for one configuration;
its exclusive service lock prevents two adapters from sharing that service.

For offline rebuilds, obtain the exact wheel filenames/versions/checksums in
`requirements.lock.json` using `python -m pip download --only-binary=:all:
--require-hashes -r requirements.lock --dest WHEELHOUSE`. Then run
`python3 packaging/build_deb.py FRAMEWORK WHEELHOUSE NEW_OUTPUT`. The builder
verifies every SHA256, safely unpacks only locked wheels into an isolated vendor
directory, preserves original dependency license notices/METADATA, and embeds
its lock and licenses in the package. No pip, network, second framework, or
system Python package mutation is needed at installation/runtime.

## Framework compatibility negotiation

Framework `VERSION.txt` and `PATCH_LEVEL.txt` are diagnostic labels only. They
are never admission rules. The same adapter supports compatible P009, P010,
P011 and future releases without a patch-specific update. No installed
framework code, Session or scientific values are modified by negotiation.

`check` invokes the selected original Bridge's inert `--metadata-tcl` public
discovery, verifies the inactive metadata envelope, and reports the actual API
count, declaration hash and optional feature contracts with their exact missing
API/version/operation. Missing TeX, Registry or debugger operations affect that
feature; they do not disable unrelated generic public API discovery/invocation.
The live Bridge remains the sole authority for the APIs actually exported in an
authorized Session. Unknown API or operation errors retain its original identity.

Selecting a Session performs real authenticated Bridge startup and validates
`OCTAVE_SCRIPT_BRIDGE_API_v1` API version1, supported transport version2,
binary descriptor version2, `active=true` and `execution_profile=authorized_direct`.
The returned compatibility receipt distinguishes inert declarations from this
actual runtime verification. Missing transport/security contracts reject that
context with `GXTXT:MCP:ContractIncompatible` and the exact field/version. An
existing accepted context is retained when replacement admission fails.

The SDK remains pinned separately to2.3.0. Its standard initialize negotiation
owns MCP handshake versions; unsupported offers receive the SDK's supported
counteroffer. HTTP protocol headers still reject unsupported versions with400.
This adapter's client-context lifecycle supports the SDK handshake revisions;
per-request modern MCP protocols are a separate transport capability, not a
GX-TXT patch requirement. The pinned default/test handshake is2025-11-25.
See the official [MCP2025-11-25 lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle)
and [HTTP protocol header contract](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports).

Authentication, local-only transport, exact Session grants, Author/Run/Invoke
permissions, approved source/request identities, original resource leases and
host-only public API restrictions remain enforced. Compatibility checks grant
no additional authority. Stop/reconnect never replay an unresolved mutation.
