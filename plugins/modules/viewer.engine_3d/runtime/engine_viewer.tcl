# SPDX-License-Identifier: GPL-3.0-or-later
# Compatibility entrypoint; the renderer/worker/control host is shared in CORE.
if {![llength [info commands ::GX::native3DGuiHostApiInfo]]} {
    source [file join $::GX::scriptDir core tcl native3d_gui_host_v1.tcl]
}
