# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildManifestPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Manifest tab - always accessible, generated from current GUI values
    set f .top.nb.manifest
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 1 -weight 1
    ttk::frame $f.buttons
    ttk::button $f.buttons.refresh -text "Refresh" -command ::GX::refreshManifestPreview
    ttk::button $f.buttons.load -text "Load configuration only (.ini)..." -command ::GX::loadManifestDialog
    ttk::button $f.buttons.save -text "Export configuration (.ini)..." -command ::GX::saveManifestDialog
    ttk::button $f.buttons.copy -text "Copy all" -command [list ::GX::copyTextWidget $f.txt "Manifest"]
    ttk::label $f.buttons.note -text "The manifest contains CONFIGURATION only; use Open Session to resume data and results."
    pack $f.buttons.refresh $f.buttons.load $f.buttons.save $f.buttons.copy $f.buttons.note -side left -padx 4
    grid $f.buttons -row 0 -column 0 -sticky w -padx 5 -pady 5
    text $f.txt -wrap none -font TkFixedFont -state disabled
    ttk::scrollbar $f.sy -orient vertical -command [list $f.txt yview]
    ttk::scrollbar $f.sx -orient horizontal -command [list $f.txt xview]
    $f.txt configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    grid $f.txt -row 1 -column 0 -sticky nsew -padx {5 0}
    grid $f.sy -row 1 -column 1 -sticky ns
    grid $f.sx -row 2 -column 0 -sticky ew -padx {5 0}
    set ui(manifest) $f.txt

}
