# GX-TXT Portable Resource API v1. Host/plugin operations only.
# Resource packages use the Portable Session helper's path, symlink and SHA
# rules; all content is validated in a private staging area before commit.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX { variable portableResourceApiVersion 1;variable portableDocumentImportActive 0;variable portableDocumentImportOwners {} }

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
proc ::GX::_portableResourceFields {path {schema 0} {graph 0} {group 0}} {
    set operation [expr {$group ? "emit-group" : ($graph ? "emit-graph-state" : ($schema ? "emit-schema" : "emit-fields"))}]
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
proc ::GX::_portableResourceExportWithAssets {datasetIds args} {
    set session [_interactiveDocumentRequireSession]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::_portableResourceExportWithAssets $datasetIds {*}$args]}
    set rows {}
    foreach id [lsort -unique $datasetIds] {
        set assets [datasetPublicationV2DictDefault [datasetPrivateMetadataRead $session $id] _gxtxt.framework.document_assets_v1 {}]
        _documentAssetsValidate $assets
        dict for {name reference} $assets {
            lappend rows [dict create dataset_id $id name $name reference $reference path [_documentResourceIdentity $reference]]
            if {[llength $rows]>4096} {error {Portable document resource plan exceeds its bound}}
        }
    }
    if {![llength $rows]} {return [_portableResourceRun {*}$args]}
    set allocation [resourceManagementAllocate portable_document_assets [dict create category temporary lifetime request retention_seconds 0]]
    set channel {}
    try {
        set plan [file join [dict get $allocation path] document-assets.tsv]
        set channel [open $plan {WRONLY CREAT EXCL}]
        fconfigure $channel -encoding utf-8 -translation lf
        _portableResourceWriteStateField $channel schema gxtxt.portable_document_assets.v1
        _portableResourceWriteStateField $channel count [llength $rows]
        set index 0
        foreach row $rows {incr index;dict for {key value} $row {_portableResourceWriteStateField $channel asset.$index.$key $value}}
        close $channel;set channel {}
        return [_portableResourceRun {*}$args --document-assets-plan $plan]
    } finally {if {$channel ne {}} {close $channel};documentInteractiveAllocationRelease $allocation}
}
proc ::GX::portableResourceExportDataset {datasetId archive} {
    variable currentSession
    variable version
    set session [_sessionPortableRequireSession]
    if {$session ne [file normalize $currentSession]} {error "Open the source Session first"}
    if {[datasetField $datasetId id ""] eq ""} {error "Unknown Dataset '$datasetId'"}
    set archive [file normalize $archive]
    if {![string match *.zip [string tolower $archive]]} {append archive .gxtxt-dataset.zip}
    set groupId [datasetGroupForDataset $session $datasetId]
    set args {};if {$groupId ne {}} {set args [list --original-group $groupId]}
    return [_sessionPortableParseOutput [_portableResourceExportWithAssets [list $datasetId] export-dataset $session $datasetId $archive $version {*}$args]]
}
proc ::GX::portableResourceGroupApiInfo {} {
    return [dict create api_id PORTABLE_RESOURCE_API_v2 api_version 2 resource_types dataset_group compatibility {Dataset Graph Workspace v1 remain unchanged}]
}
proc ::GX::portableResourceExportGroup {groupId archive} {
    set session [_sessionPortableRequireSession]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::portableResourceExportGroup $groupId $archive]}
    set group [datasetGroupGet $session $groupId]
    if {[dict get $group status] ne {COMPLETE}} {error {Cannot export a degraded Dataset Group}}
    set archive [file normalize $archive]
    if {![string match *.zip [string tolower $archive]]} {append archive .gxtxt-dataset-group.zip}
    set plan [file join $session metadata ".portable_group_[pid]_[clock clicks].tsv"]
    set fd [open $plan {WRONLY CREAT EXCL}]
    try {
        fconfigure $fd -encoding utf-8 -translation lf
        foreach field {group_id display_name group_contract revision namespace primary_dataset_id} {_portableResourceWriteStateField $fd $field [dict get $group $field]}
        if {[dict exists $group created_at]} {_portableResourceWriteStateField $fd created_at [dict get $group created_at]}
        set history [datasetPublicationV2DictDefault $group history {}]
        _portableResourceWriteStateField $fd history_count [llength $history]
        set index 0
        foreach event $history {
            incr index
            foreach field {action at revision} {_portableResourceWriteStateField $fd history.$index.$field [dict get $event $field]}
            _portableResourceWriteStateField $fd history.$index.details [dict get $event details]
        }
        _portableResourceWriteStateField $fd member_count [llength [dict get $group members]]
        set index 0
        set memberIds {}
        foreach member [dict get $group members] {
            incr index;set id [dict get $member dataset_id]
            lappend memberIds $id
            foreach field {dataset_id role required contract canonical_sha256} {_portableResourceWriteStateField $fd member.$index.$field [dict get $member $field]}
            foreach field {source_module source_sha256} {_portableResourceWriteStateField $fd member.$index.$field [dict get $group source $id $field]}
            set sourceName [datasetPublicationV2DictDefault [dict get $group source $id] source_name [file tail [dict get $group source $id source_raw]]]
            _portableResourceWriteStateField $fd member.$index.source_name $sourceName
        }
        close $fd;set fd {}
        return [_sessionPortableParseOutput [_portableResourceExportWithAssets $memberIds export-group $session $plan $archive $::GX::version]]
    } finally {if {$fd ne {}} {close $fd};file delete -force -- $plan}
}
proc ::GX::_portableResourceImportGroup {staging options} {
    set session [_sessionPortableRequireSession]
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::_portableResourceImportGroup $staging $options]}
    foreach key [dict keys $options] {if {$key ni {group_id dataset_id_map destination_namespace}} {error "Invalid Dataset Group import option '$key'"}}
    set fields [_portableResourceFields [file join $staging group descriptor.json] 0 0 1]
    set history {}
    for {set i 1} {$i<=[datasetPublicationV2DictDefault $fields history_count 0]} {incr i} {
        set event {}
        foreach field {action at revision details} {dict set event $field [dict get $fields history.$i.$field]}
        lappend history $event
    }
    _datasetGroupHistoryValidate $history
    set sourceGroup [dict get $fields group_id]
    set groupId [datasetPublicationV2DictDefault $options group_id $sourceGroup]
    acquisitionHandlerValidateDatasetId $groupId {Dataset Group import ID}
    if {[dict exists [_datasetGroupStoreRead $session] groups $groupId]} {error "Dataset Group '$groupId' already exists"}
    set mapping [datasetPublicationV2DictDefault $options dataset_id_map {}]
    if {[catch {dict size $mapping}]} {error {Dataset Group ID mapping must be a dictionary}}
    set destination [datasetNamespaceNormalize [datasetPublicationV2DictDefault $options destination_namespace [datasetNamespaceCurrentGet $session]]]
    if {[lindex [split $destination /] 0] eq {pending}} {error {Pending is not a published Dataset Group destination}}
    set members {};set targets {};set sourceIds {};set actualMap {}
    set count [dict get $fields member_count]
    if {![string is integer -strict $count] || $count<1 || $count>1000} {error {Invalid Dataset Group member count}}
    for {set i 1} {$i<=$count} {incr i} {
        set sourceId [dict get $fields member.$i.dataset_id]
        set target [datasetPublicationV2ValidateId dataset [datasetPublicationV2DictDefault $mapping $sourceId $sourceId]]
        if {$target in $targets || [datasetField $target id {}] ne {}} {error "Dataset Group member ID collides: '$target'"}
        set payload [lindex [glob -nocomplain -types f [file join $staging datasets $sourceId payload *]] 0]
        foreach path [list [file join $session datasets imported "$target[file extension $payload]"] [file join $session metadata datasets $target.ini] [datasetNotePath $target $session]] {
            if {[file exists $path]} {error "Dataset Group member destination already exists: '$target'"}
        }
        dict set actualMap $sourceId $target
        lappend targets $target;lappend sourceIds $sourceId
        lappend members [dict create dataset_id $target role [dict get $fields member.$i.role] required [dict get $fields member.$i.required]]
    }
    foreach id [dict keys $mapping] {if {$id ni $sourceIds} {error "Dataset Group remap contains unrequested Dataset '$id'"}}
    set results {}
    foreach sourceId $sourceIds target $targets {
        lappend results [_portableResourceImportDataset $staging $target [file join datasets $sourceId]]
        datasetNamespaceSet $session $target $destination
    }
    foreach target $targets {
        set references [split [datasetField $target source_dataset_ids {}] {;}]
        set mapped {}
        foreach id $references {lappend mapped [datasetPublicationV2DictDefault $actualMap $id $id]}
        if {[datasetField $target source_dataset_ids {}] ne {}} {datasetRegister $target [list source_dataset_ids [join $mapped {;}]]}
    }
    saveDatasetRegistry $session
    set primary [dict get $actualMap [dict get $fields primary_dataset_id]]
    datasetGroupCreate $session [dict create group_id $groupId display_name [dict get $fields display_name] group_contract [dict get $fields group_contract] primary_dataset_id $primary members $members]
    set store [_datasetGroupStoreRead $session]
    dict set store groups $groupId revision [dict get $fields revision]
    if {[dict exists $fields created_at]} {dict set store groups $groupId created_at [dict get $fields created_at]}
    dict set store groups $groupId history $history
    _datasetGroupHistoryAppend store $groupId import [dict create source_group_id $sourceGroup source_namespace [dict get $fields namespace] destination_namespace $destination]
    for {set i 1} {$i<=$count} {incr i} {
        set target [dict get $actualMap [dict get $fields member.$i.dataset_id]]
        dict set store groups $groupId source $target source_name [dict get $fields member.$i.source_name]
    }
    dict set store groups $groupId origin [dict create source_group_id $sourceGroup source_namespace [dict get $fields namespace] id_mapping $actualMap descriptor $fields]
    _datasetGroupStoreWrite $session $store
    return [dict create resource_type dataset_group group_id $groupId imported_dataset_ids $targets id_mapping $actualMap atomic 1 datasets $results]
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
    set native [expr {[graphRendererOwner $ref] eq {PLOT_DATASET_API_v4}}]
    if {$native} {
        try {
            graphNativeRendererRequire
            if {[dict get $ref kind] eq {clone}} {
                set capture [::GX::PlotDatasetAPIv4::snapshotCopy [file dirname $artifact] $scientific]
            } else {
                set capture [::GX::PlotDatasetAPIv4::captureForArtifact $artifact $scientific]
            }
            # Each canonical Dataset archive is embedded in the verified native
            # snapshot. Export also works after its live source was removed.
            set dependencies {}
            set snapshot $scientific
            dict set state capture_mode scientific
            set fd [open $statePath a]
            try {fconfigure $fd -encoding utf-8 -translation lf;_portableResourceWriteStateField $fd capture_mode scientific} finally {close $fd}
        } on error {message options} {
            catch {file delete -force -- $statePath}
            catch {file delete -force -- $scientific}
            return -options $options $message
        }
    } elseif {[dict get $ref kind] eq "clone" && [dict get $state capture_mode] eq "scientific"} {
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
        return [_sessionPortableParseOutput [_portableResourceExportWithAssets $dependencies export-graph $session $artifact $statePath $note $metadata $annotation $renderMeta $snapshot [join [lsort -unique $dependencies] {;}] $archive $version]]
    } finally {
        catch {file delete -force -- $statePath}
        catch {file delete -force -- $scientific}
    }
}
proc ::GX::_portableResourceAdoptDocumentAssets {root metadata sourceId newId} {
    set assets [datasetPublicationV2DictDefault $metadata _gxtxt.framework.document_assets_v1 {}]
    if {![dict size $assets]} {return [dict create metadata $metadata owner {}]}
    set index [_portableResourceFields [file join $root document-assets.json]]
    if {[dict get $index schema] ne {gxtxt.portable_document_assets.v1} || [dict get $index count]!=[dict size $assets] || [dict size $assets]>32} {error {Invalid portable document asset closure}}
    set owner [_datasetDocumentAssetOwnerCreateForImport [dict create operation portable_dataset_import source_dataset_id $sourceId destination_dataset_id $newId]]
    if {$::GX::portableDocumentImportActive} {lappend ::GX::portableDocumentImportOwners $owner}
    set remapped {};set complete 0
    try {
        for {set i 1} {$i<=[dict get $index count]} {incr i} {
            set name [dict get $index asset.$i.name]
            set source [dict get $index asset.$i.reference]
            if {![dict exists $assets $name] || [dict get $assets $name] ne $source || [dict exists $remapped $name]} {error {Portable document asset association changed}}
            set blob [dict get $index asset.$i.blob]
            if {![regexp {^assets/[a-f0-9]{64}[.]blob$} $blob]} {error {Invalid portable document asset path}}
            set path [file join $root $blob]
            if {[file type $path] ne {file} || [file size $path]!=[dict get $source size_bytes] || [sha256File $path] ne [dict get $source sha256]} {error {Portable document asset bytes changed during adoption}}
            set reference [interactiveDocumentResourceImportNumeric [dict get $owner document_id] $path [dict get $source metadata]]
            if {[dict get $reference sha256] ne [dict get $source sha256] || [dict get $reference size_bytes]!=[dict get $source size_bytes]} {error {Imported managed image differs from its portable source}}
            dict set remapped $name $reference
        }
        _documentAssetsValidate $remapped
        dict set metadata _gxtxt.framework.document_assets_v1 $remapped
        set complete 1
        return [dict create metadata $metadata owner $owner]
    } finally {if {!$complete && !$::GX::portableDocumentImportActive} {_datasetDocumentAssetOwnerCloseForImport $owner}}
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
    set committed 0;set documentAssetOwner {}
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
            if {[dict get $variable semantic_source] ni {user importer plugin generator inferred default}} {error "Invalid Variable semantic source"}
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
        if {[llength [info commands ::GX::sourceNotePortableMetadata]]} {
            set metadata [sourceNotePortableMetadata $metadata $sourceId $newId]
        } elseif {[dict exists $metadata _gxtxt.framework.source_note_v1]} {
            error {Source-note portable metadata requires its current public owner}
        }
        set adopted [_portableResourceAdoptDocumentAssets $root $metadata $sourceId $newId]
        set metadata [dict get $adopted metadata];set documentAssetOwner [dict get $adopted owner]
        set namespace [datasetNamespaceCurrentGet $currentSession]
        if {[lindex [split $namespace /] 0] eq "pending"} {set namespace base}
        dict set metadata _gxtxt.framework.dataset_namespace $namespace
        _datasetMetadataWriteAll $currentSession $newId $metadata
        if {$documentAssetOwner ne {} && !$::GX::portableDocumentImportActive} {_datasetDocumentAssetOwnerCloseForImport $documentAssetOwner}
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
            if {$documentAssetOwner ne {} && !$::GX::portableDocumentImportActive} {_datasetDocumentAssetOwnerCloseForImport $documentAssetOwner}
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
    set native [file isfile [file join $graphRoot scientific native_v4_snapshot.tcldict]]
    set scientific [expr {!$renderedOnly && [dict get $state module_id] eq "plot.dataset" && [dict get $state capture_mode] eq "scientific" && ($native || [file isfile [file join $graphRoot scientific snapshot.h5]])}]
    if {$scientific} {
        if {$native} {
            graphNativeRendererRequire
            set nativeInfo [::GX::PlotDatasetAPIv4::snapshotValidate [file join $graphRoot scientific] [dict get $state graph_id]]
            ::GX::PlotDatasetAPIv4::renderSnapshot [file join $graphRoot scientific] [dict get $state graph_id]
        } else {
            file mkdir [file join $graphRoot scientific private_session]
            modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
            ::GX::PlotDatasetAPIv3::renderSnapshot [file join $graphRoot scientific] [dict get $state graph_id]
        }
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
            if {$native} {
                ::GX::PlotDatasetAPIv4::snapshotCopy [file join $graphRoot scientific] $cloneRoot
            } else {
                foreach item {snapshot.h5 presentation.ini private_session} {
                    file copy -force -- [file join $graphRoot scientific $item] [file join $cloneRoot $item]
                }
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
            putKV $fd source_dataset_ids [join [expr {$scientific && $native ? [dict keys [dict get $nativeInfo datasets]] : $dependencies}] {;}]
            putKV $fd source_variable_ids [expr {$scientific && $native && [dict exists $nativeInfo source_variable_ids] ? [join [dict get $nativeInfo source_variable_ids] {;}] : ""}]
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
        if {$renderedOnly} {
            # An intentional rendered-only import must not retain an executable
            # renderer claim without its scientific representation.
            set fields [graphMetadataRead $cloneRef]
            foreach field {renderer_owner renderer_owner_api_version} {catch {dict unset fields $field}}
            graphMetadataWrite $cloneRef $fields
        }
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
    foreach key [dict keys $options] {if {$key ni {dataset_id rendered_only group_id dataset_id_map destination_namespace}} {error "Unknown Portable Resource import option '$key'"}}
    if {[dict exists $options rendered_only] && ![string is boolean -strict [dict get $options rendered_only]]} {error "rendered_only must be a boolean"}
    set session [_sessionPortableRequireSession]
    if {$session ne [file normalize $currentSession]} {error "Open the target Session first"}
    set info [portableResourceValidate $archive]
    if {$::GX::portableDocumentImportActive} {error {Another portable Resource import is still completing}}
    set ::GX::portableDocumentImportActive 1;set ::GX::portableDocumentImportOwners {}
    set stage [file join $session metadata ".portable_resource_stage_[pid]_[clock clicks]"]
    try {
        _portableResourceRun extract [file normalize $archive] $stage
        switch -- [dict get $info resource_type] {
            dataset {
                foreach key [dict keys $options] {if {$key ne {dataset_id}} {error "Invalid individual Dataset import option '$key'"}}
                if {[dict exists $options rendered_only]} {error "rendered_only is a Graph import option"}
                set result [_portableResourceImportDataset $stage [expr {[dict exists $options dataset_id] ? [dict get $options dataset_id] : ""}]]
                dict set result id_mapping [dict create [dict get $result source_dataset_id] [dict get $result dataset_id]]
            }
            graph {
                foreach key [dict keys $options] {if {$key ne {rendered_only}} {error "Invalid Graph import option '$key'"}}
                if {[dict exists $options dataset_id]} {error "dataset_id is a Dataset import option"}
                set result [_portableResourceImportGraph $stage $options]
                dict set result id_mapping [dict create [dict get $info resource_identity] [dict get $result clone_id]]
            }
            dataset_group {set result [_portableResourceImportGroup $stage $options]}
            default {error "Unsupported resource package type"}
        }
        dict set result source_identity [dict get $info resource_identity]
        dict set result archive_sha256 [dict get $info archive_sha256]
        dict set result integrity verified
        dict set result package_info $info
        dict set result warnings [expr {[dict get $info resource_type] eq "graph" && [dict get $result capture_mode] eq "rendered" ? [list "Graph imported as a rendered-only Detached Clone"] : {}}]
        if {[dict get $info resource_type] eq {dataset} && [datasetField [dict get $result dataset_id] original_group_id {}] ne {}} {
            dict lappend result warnings {Individual Dataset imported detached; its original Group was not reconstructed}
        }
        return $result
    } finally {
        # Dataset/Group/Graph authority has now committed or rolled back every
        # metadata member. Retire only this request's newly created carriers;
        # ordinary resource retention protects successfully adopted references.
        set failures {}
        foreach owner $::GX::portableDocumentImportOwners {
            if {[catch {_datasetDocumentAssetOwnerCloseForImport $owner} reason]} {lappend failures [dict create document_id [dict get $owner document_id] error $reason]}
        }
        set ::GX::portableDocumentImportActive 0;set ::GX::portableDocumentImportOwners {}
        catch {file delete -force -- $stage}
        if {[llength $failures]} {error "Portable document resource retirement requires review: $failures"}
    }
}
proc ::GX::portableResourceGuiExportGroup {groupId} {
    set session [sessionInspectionCurrentSession]
    set group [datasetGroupGet $session $groupId]
    set archive [tk_getSaveFile -parent .top -title {Export Dataset Group ZIP} -defaultextension .gxtxt-dataset-group.zip -initialfile "$groupId.gxtxt-dataset-group.zip" -filetypes {{{Dataset Group ZIP} {.zip}}}]
    if {$archive eq {}} return
    if {$session ne [sessionInspectionCurrentSession]} {error {Session changed; reopen Group export}}
    if {[catch {portableResourceExportGroup $groupId $archive} message]} {tk_messageBox -parent .top -icon error -message $message} else {tk_messageBox -parent .top -message "Exported [llength [dict get $group members]] Dataset members to $archive"}
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
    if {$ui(portableResourceImportSessionToken) ne [interactiveDocumentSessionToken]} {tk_messageBox -parent $window -icon error -message {Session changed; reopen Resource import};return}
    if {$mode eq "dataset"} {
        set datasetId [string trim $ui(portableResourceDatasetId)]
        if {[catch {datasetPublicationV2ValidateId dataset $datasetId} reason]} {
            tk_messageBox -parent $window -icon error -title "Dataset ID" -message $reason;return
        }
        if {[datasetField $datasetId id ""] ne ""} {
            tk_messageBox -parent $window -icon error -title "Dataset ID collision" -message "Dataset '$datasetId' already exists. Enter a new ID.";return
        }
        set options [dict create dataset_id $datasetId]
    } elseif {$mode eq {dataset_group}} {
        set mapping [string trim [$window.mapping get 1.0 end-1c]]
        if {[catch {dict size $mapping}]} {tk_messageBox -parent $window -icon error -message {Enter one original-ID and destination-ID pair per line};return}
        set options [dict create group_id [string trim $ui(portableResourceGroupId)] dataset_id_map $mapping destination_namespace [string trim $ui(portableResourceGroupNamespace)]]
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
    set identity [expr {$mode eq "dataset" ? [dict get $result dataset_id] : ($mode eq {dataset_group} ? [dict get $result group_id] : [dict get $result clone_id])}]
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
    set ui(portableResourceImportSessionToken) [interactiveDocumentSessionToken]
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
    } elseif {$type eq {dataset_group}} {
        set ui(portableResourceGroupId) [dict get $info group_id]
        set ui(portableResourceGroupNamespace) [datasetNamespaceCurrentGet]
        ttk::label $w.identity -text "Group: [dict get $info group_id]; [dict get $info group_member_count] actual members\nDestination Group ID:"
        ttk::entry $w.id -textvariable ::GX::ui(portableResourceGroupId)
        ttk::label $w.namespaceLabel -text {Destination Namespace:}
        ttk::entry $w.namespace -textvariable ::GX::ui(portableResourceGroupNamespace)
        ttk::label $w.mappingLabel -text {Reviewed member IDs (original destination, one pair per line):}
        text $w.mapping -height 6 -width 60 -wrap none
        foreach id [split [dict get $info group_member_ids] {;}] {$w.mapping insert end "$id $id\n"}
        pack $w.identity $w.id $w.namespaceLabel $w.namespace $w.mappingLabel -fill x -padx 10 -pady 3
        pack $w.mapping -fill both -expand 1 -padx 10 -pady 3
    } else {
        set module [dict get $info module_id]
        set dependencies [split [dict get $info dependency_ids] {;}]
        if {$dependencies eq {{}}} {set dependencies {}}
        set collisions {}
        foreach id $dependencies {if {[datasetField $id id ""] ne ""} {lappend collisions $id}}
        set installed [expr {$module ne "" && [moduleField $module descriptor ""] ne ""}]
        set ui(portableResourceScientificPossible) [expr {[dict get $info capture_mode] eq "scientific" && $module eq "plot.dataset" && $installed && ![llength $collisions]}]
        set graphDetails "Graph: $module / [dict get $info graph_id] / [dict get $info variant_id]\nCapture: [dict get $info capture_mode]\nDataset imports into Session: [dict get $info dependency_count] ([join $dependencies {, }])\nColliding import IDs: [expr {[llength $collisions] ? [join $collisions {, }] : "none"}]"
        if {[dict exists $info native_snapshot_dataset_count] && [dict get $info native_snapshot_dataset_count]>0} {
            append graphDetails "\nFrozen native snapshot Datasets: [dict get $info native_snapshot_dataset_count]"
            foreach id [split [dict get $info native_snapshot_dataset_ids] {;}] {append graphDetails "\n  $id"}
            append graphDetails "\nThese Datasets remain inside the Clone; their IDs are not registered in the destination Session."
        }
        append graphDetails "\nSource plugin available: [expr {$installed ? "yes" : "no"}]\nImport target: new Detached Clone"
        ttk::label $w.graph -text $graphDetails -justify left -wraplength 640
        pack $w.graph -anchor w -padx 10 -pady 4
    }
    ttk::frame $w.buttons
    if {$type eq "dataset"} {
        ttk::button $w.buttons.import -text "Import Dataset" -command [list ::GX::_portableResourceGuiImportCommit $w dataset]
        pack $w.buttons.import -side left -padx 4
    } elseif {$type eq {dataset_group}} {
        ttk::button $w.buttons.import -text {Import whole Group} -command [list ::GX::_portableResourceGuiImportCommit $w dataset_group]
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
