# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::setRunSelections {mode {onlyKey ""}} {
    variable cfg
    set pairs {
        run_analysis_ir analysis_ir
        run_analysis_identify analysis_identify
        run_analysis_compare analysis_compare
        run_analysis_holdled analysis_holdled
    }
    foreach {runKey activeKey} $pairs {
        if {$mode eq "none"} {
            set cfg($runKey) 0
        } elseif {$mode eq "all_active"} {
            set cfg($runKey) [expr {$cfg($activeKey) ? 1 : 0}]
        } elseif {$mode eq "only"} {
            set cfg($runKey) [expr {$runKey eq $onlyKey && $cfg($activeKey) ? 1 : 0}]
        }
    }
    refreshAnalysisStatus
    refreshManifestPreview
}

proc ::GX::moduleResultState {short} {
    variable currentSession
    if {$currentSession eq ""} { return "results: no session open" }
    switch -- $short {
        ir {
            set found [glob -nocomplain [file join $currentSession analysis IR * eventi_mark_space.csv]]
            return [expr {[llength $found] ? "results: PRESENT" : "results: absent"}]
        }
        identify {
            set found [glob -nocomplain [file join $currentSession analysis IR * identificazione_protocollo_IR.txt]]
            return [expr {[llength $found] ? "results: PRESENT" : "results: absent"}]
        }
        compare {
            return [expr {[file isfile [file join $currentSession analysis CONFRONTO_STADI risultati.txt]] ? "results: PRESENT" : "results: absent"}]
        }
        holdled {
            return [expr {[file isfile [file join $currentSession analysis HOLD_LED risultati.csv]] ? "results: PRESENT" : "results: absent"}]
        }
    }
    return "results: n/a"
}

proc ::GX::refreshRunModuleControls {} {
    variable cfg
    variable ui
    foreach {short active run} {
        ir analysis_ir run_analysis_ir
        identify analysis_identify run_analysis_identify
        compare analysis_compare run_analysis_compare
        holdled analysis_holdled run_analysis_holdled
    } {
        set catalogState [expr {$cfg($active) ? "ACTIVE" : "inactive"}]
        set ui(runState,$short) "$catalogState | [moduleResultState $short]"
        if {[info exists ui(runCheck,$short)] && [winfo exists $ui(runCheck,$short)]} {
            if {$cfg($active)} {
                $ui(runCheck,$short) state !disabled
            } else {
                set cfg($run) 0
                $ui(runCheck,$short) state disabled
            }
        }
    }
}

