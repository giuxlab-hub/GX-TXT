# GX-TXT Dataset Rename API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Canonical identity changes without rewriting the Dataset payload or RAW file.

namespace eval ::GX { variable datasetRenameProposed ""; variable datasetRenameAccepted 0 }

proc ::GX::datasetRenameReference {section key value oldId newId} {
    if {[string match *dataset_id $key]} {
        if {$value eq $oldId} { return $newId }
    }
    if {$key eq "source_dataset_ids"} {
        set ids {}
        foreach id [split $value {;}] { lappend ids [expr {$id eq $oldId ? $newId : $id}] }
        return [join $ids {;}]
    }
    if {$key eq "x_bindings"} {
        set bindings {}
        foreach binding [split $value {;}] {
            if {[string first "$oldId:" $binding] == 0} {
                set binding "$newId:[string range $binding [expr {[string length $oldId]+1}] end]"
            }
            lappend bindings $binding
        }
        return [join $bindings {;}]
    }
    if {[string match module_binding_variable_id.* $section]} {
        set parts [split $value |]
        if {[llength $parts] == 3 && [lindex $parts 1] eq $oldId} {
            lset parts 1 $newId
            return [join $parts |]
        }
    }
    if {[string match variable_reference_id.* $section] ||
        [string match repeatable_variable_id.* $section]} {
        set parts [split $value |]
        if {[llength $parts] == 2 && [lindex $parts 0] eq $oldId} {
            lset parts 0 $newId
            return [join $parts |]
        }
    }
    return $value
}

proc ::GX::datasetRenameIniText {path oldId newId oldMeta newMeta oldNote newNote} {
    set fd [open $path r]
    fconfigure $fd -encoding utf-8 -translation lf
    try { set source [read $fd] } finally { close $fd }
    set section ""
    set lines {}
    foreach line [split $source "\n"] {
        if {[regexp {^\[([^]]+)\]$} $line -> name]} {
            set section $name
            if {$name eq "dataset.$oldId"} { set line "\[dataset.$newId\]" }
        } elseif {[regexp {^([^=]+)=(.*)$} $line -> key encoded]} {
            set key [string trim $key]
            set value [iniUnescape $encoded]
            if {$section eq "dataset.$oldId" && $key eq "id"} { set value $newId }
            if {$section eq "dataset.$oldId" && $key eq "structured_metadata_file" && $value eq $oldMeta} { set value $newMeta }
            if {$section eq "dataset.$oldId" && $key eq "user_notes_file" && $value eq $oldNote} { set value $newNote }
            set value [datasetRenameReference $section $key $value $oldId $newId]
            set line "$key=[iniEscape $value]"
        }
        lappend lines $line
    }
    return [join $lines "\n"]
}

# Public API. All authoritative INI files and sidecars are restored from
# byte-for-byte backups if any write fails.
proc ::GX::datasetRename {session oldId newId} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {_datasetNamespaceRequireModuleWrite $session [dict get $::GX::DatasetPrivate::activeContext module_id] $oldId}
    variable currentSession
    variable graphSeries
    variable plotVariantBinding
    variable moduleCfg
    variable genericCsvBatch
    variable moduleAnalysisSource
    variable moduleBindingIdentity
    variable variableReferenceIdentity
    set session [file normalize $session]
    if {![file isdirectory $session]} { error "Dataset rename requires an existing Session." }
    set oldId [string trim $oldId]
    set newId [datasetPublicationV2ValidateId dataset $newId]
    loadDatasetRegistry $session
    if {[datasetField $oldId id ""] eq ""} { error "Dataset '$oldId' is not registered in this Session." }
    if {$oldId eq $newId} { return $newId }
    if {[datasetField $newId id ""] ne ""} { error "Dataset '$newId' already exists." }

    set oldMeta [datasetField $oldId structured_metadata_file ""]
    if {$oldMeta eq ""} { set oldMeta [_datasetMetadataRelativePath $oldId] }
    set newMeta [_datasetMetadataRelativePath $newId]
    set oldNote [datasetNoteRelativePath $oldId]
    set newNote [datasetNoteRelativePath $newId]
    if {[file pathtype $oldMeta] ne "relative" ||
        ![_datasetDeletePathWithin [file normalize [file join $session $oldMeta]] [file join $session metadata datasets]]} {
        error "Dataset metadata path is outside Session metadata storage."
    }
    set metaSource [file join $session $oldMeta]
    set metaTarget [file join $session $newMeta]
    set noteSource [file join $session $oldNote]
    set noteTarget [file join $session $newNote]
    foreach {source target} [list $metaSource $metaTarget $noteSource $noteTarget] {
        if {$source ne $target && [file exists $target]} { error "Dataset rename target already exists: $target" }
    }
    if {[file isfile $metaSource]} {
        set metadata [parseIni $metaSource]
        if {![dict exists $metadata dataset_metadata.dataset_id] ||
            [dict get $metadata dataset_metadata.dataset_id] ne $oldId} {
            error "Dataset metadata identity does not match '$oldId'."
        }
    }
    set registry [datasetRegistryPath $session]
    set manifest [file join $session metadata manifest.ini]
    set selections [datasetSelectionRegistryPath $session]
    set temporal [temporalSetRegistryPath $session]
    set inputs [list $registry $manifest $selections $temporal]
    foreach path [glob -nocomplain -directory [file join $session metadata datasets] *.ini] {
        if {[lsearch -exact $inputs $path] < 0} { lappend inputs $path }
    }
    set changes [dict create]
    foreach path $inputs {
        if {![file isfile $path]} continue
        set target [expr {$path eq $metaSource ? $metaTarget : $path}]
        dict set changes $target [datasetRenameIniText $path $oldId $newId $oldMeta $newMeta $oldNote $newNote]
    }
    set backups [dict create]
    set created {}
    set stamp ".dataset-rename.[pid].[clock clicks]"
    set touched [lsort -unique [concat $inputs [dict keys $changes] [list $noteSource $noteTarget]]]
    try {
        foreach path $touched {
            if {![file isfile $path]} continue
            set backup "$path$stamp.backup"
            file copy -- $path $backup
            dict set backups $path $backup
        }
        dict for {path contents} $changes {
            file mkdir [file dirname $path]
            set temporary "$path$stamp.tmp"
            set fd [open $temporary w]
            fconfigure $fd -encoding utf-8 -translation lf
            try { puts -nonewline $fd $contents } finally { close $fd }
            file rename -force -- $temporary $path
            if {![dict exists $backups $path]} { lappend created $path }
        }
        if {$metaSource ne $metaTarget && [file isfile $metaSource]} { file delete -- $metaSource }
        if {$noteSource ne $noteTarget && [file isfile $noteSource]} {
            file mkdir [file dirname $noteTarget]
            file rename -- $noteSource $noteTarget
            if {![dict exists $backups $noteTarget]} { lappend created $noteTarget }
        }
    } on error {reason options} {
        foreach path $created { catch {file delete -force -- $path} }
        dict for {path backup} $backups { catch {file copy -force -- $backup $path} }
        dict for {path backup} $backups { catch {file delete -force -- $backup} }
        foreach path [dict keys $changes] { catch {file delete -force -- "$path$stamp.tmp"} }
        return -options $options $reason
    }
    dict for {path backup} $backups { file delete -force -- $backup }
    loadDatasetRegistry $session
    if {$currentSession ne "" && [file normalize $currentSession] eq $session} {
        datasetSelectionLoadRegistry $session
        temporalSetLoadRegistry $session
        foreach key [array names graphSeries] {
            if {[dict exists $graphSeries($key) dataset_id] && [dict get $graphSeries($key) dataset_id] eq $oldId} {
                dict set graphSeries($key) dataset_id $newId
            }
        }
        foreach key [array names plotVariantBinding] {
            if {[dict exists $plotVariantBinding($key) dataset_id] && [dict get $plotVariantBinding($key) dataset_id] eq $oldId} {
                dict set plotVariantBinding($key) dataset_id $newId
            }
        }
        foreach name [array names moduleCfg "*,*dataset_id"] {
            if {$moduleCfg($name) eq $oldId} { set moduleCfg($name) $newId }
        }
        foreach name [array names genericCsvBatch "*,dataset_id"] {
            if {$genericCsvBatch($name) eq $oldId} { set genericCsvBatch($name) $newId }
        }
        foreach name [array names moduleAnalysisSource "*,dataset_id"] {
            if {$moduleAnalysisSource($name) eq $oldId} { set moduleAnalysisSource($name) $newId }
        }
        foreach name [array names moduleBindingIdentity] {
            set moduleBindingIdentity($name) [datasetRenameReference module_binding_variable_id.identity identity $moduleBindingIdentity($name) $oldId $newId]
        }
        foreach name [array names variableReferenceIdentity] {
            set variableReferenceIdentity($name) [datasetRenameReference variable_reference_id.identity identity $variableReferenceIdentity($name) $oldId $newId]
        }
    }
    return $newId
}

proc ::GX::datasetRenameSelectedFromGui {{targetId {}}} {
    variable currentSession
    variable variableDatasetChoice
    variable csvPreviewDatasetChoice
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode oldId
    set renamingActive [expr {$targetId eq {}||($mode eq "imported"&&$oldId eq $targetId)}]
    if {$targetId ne {}} {set oldId $targetId;set mode imported}
    if {$mode ne "imported" || $oldId eq ""} { return 0 }
    set dialog .datasetRename
    catch {destroy $dialog}
    toplevel $dialog
    wm title $dialog "Rename Dataset"
    wm transient $dialog .top
    set ::GX::datasetRenameProposed $oldId
    set ::GX::datasetRenameAccepted 0
    ttk::label $dialog.label -text "New ID for Dataset '$oldId':"
    ttk::entry $dialog.entry -textvariable ::GX::datasetRenameProposed -width 42
    ttk::frame $dialog.buttons
    ttk::button $dialog.buttons.ok -text "Rename" -command {set ::GX::datasetRenameAccepted 1}
    ttk::button $dialog.buttons.cancel -text "Cancel" -command {set ::GX::datasetRenameAccepted -1}
    pack $dialog.buttons.ok $dialog.buttons.cancel -side left -padx 5
    pack $dialog.label $dialog.entry $dialog.buttons -padx 12 -pady 7
    bind $dialog.entry <Return> {set ::GX::datasetRenameAccepted 1}
    bind $dialog <Escape> {set ::GX::datasetRenameAccepted -1}
    wm protocol $dialog WM_DELETE_WINDOW {set ::GX::datasetRenameAccepted -1}
    focus $dialog.entry
    grab $dialog
    vwait ::GX::datasetRenameAccepted
    set accepted $::GX::datasetRenameAccepted
    set proposed $::GX::datasetRenameProposed
    catch {grab release $dialog}
    destroy $dialog
    if {$accepted != 1} { return 0 }
    if {[catch {set newId [datasetRename $currentSession $oldId $proposed]} reason]} {
        tk_messageBox -parent .top -icon error -title "Rename Dataset" -message $reason
        return 0
    }
    if {$renamingActive} {
        set variableDatasetChoice [datasetInspectionImportedChoice $newId]
        set csvPreviewDatasetChoice $variableDatasetChoice
    }
    catch {refreshDatasetInspectionChoices}
    catch {refreshNativeVariablesGui}
    catch {refreshCsvPreview}
    catch {refreshNativeAnalysisState}
    catch {refreshResults}
    setStatus "Dataset $oldId renamed to $newId." 100
    return 1
}
