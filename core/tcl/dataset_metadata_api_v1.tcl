# GX-TXT Dataset Metadata API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# One opaque generic key/value resource belongs to each canonical Dataset ID.
# CORE owns persistence and lifecycle; importers own field semantics.

namespace eval ::GX {
    variable datasetMetadataApiVersion 1
    variable datasetMetadataEditorDataset ""
    variable datasetMetadataEditorData [dict create]
    variable datasetMetadataEditorKey ""
}

source [file join [file dirname [info script]] dataset_coordinate_context_v1.tcl]

proc ::GX::_datasetMetadataStem {datasetId} {
    set stem [sanitize $datasetId]
    if {$stem eq ""} { set stem dataset }
    if {$stem ne $datasetId} {
        set crc [format %08x [zlib crc32 [encoding convertto utf-8 $datasetId]]]
        append stem "_" $crc
    }
    return $stem
}

proc ::GX::_datasetMetadataRelativePath {datasetId} {
    return [file join metadata datasets "[_datasetMetadataStem $datasetId].ini"]
}

proc ::GX::_datasetMetadataRequireDataset {session datasetId} {
    if {$session eq "" || ![file isdirectory $session]} { error "Dataset metadata requires an existing session." }
    set session [file normalize $session]
    set datasetId [string trim $datasetId]
    if {$datasetId eq ""} { error "Dataset metadata requires a Dataset ID." }
    loadDatasetRegistry $session
    if {[datasetField $datasetId id ""] eq ""} { error "Dataset '$datasetId' is not registered in this session." }
    return [list $session $datasetId]
}

proc ::GX::_datasetMetadataValidateKey {key} {
    set key [string trim $key]
    if {![regexp {^[[:alnum:]_-]+([.][[:alnum:]_-]+)*$} $key]} {
        error "Metadata keys may contain letters, digits, underscores, hyphens and dot-separated segments."
    }
    return $key
}

proc ::GX::_datasetMetadataPortableParse {text} {
    set metadata [dict create]
    set lineNumber 0
    set text [string map [list "\r\n" "\n" "\r" "\n"] $text]
    foreach line [split $text "\n"] {
        incr lineNumber
        set leadingTrimmed [string trimleft $line]
        if {$leadingTrimmed eq ""} continue
        set first [string index $leadingTrimmed 0]
        if {$first eq "#" || $first eq ";"} continue

        set separator [string first "=" $line]
        if {$separator < 0} {
            error "Invalid metadata line $lineNumber: expected key=value."
        }
        set key [string trim [string range $line 0 [expr {$separator - 1}]]]
        if {$key eq ""} {
            error "Invalid metadata line $lineNumber: metadata key is empty."
        }
        if {[catch {set key [_datasetMetadataUserKey $key]} validationError]} {
            error "Invalid metadata line $lineNumber: $validationError"
        }
        set value [string trim [string range $line [expr {$separator + 1}] end]]
        # Deterministic duplicate handling: the last occurrence in the file wins.
        dict set metadata $key $value
    }
    return $metadata
}

proc ::GX::_datasetMetadataPortableSerialize {metadata} {
    if {[catch {dict size $metadata}]} { error "Dataset metadata must be a dictionary." }
    set text ""
    foreach key [lsort -dictionary [dict keys $metadata]] {
        if {[_datasetMetadataReserved $key]} continue
        set key [_datasetMetadataUserKey $key]
        set value [dict get $metadata $key]
        if {[regexp {[\r\n]} $value]} {
            error "Metadata value for '$key' contains a line break and cannot be represented by the one-field-per-line export format."
        }
        append text $key "=" $value "\n"
    }
    return $text
}

# Public, headless parsing surface; file import and clipboard input share it.
proc ::GX::datasetMetadataParseText {text {options {}}} {
    if {[dict size $options]} {error "Metadata text parsing does not accept options in API v1."}
    if {[string index $text 0] eq "\ufeff"} {set text [string range $text 1 end]}
    return [_datasetMetadataPortableParse $text]
}

proc ::GX::_datasetMetadataPortableReadFile {path} {
    if {$path eq "" || ![file isfile $path]} { error "Metadata import file does not exist." }
    if {[catch {
        set fd [open $path rb]
        fconfigure $fd -translation binary -encoding binary
        set bytes [read $fd]
        close $fd
    } err options]} {
        catch {close $fd}
        return -options $options $err
    }
    set text [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $text] ne $bytes} {
        error "Metadata import file is not valid UTF-8."
    }
    if {[string length $text] > 0 && [string index $text 0] eq "\ufeff"} {
        set text [string range $text 1 end]
    }
    return [datasetMetadataParseText $text]
}

proc ::GX::_datasetMetadataPortableWriteFile {path metadata} {
    if {$path eq ""} { error "Metadata export path is empty." }
    set text [_datasetMetadataPortableSerialize $metadata]
    set parent [file dirname $path]
    if {![file isdirectory $parent]} { error "Metadata export directory does not exist." }
    set temporary [format "%s.tmp.%s.%s" $path [pid] [clock clicks]]
    if {[catch {
        set fd [open $temporary w]
        fconfigure $fd -encoding utf-8 -translation lf
        puts -nonewline $fd $text
        close $fd
        file rename -force -- $temporary $path
    } err options]} {
        catch {close $fd}
        catch {file delete -force -- $temporary}
        return -options $options $err
    }
    return $path
}

proc ::GX::_datasetMetadataPath {session datasetId} {
    set rel [datasetField $datasetId structured_metadata_file ""]
    if {$rel eq ""} { set rel [_datasetMetadataRelativePath $datasetId] }
    if {[file pathtype $rel] eq "absolute"} { error "Dataset metadata path must be session-relative." }
    set path [file normalize [file join $session $rel]]
    if {![_datasetDeletePathWithin $path [file join $session metadata datasets]]} {
        error "Dataset metadata path is outside session metadata storage."
    }
    return [list $rel $path]
}

proc ::GX::_datasetMetadataReadAll {session datasetId} {
    lassign [_datasetMetadataRequireDataset $session $datasetId] session datasetId
    return [_datasetMetadataReadRegistered $session $datasetId]
}
# Internal batch reader: caller has already loaded and validated the Session's
# registry. This reads the same resource without reloading the full registry for
# every catalog row; it is not a cache or a second metadata authority.
proc ::GX::_datasetMetadataReadRegistered {session datasetId} {
    if {[datasetField $datasetId id {}] ne $datasetId} {error "Unknown Dataset '$datasetId'"}
    lassign [_datasetMetadataPath $session $datasetId] rel path
    if {![file isfile $path]} { return [dict create] }
    set parsed [parseIni $path]
    if {![dict exists $parsed dataset_metadata.dataset_id] ||
        [dict get $parsed dataset_metadata.dataset_id] ne $datasetId} {
        error "Dataset metadata identity does not match Dataset ID '$datasetId'."
    }
    set result [dict create]
    set prefix "metadata."
    foreach name [dict keys $parsed] {
        if {[string first $prefix $name] != 0} continue
        set key [string range $name [string length $prefix] end]
        _datasetMetadataValidateKey $key
        dict set result $key [dict get $parsed $name]
    }
    return $result
}

proc ::GX::_datasetMetadataWriteAll {session datasetId metadata} {
    variable datasetRegistry
    if {[catch {dict size $metadata}]} { error "Dataset metadata must be a dictionary." }
    lassign [_datasetMetadataRequireDataset $session $datasetId] session datasetId
    set normalized [dict create]
    foreach key [dict keys $metadata] {
        set valid [_datasetMetadataValidateKey $key]
        dict set normalized $valid [dict get $metadata $key]
    }
    lassign [_datasetMetadataPath $session $datasetId] rel path
    datasetAuthorityEnlist $path
    file mkdir [file dirname $path]
    set updated [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
    set temporary [format "%s.tmp.%s.%s" $path [pid] [clock clicks]]
    if {[catch {
        set fd [open $temporary w]
        fconfigure $fd -encoding utf-8 -translation lf
        puts $fd "; GX-TXT Dataset Metadata API v1"
        puts $fd "; SPDX-License-Identifier: GPL-3.0-or-later"
        puts $fd "\[dataset_metadata\]"
        putKV $fd api_version 1
        putKV $fd dataset_id $datasetId
        putKV $fd updated_at $updated
        putKV $fd count [dict size $normalized]
        puts $fd "\n\[metadata\]"
        foreach key [lsort -dictionary [dict keys $normalized]] {
            putKV $fd $key [dict get $normalized $key]
        }
        close $fd
    } err options]} {
        catch {close $fd}
        catch {file delete -force -- $temporary}
        return -options $options $err
    }

    set fields {structured_metadata_file structured_metadata_api_version structured_metadata_updated_at structured_metadata_revision metadata_display_name}
    set previous [dict create]
    foreach field $fields {
        if {[info exists datasetRegistry($datasetId,$field)]} {
            dict set previous $field [list 1 $datasetRegistry($datasetId,$field)]
        } else {
            dict set previous $field [list 0 ""]
        }
    }
    set datasetRegistry($datasetId,structured_metadata_file) $rel
    set datasetRegistry($datasetId,structured_metadata_api_version) 1
    set datasetRegistry($datasetId,structured_metadata_updated_at) $updated
    set revision [expr {[info exists datasetRegistry($datasetId,structured_metadata_revision)] ? $datasetRegistry($datasetId,structured_metadata_revision) : 0}]
    set datasetRegistry($datasetId,structured_metadata_revision) [expr {$revision+1}]
    set datasetRegistry($datasetId,metadata_display_name) [expr {[dict exists $normalized dataset.display_name] ? [dict get $normalized dataset.display_name] : ""}]
    if {[catch {saveDatasetRegistry $session} err options]} {
        foreach field $fields {
            lassign [dict get $previous $field] existed value
            if {$existed} { set datasetRegistry($datasetId,$field) $value } else { catch {unset datasetRegistry($datasetId,$field)} }
        }
        catch {file delete -force -- $temporary}
        return -options $options $err
    }
    if {[catch {file rename -force -- $temporary $path} err options]} {
        foreach field $fields {
            lassign [dict get $previous $field] existed value
            if {$existed} { set datasetRegistry($datasetId,$field) $value } else { catch {unset datasetRegistry($datasetId,$field)} }
        }
        catch {saveDatasetRegistry $session}
        catch {file delete -force -- $temporary}
        return -options $options $err
    }
    return $path
}

# Ordinary metadata never grants access to reserved writes. Replacement keeps
# existing private fields, so an unchanged generic editor cannot erase them.
proc ::GX::datasetMetadataRead {session datasetId} {
    return [_datasetMetadataFilter [_datasetMetadataReadAll $session $datasetId] 0]
}
proc ::GX::datasetMetadataWrite {session datasetId metadata} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetMetadataWrite $session $datasetId $metadata]}
    if {$::GX::DatasetPrivate::activeContext ne {}} {
        _datasetNamespaceRequireModuleWrite $session [dict get $::GX::DatasetPrivate::activeContext module_id] $datasetId
    }
    set normalized {}
    dict for {key value} $metadata {dict set normalized [_datasetMetadataUserKey $key] $value}
    set before [_datasetMetadataReadAll $session $datasetId]
    ::GX::StatisticsV1::validateMetadataReplacement [_datasetMetadataFilter $before 0] $normalized
    set private [_datasetMetadataFilter $before 1]
    set path [_datasetMetadataWriteAll $session $datasetId [dict merge $normalized $private]]
    if {$::GX::DatasetPrivate::activeContext ne {}} {
        set changed {}
        dict for {key value} $normalized {if {![dict exists $before $key] || [dict get $before $key] ne $value} {lappend changed $key}}
        if {$changed ne {}} {_datasetMetadataOriginRecord $session $datasetId module:[dict get $::GX::DatasetPrivate::activeContext module_id] $changed}
    }
    return $path
}

proc ::GX::datasetMetadataUpdate {session datasetId updates} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetMetadataUpdate $session $datasetId $updates]}
    if {[catch {dict size $updates}]} { error "Dataset metadata updates must be a dictionary." }
    set metadata [datasetMetadataRead $session $datasetId]
    foreach key [dict keys $updates] {
        dict set metadata [_datasetMetadataUserKey $key] [dict get $updates $key]
    }
    datasetMetadataWrite $session $datasetId $metadata
    return $metadata
}

proc ::GX::datasetMetadataUnset {session datasetId keys} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::datasetMetadataUnset $session $datasetId $keys]}
    set metadata [datasetMetadataRead $session $datasetId]
    foreach key $keys {
        set key [_datasetMetadataUserKey $key]
        if {[dict exists $metadata $key]} { dict unset metadata $key }
    }
    datasetMetadataWrite $session $datasetId $metadata
    return $metadata
}

proc ::GX::datasetMetadataEditorRender {} {
    variable datasetMetadataEditorData
    set tree .top.nb.channels.metadataEditor.table.tree
    if {![winfo exists $tree]} return
    $tree delete [$tree children {}]
    foreach key [lsort -dictionary [dict keys $datasetMetadataEditorData]] {
        set value [dict get $datasetMetadataEditorData $key]
        set display [datasetMetadataBoundedValue $value]
        $tree insert {} end -values [list $key $display]
    }
}

proc ::GX::datasetMetadataEditorSelect {} {
    variable datasetMetadataEditorData
    variable datasetMetadataEditorKey
    set tree .top.nb.channels.metadataEditor.table.tree
    set valueWidget .top.nb.channels.metadataEditor.edit.value
    set selection [$tree selection]
    if {[llength $selection] != 1} return
    set datasetMetadataEditorKey [lindex [$tree item [lindex $selection 0] -values] 0]
    $valueWidget delete 1.0 end
    $valueWidget insert 1.0 [dict get $datasetMetadataEditorData $datasetMetadataEditorKey]
}

proc ::GX::datasetMetadataEditorPut {} {
    variable datasetMetadataEditorData
    variable datasetMetadataEditorKey
    set key [string trim $datasetMetadataEditorKey]
    if {[catch {set key [_datasetMetadataUserKey $key]} err]} {
        tk_messageBox -parent .top.nb.channels.metadataEditor -icon error -type ok -title "Dataset metadata" -message $err
        return
    }
    set value [.top.nb.channels.metadataEditor.edit.value get 1.0 end-1c]
    dict set datasetMetadataEditorData $key $value
    set datasetMetadataEditorKey $key
    datasetMetadataEditorRender
}

proc ::GX::datasetMetadataEditorRemove {} {
    variable datasetMetadataEditorData
    variable datasetMetadataEditorKey
    set key [string trim $datasetMetadataEditorKey]
    if {$key eq ""} return
    if {[dict exists $datasetMetadataEditorData $key]} { dict unset datasetMetadataEditorData $key }
    set datasetMetadataEditorKey ""
    .top.nb.channels.metadataEditor.edit.value delete 1.0 end
    datasetMetadataEditorRender
}


proc ::GX::_datasetMetadataEditorImportFile {path} {
    variable datasetMetadataEditorData
    variable datasetMetadataEditorKey
    # Parse and validate the complete file before changing editor state.
    set imported [_datasetMetadataPortableReadFile $path]
    set merged $datasetMetadataEditorData
    foreach key [dict keys $imported] {
        dict set merged $key [dict get $imported $key]
    }
    set datasetMetadataEditorData $merged
    datasetMetadataEditorRender
    set valueWidget .top.nb.channels.metadataEditor.edit.value
    if {$datasetMetadataEditorKey ne "" && [dict exists $datasetMetadataEditorData $datasetMetadataEditorKey] && [winfo exists $valueWidget]} {
        $valueWidget delete 1.0 end
        $valueWidget insert 1.0 [dict get $datasetMetadataEditorData $datasetMetadataEditorKey]
    }
    return [dict size $imported]
}

proc ::GX::_datasetMetadataEditorExportFile {path} {
    variable datasetMetadataEditorData
    return [_datasetMetadataPortableWriteFile $path $datasetMetadataEditorData]
}

proc ::GX::datasetMetadataEditorImport {} {
    set path [tk_getOpenFile \
        -parent .top.nb.channels.metadataEditor \
        -title "Import Dataset metadata" \
        -filetypes {{{Metadata text} {.metadata.txt .txt}} {{All files} *}}]
    if {$path eq ""} return
    if {[catch {set count [_datasetMetadataEditorImportFile $path]} err]} {
        tk_messageBox -parent .top.nb.channels.metadataEditor -icon error -type ok -title "Dataset metadata" -message $err
        return
    }
    setStatus "Imported $count metadata field(s). Review the editor and use Save to commit changes." 100
}

proc ::GX::datasetMetadataEditorExport {} {
    variable datasetMetadataEditorDataset
    set initialfile "[_datasetMetadataStem $datasetMetadataEditorDataset].metadata.txt"
    set path [tk_getSaveFile \
        -parent .top.nb.channels.metadataEditor \
        -title "Export Dataset metadata" \
        -initialfile $initialfile \
        -defaultextension .metadata.txt \
        -filetypes {{{Metadata text} {.metadata.txt .txt}} {{Text files} {.txt}} {{All files} *}}]
    if {$path eq ""} return
    if {[catch {_datasetMetadataEditorExportFile $path} err]} {
        tk_messageBox -parent .top.nb.channels.metadataEditor -icon error -type ok -title "Dataset metadata" -message $err
        return
    }
    setStatus "Dataset metadata exported without saving the Dataset." 100
}

proc ::GX::datasetMetadataEditorSave {} {
    variable currentSession
    variable datasetMetadataEditorDataset
    variable datasetMetadataEditorData
    if {[catch {datasetPageEditorRequire metadata;_datasetMetadataUserSave $currentSession $datasetMetadataEditorDataset $datasetMetadataEditorData} err]} {
        tk_messageBox -parent .top.nb.channels.metadataEditor -icon error -type ok -title "Dataset metadata" -message $err
        return 0
    }
    setStatus "Structured metadata saved for dataset $datasetMetadataEditorDataset." 100
    datasetPageEditorEnd metadata
    return 1
}

proc ::GX::datasetMetadataEditorOpen {datasetId} {
    variable currentSession
    variable datasetMetadataEditorDataset
    variable datasetMetadataEditorData
    variable datasetMetadataEditorKey
    if {[catch {set metadata [datasetMetadataUserFields $currentSession $datasetId]} err]} {
        tk_messageBox -parent .top -icon error -type ok -title "Dataset metadata" -message $err
        return
    }
    datasetPageBuildViews
    if {[catch {datasetPageEditorBegin metadata $datasetId} message]} {setStatus $message 100;return}
    set datasetMetadataEditorDataset $datasetId
    set datasetMetadataEditorData $metadata
    set datasetMetadataEditorKey ""
    set w .top.nb.channels.metadataEditor
    catch {destroy $w}
    ttk::frame $w
    pack forget .top.nb.channels.metadata
    pack $w -in .top.nb.channels.views.metadata -fill both -expand 1
    raise $w
    .top.nb select .top.nb.channels
    .top.nb.channels.views select .top.nb.channels.views.metadata
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 1 -weight 1
    ttk::label $w.heading -text "Dataset: $datasetId    User metadata (producer and unclassified fields remain read-only)" -anchor w
    grid $w.heading -row 0 -column 0 -sticky ew -padx 10 -pady 8

    ttk::frame $w.table
    ttk::treeview $w.table.tree -columns {key value} -show headings -selectmode browse
    $w.table.tree heading key -text "Key"
    $w.table.tree heading value -text "Value"
    $w.table.tree column key -width 230 -stretch 1
    $w.table.tree column value -width 390 -stretch 1
    ttk::scrollbar $w.table.scroll -orient vertical -command [list $w.table.tree yview]
    $w.table.tree configure -yscrollcommand [list $w.table.scroll set]
    grid $w.table.tree -row 0 -column 0 -sticky nsew
    grid $w.table.scroll -row 0 -column 1 -sticky ns
    grid columnconfigure $w.table 0 -weight 1
    grid rowconfigure $w.table 0 -weight 1
    grid $w.table -row 1 -column 0 -sticky nsew -padx 10
    bind $w.table.tree <<TreeviewSelect>> ::GX::datasetMetadataEditorSelect

    ttk::labelframe $w.edit -text "Field"
    ttk::label $w.edit.keyLabel -text "Namespaced key:"
    ttk::entry $w.edit.key -textvariable ::GX::datasetMetadataEditorKey
    ttk::label $w.edit.valueLabel -text "Value:"
    text $w.edit.value -height 4 -wrap word
    ttk::button $w.edit.put -text "Add/update field" -command ::GX::datasetMetadataEditorPut
    ttk::button $w.edit.remove -text "Remove field" -command ::GX::datasetMetadataEditorRemove
    grid $w.edit.keyLabel -row 0 -column 0 -sticky w -padx 6 -pady 4
    grid $w.edit.key -row 0 -column 1 -columnspan 2 -sticky ew -padx 6 -pady 4
    grid $w.edit.valueLabel -row 1 -column 0 -sticky nw -padx 6 -pady 4
    grid $w.edit.value -row 1 -column 1 -columnspan 2 -sticky ew -padx 6 -pady 4
    grid $w.edit.put -row 2 -column 1 -sticky w -padx 6 -pady 6
    grid $w.edit.remove -row 2 -column 2 -sticky e -padx 6 -pady 6
    grid columnconfigure $w.edit 1 -weight 1
    grid $w.edit -row 2 -column 0 -sticky ew -padx 10 -pady 8

    ttk::frame $w.buttons
    ttk::button $w.buttons.import -text "Import..." -command ::GX::datasetMetadataEditorImport
    ttk::button $w.buttons.export -text "Export..." -command ::GX::datasetMetadataEditorExport
    ttk::button $w.buttons.bulk -text "Add multiple fields..." -command ::GX::datasetMetadataEditorBulkOpen
    ttk::button $w.buttons.save -text "Save" -command ::GX::datasetMetadataEditorSave
    ttk::button $w.buttons.close -text "Cancel" -command {::GX::datasetPageEditorEnd metadata}
    pack $w.buttons.import $w.buttons.export $w.buttons.bulk -side left -padx 5
    pack $w.buttons.close $w.buttons.save -side right -padx 5
    grid $w.buttons -row 3 -column 0 -sticky ew -padx 10 -pady {0 10}
    datasetMetadataEditorRender
}

proc ::GX::datasetMetadataEditorBulkClose {} {
    set panel .top.nb.channels.metadataEditor.bulk
    if {[winfo exists $panel]} {grid remove $panel}
    focus .top.nb.channels.metadataEditor.buttons.bulk
}

proc ::GX::datasetMetadataEditorBulkApply {} {
    variable datasetMetadataEditorData
    variable datasetMetadataBulkStatus
    set panel .top.nb.channels.metadataEditor.bulk
    if {[catch {set parsed [datasetMetadataParseText [$panel.text get 1.0 end-1c]]} reason]} {
        set datasetMetadataBulkStatus $reason
        focus $panel.text
        return 0
    }
    set existing 0
    foreach key [dict keys $parsed] {if {[dict exists $datasetMetadataEditorData $key]} {incr existing}}
    # Validation above is complete; one in-memory assignment applies the block.
    set datasetMetadataEditorData [dict merge $datasetMetadataEditorData $parsed]
    datasetMetadataEditorRender
    datasetMetadataEditorSelect
    set count [dict size $parsed]
    set datasetMetadataBulkStatus "Parsed: $count fields. New: [expr {$count-$existing}]. Updated: $existing. Press Save to persist."
    return 1
}

proc ::GX::datasetMetadataEditorBulkOpen {} {
    variable datasetMetadataBulkStatus
    set w .top.nb.channels.metadataEditor
    set panel $w.bulk
    if {![winfo exists $panel]} {
        set datasetMetadataBulkStatus "Paste key=value, one field per line. Apply changes the editor; Save persists."
        ttk::labelframe $panel -text "Add multiple metadata fields"
        ttk::label $panel.help -text "First = separates key and value. Later = and : remain in the value." -wraplength 300
        text $panel.text -width 35 -height 12 -wrap word -undo 1
        ttk::scrollbar $panel.scroll -orient vertical -command [list $panel.text yview]
        $panel.text configure -yscrollcommand [list $panel.scroll set]
        ttk::label $panel.status -textvariable ::GX::datasetMetadataBulkStatus -wraplength 300
        ttk::frame $panel.actions
        ttk::button $panel.actions.apply -text "Apply" -command ::GX::datasetMetadataEditorBulkApply
        ttk::button $panel.actions.clear -text "Clear" -command [list $panel.text delete 1.0 end]
        ttk::button $panel.actions.close -text "Close panel" -command ::GX::datasetMetadataEditorBulkClose
        pack $panel.actions.apply $panel.actions.clear $panel.actions.close -side left -padx 4 -pady 5
        grid $panel.help -row 0 -column 0 -columnspan 2 -sticky ew -padx 6 -pady 6
        grid $panel.text -row 1 -column 0 -sticky nsew -padx {6 0}
        grid $panel.scroll -row 1 -column 1 -sticky ns -padx {0 6}
        grid $panel.status -row 2 -column 0 -columnspan 2 -sticky ew -padx 6 -pady 6
        grid $panel.actions -row 3 -column 0 -columnspan 2 -sticky ew
        grid rowconfigure $panel 1 -weight 1
        grid columnconfigure $panel 0 -weight 1
        bind $panel.text <Escape> {::GX::datasetMetadataEditorBulkClose; break}
    }
    # Use a lower embedded pane so narrow displays keep the original Save row.
    grid $panel -row 4 -column 0 -sticky nsew -padx 10 -pady {0 10}
    grid rowconfigure $w 4 -weight 1
    focus $panel.text
}

proc ::GX::datasetMetadataOpenSelectedFromGui {} {
    variable variableDatasetChoice
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode datasetId
    if {$mode ne "imported" || $datasetId eq ""} return
    datasetMetadataEditorOpen $datasetId
}
source [file join [file dirname [info script]] dataset_metadata_origins_v1.tcl]
