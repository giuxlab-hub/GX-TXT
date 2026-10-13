# GX-TXT Dataset Inspection / Variable Mapping API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Additive v0.8.6 framework layer.  It makes multi-dataset import inspectable
# before and after canonicalization, without changing the Scientific Analysis
# semantics.  Original CSV files remain immutable; aliases are applied only to
# the canonical dataset created by acq.generic_csv.

namespace eval ::GX {
    variable datasetInspectionApiVersion 1
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    variable variableDatasetChoice ""
    unset -nocomplain ::GX::csvPreviewDatasetChoice
    namespace upvar ::GX variableDatasetChoice csvPreviewDatasetChoice
    variable csvPreviewDatasetChoice ""
    variable inspectVar
    variable inspectVarCount 0
}

proc ::GX::datasetInspectionVarFields {} {
    return {enabled source_column original_header canonical unit semantic_role instrument_id instrument_channel}
}

proc ::GX::genericCsvBatchClearVariables {row} {
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    foreach k [array names genericCsvBatchVar "$row,*,*"] { unset genericCsvBatchVar($k) }
    catch {unset genericCsvBatchVarCount($row)}
}

proc ::GX::genericCsvBatchEnsureVariables_v088_before_acquisition_handler_batch {row {force 0}} {
    variable genericCsvBatch
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    if {!$force && [info exists genericCsvBatchVarCount($row)] && $genericCsvBatchVarCount($row) > 0} {
        return $genericCsvBatchVarCount($row)
    }
    set p [expr {[info exists genericCsvBatch($row,path)] ? [string trim $genericCsvBatch($row,path)] : ""}]
    if {$p eq "" || ![file isfile $p]} { return 0 }
    set d [expr {[info exists genericCsvBatch($row,delimiter)] ? $genericCsvBatch($row,delimiter) : "auto"}]
    set h [expr {[info exists genericCsvBatch($row,header_rows)] ? $genericCsvBatch($row,header_rows) : 1}]
    if {![string is integer -strict $h] || $h < 1} { set h 1 }
    set headers [headersFromCsv $p $d $h]
    genericCsvBatchClearVariables $row
    set j 0
    foreach raw $headers {
        incr j
        set name [string trim $raw]
        if {$name eq ""} { set name "C$j" }
        foreach {f v} [list enabled 1 source_column $j original_header $name canonical $name unit "" semantic_role "" instrument_id "" instrument_channel ""] {
            set genericCsvBatchVar($row,$j,$f) $v
        }
    }
    set genericCsvBatchVarCount($row) $j
    return $j
}
proc ::GX::genericCsvBatchEnsureVariables {row {force 0}} {
    return [::GX::genericCsvBatchEnsureVariables_v088_before_acquisition_handler_batch $row $force]
}

proc ::GX::genericCsvBatchVariableNames {row} {
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    set out {}
    if {![info exists genericCsvBatchVarCount($row)]} { return $out }
    for {set j 1} {$j <= $genericCsvBatchVarCount($row)} {incr j} {
        if {![info exists genericCsvBatchVar($row,$j,enabled)] || !$genericCsvBatchVar($row,$j,enabled)} continue
        set n [string trim $genericCsvBatchVar($row,$j,canonical)]
        if {$n ne ""} { lappend out $n }
    }
    return $out
}

proc ::GX::genericCsvBatchValidateVariables {row} {
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    if {[genericCsvBatchEnsureVariables $row] <= 0} { error "Batch row $row: no variables could be read from the configured CSV header." }
    set seen {}
    for {set j 1} {$j <= $genericCsvBatchVarCount($row)} {incr j} {
        if {!$genericCsvBatchVar($row,$j,enabled)} continue
        set c [string trim $genericCsvBatchVar($row,$j,source_column)]
        set n [string trim $genericCsvBatchVar($row,$j,canonical)]
        if {![string is integer -strict $c] || $c < 1} { error "Batch row $row variable $j: source column must be an integer >= 1." }
        if {$n eq ""} { error "Batch row $row variable $j: canonical variable name is required." }
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $n]} { error "Batch row $row variable '$n': invalid canonical name." }
        if {[lsearch -exact $seen $n] >= 0} { error "Batch row $row: duplicate canonical variable '$n'." }
        lappend seen $n
    }
    if {![llength $seen]} { error "Batch row $row: enable at least one variable." }
}

proc ::GX::datasetInspectionPendingChoice {row} {
    variable genericCsvBatch
    set id [expr {[info exists genericCsvBatch($row,dataset_id)] ? [string trim $genericCsvBatch($row,dataset_id)] : "dataset.$row"}]
    return "Pending: $id"
}

proc ::GX::datasetInspectionImportedChoice {id} { return "Imported: $id" }
proc ::GX::datasetInspectionSingleChoice {} { return "Single-file input" }

proc ::GX::datasetInspectionChoices {} {
    variable genericCsvBatchCount
    variable genericCsvBatch
    variable currentSession
    set out {}
    set imported {}
    lappend out [datasetInspectionSingleChoice]
    if {$currentSession ne "" && [file isdirectory $currentSession]} {
        catch {loadDatasetRegistry $currentSession}
        set imported [datasetRegistryIds]
    }
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        if {![info exists genericCsvBatch($i,path)]} continue
        set id [expr {[info exists genericCsvBatch($i,dataset_id)] ? [string trim $genericCsvBatch($i,dataset_id)] : ""}]
        if {$id ne "" && [lsearch -exact $imported $id] >= 0} continue
        lappend out [datasetInspectionPendingChoice $i]
    }
    foreach id $imported { lappend out [datasetInspectionImportedChoice $id] }
    return $out
}

proc ::GX::datasetInspectionParseChoice {choice} {
    if {$choice eq [datasetInspectionSingleChoice]} { return [list single ""] }
    if {[string match "Pending: *" $choice]} {
        set id [string range $choice 9 end]
        variable genericCsvBatchCount
        variable genericCsvBatch
        for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
            if {[info exists genericCsvBatch($i,dataset_id)] && [string trim $genericCsvBatch($i,dataset_id)] eq $id} { return [list pending $i] }
        }
        return [list pending 0]
    }
    if {[string match "Imported: *" $choice]} { return [list imported [string range $choice 10 end]] }
    return [list single ""]
}

proc ::GX::refreshDatasetInspectionChoices {} {
    variable ui
    variable variableDatasetChoice
    variable csvPreviewDatasetChoice
    set vals [datasetInspectionChoices]
    if {$variableDatasetChoice eq "" || [lsearch -exact $vals $variableDatasetChoice] < 0} {
        set variableDatasetChoice [expr {[llength $vals] ? [lindex $vals 0] : ""}]
    }
    if {$csvPreviewDatasetChoice eq "" || [lsearch -exact $vals $csvPreviewDatasetChoice] < 0} {
        set csvPreviewDatasetChoice $variableDatasetChoice
    }
    foreach k {variableDatasetCombo csvPreviewDatasetCombo} {
        if {[info exists ui($k)] && [winfo exists $ui($k)]} { $ui($k) configure -values $vals }
    }
    catch {genericCsvBatchRefreshImportButton}
    # Pending queue changes are part of the navigator projection too.
    catch {datasetBrowserRefresh}
}

proc ::GX::datasetInspectionLoadImportedVariables_v1_before_schema {id} {
    variable inspectVar
    variable inspectVarCount
    array unset inspectVar *
    set inspectVarCount 0
    set vc [datasetField $id var_count ""]
    if {![string is integer -strict $vc] || $vc < 1} {
        set vars [splitList [datasetField $id variables [datasetField $id columns ""]]]
        if {[llength $vars] == 1 && [string first "," [lindex $vars 0]] >= 0} { set vars [split [lindex $vars 0] ,] }
        set j 0
        foreach n $vars {
            set n [string trim $n]
            if {$n eq ""} continue
            incr j
            foreach {f v} [list enabled 1 source_column $j original_header $n canonical $n unit "" semantic_role "" instrument_id "" instrument_channel ""] { set inspectVar($j,$f) $v }
        }
        set inspectVarCount $j
        return
    }
    set inspectVarCount $vc
    for {set j 1} {$j <= $vc} {incr j} {
        foreach f [datasetInspectionVarFields] {
            set def ""
            if {$f eq "enabled"} { set def 1 }
            if {$f eq "source_column"} { set def $j }
            set inspectVar($j,$f) [datasetField $id var${j}_$f $def]
        }
    }
}

proc ::GX::datasetInspectionLoadImportedVariables {id} {
    tailcall ::GX::datasetInspectionLoadImportedVariables_v1_before_schema $id
}
proc ::GX::datasetInspectionSelectedInfo {choice} {
    variable cfg
    variable moduleCfg
    variable genericCsvBatch
    variable currentSession
    lassign [datasetInspectionParseChoice $choice] mode key
    if {$mode eq "pending" && $key > 0} {
        set id [string trim $genericCsvBatch($key,dataset_id)]
        return [dict create mode pending id $id contract [genericCsvBatchResolvedContract $key] path $genericCsvBatch($key,path) delimiter $genericCsvBatch($key,delimiter) header_rows $genericCsvBatch($key,header_rows)]
    }
    if {$mode eq "imported"} {
        if {$currentSession ne ""} { catch {loadDatasetRegistry $currentSession} }
        return [dict create mode imported id $key contract [datasetField $key kind ""] path [datasetResolvePath $currentSession $key] delimiter auto header_rows 1 source_raw [datasetField $key source_raw ""]]
    }
    set contract [expr {[info exists moduleCfg(acq.generic_csv,dataset_kind)] ? $moduleCfg(acq.generic_csv,dataset_kind) : "table.generic"}]
    set delim [expr {[info exists moduleCfg(acq.generic_csv,delimiter)] ? $moduleCfg(acq.generic_csv,delimiter) : "auto"}]
    set hr [expr {[info exists moduleCfg(acq.generic_csv,header_rows)] ? $moduleCfg(acq.generic_csv,header_rows) : 1}]
    set id [expr {[info exists moduleCfg(acq.generic_csv,dataset_id)] ? $moduleCfg(acq.generic_csv,dataset_id) : ""}]
    return [dict create mode single id $id contract $contract path $cfg(input_csv) delimiter $delim header_rows $hr]
}

proc ::GX::datasetInspectionRenderMappingTable_v1_before_schema {frame mode key} {
    variable sourceVar
    variable sourceVarCount
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    variable inspectVar
    variable inspectVarCount
    variable instruments

    foreach child [winfo children $frame] { destroy $child }
    foreach {c txt} {0 Use 1 {CSV col} 2 {Original header} 3 {Canonical variable} 4 Unit 5 {Semantic role} 6 Instrument 7 {Instrument channel}} {
        ttk::label $frame.h$c -text $txt
        grid $frame.h$c -row 0 -column $c -sticky w -padx 3 -pady 2
    }
    set inst [linsert [instrumentIds] 0 ""]
    if {$mode eq "pending"} {
        genericCsvBatchEnsureVariables $key
        set count [expr {[info exists genericCsvBatchVarCount($key)] ? $genericCsvBatchVarCount($key) : 0}]
        set arr genericCsvBatchVar
        set prefix "$key,"
        set editable 1
    } elseif {$mode eq "imported"} {
        datasetInspectionLoadImportedVariables $key
        set count $inspectVarCount
        set arr inspectVar
        set prefix ""
        set editable 0
    } else {
        ensureVariablesForCurrentInput
        set count $sourceVarCount
        set arr sourceVar
        set prefix ""
        set editable 1
    }
    for {set j 1} {$j <= $count} {incr j} {
        set vbase "::GX::${arr}(${prefix}${j},"
        ttk::checkbutton $frame.e$j -variable ${vbase}enabled)
        ttk::entry $frame.c$j -textvariable ${vbase}source_column) -width 7
        ttk::entry $frame.o$j -textvariable ${vbase}original_header) -width 24 -state readonly
        ttk::entry $frame.n$j -textvariable ${vbase}canonical) -width 24
        ttk::entry $frame.u$j -textvariable ${vbase}unit) -width 10
        ttk::entry $frame.r$j -textvariable ${vbase}semantic_role) -width 16
        ttk::combobox $frame.i$j -textvariable ${vbase}instrument_id) -values $inst -width 16
        ttk::entry $frame.ic$j -textvariable ${vbase}instrument_channel) -width 14
        if {!$editable} {
            foreach w [list $frame.e$j $frame.c$j $frame.n$j $frame.u$j $frame.r$j $frame.i$j $frame.ic$j] { catch {$w state disabled} }
        } else {
            foreach w [list $frame.n$j $frame.u$j $frame.r$j $frame.ic$j] { bind $w <KeyRelease> {::GX::refreshManifestPreview} }
        }
        grid $frame.e$j -row $j -column 0 -padx 3 -pady 2
        grid $frame.c$j -row $j -column 1 -padx 3 -pady 2
        grid $frame.o$j -row $j -column 2 -padx 3 -pady 2
        grid $frame.n$j -row $j -column 3 -padx 3 -pady 2
        grid $frame.u$j -row $j -column 4 -padx 3 -pady 2
        grid $frame.r$j -row $j -column 5 -padx 3 -pady 2
        grid $frame.i$j -row $j -column 6 -padx 3 -pady 2
        grid $frame.ic$j -row $j -column 7 -padx 3 -pady 2
    }
}

proc ::GX::datasetInspectionRenderMappingTable {frame mode key} {
    tailcall ::GX::datasetInspectionRenderMappingTable_v1_before_schema $frame $mode $key
}
proc ::GX::datasetInspectionScrollRefresh {canvas} {
    if {![winfo exists $canvas]} return
    set bb [$canvas bbox all]
    if {[llength $bb] == 4} { $canvas configure -scrollregion $bb }
}

# Replace the single-source Variables workspace with a dataset-aware inspector.
proc ::GX::refreshNativeVariablesGui_v086_draft {} {
    variable ui
    variable variableDatasetChoice
    set f .top.nb.channels
    if {![winfo exists $f]} return
    destroyChildren $f
    grid columnconfigure $f 0 -weight 1
    grid rowconfigure $f 2 -weight 1

    ttk::frame $f.bar
    ttk::label $f.bar.l -text "Dataset:"
    ttk::combobox $f.bar.ds -textvariable ::GX::variableDatasetChoice -state readonly -width 42
    datasetSelectorAttach $f.bar.ds ::GX::datasetInspectionChoices
    ttk::button $f.bar.refresh -text "Refresh" -command {::GX::refreshDatasetInspectionChoices; ::GX::refreshNativeVariablesGui}
    ttk::button $f.bar.preview -text "Preview selected" -command ::GX::datasetInspectionPreviewFromVariables
    pack $f.bar.l $f.bar.ds $f.bar.refresh $f.bar.preview -side left -padx 4
    grid $f.bar -row 0 -column 0 -sticky ew -padx 5 -pady {5 2}
    set ui(variableDatasetCombo) $f.bar.ds
    refreshDatasetInspectionChoices
    bind $f.bar.ds <<ComboboxSelected>> {::GX::refreshNativeVariablesGui}

    set info [datasetInspectionSelectedInfo $variableDatasetChoice]
    set mode [dict get $info mode]
    set id [dict get $info id]
    set contract [dict get $info contract]
    set path [dict get $info path]
    set note ""
    if {$mode eq "pending"} {
        set note "PENDING IMPORT — aliases below will be written into the canonical CSV header. RAW input remains unchanged."
    } elseif {$mode eq "imported"} {
        set note "IMPORTED CANONICAL DATASET — mapping is shown for provenance. Re-import the source to change canonical variable names."
    } else {
        set note "SINGLE-FILE IMPORT — aliases below will become canonical CSV variable names."
    }
    ttk::label $f.summary -text "Dataset ID: $id    Contract: $contract    State: [string toupper $mode]\nFile: $path\n$note" -justify left -wraplength 1400
    grid $f.summary -row 1 -column 0 -sticky ew -padx 7 -pady {2 5}

    canvas $f.c -highlightthickness 0
    ttk::scrollbar $f.sy -orient vertical -command [list $f.c yview]
    ttk::scrollbar $f.sx -orient horizontal -command [list $f.c xview]
    $f.c configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
    ttk::frame $f.c.inner
    set win [$f.c create window 0 0 -anchor nw -window $f.c.inner]
    bind $f.c.inner <Configure> [list ::GX::datasetInspectionScrollRefresh $f.c]
    grid $f.c -row 2 -column 0 -sticky nsew -padx {5 0}
    grid $f.sy -row 2 -column 1 -sticky ns
    grid $f.sx -row 3 -column 0 -sticky ew -padx {5 0}
    datasetInspectionRenderMappingTable $f.c.inner $mode [expr {$mode eq "single" ? "" : $key}]
}

# The expression above needs the parsed key.  Wrap the renderer with the correct
# key while preserving the public refresh procedure name.
proc ::GX::refreshNativeVariablesGui_v1_before_schema {} {
    variable ui
    variable variableDatasetChoice
    set f .top.nb.channels
    if {![winfo exists $f]} return
    # The shell and its content containers survive Dataset activation. Only
    # schema rows inside the scrollable editor are rebound to the active data.
    if {![winfo exists $f.bar]} {
        # Replace the original acquisition-channel form only once, when the
        # Dataset shell is first installed; activation never enters this branch.
        destroyChildren $f
        foreach row {0 1 2 3 4 5 6 7} {grid rowconfigure $f $row -weight 0 -minsize 0}
        foreach column {0 1 2 3} {grid columnconfigure $f $column -weight 0 -minsize 0}
        grid columnconfigure $f 0 -weight 1
        grid rowconfigure $f 2 -weight 1
        ttk::frame $f.bar
        ttk::button $f.bar.refresh -text "Refresh" -command {::GX::refreshDatasetInspectionChoices; ::GX::refreshNativeVariablesGui}
        ttk::button $f.bar.preview -text "Preview active" -command ::GX::datasetInspectionPreviewFromVariables
        pack $f.bar.refresh $f.bar.preview -side left -padx 4
        grid $f.bar -row 0 -column 0 -sticky ew -padx 5 -pady {5 2}
        ttk::label $f.summary -justify left -wraplength 850
        grid $f.summary -row 1 -column 0 -sticky ew -padx 7 -pady {2 5}
        canvas $f.c -highlightthickness 0
        ttk::scrollbar $f.sy -orient vertical -command [list $f.c yview]
        ttk::scrollbar $f.sx -orient horizontal -command [list $f.c xview]
        $f.c configure -yscrollcommand [list $f.sy set] -xscrollcommand [list $f.sx set]
        ttk::frame $f.c.inner
        $f.c create window 0 0 -anchor nw -window $f.c.inner
        bind $f.c.inner <Configure> [list ::GX::datasetInspectionScrollRefresh $f.c]
    }
    unset -nocomplain ui(variableDatasetCombo)
    refreshDatasetInspectionChoices
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode key
    set info [datasetInspectionSelectedInfo $variableDatasetChoice]
    set id [dict get $info id]; set contract [dict get $info contract]; set path [dict get $info path]
    if {$mode eq "pending"} {
        set note "PENDING IMPORT — Original header and Canonical variable are shown side by side. Edit Canonical variable, Unit or Semantic role before Run. RAW input remains unchanged."
    } elseif {$mode eq "imported"} {
        set note "IMPORTED CANONICAL DATASET — provenance mapping is read-only. Re-import the source to change canonical variable names."
    } else {
        set note "SINGLE-FILE IMPORT — Original header and Canonical variable are shown side by side."
    }
    $f.summary configure -text "Dataset ID: $id    Contract: $contract    State: [string toupper $mode]\nFile: $path\n$note"
    datasetInspectionRenderMappingTable $f.c.inner $mode $key
}

proc ::GX::datasetInspectionPreviewFromVariables {{datasetId {}}} {
    variable variableDatasetChoice
    variable csvPreviewDatasetChoice
    set csvPreviewDatasetChoice [expr {$datasetId eq {}?$variableDatasetChoice:[datasetInspectionImportedChoice $datasetId]}]
    refreshDatasetInspectionChoices
    refreshCsvPreview
    catch {.top.nb select .top.nb.channels; .top.nb.channels.views select .top.nb.channels.views.preview}
}

proc ::GX::datasetDeleteSelectedFromGui {{targetId {}}} {
    variable currentSession
    variable variableDatasetChoice
    variable csvPreviewDatasetChoice
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode datasetId
    set deletingActive [expr {$targetId eq {}||($mode eq "imported"&&$datasetId eq $targetId)}]
    if {$targetId ne {}} {set datasetId $targetId;set mode imported}
    if {$mode ne "imported" || $datasetId eq ""} { return 0 }
    set answer [tk_messageBox -parent .top -icon warning -type yesno -default no \
        -title "Delete dataset" \
        -message "Delete dataset '$datasetId' from this session?\n\nIts canonical dataset file, structured metadata and dataset note will be removed when they are stored inside this session. The original RAW/source file and unrelated analysis resources will not be deleted."]
    if {$answer ne "yes"} { return 0 }
    if {[catch {set result [datasetDelete $currentSession $datasetId]} err]} {
        tk_messageBox -parent .top -icon error -type ok -title "Delete dataset" -message $err
        return 0
    }

    if {$deletingActive} {
        set variableDatasetChoice ""
        set csvPreviewDatasetChoice ""
        set choices [datasetInspectionChoices]
        foreach choice $choices {
            if {[lindex [datasetInspectionParseChoice $choice] 0] eq "imported"} {
                set variableDatasetChoice $choice
                break
            }
        }
        if {$variableDatasetChoice eq "" && [llength $choices]} { set variableDatasetChoice [lindex $choices 0] }
        set csvPreviewDatasetChoice $variableDatasetChoice
    }
    catch {refreshDatasetInspectionChoices}
    catch {refreshNativeVariablesGui}
    catch {refreshCsvPreview}
    catch {refreshNativeAnalysisState}
    catch {refreshResults}
    setStatus "Dataset $datasetId deleted from the current session." 100

    set cleanupErrors [dict get $result cleanup_errors]
    if {[llength $cleanupErrors]} {
        tk_messageBox -parent .top -icon warning -type ok -title "Delete dataset" \
            -message "The dataset was removed from the session registry, but some staged files could not be cleaned up:\n[join $cleanupErrors \n]"
    }
    return 1
}

proc ::GX::datasetInspectionSelectPendingPreview {row} {
    variable csvPreviewDatasetChoice
    variable genericCsvBatch
    set id [expr {[info exists genericCsvBatch($row,dataset_id)] ? [string trim $genericCsvBatch($row,dataset_id)] : ""}]
    if {[genericCsvBatchRowStatus $row] eq "Imported" && $id ne ""} {
        set csvPreviewDatasetChoice [datasetInspectionImportedChoice $id]
    } else {
        set csvPreviewDatasetChoice [datasetInspectionPendingChoice $row]
    }
    refreshDatasetInspectionChoices
    refreshCsvPreview
    catch {.top.nb select .top.nb.channels; .top.nb.channels.views select .top.nb.channels.views.preview}
}

proc ::GX::datasetInspectionSelectPendingVariables {row} {
    variable variableDatasetChoice
    variable genericCsvBatch
    set id [expr {[info exists genericCsvBatch($row,dataset_id)] ? [string trim $genericCsvBatch($row,dataset_id)] : ""}]
    if {[genericCsvBatchRowStatus $row] eq "Imported" && $id ne ""} {
        set variableDatasetChoice [datasetInspectionImportedChoice $id]
    } else {
        set variableDatasetChoice [datasetInspectionPendingChoice $row]
    }
    refreshDatasetInspectionChoices
    refreshNativeVariablesGui
    catch {.top.nb select .top.nb.channels; .top.nb.channels.views select .top.nb.channels.views.variables}
}

proc ::GX::datasetInspectionMappingRows {mode key} {
    variable sourceVar; variable sourceVarCount
    variable genericCsvBatchVar; variable genericCsvBatchVarCount
    variable inspectVar; variable inspectVarCount
    set out {}
    if {$mode eq "pending"} {
        genericCsvBatchEnsureVariables $key
        set count [expr {[info exists genericCsvBatchVarCount($key)] ? $genericCsvBatchVarCount($key) : 0}]
        for {set j 1} {$j <= $count} {incr j} {
            lappend out [list $genericCsvBatchVar($key,$j,enabled) $genericCsvBatchVar($key,$j,source_column) $genericCsvBatchVar($key,$j,original_header) $genericCsvBatchVar($key,$j,canonical) $genericCsvBatchVar($key,$j,unit) $genericCsvBatchVar($key,$j,semantic_role)]
        }
    } elseif {$mode eq "imported"} {
        datasetInspectionLoadImportedVariables $key
        for {set j 1} {$j <= $inspectVarCount} {incr j} {
            lappend out [list $inspectVar($j,enabled) $inspectVar($j,source_column) $inspectVar($j,original_header) $inspectVar($j,canonical) $inspectVar($j,unit) $inspectVar($j,semantic_role)]
        }
    } else {
        ensureVariablesForCurrentInput
        for {set j 1} {$j <= $sourceVarCount} {incr j} {
            lappend out [list $sourceVar($j,enabled) $sourceVar($j,source_column) $sourceVar($j,original_header) $sourceVar($j,canonical) $sourceVar($j,unit) $sourceVar($j,semantic_role)]
        }
    }
    return $out
}

proc ::GX::datasetInspectionRenderPreview_v089 {w choice} {
    variable cfg
    lassign [datasetInspectionParseChoice $choice] mode key
    set info [datasetInspectionSelectedInfo $choice]
    set id [dict get $info id]; set contract [dict get $info contract]; set path [dict get $info path]
    set delimiter [dict get $info delimiter]; set headerRows [dict get $info header_rows]
    $w configure -state normal; $w delete 1.0 end
    if {$path eq "" || ![file isfile $path]} {
        $w insert end "DATASET PREVIEW\n===============\nState: [string toupper $mode]\nDataset ID: $id\nContract: $contract\n\nNo readable CSV file is available for this selection.\n"
        $w configure -state disabled; return
    }
    if {[catch {set delim [csvDelimiter $path $delimiter]} err]} {
        $w insert end "Delimiter detection error: $err\n"; $w configure -state disabled; return
    }
    if {![string is integer -strict $headerRows] || $headerRows < 1} { set headerRows 1 }
    set nsamp $cfg(preview_lines); if {![string is integer -strict $nsamp] || $nsamp < 1} { set nsamp 8 }
    set lines {}
    set fd [open $path r]; fconfigure $fd -encoding utf-8 -translation auto
    set max [expr {$headerRows + $nsamp}]
    for {set i 1} {$i <= $max && [gets $fd line] >= 0} {incr i} { lappend lines $line }
    close $fd
    if {[llength $lines] < $headerRows} { $w insert end "File ends inside configured header rows.\n"; $w configure -state disabled; return }
    set header [lindex $lines [expr {$headerRows-1}]]
    set headers {}; foreach c [split $header $delim] { lappend headers [string trim $c " \t\r\n\""] }
    set mapping [datasetInspectionMappingRows $mode $key]
    set dlabel [expr {$delim eq "\t" ? "TAB" : $delim}]

    $w insert end "DATASET PREVIEW\n===============\n"
    $w insert end "State:       [string toupper $mode]\n"
    $w insert end "Dataset ID:  $id\nContract:    $contract\n"
    $w insert end "File:        $path\nSize:        [file size $path] bytes\nDelimiter:   $dlabel"
    if {$delimiter eq "auto"} { $w insert end " (auto-detected)" }
    $w insert end "\nHeader rows: $headerRows\nColumns:     [llength $headers]\nPreview data rows: [expr {[llength $lines]-$headerRows}]\n"
    if {$mode eq "imported"} {
        set raw [datasetField $id source_raw ""]
        if {$raw ne ""} { $w insert end "RAW source:   $raw\n" }
        $w insert end "Canonical SHA-256: [datasetField $id canonical_sha256 ""]\n"
    }

    $w insert end "\nVARIABLE MAP\n============\n"
    $w insert end [format "%-5s %-7s %-30s %-30s %-12s %-18s\n" "Use" "CSV#" "Original header" "Canonical variable" "Unit" "Semantic role"]
    $w insert end [string repeat "-" 112]; $w insert end "\n"
    if {[llength $mapping]} {
        foreach row $mapping {
            lassign $row en col orig canon unit role
            $w insert end [format "%-5s %-7s %-30s %-30s %-12s %-18s\n" [expr {$en ? "yes" : "no"}] $col $orig $canon $unit $role]
        }
    } else {
        set j 0; foreach h $headers { incr j; $w insert end [format "%-5s %-7s %-30s %-30s\n" yes $j $h $h] }
    }

    set expected [llength $headers]; set bad 0
    foreach line [lrange $lines $headerRows end] {
        if {[string trim $line] eq ""} continue
        if {[llength [split $line $delim]] != $expected} { incr bad }
    }
    $w insert end "\nSTRUCTURE CHECK\n===============\n"
    if {$bad} { $w insert end "WARNING: $bad sampled data row(s) have a field count different from the header ($expected).\n" } else { $w insert end "Sampled rows have a consistent field count ($expected columns).\n" }
    set names {}; foreach row $mapping { if {[lindex $row 0]} { lappend names [lindex $row 3] } }
    if {[llength $names] != [llength [lsort -unique $names]]} { $w insert end "WARNING: duplicate canonical variable names are configured.\n" }

    $w insert end "\nDATA SAMPLE\n===========\n"
    set n 0
    foreach line [lrange $lines $headerRows end] {
        incr n
        $w insert end [format "ROW %-4d %s\n" $n [join [split $line $delim] " | "]]
    }
    $w insert end "\nThe RAW file is never renamed or rewritten. Canonical aliases apply only to the canonical dataset created by GX-TXT.\n"
    $w configure -state disabled
}

proc ::GX::datasetInspectionRenderPreview {w choice} {
    return [::GX::datasetInspectionRenderPreview_v089 $w $choice]
}

proc ::GX::refreshGenericCsvPreview {} {
    variable ui
    variable csvPreviewDatasetChoice
    if {![info exists ui(preview)] || ![winfo exists $ui(preview)]} return
    refreshDatasetInspectionChoices
    datasetInspectionRenderPreview $ui(preview) $csvPreviewDatasetChoice
}

proc ::GX::buildDatasetInspectionPreviewControls {} {
    refreshDatasetInspectionChoices
}

proc ::GX::augmentStandardGui_v089_before_acq_native_gui {} {
    ::GX::augmentStandardGui_v085_before_dataset_inspection
    buildDatasetInspectionPreviewControls
    buildGenericCsvBatchCurrentImportButton
    refreshDatasetInspectionChoices
    genericCsvBatchRefreshImportButton
}

# Batch import state -----------------------------------------------------------
proc ::GX::genericCsvBatchImportedIds {} {
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return {} }
    catch {loadDatasetRegistry $currentSession}
    return [datasetRegistryIds]
}

proc ::GX::genericCsvBatchRowStatus_v09780 {row} {
    variable genericCsvBatch
    set id [expr {[info exists genericCsvBatch($row,dataset_id)] ? [string trim $genericCsvBatch($row,dataset_id)] : ""}]
    if {$id ne "" && [lsearch -exact [genericCsvBatchImportedIds] $id] >= 0} { return "Imported" }
    return "Pending"
}
proc ::GX::genericCsvBatchRowStatus {row} {
    return [::GX::genericCsvBatchRowStatus_v09780 $row]
}

proc ::GX::genericCsvBatchPendingEnabledRows_before_import_queue {} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    set imported [genericCsvBatchImportedIds]
    set out {}
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        if {![info exists genericCsvBatch($i,enabled)] || !$genericCsvBatch($i,enabled)} continue
        set id [expr {[info exists genericCsvBatch($i,dataset_id)] ? [string trim $genericCsvBatch($i,dataset_id)] : ""}]
        if {$id ne "" && [lsearch -exact $imported $id] >= 0} continue
        lappend out $i
    }
    return $out
}
proc ::GX::genericCsvBatchPendingEnabledRows {} {
    return [::GX::genericCsvBatchPendingEnabledRows_before_import_queue]
}

proc ::GX::genericCsvBatchRefreshImportButton {} {
    variable ui
    variable currentSession
    variable genericCsvBatchEnabled
    if {![info exists ui(genericBatchImportCurrentButton)] || ![winfo exists $ui(genericBatchImportCurrentButton)]} { return }
    set ok [expr {$genericCsvBatchEnabled && $currentSession ne "" && [file isdirectory $currentSession] && [llength [genericCsvBatchPendingEnabledRows]] > 0}]
    $ui(genericBatchImportCurrentButton) configure -state [expr {$ok ? "normal" : "disabled"}]
}

proc ::GX::genericCsvBatchStateChanged {} {
    catch {refreshManifestPreview}
    catch {refreshDatasetInspectionChoices}
    catch {genericCsvBatchRefreshImportButton}
}

proc ::GX::buildGenericCsvBatchCurrentImportButton {} {
    variable ui
    set b .top.nb.acq.batch.bar
    if {![winfo exists $b]} { return }
    if {![winfo exists $b.importCurrent]} {
        ttk::button $b.importCurrent -text "Import enabled pending into current session" -command ::GX::genericCsvBatchImportIntoCurrentSession
        pack $b.importCurrent -side left -padx 8
    }
    set ui(genericBatchImportCurrentButton) $b.importCurrent
    if {[winfo exists $b.enabled]} { $b.enabled configure -command ::GX::genericCsvBatchStateChanged }
    genericCsvBatchRefreshImportButton
}

# Multi-CSV row actions ---------------------------------------------------------
proc ::GX::genericCsvBatchBrowse_v087_before_workspace_profiles {i} {
    variable genericCsvBatch
    set old [expr {[info exists genericCsvBatch($i,path)] ? $genericCsvBatch($i,path) : ""}]
    ::GX::genericCsvBatchBrowse_v085_before_dataset_inspection $i
    set now [expr {[info exists genericCsvBatch($i,path)] ? $genericCsvBatch($i,path) : ""}]
    if {$now ne $old} { genericCsvBatchClearVariables $i }
    catch {refreshDatasetInspectionChoices}
}
proc ::GX::genericCsvBatchBrowse {i} {
    return [::GX::genericCsvBatchBrowse_v087_before_workspace_profiles $i]
}

proc ::GX::genericCsvBatchRemove_v089_before_group_fields {idx} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    if {$idx < 1 || $idx > $genericCsvBatchCount} return
    # Shift variable maps first because the legacy remover shifts row metadata.
    for {set i $idx} {$i < $genericCsvBatchCount} {incr i} {
        genericCsvBatchClearVariables $i
        set src [expr {$i+1}]
        if {[info exists genericCsvBatchVarCount($src)]} {
            set genericCsvBatchVarCount($i) $genericCsvBatchVarCount($src)
            for {set j 1} {$j <= $genericCsvBatchVarCount($src)} {incr j} {
                foreach f [datasetInspectionVarFields] {
                    if {[info exists genericCsvBatchVar($src,$j,$f)]} { set genericCsvBatchVar($i,$j,$f) $genericCsvBatchVar($src,$j,$f) }
                }
            }
        }
    }
    genericCsvBatchClearVariables $genericCsvBatchCount
    ::GX::genericCsvBatchRemove_v085_before_dataset_inspection $idx
    catch {refreshDatasetInspectionChoices}
}
proc ::GX::genericCsvBatchRemove {idx} {
    return [::GX::genericCsvBatchRemove_v089_before_group_fields $idx]
}

proc ::GX::genericCsvBatchClear_before_import_queue {} {
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    array unset genericCsvBatchVar *
    array unset genericCsvBatchVarCount *
    ::GX::genericCsvBatchClear_v085_before_dataset_inspection
    catch {refreshDatasetInspectionChoices}
}
proc ::GX::genericCsvBatchClear {} {
    return [::GX::genericCsvBatchClear_before_import_queue]
}

proc ::GX::genericCsvBatchRender_v088_before_acquisition_handler_batch {} {
    variable ui
    variable genericCsvBatch
    variable genericCsvBatchCount
    if {![info exists ui(genericBatchInner)] || ![winfo exists $ui(genericBatchInner)]} return
    set p $ui(genericBatchInner)
    set imported [genericCsvBatchImportedIds]
    foreach child [winfo children $p] { destroy $child }
    foreach {col txt} {0 Use 1 {CSV file} 2 {} 3 {Dataset ID} 4 Contract 5 {Other / custom contract} 6 Delimiter 7 Header 8 Status 9 Preview 10 Variables 11 {}} {
        if {$txt ne ""} { ttk::label $p.h$col -text $txt; grid $p.h$col -row 0 -column $col -sticky w -padx 3 -pady 2 }
    }
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        ttk::checkbutton $p.use$i -variable ::GX::genericCsvBatch($i,enabled) -command ::GX::genericCsvBatchStateChanged
        ttk::entry $p.path$i -textvariable ::GX::genericCsvBatch($i,path) -width 48
        ttk::button $p.browse$i -text "..." -width 3 -command [list ::GX::genericCsvBatchBrowse $i]
        ttk::entry $p.id$i -textvariable ::GX::genericCsvBatch($i,dataset_id) -width 22
        ttk::combobox $p.kind$i -textvariable ::GX::genericCsvBatch($i,contract_choice) -values [contractRegistryChoices] -state readonly -width 22
        ttk::entry $p.other$i -textvariable ::GX::genericCsvBatch($i,custom_contract) -width 24
        ttk::combobox $p.delim$i -textvariable ::GX::genericCsvBatch($i,delimiter) -values {auto comma semicolon tab} -state readonly -width 10
        ttk::spinbox $p.head$i -from 1 -to 999 -textvariable ::GX::genericCsvBatch($i,header_rows) -width 6
        set rowId [string trim $genericCsvBatch($i,dataset_id)]
        ttk::label $p.status$i -text [genericCsvBatchRowStatus $i]
        ttk::button $p.prev$i -text "Preview" -command [list ::GX::datasetInspectionSelectPendingPreview $i]
        ttk::button $p.vars$i -text "Variables" -command [list ::GX::datasetInspectionSelectPendingVariables $i]
        ttk::button $p.rm$i -text "Remove" -command [list ::GX::genericCsvBatchRemove $i]
        set ui(genericContractCombo,$i) $p.kind$i
        bind $p.kind$i <<ComboboxSelected>> [list ::GX::genericCsvBatchContractChanged $i]
        bind $p.other$i <KeyRelease> [list ::GX::refreshManifestPreview]
        bind $p.path$i <KeyRelease> [list ::GX::genericCsvBatchStateChanged]
        bind $p.id$i <KeyRelease> [list ::GX::genericCsvBatchStateChanged]
        foreach {w c} [list $p.use$i 0 $p.path$i 1 $p.browse$i 2 $p.id$i 3 $p.kind$i 4 $p.other$i 5 $p.delim$i 6 $p.head$i 7 $p.status$i 8 $p.prev$i 9 $p.vars$i 10 $p.rm$i 11] {
            grid $w -row $i -column $c -padx 3 -pady 2 -sticky [expr {$c == 1 ? "ew" : ""}]
        }
    }
    acquisitionQueueLayout $p
    update idletasks
    genericCsvBatchScrollRefresh
    catch {refreshDatasetInspectionChoices}
    catch {genericCsvBatchRefreshImportButton}
}
proc ::GX::genericCsvBatchRender {} {
    return [::GX::genericCsvBatchRender_v088_before_acquisition_handler_batch]
}

# Validate and import the per-dataset variable map.  No scientific alignment is
# performed here; this is canonicalization only.
proc ::GX::genericCsvBatchValidate_v09780 {} {
    ::GX::genericCsvBatchValidate_v085_before_dataset_inspection
    variable genericCsvBatchEnabled
    if {!$genericCsvBatchEnabled} return
    foreach i [genericCsvBatchEnabledRows] { genericCsvBatchValidateVariables $i }
}
proc ::GX::genericCsvBatchValidate {} {
    return [::GX::genericCsvBatchValidate_v09780]
}

proc ::GX::genericCsvBatchValidateSelectedRows_v088_before_acquisition_handler_batch {rows} {
    variable genericCsvBatch
    set ids {}
    foreach i $rows {
        set path [string trim $genericCsvBatch($i,path)]
        if {$path eq "" || ![file isfile $path]} { error "Batch row $i: select an existing CSV file." }
        set id [string trim $genericCsvBatch($i,dataset_id)]
        if {$id eq "" || ![regexp {^[A-Za-z0-9_.-]+$} $id]} { error "Batch row $i: Dataset ID may contain only letters, digits, '.', '_' and '-'." }
        if {[lsearch -exact $ids $id] >= 0} { error "Batch row $i: duplicate Dataset ID '$id'." }
        lappend ids $id
        set kind [genericCsvBatchResolvedContract $i]
        if {$kind eq ""} { error "Batch row $i: choose a dataset contract or enter Other/custom contract." }
        if {[regexp {[\r\n]} $kind]} { error "Batch row $i: dataset contract must be a single line." }
        set hr $genericCsvBatch($i,header_rows)
        if {![string is integer -strict $hr] || $hr < 1} { error "Batch row $i: Header rows must be an integer >= 1." }
        if {$genericCsvBatch($i,delimiter) ni {auto comma semicolon tab , ;}} { error "Batch row $i: unsupported delimiter '$genericCsvBatch($i,delimiter)'." }
        genericCsvBatchValidateVariables $i
    }
}
proc ::GX::genericCsvBatchValidateSelectedRows {rows} {
    return [::GX::genericCsvBatchValidateSelectedRows_v088_before_acquisition_handler_batch $rows]
}

proc ::GX::genericCsvBatchImportRowToSession_v088_before_acquisition_handler_batch {session i} {
    variable genericCsvBatch
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    variable scriptDir
    set src [file normalize $genericCsvBatch($i,path)]
    set id [string trim $genericCsvBatch($i,dataset_id)]
    set kind [genericCsvBatchResolvedContract $i]
    set rawRel [file join raw $id [file tail $src]]
    set rawDst [file join $session $rawRel]
    file mkdir [file dirname $rawDst]
    file copy -force -- $src $rawDst
    set srcHash [sha256File $rawDst]
    set dataRel [file join datasets "${id}.csv"]
    set dataDst [file join $session $dataRel]
    set setting $genericCsvBatch($i,delimiter)
    set delim [csvDelimiter $rawDst $setting]
    set token [expr {$delim eq "," ? "comma" : ($delim eq ";" ? "semicolon" : "tab")}]
    set helper [file join $scriptDir plugins modules acq.generic_csv runtime canonicalize_csv.py]
    set cmd [list [runtimeToolRequired python] $helper --input $rawDst --output $dataDst --delimiter $token --header-rows $genericCsvBatch($i,header_rows)]
    set vars {}; set varMeta {}
    for {set j 1} {$j <= $genericCsvBatchVarCount($i)} {incr j} {
        foreach f [datasetInspectionVarFields] { lappend varMeta var${j}_$f $genericCsvBatchVar($i,$j,$f) }
        if {!$genericCsvBatchVar($i,$j,enabled)} continue
        set col $genericCsvBatchVar($i,$j,source_column)
        set canon [string trim $genericCsvBatchVar($i,$j,canonical)]
        lappend cmd --map "$col=$canon"
        lappend vars $canon
    }
    if {[catch {exec {*}$cmd 2>@1} out opts]} { error "Batch row $i ($id): canonical CSV conversion failed: $out" }
    set canonHash [sha256File $dataDst]
    set fields [list kind $kind format csv path $dataRel columns [join $vars ,] variables [join $vars ,] var_count $genericCsvBatchVarCount($i) source_header_rows $genericCsvBatch($i,header_rows) source_delimiter $token canonical_delimiter $token source_module acq.generic_csv source_raw $rawRel source_sha256 $srcHash canonical_sha256 $canonHash created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] immutable 0 notes "Canonical CSV generated by GX-TXT v0.8.7 multi-CSV variable mapping"]
    set fields [concat $fields $varMeta]
    datasetRegister $id $fields
    return "Dataset: $id | contract: $kind | variables: [join $vars ,] | source: $src"
}

proc ::GX::genericCsvBatchImportRowToSession {session i} {
    return [::GX::genericCsvBatchImportRowToSession_v088_before_acquisition_handler_batch $session $i]
}

proc ::GX::genericCsvBatchImportSync_v09780 {} {
    variable cfg
    variable genericCsvBatch
    variable currentSession
    genericCsvBatchValidate
    set cfg(session_mode) "analysis_only"
    set rows [genericCsvBatchEnabledRows]
    if {[llength $rows]} { set cfg(input_csv) $genericCsvBatch([lindex $rows 0],path) }
    set session [makeSession]
    file mkdir [file join $session datasets]
    datasetRegistryClear
    set logLines {}
    foreach i $rows { lappend logLines [genericCsvBatchImportRowToSession $session $i] }
    saveDatasetRegistry $session
    writeManifest [file join $session metadata manifest.ini]
    set log [open [file join $session logs pipeline.log] w]; fconfigure $log -encoding utf-8 -translation lf
    puts $log "Standard Module API v1 / Manifest format 2"
    puts $log "Dataset Inspection / Variable Mapping API v1"
    puts $log "Acquisition module: acq.generic_csv"
    puts $log "Mode: multi_csv_batch"
    puts $log "Dataset count: [llength $rows]"
    foreach line $logLines { puts $log $line }
    close $log
    set currentSession $session
    if {[llength $rows]} {
        set firstId [string trim $genericCsvBatch([lindex $rows 0],dataset_id)]
        set ::GX::variableDatasetChoice [datasetInspectionImportedChoice $firstId]
        set ::GX::csvPreviewDatasetChoice [datasetInspectionImportedChoice $firstId]
    }
    catch {genericCsvBatchRender}; catch {refreshDatasetInspectionChoices}; catch {genericCsvBatchRefreshImportButton}
    return $session
}
proc ::GX::genericCsvBatchImportSync {} {
    return [::GX::genericCsvBatchImportSync_v09780]
}

proc ::GX::genericCsvBatchImportIntoCurrentSessionSync_v09780 {} {
    variable genericCsvBatchEnabled
    variable currentSession
    variable cfg
    if {!$genericCsvBatchEnabled} { error "Enable 'Use batch table' before importing batch datasets." }
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "Create or open a session before importing additional batch datasets." }
    loadDatasetRegistry $currentSession
    set rows [genericCsvBatchPendingEnabledRows]
    if {![llength $rows]} { return $currentSession }
    genericCsvBatchValidateSelectedRows $rows
    file mkdir [file join $currentSession datasets]
    set logLines {}
    foreach i $rows { lappend logLines [genericCsvBatchImportRowToSession $currentSession $i] }
    saveDatasetRegistry $currentSession
    writeManifest [file join $currentSession metadata manifest.ini]
    set logPath [file join $currentSession logs pipeline.log]
    file mkdir [file dirname $logPath]
    set log [open $logPath a]; fconfigure $log -encoding utf-8 -translation lf
    puts $log ""
    puts $log "Additional multi-CSV import into current session"
    puts $log "Dataset count: [llength $rows]"
    foreach line $logLines { puts $log $line }
    close $log
    set firstId [string trim $::GX::genericCsvBatch([lindex $rows 0],dataset_id)]
    set ::GX::variableDatasetChoice [datasetInspectionImportedChoice $firstId]
    set ::GX::csvPreviewDatasetChoice [datasetInspectionImportedChoice $firstId]
    catch {genericCsvBatchRender}; catch {refreshDatasetInspectionChoices}; catch {refreshNativeVariablesGui}; catch {refreshStandardModuleControls}; catch {genericCsvBatchRefreshImportButton}
    return $currentSession
}
proc ::GX::genericCsvBatchImportIntoCurrentSessionSync {} {
    return [::GX::genericCsvBatchImportIntoCurrentSessionSync_v09780]
}

proc ::GX::genericCsvBatchImportIntoCurrentSession {} {
    if {[catch {set session [genericCsvBatchImportIntoCurrentSessionSync]} err opts]} {
        tk_messageBox -icon error -type ok -title "Import batch datasets" -message $err
        return
    }
    setStatus "Additional enabled batch datasets imported into current session." 100
    catch {refreshCsvPreview}
    catch {refreshManifestPreview}
    return $session
}

# Persist all dataset metadata, including provenance mapping.  The loader was
# already generic and therefore needs no format-breaking change.
proc ::GX::saveDatasetRegistry_v1_before_schema {session} {
    variable cfg
    variable datasetRegistry
    set path [datasetRegistryPath $session]
    set fd [open $path w]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "; GX-TXT Canonical Dataset API registry"
    puts $fd "; Dataset Inspection / Variable Mapping API v1"
    puts $fd "; SPDX-License-Identifier: GPL-3.0-or-later"
    puts $fd "\[registry\]"; putKV $fd api_version 1; putKV $fd inspection_api_version 1; putKV $fd session_mode $cfg(session_mode)
    set ids [datasetRegistryIds]; putKV $fd count [llength $ids]
    foreach id $ids {
        puts $fd "\n\[dataset.$id\]"
        set fields {}
        foreach k [array names datasetRegistry "$id,*"] { lappend fields [string range $k [expr {[string length $id]+1}] end] }
        foreach field [lsort -unique $fields] { putKV $fd $field [datasetField $id $field ""] }
    }
    close $fd
    return $path
}

# Manifest persistence for pending batch mappings.
proc ::GX::manifestStringV2_v089_before_acq_group_manifest {} {
    variable genericCsvBatchCount
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    set out [::GX::manifestStringV2_v085_before_dataset_inspection]
    append out "\n\[dataset_inspection_api\]\n"; appendKV out version $::GX::datasetInspectionApiVersion
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        set n [expr {[info exists genericCsvBatchVarCount($i)] ? $genericCsvBatchVarCount($i) : 0}]
        append out "\n\[generic_csv_batch_variables.$i\]\n"; appendKV out count $n
        for {set j 1} {$j <= $n} {incr j} {
            append out "\n\[generic_csv_batch_variable.$i.$j\]\n"
            foreach f [datasetInspectionVarFields] { appendKV out $f [expr {[info exists genericCsvBatchVar($i,$j,$f)] ? $genericCsvBatchVar($i,$j,$f) : ""}] }
        }
    }
    return $out
}

proc ::GX::loadManifestV2_v089_before_acq_group_manifest {path} {
    variable genericCsvBatchCount
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    ::GX::loadManifestV2_v085_before_dataset_inspection $path
    array unset genericCsvBatchVar *; array unset genericCsvBatchVarCount *
    set d [parseIni $path]
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        set ck "generic_csv_batch_variables.$i.count"
        set n [expr {[dict exists $d $ck] ? [dict get $d $ck] : 0}]
        if {![string is integer -strict $n] || $n < 0} { set n 0 }
        if {$n > 0} { set genericCsvBatchVarCount($i) $n }
        for {set j 1} {$j <= $n} {incr j} {
            foreach f [datasetInspectionVarFields] {
                set k "generic_csv_batch_variable.$i.$j.$f"
                set def ""; if {$f eq "enabled"} { set def 1 }; if {$f eq "source_column"} { set def $j }
                set genericCsvBatchVar($i,$j,$f) [expr {[dict exists $d $k] ? [dict get $d $k] : $def}]
            }
        }
    }
    catch {genericCsvBatchRender}; catch {refreshDatasetInspectionChoices}; catch {refreshNativeVariablesGui}
}

proc ::GX::defaults_v091_before_dataset_selection {} {
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    variable variableDatasetChoice
    variable csvPreviewDatasetChoice
    variable inspectVar
    variable inspectVarCount
    ::GX::defaults_v085_before_dataset_inspection
    array unset genericCsvBatchVar *; array unset genericCsvBatchVarCount *; array unset inspectVar *
    set variableDatasetChoice ""; set csvPreviewDatasetChoice ""; set inspectVarCount 0
}
