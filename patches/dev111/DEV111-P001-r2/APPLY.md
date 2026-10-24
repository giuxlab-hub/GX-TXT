# DEV111-P001 installer revision 2

GX-TXT dev-111 r3 only. Patch P001 source content is unchanged from revision 1; only the installation helper is simplified. Close GX-TXT.

Extract this distribution ZIP into a separate directory and from that directory run:

    bash apply.sh /path/to/gxtxt

Restore the six original files with GX-TXT closed using:

    bash apply.sh --rollback /path/to/gxtxt

The installer checks exact original file SHA-256 values, the two unchanged release guards and Unix permissions before writing. It uses /home/giu/script-ag/current/gxtxt when no target argument is provided. Keep all created transaction backups. On a Git checkout with file mode 0644 rather than the expected installed file mode 0664, the original helper refuses application; use an installation with the documented original modes, without bypassing preflight checks.

After P001-r2, apply P002, then P003, P004 and P005 in numerical order when needed. Neither this public distribution nor the historical P001 tag changes the official dev-111 r3 source release.
