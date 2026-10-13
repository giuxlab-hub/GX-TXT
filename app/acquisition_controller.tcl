# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::chooseInput_v087_before_workspace_profiles {} {
    variable cfg
    set p [tk_getOpenFile -title "Acquisition CSV" -filetypes {{{CSV} {.csv}} {{All files} *}}]
    if {$p eq ""} return
    set cfg(input_csv) [file normalize $p]
    if {$cfg(output_root) eq ""} {
        set cfg(output_root) [file join [file dirname $cfg(input_csv)] GXTXT_sessions]
    }
    catch {::GX::refreshCsvPreview}
}

proc ::GX::chooseInput {} {
    return [::GX::chooseInput_v087_before_workspace_profiles]
}

proc ::GX::chooseOutput_v087_before_workspace_profiles {} {
    variable cfg
    set p [tk_chooseDirectory -title "Session root folder"]
    if {$p ne ""} { set cfg(output_root) [file normalize $p] }
}

proc ::GX::chooseWorker {} {
    variable cfg
    set p [tk_getOpenFile -title "Worker Octave" -filetypes {{{GNU Octave} {.m}} {{All files} *}}]
    if {$p ne ""} { set cfg(worker_file) [file normalize $p] }
}

proc ::GX::saveManifestDialog_v050 {} {
    variable cfg
    if {[catch {channelSpec} err]} { tk_messageBox -icon error -message $err; return }
    set p [tk_getSaveFile -title "Export configuration manifest" -defaultextension .ini -filetypes {{{Manifest INI} {.ini}} {{All files} *}}]
    if {$p eq ""} return
    if {[catch {writeManifest $p} err]} { tk_messageBox -icon error -message $err }
}

proc ::GX::saveManifestDialog {} { ::GX::saveManifestDialog_v050 }

proc ::GX::loadManifestDialog_v087_before_workspace_profiles {} {
    set p [tk_getOpenFile -title "Load configuration manifest only" -filetypes {{{Manifest INI} {.ini}} {{All files} *}}]
    if {$p eq ""} return
    if {[catch {loadManifest $p} err]} { tk_messageBox -icon error -message $err; return }
    catch {::GX::refreshCsvPreview}
    catch {::GX::refreshManifestPreview}
    catch {::GX::refreshModuleCatalog}
    catch {::GX::refreshCustomCompareTree}
    catch {::GX::guiLog "Manifest loaded: $p"}
    catch {::GX::guiLog "Current runtime preserved: worker=$::GX::cfg(worker_file)"}
    catch {::GX::setStatus "Manifest loaded"}
}

proc ::GX::csvDelimiterChar {} {
    variable cfg
    if {$cfg(delimiter) eq "tab"} { return "\t" }
    return $cfg(delimiter)
}

proc ::GX::applyDetectedCsvLayout_v050 {} {
    variable cfg
    set p [string trim $cfg(input_csv)]
    if {$p eq "" || ![file isfile $p]} {
        tk_messageBox -icon error -title "GX-TXT" -message "Select a valid CSV first."
        return
    }
    set delim [csvDelimiterChar]
    set nhead $cfg(header_lines)
    if {![string is integer -strict $nhead] || $nhead < 0} { set nhead 0 }
    if {[catch {
        set fd [open $p r]
        fconfigure $fd -encoding utf-8 -translation auto
        for {set i 0} {$i < $nhead} {incr i} {
            if {[gets $fd _line] < 0} { error "The file ends within the header rows." }
        }
        set first ""
        while {[gets $fd line] >= 0} {
            if {[string trim $line] ne ""} { set first $line; break }
        }
        close $fd
        if {$first eq ""} { error "No data rows found." }
        set raw [split $first $delim]
        set trailing 0
        set tmp $raw
        while {[llength $tmp] > 0 && [string trim [lindex $tmp end]] eq ""} {
            incr trailing
            set tmp [lrange $tmp 0 end-1]
        }
        set cfg(raw_fields) [llength $raw]
        set cfg(drop_trailing_fields) $trailing
    } err]} {
        tk_messageBox -icon error -title "GX-TXT" -message $err
        return
    }
    refreshCsvPreview
    refreshManifestPreview
}

proc ::GX::refreshCsvPreview_v050 {} {
    variable cfg
    variable ui
    if {![info exists ui(preview)] || ![winfo exists $ui(preview)]} return
    set w $ui(preview)
    $w configure -state normal
    $w delete 1.0 end
    set p [string trim $cfg(input_csv)]
    if {$p eq "" || ![file isfile $p]} {
        $w insert end "Select a valid CSV file.\n"
        $w configure -state disabled
        return
    }
    set delim [csvDelimiterChar]
    set nhead $cfg(header_lines)
    if {![string is integer -strict $nhead] || $nhead < 0} { set nhead 0 }
    set nsamp $cfg(preview_lines)
    if {![string is integer -strict $nsamp] || $nsamp < 1} { set nsamp 8 }
    if {[catch {
        set fd [open $p r]
        fconfigure $fd -encoding utf-8 -translation auto
        set lines {}
        set max [expr {$nhead + $nsamp}]
        for {set i 1} {$i <= $max && [gets $fd line] >= 0} {incr i} { lappend lines $line }
        close $fd
    } err]} {
        $w insert end "Error lettura: $err\n"
        $w configure -state disabled
        return
    }
    $w insert end "FILE: $p\n"
    $w insert end "Size: [file size $p] bytes\n"
    $w insert end "Parser: $cfg(parser)   Delimitatore: [expr {$cfg(delimiter) eq "tab" ? "TAB" : $cfg(delimiter)}]\n"
    $w insert end "Configured header rows: $nhead\n\n"
    $w insert end "=== RAW ROWS ===\n"
    set i 0
    foreach line $lines {
        incr i
        set tag [expr {$i <= $nhead ? "HEADER" : "DATA"}]
        $w insert end [format "%s %d: %s\n" $tag $i $line]
    }
    if {[llength $lines] > $nhead} {
        set first [lindex $lines $nhead]
        set rawFields [split $first $delim]
        set fields $rawFields
        set trailingEmpty 0
        while {[llength $fields] > 0 && [string trim [lindex $fields end]] eq ""} {
            set fields [lrange $fields 0 end-1]
            incr trailingEmpty
        }
        $w insert end "\n=== STRUTTURA RILEVATA / STRUTTURA USATA ===\n"
        $w insert end "Raw fields detected in row: [llength $rawFields]\n"
        $w insert end "Trailing empty fields detected: $trailingEmpty\n"
        set configuredRaw $cfg(raw_fields)
        if {![string is integer -strict $configuredRaw] || $configuredRaw <= 0} { set configuredRaw [llength $rawFields]; set rawMode "AUTO" } else { set rawMode "MANUALE" }
        set configuredDrop $cfg(drop_trailing_fields)
        if {![string is integer -strict $configuredDrop] || $configuredDrop < 0} { set configuredDrop 0 }
        set configuredData [expr {$configuredRaw - $configuredDrop}]
        $w insert end "CONFIGURED raw fields per record: $configuredRaw ($rawMode)\n"
        $w insert end "CONFIGURED trailing fields to ignore: $configuredDrop\n"
        $w insert end "Colonne dati che il worker userà: $configuredData\n"
        if {$configuredRaw != [llength $rawFields] || $configuredDrop != $trailingEmpty} {
            $w insert end "ATTENZIONE: configurazione manuale diversa dalla struttura rilevata. È consentito, ma va verificato intenzionalmente.\n"
        }
        set displayFields $rawFields
        if {$configuredDrop > 0 && $configuredDrop < [llength $displayFields]} { set fields [lrange $displayFields 0 end-$configuredDrop] } else { set fields $displayFields }
        $w insert end "\n=== COLONNE CHE VERRANNO USATE ===\n"
        $w insert end "Colonne dati effettive: [llength $fields]\n"
        set c 0
        foreach v $fields { incr c; $w insert end [format "Column %2d = %s\n" $c [string trim $v]] }

        if {$cfg(parser) eq "rigol_ds1000z" && $nhead >= 2 && [llength $lines] >= 2} {
            set h1 [split [lindex $lines 0] $delim]
            set h2 [split [lindex $lines 1] $delim]
            $w insert end "\n=== RIGOL HEADER INTERPRETATION ===\n"
            set maxh [expr {min([llength $h1],[llength $h2])}]
            set startVal ""
            set incrVal ""
            for {set j 0} {$j < $maxh} {incr j} {
                set a [string trim [lindex $h1 $j]]
                set b [string trim [lindex $h2 $j]]
                if {$a eq "" && $b eq ""} continue
                if {$a eq "Start"} { set startVal $b }
                if {$a eq "Increment"} { set incrVal $b }
                if {$j < [llength $fields]} {
                    $w insert end [format "C%-2d  %-12s  %s\n" [expr {$j+1}] $a $b]
                } elseif {$a ne ""} {
                    $w insert end [format "META %-12s  %s\n" $a $b]
                }
            }
            if {$startVal ne ""} { $w insert end "Start = $startVal s\n" }
            if {$incrVal ne ""} {
                $w insert end "Increment = $incrVal s\n"
                if {![catch {expr {1.0/double($incrVal)}} fs]} {
                    $w insert end [format "Fs = %.12g Sa/s\n" $fs]
                }
            }
        }

        $w insert end "\n=== MAPPING CONFIGURATO ===\n"
        variable ch
        for {set ci 1} {$ci <= 8} {incr ci} {
            if {!$ch($ci,enabled)} continue
            $w insert end [format "CSV C%-2s -> %-4s -> %s\n" $ch($ci,column) $ch($ci,scope) $ch($ci,name)]
        }

        $w insert end "\n=== ESTRATTO TABELLARE ===\n"
        set heads {}
        for {set c 1} {$c <= [llength $fields]} {incr c} { lappend heads [format "C%-2d" $c] }
        $w insert end "[join $heads "\t"]\n"
        foreach line [lrange $lines $nhead end] {
            set row [split $line $delim]
            while {[llength $row] > [llength $fields]} { set row [lrange $row 0 end-1] }
            $w insert end "[join $row "\t"]\n"
        }
    }
    $w insert end "\nNOTE: column numbering is 1-based. Reading uses the Raw fields per record and Trailing fields to ignore parameters; the preview shows them before the worker starts. Start and Increment are header metadata, not sample columns.\n"
    $w configure -state disabled
}

proc ::GX::refreshManifestPreview {} {
    variable ui
    if {![info exists ui(manifest)] || ![winfo exists $ui(manifest)]} return
    set w $ui(manifest)
    $w configure -state normal
    $w delete 1.0 end
    $w insert end [manifestString]
    $w configure -state disabled
}

proc ::GX::refreshResults_v060_legacy {} {
    variable ui
    variable currentSession
    if {![info exists ui(results)] || ![winfo exists $ui(results)]} return
    set w $ui(results)
    $w configure -state normal
    $w delete 1.0 end
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        $w insert end "No current session. Run the pipeline to display results.\n"
        $w configure -state disabled
        return
    }
    set cdir [file join $currentSession channels]
    $w insert end "SESSION: $currentSession\n\n"
    foreach {title fname} {
        "IMPORT RESULT" import_result.ini
        "CHANNEL STATISTICS" summary.tsv
    } {
        set path [file join $cdir $fname]
        $w insert end "=== $title ===\n"
        if {[file isfile $path]} {
            if {[catch {
                set fd [open $path r]
                fconfigure $fd -encoding utf-8 -translation auto
                set txt [read $fd]
                close $fd
            } err]} {
                $w insert end "Error lettura $fname: $err\n\n"
            } else {
                $w insert end "$txt\n"
            }
        } else {
            $w insert end "$fname unavailable.\n\n"
        }
    }
    $w insert end "=== CHANNEL FILES ===\n"
    if {[file isdirectory $cdir]} {
        set files [lsort [glob -nocomplain -directory $cdir *]]
        foreach f $files {
            if {[file isfile $f]} {
                $w insert end [format "%-42s %12d byte\n" [file tail $f] [file size $f]]
            }
        }
    }
    set adir [file join $currentSession analysis]
    $w insert end "\n=== ANALYSIS OUTPUT ===\n"
    if {[file isdirectory $adir]} {
        foreach f [walkFiles $adir] {
            $w insert end [format "%-70s %12d byte\n" [string range $f [expr {[string length $adir]+1}] end] [file size $f]]
        }
    } else {
        $w insert end "No analysis has been run.\n"
    }
    $w configure -state disabled
}

proc ::GX::refreshResults {} { ::GX::refreshResults_v060_legacy }

proc ::GX::onNotebookChanged_v089_before_session_files {nb} {
    set tab [$nb select]
    if {$tab eq ".top.nb.preview"} { refreshCsvPreview }
    if {$tab eq ".top.nb.modules"} { refreshModuleCatalog }
    if {$tab eq ".top.nb.analysis"} { catch {rebuildNativeAnalysisGui}; refreshAnalysisStatus }
    if {$tab eq ".top.nb.graphs"} { refreshGraphs }
    if {$tab eq ".top.nb.print"} { discoverPrinters }
    if {$tab eq ".top.nb.manifest"} { refreshManifestPreview }
    if {$tab eq ".top.nb.results"} { refreshResults }
}
