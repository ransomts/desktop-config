#!/usr/bin/env python3
"""A plain window for hypr-test: client.py CLASS [TITLE]. Hyprland's class is the Wayland app id,
taken from the program name, so any CLASS works (an application id would have to contain a dot)."""
import sys, gi
gi.require_version("Gtk", "4.0")
from gi.repository import Gtk, GLib
cls = sys.argv[1]
GLib.set_prgname(cls)
Gtk.init()
w = Gtk.Window(title=sys.argv[2] if len(sys.argv) > 2 else cls)
w.set_default_size(320, 200)
loop = GLib.MainLoop()
w.connect("close-request", lambda *_: loop.quit() or False)
w.present()
loop.run()
