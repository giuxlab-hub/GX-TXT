#!/usr/bin/env python3
"""Keep a GTK image clipboard owner alive for a GX-TXT X11 process.

Tk's byte-string clipboard encoding is not a reliable binary image transport
for independent X11 clients. GTK advertises standard image MIME targets and
serves the decoded PNG as an image for as long as this helper remains alive.
The parent owns stdin; closing it ends the helper.
"""
import base64
import sys

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk


def main():
    clipboard = Gtk.Clipboard.get(Gdk.SELECTION_CLIPBOARD)
    loop = GLib.MainLoop()
    current = {"pixbuf": None}

    def receive(_source, condition):
        if condition & GLib.IO_HUP:
            loop.quit()
            return False
        line = sys.stdin.readline()
        if not line:
            loop.quit()
            return False
        try:
            command, encoded = line.rstrip("\n").split(" ", 1)
            if command != "SET":
                raise ValueError("Unknown clipboard command")
            path = base64.b64decode(encoded, validate=True).decode("utf-8")
            pixbuf = GdkPixbuf.Pixbuf.new_from_file(path)
            if pixbuf.get_width() < 1 or pixbuf.get_height() < 1:
                raise ValueError("Empty PNG image")
            clipboard.set_image(pixbuf)
            current["pixbuf"] = pixbuf
            print(f"OK {pixbuf.get_width()} {pixbuf.get_height()}", flush=True)
        except Exception as exc:
            print(f"ERROR {exc}", flush=True)
        return True

    GLib.io_add_watch(sys.stdin, GLib.IO_IN | GLib.IO_HUP, receive)
    loop.run()


if __name__ == "__main__":
    main()
