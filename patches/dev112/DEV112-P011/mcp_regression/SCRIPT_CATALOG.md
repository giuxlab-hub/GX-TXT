# P011 MCP compatibility regression

`PYTHONPATH=PRIVATE_PINNED_VENDOR python3 -B validation/dev112_p011_mcp/check.py FRAMEWORK NEW_OUTPUT [EXTRACTED_ADAPTER_LAUNCHER]`

Scope: P011 adapter0.2.0 with pinned SDK2.3.0 against compatible public Bridge
contracts. FRAMEWORK can be an isolated P009/P010/P011 source installation;
the adapter source comes from this delivered regression tree. An optional
launcher exercises an independently extracted updated Debian package.
Never run historical P009 check.py unchanged on a newer framework.

Creates only NEW_OUTPUT (must not exist), protected private XDG/config/cache/
Resource/Job/Session roots, synthetic Sessions A/B and owned loopback endpoint.
Runs actual stdio/HTTP SDK initialization, discovery, authentication, live public
catalog and runtime compatibility receipt; protocol counteroffer, Host/Origin/
header/body/concurrency bounds, independent connections, grant revocation,
lease cleanup, crash/restart and normal stop. Credentials stay in memory/stdin
and are scanned out of ordinary logs and Session state. No real Session,
production installation, deposited source or existing service is modified.
The test stops its own recorded adapter process in a finally block.
