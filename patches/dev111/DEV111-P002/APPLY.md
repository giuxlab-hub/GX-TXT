# DEV111-P002 — Installation and rollback

For GX-TXT dev-111 r3, after DEV111-P001. Close GX-TXT and extract DEV111-P002-PUBLIC.zip outside the framework.

Apply:

    bash apply.sh /path/to/gxtxt

Rollback:

    bash apply.sh --rollback /path/to/gxtxt

The installer checks the existing source hashes, predecessor patch and Linux x86_64 platform before changing files. Retain the transaction backup until it is no longer needed.
