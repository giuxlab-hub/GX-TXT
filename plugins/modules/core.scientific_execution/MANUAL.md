# Scientific Execution

Scientific modules submit typed provider requests through
`SCIENTIFIC_EXECUTION_API_v1`. CORE validates provider parameters, immutable
managed inputs and source identity before the existing Job Supervisor admits a
Job. Local and configured remote destinations share status, logs, cancellation
and registered result import contracts. Opening a Viewer runs no solver.

Compute nodes use mutual TLS. An administrator registers client certificates,
logical Session grants and trusted providers on the Debian agent. Client
Configuration retains endpoint and certificate/key file references outside
Session metadata. Private keys require owner-only access. The agent accepts
registered operations and managed input chunks; it accepts no arbitrary shell
or executable commands. Network unavailability is distinct from solver failure.

Remote Datasets remain authoritative on the node. Catalog projections retain
Dataset/Variable identity, units and source revisions. Consultation reads bounded
typed ranges or supported hyperslabs; complete local import is an explicit
canonical publication with a new local identity and remote lineage.
