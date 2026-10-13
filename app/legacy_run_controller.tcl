# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::guiLog {msg} {
    variable ui
    if {[info exists ui(log)] && [winfo exists $ui(log)]} {
        $ui(log) configure -state normal
        $ui(log) insert end "$msg\n"
        $ui(log) see end
        $ui(log) configure -state disabled
        update idletasks
    }
}

proc ::GX::copyTextWidget {w {what "Testo"}} {
    variable ui
    if {![winfo exists $w]} return
    set txt [$w get 1.0 "end-1c"]
    clipboard clear
    clipboard append -- $txt
    update idletasks
    setStatus "$what copiato negli appunti"
}

proc ::GX::setStatus {text {progress ""}} {
    variable ui
    if {[info exists ui(status)]} { set ui(status) $text }
    if {$progress ne "" && [info exists ui(progress)] && [winfo exists $ui(progress)]} {
        $ui(progress) configure -value $progress
    }
}

proc ::GX::startAsync_v050 {} {
    variable cfg
    variable pipe
    variable currentSession
    variable ui
    variable runAllPending
    if {$pipe ne ""} { return }
    if {[catch {validate} err]} {
        set runAllPending 0
        tk_messageBox -icon error -title "GX-TXT" -message $err
        return
    }
    if {[catch {
        set session [makeSession]
        prepareRawReference $session
        set manifest [file join $session metadata manifest.ini]
        writeManifest $manifest
        set cmd [buildWorkerCommand $session]
        set logPath [file join $session logs pipeline.log]
        set ui(logfile) [open $logPath w]
        fconfigure $ui(logfile) -encoding utf-8 -translation lf -buffering line
        guiLog "Session: $session"
        guiLog "Manifest: $manifest"
        guiLog "Worker effettivamente usato: $cfg(worker_file)"
        guiLog "Avvio worker Octave..."
        puts $ui(logfile) "Session: $session"
        puts $ui(logfile) "Command: $cmd"

        set pipeline [concat | $cmd [list 2>@1]]
        set pipe [open $pipeline r]
        set ::GX::pipePids [pid $pipe]
        fconfigure $pipe -blocking 0 -buffering line -encoding utf-8
        fileevent $pipe readable [list ::GX::onPipeReadable $pipe]
        setStatus "Elaborazione in corso" 2
        $ui(startButton) configure -state disabled
        if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state disabled }
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state disabled }
        $ui(stopButton) configure -state normal
    } err opts]} {
        if {[info exists ui(logfile)] && $ui(logfile) ne ""} { catch {close $ui(logfile)}; set ui(logfile) "" }
        set pipe ""
        set runAllPending 0
        if {[info exists ui(startButton)]} { $ui(startButton) configure -state normal }
        if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
        if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state disabled }
        tk_messageBox -icon error -title "GX-TXT" -message $err
    }
}

proc ::GX::onPipeReadable_v052_native {p} {
    variable pipe
    variable ui
    variable currentSession
    if {$p ne $pipe} return

    while {[gets $p line] >= 0} {
        guiLog $line
        if {[info exists ui(logfile)] && $ui(logfile) ne ""} { puts $ui(logfile) $line }
        if {[regexp {^\[STAGE ([0-9]+)/([0-9]+)\]} $line -> n total]} {
            set pct [expr {5.0 + 90.0 * $n / $total}]
            setStatus $line $pct
        }
    }

    if {[eof $p]} {
        fileevent $p readable {}
        set ok 1
        set errtxt ""
        if {[catch {close $p} err opts]} {
            set ok 0
            set errtxt $err
        }
        set pipe ""
        if {[info exists ui(logfile)] && $ui(logfile) ne ""} { catch {close $ui(logfile)}; set ui(logfile) "" }
        $ui(startButton) configure -state normal
        if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
        $ui(stopButton) configure -state disabled
        if {$ok} {
            guiLog "Pipeline completed."
            setStatus "Import completed" 100
            catch {::GX::refreshResults}
            catch {::GX::refreshAnalysisStatus}
            catch {::GX::refreshGraphs}
            catch {::GX::runPerChannelHooks $currentSession}
            variable runAllPending
            if {$runAllPending} {
                set runAllPending 0
                guiLog "RUN ALL: import completed, starting PHASE 2."
                after 100 ::GX::startAnalysis
            } else {
                tk_messageBox -icon info -title "GX-TXT" -message "Import completed.\n\n$currentSession"
            }
        } else {
            variable runAllPending
            set runAllPending 0
            guiLog "ERROR: $errtxt"
            setStatus "Error" 0
            tk_messageBox -icon error -title "GX-TXT" -message "Worker finished with an error.\n\n$errtxt"
        }
    }
}

proc ::GX::stopAsync {} {
    variable pipe
    variable pipePids
    variable ui
    if {$pipe eq ""} return
    guiLog "Richiesta interruzione..."
    fileevent $pipe readable {}
    foreach p $pipePids { catch {exec kill -TERM $p} }
    after 200
    catch {close $pipe}
    set pipe ""
    set pipePids {}
    if {[info exists ui(logfile)] && $ui(logfile) ne ""} { catch {close $ui(logfile)}; set ui(logfile) "" }
    variable runAllPending
    set runAllPending 0
    $ui(startButton) configure -state normal
    if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
    if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
    $ui(stopButton) configure -state disabled
    setStatus "Interrupted" 0
    guiLog "Worker interrupted. Any .part files are incomplete and can be deleted."
}

proc ::GX::startAll {} {
    variable runAllPending
    variable pipe
    variable analysisPipe
    if {$pipe ne "" || $analysisPipe ne ""} return
    set runAllPending 1
    guiLog "RUN ALL: starting PHASE 1; PHASE 2 will start only if import completes successfully."
    startAsync
}

proc ::GX::stopCurrent_v089_before_acq_async {} {
    variable pipe
    variable analysisPipe
    if {$pipe ne ""} {
        stopAsync
    } elseif {$analysisPipe ne ""} {
        stopAnalysis
    }
}

proc ::GX::stopCurrent {} { ::GX::stopCurrent_v089_before_acq_async }

proc ::GX::runPerChannelHooks {session} {
    variable cfg
    variable ch
    set templ [string trim $cfg(post_per_channel)]
    if {$templ eq ""} return
    for {set i 1} {$i <= 8} {incr i} {
        if {!$ch($i,enabled)} continue
        set name [sanitize $ch($i,name)]
        if {$cfg(make_rigol_split)} {
            set f [file join $session channels "${name}_rigol.csv"]
        } elseif {$cfg(make_canonical_split)} {
            set f [file join $session channels "${name}_canonical.csv"]
        } else {
            continue
        }
        if {![file exists $f]} continue
        set cmd [string map [list \
            "{FILE}" $f \
            "{NAME}" $ch($i,name) \
            "{SCOPE}" $ch($i,scope) \
            "{SESSION}" $session \
            "{MANIFEST}" [file join $session metadata manifest.ini]] $templ]
        guiLog "HOOK $ch($i,name): $cmd"
        if {[catch {exec /bin/sh -lc $cmd 2>@1} out]} {
            guiLog "HOOK ERROR $ch($i,name): $out"
        } elseif {$out ne ""} {
            guiLog $out
        }
    }
}
