# GX-TXT Session Inspection API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only, structured Session snapshot for exporters and archival tools.

namespace eval ::GX { variable sessionInspectionApiVersion 1 }

proc ::GX::_sessionInspectionRequire {{session ""}} {
    variable currentSession
    if {$session eq ""} { set session $currentSession }
    if {$session eq "" || ![file isdirectory $session]} { error "Session Inspection API requires an open or existing Session." }
    set session [file normalize $session]
    if {![file isfile [file join $session metadata manifest.ini]]} { error "Session is missing metadata/manifest.ini." }
    return $session
}

# Public current-Session context for modules that must create Session-owned
# resources. This returns a validated path, not a mutable CORE registry.
proc ::GX::sessionInspectionCurrentSession {} {
    return [_sessionInspectionRequire]
}

proc ::GX::sessionInspectionResolveResource {relative {session ""} {expectedSha ""}} {
    set session [_sessionInspectionRequire $session]
    if {$relative eq "" || [file pathtype $relative] ne "relative" || [regexp {[\r\n]} $relative]} {
        error "Session resource path must be nonempty and relative"
    }
    set path [file normalize [file join $session $relative]]
    if {![string match "$session/*" $path]} {error "Session resource escapes the Session"}
    set canonical [string range $path [expr {[string length $session]+1}] end]
    set probe $session
    foreach component [file split $canonical] {
        set probe [file join $probe $component]
        if {[file exists $probe] && [file type $probe] eq "link"} {
            error "Session resource symlinks are not allowed"
        }
    }
    if {![file isfile $path]} {error "Session resource does not exist: $canonical"}
    set digest [string tolower [sha256File $path]]
    if {$expectedSha ne ""} {
        if {![regexp {^[0-9a-fA-F]{64}$} $expectedSha] ||
            ![string equal -nocase $digest $expectedSha]} {
            error "Session resource SHA-256 mismatch"
        }
    }
    return [dict create path $path relative_path $canonical sha256 $digest size_bytes [file size $path]]
}

proc ::GX::_sessionInspectionSelectionRecords {session} {
    set path [file join $session metadata dataset_selections.ini]
    if {![file isfile $path]} {return [dict create]}
    set ini [parseIni $path]
    set ids [expr {[dict exists $ini dataset_selection_api.ids] ?
        [splitList [dict get $ini dataset_selection_api.ids]] : {}}]
    set records [dict create]
    foreach id $ids {
        if {![regexp {^sel_[0-9]+$} $id]} {error "Invalid Dataset Selection ID '$id'"}
        set prefix "dataset_selection.$id."
        set record [dict create]
        foreach key [dict keys $ini] {
            if {[string first $prefix $key] != 0} continue
            dict set record [string range $key [string length $prefix] end] [dict get $ini $key]
        }
        if {![dict exists $record id] || [dict get $record id] ne $id} {
            error "Dataset Selection '$id' has mismatched registry identity"
        }
        dict set records $id $record
    }
    return $records
}

proc ::GX::sessionInspectionSelectionIds {{session ""}} {
    return [lsort -dictionary [dict keys [_sessionInspectionSelectionRecords [_sessionInspectionRequire $session]]]]
}

proc ::GX::sessionInspectionSelection {selectionId {session ""}} {
    set records [_sessionInspectionSelectionRecords [_sessionInspectionRequire $session]]
    if {![dict exists $records $selectionId]} {error "Unknown Dataset Selection '$selectionId'"}
    return [dict get $records $selectionId]
}

proc ::GX::_sessionInspectionB64 {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}

proc ::GX::_sessionInspectionWriteRec {fd category object field value} {
    puts $fd "REC\t$category\t[_sessionInspectionB64 $object]\t[_sessionInspectionB64 $field]\t[_sessionInspectionB64 $value]"
}

proc ::GX::_sessionInspectionFiles {session {dir ""}} {
    if {$dir eq ""} { set dir $session }
    set out {}
    foreach p [lsort -dictionary [glob -nocomplain -directory $dir * .*]] {
        set tail [file tail $p]
        if {$tail in {. ..}} continue
        if {[file type $p] eq "link"} {
            # Exporters see the link as an artifact/reference; they never follow
            # directory links through this inspection API.
            if {[file isfile $p]} { lappend out $p }
            continue
        }
        if {[file isdirectory $p]} { lappend out {*}[::GX::_sessionInspectionFiles $session $p] } elseif {[file isfile $p]} { lappend out $p }
    }
    return $out
}

proc ::GX::sessionInspectionSummary {{session ""}} {
    variable version
    set session [_sessionInspectionRequire $session]
    set mf [parseIni [file join $session metadata manifest.ini]]
    set out [dict create session_name [file tail $session] framework_version $version]
    foreach {key manifestKey} {
        experiment_name experiment.name
        experiment_project experiment.project
        experiment_date experiment.date
        experiment_operator experiment.operator
        experiment_tags experiment.tags
        experiment_objective experiment.objective
    } {
        dict set out $key [expr {[dict exists $mf $manifestKey] ? [dict get $mf $manifestKey] : ""}]
    }
    return $out
}

proc ::GX::sessionInspectionDatasetIds {{session ""}} {
    set session [_sessionInspectionRequire $session]
    return [lsort -dictionary [dict keys [_sessionInspectionDatasetRecords $session]]]
}

proc ::GX::sessionInspectionDataset {datasetId {session ""}} {
    set session [_sessionInspectionRequire $session]
    set records [_sessionInspectionDatasetRecords $session]
    if {![dict exists $records $datasetId]} { error "Dataset '$datasetId' is not registered in the Session." }
    return [dict get $records $datasetId]
}

proc ::GX::_sessionInspectionDatasetRecords {session} {
    set path [file join $session metadata datasets.ini]
    if {![file isfile $path]} { return [dict create] }
    set fd [open $path r]
    fconfigure $fd -encoding utf-8
    set sectionId ""
    set records [dict create]
    try {
        while {[gets $fd line] >= 0} {
            set line [string trim $line]
            if {$line eq "" || [string match ";*" $line] || [string match "#*" $line]} continue
            if {[regexp {^\[(.+)\]$} $line -> section]} {
                set sectionId ""
                if {[string match "dataset.*" $section]} {
                    set sectionId [string range $section [string length "dataset."] end]
                }
                continue
            }
            if {$sectionId ne "" && [regexp {^([^=]+)=(.*)$} $line -> field value]} {
                dict set records $sectionId [string trim $field] [iniUnescape $value]
            }
        }
    } finally { close $fd }
    set result [dict create]
    dict for {id fields} $records {
        if {![dict exists $fields id]} continue
        if {[dict get $fields id] ne $id} {
            error "Dataset registry section 'dataset.$id' has mismatched ID '[dict get $fields id]'."
        }
        dict set result $id $fields
    }
    return $result
}

# Public, read-only canonical payload resolution for presentation modules.
# An opaque Dataset may not support numeric Dataset Access, but its original
# Session-owned payload is still available with identity and digest checks.
# Cheap guarded availability for Info; Payload remains the integrity-verifying reader.
proc ::GX::sessionInspectionDatasetLocation {datasetId {session ""}} {
    set session [_sessionInspectionRequire $session]
    set record [sessionInspectionDataset $datasetId $session]
    if {![dict exists $record path]} { error "Dataset '$datasetId' has no payload path." }
    set relative [dict get $record path]
    if {$relative eq "" || [file pathtype $relative] ne "relative" ||
        [regexp {[\r\n]} $relative]} { error "Dataset '$datasetId' payload is not Session-relative." }
    set path [file normalize [file join $session $relative]]
    if {![string match "$session/*" $path]} { error "Dataset '$datasetId' payload escapes the Session." }
    set probe $session
    foreach component [file split [string range $path [expr {[string length $session]+1}] end]] {
        set probe [file join $probe $component]
        if {[file exists $probe] && [file type $probe] eq "link"} {
            error "Dataset '$datasetId' payload contains a symlink."
        }
    }
    if {![file isfile $path]} { error "Dataset '$datasetId' payload is missing: $relative" }
    set expected [expr {[dict exists $record canonical_sha256] ? [dict get $record canonical_sha256] : ""}]
    if {![regexp {^[0-9a-fA-F]{64}$} $expected]} {
        error "Dataset '$datasetId' has no canonical SHA-256."
    }
    return [dict create dataset_id $datasetId path $path relative_path $relative expected_sha256 [string tolower $expected] size_bytes [file size $path] format [dict get $record format] contract [datasetPublicationV2DictDefault $record kind {}] integrity not_checked]
}
proc ::GX::sessionInspectionDatasetPayload {datasetId {session ""}} {
    set session [_sessionInspectionRequire $session]
    set record [sessionInspectionDataset $datasetId $session]
    if {[datasetPublicationV2DictDefault $record storage_provider {}] eq "remote"} {
        set origin [_datasetRemoteVerifyRecord $datasetId $record]
        return [dict create dataset_id $datasetId path {} relative_path {} sha256 [dict get $origin sha256] format [dict get $record format] contract [datasetPublicationV2DictDefault $record kind {}] remote_source $origin]
    }
    set result [sessionInspectionDatasetLocation $datasetId $session]
    if {![string equal -nocase [sha256File [dict get $result path]] [dict get $result expected_sha256]]} {error "Dataset '$datasetId' payload SHA-256 mismatch."}
    return [dict create dataset_id $datasetId path [dict get $result path] relative_path [dict get $result relative_path] sha256 [dict get $result expected_sha256] format [dict get $result format] contract [dict get $result contract]]
}

proc ::GX::sessionInspectionFileInventory {{session ""}} {
    set session [_sessionInspectionRequire $session]
    set out {}
    foreach p [_sessionInspectionFiles $session] {
        set n [file normalize $p]
        set root [file normalize $session]
        if {[string first "$root/" "$n/"] != 0} continue
        set rel [string range $n [expr {[string length $root]+1}] end]
        lappend out [dict create path $rel size [file size $p] sha256 [sha256File $p] extension [string tolower [file extension $p]]]
    }
    return $out
}

proc ::GX::sessionInspectionWriteSnapshot {path {session ""}} {
    set session [_sessionInspectionRequire $session]
    set path [file normalize $path]
    file mkdir [file dirname $path]
    set tmp "$path.tmp.[pid].[clock clicks]"
    set fd [open $tmp w]
    fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "GXTXT_SESSION_INSPECTION_V1"
    set summary [sessionInspectionSummary $session]
    dict for {k v} $summary { _sessionInspectionWriteRec $fd session "" $k $v }

    set manifest [parseIni [file join $session metadata manifest.ini]]
    dict for {k v} $manifest { _sessionInspectionWriteRec $fd manifest "" $k $v }

    foreach id [sessionInspectionDatasetIds $session] {
        set ds [sessionInspectionDataset $id $session]
        dict for {k v} $ds { _sessionInspectionWriteRec $fd dataset $id $k $v }
        if {[llength [info commands ::GX::datasetMetadataRead]]} {
            if {![catch {set meta [datasetMetadataRead $session $id]}]} {
                dict for {k v} $meta { _sessionInspectionWriteRec $fd dataset_metadata $id $k $v }
            }
        }
        if {[llength [info commands ::GX::datasetUserNotes]]} {
            if {![catch {set note [datasetUserNotes $id]}] && $note ne ""} { _sessionInspectionWriteRec $fd dataset_note $id markup $note }
        }
    }
    if {[llength [info commands ::GX::scriptRegistryList]]} {
        foreach script [scriptRegistryList session $session] {
            set id [dict get $script id]
            foreach key {id name language scope description version revision sha256 required_apis source_scope source_id source_sha256 created_at updated_at} {
                _sessionInspectionWriteRec $fd script $id $key [dict get $script $key]
            }
            dict for {name descriptor} [dict get $script parameters] {
                foreach key {type required default description} {
                    _sessionInspectionWriteRec $fd script $id "parameter.$name.$key" [dict get $descriptor $key]
                }
            }
        }
    }
    foreach runDir [lsort -dictionary [glob -nocomplain -types d -directory [file join $session analysis scripts] *]] {
        set report [file join $runDir execution.ini]
        if {![file isfile $report]} continue
        set runId [file tail [file dirname $report]]
        set execution [parseIni $report]
        dict for {key value} $execution {
            _sessionInspectionWriteRec $fd script_execution $runId $key $value
        }
    }
    foreach moduleDir [lsort -dictionary [glob -nocomplain -types d -directory [file join $session metadata documentation] *]] {
        foreach snapshotDir [lsort -dictionary [glob -nocomplain -types d -directory $moduleDir *]] {
            set report [file join $snapshotDir record.ini]
            set manual [file join $snapshotDir manual.md]
            if {![file isfile $report] || ![file isfile $manual]} continue
            set record [parseIni $report]
            if {![dict exists $record documentation.sha256] || [dict get $record documentation.sha256] ne [sha256File $manual]} continue
            set identity "[file tail $moduleDir]/[file tail $snapshotDir]"
            dict for {key value} $record {
                _sessionInspectionWriteRec $fd module_documentation $identity $key $value
            }
            _sessionInspectionWriteRec $fd module_documentation $identity manual_path \
                "metadata/documentation/[file tail $moduleDir]/[file tail $snapshotDir]/manual.md"
        }
    }
    foreach rec [sessionInspectionFileInventory $session] {
        set rel [dict get $rec path]
        foreach k {size sha256 extension} { _sessionInspectionWriteRec $fd file $rel $k [dict get $rec $k] }
    }
    close $fd
    file rename -force -- $tmp $path
    return $path
}
# Additive bounded read-only Markdown discovery for Project Info; scientific
# payloads are never hashed merely to list a Session's documents.
proc ::GX::sessionInspectionMarkdownDocuments {{session {}}} {
    set session [_sessionInspectionRequire $session];set out {}
    foreach path [_sessionInspectionFiles $session] {
        if {[string tolower [file extension $path]] ne {.md}} continue
        set relative [string range $path [expr {[string length $session]+1}] end]
        if {[catch {set info [sessionInspectionResolveResource $relative $session]} reason]} {
            lappend out [dict create path $relative status unavailable diagnostic $reason size 0 sha256 {} extension .md]
        } else {
            lappend out [dict create path $relative status verified size [dict get $info size_bytes] sha256 [dict get $info sha256] extension .md]
        }
    }
    return $out
}

# Read-only typed result projection of existing authorities, not a Results store.
proc ::GX::sessionInspectionResults {session {offset 0} {limit 500}} {
    set session [_sessionInspectionRequire $session]
    if {![string is integer -strict $offset] || $offset<0 || ![string is integer -strict $limit] || $limit<1 || $limit>1000} {error {Results query requires offset >= 0 and limit 1..1000}}
    set imports {};set scriptImports {}
    foreach path [lrange [lsort [glob -nocomplain -directory [file join $session metadata acquisitions] *.tcldict]] 0 9999] {
        if {[file type $path] ne {file} || [file size $path]>65536} continue
        set fd [open $path];fconfigure $fd -encoding utf-8;try {set receipt [read $fd]} finally {close $fd}
        if {[catch {dict get $receipt schema} schema] || $schema ne {gxtxt.acquisition_receipt.v1}} continue
        foreach output [dict get $receipt outputs] {if {[string match session:* $output]} {lappend scriptImports $receipt} else {dict lappend imports $output $receipt}}
    }
    set rows {};set records [_sessionInspectionDatasetRecords $session]
    foreach id [lsort -dictionary [dict keys $records]] {
        set dataset [dict get $records $id]
        set producer [datasetPublicationV2DictDefault $dataset producer_module [datasetPublicationV2DictDefault $dataset source_module unknown]]
        set category [expr {[moduleField $producer kind {}] eq {acquisition} ? {Acquisition/import} : ([moduleField $producer kind {}] eq {analysis} ? {Analysis} : ([moduleField $producer kind {}] eq {viewer} ? {Viewer publications} : {Canonical Datasets}))}]
        set receipt [dict create id dataset:$id category $category name $id type [datasetPublicationV2DictDefault $dataset contract [datasetPublicationV2DictDefault $dataset kind {}]] producer $producer state {Registered canonical output} dataset_id $id session $session timestamp [datasetPublicationV2DictDefault $dataset created_at {}] summary $dataset origin user_scientific]
        if {$category eq {Acquisition/import}} {
            if {[dict exists $imports $id]} {dict set receipt summary import_outcomes [dict get $imports $id];dict set receipt state {Import completed; canonical output registered}} else {dict set receipt historical_operation_status {Publication verified by Registry; historical import operation status is not independently recorded}}
        }
        lappend rows $receipt
    }
    foreach receipt $scriptImports {
        lappend rows [dict create id acquisition:[dict get $receipt id] category Acquisition/import name [join [dict get $receipt outputs] {, }] type session_script producer [dict get $receipt module_id] state [dict get $receipt state] session $session timestamp [dict get $receipt timestamp] summary $receipt origin user_scientific]
    }
    # Inspect only descriptor-declared reports, never a recursive technical tree.
    foreach module $::GX::moduleOrder {
        if {[moduleField $module kind {}] ne {analysis}} continue
        foreach name [splitList [moduleExpectedOutputs $module]] {
            if {![regexp {(_report\.(txt|md|html)|_summary\.ini)$} $name]} continue
            set relative [file join analysis [sanitize $module] $name]
            if {[catch {sessionInspectionResolveResource $relative $session} verified]} continue
            set path [dict get $verified path]
            set fd [open $path];fconfigure $fd -encoding utf-8;try {set content [read $fd 32768];set truncated [expr {![eof $fd]}]} finally {close $fd}
            lappend rows [dict create id analysis:$module:$name category Analysis name "[moduleField $module name] — $name" type scientific_report producer $module state {Declared report available} session $session timestamp [clock format [file mtime $path] -format {%Y-%m-%dT%H:%M:%S%z}] summary [dict create relative_path $relative sha256 [dict get $verified sha256] text $content truncated $truncated] origin user_scientific]
        }
    }
    foreach run [scriptExecutionRunSummaries $session] {
        if {[datasetPublicationV2DictDefault $run origin user_script] eq {core_service}} continue
        set id [dict get $run id]
        set category {User Script Jobs};set producer [datasetPublicationV2DictDefault $run reference unknown]
        if {[datasetPublicationV2DictDefault $run origin user_script] eq {scientific_provider}} {set category {Scientific Jobs};set producer SCIENTIFIC_EXECUTION_API_v1;dict unset run reference}
        lappend rows [dict create id script:$id category $category name [datasetPublicationV2DictDefault $run script_name $id] type script_job producer $producer state [datasetPublicationV2DictDefault $run state {not recorded}] job_id $id session $session timestamp [datasetPublicationV2DictDefault $run started {}] summary $run origin user_script]
    }
    set total [llength $rows]
    return [dict create api_id SESSION_INSPECTION_API_v1 projection user_results session $session offset $offset limit $limit total $total records [lrange $rows $offset [expr {$offset+$limit-1}]] has_next [expr {$offset+$limit<$total}] classification_owner {Dataset provenance / Script Job inspection}]
}
