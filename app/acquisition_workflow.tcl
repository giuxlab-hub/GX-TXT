# SPDX-License-Identifier: GPL-3.0-or-later
# The interactive import table is a pending work queue. The older manifest and
# import routines remain callable by headless generators and compatibility tools.
namespace eval ::GX {
    variable interactiveImportQueue 0
    variable importQueueModule ""
    variable importerChoice ""
}

proc ::GX::importerBuilderSelectedId {} {
    if {[string match {builder.*} $::GX::importerChoice]} {
        return [string range $::GX::importerChoice 8 end]
    }
    return ""
}

proc ::GX::importerBuilderRefreshSelector {} {
    importerBuilderReload
    if {![llength [info commands winfo]] || ![winfo exists .top.nb.acq.browser.tree]} return
    acquisitionBrowserRefresh
}

proc ::GX::importerSelectionChanged {} {
    variable importerChoice
    variable importQueueModule
    if {$importerChoice ne $importQueueModule} { importQueueReset }
    set builderId [importerBuilderSelectedId]
    if {$builderId ne ""} {
        importerBuilderGet $builderId
        set ::GX::cfg(acquisition_module) acq.generic_csv
    } else {
        set ::GX::cfg(acquisition_module) $importerChoice
    }
    set importQueueModule $importerChoice
    refreshNativeAcquisitionConfig
    ::GX::onAcquisitionModuleChanged_before_import_queue
    refreshGenericCsvBatchVisibility
    acquisitionHandlerRefreshBatchLabel
    importQueueRefreshFolderButton
    acquisitionBrowserDescribe
}

proc ::GX::importQueueRefreshFolderButton {} {
    set button .top.nb.acq.batch.bar.folder
    if {![winfo exists $button]} return
    set enabled [expr {[importerBuilderSelectedId] ne "" || $::GX::cfg(acquisition_module) eq "acq.generic_csv"}]
    $button state [expr {$enabled ? "!disabled" : "disabled"}]
}

proc ::GX::importQueueAddFolder {{directory ""}} {
    if {$directory eq ""} { set directory [tk_chooseDirectory -title "Add data files to import queue"] }
    if {$directory eq ""} return
    if {![file isdirectory $directory]} { error "Import folder does not exist: $directory" }
    set builderId [importerBuilderSelectedId]
    if {$builderId ne ""} {
        set d [importerBuilderGet $builderId]
        set pattern [dict get $d match_regex]
    } elseif {$::GX::cfg(acquisition_module) eq "acq.generic_csv"} {
        set pattern {(?i)\.(csv|tsv|txt|dat)$}
    } else {
        error "Folder import is available for generic and built importers."
    }
    set added 0
    foreach path [lsort -dictionary [glob -nocomplain -directory $directory *]] {
        if {![file isfile $path]} continue
        if {$pattern ne "" && ![regexp -- $pattern [file tail $path]]} continue
        genericCsvBatchAdd $path
        incr added
    }
    if {$added == 0} { error "No matching files were found in $directory." }
    return $added
}

proc ::GX::refreshNativeAcquisitionConfig {} {
    ::GX::refreshNativeAcquisitionConfig_before_importer_builder
    set builderId [importerBuilderSelectedId]
    if {$builderId eq ""} return
    set host .top.nb.acq.cfg
    if {![winfo exists $host]} return
    destroyChildren $host
    set d [importerBuilderGet $builderId]
    ttk::label $host.info -text "[dict get $d name] v[dict get $d version] — [dict get $d description]" -wraplength 850 -justify left
    grid $host.info -row 0 -column 0 -sticky ew -padx 5 -pady 5
}

proc ::GX::importQueueReset {} {
    variable genericCsvBatchEnabled
    variable genericCsvBatchResult
    genericCsvBatchClear
    array unset genericCsvBatchResult *
    set genericCsvBatchEnabled 1
    catch {genericCsvBatchRender}
    catch {genericCsvBatchRefreshImportButton}
}

# A newly queued row with an existing Dataset ID must reach preflight and show
# a correction message. The legacy batch helper silently omitted such rows.
proc ::GX::genericCsvBatchPendingEnabledRows {} {
    if {!$::GX::interactiveImportQueue} {
        return [::GX::genericCsvBatchPendingEnabledRows_before_import_queue]
    }
    set rows {}
    for {set i 1} {$i <= $::GX::genericCsvBatchCount} {incr i} {
        if {[info exists ::GX::genericCsvBatch($i,enabled)] && $::GX::genericCsvBatch($i,enabled)} { lappend rows $i }
    }
    return $rows
}

proc ::GX::genericCsvBatchRowStatus {row} {
    if {$::GX::interactiveImportQueue} {
        if {[info exists ::GX::genericCsvBatchResult($row,status)]} { return $::GX::genericCsvBatchResult($row,status) }
        return Pending
    }
    return [::GX::genericCsvBatchRowStatus_before_import_queue $row]
}

proc ::GX::genericCsvBatchClear {} {
    variable interactiveImportQueue
    variable genericCsvBatchEnabled
    variable genericCsvBatchResult
    ::GX::genericCsvBatchClear_before_import_queue
    array unset genericCsvBatchResult *
    if {$interactiveImportQueue} { set genericCsvBatchEnabled 1 }
    catch {genericCsvBatchRefreshImportButton}
}

proc ::GX::genericCsvBatchAdd {{path ""}} {
    if {$::GX::interactiveImportQueue && $path eq ""} {
        set path [tk_getOpenFile -filetypes {{{Data files} {.csv .txt .tsv .dat}} {{All files} *}}]
        if {$path eq ""} { return "" }
    }
    set builderId [importerBuilderSelectedId]
    if {$builderId ne ""} {
        set d [importerBuilderGet $builderId]
        if {$path ne "" && [dict get $d match_regex] ne "" && ![regexp -- [dict get $d match_regex] [file tail $path]]} {
            error "The selected file does not match importer '$builderId'."
        }
    }
    set row [::GX::genericCsvBatchAdd_before_import_queue $path]
    if {$builderId ne ""} { importerBuilderApplyToRow $builderId $row }
    return $row
}

proc ::GX::importerBuilderApplyToRow {id row} {
    variable genericCsvBatch
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    set d [importerBuilderGet $id]
    set genericCsvBatch($row,importer_definition) $id
    set genericCsvBatch($row,delimiter) [dict get $d delimiter]
    set genericCsvBatch($row,header_rows) [dict get $d header_rows]
    genericCsvBatchSetContract $row [dict get $d contract]
    genericCsvBatchClearVariables $row
    set j 0
    foreach mapping [dict get $d mappings] {
        incr j
        foreach {key value} [list enabled 1 source_column [dict get $mapping column] \
            original_header [dict get $mapping name] canonical [dict get $mapping name] \
            unit [dict get $mapping unit] semantic_role "" instrument_id "" instrument_channel ""] {
            set genericCsvBatchVar($row,$j,$key) $value
        }
    }
    set genericCsvBatchVarCount($row) $j
    catch {genericCsvBatchRender}
}

proc ::GX::genericCsvBatchEnsureVariables {row {force 0}} {
    if {[info exists ::GX::genericCsvBatch($row,importer_definition)]} {
        set id $::GX::genericCsvBatch($row,importer_definition)
        if {$force || ![info exists ::GX::genericCsvBatchVarCount($row)]} {
            importerBuilderApplyToRow $id $row
        }
        return $::GX::genericCsvBatchVarCount($row)
    }
    return [::GX::genericCsvBatchEnsureVariables_before_importer_builder $row $force]
}

proc ::GX::genericCsvBatchRemove {row} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    set definitions [dict create]
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        if {[info exists genericCsvBatch($i,importer_definition)]} {
            dict set definitions $i $genericCsvBatch($i,importer_definition)
        }
    }
    ::GX::genericCsvBatchRemove_before_importer_builder $row
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        catch {unset genericCsvBatch($i,importer_definition)}
        set old [expr {$i >= $row ? $i+1 : $i}]
        if {[dict exists $definitions $old]} {
            set genericCsvBatch($i,importer_definition) [dict get $definitions $old]
        }
    }
    catch {unset genericCsvBatch([expr {$genericCsvBatchCount+1}],importer_definition)}
}

proc ::GX::refreshGenericCsvBatchVisibility {} {
    if {!$::GX::interactiveImportQueue} {
        return [::GX::refreshGenericCsvBatchVisibility_before_import_queue]
    }
    set box .top.nb.acq.batch
    if {![llength [info commands winfo]] || ![winfo exists $box]} return
    set module $::GX::cfg(acquisition_module)
    if {$module eq "acq.generic_csv" || [acquisitionHandlerIsPluginModule $module]} {
        grid $box
    } else {
        grid remove $box
    }
}

proc ::GX::onAcquisitionModuleChanged {} {
    variable importQueueModule
    if {$::GX::interactiveImportQueue && $importQueueModule ne "" &&
        $importQueueModule ne $::GX::cfg(acquisition_module)} {
        importQueueReset
    }
    set importQueueModule $::GX::cfg(acquisition_module)
    ::GX::onAcquisitionModuleChanged_before_import_queue
    refreshGenericCsvBatchVisibility
}

proc ::GX::acquisitionHandlerRefreshBatchLabel {} {
    ::GX::acquisitionHandlerRefreshBatchLabel_before_import_queue
    if {!$::GX::interactiveImportQueue} return
    set box .top.nb.acq.batch
    if {![winfo exists $box]} return
    $box configure -text "Pending imports"
    $box.note configure -text "Select files for the current Session. Imported rows leave this temporary queue; failed rows remain for correction and retry."
    catch {$box.bar.add configure -text "+ Add file"}
    catch {$box.bar.multi configure -text "Add multiple..."}
}

# Final Manifest Format 2 serialization follows fixed named predecessors.
proc ::GX::manifestStringV2 {} {
    variable genericCsvBatchCount
    variable genericCsvBatchEnabled
    if {!$::GX::interactiveImportQueue} {
        return [::GX::manifestStringV2_before_import_queue]
    }
    set savedCount $genericCsvBatchCount
    set savedEnabled $genericCsvBatchEnabled
    try {
        set genericCsvBatchCount 0
        set genericCsvBatchEnabled 0
        return [::GX::manifestStringV2_before_import_queue]
    } finally {
        set genericCsvBatchCount $savedCount
        set genericCsvBatchEnabled $savedEnabled
    }
}

# Final Manifest Format 2 loader follows fixed named predecessors.
proc ::GX::loadManifestV2 {path} {
    set result [::GX::loadManifestV2_before_import_queue $path]
    if {$::GX::interactiveImportQueue} { importQueueReset }
    return $result
}

proc ::GX::importQueuePruneSuccessful {} {
    variable genericCsvBatchCount
    variable genericCsvBatchResult
    variable genericCsvBatch
    set survivors {}
    set removed 0
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        set status [expr {[info exists genericCsvBatchResult($i,status)] ? $genericCsvBatchResult($i,status) : "Pending"}]
        if {$status eq "Imported"} {
            incr removed
        } else {
            lappend survivors [list $status [expr {[info exists genericCsvBatchResult($i,message)] ? $genericCsvBatchResult($i,message) : ""}]]
        }
    }
    for {set i $genericCsvBatchCount} {$i >= 1} {incr i -1} {
        if {[info exists genericCsvBatchResult($i,status)] && $genericCsvBatchResult($i,status) eq "Imported"} {
            genericCsvBatchRemove $i
        }
    }
    array unset genericCsvBatchResult *
    for {set j 1} {$j <= $genericCsvBatchCount} {incr j} {
        catch {unset genericCsvBatch($j,acquisition_status)}
        catch {unset genericCsvBatch($j,acquisition_message)}
    }
    set i 0
    foreach state $survivors {
        incr i
        lassign $state status message
        if {$status ne "Pending"} { genericCsvBatchRecord $i $status $message }
    }
    catch {genericCsvBatchRender}
    catch {genericCsvBatchRefreshImportButton}
    return $removed
}

proc ::GX::genericCsvBatchImportIntoCurrentSessionSync {} {
    variable currentSession
    variable genericCsvBatchResult
    variable acquisitionHandlerBatchLastReport
    if {!$::GX::interactiveImportQueue} {
        return [::GX::genericCsvBatchImportIntoCurrentSessionSync_before_import_queue]
    }
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        error "Create or open a Session before importing Datasets."
    }
    loadDatasetRegistry $currentSession
    set rows [genericCsvBatchPendingEnabledRows]
    if {![llength $rows]} { return $currentSession }
    set ready {}
    set rejected [dict create]
    foreach row $rows {
        if {[catch {genericCsvBatchPreflightRows [list $row] $currentSession} reason]} {
            dict set rejected $row $reason
        } else {
            lappend ready $row
        }
    }
    if {[llength $ready]} { genericCsvBatchRunRows $currentSession $ready }
    dict for {row reason} $rejected { genericCsvBatchRecord $row Failed $reason }
    set reports {}
    foreach row $rows {
        set status $genericCsvBatchResult($row,status)
        set message $genericCsvBatchResult($row,message)
        lappend reports "Import row $row $status: $message"
    }
    writeManifest [file join $currentSession metadata manifest.ini]
    set logPath [file join $currentSession logs pipeline.log]
    file mkdir [file dirname $logPath]
    set log [open $logPath a]
    fconfigure $log -encoding utf-8 -translation lf
    try { foreach line $reports { puts $log $line } } finally { close $log }
    importQueuePruneSuccessful
    catch {refreshDatasetInspectionChoices}
    catch {refreshNativeVariablesGui}
    catch {refreshStandardModuleControls}
    return $currentSession
}

# The GUI composition order is expressed by named calls in each layer.
# Import queue flags must be set before the base constructs its pages.
proc ::GX::launchGui {} {
    variable interactiveImportQueue
    variable genericCsvBatchEnabled
    variable importQueueModule
    set interactiveImportQueue 1
    set genericCsvBatchEnabled 1
    ::GX::launchGui_before_import_queue
    set ::GX::importerChoice $::GX::cfg(acquisition_module)
    set importQueueModule $::GX::importerChoice
    importerBuilderRefreshSelector
    acquisitionBrowserDescribe
    refreshGenericCsvBatchVisibility
    acquisitionHandlerRefreshBatchLabel
    catch {.top.nb.acq.batch.bar.importCurrent configure -text "Import into current Session"}
    ttk::button .top.nb.acq.batch.bar.folder -text "Add folder..." -command ::GX::importQueueAddFolder
    pack .top.nb.acq.batch.bar.folder -side left -padx 3
    # General catalog tools belong above the browser; queue tools stay left.
    pack forget .top.nb.acq.batch.bar.contracts
    bind .top.nb.acq.batch.bar <Configure> ::GX::acquisitionQueueToolbarLayout
    after idle ::GX::acquisitionQueueToolbarLayout
    importQueueRefreshFolderButton
    # The historical Run actions create a Session during acquisition. The
    # interactive path now imports through the queue into the open Session.
    catch {pack forget .top.nb.run.buttons.start .top.nb.run.buttons.all}
    catch {genericCsvBatchRefreshImportButton}
}
