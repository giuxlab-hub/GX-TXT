# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::buildAnalysisQueue_v048 {} {
    variable cfg
    variable ch
    variable currentSession
    variable scriptDir
    set q {}
    if {$currentSession eq "" || ![file isdirectory [file join $currentSession channels]]} {
        error "Open or create a valid session first."
    }
    set ncpu $cfg(cpu_count)
    set octave $cfg(octave_cmd)
    set mdir [file join $scriptDir modules]
    set commonEnv [concat [list OMP_NUM_THREADS=$ncpu OPENBLAS_NUM_THREADS=$ncpu MKL_NUM_THREADS=$ncpu NUMEXPR_NUM_THREADS=$ncpu] [graphicsEnv] [plotEnv]]

    set nodes [split [string map [list ";" ","] $cfg(analysis_ir_nodes)] ","]
    set clean {}
    foreach n $nodes { set n [string trim $n]; if {$n ne ""} { lappend clean $n } }

    set runIR [expr {$cfg(analysis_ir) && $cfg(run_analysis_ir)}]
    set runIdentify [expr {$cfg(analysis_identify) && $cfg(run_analysis_identify)}]
    set runCompare [expr {$cfg(analysis_compare) && $cfg(run_analysis_compare)}]
    set runHold [expr {$cfg(analysis_holdled) && $cfg(run_analysis_holdled)}]

    if {$runIR || $runIdentify} {
        if {[llength $clean] == 0} { error "IR/Identification selected but no IR node was specified." }
    }

    if {$runIR} {
        foreach node $clean {
            set csv [findNodeRigol $currentSession $node]
            if {$csv eq ""} { error "IR analysis: missing Rigol extract for node $node." }
            lassign [nodePlotMeta $node] nodeLabel nodeColor
            set od [file join $currentSession analysis IR [sanitize $node]]
            file mkdir $od
            set prefix "ir.[sanitize $node]"
            set launcher [writeOctaveLauncher "ir_[sanitize $node]" "GXTXT_analisi_VIR_protocollo_v2_4($cfg(analysis_verbosity),'full',$cfg(cpu_count));"]
            set cmd [concat [list env] $commonEnv [list \
                GXTXT_IR_CSV=$csv \
                GXTXT_IR_OUTPUT_DIR=$od \
                GXTXT_IR_NOMINAL_CARRIER_HZ=$cfg(analysis_nominal_carrier_hz) \
                GXTXT_IR_CLUSTER_GUARD=$cfg(analysis_ir_cluster_guard) \
                GXTXT_IR_CLUSTER_MAX_RATIO=$cfg(analysis_ir_cluster_max_ratio) \
                GXTXT_PNG_DPI=$cfg(analysis_png_dpi) \
                GXTXT_IR_SIGNAL_LABEL=$nodeLabel \
                GXTXT_IR_SIGNAL_COLOR=$nodeColor \
                GXTXT_IR_LEGEND_PREFIX=$prefix \
                $octave --quiet --no-gui $launcher]]
            lappend q [list "IR v2.4 - $node" $cmd]
        }
    }

    if {$runIdentify} {
        foreach node $clean {
            set od [file join $currentSession analysis IR [sanitize $node]]
            set ev [file join $od eventi_mark_space.csv]
            if {!$runIR && ![file isfile $ev]} {
                error "Protocol identification - $node: eventi_mark_space.csv is missing. Also select IR Analysis or run the IR module first."
            }
            set body "GXTXT_identifica_protocollo_IR_v1('[octaveQuote $ev]',\[\],$cfg(analysis_verbosity));"
            set launcher2 [writeOctaveLauncher "identify_[sanitize $node]" $body]
            set cmd2 [concat [list env] $commonEnv [list $octave --quiet --no-gui $launcher2]]
            lappend q [list "Protocol identification - $node" $cmd2]
        }
    }

    if {$runCompare} {
        set od [file join $currentSession analysis CONFRONTO_STADI]
        file mkdir $od
        set script [file join $mdir GXTXT_confronto_stadi_v1.m]
        set customSpec [writeCompareCustomPlotFile $od]
        set customEnv {}
        if {$customSpec ne ""} { lappend customEnv GXTXT_COMPARE_CUSTOM_FILE=$customSpec }
        set cmd [concat [list env] $commonEnv $customEnv [list GXTXT_PNG_DPI=$cfg(analysis_png_dpi) $octave --quiet --no-gui $script --out $od --nominal-carrier $cfg(analysis_nominal_carrier_hz) --dpi $cfg(analysis_png_dpi)]]
        set count 0
        for {set i 1} {$i <= 8} {incr i} {
            if {!$ch($i,enabled)} continue
            set f [findNodeRigol $currentSession $ch($i,name)]
            if {$f eq ""} continue
            lappend cmd --channel "$ch($i,name)|$f"
            incr count
        }
        if {$count < 2} { error "Stage comparison: at least two synchronized Rigol extracts are required." }
        lappend q [list "Synchronized stage comparison" $cmd]
    }

    if {$runHold} {
        set hf [findNodeRigol $currentSession $cfg(analysis_hold_node)]
        set lf [findNodeRigol $currentSession $cfg(analysis_led_node)]
        if {$hf eq "" || $lf eq ""} { error "HOLD/LED v6 requires Rigol extracts for $cfg(analysis_hold_node) and $cfg(analysis_led_node)." }
        lassign [nodePlotMeta $cfg(analysis_hold_node)] holdLabel holdColor
        lassign [nodePlotMeta $cfg(analysis_led_node)] ledLabel ledColor
        set od [file join $currentSession analysis HOLD_LED]
        file mkdir $od
        set merged [file join $od time_led_pipeline.csv]
        set merge [file join $mdir gxtxt_merge_hold_led.py]
        set cmdm [list [runtimeToolRequired python] $merge --hold $hf --led $lf --out $merged]
        lappend q [list "Prepare HOLD/LED input" $cmdm]
        set testRaw [string trim $cfg(test)]; if {$testRaw eq ""} { set testRaw "hold_led" }
        set testid [sanitize $testRaw]
        set rg [string trim $cfg(p_gain_ohm)]; if {$rg eq ""} { set rg "NaN" }
        set rs [string trim $cfg(p_sens_ohm)]; if {$rs eq ""} { set rs "NaN" }
        set vv [string trim $cfg(holdled_vgen_v)]; if {$vv eq ""} { set vv "NaN" }
        set ip [string trim $cfg(holdled_ipd_ua)]; if {$ip eq ""} { set ip "NaN" }
        set holdScript [file join $mdir GXTXT_singola_v6_pipeline.m]
        set launcher [writeOctaveLauncher "hold_led_v6" "run('[octaveQuote $holdScript]');"]
        set cmdh [concat [list env] $commonEnv [list \
            GXTXT_HOLDLED_CSV=$merged \
            GXTXT_TEST_ID=$testid \
            GXTXT_RGAIN_OHM=$rg \
            GXTXT_RSENS_OHM=$rs \
            GXTXT_FREQUENZA_HZ=$cfg(analysis_nominal_carrier_hz) \
            GXTXT_NUMERO_IMPULSI=$cfg(holdled_num_impulses) \
            GXTXT_VGEN_V=$vv \
            GXTXT_DUTY_PCT=$cfg(holdled_duty_pct) \
            GXTXT_IPD_UA=$ip \
            GXTXT_MODALITA_STIMOLO=$cfg(holdled_mode) \
            GXTXT_TRIGGER_REFERENCE=$cfg(holdled_trigger_reference) \
            GXTXT_RLED_OHM=$cfg(holdled_rled_ohm) \
            GXTXT_RHOLD_OHM=$cfg(holdled_rdischarge_ohm) \
            GXTXT_HOLDLED_OUTPUT_ROOT=$od \
            GXTXT_PNG_DPI=$cfg(analysis_png_dpi) \
            GXTXT_HOLD_LABEL=$holdLabel \
            GXTXT_LED_LABEL=$ledLabel \
            GXTXT_HOLD_COLOR=$holdColor \
            GXTXT_LED_COLOR=$ledColor \
            $octave --quiet --no-gui $launcher]]
        lappend q [list "HOLD/LED Analysis v6" $cmdh]
    }
    if {[llength $q] == 0} { error "No module selected for this run. Checkboxes in ANALYSIS select what to recalculate now; existing results remain unchanged." }
    return $q
}

proc ::GX::startPreparedQueue {queue operation} {
    variable analysisPipe
    variable analysisQueue
    variable analysisTotal
    variable analysisDone
    variable analysisOperation
    variable ui
    variable currentSession
    if {$analysisPipe ne ""} return
    if {[llength $queue] == 0} { return }
    set analysisQueue $queue
    set analysisOperation $operation
    if {$operation ne "Targeted analysis" && $currentSession ne "" && [file isdirectory [file join $currentSession metadata]]} {
        catch {writeManifest [file join $currentSession metadata manifest.ini]}
    }
    set analysisTotal [llength $analysisQueue]
    set analysisDone 0
    set lf [file join $currentSession logs analysis.log]
    set ui(analysisLogFile) [open $lf a]
    fconfigure $ui(analysisLogFile) -encoding utf-8 -translation lf -buffering line
    if {[info exists ui(startButton)]} { $ui(startButton) configure -state disabled }
    if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state disabled }
    if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state disabled }
    if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state normal }
    analysisLog "$operation - queue started: $analysisTotal stages."
    runNextAnalysis
}

proc ::GX::startAnalysis {} {
    if {[catch {set q [buildAnalysisQueue]} err]} {
        tk_messageBox -icon error -title "GX-TXT Analysis" -message $err
        return
    }
    startPreparedQueue $q "Selective analysis"
}

proc ::GX::runNextAnalysis_v077 {} {
    variable analysisPipe
    variable analysisQueue
    variable analysisDone
    variable analysisTotal
    variable analysisPids
    variable ui
    if {[llength $analysisQueue] == 0} {
        set analysisPipe ""
        if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { catch {close $ui(analysisLogFile)}; set ui(analysisLogFile) "" }
        $ui(startButton) configure -state normal
        $ui(analysisStart) configure -state normal
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
        $ui(stopButton) configure -state disabled
        variable analysisOperation
        analysisLog "$analysisOperation completed."
        setStatus "$analysisOperation completed" 100
        if {$analysisOperation eq "Plot rerendering"} {
            catch {unset ui(graphPreviewLoadSig)}
            catch {unset ui(graphPreviewFitW)}
            catch {unset ui(graphPreviewFitH)}
        }
        catch {refreshResults}; catch {refreshGraphs}; catch {refreshOpenGraphWindow}; catch {refreshAnalysisStatus}
        tk_messageBox -icon info -title "GX-TXT" -message "$analysisOperation completed."
        return
    }
    set item [lindex $analysisQueue 0]
    set analysisQueue [lrange $analysisQueue 1 end]
    set label [lindex $item 0]
    set cmd [lindex $item 1]
    set ui(analysisCurrentLabel) $label
    analysisLog "=== $label ==="
    analysisLog "Server command: $cmd"
    if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { puts $ui(analysisLogFile) "=== $label ===\n$cmd" }
    set pipeline [concat | $cmd [list 2>@1]]
    if {[catch {
        set analysisPipe [open $pipeline r]
        set analysisPids [pid $analysisPipe]
        fconfigure $analysisPipe -blocking 0 -buffering line -encoding utf-8
        fileevent $analysisPipe readable [list ::GX::onAnalysisReadable $analysisPipe]
        set pct [expr {100.0*$analysisDone/max(1,$analysisTotal)}]
        variable analysisOperation
        setStatus "$analysisOperation: $label" $pct
    } err]} {
        analysisLog "START ERROR: $err"
        stopAnalysis 0
    }
}

proc ::GX::onAnalysisReadable_v077 {p} {
    variable analysisPipe
    variable analysisDone
    variable analysisTotal
    variable ui
    if {$p ne $analysisPipe} return
    while {[gets $p line] >= 0} {
        analysisLog $line
        if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { puts $ui(analysisLogFile) $line }
    }
    if {[eof $p]} {
        fileevent $p readable {}
        set ok 1; set errtxt ""
        if {[catch {close $p} err]} { set ok 0; set errtxt $err }
        set analysisPipe ""
        if {!$ok} {
            analysisLog "ERROR: $errtxt"
            if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { catch {close $ui(analysisLogFile)}; set ui(analysisLogFile) "" }
            $ui(startButton) configure -state normal
            $ui(analysisStart) configure -state normal
            if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
            $ui(stopButton) configure -state disabled
            setStatus "Analysis error" 0
            variable analysisOperation
            tk_messageBox -icon error -title "GX-TXT" -message "$analysisOperation: module finished with an error.\n\n$errtxt"
            return
        }
        incr analysisDone
        variable analysisOperation
        setStatus "$analysisOperation: $analysisDone / $analysisTotal" [expr {100.0*$analysisDone/max(1,$analysisTotal)}]
        runNextAnalysis
    }
}

proc ::GX::stopAnalysis_v077 {{message 1}} {
    variable analysisPipe
    variable analysisPids
    variable analysisQueue
    variable ui
    variable runAllPending
    if {$analysisPipe ne ""} {
        fileevent $analysisPipe readable {}
        if {[info exists ::GX::analysisOwnedGroup] && $::GX::analysisOwnedGroup} {
            foreach p $analysisPids {catch {exec kill -TERM -- -$p}}
        }
        foreach p $analysisPids { catch {exec kill -TERM $p} }
        catch {close $analysisPipe}
    }
    set ::GX::analysisOwnedGroup 0
    set analysisPipe ""; set analysisPids {}; set analysisQueue {}
    if {[info exists ui(analysisLogFile)] && $ui(analysisLogFile) ne ""} { catch {close $ui(analysisLogFile)}; set ui(analysisLogFile) "" }
    set runAllPending 0
    if {[info exists ui(startButton)]} { $ui(startButton) configure -state normal }
    if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
    if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
    if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state disabled }
    analysisLog "Analysis interrupted."
    if {$message} { setStatus "Analysis interrupted" 0 }
}

proc ::GX::refreshAnalysisStatus_v050 {} {
    variable ui
    variable cfg
    variable currentSession
    catch {refreshRunModuleControls}
    if {![info exists ui(analysisStatus)] || ![winfo exists $ui(analysisStatus)]} return
    set w $ui(analysisStatus); $w configure -state normal; $w delete 1.0 end
    if {$currentSession eq ""} {
        $w insert end "No current session. Run the import or open an existing session.\n"
    } else {
        $w insert end "SESSION: $currentSession\n\n"
        set nodes [currentChannelNames]
        $w insert end "Nodes in manifest: [join $nodes {, }]\n\n"
        $w insert end "RUN NOW: IR=$cfg(run_analysis_ir), identify=$cfg(run_analysis_identify), compare=$cfg(run_analysis_compare), HOLD/LED=$cfg(run_analysis_holdled)\n"
        $w insert end "Unselected analyses keep the results already stored on disk.\n\n"
        if {$cfg(analysis_ir)} {
            $w insert end "IR v2.4: "
            set miss {}
            foreach n [split [string map [list ";" ","] $cfg(analysis_ir_nodes)] ","] {
                set n [string trim $n]; if {$n eq ""} continue
                if {[findNodeRigol $currentSession $n] eq ""} { lappend miss $n }
            }
            $w insert end [expr {[llength $miss] ? "NOT compatible, missing [join $miss {, }]" : "compatible"}]
            $w insert end "\n"
        } else {
            $w insert end "IR v2.4: disabled\n"
        }
        if {$cfg(analysis_identify)} {
            $w insert end "IR identification: enabled; depends on eventi_mark_space.csv from the IR module.\n"
        } else {
            $w insert end "IR identification: disabled\n"
        }
        if {$cfg(analysis_compare)} {
            set nrig 0; foreach n $nodes { if {[findNodeRigol $currentSession $n] ne ""} { incr nrig } }
            $w insert end "Stage comparison: [expr {$nrig >= 2 ? "compatible ($nrig synchronized channels)" : "NON compatible"}]\n"
        } else {
            $w insert end "Stage comparison: disabled\n"
        }
        if {$cfg(analysis_holdled)} {
            set h [findNodeRigol $currentSession $cfg(analysis_hold_node)]
            set l [findNodeRigol $currentSession $cfg(analysis_led_node)]
            $w insert end "HOLD/LED v6: [expr {$h ne "" && $l ne "" ? "compatible" : "NOT compatible: requires $cfg(analysis_hold_node) + $cfg(analysis_led_node)"}]\n"
        } else {
            $w insert end "HOLD/LED v6: disabled\n"
        }
        set curDisp [expr {[info exists ::env(DISPLAY)] ? $::env(DISPLAY) : "<not set>"}]
        set chosenDisp [expr {[string trim $cfg(graphics_display)] ne "" ? $cfg(graphics_display) : "<inherit/none>"}]
        $w insert end "\nGraphics: mode=$cfg(graphics_mode), toolkit=$cfg(graphics_toolkit), visible=$cfg(graphics_visible)\n"
        $w insert end "Current GUI DISPLAY: $curDisp\nConfigured DISPLAY: $chosenDisp\n"
    }
    $w configure -state disabled
}

proc ::GX::refreshAnalysisStatus {} { ::GX::refreshAnalysisStatus_v050 }
