# Session HTML Export

`export.session_html` 1.0.2 is a GX-TXT export module that creates a static,
read-only, offline website from the current Session.

It uses the public Session Inspection API v1 and registers the Session action
`Export Session to HTML...` through Session Action Provider API v1. The result
requires only a normal desktop browser; it does not require GX-TXT, Tcl/Tk,
Octave, Python, a local web server or an Internet connection.

See `SESSION_HTML_EXPORT.md` for the user workflow and limitations.

License: GPL-3.0-or-later.

HTML export must be verified against a disposable Session, including a browser-readable offline result.
