# GX-TXT 0.9.8.10-dev-112

This is a complete offline consolidation of independently accepted DEV111-P035,
not a patch to an existing installation. No DEV111 patch replay is needed.

Read [installation](distribution/INSTALL.md),
[side-by-side migration](distribution/MIGRATION.md), and
[recovery and release limits](distribution/RECOVERY.md) before first use.
All 149 non-demo modules are already expanded in the framework, including CORE
and ALWAYS. Extract the distribution into a new directory and start it; ordinary
modules need no separate installation. Independent modules were registered using
the official API during clean release preparation, without development state.
Only the 15 demos are supplied separately with their own dedicated installer.

The distribution preserves P035 runtime behavior. The only existing runtime
source edit is its release-version literal. No ALWAYS, CORE, activation,
Session, Analysis, or Plugin Manager policies were changed.
