# GX-TXT Dataset Publication API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Framework-owned registration of module-produced datasets.

namespace eval ::GX {
    variable datasetPublicationApiVersion 1
}

proc ::GX::datasetPublicationRequestDir {moduleId} {
    variable currentSession
    if {$currentSession eq ""} { return "" }
    return [file join $currentSession analysis [sanitize $moduleId] dataset_publications]
}

proc ::GX::datasetPublicationRuntimeAppend_v1_base {runtime moduleId} {
    set fd [open $runtime a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[dataset_publication_api\]"
    putKV $fd api_version $::GX::datasetPublicationApiVersion
    putKV $fd request_dir [datasetPublicationRequestDir $moduleId]
    putKV $fd contract_file_format ini_per_dataset
    close $fd
}

# Append publication API metadata to every final Standard Module runtime.
proc ::GX::writeStandardRuntimeConfig_v090_before_source_metadata {id} {
    set p [::GX::writeStandardRuntimeConfig_v087_before_dataset_publication $id]
    datasetPublicationRuntimeAppend $p $id
    return $p
}

proc ::GX::datasetPublicationSafeRelPath {rel} {
    set rel [string trim $rel]
    if {$rel eq ""} { error "Dataset publication path is required." }
    if {[file pathtype $rel] eq "absolute"} { error "Dataset publication path must be relative to the module output directory." }
    foreach part [file split $rel] { if {$part eq ".."} { error "Dataset publication path may not contain '..'." } }
    return $rel
}

proc ::GX::datasetPublicationSessionRelativePath {abs} {
    variable currentSession
    set root [file normalize $currentSession]
    set p [file normalize $abs]
    if {$p eq $root} { return "." }
    set prefix "$root/"
    if {[string first $prefix "$p/"] != 0} { error "Published dataset is outside the current session: $p" }
    return [string range $p [string length $prefix] end]
}

proc ::GX::datasetPublicationInheritedSchema {d datasetId abs variables units roles storageKind format} {
    variable currentSession
    set hasSource [dict exists $d publication.schema_source_dataset_id]
    set hasIds [dict exists $d publication.schema_source_variable_ids]
    if {!$hasSource && !$hasIds} { return {} }
    if {!$hasSource || !$hasIds} { error "Schema inheritance requires both source Dataset ID and source variable IDs." }
    if {$storageKind ne "text" || [string tolower $format] ne "csv"} {
        error "Schema inheritance requires a text CSV publication."
    }
    set sourceId [string trim [dict get $d publication.schema_source_dataset_id]]
    if {$sourceId eq "" || $sourceId eq $datasetId || [datasetField $sourceId id ""] eq ""} {
        error "Invalid schema source dataset '$sourceId'."
    }
    set sourcePath [datasetResolvePath $currentSession $sourceId]
    if {$sourcePath eq "" || ![file isfile $sourcePath]} { error "Schema source dataset file is unavailable: $sourceId" }
    set ids [splitList [dict get $d publication.schema_source_variable_ids]]
    set names [datasetSchemaSplitNames $variables]
    set count [llength $names]
    if {$count < 1 || [llength $ids] != $count || [llength [lsort -unique $ids]] != $count} {
        error "Schema inheritance requires a distinct, ordered source variable ID for every published variable."
    }
    set declaredUnits [expr {[string trim $units] eq "" ? {} : [split $units ";"]}]
    set declaredRoles [expr {[string trim $roles] eq "" ? {} : [split $roles ";"]}]
    if {[llength $declaredUnits] ni [list 0 $count] || [llength $declaredRoles] ni [list 0 $count]} {
        error "Published units and semantic roles must match the schema mapping length."
    }
    set sep [datasetSchemaDetectDelimiter $abs]
    set fd [open $abs r]; fconfigure $fd -encoding utf-8 -translation auto
    try {
        if {[gets $fd header] < 0} { error "Published CSV has no header." }
    } finally { close $fd }
    set headers [datasetSchemaCsvSplit $header $sep]
    if {[llength $headers] != $count} { error "Published CSV header count does not match the schema mapping." }
    for {set j 0} {$j < $count} {incr j} {
        set name [lindex $names $j]
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $name] || [lsearch -exact [lrange $names 0 [expr {$j-1}]] $name] >= 0} {
            error "Invalid or duplicate published variable name '$name'."
        }
        if {[lindex $headers $j] ne $name} { error "Published CSV header does not match declared variable '$name' at column [expr {$j+1}]." }
    }
    set fields [list var_count $count variable_schema_api_version 2 canonical_delimiter [expr {$sep eq "	" ? "tab" : ($sep eq ";" ? "semicolon" : "comma")}]]
    set inheritedUnits {}; set inheritedRoles {}
    for {set j 0} {$j < $count} {incr j} {
        set vid [lindex $ids $j]
        if {![regexp {^v[0-9]+$} $vid]} { error "Invalid source variable_id '$vid'." }
        set v [datasetVariableById $sourceId $vid]
        if {![dict get $v enabled] || [dict get $v canonical_position] eq ""} {
            error "Source variable $sourceId/$vid is absent from the canonical source."
        }
        set unit [dict get $v unit]; set role [dict get $v semantic_role]
        if {[llength $declaredUnits] && [lindex $declaredUnits $j] ne $unit} {
            error "Published unit contradicts source variable $sourceId/$vid."
        }
        if {[llength $declaredRoles] && [lindex $declaredRoles $j] ne $role} {
            error "Published semantic role contradicts source variable $sourceId/$vid."
        }
        lappend inheritedUnits $unit; lappend inheritedRoles $role
        set n [expr {$j+1}]
        set prefix "var${n}_"
        foreach {field value} [list variable_id [format "v%04d" $n] enabled 1 source_column $n canonical_position $n original_header [lindex $headers $j] canonical [lindex $names $j] source_channel "" schema_inherited 1 value_inferred 1] {
            lappend fields "${prefix}$field" $value
        }
        foreach field {unit canonical_unit to_canonical from_canonical display_label semantic_role semantic_source semantic_reason instrument_id instrument_channel value_kind value_format decimal_separator time_origin time_reference} {
            lappend fields "${prefix}$field" [dict get $v $field]
        }
    }
    return [dict create fields $fields units [join $inheritedUnits ";"] roles [join $inheritedRoles ";"]]
}

proc ::GX::datasetPublicationProcessFile {moduleId requestFile} {
    variable currentSession
    if {![file isfile $requestFile]} { return "" }
    set d [parseIni $requestFile]
    set api [expr {[dict exists $d publication.api_version] ? [dict get $d publication.api_version] : ""}]
    if {$api ne "1"} { error "$moduleId: unsupported Dataset Publication API version '$api' in $requestFile" }
    foreach k {dataset_id contract format path} {
        if {![dict exists $d publication.$k] || [string trim [dict get $d publication.$k]] eq ""} { error "$moduleId: publication request is missing '$k': $requestFile" }
    }
    foreach k {variables units semantic_roles source provenance} {
        if {![dict exists $d publication.$k]} { error "$moduleId: publication request is missing metadata field '$k': $requestFile" }
    }
    set datasetId [string trim [dict get $d publication.dataset_id]]
    if {![regexp {^[A-Za-z0-9_.-]+$} $datasetId]} { error "$moduleId: invalid published dataset ID '$datasetId'." }
    set contract [string trim [dict get $d publication.contract]]
    set format [string trim [dict get $d publication.format]]
    set declared [splitList [moduleField $moduleId output_datasets ""]]
    if {[llength $declared] && [lsearch -exact $declared $contract] < 0} { error "$moduleId: published contract '$contract' is not declared in [outputs] datasets=." }
    set rel [datasetPublicationSafeRelPath [dict get $d publication.path]]
    set outDir [file join $currentSession analysis [sanitize $moduleId]]
    set abs [file normalize [file join $outDir $rel]]
    set outNorm [file normalize $outDir]
    if {[string first "$outNorm/" "$abs/"] != 0} { error "$moduleId: publication path escapes module output directory: $rel" }
    if {![file isfile $abs]} { error "$moduleId: published dataset file does not exist: $abs" }

    set existing [datasetField $datasetId id ""]
    if {$existing ne ""} {
        _datasetNamespaceRequireModuleWrite $currentSession $moduleId $datasetId
        if {[string is true -strict [datasetField $datasetId immutable 0]]} {error "Dataset '$datasetId' is immutable"}
        set owner [datasetField $datasetId source_module ""]
        set pubv [datasetField $datasetId publication_api_version ""]
        if {$owner ne $moduleId || $pubv ne "1"} {
            error "$moduleId: dataset ID '$datasetId' already exists and is not owned by this module through Dataset Publication API v1."
        }
    }

    set variables [expr {[dict exists $d publication.variables] ? [dict get $d publication.variables] : ""}]
    set units [expr {[dict exists $d publication.units] ? [dict get $d publication.units] : ""}]
    set roles [expr {[dict exists $d publication.semantic_roles] ? [dict get $d publication.semantic_roles] : ""}]
    set source [expr {[dict exists $d publication.source] ? [dict get $d publication.source] : ""}]
    set provenance [expr {[dict exists $d publication.provenance] ? [dict get $d publication.provenance] : ""}]
    set notes [expr {[dict exists $d publication.notes] ? [dict get $d publication.notes] : ""}]
    set storageKind [string tolower [string trim [expr {[dict exists $d publication.storage_kind] ? [dict get $d publication.storage_kind] : "text"}]]]
    if {$storageKind eq ""} { set storageKind text }
    if {$storageKind ni {text binary}} { error "$moduleId: publication storage_kind must be text or binary." }
    set mediaType [string trim [expr {[dict exists $d publication.media_type] ? [dict get $d publication.media_type] : ""}]]
    if {$mediaType ne "" && ([string first "/" $mediaType] < 1 || [regexp {[\r\n]} $mediaType])} { error "$moduleId: publication media_type '$mediaType' is invalid." }
    set computedAnnotations ""
    if {[dict exists $d publication.computed_annotations] && [string trim [dict get $d publication.computed_annotations]] ne ""} {
        set annRel [computedDataAnnotationSafeRelPath [dict get $d publication.computed_annotations]]
        set annAbs [file normalize [file join $outDir $annRel]]
        if {[string first "$outNorm/" "$annAbs/"] != 0} { error "$moduleId: computed annotation sidecar escapes module output directory: $annRel" }
        computedDataAnnotationValidateFile $annAbs $datasetId
        set computedAnnotations [datasetPublicationSessionRelativePath $annAbs]
    }
    set inheritance [datasetPublicationInheritedSchema $d $datasetId $abs $variables $units $roles $storageKind $format]
    if {$inheritance ne ""} {
        set units [dict get $inheritance units]
        set roles [dict get $inheritance roles]
    }
    set sha [sha256File $abs]
    set sessionRel [datasetPublicationSessionRelativePath $abs]
    set fields [list \
        kind $contract contract $contract format $format storage_kind $storageKind media_type $mediaType path $sessionRel \
        columns $variables variables $variables units $units semantic_roles $roles \
        source_module $moduleId source $source provenance $provenance \
        canonical_sha256 $sha sha256 $sha publication_api_version 1 \
        publication_request [file tail $requestFile] \
        created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] \
        immutable 0 notes $notes \
        computed_annotations_api_version [expr {$computedAnnotations eq "" ? "" : "1"}] \
        computed_annotations_file $computedAnnotations]
    if {$inheritance ne ""} {
        variable datasetRegistry
        foreach key [array names datasetRegistry "$datasetId,var*"] { unset datasetRegistry($key) }
        set fields [concat $fields [dict get $inheritance fields]]
    }
    datasetRegister $datasetId $fields
    return $datasetId
}

proc ::GX::datasetPublicationProcessModule {moduleId} {
    if {![datasetAuthorityActive $::GX::currentSession]} {return [datasetAuthorityTransaction $::GX::currentSession ::GX::datasetPublicationProcessModule $moduleId]}
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { return {} }
    # Public CORE transports may already have committed inside the child.
    # Refresh the parent catalog before considering legacy request files.
    loadDatasetRegistry $currentSession
    set dir [datasetPublicationRequestDir $moduleId]
    if {$dir eq "" || ![file isdirectory $dir]} { return {} }
    set reqs [lsort [glob -nocomplain -types f [file join $dir *.ini]]]
    if {![llength $reqs]} { return {} }
    loadDatasetRegistry $currentSession
    variable datasetRegistry
    set prior [array get datasetRegistry]
    set registryPath [datasetRegistryPath $currentSession]
    set existed [file isfile $registryPath]
    set backup "${registryPath}.publication.[pid].backup"
    if {$existed} { file copy -force -- $registryPath $backup }
    set published {}
    try {
        foreach req $reqs { lappend published [datasetPublicationProcessFile $moduleId $req] }
        saveDatasetRegistry $currentSession
    } on error {err opts} {
        array unset datasetRegistry *
        array set datasetRegistry $prior
        if {$existed} {
            if {[file isfile $backup]} { file rename -force -- $backup $registryPath }
        } else {
            catch {file delete -force -- $registryPath}
        }
        return -options $opts $err
    }
    if {[file isfile $backup]} { file delete -force -- $backup }
    set processed [file join $dir processed]; file mkdir $processed
    set stamp [clock format [clock seconds] -format "%Y%m%dT%H%M%S"]
    foreach req $reqs {
        set dst [file join $processed "${stamp}_[file tail $req]"]
        catch {file rename -force $req $dst}
    }
    catch {writeManifest [file join $currentSession metadata manifest.ini]}
    catch {refreshResults}; catch {refreshCsvPreview}; catch {refreshNativeVariablesGui}; catch {refreshAnalysisSourceWidgets}
    return $published
}
