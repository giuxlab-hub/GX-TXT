# GX-TXT Portable Resource API v1. Host/plugin operations only.
# Resource packages use the Portable Session helper's path, symlink and SHA
# rules; all content is validated in a private staging area before commit.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable portableResourceApiVersion 1 }

proc ::GX::_portableResourceHelper {} {
    variable scriptDir
    set path [file join $scriptDir core python portable_resource_v1.py]
    if {![file isfile $path]} {error "Portable Resource helper is missing"}
    return $path
}
proc ::GX::_portableResourceRun {args} {
    set command [list [runtimeToolRequired python] [_portableResourceHelper] {*}$args]
    if {[catch {set output [exec {*}$command 2>@1]} message options]} {
        return -options $options $message
    }
    return $output
}
proc ::GX::_portableResourceFields {path {schema 0} {graph 0}} {
    set operation [expr {$graph ? "emit-graph-state" : ($schema ? "emit-schema" : "emit-fields")}]
    set output [_portableResourceRun $operation $path]
    set result [dict create]
    foreach line [split $output "\n"] {
        if {$line eq ""} continue
        set columns [split $line "\t"]
        if {[llength $columns] != ($schema ? 3 : 2)} {error "Invalid Portable Resource field response"}
        if {$schema} {lassign $columns index key encoded;set key "var${index}_$key"} else {lassign $columns key encoded}
        dict set result $key [encoding convertfrom utf-8 [binary decode base64 $encoded]]
    }
    return $result
}
proc ::GX::portableResourceValidate {archive} {
    set archive [file normalize $archive]
    if {![file isfile $archive]} {error "Portable Resource archive does not exist"}
    return [_sessionPortableParseOutput [_portableResourceRun inspect $archive]]
}
proc ::GX::portableResourceInspect {archive} {portableResourceValidate $archive}
proc ::GX::portableResourceExportDataset {datasetId archive} {
    variable currentSession
    variable version
    set session [_sessionPortableRequireSession]
    if {$session ne [file normalize $currentSession]} {error "Open the source Session first"}
    if {[datasetField $datasetId id ""] eq ""} {error "Unknown Dataset '$datasetId'"}
    set archive [file normalize $archive]
    if {![string match *.zip [string tolower $archive]]} {append archive .gxtxt-dataset.zip}
    return [_sessionPortableParseOutput [_portableResourceRun export-dataset $session $datasetId $archive $version]]
}
proc ::GX::_portableResourceWriteStateField {fd key value} {
    if {[regexp {[\r\n]} $key]} {error "Invalid graph state key"}
    puts $fd "$key\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]"
}
proc ::GX::portableResourceExportGraph {artifact archive} {
    variable currentSession
    variable version
    set session [_sessionPortableRequireSession]
    if {$session ne [file normalize $currentSession]} {error "Open the source Session first"}
    if {![catch {dict size $artifact}] && ([dict exists $artifact module_id] || [dict exists $artifact clone_id])} {
        set reference [graphResourceRef $artifact]
        if {[dict get $reference kind] eq "provider"} {
            set artifact [graphAxisArtifactPath [dict get $reference module_id] [dict get $reference graph_id] [dict get $reference variant_id]]
        } else {set artifact [file join [::GX::PlotClone::root] [dict get $reference clone_id] graph.png]}
    }
    set artifact [file normalize $artifact]
    if {![::GX::PlotClone::validPng $artifact]} {error "Select a valid Session graph PNG"}
    set ref [graphResourceRefForPath $artifact]
    set state [dict create kind [dict get $ref kind] module_id "" graph_id "" variant_id "" clone_id "" use 1 title "" capture_mode rendered]
    set dependencies {}
    if {[dict get $ref kind] eq "provider"} {
        set mid [dict get $ref module_id];set gid [dict get $ref graph_id];set vid [dict get $ref variant_id]
        foreach field {module_id graph_id variant_id} {dict set state $field [dict get $ref $field]}
        dict set state source_module_version [moduleField $mid version ""]
        dict set state title [moduleGraphField $mid $gid title $gid]
        dict set state use [graphUseStateGet $mid $gid $vid]
        set axis [graphAxisConfigSnapshot $mid $gid $vid]
        if {$mid eq "plot.dataset"} {
            foreach row [graphSeriesList $mid $gid $vid 1] {
                lappend dependencies [dict get $row dataset_id]
            }
        }
    } else {
        dict set state clone_id [dict get $ref clone_id]
        set cloneInfo [::GX::PlotClone::infoForPath $artifact]
        dict set state module_id [dict get $cloneInfo clone.source_module]
        dict set state graph_id [dict get $cloneInfo clone.source_graph]
        dict set state variant_id [dict get $cloneInfo clone.source_variant]
        dict set state source_module_version [dict get $cloneInfo clone.source_module_version]
        dict set state capture_mode [dict get $cloneInfo clone.capture_mode]
        dict set state title [graphDisplayTitle $artifact]
        dict set state use [::GX::PlotClone::useForPath $artifact]
        set axis [dict create]
        set dependencies [split [dict get $cloneInfo clone.source_dataset_ids] {;}]
    }
    set statePath [file join $session metadata ".portable_graph_state_[pid]_[clock clicks].tsv"]
    set scientific [file join $session metadata ".portable_graph_scientific_[pid]_[clock clicks]"]
    set fd [open $statePath w]
    try {
        fconfigure $fd -encoding utf-8 -translation lf
        dict for {field value} $state {_portableResourceWriteStateField $fd $field $value}
        dict for {field value} $axis {_portableResourceWriteStateField $fd "axis.$field" $value}
        if {[dict get $ref kind] eq "provider" && [dict get $ref module_id] eq "plot.dataset"} {
            set rowIndex 0
            foreach row [graphSeriesList $mid $gid $vid 1] {
                incr rowIndex
                foreach field {series_id dataset_id x_variable_id y_variable_id axis enabled label order row_filters secondary_variable_id ordering_variable_id} {
                    if {[dict exists $row $field]} {_portableResourceWriteStateField $fd "series.$rowIndex.$field" [dict get $row $field]}
                }
            }
        }
    } finally {close $fd}
    set note [graphResourcePath $ref note];if {![file isfile $note]} {set note ""}
    set metadata [graphResourcePath $ref metadata];if {![file isfile $metadata]} {set metadata ""}
    set annotation [annotationPathForPlot $artifact];if {![file isfile $annotation]} {set annotation ""}
    set renderMeta [plotRegionMetadataPath $artifact];if {![file isfile $renderMeta]} {set renderMeta ""}
    set snapshot ""
    if {[dict get $ref kind] eq "clone" && [dict get $state capture_mode] eq "scientific"} {
        file mkdir $scientific
        foreach item {snapshot.h5 presentation.ini private_session} {
            file copy -force -- [file join [file dirname $artifact] $item] [file join $scientific $item]
        }
        set snapshot $scientific
    } elseif {[dict get $ref kind] eq "provider" && [dict get $ref module_id] eq "plot.dataset"} {
        if {![catch {
            modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
            ::GX::PlotDatasetAPIv3::captureForArtifact $artifact $scientific
        } scientificError]} {
            set snapshot $scientific
            dict set state capture_mode scientific
            # Update the state transport after a successful scientific capture.
            set fd [open $statePath a]
            try {fconfigure $fd -encoding utf-8 -translation lf;_portableResourceWriteStateField $fd capture_mode scientific} finally {close $fd}
        }
    }
    set archive [file normalize $archive]
    if {![string match *.zip [string tolower $archive]]} {append archive .gxtxt-graph.zip}
    try {
        return [_sessionPortableParseOutput [_portableResourceRun export-graph $session $artifact $statePath $note $metadata $annotation $renderMeta $snapshot [join [lsort -unique $dependencies] {;}] $archive $version]]
    } finally {
        catch {file delete -force -- $statePath}
        catch {file delete -force -- $scientific}
    }
}
proc ::GX::_portableResourceImportDataset {staging {newId ""} {prefix dataset}} {
    if {![datasetAuthorityActive $::GX::currentSession]} {return [datasetAuthorityTransaction $::GX::currentSession ::GX::_portableResourceImportDataset $staging $newId $prefix]}
    variable currentSession
    variable datasetRegistry
    set root [file join $staging $prefix]
    set registry [_portableResourceFields [file join $root registry.json]]
    set schema [_portableResourceFields [file join $root schema.json] 1]
    set sourceId [dict get $registry id]
    if {$newId eq ""} {set newId $sourceId}
    datasetPublicationV2ValidateId dataset $newId
    if {[datasetField $newId id ""] ne ""} {error "Dataset ID '$newId' already exists"}
    set payloads [glob -nocomplain -types f [file join $root payload *]]
    if {[llength $payloads] != 1} {error "Dataset package has no unique canonical payload"}
    set payload [lindex $payloads 0]
    set extension [file extension $payload]
    if {$extension eq ""} {set extension .dat}
    set relative [file join datasets imported "${newId}${extension}"]
    set final [file join $currentSession $relative]
    if {[file exists $final]} {error "Imported Dataset payload target already exists"}
    set snapshot [lindex [glob -nocomplain -types f [file join $root schema_source *]] 0]
    set snapshotTarget ""
    if {$snapshot ne ""} {
        set snapshotTarget [file join $currentSession metadata schema_sources "${newId}_[file tail $snapshot]"]
        if {[file exists $snapshotTarget]} {error "Imported schema-source target already exists"}
    }
    set metadataPath [file join $root metadata.json]
    set notePath [file join $root notes.md]
    set noteTarget [datasetNotePath $newId $currentSession]
    if {[file exists $noteTarget]} {error "Imported Dataset Notes target already exists"}
    set metadataTarget [file join $currentSession metadata datasets "${newId}.ini"]
    if {[file exists $metadataTarget]} {error "Imported Dataset Metadata target already exists"}
    set registryPath [datasetRegistryPath $currentSession]
    set manifestPath [file join $currentSession metadata manifest.ini]
    set prior [array get datasetRegistry]
    set registryExisted [file isfile $registryPath]
    set manifestExisted [file isfile $manifestPath]
    set registryBackup "${registryPath}.portable.[pid].[clock clicks].backup"
    set manifestBackup "${manifestPath}.portable.[pid].[clock clicks].backup"
    if {[file isfile $registryPath]} {file copy -- $registryPath $registryBackup}
    if {[file isfile $manifestPath]} {file copy -- $manifestPath $manifestBackup}
    foreach resource [list $registryPath $manifestPath $final $metadataTarget $noteTarget $snapshotTarget] {
        if {$resource ne {}} {datasetAuthorityEnlist $resource}
    }
    set committed 0
    try {
        file mkdir [file dirname $final]
        file copy -- $payload $final
        if {[sha256File $final] ne [dict get $registry canonical_sha256]} {error "Imported payload SHA-256 mismatch"}
        dict set registry id $newId
        dict set registry path $relative
        dict set registry structured_metadata_file [file join metadata datasets "${newId}.ini"]
        # A renamed import owns its new note resource. Keeping the exported
        # source path would make later rename/delete target the source note or
        # leave the imported note orphaned in the same Session.
        if {[file isfile $notePath]} {
            dict set registry user_notes_file [datasetNoteRelativePath $newId]
        } else {
            catch {dict unset registry user_notes_file}
        }
        if {$snapshotTarget ne ""} {
            file mkdir [file dirname $snapshotTarget]
            file copy -- $snapshot $snapshotTarget
            dict set registry schema_source_snapshot [file join metadata schema_sources [file tail $snapshotTarget]]
        } else {
            catch {dict unset registry schema_source_snapshot}
            catch {dict unset registry schema_source_snapshot_sha256}
        }
        if {$newId ne $sourceId && [dict exists $registry source_dataset_ids]} {
            set ids [split [dict get $registry source_dataset_ids] {;}]
            set mapped {}
            foreach id $ids {lappend mapped [expr {$id eq $sourceId ? $newId : $id}]}
            dict set registry source_dataset_ids [join $mapped {;}]
        }
        datasetRegister $newId [concat $registry $schema]
        foreach variable [datasetVariableSchema $newId] {
            set canonicalUnit [dict get $variable canonical_unit]
            set forward [dict get $variable to_canonical]
            set inverse [dict get $variable from_canonical]
            if {$canonicalUnit ne "" && ($forward eq "" || $inverse eq "")} {error "Canonical conversion requires both formulas"}
            if {$canonicalUnit eq "" && ($forward ne "" || $inverse ne "")} {error "Canonical conversion formulas require canonical_unit"}
            foreach formula [list $forward $inverse] {if {$formula ne ""} {unitFormulaValidate $formula}}
            if {[dict get $variable value_kind] ni {number text elapsed_time}} {error "Invalid Variable value kind"}
            if {[dict get $variable decimal_separator] ni {. ,} || [dict get $variable time_reference] ni {elapsed absolute}} {error "Invalid Variable source-format semantics"}
            if {[dict get $variable semantic_source] ni {user importer plugin inferred default}} {error "Invalid Variable semantic source"}
            if {[dict get $variable semantic_role] ne "" && ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} [dict get $variable semantic_role]]} {error "Invalid Variable semantic role"}
            if {[dict get $variable value_kind] eq "elapsed_time" && ([dict get $variable value_format] ne "hms" || [dict get $variable unit] ni {s min h})} {error "Invalid elapsed-time format/unit"}
            if {[dict get $variable value_kind] ne "elapsed_time" && [dict get $variable value_format] ne ""} {error "Value format requires elapsed_time"}
        }
        if {[datasetField $newId variable_schema_api_version ""] eq "3"} {
            foreach variable [datasetVariableSchemaV3 $newId] {datasetSchemaV3ValidateVariable $newId $variable}
        } else {
            datasetVariableSchema $newId
        }
        saveDatasetRegistry $currentSession
        # Package import is an explicit user operation. Restore the validated
        # complete metadata resource, including private provenance, then place
        # the imported Dataset in this Session's current namespace. The generic
        # Metadata editor must never gain this privileged restore capability.
        set metadata [expr {[file isfile $metadataPath]?[_portableResourceFields $metadataPath]:{}}]
        set namespace [datasetNamespaceCurrentGet $currentSession]
        if {[lindex [split $namespace /] 0] eq "pending"} {set namespace base}
        dict set metadata _gxtxt.framework.dataset_namespace $namespace
        _datasetMetadataWriteAll $currentSession $newId $metadata
        if {[file isfile $notePath]} {
            set fd [open $notePath r]
            fconfigure $fd -encoding utf-8 -translation lf
            try {set note [read $fd]} finally {close $fd}
            noteWriteUtf8 $noteTarget $note
        }
        writeManifest $manifestPath
        set committed 1
    } finally {
        if {!$committed} {
            array unset datasetRegistry *
            array set datasetRegistry $prior
            catch {file delete -force -- $final}
            catch {file delete -force -- $metadataTarget}
            catch {file delete -force -- $noteTarget}
            if {$snapshotTarget ne ""} {catch {file delete -force -- $snapshotTarget}}
            if {[file isfile $registryBackup]} {catch {file rename -force -- $registryBackup $registryPath}}
            if {!$registryExisted} {catch {file delete -force -- $registryPath}}
            if {[file isfile $manifestBackup]} {catch {file rename -force -- $manifestBackup $manifestPath}}
            if {!$manifestExisted} {catch {file delete -force -- $manifestPath}}
        } else {
            catch {file delete -force -- $registryBackup}
            catch {file delete -force -- $manifestBackup}
        }
    }
    return [dict create resource_type dataset source_dataset_id $sourceId dataset_id $newId canonical_path $relative variable_ids [lmap v [datasetVariableSchema $newId] {dict get $v variable_id}]]
}
proc ::GX::_portableResourceImportGraph {staging options} {
    if {![datasetAuthorityActive $::GX::currentSession]} {return [datasetAuthorityTransaction $::GX::currentSession ::GX::_portableResourceImportGraph $staging $options]}
    variable currentSession
    variable datasetRegistry
    variable graphResourceRefs
    set renderedOnly [expr {[dict exists $options rendered_only] && [string is true -strict [dict get $options rendered_only]]}]
    set graphRoot [file join $staging graph]
    set state [_portableResourceFields [file join $graphRoot graph-state.json] 0 1]
    set dependencies [split [string trim [_portableResourceRun emit-dependencies [file join $staging gxtxt-resource-package.json]]] "\n"]
    if {$dependencies eq {{}}} {set dependencies {}}
    foreach id $dependencies {
        if {!$renderedOnly && [datasetField $id id ""] ne ""} {error "Dependent Dataset ID '$id' already exists"}
    }
    set cloneId [::GX::PlotClone::nextId]
    set cloneRoot [file join [::GX::PlotClone::root] $cloneId]
    set source [file join $graphRoot graph.png]
    if {![::GX::PlotClone::validPng $source]} {error "Graph package has an invalid rendered artifact"}
    set scientific [expr {!$renderedOnly && [dict get $state module_id] eq "plot.dataset" && [dict get $state capture_mode] eq "scientific" && [file isfile [file join $graphRoot scientific snapshot.h5]]}]
    if {$scientific} {
        file mkdir [file join $graphRoot scientific private_session]
        modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
        ::GX::PlotDatasetAPIv3::renderSnapshot [file join $graphRoot scientific] [dict get $state graph_id]
        if {![::GX::PlotClone::validPng [file join $graphRoot scientific graph.png]]} {error "Graph scientific snapshot failed validation"}
    }
    set registryPath [datasetRegistryPath $currentSession]
    set manifestPath [file join $currentSession metadata manifest.ini]
    set registryBackup "${registryPath}.portable-graph.[pid].[clock clicks].backup"
    set manifestBackup "${manifestPath}.portable-graph.[pid].[clock clicks].backup"
    set priorRegistry [array get datasetRegistry]
    set priorRefs [array get graphResourceRefs]
    set registryExisted [file isfile $registryPath]
    set manifestExisted [file isfile $manifestPath]
    if {[file isfile $registryPath]} {file copy -- $registryPath $registryBackup}
    if {[file isfile $manifestPath]} {file copy -- $manifestPath $manifestBackup}
    set imported {}
    set committed 0
    try {
        if {!$renderedOnly} {
            foreach id $dependencies {
                set result [_portableResourceImportDataset $staging "" [file join datasets $id]]
                lappend imported [dict get $result dataset_id]
            }
        }
        file mkdir $cloneRoot
        file copy -- $source [file join $cloneRoot graph.png]
        if {$scientific} {
            foreach item {snapshot.h5 presentation.ini private_session} {
                file copy -force -- [file join $graphRoot scientific $item] [file join $cloneRoot $item]
            }
        }
        set fd [open [file join $cloneRoot clone.ini] w]
        try {
            fconfigure $fd -encoding utf-8 -translation lf
            puts $fd "\[clone\]"
            putKV $fd schema GXTXT_DETACHED_PLOT_CLONE_v1
            putKV $fd id $cloneId
            putKV $fd capture_mode [expr {$scientific ? "scientific" : "rendered"}]
            putKV $fd title [dict get $state title]
            putKV $fd use [dict get $state use]
            putKV $fd created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"]
            putKV $fd source_module [dict get $state module_id]
            putKV $fd source_module_version [dict get $state source_module_version]
            putKV $fd source_graph [dict get $state graph_id]
            putKV $fd source_variant [dict get $state variant_id]
            putKV $fd source_dataset_ids [join $dependencies {;}]
            putKV $fd source_variable_ids ""
            putKV $fd source_artifact "portable-resource-package"
            putKV $fd source_artifact_bytes [file size $source]
        if {$scientific} {
                putKV $fd snapshot_graph [dict get $state graph_id]
                putKV $fd snapshot_source_variant [dict get $state variant_id]
            } else {
                putKV $fd scientific_capture_error [expr {$renderedOnly ? "Imported as rendered-only by caller request" : "Scientific snapshot unavailable in source package"}]
            }
        } finally {close $fd}
        set cloneRef [dict create kind clone clone_id $cloneId]
        set note [file join $graphRoot notes.md]
        if {[file isfile $note]} {
            set fd [open $note r]
            fconfigure $fd -encoding utf-8 -translation lf
            try {graphNotesWrite $cloneRef [read $fd]} finally {close $fd}
        }
        file copy -- [file join $graphRoot graph-state.json] [file join $cloneRoot portable_source.json]
        set metadata [file join $graphRoot metadata.json]
        if {[file isfile $metadata]} {graphMetadataWrite $cloneRef [_portableResourceFields $metadata]}
        set annotation [file join $graphRoot annotations.json]
        if {[file isfile $annotation]} {
            set target [annotationPathForPlot [file join $cloneRoot graph.png]]
            file mkdir [file dirname $target]
            file copy -- $annotation $target
        }
        set renderMeta [file join $graphRoot render-metadata.ini]
        if {[file isfile $renderMeta]} {
            set target [plotRegionMetadataPath [file join $cloneRoot graph.png]]
            file mkdir [file dirname $target]
            file copy -- $renderMeta $target
        }
        writeManifest $manifestPath
        set committed 1
    } finally {
        if {!$committed} {
            catch {graphResourceDelete [dict create kind clone clone_id $cloneId]}
            array unset datasetRegistry *;array set datasetRegistry $priorRegistry
            array unset graphResourceRefs *;array set graphResourceRefs $priorRefs
            catch {file delete -force -- $cloneRoot}
            foreach id $imported {
                set relative [file join datasets imported $id]
                foreach path [glob -nocomplain [file join $currentSession $relative.*]] {catch {file delete -force -- $path}}
                catch {file delete -force -- [file join $currentSession metadata datasets "${id}.ini"]}
                catch {file delete -force -- [datasetNotePath $id $currentSession]}
                foreach path [glob -nocomplain [file join $currentSession metadata schema_sources "${id}_*"]] {catch {file delete -force -- $path}}
            }
            if {[file isfile $registryBackup]} {catch {file rename -force -- $registryBackup $registryPath}}
            if {!$registryExisted} {catch {file delete -force -- $registryPath}}
            if {[file isfile $manifestBackup]} {catch {file rename -force -- $manifestBackup $manifestPath}}
            if {!$manifestExisted} {catch {file delete -force -- $manifestPath}}
        } else {
            catch {file delete -force -- $registryBackup}
            catch {file delete -force -- $manifestBackup}
        }
    }
    return [dict create resource_type graph clone_id $cloneId capture_mode [expr {$scientific ? "scientific" : "rendered"}] imported_dataset_ids $imported rendered_only $renderedOnly]
}
proc ::GX::portableResourceImport {archive {options {}}} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Portable Resource import is a user/admin Session operation. Modules publish through Dataset Publication in their assigned namespace.}}
    variable currentSession
    if {[catch {dict size $options}]} {error "Portable Resource import options must be a dictionary"}
    foreach key [dict keys $options] {if {$key ni {dataset_id rendered_only}} {error "Unknown Portable Resource import option '$key'"}}
    if {[dict exists $options rendered_only] && ![string is boolean -strict [dict get $options rendered_only]]} {error "rendered_only must be a boolean"}
    set session [_sessionPortableRequireSession]
    if {$session ne [file normalize $currentSession]} {error "Open the target Session first"}
    set info [portableResourceValidate $archive]
    set stage [file join $session metadata ".portable_resource_stage_[pid]_[clock clicks]"]
    try {
        _portableResourceRun extract [file normalize $archive] $stage
        switch -- [dict get $info resource_type] {
            dataset {
                if {[dict exists $options rendered_only]} {error "rendered_only is a Graph import option"}
                set result [_portableResourceImportDataset $stage [expr {[dict exists $options dataset_id] ? [dict get $options dataset_id] : ""}]]
                dict set result id_mapping [dict create [dict get $result source_dataset_id] [dict get $result dataset_id]]
            }
            graph {
                if {[dict exists $options dataset_id]} {error "dataset_id is a Dataset import option"}
                set result [_portableResourceImportGraph $stage $options]
                dict set result id_mapping [dict create [dict get $info resource_identity] [dict get $result clone_id]]
            }
            default {error "Unsupported resource package type"}
        }
        dict set result source_identity [dict get $info resource_identity]
        dict set result archive_sha256 [dict get $info archive_sha256]
        dict set result integrity verified
        dict set result package_info $info
        dict set result warnings [expr {[dict get $info resource_type] eq "graph" && [dict get $result capture_mode] eq "rendered" ? [list "Graph imported as a rendered-only Detached Clone"] : {}}]
        return $result
    } finally {catch {file delete -force -- $stage}}
}

proc ::GX::portableResourceGuiExportDataset {{targetId {}}} {
    variable variableDatasetChoice
    if {[catch {
        _sessionPortableRequireSession
        lassign [datasetInspectionParseChoice $variableDatasetChoice] mode datasetId
        if {$targetId ne {}} {set datasetId $targetId;set mode imported}
        if {$mode ne "imported" || $datasetId eq ""} {error "Select a published Session Dataset first"}
    } reason]} {tk_messageBox -icon info -title "Export Dataset ZIP" -message $reason;return}
    set archive [workspaceSaveFile export_dir -title "Export Dataset ZIP" -initialfile "${datasetId}.gxtxt-dataset.zip" -defaultextension .zip -filetypes {{{GX-TXT Dataset ZIP} {.zip}} {{All files} *}}]
    if {$archive eq ""} return
    if {[catch {set result [portableResourceExportDataset $datasetId $archive]} reason]} {
        tk_messageBox -icon error -title "Dataset ZIP export failed" -message $reason;return
    }
    tk_messageBox -icon info -title "Dataset ZIP exported" -message "[dict get $result archive]\nSHA-256: [dict get $result sha256]\nFiles: [dict get $result file_count]"
}
proc ::GX::portableResourceGuiExportGraph {} {
    if {[catch {
        _sessionPortableRequireSession
        set artifact [currentGraphPath]
        if {$artifact eq ""} {error "Select a graph first"}
        set ref [graphResourceRefForPath $artifact]
        set name [expr {[dict get $ref kind] eq "clone" ? [dict get $ref clone_id] : [dict get $ref graph_id]}]
        if {[dict get $ref kind] eq "provider" && [dict get $ref variant_id] ne ""} {append name "-" [dict get $ref variant_id]}
    } reason]} {tk_messageBox -icon info -title "Export Graph ZIP" -message $reason;return}
    set archive [workspaceSaveFile export_dir -title "Export Graph ZIP" -initialfile "${name}.gxtxt-graph.zip" -defaultextension .zip -filetypes {{{GX-TXT Graph ZIP} {.zip}} {{All files} *}}]
    if {$archive eq ""} return
    if {[catch {set result [portableResourceExportGraph $artifact $archive]} reason]} {
        tk_messageBox -icon error -title "Graph ZIP export failed" -message $reason;return
    }
    tk_messageBox -icon info -title "Graph ZIP exported" -message "[dict get $result archive]\nSHA-256: [dict get $result sha256]\nFiles: [dict get $result file_count]"
}
proc ::GX::_portableResourceGuiImportCommit {window mode} {
    variable ui
    set archive $ui(portableResourceImportArchive)
    set info $ui(portableResourceImportInfo)
    if {$mode eq "dataset"} {
        set datasetId [string trim $ui(portableResourceDatasetId)]
        if {[catch {datasetPublicationV2ValidateId dataset $datasetId} reason]} {
            tk_messageBox -parent $window -icon error -title "Dataset ID" -message $reason;return
        }
        if {[datasetField $datasetId id ""] ne ""} {
            tk_messageBox -parent $window -icon error -title "Dataset ID collision" -message "Dataset '$datasetId' already exists. Enter a new ID.";return
        }
        set options [dict create dataset_id $datasetId]
    } else {
        set options [dict create rendered_only [expr {$mode eq "rendered"}]]
        if {$mode eq "scientific" && !$ui(portableResourceScientificPossible)} {
            tk_messageBox -parent $window -icon error -title "Graph dependency" -message "Scientific import requires Plot Dataset and available, noncolliding dependent Datasets.";return
        }
    }
    if {[catch {set result [portableResourceImport $archive $options]} reason]} {
        tk_messageBox -parent $window -icon error -title "Resource ZIP import failed" -message $reason;return
    }
    destroy $window
    catch {refreshGraphs}
    catch {refreshNativeVariablesGui}
    set identity [expr {$mode eq "dataset" ? [dict get $result dataset_id] : [dict get $result clone_id]}]
    tk_messageBox -icon info -title "Resource ZIP imported" -message "[dict get $info resource_type] imported as $identity.\nIntegrity: [dict get $info integrity]."
}
proc ::GX::portableResourceGuiImport {{expectedType ""}} {
    variable ui
    if {[catch {_sessionPortableRequireSession} reason]} {tk_messageBox -icon info -title "Import Resource ZIP" -message $reason;return}
    set archive [workspaceOpenFile session_open_dir -title "Import GX-TXT Resource ZIP" -filetypes {{{GX-TXT resource ZIP} {.zip}} {{All files} *}}]
    if {$archive eq ""} return
    if {[catch {set info [portableResourceValidate $archive]} reason]} {tk_messageBox -icon error -title "Invalid Resource ZIP" -message $reason;return}
    set type [dict get $info resource_type]
    if {$expectedType ne "" && $type ne $expectedType} {tk_messageBox -icon error -title "Resource type" -message "This is a $type package. Choose a $expectedType package.";return}
    set ui(portableResourceImportArchive) $archive
    set ui(portableResourceImportInfo) $info
    set details "Type: $type\nSource GX-TXT: [dict get $info source_gxtxt_version]\nSource Session: [dict get $info source_session_name]\nIntegrity: SHA-256 verified\nFiles: [dict get $info file_count]\nPayload bytes: [dict get $info total_bytes]\nContract/provider: [dict get $info contract] / [dict get $info provider]"
    set w .gxPortableResourceImport
    catch {destroy $w}
    toplevel $w
    wm title $w "Import [string totitle $type] ZIP"
    wm transient $w .
    ttk::label $w.summary -text $details -justify left
    pack $w.summary -anchor w -padx 10 -pady 8
    if {$type eq "dataset"} {
        set sourceId [dict get $info dataset_id]
        set ui(portableResourceDatasetId) $sourceId
        ttk::label $w.identity -text "Source Dataset: $sourceId\nDestination ID (change to resolve a collision):" -justify left
        ttk::entry $w.id -textvariable ::GX::ui(portableResourceDatasetId) -width 45
        pack $w.identity $w.id -anchor w -padx 10 -pady 4
        if {[datasetField $sourceId id ""] ne ""} {
            ttk::label $w.collision -text "Collision: $sourceId already exists; enter a new ID." -foreground #9b2f20
            pack $w.collision -anchor w -padx 10
        }
    } else {
        set module [dict get $info module_id]
        set dependencies [split [dict get $info dependency_ids] {;}]
        if {$dependencies eq {{}}} {set dependencies {}}
        set collisions {}
        foreach id $dependencies {if {[datasetField $id id ""] ne ""} {lappend collisions $id}}
        set installed [expr {$module ne "" && [moduleField $module descriptor ""] ne ""}]
        set ui(portableResourceScientificPossible) [expr {[dict get $info capture_mode] eq "scientific" && $module eq "plot.dataset" && $installed && ![llength $collisions]}]
        set graphDetails "Graph: $module / [dict get $info graph_id] / [dict get $info variant_id]\nCapture: [dict get $info capture_mode]\nEmbedded Dataset dependencies: [dict get $info dependency_count] ([join $dependencies {, }])\nColliding IDs: [expr {[llength $collisions] ? [join $collisions {, }] : "none"}]\nSource plugin available: [expr {$installed ? "yes" : "no"}]\nImport target: new Detached Clone"
        ttk::label $w.graph -text $graphDetails -justify left
        pack $w.graph -anchor w -padx 10 -pady 4
    }
    ttk::frame $w.buttons
    if {$type eq "dataset"} {
        ttk::button $w.buttons.import -text "Import Dataset" -command [list ::GX::_portableResourceGuiImportCommit $w dataset]
        pack $w.buttons.import -side left -padx 4
    } else {
        ttk::button $w.buttons.scientific -text "Import scientific Clone" -command [list ::GX::_portableResourceGuiImportCommit $w scientific]
        if {!$ui(portableResourceScientificPossible)} {$w.buttons.scientific state disabled}
        ttk::button $w.buttons.rendered -text "Import rendered-only Clone" -command [list ::GX::_portableResourceGuiImportCommit $w rendered]
        pack $w.buttons.scientific $w.buttons.rendered -side left -padx 4
    }
    ttk::button $w.buttons.cancel -text Cancel -command [list destroy $w]
    pack $w.buttons.cancel -side left -padx 4
    pack $w.buttons -anchor e -padx 8 -pady 8
    bind $w <Escape> [list destroy $w]
}
