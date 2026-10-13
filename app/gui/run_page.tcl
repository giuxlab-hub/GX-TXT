# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildRunPage_before_execution_plan {} {
    variable cfg
    variable ch
    variable probe
    variable extra
    variable ui
    variable version
    # Run tab
    set f .top.nb.run
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 3 -weight 1
    ttk::label $f.sessionNote -text "SESSION = complete folder containing data/analysis. MANIFEST = configuration only. Use Open Session in the top bar to resume existing work." -wraplength 1100 -justify left
    grid $f.sessionNote -row 0 -column 0 -sticky ew -padx 5 -pady {5 2}
    ttk::frame $f.buttons
    ttk::button $f.buttons.start -text "PHASE 1 - IMPORT / SPLIT" -command ::GX::startAsync
    ttk::button $f.buttons.analysis -text "PHASE 2 - RUN SELECTED ANALYSES" -command ::GX::startAnalysis
    ttk::button $f.buttons.all -text "RUN PHASE 1 + PHASE 2" -command ::GX::startAll
    ttk::button $f.buttons.stop -text "STOP" -command ::GX::stopCurrent -state disabled
    ttk::button $f.buttons.save -text "Export configuration (.ini)..." -command ::GX::saveManifestDialog
    ttk::button $f.buttons.load -text "Load configuration only (.ini)..." -command ::GX::loadManifestDialog
    ttk::button $f.buttons.copy -text "Copy log" -command [list ::GX::copyTextWidget $f.log "Log"]
    ttk::button $f.buttons.session -text "Open session..." -command ::GX::chooseSession
    pack $f.buttons.start $f.buttons.analysis $f.buttons.all $f.buttons.stop $f.buttons.save $f.buttons.load $f.buttons.session $f.buttons.copy -side left -padx 3
    grid $f.buttons -row 1 -column 0 -sticky w -padx 5 -pady 7
    set ui(startButton) $f.buttons.start
    set ui(analysisStart) $f.buttons.analysis
    set ui(runAllButton) $f.buttons.all
    set ui(stopButton) $f.buttons.stop
    set ui(analysisStop) $f.buttons.stop

    set ui(status) "Ready"
    ttk::frame $f.status
    ttk::label $f.status.lab -textvariable ::GX::ui(status) -width 48
    ttk::progressbar $f.status.pb -orient horizontal -mode determinate -maximum 100
    set ui(progress) $f.status.pb
    pack $f.status.lab -side left -padx 4
    pack $f.status.pb -side left -fill x -expand 1 -padx 4
    grid $f.status -row 2 -column 0 -sticky ew -padx 5 -pady 4

    text $f.log -wrap none -height 30 -state disabled -font TkFixedFont
    ttk::scrollbar $f.sy -orient vertical -command [list $f.log yview]
    ttk::scrollbar $f.sx -orient horizontal -command [list $f.log xview]
    $f.log configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    grid $f.log -row 3 -column 0 -sticky nsew -padx {5 0} -pady {4 0}
    grid $f.sy -row 3 -column 1 -sticky ns -pady {4 0}
    grid $f.sx -row 4 -column 0 -sticky ew -padx {5 0}
    set ui(log) $f.log

}
