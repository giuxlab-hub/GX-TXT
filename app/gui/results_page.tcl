# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildResultsPage {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Results tab
    set f .top.nb.results
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 1 -weight 1
    ttk::frame $f.buttons
    ttk::button $f.buttons.refresh -text "Refresh" -command ::GX::refreshResults
    ttk::button $f.buttons.copy -text "Copy results" -command [list ::GX::copyTextWidget $f.txt "Results"]
    pack $f.buttons.refresh $f.buttons.copy -side left -padx 4
    grid $f.buttons -row 0 -column 0 -sticky w -padx 5 -pady 5
    text $f.txt -wrap none -font TkFixedFont -state disabled
    ttk::scrollbar $f.sy -orient vertical -command [list $f.txt yview]
    ttk::scrollbar $f.sx -orient horizontal -command [list $f.txt xview]
    $f.txt configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    grid $f.txt -row 1 -column 0 -sticky nsew -padx {5 0}
    grid $f.sy -row 1 -column 1 -sticky ns
    grid $f.sx -row 2 -column 0 -sticky ew -padx {5 0}
    set ui(results) $f.txt

}
