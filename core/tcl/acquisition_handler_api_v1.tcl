# GX-TXT Acquisition Handler Plugin API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Additive v0.8.9 layer.  standard_tcl acquisition modules may provide a
# descriptor-declared runtime handler without adding branches to core dispatch.
# The framework owns session creation, RAW provenance and Dataset Registry
# updates; the plugin owns format recognition/parsing/canonical output.

namespace eval ::GX {
    variable acquisitionHandlerApiVersion 1
    variable acquisitionHandlerRegistry
    array unset acquisitionHandlerRegistry *
}

proc ::GX::acquisitionHandlerSectionField {moduleId key {default ""}} {
    variable moduleCatalog
    if {![info exists moduleCatalog($moduleId,dict)]} { return $default }
    return [descriptorValue $moduleCatalog($moduleId,dict) acquisition_handler $key $default]
}

proc ::GX::acquisitionHandlerHasPluginDescriptor {moduleId} {
    return [expr {[string trim [acquisitionHandlerSectionField $moduleId api_version ""]] ne ""}]
}

proc ::GX::acquisitionHandlerSourceKind {moduleId} {
    set k [string tolower [string trim [acquisitionHandlerSectionField $moduleId source_kind "text"]]]
    if {$k eq ""} { set k text }
    if {$k ni {text binary}} { error "$moduleId: acquisition_handler.source_kind must be text or binary." }
    return $k
}

# Variable mapping is an acquisition capability, not a storage-format property.
# required (default): legacy/tabular behavior, at least one source variable.
# optional: zero or more variables are valid.
# none: the source/dataset is intentionally opaque to the Variables workspace.
proc ::GX::acquisitionHandlerVariableMappingMode {moduleId} {
    set m [string tolower [string trim [acquisitionHandlerSectionField $moduleId variable_mapping "required"]]]
    if {$m eq ""} { set m required }
    if {$m ni {required optional none}} {
        error "$moduleId: acquisition_handler.variable_mapping must be required, optional or none."
    }
    return $m
}

proc ::GX::acquisitionHandlerValidateDatasetId {id {context "Dataset ID"}} {
    set id [string trim $id]
    if {$id eq "" || ![regexp {^[A-Za-z0-9_.-]+$} $id] || $id in {. ..}} {
        error "$context '$id' is invalid. Allowed characters: letters, digits, '.', '_' and '-'."
    }
    return $id
}

proc ::GX::acquisitionHandlerRegister {handlerId fields} {
    variable acquisitionHandlerRegistry
    set handlerId [string trim $handlerId]
    if {$handlerId eq ""} { error "Acquisition handler ID is required." }
    if {[catch {dict size $fields}]} { error "Acquisition handler '$handlerId' registration must be a dict." }
    set acquisitionHandlerRegistry($handlerId) $fields
    return $handlerId
}

proc ::GX::acquisitionHandlerRegistered {handlerId} {
    variable acquisitionHandlerRegistry
    return [info exists acquisitionHandlerRegistry($handlerId)]
}

proc ::GX::acquisitionHandlerField {handlerId key {default ""}} {
    variable acquisitionHandlerRegistry
    if {![info exists acquisitionHandlerRegistry($handlerId)]} { return $default }
    set d $acquisitionHandlerRegistry($handlerId)
    if {[dict exists $d $key]} { return [dict get $d $key] }
    return $default
}

proc ::GX::acquisitionHandlerResolveScript {moduleId rel} {
    set rel [string trim $rel]
    if {$rel eq ""} { error "$moduleId: acquisition_handler.script is required." }
    if {[file pathtype $rel] eq "absolute"} { error "$moduleId: acquisition handler script must be plugin-relative." }
    foreach p [file split $rel] { if {$p eq ".."} { error "$moduleId: acquisition handler script may not contain '..'." } }
    set descriptor [moduleField $moduleId descriptor ""]
    set root [file dirname $descriptor]
    set path [file normalize [file join $root $rel]]
    set rootn [file normalize $root]
    if {[string first "$rootn/" "$path/"] != 0} { error "$moduleId: acquisition handler script escapes plugin directory." }
    if {![file isfile $path]} { error "$moduleId: acquisition handler script does not exist: $path" }
    return $path
}

proc ::GX::acquisitionHandlerLoadModule_v089 {moduleId} {
    variable acquisitionHandlerApiVersion
    if {[moduleField $moduleId kind ""] ne "acquisition" || [moduleField $moduleId runner ""] ne "standard_tcl"} {
        error "$moduleId: Acquisition Handler Plugin API v1 requires kind=acquisition and runner=standard_tcl."
    }
    set handlerId [moduleRunnerHandler $moduleId]
    if {$handlerId eq ""} { error "$moduleId: \[runner\].handler is required." }
    if {[acquisitionHandlerRegistered $handlerId] &&
        ([acquisitionHandlerField $handlerId kind ""] ne "legacy" ||
         ![acquisitionHandlerHasPluginDescriptor $moduleId])} { return $handlerId }
    if {![acquisitionHandlerHasPluginDescriptor $moduleId]} { return "" }
    set api [acquisitionHandlerSectionField $moduleId api_version ""]
    if {$api ne "$acquisitionHandlerApiVersion"} { error "$moduleId: unsupported Acquisition Handler Plugin API version '$api'." }
    set script [acquisitionHandlerResolveScript $moduleId [acquisitionHandlerSectionField $moduleId script ""]]
    uplevel #0 [list source $script]
    set inspectProc [string trim [acquisitionHandlerSectionField $moduleId inspect_proc ""]]
    set importProc [string trim [acquisitionHandlerSectionField $moduleId import_proc ""]]
    if {$inspectProc eq "" || ![llength [info commands $inspectProc]]} { error "$moduleId: acquisition inspect_proc '$inspectProc' is not callable." }
    if {$importProc eq "" || ![llength [info commands $importProc]]} { error "$moduleId: acquisition import_proc '$importProc' is not callable." }
    acquisitionHandlerRegister $handlerId [dict create \
        module_id $moduleId kind plugin inspect_proc $inspectProc import_proc $importProc \
        file_label [acquisitionHandlerSectionField $moduleId file_label "Input files"] \
        file_patterns [acquisitionHandlerSectionField $moduleId file_patterns "*"] \
        source_kind [acquisitionHandlerSourceKind $moduleId] \
        variable_mapping [acquisitionHandlerVariableMappingMode $moduleId] \
        supports_batch [acquisitionHandlerSectionField $moduleId supports_batch 0]]
    return $handlerId
}

proc ::GX::acquisitionHandlerLoadModule {moduleId} {
    tailcall ::GX::acquisitionHandlerLoadModule_v089 $moduleId
}

proc ::GX::acquisitionHandlerValidateDescriptors {} {
    variable moduleOrder
    foreach moduleId $moduleOrder {
        if {[moduleField $moduleId kind ""] ne "acquisition" || [moduleField $moduleId runner ""] ne "standard_tcl"} continue
        set h [moduleRunnerHandler $moduleId]
        if {$h in {generic_csv rigol_csv}} continue
        if {![acquisitionHandlerHasPluginDescriptor $moduleId]} {
            error "$moduleId: standard_tcl handler '$h' is not a legacy handler and has no \[acquisition_handler\] API descriptor."
        }
        set api [acquisitionHandlerSectionField $moduleId api_version ""]
        if {$api ne "1"} { error "$moduleId: acquisition_handler.api_version must be 1." }
        foreach key {script inspect_proc import_proc} {
            if {[string trim [acquisitionHandlerSectionField $moduleId $key ""]] eq ""} { error "$moduleId: acquisition_handler.$key is required." }
        }
        acquisitionHandlerSourceKind $moduleId
        acquisitionHandlerVariableMappingMode $moduleId
    }
}

# Validate new acquisition descriptors after normal module discovery.  Legacy
# generic_csv/rigol_csv descriptors remain untouched and fully compatible.
proc ::GX::loadModuleCatalog_v089_before_acq_v090 {} {
    ::GX::loadModuleCatalog_v088_before_acquisition_handler_api
    acquisitionHandlerValidateDescriptors
}

proc ::GX::acquisitionHandlerInspect {moduleId sourcePath {previewDir ""}} {
    variable moduleCfg
    set handlerId [acquisitionHandlerLoadModule $moduleId]
    if {$handlerId eq "" || [acquisitionHandlerField $handlerId kind ""] ne "plugin"} {
        error "$moduleId: no plug-in acquisition handler is available."
    }
    set sourcePath [file normalize $sourcePath]
    if {![file isfile $sourcePath]} { error "$moduleId: input file does not exist: $sourcePath" }
    set sourceKind [acquisitionHandlerField $handlerId source_kind [acquisitionHandlerSourceKind $moduleId]]
    if {[string trim $previewDir] ne ""} {
        set previewDir [file normalize $previewDir]
        file mkdir $previewDir
    }
    set p [acquisitionHandlerField $handlerId inspect_proc ""]
    # Hand off only descriptor-declared settings. Inspectors must not read
    # CORE's moduleCfg array, and can preview the same parser settings import
    # receives through its existing request.config field.
    set config [dict create]
    foreach key [moduleConfigKeys $moduleId] {
        dict set config $key [expr {[info exists moduleCfg($moduleId,$key)] ? $moduleCfg($moduleId,$key) : [moduleConfigField $moduleId $key default ""]}]
    }
    set req [dict create api_version 1 module_id $moduleId handler_id $handlerId source_path $sourcePath source_kind $sourceKind preview_dir $previewDir config $config]
    set result [uplevel #0 [list $p $req]]
    if {[catch {dict size $result}]} { error "$moduleId: inspect_proc must return a dict." }
    foreach key {recognized format variables metadata preview_rows warnings} {
        if {![dict exists $result $key]} { dict set result $key [expr {$key in {variables preview_rows warnings} ? [list] : ($key eq "metadata" ? [dict create] : "")}] }
    }
    dict set result source_kind $sourceKind
    return $result
}

proc ::GX::_acquisitionHandlerUnrecognizedReason {moduleId inspection} {
    set diagnostics {}
    if {[dict exists $inspection preview_metadata Diagnostic]} {
        set diagnostic [string trim [dict get $inspection preview_metadata Diagnostic]]
        if {$diagnostic ne {}} {lappend diagnostics $diagnostic}
    }
    foreach warning [dict get $inspection warnings] {
        set warning [string trim $warning]
        if {$warning ne {} && $warning ni $diagnostics} {lappend diagnostics $warning}
    }
    set reason "$moduleId: acquisition handler did not recognize the selected source group."
    if {[llength $diagnostics]} {append reason "\n\n[join $diagnostics \n]"}
    append reason "\n\nThe source row is retained. Use Preview for the inspection details, or correct the source and import again."
    return $reason
}

proc ::GX::acquisitionHandlerSeedVariables {inspection} {
    variable sourceVar
    variable sourceVarCount
    if {![dict exists $inspection variables]} { return }
    set vars [dict get $inspection variables]
    if {![llength $vars]} { return }
    clearSourceVariables
    set i 0
    foreach v $vars {
        incr i
        set sourceVarCount $i
        set orig [expr {[dict exists $v original_header] ? [dict get $v original_header] : "C$i"}]
        set canon [expr {[dict exists $v canonical] ? [dict get $v canonical] : $orig}]
        foreach {f def} {enabled 1 source_column "" source_channel "" original_header "" canonical "" unit "" semantic_role "" instrument_id "" instrument_channel ""} {
            set sourceVar($i,$f) $def
        }
        set sourceVar($i,source_column) [expr {[dict exists $v source_column] ? [dict get $v source_column] : $i}]
        set sourceVar($i,original_header) $orig
        set sourceVar($i,canonical) $canon
        foreach f {unit semantic_role instrument_id instrument_channel source_channel} {
            if {[dict exists $v $f]} { set sourceVar($i,$f) [dict get $v $f] }
        }
    }
}

proc ::GX::acquisitionHandlerVariableMap {} {
    variable sourceVar
    variable sourceVarCount
    set out {}
    for {set i 1} {$i <= $sourceVarCount} {incr i} {
        if {![info exists sourceVar($i,enabled)] || !$sourceVar($i,enabled)} continue
        set d [dict create]
        foreach f {source_column source_channel original_header canonical unit semantic_role instrument_id instrument_channel} {
            dict set d $f [expr {[info exists sourceVar($i,$f)] ? $sourceVar($i,$f) : ""}]
        }
        lappend out $d
    }
    return $out
}

proc ::GX::acquisitionHandlerPreviewPlugin_before_dataset_preview_v1 {moduleId sourcePath} {
    variable ui
    if {![info exists ui(preview)] || ![winfo exists $ui(preview)]} { return }
    set w $ui(preview)
    previewDescriptorClearWidgetArtifact $w
    $w configure -state normal; $w delete 1.0 end
    if {$sourcePath eq "" || ![file isfile $sourcePath]} {
        $w insert end "Select an input file to inspect with $moduleId.\n"; $w configure -state disabled; return
    }
    set previewDir [previewDescriptorCreateTempDir]
    if {[catch {set r [acquisitionHandlerInspect $moduleId $sourcePath $previewDir]} err]} {
        previewDescriptorCleanupDir $previewDir
        $w insert end "ACQUISITION HANDLER PREVIEW ERROR\n=================================\n$err\n"; $w configure -state disabled; return
    }
    catch {acquisitionHandlerSeedVariables $r}
    set sourceKind [dict get $r source_kind]
    $w insert end "ACQUISITION HANDLER PREVIEW\n===========================\n"
    $w insert end "Module:      $moduleId\n"
    $w insert end "Source:      [file normalize $sourcePath]\n"
    $w insert end "Source kind: $sourceKind\n"
    $w insert end "Recognized:  [dict get $r recognized]\n"
    $w insert end "Format:      [dict get $r format]\n"
    if {$sourceKind eq "binary"} {
        if {[catch {set pd [previewDescriptorNormalize $r $previewDir]} perr]} {
            $w insert end "\nPREVIEW DESCRIPTOR ERROR\n========================\n$perr\n"
        } else {
            previewDescriptorRenderTextWidget $w $pd
            if {![llength [dict get $pd kinds]]} { $w insert end "\nNo binary preview descriptor was returned by the plugin. Raw bytes are intentionally not rendered.\n" }
        }
    } else {
        set md [dict get $r metadata]
        if {[dict size $md]} {
            $w insert end "\nMETADATA\n========\n"
            dict for {k v} $md { $w insert end [format "%-24s %s\n" $k $v] }
        }
        if {[dict exists $r preview_kind] && [string trim [dict get $r preview_kind]] ni {"" legacy}} {
            if {[catch {set pd [previewDescriptorNormalize $r $previewDir]} perr]} {
                $w insert end "\nPREVIEW DESCRIPTOR ERROR\n========================\n$perr\n"
            } else { previewDescriptorRenderTextWidget $w $pd }
        }
    }
    $w insert end "\nVARIABLES\n=========\n"
    $w insert end [format "%-6s %-30s %-30s %-12s %-18s\n" "Input" "Original / source" "Canonical default" "Unit" "Semantic role"]
    $w insert end [string repeat "-" 104]; $w insert end "\n"
    set n 0
    foreach v [dict get $r variables] {
        incr n
        set orig [expr {[dict exists $v original_header] ? [dict get $v original_header] : "C$n"}]
        set canon [expr {[dict exists $v canonical] ? [dict get $v canonical] : $orig}]
        set unit [expr {[dict exists $v unit] ? [dict get $v unit] : ""}]
        set role [expr {[dict exists $v semantic_role] ? [dict get $v semantic_role] : ""}]
        $w insert end [format "%-6d %-30s %-30s %-12s %-18s\n" $n $orig $canon $unit $role]
    }
    set warns [dict get $r warnings]
    if {[llength $warns]} { $w insert end "\nWARNINGS\n========\n"; foreach x $warns { $w insert end "- $x\n" } }
    if {$sourceKind eq "text"} {
        set rows [dict get $r preview_rows]
        if {[llength $rows]} { $w insert end "\nDATA SAMPLE\n===========\n"; set i 0; foreach row $rows { incr i; $w insert end "ROW $i    [join $row { | }]\n" } }
    }
    $w insert end "\nThe framework owns session/RAW/registry lifecycle. This preview is supplied through Acquisition Handler Plugin API v1 + Preview Descriptor API v1.\n"
    $w configure -state disabled
    previewDescriptorCleanupDir $previewDir
    catch {refreshNativeVariablesGui}; catch {rebuildNativeAnalysisGui}
}

# Route the common preview workspace through plug-in inspection only for new
# acquisition handlers. Existing generic_csv/rigol_csv preview paths are kept.
proc ::GX::refreshCsvPreview_before_binary_guard_v1 {} {
    variable cfg
    variable csvPreviewDatasetChoice
    variable genericCsvBatch
    variable ui
    set moduleId $cfg(acquisition_module)
    set h [moduleRunnerHandler $moduleId]
    if {$h ni {generic_csv rigol_csv} && [acquisitionHandlerHasPluginDescriptor $moduleId]} {
        if {[info exists csvPreviewDatasetChoice] && $csvPreviewDatasetChoice ne ""} {
            lassign [datasetInspectionParseChoice $csvPreviewDatasetChoice] mode key
            if {$mode eq "pending" && $key > 0 && [info exists genericCsvBatch($key,path)]} {
                return [acquisitionHandlerPreviewPlugin $moduleId $genericCsvBatch($key,path)]
            }
            if {$mode eq "imported" && [info exists ui(preview)] && [winfo exists $ui(preview)]} {
                return [datasetInspectionRenderPreview $ui(preview) $csvPreviewDatasetChoice]
            }
        }
        return [acquisitionHandlerPreviewPlugin $moduleId $cfg(input_csv)]
    }
    return [::GX::refreshCsvPreview_v088_before_acquisition_handler_api]
}

# Seed Variables through inspect_proc for plug-in acquisition modules while
# preserving the established CSV paths verbatim.
proc ::GX::ensureVariablesForCurrentInput_before_binary_guard_v1 {} {
    variable cfg
    variable sourceVarCount
    set moduleId $cfg(acquisition_module)
    set h [moduleRunnerHandler $moduleId]
    if {$h ni {generic_csv rigol_csv} && [acquisitionHandlerHasPluginDescriptor $moduleId]} {
        if {$cfg(input_csv) eq "" || ![file isfile $cfg(input_csv)]} return
        if {[catch {set r [acquisitionHandlerInspect $moduleId $cfg(input_csv)]}]} return
        if {$sourceVarCount == 0} { acquisitionHandlerSeedVariables $r }
        return
    }
    return [::GX::ensureVariablesForCurrentInput_v088_before_acquisition_handler_api]
}

proc ::GX::ensureVariablesForCurrentInput {} {
    tailcall ::GX::ensureVariablesForCurrentInput_before_binary_guard_v1
}

proc ::GX::acquisitionHandlerFileTypes {moduleId} {
    set label [acquisitionHandlerSectionField $moduleId file_label "Input files"]
    set pats [splitList [acquisitionHandlerSectionField $moduleId file_patterns "*"]]
    if {![llength $pats]} { set pats [list *] }
    set types {}
    # Optional ordered groups: label|pattern;pattern, separated by ||.
    # The legacy file_label/file_patterns pair remains the fallback.
    foreach group [split [string map [list "||" "\n"] [acquisitionHandlerSectionField $moduleId file_type_groups ""]] "\n"] {
        if {[string trim $group] eq ""} continue
        set sep [string first "|" $group]
        if {$sep < 1} continue
        set groupLabel [string trim [string range $group 0 [expr {$sep-1}]]]
        set groupPatterns [splitList [string trim [string range $group [expr {$sep+1}] end]]]
        if {$groupLabel ne "" && [llength $groupPatterns]} {lappend types [list $groupLabel $groupPatterns]}
    }
    if {![llength $types]} {lappend types [list $label $pats]}
    lappend types [list "All files" *]
    return $types
}

proc ::GX::acquisitionHandlerSourceStoragePolicy {moduleId} {
    variable cfg
    set policy [expr {[info exists cfg(acquisition_source_storage)] ? $cfg(acquisition_source_storage) : "copy"}]
    if {$policy ni {copy reference}} {error "Source storage must be Copy or Keep/reference."}
    if {$policy eq "reference" && [acquisitionHandlerSectionField $moduleId supports_external_raw 0] ne "1"} {
        error "$moduleId does not support external RAW references. Choose Copy source into Session."
    }
    return $policy
}

proc ::GX::acquisitionHandlerRawIntegrity {datasetId} {
    set policy [datasetField $datasetId source_storage_policy copy]
    set path [datasetField $datasetId source_raw ""]
    if {$policy ne "reference"} {return [dict create status OK policy copy path $path]}
    if {$path eq "" || ![file isfile $path]} {return [dict create status {SOURCE MISSING} policy reference path $path]}
    set expected [datasetField $datasetId source_sha256 ""]
    set actual [sha256File $path]
    set status [expr {$expected ne "" && [string equal -nocase $expected $actual] ? "OK" : "SOURCE MODIFIED"}]
    return [dict create status $status policy reference path $path expected_sha256 $expected actual_sha256 $actual size_bytes [file size $path] mtime [file mtime $path]]
}

proc ::GX::chooseInput_v089_before_batch_bridge {} {
    variable cfg
    set moduleId $cfg(acquisition_module)
    set h [moduleRunnerHandler $moduleId]
    if {$h in {generic_csv rigol_csv} || ![acquisitionHandlerHasPluginDescriptor $moduleId]} {
        return [::GX::chooseInput_v088_before_acquisition_handler_api]
    }
    set p [workspaceOpenFile acquisition_dir -title "Acquisition input" -filetypes [acquisitionHandlerFileTypes $moduleId]]
    if {$p eq ""} return
    set cfg(input_csv) [file normalize $p]
    if {$cfg(output_root) eq ""} { set cfg(output_root) [file join [file dirname $cfg(input_csv)] GXTXT_sessions] }
    clearSourceVariables
    catch {refreshCsvPreview}; catch {refreshNativeVariablesGui}; catch {refreshManifestPreview}
}
proc ::GX::chooseInput {} {
    return [::GX::chooseInput_v089_before_batch_bridge]
}

proc ::GX::acquisitionHandlerSafeDatasetPath {session outputDir rel} {
    set rel [string trim $rel]
    if {$rel eq "" || [file pathtype $rel] eq "absolute"} { error "Acquisition handler dataset path must be a non-empty relative path." }
    foreach p [file split $rel] { if {$p eq ".."} { error "Acquisition handler dataset path may not contain '..'." } }
    set abs [file normalize [file join $outputDir $rel]]
    set outn [file normalize $outputDir]
    if {[string first "$outn/" "$abs/"] != 0} { error "Acquisition handler dataset path escapes the framework output directory: $rel" }
    if {![file isfile $abs]} { error "Acquisition handler declared dataset file does not exist: $abs" }
    set root [file normalize $session]
    if {[string first "$root/" "$abs/"] != 0} { error "Acquisition handler dataset is outside the session: $abs" }
    return [list $abs [string range $abs [expr {[string length $root]+1}] end]]
}

# Normalize a handler's optional public schema before changing Dataset state.
# Registry fields are returned in physical CSV-column order, independent of
# the declaration list order. The canonical payload remains handler-owned.
proc ::GX::acquisitionHandlerDeclaredSchemaFields {moduleId ds path} {
    if {![dict exists $ds variable_schema]} { return {} }
    set declared [dict get $ds variable_schema]
    if {![llength $declared]} { error "$moduleId: variable_schema must not be empty." }
    set csv [expr {[string tolower [dict get $ds format]] eq "csv"}]
    if {$csv && [dict exists $ds storage_kind] && [string tolower [dict get $ds storage_kind]] eq "binary"} {
        error "$moduleId: a canonical CSV cannot declare binary storage_kind."
    }
    set headers {}; set rows ""; set delimiter ""; set separator ""
    if {$csv} {
        set separator [datasetSchemaDetectDelimiter $path]
        set delimiter [expr {$separator eq "\t" ? "tab" : ($separator eq ";" ? "semicolon" : "comma")}]
        set headers [datasetSchemaRawHeaders $path 1 $separator]
        if {![llength $headers]} { error "$moduleId: canonical CSV has no header." }
        set fd [open $path r]
        fconfigure $fd -encoding utf-8 -translation auto
        gets $fd line
        set rows 0
        try {
            while {[gets $fd line] >= 0} {
                if {[string trim $line] eq ""} continue
                if {[llength [datasetSchemaCsvSplit $line $separator]] != [llength $headers]} {
                    error "$moduleId: canonical CSV row has a different column count."
                }
                incr rows
            }
        } finally { close $fd }
        set summary [dict get $ds variables]
        if {$summary ne $headers} { error "$moduleId: declared variables do not match canonical CSV columns." }
        if {[llength $declared] != [llength $headers]} { error "$moduleId: variable_schema count does not match canonical CSV columns." }
        if {[dict exists $ds row_count] && [dict get $ds row_count] ne $rows} {
            error "$moduleId: declared row_count does not match canonical CSV."
        }
    } elseif {[llength [dict get $ds variables]] != [llength $declared]} {
        error "$moduleId: variable_schema count does not match descriptor variables."
    }
    set allowed {variable_id canonical name source_column unit semantic_role value_kind value_format decimal_separator time_origin time_reference dtype rank shape dimension_ids coordinate_variable_ids coordinate_role axis_kind axis_origin axis_step axis_count component_ids group_id display_label}
    set byColumn [dict create]; set seenIds {}; set seenNames {}
    set position 0
    foreach item $declared {
        incr position
        if {[catch {dict size $item}]} { error "$moduleId: each variable_schema entry must be a dictionary." }
        dict for {key value} $item {
            if {$key ni $allowed} { error "$moduleId: unsupported variable_schema field '$key'." }
            if {[regexp {[\r\n]} $value]} { error "$moduleId: variable_schema fields must be single-line." }
        }
        if {![dict exists $item variable_id]} { error "$moduleId: variable_schema entry is missing variable_id." }
        set id [datasetPublicationV2ValidateId variable [dict get $item variable_id]]
        if {$id in $seenIds} { error "$moduleId: duplicate variable_id '$id'." }
        lappend seenIds $id
        set column [expr {[dict exists $item source_column] ? [dict get $item source_column] : $position}]
        if {!$csv && [dict exists $item source_column]} { error "$moduleId: source_column applies only to canonical CSV." }
        if {$csv && (![string is integer -strict $column] || $column < 1 || $column > [llength $headers])} {
            error "$moduleId: invalid source_column '$column'."
        }
        if {$csv && [dict exists $byColumn $column]} { error "$moduleId: duplicate source_column '$column'." }
        set canonical [expr {[dict exists $item canonical] ? [dict get $item canonical] :
            ([dict exists $item name] ? [dict get $item name] : ($csv ? [lindex $headers [expr {$column-1}]] : $id))}]
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $canonical]} { error "$moduleId: invalid canonical variable name '$canonical'." }
        if {$canonical in $seenNames} { error "$moduleId: duplicate canonical variable '$canonical'." }
        lappend seenNames $canonical
        if {$csv && $canonical ne [lindex $headers [expr {$column-1}]]} {
            error "$moduleId: canonical variable '$canonical' does not match source_column $column."
        }
        set dtype [string tolower [expr {[dict exists $item dtype] ? [dict get $item dtype] : "float64"}]]
        if {$dtype ni {float32 float64 int8 int16 int32 int64 uint8 uint16 uint32 uint64 bool string}} {
            error "$moduleId: unsupported dtype '$dtype'."
        }
        set valueKind [expr {[dict exists $item value_kind] ? [dict get $item value_kind] : ($dtype eq "string" ? "text" : "number")}]
        if {$valueKind ni {number text elapsed_time} || ($dtype eq "string") != ($valueKind eq "text")} {
            error "$moduleId: value_kind is incompatible with dtype for '$id'."
        }
        if {[dict exists $item semantic_role] && [dict get $item semantic_role] ne "" &&
            ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} [dict get $item semantic_role]]} {
            error "$moduleId: invalid semantic_role for '$id'."
        }
        set unit [expr {[dict exists $item unit] ? [dict get $item unit] : ""}]
        set valueFormat [expr {[dict exists $item value_format] ? [dict get $item value_format] : ""}]
        set timeReference [expr {[dict exists $item time_reference] ? [dict get $item time_reference] : "elapsed"}]
        if {$valueFormat ni {"" hms} || $timeReference ni {elapsed absolute}} {
            error "$moduleId: invalid value format or time reference for '$id'."
        }
        if {$valueKind eq "elapsed_time" && ($valueFormat ne "hms" || $unit ni {s min h})} {
            error "$moduleId: elapsed_time '$id' requires HMS format and unit s, min or h."
        }
        if {$valueKind ne "elapsed_time" && $valueFormat ne ""} {
            error "$moduleId: value_format requires elapsed_time for '$id'."
        }
        if {$timeReference eq "absolute" && ($valueKind ne "elapsed_time" ||
            ![dict exists $item time_origin] || [string trim [dict get $item time_origin]] eq "")} {
            error "$moduleId: absolute time requires elapsed_time and time_origin for '$id'."
        }
        if {[dict exists $item decimal_separator] && [dict get $item decimal_separator] ni {. ,}} {
            error "$moduleId: invalid decimal_separator for '$id'."
        }
        set rank [expr {[dict exists $item rank] ? [dict get $item rank] : 1}]
        set shape [expr {[dict exists $item shape] ? [dict get $item shape] : ($csv ? $rows : "")}]
        set dimensionIds [expr {[dict exists $item dimension_ids] ? [dict get $item dimension_ids] : ($csv ? "row" : "")}]
        foreach dimension [datasetSchemaV3SplitIds $dimensionIds] {
            datasetPublicationV2ValidateId dimension $dimension
        }
        if {[dict exists $item group_id] && [dict get $item group_id] ne ""} {
            datasetPublicationV2ValidateId group [dict get $item group_id]
        }
        if {$csv && [dict exists $item axis_kind] && [dict get $item axis_kind] eq "uniform"} {
            error "$moduleId: canonical CSV cannot declare an implicit uniform axis."
        }
        if {$csv && ($rank ne "1" || [datasetSchemaV3SplitIds $shape] ne [list $rows] ||
            [datasetSchemaV3SplitIds $dimensionIds] ne {row})} {
            error "$moduleId: canonical CSV variables require rank 1 and the row dimension."
        }
        set normalized [dict merge $item [dict create variable_id $id canonical $canonical source_column $column \
            dtype $dtype value_kind $valueKind rank $rank shape $shape dimension_ids $dimensionIds]]
        dict set byColumn $column $normalized
    }
    set fields [list var_count [llength $declared] variable_schema_api_version 3]
    if {$csv} { lappend fields row_count $rows sample_count $rows canonical_delimiter $delimiter storage_provider csv }
    set names {}; set units {}; set roles {}
    for {set index 1} {$index <= [llength $declared]} {incr index} {
        if {![dict exists $byColumn $index]} { error "$moduleId: variable_schema source columns are not contiguous." }
        set item [dict get $byColumn $index]
        set prefix "var${index}_"
        foreach {field value} [list variable_id [dict get $item variable_id] enabled 1 \
            source_column [expr {$csv ? $index : ""}] canonical_position $index \
            original_header [dict get $item canonical] canonical [dict get $item canonical] \
            unit [expr {[dict exists $item unit] ? [dict get $item unit] : ""}] \
            semantic_role [expr {[dict exists $item semantic_role] ? [dict get $item semantic_role] : ""}] \
            semantic_source plugin value_kind [dict get $item value_kind] dtype [dict get $item dtype] \
            rank [dict get $item rank] shape [dict get $item shape] dimension_ids [dict get $item dimension_ids]] {
            lappend fields "${prefix}$field" $value
        }
        foreach {field default} {value_format "" decimal_separator . time_origin "" time_reference elapsed} {
            lappend fields "${prefix}$field" [expr {[dict exists $item $field] ? [dict get $item $field] : $default}]
        }
        foreach {field default} [datasetSchemaV3FieldDefaults] {
            if {$field in {dtype rank shape dimension_ids}} continue
            lappend fields "${prefix}$field" [expr {[dict exists $item $field] ? [dict get $item $field] : $default}]
        }
        if {[dict exists $item display_label]} { lappend fields "${prefix}display_label" [dict get $item display_label] }
        lappend names [dict get $item canonical]
        lappend units [expr {[dict exists $item unit] ? [dict get $item unit] : ""}]
        lappend roles [expr {[dict exists $item semantic_role] ? [dict get $item semantic_role] : ""}]
    }
    lappend fields columns [join $names ,] variables [join $names ,] units [join $units ,] semantic_roles [join $roles ,]
    return $fields
}

proc ::GX::acquisitionHandlerRegisterResult {moduleId session rawRel rawHash outputDir result} {
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::acquisitionHandlerRegisterResult $moduleId $session $rawRel $rawHash $outputDir $result]}
    variable datasetRegistry
    if {[catch {dict size $result}]} { error "$moduleId: import_proc must return a dict." }
    if {![dict exists $result datasets]} { error "$moduleId: import_proc result must contain a datasets list." }
    set datasets [dict get $result datasets]
    set declared [splitList [moduleField $moduleId output_datasets ""]]

    # Validate all optional structured metadata before changing the registry.
    # Dataset Metadata API v1 remains the sole persistence and ownership layer.
    set structuredByIndex [dict create]
    set usesStructuredMetadata 0
    set schemaByIndex [dict create]
    set usesDeclaredSchema 0
    set index -1
    foreach ds $datasets {
        incr index
        if {[catch {dict size $ds}]} { error "$moduleId: each returned dataset must be a dict." }
        if {[dict exists $ds structured_metadata]} {
            set metadata [dict get $ds structured_metadata]
            if {[catch {dict size $metadata}]} {
                error "$moduleId: returned dataset structured_metadata must be a dictionary."
            }
            foreach key [dict keys $metadata] {
                if {[catch {_datasetMetadataValidateKey $key} validationError]} {
                    error "$moduleId: invalid structured_metadata field '$key': $validationError"
                }
            }
            dict set structuredByIndex $index $metadata
            set usesStructuredMetadata 1
        }
        if {[dict exists $ds variable_schema]} {
            foreach key {format path variables} {
                if {![dict exists $ds $key]} { error "$moduleId: returned dataset with variable_schema is missing '$key'." }
            }
            lassign [acquisitionHandlerSafeDatasetPath $session $outputDir [dict get $ds path]] abs unused
            dict set schemaByIndex $index [acquisitionHandlerDeclaredSchemaFields $moduleId $ds $abs]
            set usesDeclaredSchema 1
        }
    }

    set priorRegistry {}
    set registryPath ""
    set registryBackup ""
    set registryExisted 0
    if {$usesStructuredMetadata || $usesDeclaredSchema} {
        set priorRegistry [array get datasetRegistry]
        set registryPath [datasetRegistryPath $session]
        set registryExisted [file isfile $registryPath]
        set registryBackup [format "%s.acquisition-metadata.%s.%s.backup" $registryPath [pid] [clock clicks]]
        if {$registryExisted} { file copy -force -- $registryPath $registryBackup }
    }

    set ids {}
    set metadataPaths {}
    set index -1
    if {[catch {
        foreach ds $datasets {
            incr index
            foreach k {dataset_id contract format path variables units semantic_roles source provenance} {
                if {![dict exists $ds $k]} { error "$moduleId: returned dataset is missing '$k'." }
            }
            set id [string trim [dict get $ds dataset_id]]
            set contract [string trim [dict get $ds contract]]
            set format [string trim [dict get $ds format]]
            set id [acquisitionHandlerValidateDatasetId $id "$moduleId returned Dataset ID"]
            if {[llength $declared] && [lsearch -exact $declared $contract] < 0} { error "$moduleId: returned contract '$contract' is not declared in \[outputs\] datasets=." }
            if {[datasetField $id id ""] ne ""} { error "$moduleId: dataset ID '$id' already exists in the current session." }
            lassign [acquisitionHandlerSafeDatasetPath $session $outputDir [dict get $ds path]] abs sessionRel
            set sha [sha256File $abs]
            set vars [dict get $ds variables]
            set units [dict get $ds units]
            set roles [dict get $ds semantic_roles]
            set notes [expr {[dict exists $ds notes] ? [dict get $ds notes] : ""}]
            set storageKind [string tolower [string trim [expr {[dict exists $ds storage_kind] ? [dict get $ds storage_kind] : "text"}]]]
            if {$storageKind eq ""} { set storageKind text }
            if {$storageKind ni {text binary}} { error "$moduleId: dataset '$id' storage_kind must be text or binary." }
            set mediaType [string trim [expr {[dict exists $ds media_type] ? [dict get $ds media_type] : ""}]]
            if {$mediaType ne "" && ([string first "/" $mediaType] < 1 || [regexp {[\r\n]} $mediaType])} { error "$moduleId: dataset '$id' has invalid media_type '$mediaType'." }
            set fields [list kind $contract contract $contract format $format storage_kind $storageKind media_type $mediaType path $sessionRel \
                columns [join $vars ,] variables [join $vars ,] units [join $units ,] semantic_roles [join $roles ,] \
                source_module $moduleId source [dict get $ds source] provenance [dict get $ds provenance] \
                source_raw $rawRel source_sha256 $rawHash canonical_sha256 $sha sha256 $sha \
                acquisition_handler_api_version 1 created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] immutable 0 notes $notes]
            if {[dict exists $schemaByIndex $index]} { set fields [concat $fields [dict get $schemaByIndex $index]] }
            datasetRegister $id $fields
            if {[dict exists $schemaByIndex $index]} {
                foreach variable [datasetVariableSchemaV3 $id] { datasetSchemaV3ValidateVariable $id $variable }
            }
            lappend ids $id
        }

        if {$usesStructuredMetadata} {
            # datasetMetadataWrite intentionally requires a registered Dataset.
            # Commit the registrations first, then let Dataset Metadata API v1
            # validate, persist and attach each sidecar.
            saveDatasetRegistry $session
            set index -1
            foreach id $ids {
                incr index
                if {![dict exists $structuredByIndex $index]} continue
                lappend metadataPaths [_datasetMetadataPublicationWrite $session $id [dict get $structuredByIndex $index] $moduleId [dict keys [dict get $structuredByIndex $index]]]
            }
        }
    } failure options]} {
        if {$usesStructuredMetadata || $usesDeclaredSchema} {
            foreach path $metadataPaths {
                if {[_datasetDeletePathWithin $path [file join $session metadata datasets]]} {
                    catch {file delete -force -- $path}
                }
            }
            array unset datasetRegistry *
            array set datasetRegistry $priorRegistry
            if {$registryExisted && [file isfile $registryBackup]} {
                catch {file rename -force -- $registryBackup $registryPath}
            } elseif {!$registryExisted} {
                catch {file delete -force -- $registryPath}
            }
        }
        return -options $options $failure
    }
    if {$registryBackup ne ""} { catch {file delete -force -- $registryBackup} }
    return $ids
}

proc ::GX::acquisitionHandlerDefaultDatasetId {moduleId} {
    variable moduleCfg
    if {[info exists moduleCfg($moduleId,dataset_id)] && [string trim $moduleCfg($moduleId,dataset_id)] ne ""} { return [string trim $moduleCfg($moduleId,dataset_id)] }
    return [string map [list "acq." ""] $moduleId]
}

proc ::GX::acquisitionHandlerImportSync_v089_initial {moduleId {session ""}} {
    variable cfg
    variable currentSession
    variable moduleCfg
    set handlerId [acquisitionHandlerLoadModule $moduleId]
    if {$handlerId eq ""} { error "$moduleId: Acquisition Handler Plugin API is not configured." }
    set src [file normalize $cfg(input_csv)]
    if {![file isfile $src]} { error "$moduleId: input file does not exist: $src" }
    if {$session eq ""} {
        set cfg(session_mode) "measurement"
        set session [makeSession]
        datasetRegistryClear
    } else {
        set session [file normalize $session]
        if {![file isdirectory $session]} { error "$moduleId: target session does not exist: $session" }
        loadDatasetRegistry $session
    }
    set rawRel [file join raw [sanitize $moduleId] [file tail $src]]
    set rawAbs [file join $session $rawRel]
    file mkdir [file dirname $rawAbs]
    file copy -force -- $src $rawAbs
    set rawHash [sha256File $rawAbs]
    set outputDir [file join $session datasets]
    file mkdir $outputDir
    set inspect [acquisitionHandlerInspect $moduleId $src]
    if {[dict exists $inspect recognized] && ![dict get $inspect recognized]} { error "$moduleId: acquisition handler did not recognize the selected input file." }
    if {$::GX::sourceVarCount == 0} { acquisitionHandlerSeedVariables $inspect }
    set cfgDict [dict create]
    foreach key [moduleConfigKeys $moduleId] { if {[info exists moduleCfg($moduleId,$key)]} { dict set cfgDict $key $moduleCfg($moduleId,$key) } }
    set request [dict create api_version 1 module_id $moduleId handler_id $handlerId \
        source_path $src raw_path $rawAbs session_path $session output_dir $outputDir \
        dataset_id [acquisitionHandlerDefaultDatasetId $moduleId] config $cfgDict variables [acquisitionHandlerVariableMap] inspection $inspect]
    set importProc [acquisitionHandlerField $handlerId import_proc ""]
    set result [uplevel #0 [list $importProc $request]]
    set ids [acquisitionHandlerRegisterResult $moduleId $session $rawRel $rawHash $outputDir $result]
    saveDatasetRegistry $session
    set currentSession $session
    writeManifest [file join $session metadata manifest.ini]
    set logPath [file join $session logs pipeline.log]; file mkdir [file dirname $logPath]
    set log [open $logPath a]; fconfigure $log -encoding utf-8 -translation lf
    puts $log "Acquisition Handler Plugin API v1"
    puts $log "Acquisition module: $moduleId"
    puts $log "Handler: $handlerId"
    puts $log "Source: $src"
    puts $log "RAW SHA-256: $rawHash"
    puts $log "Published canonical dataset(s): [join $ids {, }]"
    close $log
    catch {refreshResults}; catch {refreshAnalysisStatus}; catch {refreshGraphs}; catch {refreshNativeVariablesGui}; catch {refreshDatasetInspectionChoices}; catch {refreshAnalysisSourceWidgets}; catch {updateSessionUi}
    return $session
}

proc ::GX::acquisitionHandlerImportSync {moduleId {session ""}} {
    tailcall ::GX::acquisitionHandlerImportSync_v089_initial $moduleId $session
}

proc ::GX::acquisitionHandlerStartPlugin_v089_single {moduleId} {
    variable pipe
    variable currentSession
    variable ui
    variable runAllPending
    if {$pipe ne ""} return
    if {[catch {
        setStatus "Importing through acquisition plug-in..." 5
        if {[info exists ui(startButton)]} { $ui(startButton) configure -state disabled }
        if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state disabled }
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state disabled }
        set session [acquisitionHandlerImportSync $moduleId]
        guiLog "Session: $session"
        guiLog "Acquisition handler plugin: $moduleId"
        setStatus "Acquisition plug-in import completed" 100
    } err opts]} {
        set runAllPending 0
        if {[info exists ui(startButton)]} { $ui(startButton) configure -state normal }
        if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
        if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state disabled }
        setStatus "Error" 0
        if {[llength [info commands tk_messageBox]]} { tk_messageBox -icon error -title "GX-TXT" -message $err }
        return
    }
    if {[info exists ui(startButton)]} { $ui(startButton) configure -state normal }
    if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
    if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
    if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state disabled }
    if {$runAllPending} {
        set runAllPending 0
        guiLog "RUN ALL: acquisition plug-in import completed, starting PHASE 2."
        after 100 ::GX::startAnalysis
    } elseif {[llength [info commands tk_messageBox]]} {
        tk_messageBox -icon info -title "GX-TXT" -message "Acquisition plug-in import completed.\n\n$currentSession"
    }
}

proc ::GX::acquisitionHandlerStartPlugin {moduleId} {
    tailcall ::GX::acquisitionHandlerStartPlugin_v089_single $moduleId
}

# Register legacy adapters in the same registry. Their internals remain exactly
# as in v0.8.8; only dispatch is centralized here.
proc ::GX::acquisitionHandlerStartLegacy {moduleId} {
    return [::GX::startAsync_v088_before_acquisition_handler_dispatch]
}
::GX::acquisitionHandlerRegister generic_csv [dict create kind legacy start_proc ::GX::acquisitionHandlerStartLegacy]
::GX::acquisitionHandlerRegister rigol_csv   [dict create kind legacy start_proc ::GX::acquisitionHandlerStartLegacy]

proc ::GX::startAsync {} {
    variable cfg
    set moduleId $cfg(acquisition_module)
    if {[moduleField $moduleId kind ""] ne "acquisition" || [moduleField $moduleId runner ""] ne "standard_tcl"} {
        error "Acquisition module '$moduleId' is not a standard_tcl acquisition module."
    }
    set handlerId [moduleRunnerHandler $moduleId]
    if {![acquisitionHandlerRegistered $handlerId]} {
        set loaded [acquisitionHandlerLoadModule $moduleId]
        if {$loaded eq ""} { error "$moduleId: missing or unsupported acquisition handler '$handlerId'." }
        set handlerId $loaded
    }
    if {[acquisitionHandlerField $handlerId kind ""] eq "legacy"} {
        set p [acquisitionHandlerField $handlerId start_proc ""]
        return [uplevel #0 [list $p $moduleId]]
    }
    return [acquisitionHandlerStartPlugin $moduleId]
}

# -----------------------------------------------------------------------------
# Framework-owned batch integration for plug-in handlers.
# The historical genericCsvBatch* names remain for backward compatibility, but
# non-legacy acquisition handlers use the same Pending/Imported lifecycle.
# -----------------------------------------------------------------------------

proc ::GX::acquisitionHandlerIsPluginModule {moduleId} {
    if {$moduleId eq ""} { return 0 }
    set h [moduleRunnerHandler $moduleId]
    return [expr {$h ne "generic_csv" && [acquisitionHandlerHasPluginDescriptor $moduleId]}]
}

proc ::GX::acquisitionHandlerCurrentModuleIsPlugin {} {
    variable cfg
    return [acquisitionHandlerIsPluginModule $cfg(acquisition_module)]
}

proc ::GX::acquisitionHandlerDefaultContract {moduleId} {
    set ds [splitList [moduleField $moduleId output_datasets ""]]
    if {[llength $ds]} { return [lindex $ds 0] }
    return "table.generic"
}

proc ::GX::acquisitionHandlerBatchVariableMap {row} {
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    set out {}
    if {![info exists genericCsvBatchVarCount($row)]} { return $out }
    for {set j 1} {$j <= $genericCsvBatchVarCount($row)} {incr j} {
        if {![info exists genericCsvBatchVar($row,$j,enabled)] || !$genericCsvBatchVar($row,$j,enabled)} continue
        set d [dict create]
        foreach f [datasetInspectionVarFields] {
            dict set d $f [expr {[info exists genericCsvBatchVar($row,$j,$f)] ? $genericCsvBatchVar($row,$j,$f) : ""}]
        }
        lappend out $d
    }
    return $out
}

proc ::GX::acquisitionHandlerImportSourceToSession_v089 {moduleId session src proposedId proposedContract variableMap} {
    variable moduleCfg
    set handlerId [acquisitionHandlerLoadModule $moduleId]
    set src [file normalize $src]
    set session [file normalize $session]
    if {![file isfile $src]} { error "$moduleId: input file does not exist: $src" }
    if {![file isdirectory $session]} { error "$moduleId: target session does not exist: $session" }
    if {$proposedId eq ""} { set proposedId [acquisitionHandlerDefaultDatasetId $moduleId] }
    if {$proposedContract eq ""} { set proposedContract [acquisitionHandlerDefaultContract $moduleId] }

    set rawRel [file join raw [sanitize $moduleId] [sanitize $proposedId] [file tail $src]]
    set rawAbs [file join $session $rawRel]
    file mkdir [file dirname $rawAbs]
    file copy -force -- $src $rawAbs
    set rawHash [sha256File $rawAbs]
    set outputDir [file join $session datasets]
    file mkdir $outputDir
    set inspect [acquisitionHandlerInspect $moduleId $src]
    if {[dict exists $inspect recognized] && ![dict get $inspect recognized]} { error "$moduleId: acquisition handler did not recognize '$src'." }
    set cfgDict [dict create]
    foreach key [moduleConfigKeys $moduleId] { if {[info exists moduleCfg($moduleId,$key)]} { dict set cfgDict $key $moduleCfg($moduleId,$key) } }
    set request [dict create api_version 1 module_id $moduleId handler_id $handlerId \
        source_path $src raw_path $rawAbs session_path $session output_dir $outputDir \
        dataset_id $proposedId contract $proposedContract config $cfgDict variables $variableMap inspection $inspect]
    set importProc [acquisitionHandlerField $handlerId import_proc ""]
    set result [uplevel #0 [list $importProc $request]]
    return [acquisitionHandlerRegisterResult $moduleId $session $rawRel $rawHash $outputDir $result]
}

proc ::GX::acquisitionHandlerImportSourceToSession {moduleId session src proposedId proposedContract variableMap} {
    tailcall ::GX::acquisitionHandlerImportSourceToSession_v089 $moduleId $session $src $proposedId $proposedContract $variableMap
}

# Reimplement the public single-source helper on top of the per-source/session
# primitive so the session lifecycle and registration code have one owner.
proc ::GX::acquisitionHandlerImportSync {moduleId {session ""}} {
    variable cfg
    variable currentSession
    if {$cfg(input_csv) eq "" || ![file isfile $cfg(input_csv)]} { error "$moduleId: select an existing input file." }
    if {$session eq ""} {
        set cfg(session_mode) "measurement"
        set session [makeSession]
        datasetRegistryClear
    } else {
        set session [file normalize $session]
        if {![file isdirectory $session]} { error "$moduleId: target session does not exist: $session" }
        loadDatasetRegistry $session
    }
    set inspect [acquisitionHandlerInspect $moduleId $cfg(input_csv)]
    if {$::GX::sourceVarCount == 0} { acquisitionHandlerSeedVariables $inspect }
    set ids [acquisitionHandlerImportSourceToSession $moduleId $session $cfg(input_csv) \
        [acquisitionHandlerDefaultDatasetId $moduleId] [acquisitionHandlerDefaultContract $moduleId] [acquisitionHandlerVariableMap]]
    saveDatasetRegistry $session
    set currentSession $session
    writeManifest [file join $session metadata manifest.ini]
    set logPath [file join $session logs pipeline.log]; file mkdir [file dirname $logPath]
    set log [open $logPath a]; fconfigure $log -encoding utf-8 -translation lf
    puts $log "Acquisition Handler Plugin API v1"
    puts $log "Acquisition module: $moduleId"
    puts $log "Handler: [moduleRunnerHandler $moduleId]"
    puts $log "Source: [file normalize $cfg(input_csv)]"
    puts $log "Published canonical dataset(s): [join $ids {, }]"
    close $log
    catch {refreshResults}; catch {refreshAnalysisStatus}; catch {refreshGraphs}; catch {refreshNativeVariablesGui}; catch {refreshDatasetInspectionChoices}; catch {refreshAnalysisSourceWidgets}; catch {updateSessionUi}
    return $session
}

# Batch add defaults: reuse the existing row store/UI but use the selected
# acquisition plug-in's declared output contract for new rows.
proc ::GX::genericCsvBatchAdd_before_import_queue {{path ""}} {
    variable cfg
    set row [::GX::genericCsvBatchAdd_v088_before_acquisition_handler_batch $path]
    if {[acquisitionHandlerCurrentModuleIsPlugin]} {
        genericCsvBatchSetContract $row [acquisitionHandlerDefaultContract $cfg(acquisition_module)]
        set ::GX::genericCsvBatch($row,delimiter) auto
        set ::GX::genericCsvBatch($row,header_rows) 1
        catch {genericCsvBatchClearVariables $row}
        if {$path ne "" && [file isfile $path]} { catch {genericCsvBatchEnsureVariables $row 1} }
        catch {genericCsvBatchRender}
    }
    return $row
}
proc ::GX::genericCsvBatchAdd {{path ""}} {
    return [::GX::genericCsvBatchAdd_before_import_queue $path]
}

proc ::GX::genericCsvBatchAddMultiple_v089_before_grouping {} {
    variable cfg
    if {![acquisitionHandlerCurrentModuleIsPlugin]} { return [::GX::genericCsvBatchAddMultiple_v088_before_acquisition_handler_batch] }
    set paths [workspaceOpenFile acquisition_dir -multiple 1 -title "Add acquisition sources" -filetypes [acquisitionHandlerFileTypes $cfg(acquisition_module)]]
    if {![llength $paths]} return
    foreach p $paths { genericCsvBatchAdd $p }
}
proc ::GX::genericCsvBatchAddMultiple {} {
    return [::GX::genericCsvBatchAddMultiple_v089_before_grouping]
}

# The single Add file action follows the same Workspace and handler policy as
# Add multiple and each row's Browse action.
proc ::GX::genericCsvBatchChooseOne {} {
    variable cfg
    if {[acquisitionHandlerCurrentModuleIsPlugin]} {
        set types [acquisitionHandlerFileTypes $cfg(acquisition_module)]
    } else {
        set types {{{CSV / text tables} {.csv .txt .tsv}} {{All files} *}}
    }
    set path [workspaceOpenFile acquisition_dir -title "Add acquisition source" -filetypes $types]
    if {$path ne ""} {genericCsvBatchAdd $path}
}

# dataset_inspection_api_v1 already wrapped Browse; wrap the final function.
proc ::GX::genericCsvBatchBrowse {i} {
    variable cfg
    variable genericCsvBatch
    if {![acquisitionHandlerCurrentModuleIsPlugin]} { return [::GX::genericCsvBatchBrowse_v088_before_acquisition_handler_batch $i] }
    set p [workspaceOpenFile acquisition_dir -title "Acquisition source" -filetypes [acquisitionHandlerFileTypes $cfg(acquisition_module)]]
    if {$p eq ""} return
    set genericCsvBatch($i,path) [file normalize $p]
    if {![info exists genericCsvBatch($i,dataset_id)] || [string trim $genericCsvBatch($i,dataset_id)] eq "" || [string match "dataset.*" $genericCsvBatch($i,dataset_id)]} {
        set genericCsvBatch($i,dataset_id) [genericCsvAutoDatasetId $p]
    }
    catch {genericCsvBatchClearVariables $i}
    catch {genericCsvBatchEnsureVariables $i 1}
    catch {refreshManifestPreview}; catch {refreshDatasetInspectionChoices}; catch {genericCsvBatchRender}
}

proc ::GX::genericCsvBatchEnsureVariables_v089_before_group_inspect {row {force 0}} {
    variable cfg
    variable genericCsvBatch
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    if {![acquisitionHandlerCurrentModuleIsPlugin]} { return [::GX::genericCsvBatchEnsureVariables_v088_before_acquisition_handler_batch $row $force] }
    if {!$force && [info exists genericCsvBatchVarCount($row)] && $genericCsvBatchVarCount($row) > 0} { return $genericCsvBatchVarCount($row) }
    set p [expr {[info exists genericCsvBatch($row,path)] ? [string trim $genericCsvBatch($row,path)] : ""}]
    if {$p eq "" || ![file isfile $p]} { return 0 }
    set result [acquisitionHandlerInspect $cfg(acquisition_module) $p]
    genericCsvBatchClearVariables $row
    set j 0
    foreach v [dict get $result variables] {
        incr j
        foreach {f def} {enabled 1 source_column "" source_channel "" original_header "" canonical "" unit "" semantic_role "" instrument_id "" instrument_channel ""} {
            set genericCsvBatchVar($row,$j,$f) $def
        }
        set orig [expr {[dict exists $v original_header] ? [dict get $v original_header] : "C$j"}]
        set genericCsvBatchVar($row,$j,source_column) [expr {[dict exists $v source_column] ? [dict get $v source_column] : $j}]
        set genericCsvBatchVar($row,$j,original_header) $orig
        set genericCsvBatchVar($row,$j,canonical) [expr {[dict exists $v canonical] ? [dict get $v canonical] : $orig}]
        foreach f {source_channel unit semantic_role instrument_id instrument_channel} {
            if {[dict exists $v $f]} { set genericCsvBatchVar($row,$j,$f) [dict get $v $f] }
        }
    }
    set genericCsvBatchVarCount($row) $j
    return $j
}
proc ::GX::genericCsvBatchEnsureVariables {row {force 0}} {
    return [::GX::genericCsvBatchEnsureVariables_v089_before_group_inspect $row $force]
}

proc ::GX::genericCsvBatchValidateSelectedRows_v09780 {rows} {
    variable cfg
    variable genericCsvBatch
    if {![acquisitionHandlerCurrentModuleIsPlugin]} { return [::GX::genericCsvBatchValidateSelectedRows_v088_before_acquisition_handler_batch $rows] }
    set ids {}
    set allowed [splitList [moduleField $cfg(acquisition_module) output_datasets ""]]
    foreach i $rows {
        set path [string trim $genericCsvBatch($i,path)]
        if {$path eq "" || ![file isfile $path]} { error "Batch row $i: select an existing acquisition source." }
        set id [string trim $genericCsvBatch($i,dataset_id)]
        if {$id eq "" || ![regexp {^[A-Za-z0-9_.-]+$} $id]} { error "Batch row $i: invalid Dataset ID '$id'." }
        if {[lsearch -exact $ids $id] >= 0} { error "Batch row $i: duplicate Dataset ID '$id'." }
        lappend ids $id
        set kind [genericCsvBatchResolvedContract $i]
        if {$kind eq ""} { error "Batch row $i: choose a dataset contract." }
        if {[llength $allowed] && [lsearch -exact $allowed $kind] < 0} { error "Batch row $i: contract '$kind' is not declared by $cfg(acquisition_module)." }
        set nvars [genericCsvBatchEnsureVariables $i]
        set variableMode [acquisitionHandlerVariableMappingMode $cfg(acquisition_module)]
        if {$nvars <= 0 && $variableMode eq "required"} {
            error "Batch row $i: acquisition handler did not expose any source variables (variable_mapping=required)."
        }
        if {$nvars > 0} { genericCsvBatchValidateVariables $i }
    }
}
proc ::GX::genericCsvBatchValidateSelectedRows {rows} {
    return [::GX::genericCsvBatchValidateSelectedRows_v09780 $rows]
}

proc ::GX::genericCsvBatchImportRowToSession_v09780 {session i} {
    variable cfg
    variable genericCsvBatch
    if {![acquisitionHandlerCurrentModuleIsPlugin]} { return [::GX::genericCsvBatchImportRowToSession_v088_before_acquisition_handler_batch $session $i] }
    set id [string trim $genericCsvBatch($i,dataset_id)]
    set kind [genericCsvBatchResolvedContract $i]
    set ids [acquisitionHandlerImportSourceToSession $cfg(acquisition_module) $session $genericCsvBatch($i,path) $id $kind [acquisitionHandlerBatchVariableMap $i]]
    return "Source: $genericCsvBatch($i,path) | dataset(s): [join $ids {, }] | handler: [moduleRunnerHandler $cfg(acquisition_module)]"
}
proc ::GX::genericCsvBatchImportRowToSession {session i} {
    return [::GX::genericCsvBatchImportRowToSession_v09780 $session $i]
}

# Make the existing batch workspace generic for plug-in acquisition modules.
# Generic CSV retains its delimiter/header columns; plug-in rows omit them.
proc ::GX::genericCsvBatchRender {} {
    variable cfg
    variable ui
    variable genericCsvBatch
    variable genericCsvBatchCount
    if {![acquisitionHandlerCurrentModuleIsPlugin]} {
        return [::GX::genericCsvBatchRender_v088_before_acquisition_handler_batch]
    }
    if {![info exists ui(genericBatchInner)] || ![winfo exists $ui(genericBatchInner)]} return
    set p $ui(genericBatchInner)
    set imported [genericCsvBatchImportedIds]
    foreach child [winfo children $p] { destroy $child }
    foreach {col txt} {0 Use 1 {Source file} 2 {} 3 {Dataset ID} 4 Contract 5 {Other / custom contract} 6 Status 7 Preview 8 Variables 9 {}} {
        if {$txt ne ""} { ttk::label $p.h$col -text $txt; grid $p.h$col -row 0 -column $col -sticky w -padx 3 -pady 2 }
    }
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        ttk::checkbutton $p.use$i -variable ::GX::genericCsvBatch($i,enabled) -command ::GX::genericCsvBatchStateChanged
        ttk::entry $p.path$i -textvariable ::GX::genericCsvBatch($i,path) -width 52
        ttk::button $p.browse$i -text "..." -width 3 -command [list ::GX::genericCsvBatchBrowse $i]
        ttk::entry $p.id$i -textvariable ::GX::genericCsvBatch($i,dataset_id) -width 22
        ttk::combobox $p.kind$i -textvariable ::GX::genericCsvBatch($i,contract_choice) -values [contractRegistryChoices] -state readonly -width 22
        ttk::entry $p.other$i -textvariable ::GX::genericCsvBatch($i,custom_contract) -width 24
        set rowId [string trim $genericCsvBatch($i,dataset_id)]
        if {[genericCsvBatchRowStatus $i] eq {Failed}} {
            ttk::button $p.status$i -text {Failed: details...} -command [list ::GX::acquisitionHandlerBatchRowDiagnostic $i]
        } else {
            ttk::label $p.status$i -text [genericCsvBatchRowStatus $i]
        }
        ttk::button $p.prev$i -text "Preview" -command [list ::GX::datasetInspectionSelectPendingPreview $i]
        ttk::button $p.vars$i -text "Variables" -command [list ::GX::datasetInspectionSelectPendingVariables $i]
        ttk::button $p.rm$i -text "Remove" -command [list ::GX::genericCsvBatchRemove $i]
        set ui(genericContractCombo,$i) $p.kind$i
        bind $p.kind$i <<ComboboxSelected>> [list ::GX::genericCsvBatchContractChanged $i]
        bind $p.other$i <KeyRelease> [list ::GX::refreshManifestPreview]
        bind $p.path$i <KeyRelease> [list ::GX::genericCsvBatchStateChanged]
        bind $p.id$i <KeyRelease> [list ::GX::genericCsvBatchStateChanged]
        foreach {w c} [list $p.use$i 0 $p.path$i 1 $p.browse$i 2 $p.id$i 3 $p.kind$i 4 $p.other$i 5 $p.status$i 6 $p.prev$i 7 $p.vars$i 8 $p.rm$i 9] {
            grid $w -row $i -column $c -padx 3 -pady 2 -sticky [expr {$c == 1 ? "ew" : ""}]
        }
    }
    acquisitionQueueLayout $p
    update idletasks
    genericCsvBatchScrollRefresh
    catch {refreshDatasetInspectionChoices}; catch {genericCsvBatchRefreshImportButton}
}

proc ::GX::acquisitionHandlerRefreshBatchLabel_v089 {} {
    variable cfg
    set box .top.nb.acq.batch
    if {![winfo exists $box]} return
    if {[acquisitionHandlerCurrentModuleIsPlugin]} {
        catch {$box configure -text "Multi-source canonical dataset import (Acquisition Handler API v1)"}
        if {[winfo exists $box.note]} { catch {$box.note configure -text "Each enabled Pending source is imported through the selected acquisition plug-in. The framework owns session/RAW/registry lifecycle; the plug-in owns only format parsing and canonicalization."} }
    } else {
        catch {$box configure -text "Multi-CSV canonical dataset import (v0.8.2)"}
        if {[winfo exists $box.note]} { catch {$box.note configure -text "Each enabled row becomes one canonical dataset. Known contracts come from installed plugin descriptors; choose Other... to enter an undeclared/custom contract literally. The table scrolls vertically and horizontally."} }
    }
    if {![info exists cfg(acquisition_source_storage)]} {set cfg(acquisition_source_storage) copy}
    if {![winfo exists $box.bar.storageLabel]} {
        ttk::label $box.bar.storageLabel -text "Original source:"
        ttk::radiobutton $box.bar.copy -text "Copy into Session" -variable ::GX::cfg(acquisition_source_storage) -value copy
        ttk::radiobutton $box.bar.reference -text "Keep/reference original" -variable ::GX::cfg(acquisition_source_storage) -value reference
        pack $box.bar.storageLabel $box.bar.copy $box.bar.reference -side left -padx 4
    }
    set supported [expr {[acquisitionHandlerCurrentModuleIsPlugin] && [acquisitionHandlerSectionField $cfg(acquisition_module) supports_external_raw 0] eq "1"}]
    $box.bar.reference state [expr {$supported ? "!disabled" : "disabled"}]
    if {!$supported} {set cfg(acquisition_source_storage) copy}
    catch {genericCsvBatchRender}
}

proc ::GX::acquisitionHandlerRefreshBatchLabel {} {
    tailcall ::GX::acquisitionHandlerRefreshBatchLabel_v089
}

proc ::GX::onAcquisitionModuleChanged_before_import_queue {} {
    ::GX::onAcquisitionModuleChanged_v088_before_acquisition_handler_batch
    catch {acquisitionHandlerRefreshBatchLabel}
}

proc ::GX::onAcquisitionModuleChanged {} {
    tailcall ::GX::onAcquisitionModuleChanged_before_import_queue
}

# For plug-in handlers the main Run uses the same framework-owned batch lifecycle
# when Use batch table is enabled and the handler advertises supports_batch=1.
proc ::GX::acquisitionHandlerStartPlugin_v089_before_async {moduleId} {
    variable genericCsvBatchEnabled
    set handlerId [acquisitionHandlerLoadModule $moduleId]
    set supports [acquisitionHandlerField $handlerId supports_batch 0]
    if {[info exists genericCsvBatchEnabled] && $genericCsvBatchEnabled && $supports} {
        variable currentSession
        variable ui
        variable runAllPending
        if {[catch {
            setStatus "Importing acquisition source batch..." 5
            if {[info exists ui(startButton)]} { $ui(startButton) configure -state disabled }
            if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state disabled }
            if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state disabled }
            set session [genericCsvBatchImportSync]
            guiLog "Session: $session"
            guiLog "Acquisition Handler API batch module: $moduleId"
            setStatus "Acquisition source batch completed" 100
        } err opts]} {
            set runAllPending 0
            if {[info exists ui(startButton)]} { $ui(startButton) configure -state normal }
            if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
            if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
            if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state disabled }
            setStatus "Error" 0
            if {[llength [info commands tk_messageBox]]} { tk_messageBox -icon error -title "GX-TXT" -message $err }
            return
        }
        if {[info exists ui(startButton)]} { $ui(startButton) configure -state normal }
        if {[info exists ui(analysisStart)]} { $ui(analysisStart) configure -state normal }
        if {[info exists ui(runAllButton)]} { $ui(runAllButton) configure -state normal }
        if {[info exists ui(stopButton)]} { $ui(stopButton) configure -state disabled }
        if {$runAllPending} { set runAllPending 0; after 100 ::GX::startAnalysis }
        return
    }
    return [::GX::acquisitionHandlerStartPlugin_v089_single $moduleId]
}

proc ::GX::acquisitionHandlerStartPlugin {moduleId} {
    tailcall ::GX::acquisitionHandlerStartPlugin_v089_before_async $moduleId
}

# =============================================================================
# GX-TXT v0.9.0 additive Acquisition Handler Plugin API v1 extensions
# =============================================================================
# These extensions deliberately keep api_version=1.  Existing v0.8.9 handlers
# remain valid.  New optional capabilities are descriptor driven; no vendor or
# format-specific dispatch is added to the framework.

namespace eval ::GX {
    variable acquisitionHandlerAsyncActive 0
    variable acquisitionHandlerAsyncState {}
    variable acquisitionHandlerCancelFlag 0
    variable acquisitionFormatRegistry
    array unset acquisitionFormatRegistry *
}

proc ::GX::acquisitionHandlerDeclaredCapabilities {moduleId} {
    set caps [splitList [acquisitionHandlerSectionField $moduleId capabilities ""]]
    if {[acquisitionHandlerSourceKind $moduleId] eq "binary"} { lappend caps binary_source preview_descriptor }
    if {[acquisitionHandlerSectionField $moduleId supports_batch 0]} { lappend caps batch }
    foreach {key cap} {
        preflight_proc preflight
        dataset_preview_proc dataset_preview
        group_proc multi_file_group
        group_inspect_proc multi_file_group_inspect
        begin_proc cooperative_async
        step_proc cooperative_async
        cancel_proc cancellation
    } {
        if {[string trim [acquisitionHandlerSectionField $moduleId $key ""]] ne ""} { lappend caps $cap }
    }
    if {[lsearch -exact $caps cooperative_async] >= 0} { lappend caps streaming progress }
    return [lsort -dictionary -unique $caps]
}

proc ::GX::acquisitionHandlerCapabilities {handlerId} {
    return [splitList [acquisitionHandlerField $handlerId capabilities ""]]
}

proc ::GX::acquisitionHandlerHasCapability {handlerId capability} {
    return [expr {[lsearch -exact [acquisitionHandlerCapabilities $handlerId] $capability] >= 0}]
}

proc ::GX::acquisitionHandlerModuleSupportsBatch {moduleId} {
    if {$moduleId eq "" || ![acquisitionHandlerIsPluginModule $moduleId]} { return 0 }
    set hid [moduleRunnerHandler $moduleId]
    if {[acquisitionHandlerRegistered $hid]} {
        return [expr {[acquisitionHandlerField $hid supports_batch 0] || [acquisitionHandlerHasCapability $hid batch]}]
    }
    return [expr {[acquisitionHandlerSectionField $moduleId supports_batch 0] || [lsearch -exact [acquisitionHandlerDeclaredCapabilities $moduleId] batch] >= 0}]
}

# Replace only the loader body extension points.  The v0.8.9 loader still owns
# safety checks and mandatory inspect/import callbacks.
proc ::GX::acquisitionHandlerLoadModule {moduleId} {
    variable acquisitionHandlerRegistry
    set handlerId [::GX::acquisitionHandlerLoadModule_v089 $moduleId]
    if {$handlerId eq "" || ![acquisitionHandlerRegistered $handlerId]} { return $handlerId }
    if {[acquisitionHandlerField $handlerId kind ""] ne "plugin"} { return $handlerId }
    set d $acquisitionHandlerRegistry($handlerId)
    dict set d capabilities [join [acquisitionHandlerDeclaredCapabilities $moduleId] {;}]
    foreach key {preflight_proc dataset_preview_proc group_proc group_inspect_proc begin_proc step_proc cancel_proc} {
        set p [string trim [acquisitionHandlerSectionField $moduleId $key ""]]
        if {$p ne ""} {
            if {![llength [info commands $p]]} { error "$moduleId: acquisition_handler.$key '$p' is not callable." }
            dict set d $key $p
        }
    }
    dict set d formats [acquisitionHandlerSectionField $moduleId formats ""]
    dict set d source_kind [acquisitionHandlerSourceKind $moduleId]
    dict set d variable_mapping [acquisitionHandlerVariableMappingMode $moduleId]
    set acquisitionHandlerRegistry($handlerId) $d
    acquisitionFormatRegistryRefresh
    return $handlerId
}

# --- Formal format / MIME registry -------------------------------------------
proc ::GX::acquisitionFormatRegistryRefresh {} {
    variable acquisitionFormatRegistry
    variable moduleOrder
    array unset acquisitionFormatRegistry *
    foreach moduleId $moduleOrder {
        if {![acquisitionHandlerIsPluginModule $moduleId]} continue
        foreach fid [splitList [acquisitionHandlerSectionField $moduleId formats ""]] {
            set acquisitionFormatRegistry($fid,id) $fid
            set acquisitionFormatRegistry($fid,module_id) $moduleId
            foreach {field def} {description "" mime "application/octet-stream" extensions "" canonical_formats ""} {
                set acquisitionFormatRegistry($fid,$field) [descriptorValue $::GX::moduleCatalog($moduleId,dict) "acquisition_format.$fid" $field $def]
            }
        }
    }
    return [acquisitionFormatRegistryIds]
}
proc ::GX::acquisitionFormatRegistryIds {} {
    variable acquisitionFormatRegistry
    set out {}
    foreach k [array names acquisitionFormatRegistry "*,id"] { lappend out [string range $k 0 end-3] }
    return [lsort -dictionary -unique $out]
}
proc ::GX::acquisitionFormatField {fid field {default ""}} {
    variable acquisitionFormatRegistry
    if {[info exists acquisitionFormatRegistry($fid,$field)]} { return $acquisitionFormatRegistry($fid,$field) }
    return $default
}

# Refresh the format registry after every normal module catalog load.
proc ::GX::loadModuleCatalog_before_semantic_registry {} {
    ::GX::loadModuleCatalog_v089_before_acq_v090
    catch {acquisitionFormatRegistryRefresh}
}

# --- Progress / cancellation callbacks --------------------------------------
proc ::GX::acquisitionHandlerProgressCallback {moduleId event} {
    if {[catch {dict size $event}]} { set event [dict create message $event] }
    dict set event api_version 1
    dict set event module_id $moduleId
    if {![dict exists $event state]} { dict set event state running }
    return [progressPublish $event]
}
proc ::GX::acquisitionHandlerLogCallback {moduleId text} {
    guiLog "$moduleId: $text"
    return $text
}
proc ::GX::acquisitionHandlerCancelRequested {} {
    variable acquisitionHandlerCancelFlag
    return $acquisitionHandlerCancelFlag
}
proc ::GX::acquisitionHandlerRequestCallbacks {moduleId} {
    return [dict create \
        progress_callback [list ::GX::acquisitionHandlerProgressCallback $moduleId] \
        log_callback [list ::GX::acquisitionHandlerLogCallback $moduleId] \
        cancel_callback [list ::GX::acquisitionHandlerCancelRequested]]
}
proc ::GX::acquisitionHandlerInvokeCallback {prefix args} {
    if {![llength $prefix]} return
    return [uplevel #0 [concat $prefix $args]]
}

# --- Preflight ---------------------------------------------------------------
proc ::GX::acquisitionHandlerPreflight {moduleId sourcePaths} {
    set hid [acquisitionHandlerLoadModule $moduleId]
    set p [acquisitionHandlerField $hid preflight_proc ""]
    if {$p eq ""} { return [dict create ok 1 checks {} warnings {} errors {}] }
    set req [dict create api_version 1 module_id $moduleId handler_id $hid source_paths $sourcePaths]
    dict for {k v} [acquisitionHandlerRequestCallbacks $moduleId] { dict set req $k $v }
    set r [uplevel #0 [list $p $req]]
    if {[catch {dict size $r}]} { error "$moduleId: preflight_proc must return a dict." }
    foreach {k def} {ok 1 checks {} warnings {} errors {}} { if {![dict exists $r $k]} { dict set r $k $def } }
    return $r
}

proc ::GX::acquisitionHandlerPreflightDialog {} {
    variable cfg
    set moduleId $cfg(acquisition_module)
    if {![acquisitionHandlerIsPluginModule $moduleId]} { return }
    set paths {}
    if {[info exists ::GX::genericCsvBatchEnabled] && $::GX::genericCsvBatchEnabled} {
        foreach i [genericCsvBatchEnabledRows] {
            if {[info exists ::GX::genericCsvBatch($i,source_paths)] && [llength $::GX::genericCsvBatch($i,source_paths)]} {
                foreach p $::GX::genericCsvBatch($i,source_paths) { lappend paths $p }
            } elseif {[info exists ::GX::genericCsvBatch($i,path)]} { lappend paths $::GX::genericCsvBatch($i,path) }
        }
    }
    if {![llength $paths] && $cfg(input_csv) ne ""} { set paths [list $cfg(input_csv)] }
    if {[catch {set r [acquisitionHandlerPreflight $moduleId $paths]} err]} { tk_messageBox -icon error -title "Acquisition preflight" -message $err; return }
    set w .gxAcqPreflight; catch {destroy $w}; toplevel $w; wm title $w "Acquisition preflight — $moduleId"; wm geometry $w 820x520
    grid columnconfigure $w 0 -weight 1; grid rowconfigure $w 0 -weight 1
    text $w.t -wrap word -font TkFixedFont; ttk::scrollbar $w.sy -orient vertical -command [list $w.t yview]; $w.t configure -yscrollcommand [list $w.sy set]
    grid $w.t -row 0 -column 0 -sticky nsew -padx {8 0} -pady 8; grid $w.sy -row 0 -column 1 -sticky ns -pady 8
    $w.t insert end "Module: $moduleId\nOK: [dict get $r ok]\n\n"
    foreach sec {checks warnings errors} { $w.t insert end "[string toupper $sec]\n[string repeat = [string length $sec]]\n"; foreach x [dict get $r $sec] { $w.t insert end "- $x\n" }; $w.t insert end "\n" }
    $w.t configure -state disabled
    ttk::button $w.close -text Close -command [list destroy $w]; grid $w.close -row 1 -column 0 -columnspan 2 -sticky e -padx 8 -pady {0 8}
}

# --- Instrument suggestions --------------------------------------------------
proc ::GX::acquisitionHandlerApplyInstrumentSuggestions {inspection} {
    variable instrumentCatalog
    variable instruments
    variable instrumentCount
    if {![dict exists $inspection instrument_suggestions]} return
    foreach s [dict get $inspection instrument_suggestions] {
        if {[catch {dict size $s}]} continue
        set mid [expr {[dict exists $s instrument_plugin_id] ? [dict get $s instrument_plugin_id] : ""}]
        if {$mid eq "" || ![info exists instrumentCatalog($mid,dict)]} continue
        set serial [expr {[dict exists $s serial] ? [dict get $s serial] : ""}]
        set exists 0
        for {set i 1} {$i <= $instrumentCount} {incr i} {
            if {[info exists instruments($i,module_id)] && $instruments($i,module_id) eq $mid} {
                if {$serial eq "" || ([info exists instruments($i,serial)] && $instruments($i,serial) eq $serial)} { set exists 1; break }
            }
        }
        if {$exists} continue
        set n [addInstrumentFromModule $mid]
        foreach f {id display_name type role manufacturer model serial firmware notes} {
            if {[dict exists $s $f]} { set instruments($n,$f) [dict get $s $f] }
        }
        guiLog "Instrument suggestion accepted from acquisition metadata: $mid"
    }
    catch {refreshNativeInstrumentationGui}
}

# --- Multi-file grouping -----------------------------------------------------
proc ::GX::acquisitionHandlerGroupSources {moduleId paths} {
    set hid [acquisitionHandlerLoadModule $moduleId]
    set p [acquisitionHandlerField $hid group_proc ""]
    if {$p eq ""} {
        set out {}; foreach path $paths { lappend out [dict create label [file tail $path] source_paths [list [file normalize $path]]] }; return $out
    }
    set req [dict create api_version 1 module_id $moduleId handler_id $hid source_paths $paths]
    set r [uplevel #0 [list $p $req]]
    if {[catch {dict size $r}] || ![dict exists $r groups]} { error "$moduleId: group_proc must return a dict containing groups." }
    return [dict get $r groups]
}

proc ::GX::acquisitionHandlerInspectSources {moduleId sourcePaths} {
    set hid [acquisitionHandlerLoadModule $moduleId]
    set gp [acquisitionHandlerField $hid group_inspect_proc ""]
    if {$gp ne "" && [llength $sourcePaths] > 1} {
        set req [dict create api_version 1 module_id $moduleId handler_id $hid source_paths $sourcePaths]
        set r [uplevel #0 [list $gp $req]]
        if {[catch {dict size $r}]} { error "$moduleId: group_inspect_proc must return a dict." }
        foreach key {recognized format variables metadata preview_rows warnings instrument_suggestions} {
            if {![dict exists $r $key]} { dict set r $key [expr {$key in {variables preview_rows warnings instrument_suggestions} ? [list] : ($key eq "metadata" ? [dict create] : "")}] }
        }
        return $r
    }
    return [acquisitionHandlerInspect $moduleId [lindex $sourcePaths 0]]
}

proc ::GX::acquisitionHandlerImportSourcesToSession {moduleId session sourcePaths proposedId proposedContract variableMap} {
    variable moduleCfg
    set hid [acquisitionHandlerLoadModule $moduleId]
    set session [file normalize $session]
    if {![file isdirectory $session]} { error "$moduleId: target session does not exist: $session" }
    set norm {}
    foreach src $sourcePaths { set src [file normalize $src]; if {![file isfile $src]} { error "$moduleId: input file does not exist: $src" }; lappend norm $src }
    if {![llength $norm]} { error "$moduleId: no input sources were supplied." }
    if {$proposedId eq ""} { set proposedId [acquisitionHandlerDefaultDatasetId $moduleId] }
    set proposedId [acquisitionHandlerValidateDatasetId $proposedId "$moduleId proposed Dataset ID"]
    if {$proposedContract eq ""} { set proposedContract [acquisitionHandlerDefaultContract $moduleId] }
    set rawRels {}; set rawAbsList {}; set rawHashes {}; set n 0
    foreach src $norm {
        incr n
        set rawRel [file join raw [sanitize $moduleId] [sanitize $proposedId] [format "%03d_%s" $n [file tail $src]]]
        set rawAbs [file join $session $rawRel]; file mkdir [file dirname $rawAbs]; file copy -force -- $src $rawAbs
        lappend rawRels $rawRel; lappend rawAbsList $rawAbs; lappend rawHashes [sha256File $rawAbs]
    }
    set outputDir [file join $session datasets]; file mkdir $outputDir
    set inspect [acquisitionHandlerInspectSources $moduleId $norm]
    if {[dict exists $inspect recognized] && ![dict get $inspect recognized]} { error [_acquisitionHandlerUnrecognizedReason $moduleId $inspect] }
    set pf [acquisitionHandlerPreflight $moduleId $norm]
    if {![dict get $pf ok] || [llength [dict get $pf errors]]} { error "$moduleId: acquisition preflight failed: [join [dict get $pf errors] {; }]" }
    set cfgDict [dict create]; foreach key [moduleConfigKeys $moduleId] { if {[info exists moduleCfg($moduleId,$key)]} { dict set cfgDict $key $moduleCfg($moduleId,$key) } }
    set request [dict create api_version 1 module_id $moduleId handler_id $hid source_path [lindex $norm 0] source_paths $norm raw_path [lindex $rawAbsList 0] raw_paths $rawAbsList session_path $session output_dir $outputDir dataset_id $proposedId contract $proposedContract config $cfgDict variables $variableMap inspection $inspect]
    dict for {k v} [acquisitionHandlerRequestCallbacks $moduleId] { dict set request $k $v }
    set importProc [acquisitionHandlerField $hid import_proc ""]
    set result [uplevel #0 [list $importProc $request]]
    set ids [acquisitionHandlerRegisterResult $moduleId $session [lindex $rawRels 0] [lindex $rawHashes 0] $outputDir $result]
    foreach id $ids {
        datasetRegister $id [list source_count [llength $norm] source_raw_list [join $rawRels {;}] source_sha256_list [join $rawHashes {;}] acquisition_capabilities [join [acquisitionHandlerCapabilities $hid] {;}]]
    }
    acquisitionHandlerApplyInstrumentSuggestions $inspect
    return $ids
}

# Cooperative handlers use the same private staging boundary. The scheduler
# remains unchanged; only begin/finalize ownership is revised.
proc ::GX::acquisitionHandlerStartCooperative_atomic_v09781 {moduleId} {
    variable cfg
    variable acquisitionHandlerAsyncActive
    variable acquisitionHandlerAsyncState
    variable acquisitionHandlerCancelFlag
    variable ui
    variable datasetRegistry
    if {$acquisitionHandlerAsyncActive} return
    set hid [acquisitionHandlerLoadModule $moduleId]
    set bp [acquisitionHandlerField $hid begin_proc ""]
    set sp [acquisitionHandlerField $hid step_proc ""]
    if {$bp eq "" || $sp eq ""} { error "$moduleId: cooperative_async requires begin_proc and step_proc." }
    set src [file normalize $cfg(input_csv)]
    if {![file isfile $src]} { error "$moduleId: input file does not exist: $src" }
    set id [acquisitionHandlerValidateDatasetId [acquisitionHandlerDefaultDatasetId $moduleId] "$moduleId proposed Dataset ID"]
    set inspect [acquisitionHandlerInspect $moduleId $src]
    if {[dict exists $inspect recognized] && ![dict get $inspect recognized]} {
        error "$moduleId: acquisition handler did not recognize the source."
    }
    set pf [acquisitionHandlerPreflight $moduleId [list $src]]
    if {![dict get $pf ok] || [llength [dict get $pf errors]]} {
        error "$moduleId: acquisition preflight failed: [join [dict get $pf errors] {; }]"
    }
    set cfg(session_mode) measurement
    if {$::GX::currentSession ne {} && [file isdirectory $::GX::currentSession]} {set session [file normalize $::GX::currentSession]} else {set session [makeSession];datasetRegistryClear}
    set importToken [interactiveDocumentSessionToken]
    set rawRel [file join raw [sanitize $moduleId] [sanitize $id] [format "001_%s" [file tail $src]]]
    set finalRaw [file join $session $rawRel]
    if {[file exists $finalRaw]} { error "$moduleId: RAW destination already exists: $finalRaw" }
    set txnRoot [file join $session .acquisition-txn]
    file mkdir $txnRoot
    set txn [file join $txnRoot [format "%s-%s-%s" [sanitize $id] [pid] [clock clicks]]]
    set rawAbs [file join $txn $rawRel]
    file mkdir [file dirname $rawAbs]
    file mkdir [file join $txn datasets]
    set registryPath [datasetRegistryPath $session]
    set registryExisted [file isfile $registryPath]
    if {$registryExisted} { file copy -- $registryPath [file join $txn registry.snapshot] }
    set priorRegistry [array get datasetRegistry]
    if {[catch {
        file copy -- $src $rawAbs
        set rawHash [sha256File $rawAbs]
        set cfgDict {};foreach key [moduleConfigKeys $moduleId] {if {[info exists ::GX::moduleCfg($moduleId,$key)]} {dict set cfgDict $key $::GX::moduleCfg($moduleId,$key)}}
        set req [dict create api_version 1 module_id $moduleId handler_id $hid \
            source_path $src source_paths [list $src] raw_path $rawAbs raw_paths [list $rawAbs] \
            session_path $session output_dir [file join $txn datasets] dataset_id $id \
            config $cfgDict contract [acquisitionHandlerDefaultContract $moduleId] variables [acquisitionHandlerVariableMap] inspection $inspect]
        dict for {k v} [acquisitionHandlerRequestCallbacks $moduleId] { dict set req $k $v }
        set token [uplevel #0 [list $bp $req]]
    } failure options]} {
        catch {file delete -force -- $txn}
        return -options $options $failure
    }
    set acquisitionHandlerCancelFlag 0
    set acquisitionHandlerAsyncActive 1
    set acquisitionHandlerAsyncState [dict create module_id $moduleId handler_id $hid session $session \
        session_token $importToken txn $txn raw_rel $rawRel raw_hash $rawHash prior_registry $priorRegistry \
        registry_existed $registryExisted request $req state_token $token]
    foreach k {startButton analysisStart runAllButton} {
        if {[info exists ui($k)] && [winfo exists $ui($k)]} { $ui($k) configure -state disabled }
    }
    if {[info exists ui(stopButton)] && [winfo exists $ui(stopButton)]} { $ui(stopButton) configure -state normal }
    progressPublish [dict create state running mode indeterminate module_id $moduleId message "Streaming acquisition"]
    after 1 ::GX::acquisitionHandlerAsyncStep
}

proc ::GX::acquisitionHandlerAsyncFinalize_atomic_v09781 {ok payload} {
    variable acquisitionHandlerAsyncActive
    variable acquisitionHandlerAsyncState
    variable acquisitionHandlerCancelFlag
    variable currentSession
    variable datasetRegistry
    variable ui
    set ctx $acquisitionHandlerAsyncState
    set moduleId [dict get $ctx module_id]
    set session [dict get $ctx session]
    if {$currentSession eq {} || [file normalize $currentSession] ne $session || [interactiveDocumentSessionToken] ne [dict get $ctx session_token]} {
        catch {file delete -force -- [dict get $ctx txn]}
        set acquisitionHandlerAsyncActive 0;set acquisitionHandlerAsyncState {};set acquisitionHandlerCancelFlag 0
        progressPublish [dict create state cancelled module_id $moduleId message {Session changed; no acquisition outputs committed}]
        foreach k {startButton analysisStart runAllButton} {if {[info exists ui($k)] && [winfo exists $ui($k)]} {$ui($k) configure -state normal}}
        return
    }
    if {![datasetAuthorityActive $session]} {return [datasetAuthorityTransaction $session ::GX::acquisitionHandlerAsyncFinalize_atomic_v09781 $ok $payload]}
    loadDatasetRegistry $session
    dict set ctx prior_registry [array get datasetRegistry]
    set registryPath [datasetRegistryPath $session]
    dict set ctx registry_existed [file isfile $registryPath]
    datasetAuthorityEnlist $registryPath
    if {[file isfile $registryPath]} {file copy -force -- $registryPath [file join [dict get $ctx txn] registry.snapshot]}
    set txn [dict get $ctx txn]
    set moved {}
    set metadataDir [file join $session metadata datasets]
    set priorMetadata [glob -nocomplain -directory $metadataDir *]
    if {$ok} {
        set rc [catch {
            set result $payload
            if {[dict exists $result outcome] && [dict get $result outcome] eq {registered_session_script}} {
                if {$moduleId ne {acq.text_document}} {error {Importer has not declared Session script outcomes}}
                lassign [acquisitionHandlerSafeDatasetPath $session [file join $txn datasets] [dict get $result source_path]] scriptSource unused
                set receipt [scriptRegistryImportSource $session $scriptSource [dict get $result script_id] [dict get $result name] [dict get $result language] [dict get $result provenance]]
                set ids [list [dict get $receipt reference]]
            } else {
            if {[catch {dict size $result}] || ![dict exists $result datasets]} {
                error "$moduleId: asynchronous result must contain datasets."
            }
            set finals {}; set seen {}
            foreach ds [dict get $result datasets] {
                if {![dict exists $ds dataset_id] || ![dict exists $ds path]} {
                    error "$moduleId: asynchronous dataset requires dataset_id and path."
                }
                set id [acquisitionHandlerValidateDatasetId [dict get $ds dataset_id] "$moduleId returned Dataset ID"]
                if {[lsearch -exact $seen $id] >= 0 || [datasetField $id id ""] ne ""} {
                    error "$moduleId: duplicate or existing Dataset ID '$id'."
                }
                lappend seen $id
                lassign [_datasetMetadataPath $session $id] unused metadataPath
                if {[file exists $metadataPath]} { error "$moduleId: metadata destination exists: $metadataPath" }
                acquisitionHandlerSafeDatasetPath $session [file join $txn datasets] [dict get $ds path]
                set final [file normalize [file join $session datasets [dict get $ds path]]]
                if {[file exists $final] || [lsearch -exact $finals $final] >= 0} {
                    error "$moduleId: dataset payload destination exists: $final"
                }
                lappend finals $final
            }
            if {![llength $finals]} { error "$moduleId: asynchronous result contains no datasets." }
            set rawFinal [file join $session [dict get $ctx raw_rel]]
            if {[file exists $rawFinal]} { error "$moduleId: RAW destination exists: $rawFinal" }
            file mkdir [file dirname $rawFinal]
            datasetAuthorityEnlist $rawFinal
            file rename -- [file join $txn [dict get $ctx raw_rel]] $rawFinal
            lappend moved $rawFinal
            foreach ds [dict get $result datasets] final $finals {
                file mkdir [file dirname $final]
                datasetAuthorityEnlist $final
                file rename -- [file join $txn datasets [dict get $ds path]] $final
                lappend moved $final
            }
            set ids [acquisitionHandlerRegisterResult $moduleId $session [dict get $ctx raw_rel] \
                [dict get $ctx raw_hash] [file join $session datasets] $result]
            saveDatasetRegistry $session
            writeManifest [file join $session metadata manifest.ini]
            }
        } failure]
        if {!$rc} {
            set currentSession $session
            if {[catch {acquisitionHandlerReceiptSave $session $moduleId [dict get $ctx request source_paths] $ids} receiptError]} {guiLog "Import succeeded; operation receipt unavailable: $receiptError"}
            guiLog "Cooperative acquisition completed: [join $ids {, }]"
            progressPublish [dict create state completed mode determinate current 1 total 1 module_id $moduleId message "Acquisition completed"]
        } else {
            set ok 0
            set payload $failure
        }
    }
    if {!$ok} {
        foreach path [lreverse $moved] { catch {file delete -- $path} }
        foreach path [glob -nocomplain -directory $metadataDir *] {
            if {[lsearch -exact $priorMetadata $path] < 0} { catch {file delete -- $path} }
        }
        array unset datasetRegistry *
        array set datasetRegistry [dict get $ctx prior_registry]
        set registryPath [datasetRegistryPath $session]
        if {[dict get $ctx registry_existed]} {
            catch {file copy -force -- [file join $txn registry.snapshot] $registryPath}
        } else { catch {file delete -- $registryPath} }
        guiLog "Cooperative acquisition failed/cancelled: $payload"
        progressPublish [dict create state [expr {$acquisitionHandlerCancelFlag ? "cancelled" : "failed"}] module_id $moduleId message $payload]
    }
    catch {file delete -force -- $txn}
    set acquisitionHandlerAsyncActive 0
    set acquisitionHandlerAsyncState {}
    set acquisitionHandlerCancelFlag 0
    foreach k {startButton analysisStart runAllButton} {
        if {[info exists ui($k)] && [winfo exists $ui($k)]} { $ui($k) configure -state normal }
    }
    if {[info exists ui(stopButton)] && [winfo exists $ui(stopButton)]} { $ui(stopButton) configure -state disabled }
    catch {refreshResults}; catch {refreshNativeVariablesGui}; catch {refreshDatasetInspectionChoices}; catch {updateSessionUi}
}

# Batch preflight guards shared identifiers and destinations; a bad source is a
# row failure, not a reason to suppress later valid rows.
proc ::GX::genericCsvBatchPreflightRows {rows {session ""}} {
    variable cfg
    variable genericCsvBatch
    set seen {}
    set paths {}
    if {$session ne ""} { set session [file normalize $session] }
    foreach i $rows {
        set id [acquisitionHandlerValidateDatasetId [string trim $genericCsvBatch($i,dataset_id)] "Batch row $i Dataset ID"]
        if {[dict exists $seen $id]} { error "Batch rows [dict get $seen $id] and $i have duplicate Dataset ID '$id'." }
        dict set seen $id $i
        if {$session ne "" && [datasetField $id id ""] ne ""} {
            error "Batch row $i: Dataset ID '$id' already exists in the session."
        }
        set kind [genericCsvBatchResolvedContract $i]
        if {[string trim $kind] eq "" || [regexp {[\r\n]} $kind]} {
            error "Batch row $i: invalid dataset contract."
        }
        if {[acquisitionHandlerCurrentModuleIsPlugin]} {
            set allowed [splitList [moduleField $cfg(acquisition_module) output_datasets ""]]
            if {[llength $allowed] && [lsearch -exact $allowed $kind] < 0} {
                error "Batch row $i: contract '$kind' is not declared by $cfg(acquisition_module)."
            }
            set sources [expr {[info exists genericCsvBatch($i,source_paths)] && [llength $genericCsvBatch($i,source_paths)] ? $genericCsvBatch($i,source_paths) : [list $genericCsvBatch($i,path)]}]
            set n 0
            foreach source $sources {
                incr n
                set rel [file join raw [sanitize $cfg(acquisition_module)] [sanitize $id] [format "%03d_%s" $n [file tail $source]]]
                if {$session ne "" && [file exists [file join $session $rel]]} {
                    error "Batch row $i: RAW destination already exists: $rel"
                }
                if {[dict exists $paths $rel]} { error "Batch rows [dict get $paths $rel] and $i share RAW destination '$rel'." }
                dict set paths $rel $i
            }
        } else {
            set rel [file join datasets "${id}.csv"]
            if {$session ne "" && [file exists [file join $session $rel]]} {
                error "Batch row $i: dataset payload destination already exists: $rel"
            }
            set rawRel [file join raw $id [file tail $genericCsvBatch($i,path)]]
            if {$session ne "" && [file exists [file join $session $rawRel]]} {
                error "Batch row $i: RAW destination already exists: $rawRel"
            }
        }
    }
}

proc ::GX::genericCsvBatchRecord {row status {message ""}} {
    variable genericCsvBatchResult
    variable genericCsvBatch
    set genericCsvBatchResult($row,status) $status
    set genericCsvBatchResult($row,message) $message
    set genericCsvBatch($row,acquisition_status) $status
    set genericCsvBatch($row,acquisition_message) $message
}

proc ::GX::acquisitionHandlerBatchRowDiagnostic {row} {
    variable genericCsvBatchResult
    if {![info exists genericCsvBatchResult($row,status)] || $genericCsvBatchResult($row,status) ne {Failed}} return
    set parent [expr {[winfo exists .top] ? {.top} : {.}}]
    tk_messageBox -parent $parent -icon error -title {Import source details} -message "Source row $row\n\n$genericCsvBatchResult($row,message)"
}

proc ::GX::genericCsvBatchRowStatus_before_import_queue {row} {
    variable genericCsvBatchResult
    if {[info exists genericCsvBatchResult($row,status)]} { return $genericCsvBatchResult($row,status) }
    return [::GX::genericCsvBatchRowStatus_v09780 $row]
}
proc ::GX::genericCsvBatchRowStatus {row} {
    return [::GX::genericCsvBatchRowStatus_before_import_queue $row]
}

proc ::GX::genericCsvBatchValidateSelectedRows_v089_before_group_validation {rows} {
    variable currentSession
    genericCsvBatchPreflightRows $rows $currentSession
}
proc ::GX::genericCsvBatchValidateSelectedRows {rows} {
    return [::GX::genericCsvBatchValidateSelectedRows_v089_before_group_validation $rows]
}

proc ::GX::genericCsvBatchValidate {} {
    variable cfg
    variable genericCsvBatchEnabled
    if {!$genericCsvBatchEnabled} { return }
    if {$cfg(output_root) eq ""} { error "Specify the session root folder." }
    set rows [genericCsvBatchEnabledRows]
    if {![llength $rows]} { error "Batch import is enabled but no rows are enabled." }
    genericCsvBatchPreflightRows $rows
}

proc ::GX::_acqBatchExecuteRows {session rows} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    variable genericCsvBatchResult
    variable acquisitionHandlerBatchLastReport
    array unset genericCsvBatchResult *
    set summary [dict create imported 0 failed 0 skipped 0]
    set entries {}
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        if {![info exists genericCsvBatch($i,enabled)] || !$genericCsvBatch($i,enabled)} {
            genericCsvBatchRecord $i Skipped "Disabled"
            dict incr summary skipped
            lappend entries [dict create row $i status Skipped message Disabled]
        }
    }
    set logLines {}
    foreach i $rows {
        if {[catch {
            set line [genericCsvBatchImportRowToSession $session $i]
            if {![acquisitionHandlerCurrentModuleIsPlugin]} { saveDatasetRegistry $session }
        } err]} {
            genericCsvBatchRecord $i Failed $err
            dict incr summary failed
            lappend entries [dict create row $i status Failed message $err]
            lappend logLines "Batch row $i FAILED: $err"
            continue
        }
        genericCsvBatchRecord $i Imported $line
        dict incr summary imported
        lappend entries [dict create row $i status Imported message $line]
        lappend logLines "Batch row $i IMPORTED: $line"
    }
    set acquisitionHandlerBatchLastReport [dict create summary $summary rows $entries session $session]
    return $logLines
}

proc ::GX::genericCsvBatchRunRows {session rows} {
    return [_acqBatchExecuteRows $session $rows]
}

proc ::GX::genericCsvBatchImportSync {} {
    variable cfg
    variable genericCsvBatch
    variable currentSession
    genericCsvBatchValidate
    set rows [genericCsvBatchEnabledRows]
    set cfg(session_mode) analysis_only
    foreach i $rows {
        set path [string trim $genericCsvBatch($i,path)]
        if {[file isfile $path]} { set cfg(input_csv) $path; break }
    }
    set session [makeSession]
    datasetRegistryClear
    genericCsvBatchPreflightRows $rows $session
    set logLines [genericCsvBatchRunRows $session $rows]
    writeManifest [file join $session metadata manifest.ini]
    set logPath [file join $session logs pipeline.log]
    file mkdir [file dirname $logPath]
    set log [open $logPath a]
    fconfigure $log -encoding utf-8 -translation lf
    puts $log "Batch acquisition results"
    foreach line $logLines { puts $log $line }
    close $log
    set currentSession $session
    catch {genericCsvBatchRender}; catch {refreshDatasetInspectionChoices}; catch {genericCsvBatchRefreshImportButton}
    return $session
}

proc ::GX::genericCsvBatchImportIntoCurrentSessionSync_before_import_queue {} {
    variable genericCsvBatchEnabled
    variable currentSession
    if {!$genericCsvBatchEnabled} { error "Enable 'Use batch table' before importing batch datasets." }
    if {$currentSession eq "" || ![file isdirectory $currentSession]} {
        error "Create or open a session before importing additional batch datasets."
    }
    loadDatasetRegistry $currentSession
    set rows [genericCsvBatchPendingEnabledRows]
    if {![llength $rows]} { return $currentSession }
    genericCsvBatchPreflightRows $rows $currentSession
    set logLines [genericCsvBatchRunRows $currentSession $rows]
    writeManifest [file join $currentSession metadata manifest.ini]
    set logPath [file join $currentSession logs pipeline.log]
    file mkdir [file dirname $logPath]
    set log [open $logPath a]
    fconfigure $log -encoding utf-8 -translation lf
    puts $log "Additional batch acquisition results"
    foreach line $logLines { puts $log $line }
    close $log
    catch {genericCsvBatchRender}; catch {refreshDatasetInspectionChoices}; catch {refreshNativeVariablesGui}
    catch {refreshStandardModuleControls}; catch {genericCsvBatchRefreshImportButton}
    return $currentSession
}
proc ::GX::genericCsvBatchImportIntoCurrentSessionSync {} {
    return [::GX::genericCsvBatchImportIntoCurrentSessionSync_before_import_queue]
}

# The built-in CSV row follows the same no-overwrite, rollback-on-failure rule.
proc ::GX::genericCsvBatchImportRowToSession_v089_before_grouping {session i} {
    variable cfg
    variable genericCsvBatch
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    variable datasetRegistry
    variable scriptDir
    if {[acquisitionHandlerCurrentModuleIsPlugin]} {
        return [::GX::genericCsvBatchImportRowToSession_v09780 $session $i]
    }
    set src [file normalize $genericCsvBatch($i,path)]
    if {![file isfile $src]} { error "Batch row $i: source does not exist: $src" }
    set builderId [expr {[info exists genericCsvBatch($i,importer_definition)] ? $genericCsvBatch($i,importer_definition) : ""}]
    if {$builderId ne ""} { set builder [importerBuilderGet $builderId] }
    set id [acquisitionHandlerValidateDatasetId [string trim $genericCsvBatch($i,dataset_id)] "Batch row $i Dataset ID"]
    if {[datasetField $id id ""] ne ""} { error "Batch row $i: Dataset ID '$id' already exists." }
    set kind [genericCsvBatchResolvedContract $i]
    set rawRel [file join raw $id [file tail $src]]
    set dataRel [file join datasets "${id}.csv"]
    set rawDst [file join $session $rawRel]
    set dataDst [file join $session $dataRel]
    foreach dst [list $rawDst $dataDst] {
        if {[file exists $dst]} { error "Batch row $i: destination already exists: $dst" }
    }
    genericCsvBatchEnsureVariables $i
    genericCsvBatchValidateVariables $i
    set txnRoot [file join $session .acquisition-txn]
    file mkdir $txnRoot
    set txn [file join $txnRoot [format "csv-%s-%s-%s" $id [pid] [clock clicks]]]
    file mkdir $txn
    set priorRegistry [array get datasetRegistry]
    set registryPath [datasetRegistryPath $session]
    set registryExisted [file isfile $registryPath]
    if {$registryExisted} { file copy -- $registryPath [file join $txn registry.snapshot] }
    set moved {}
    set rc [catch {
        set stageRaw [file join $txn source]
        set stageData [file join $txn canonical.csv]
        file copy -- $src $stageRaw
        set srcHash [sha256File $stageRaw]
        if {$builderId ne "" && [dict get $builder delimiter] eq "whitespace"} {
            set token whitespace
            set canonicalToken comma
        } else {
            set delim [csvDelimiter $stageRaw $genericCsvBatch($i,delimiter)]
            set token [expr {$delim eq "," ? "comma" : ($delim eq ";" ? "semicolon" : "tab")}]
            set canonicalToken $token
        }
        set helper [file join $scriptDir plugins modules acq.generic_csv runtime canonicalize_csv.py]
        if {$builderId ne ""} {
            set effectiveBuilder $builder
            if {[dict get $effectiveBuilder delimiter] eq "auto"} { dict set effectiveBuilder delimiter $token }
            set cmd [importerBuilderCommand $effectiveBuilder $stageRaw $stageData]
        } else {
            set cmd [list [runtimeToolResolve python] $helper --input $stageRaw --output $stageData \
                --delimiter $token --header-rows $genericCsvBatch($i,header_rows)]
        }
        set vars {}; set varMeta {}
        for {set j 1} {$j <= $genericCsvBatchVarCount($i)} {incr j} {
            foreach f [datasetInspectionVarFields] { lappend varMeta var${j}_$f $genericCsvBatchVar($i,$j,$f) }
            if {!$genericCsvBatchVar($i,$j,enabled)} continue
            set canon [string trim $genericCsvBatchVar($i,$j,canonical)]
            if {$builderId eq ""} { lappend cmd --map "$genericCsvBatchVar($i,$j,source_column)=$canon" }
            lappend vars $canon
        }
        if {[catch {exec {*}$cmd 2>@1} out]} { error "Batch row $i ($id): canonical CSV conversion failed: $out" }
        if {![regexp {(?m)^rows=([0-9]+)$} [string trim $out] -> rowCount]} {
            error "Batch row $i ($id): canonical CSV conversion did not report its row count."
        }
        if {![regexp {(?m)^kinds=([a-z;]+)$} [string trim $out] -> kinds]} {
            error "Batch row $i ($id): canonical CSV conversion did not report column types."
        }
        set inferredKinds [split $kinds {;}]
        if {[llength $inferredKinds] != [llength $vars]} {error "Batch row $i ($id): inferred column count differs from canonical columns."}
        set activeColumn -1
        for {set j 1} {$j <= $genericCsvBatchVarCount($i)} {incr j} {
            if {!$genericCsvBatchVar($i,$j,enabled)} continue
            incr activeColumn
            if {[lindex $inferredKinds $activeColumn] eq "text"} {
                lappend varMeta var${j}_value_kind text var${j}_dtype string var${j}_value_inferred 1
            }
        }
        set canonHash [sha256File $stageData]
        file mkdir [file dirname $rawDst]
        file mkdir [file dirname $dataDst]
        file rename -- $stageRaw $rawDst
        lappend moved $rawDst
        file rename -- $stageData $dataDst
        lappend moved $dataDst
        set fields [list kind $kind format csv path $dataRel row_count $rowCount columns [join $vars ,] variables [join $vars ,] \
            var_count $genericCsvBatchVarCount($i) source_header_rows $genericCsvBatch($i,header_rows) \
            source_delimiter $token canonical_delimiter $canonicalToken source_module acq.generic_csv \
            source_raw $rawRel source_sha256 $srcHash canonical_sha256 $canonHash \
            created_at [clock format [clock seconds] -format "%Y-%m-%dT%H:%M:%S%z"] immutable 0 \
            notes "Canonical CSV generated by GX-TXT multi-CSV variable mapping"]
        if {$builderId ne ""} {
            lappend fields importer_definition $builderId importer_version [dict get $builder version]
            dict for {key value} [importerBuilderMetadata $builder $src] { lappend fields $key $value }
        }
        datasetRegister $id [concat $fields $varMeta]
        saveDatasetRegistry $session
    } failure options]
    if {$rc} {
        foreach path [lreverse $moved] { catch {file delete -- $path} }
        array unset datasetRegistry *
        array set datasetRegistry $priorRegistry
        if {$registryExisted} {
            catch {file copy -force -- [file join $txn registry.snapshot] $registryPath}
        } else {
            catch {file delete -- $registryPath}
        }
    }
    catch {file delete -force -- $txn}
    if {$rc} { return -options $options $failure }
    return "Dataset: $id | contract: $kind | variables: [join $vars ,] | source: $src"
}
proc ::GX::genericCsvBatchImportRowToSession {session i} {
    return [::GX::genericCsvBatchImportRowToSession_v089_before_grouping $session $i]
}

# Preserve the public single-source helper while routing it through N-source code.
proc ::GX::acquisitionHandlerImportSourceToSession {moduleId session src proposedId proposedContract variableMap} {
    return [acquisitionHandlerImportSourcesToSession $moduleId $session [list $src] $proposedId $proposedContract $variableMap]
}

# --- Non-CSV imported dataset preview ---------------------------------------
proc ::GX::acquisitionHandlerDatasetPreview {datasetId {previewDir ""}} {
    variable currentSession
    set moduleId [datasetField $datasetId source_module ""]
    if {$moduleId eq "" || ![acquisitionHandlerIsPluginModule $moduleId]} { return {} }
    set hid [acquisitionHandlerLoadModule $moduleId]
    set p [acquisitionHandlerField $hid dataset_preview_proc ""]
    if {$p eq ""} { return {} }
    if {[string trim $previewDir] ne ""} { set previewDir [file normalize $previewDir]; file mkdir $previewDir }
    set path [datasetResolvePath $currentSession $datasetId]
    set req [dict create api_version 1 module_id $moduleId handler_id $hid dataset_id $datasetId dataset_path $path session_path $currentSession format [datasetField $datasetId format ""] contract [datasetField $datasetId kind ""] storage_kind [datasetField $datasetId storage_kind "text"] media_type [datasetField $datasetId media_type ""] preview_dir $previewDir]
    set r [uplevel #0 [list $p $req]]
    if {[catch {dict size $r}]} { error "$moduleId: dataset_preview_proc must return a dict." }
    dict set r source_kind [datasetField $datasetId storage_kind "text"]
    return $r
}

proc ::GX::datasetInspectionRenderPreview_v1_before_schema {w choice} {
    lassign [datasetInspectionParseChoice $choice] mode key
    if {$mode eq "imported"} {
        set storageKind [string tolower [datasetField $key storage_kind "text"]]
        set format [string tolower [datasetField $key format "csv"]]
        if {$storageKind eq "binary" || $format ne "csv"} {
            previewDescriptorClearWidgetArtifact $w
            set previewDir [previewDescriptorCreateTempDir]
            set r {}
            catch {set r [acquisitionHandlerDatasetPreview $key $previewDir]}
            $w configure -state normal; $w delete 1.0 end
            $w insert end "DATASET PREVIEW\n===============\nState: IMPORTED\nDataset ID: $key\nContract: [datasetField $key kind ""]\nFormat: [datasetField $key format ""]\nStorage kind: $storageKind\nMedia type: [datasetField $key media_type ""]\nFile: [datasetResolvePath $::GX::currentSession $key]\n\n"
            if {$storageKind eq "binary"} {
                if {[catch {set pd [previewDescriptorNormalize $r $previewDir]} perr]} {
                    if {[dict size $r]} { $w insert end "PREVIEW DESCRIPTOR ERROR\n========================\n$perr\n" }
                } else { previewDescriptorRenderTextWidget $w $pd }
                if {![dict size $r]} { $w insert end "Binary dataset registered safely. No dataset preview provider is available; raw bytes are intentionally not rendered.\n" }
            } elseif {[dict size $r]} {
                if {[dict exists $r text] && [string trim [dict get $r text]] ne ""} { $w insert end "[dict get $r text]\n" }
                if {[dict exists $r metadata] && [dict size [dict get $r metadata]]} { $w insert end "\nMETADATA\n========\n"; dict for {k v} [dict get $r metadata] { $w insert end "$k: $v\n" } }
                if {[dict exists $r rows] && [llength [dict get $r rows]]} { $w insert end "\nDATA SAMPLE\n===========\n"; foreach row [dict get $r rows] { $w insert end "[join $row { | }]\n" } }
                if {[dict exists $r preview_kind] && [string trim [dict get $r preview_kind]] ni {"" legacy}} {
                    if {![catch {set pd [previewDescriptorNormalize $r $previewDir]}]} { previewDescriptorRenderTextWidget $w $pd }
                }
            } else {
                previewDescriptorCleanupDir $previewDir
                return [::GX::datasetInspectionRenderPreview_v089 $w $choice]
            }
            $w configure -state disabled
            previewDescriptorCleanupDir $previewDir
            return
        }
    }
    return [::GX::datasetInspectionRenderPreview_v089 $w $choice]
}
proc ::GX::datasetInspectionRenderPreview {w choice} {
    return [::GX::datasetInspectionRenderPreview_v1_before_schema $w $choice]
}

# --- File chooser -> batch bridge -------------------------------------------
proc ::GX::acquisitionHandlerFindBatchRowByPath {path} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    set target [file normalize $path]
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        if {[info exists genericCsvBatch($i,path)] && [string trim $genericCsvBatch($i,path)] ne "" && [file normalize $genericCsvBatch($i,path)] eq $target} { return $i }
    }
    return 0
}
proc ::GX::acquisitionHandlerSyncChosenFileToBatch {moduleId path} {
    variable genericCsvBatchEnabled
    variable genericCsvBatch
    if {![acquisitionHandlerModuleSupportsBatch $moduleId]} { return 0 }
    set genericCsvBatchEnabled 1
    set row [acquisitionHandlerFindBatchRowByPath $path]
    if {$row == 0} { set row [genericCsvBatchAdd $path] }
    set genericCsvBatch($row,enabled) 1
    set genericCsvBatch($row,path) [file normalize $path]
    catch {genericCsvBatchEnsureVariables $row 1}
    catch {genericCsvBatchRender}; catch {genericCsvBatchStateChanged}; catch {acquisitionHandlerRefreshBatchLabel}
    return $row
}

# Retain the legacy chooser entry for Tcl callers. The current Importer page
# collects sources through its batch controls instead of binding this command.
proc ::GX::chooseInput {} {
    variable cfg
    set before $cfg(input_csv)
    set r [::GX::chooseInput_v089_before_batch_bridge]
    if {$cfg(input_csv) ne "" && $cfg(input_csv) ne $before && [acquisitionHandlerIsPluginModule $cfg(acquisition_module)] && [acquisitionHandlerModuleSupportsBatch $cfg(acquisition_module)]} {
        acquisitionHandlerSyncChosenFileToBatch $cfg(acquisition_module) $cfg(input_csv)
    }
    return $r
}

# Group selected files when a batch-capable plug-in declares multi_file_group.
proc ::GX::genericCsvBatchAddMultiple {} {
    variable cfg
    if {![acquisitionHandlerCurrentModuleIsPlugin]} { return [::GX::genericCsvBatchAddMultiple_v089_before_grouping] }
    set paths [workspaceOpenFile acquisition_dir -multiple 1 -title "Add acquisition sources" -filetypes [acquisitionHandlerFileTypes $cfg(acquisition_module)]]
    if {![llength $paths]} return
    set hid [acquisitionHandlerLoadModule $cfg(acquisition_module)]
    if {[acquisitionHandlerHasCapability $hid multi_file_group]} {
        foreach g [acquisitionHandlerGroupSources $cfg(acquisition_module) $paths] {
            if {![dict exists $g source_paths] || ![llength [dict get $g source_paths]]} continue
            set sp [dict get $g source_paths]
            set row [genericCsvBatchAdd [lindex $sp 0]]
            set ::GX::genericCsvBatch($row,source_paths) $sp
            if {[dict exists $g dataset_id] && [string trim [dict get $g dataset_id]] ne ""} { set ::GX::genericCsvBatch($row,dataset_id) [dict get $g dataset_id] }
            if {[dict exists $g label]} { set ::GX::genericCsvBatch($row,source_group_label) [dict get $g label] }
        }
        catch {genericCsvBatchRender}; return
    }
    foreach p $paths { genericCsvBatchAdd $p }
}

# Import grouped rows through the N-source primitive.
proc ::GX::genericCsvBatchImportRowToSession {session i} {
    variable cfg
    variable genericCsvBatch
    if {[acquisitionHandlerCurrentModuleIsPlugin] && [info exists genericCsvBatch($i,source_paths)] && [llength $genericCsvBatch($i,source_paths)] > 1} {
        set id [string trim $genericCsvBatch($i,dataset_id)]
        set kind [genericCsvBatchResolvedContract $i]
        set ids [acquisitionHandlerImportSourcesToSession $cfg(acquisition_module) $session $genericCsvBatch($i,source_paths) $id $kind [acquisitionHandlerBatchVariableMap $i]]
        return "Source group ([llength $genericCsvBatch($i,source_paths)] files): [join $genericCsvBatch($i,source_paths) {; }] | dataset(s): [join $ids {, }]"
    }
    return [::GX::genericCsvBatchImportRowToSession_v089_before_grouping $session $i]
}

# --- Cooperative asynchronous / streaming handler contract ------------------
# begin_proc(request) -> token/dict
# step_proc(request-with-state) -> dict state=running|completed|failed,
#                                 state_token=?, result=?, progress=?
# The framework schedules step_proc with after, keeping Tk responsive.
proc ::GX::acquisitionHandlerAsyncFinalize_v09780 {ok payload} {
    variable acquisitionHandlerAsyncActive
    variable acquisitionHandlerAsyncState
    variable acquisitionHandlerCancelFlag
    variable currentSession
    variable ui
    set ctx $acquisitionHandlerAsyncState
    set moduleId [dict get $ctx module_id]
    set session [dict get $ctx session]
    if {$ok} {
        set ids [acquisitionHandlerRegisterResult $moduleId $session [dict get $ctx raw_rel] [dict get $ctx raw_hash] [dict get $ctx output_dir] $payload]
        saveDatasetRegistry $session; set currentSession $session; writeManifest [file join $session metadata manifest.ini]
        guiLog "Cooperative acquisition completed: [join $ids {, }]"
        progressPublish [dict create state completed mode determinate current 1 total 1 module_id $moduleId message "Acquisition completed"]
    } else {
        guiLog "Cooperative acquisition failed/cancelled: $payload"
        progressPublish [dict create state [expr {$acquisitionHandlerCancelFlag ? "cancelled" : "failed"}] module_id $moduleId message $payload]
    }
    set acquisitionHandlerAsyncActive 0; set acquisitionHandlerAsyncState {}; set acquisitionHandlerCancelFlag 0
    foreach k {startButton analysisStart runAllButton} { if {[info exists ui($k)] && [winfo exists $ui($k)]} { $ui($k) configure -state normal } }
    if {[info exists ui(stopButton)] && [winfo exists $ui(stopButton)]} { $ui(stopButton) configure -state disabled }
    catch {refreshResults}; catch {refreshNativeVariablesGui}; catch {refreshDatasetInspectionChoices}; catch {updateSessionUi}
}

proc ::GX::acquisitionHandlerAsyncStep {} {
    variable acquisitionHandlerAsyncActive
    variable acquisitionHandlerAsyncState
    variable acquisitionHandlerCancelFlag
    if {!$acquisitionHandlerAsyncActive} return
    set ctx $acquisitionHandlerAsyncState
    set moduleId [dict get $ctx module_id]; set hid [dict get $ctx handler_id]
    if {$acquisitionHandlerCancelFlag} {
        set cp [acquisitionHandlerField $hid cancel_proc ""]
        if {$cp ne ""} { catch {uplevel #0 [list $cp [dict create api_version 1 module_id $moduleId state_token [dict get $ctx state_token]]]} }
        acquisitionHandlerAsyncFinalize 0 "Cancelled by user"; return
    }
    set p [acquisitionHandlerField $hid step_proc ""]
    set req [dict get $ctx request]; dict set req state_token [dict get $ctx state_token]
    if {[catch {set r [uplevel #0 [list $p $req]]} err]} { acquisitionHandlerAsyncFinalize 0 $err; return }
    if {[catch {dict size $r}]} { acquisitionHandlerAsyncFinalize 0 "step_proc must return a dict"; return }
    if {[dict exists $r progress]} { catch {acquisitionHandlerProgressCallback $moduleId [dict get $r progress]} }
    if {[dict exists $r state_token]} { dict set ctx state_token [dict get $r state_token]; set acquisitionHandlerAsyncState $ctx }
    set state [string tolower [expr {[dict exists $r state] ? [dict get $r state] : "running"}]]
    switch -- $state {
        completed { if {![dict exists $r result]} { acquisitionHandlerAsyncFinalize 0 "completed step missing result" } else { acquisitionHandlerAsyncFinalize 1 [dict get $r result] }; return }
        failed { acquisitionHandlerAsyncFinalize 0 [expr {[dict exists $r error] ? [dict get $r error] : "Acquisition handler reported failure"}]; return }
        cancelled { set acquisitionHandlerCancelFlag 1; acquisitionHandlerAsyncFinalize 0 "Cancelled"; return }
    }
    after 1 ::GX::acquisitionHandlerAsyncStep
}

proc ::GX::acquisitionHandlerStartCooperative_v09780 {moduleId} {
    variable cfg
    variable currentSession
    variable acquisitionHandlerAsyncActive
    variable acquisitionHandlerAsyncState
    variable acquisitionHandlerCancelFlag
    variable ui
    if {$acquisitionHandlerAsyncActive} return
    set hid [acquisitionHandlerLoadModule $moduleId]
    set bp [acquisitionHandlerField $hid begin_proc ""]; set sp [acquisitionHandlerField $hid step_proc ""]
    if {$bp eq "" || $sp eq ""} { error "$moduleId: cooperative_async requires begin_proc and step_proc." }
    set src [file normalize $cfg(input_csv)]; if {![file isfile $src]} { error "$moduleId: input file does not exist: $src" }
    set cfg(session_mode) measurement; set session [makeSession]; datasetRegistryClear
    set rawRel [file join raw [sanitize $moduleId] [file tail $src]]; set rawAbs [file join $session $rawRel]; file mkdir [file dirname $rawAbs]; file copy -force -- $src $rawAbs; set rawHash [sha256File $rawAbs]
    set outDir [file join $session datasets]; file mkdir $outDir
    set inspect [acquisitionHandlerInspect $moduleId $src]
    set req [dict create api_version 1 module_id $moduleId handler_id $hid source_path $src source_paths [list $src] raw_path $rawAbs raw_paths [list $rawAbs] session_path $session output_dir $outDir dataset_id [acquisitionHandlerDefaultDatasetId $moduleId] contract [acquisitionHandlerDefaultContract $moduleId] variables [acquisitionHandlerVariableMap] inspection $inspect]
    dict for {k v} [acquisitionHandlerRequestCallbacks $moduleId] { dict set req $k $v }
    set token [uplevel #0 [list $bp $req]]
    set acquisitionHandlerCancelFlag 0; set acquisitionHandlerAsyncActive 1
    set acquisitionHandlerAsyncState [dict create module_id $moduleId handler_id $hid session $session raw_rel $rawRel raw_hash $rawHash output_dir $outDir request $req state_token $token]
    foreach k {startButton analysisStart runAllButton} { if {[info exists ui($k)] && [winfo exists $ui($k)]} { $ui($k) configure -state disabled } }
    if {[info exists ui(stopButton)] && [winfo exists $ui(stopButton)]} { $ui(stopButton) configure -state normal }
    progressPublish [dict create state running mode indeterminate module_id $moduleId message "Streaming acquisition"]
    after 1 ::GX::acquisitionHandlerAsyncStep
}

proc ::GX::stopCurrent {} {
    if {[info exists ::GX::acquisitionHandlerAsyncActive] && $::GX::acquisitionHandlerAsyncActive} { set ::GX::acquisitionHandlerCancelFlag 1; return }
    return [::GX::stopCurrent_v089_before_acq_async]
}

# Select cooperative async only for non-batch direct runs. Batch import remains
# framework-owned and synchronous unless a future batch scheduler is requested.
proc ::GX::acquisitionHandlerStartPlugin {moduleId} {
    set hid [acquisitionHandlerLoadModule $moduleId]
    if {[acquisitionHandlerHasCapability $hid cooperative_async] && !([info exists ::GX::genericCsvBatchEnabled] && $::GX::genericCsvBatchEnabled && [acquisitionHandlerModuleSupportsBatch $moduleId])} {
        if {[catch {acquisitionHandlerStartCooperative $moduleId} err]} { tk_messageBox -icon error -title GX-TXT -message $err }
        return
    }
    return [::GX::acquisitionHandlerStartPlugin_v089_before_async $moduleId]
}

# --- GUI capability integration ---------------------------------------------
proc ::GX::acquisitionHandlerRefreshBatchLabel_before_import_queue {} {
    ::GX::acquisitionHandlerRefreshBatchLabel_v089
    variable cfg
    set b .top.nb.acq.batch.bar
    if {[winfo exists $b] && [acquisitionHandlerCurrentModuleIsPlugin]} {
        catch {$b.add configure -text "+ Add source"}
        catch {$b.multi configure -text "Add sources..."}
        if {[acquisitionHandlerModuleSupportsBatch $cfg(acquisition_module)]} {
            catch {$b.enabled configure -text "Use source batch"}
        }
    } else {
        catch {$b.add configure -text "+ Add CSV"}; catch {$b.multi configure -text "Add multiple..."}; catch {$b.enabled configure -text "Use batch table"}
    }
    set api .top.nb.acq.api
    if {[winfo exists $api]} {
        if {![winfo exists $api.preflight]} { ttk::button $api.preflight -text "Preflight..." -command ::GX::acquisitionHandlerPreflightDialog; grid $api.preflight -row 0 -column 2 -sticky w -padx 4 -pady 3 }
        set show 0
        if {[acquisitionHandlerCurrentModuleIsPlugin]} { set hid [acquisitionHandlerLoadModule $cfg(acquisition_module)]; set show [acquisitionHandlerHasCapability $hid preflight] }
        if {$show} { grid $api.preflight } else { grid remove $api.preflight }
    }
}

proc ::GX::acquisitionHandlerRefreshBatchLabel {} {
    tailcall ::GX::acquisitionHandlerRefreshBatchLabel_before_import_queue
}

# Persist optional grouped source lists in Manifest Format 2.
proc ::GX::manifestStringV2_v090_before_plot_region {} {
    variable genericCsvBatchCount
    variable genericCsvBatch
    set out [::GX::manifestStringV2_v089_before_acq_group_manifest]
    append out "\n\[acquisition_batch_extensions\]\n"
    appendKV out api_version 1
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        if {[info exists genericCsvBatch($i,source_paths)] && [llength $genericCsvBatch($i,source_paths)] > 1} {
            append out "\n\[acquisition_batch_source.$i\]\n"
            appendKV out paths [join $genericCsvBatch($i,source_paths) {;}]
            appendKV out label [expr {[info exists genericCsvBatch($i,source_group_label)] ? $genericCsvBatch($i,source_group_label) : ""}]
        }
    }
    return $out
}

proc ::GX::loadManifestV2_v090_before_plot_region {path} {
    variable genericCsvBatchCount
    variable genericCsvBatch
    ::GX::loadManifestV2_v089_before_acq_group_manifest $path
    set d [parseIni $path]
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        set pre "acquisition_batch_source.$i"
        if {[dict exists $d "$pre.paths"]} { set genericCsvBatch($i,source_paths) [splitList [dict get $d "$pre.paths"]] }
        if {[dict exists $d "$pre.label"]} { set genericCsvBatch($i,source_group_label) [dict get $d "$pre.label"] }
    }
    catch {genericCsvBatchRender}
}

# Keep grouped-row metadata aligned when rows are removed.
proc ::GX::genericCsvBatchRemove_before_importer_builder {idx} {
    variable genericCsvBatch
    variable genericCsvBatchCount
    set saved {}
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        dict set saved $i source_paths [expr {[info exists genericCsvBatch($i,source_paths)] ? $genericCsvBatch($i,source_paths) : {}}]
        dict set saved $i source_group_label [expr {[info exists genericCsvBatch($i,source_group_label)] ? $genericCsvBatch($i,source_group_label) : ""}]
    }
    ::GX::genericCsvBatchRemove_v089_before_group_fields $idx
    for {set i 1} {$i <= $genericCsvBatchCount} {incr i} {
        catch {unset genericCsvBatch($i,source_paths)}; catch {unset genericCsvBatch($i,source_group_label)}
        set src [expr {$i >= $idx ? $i+1 : $i}]
        if {[dict exists $saved $src source_paths] && [llength [dict get $saved $src source_paths]]} { set genericCsvBatch($i,source_paths) [dict get $saved $src source_paths] }
        if {[dict exists $saved $src source_group_label] && [dict get $saved $src source_group_label] ne ""} { set genericCsvBatch($i,source_group_label) [dict get $saved $src source_group_label] }
    }
}
proc ::GX::genericCsvBatchRemove {idx} {
    return [::GX::genericCsvBatchRemove_before_importer_builder $idx]
}

# Group-aware variable inspection.
proc ::GX::genericCsvBatchEnsureVariables_before_importer_builder {row {force 0}} {
    variable cfg
    variable genericCsvBatch
    variable genericCsvBatchVar
    variable genericCsvBatchVarCount
    if {![acquisitionHandlerCurrentModuleIsPlugin] || ![info exists genericCsvBatch($row,source_paths)] || [llength $genericCsvBatch($row,source_paths)] <= 1} {
        return [::GX::genericCsvBatchEnsureVariables_v089_before_group_inspect $row $force]
    }
    if {!$force && [info exists genericCsvBatchVarCount($row)] && $genericCsvBatchVarCount($row) > 0} { return $genericCsvBatchVarCount($row) }
    set result [acquisitionHandlerInspectSources $cfg(acquisition_module) $genericCsvBatch($row,source_paths)]
    genericCsvBatchClearVariables $row
    set j 0
    foreach v [dict get $result variables] {
        incr j
        foreach {f def} {enabled 1 source_column "" source_channel "" original_header "" canonical "" unit "" semantic_role "" instrument_id "" instrument_channel ""} { set genericCsvBatchVar($row,$j,$f) $def }
        set orig [expr {[dict exists $v original_header] ? [dict get $v original_header] : "C$j"}]
        set genericCsvBatchVar($row,$j,source_column) [expr {[dict exists $v source_column] ? [dict get $v source_column] : $j}]
        set genericCsvBatchVar($row,$j,original_header) $orig
        set genericCsvBatchVar($row,$j,canonical) [expr {[dict exists $v canonical] ? [dict get $v canonical] : $orig}]
        foreach f {source_channel unit semantic_role instrument_id instrument_channel} { if {[dict exists $v $f]} { set genericCsvBatchVar($row,$j,$f) [dict get $v $f] } }
    }
    set genericCsvBatchVarCount($row) $j
    return $j
}
proc ::GX::genericCsvBatchEnsureVariables {row {force 0}} {
    return [::GX::genericCsvBatchEnsureVariables_before_importer_builder $row $force]
}

# Group-aware validation: every member must still exist.
proc ::GX::genericCsvBatchValidateSelectedRows {rows} {
    variable genericCsvBatch
    foreach i $rows {
        if {[info exists genericCsvBatch($i,source_paths)]} {
            foreach p $genericCsvBatch($i,source_paths) { if {![file isfile $p]} { error "Batch row $i: grouped acquisition source does not exist: $p" } }
        }
    }
    return [::GX::genericCsvBatchValidateSelectedRows_v089_before_group_validation $rows]
}

# Native acquisition page integration (the current GUI rebuilds the historical
# .api frame, so v0.9.0 attaches capability controls to the native widgets).
proc ::GX::acquisitionHandlerRefreshNativeGui {} {
    variable cfg
    set f .top.nb.acq
    if {![winfo exists $f]} return
    set plugin [acquisitionHandlerCurrentModuleIsPlugin]
    set batchCap [expr {$plugin && [acquisitionHandlerModuleSupportsBatch $cfg(acquisition_module)]}]
    if {[winfo exists $f.l0]} { catch {$f.l0 configure -text [expr {$plugin ? "Acquisition source" : "Acquisition CSV"}]} }
    if {[winfo exists $f.batch]} {
        if {$batchCap || $cfg(acquisition_module) eq "acq.generic_csv"} { grid $f.batch } else { grid remove $f.batch }
    }
    catch {acquisitionHandlerRefreshBatchLabel}
    if {![winfo exists $f.preflight]} {
        ttk::button $f.preflight -text "Validate selected importer..." -command ::GX::acquisitionHandlerPreflightDialog
        pack $f.preflight -in $f.heading -anchor w -pady 3
    }
    set show 0
    if {$plugin} { set hid [acquisitionHandlerLoadModule $cfg(acquisition_module)]; set show [acquisitionHandlerHasCapability $hid preflight] }
    if {$show} {pack $f.preflight -in $f.heading -anchor w -pady 3} else {pack forget $f.preflight}
}

proc ::GX::refreshNativeAcquisitionConfig_before_importer_builder {} {
    set r [::GX::refreshNativeAcquisitionConfig_v089_before_acq_native_gui]
    catch {acquisitionHandlerRefreshNativeGui}
    return $r
}

# Ensure batch capability UI is synchronized after the native page is rebuilt.
proc ::GX::augmentStandardGui_v089_before_session_files {} {
    ::GX::augmentStandardGui_v089_before_acq_native_gui
    catch {acquisitionHandlerRefreshNativeGui}
}

# v0.9.7.81: import into a private staging area, then commit one Dataset group.
# A failed handler never owns an existing RAW/payload/registry path.
proc ::GX::acquisitionHandlerImportSourcesToSession {moduleId session sourcePaths proposedId proposedContract variableMap} {
    variable moduleCfg
    variable datasetRegistry
    set hid [acquisitionHandlerLoadModule $moduleId]
    set session [file normalize $session]
    if {![file isdirectory $session]} { error "$moduleId: target session does not exist: $session" }
    if {$::GX::currentSession eq {} || [file normalize $::GX::currentSession] ne $session} {error {Import target must be the selected validated Session}}
    set importToken [interactiveDocumentSessionToken]
    set norm {}
    foreach src $sourcePaths {
        set src [file normalize $src]
        if {![file isfile $src]} { error "$moduleId: input file does not exist: $src" }
        lappend norm $src
    }
    if {![llength $norm]} { error "$moduleId: no input sources were supplied." }
    if {$proposedId eq ""} { set proposedId [acquisitionHandlerDefaultDatasetId $moduleId] }
    set proposedId [acquisitionHandlerValidateDatasetId $proposedId "$moduleId proposed Dataset ID"]
    if {$proposedContract eq ""} { set proposedContract [acquisitionHandlerDefaultContract $moduleId] }
    if {[datasetField $proposedId id ""] ne ""} { error "$moduleId: Dataset ID '$proposedId' already exists." }
    set storagePolicy [acquisitionHandlerSourceStoragePolicy $moduleId]

    # Inspection and handler preflight are read-only and precede all session writes.
    set inspect [acquisitionHandlerInspectSources $moduleId $norm]
    if {[dict exists $inspect recognized] && ![dict get $inspect recognized]} {
        error [_acquisitionHandlerUnrecognizedReason $moduleId $inspect]
    }
    set pf [acquisitionHandlerPreflight $moduleId $norm]
    if {![dict get $pf ok] || [llength [dict get $pf errors]]} {
        error "$moduleId: acquisition preflight failed: [join [dict get $pf errors] {; }]"
    }

    set rawRels {}; set finalRaws {}; set n 0
    foreach src $norm {
        incr n
        if {$storagePolicy eq "reference"} {
            lappend rawRels $src
        } else {
            set rel [file join raw [sanitize $moduleId] [sanitize $proposedId] [format "%03d_%s" $n [file tail $src]]]
            set dest [file join $session $rel]
            if {[file exists $dest]} { error "$moduleId: RAW destination already exists: $dest" }
            lappend rawRels $rel; lappend finalRaws $dest
        }
    }
    set txnRoot [file join $session .acquisition-txn]
    file mkdir $txnRoot
    set txn [file join $txnRoot [format "%s-%s-%s" [sanitize $proposedId] [pid] [clock clicks]]]
    file mkdir [file join $txn datasets]
    set stagedRaws {}; set rawHashes {}; set moved {}; set ids {}
    set priorRegistry [array get datasetRegistry]
    set registryPath [datasetRegistryPath $session]
    set registryExisted [file isfile $registryPath]
    set registrySnapshot [file join $txn registry.snapshot]
    if {$registryExisted} { file copy -- $registryPath $registrySnapshot }
    set metadataDir [file join $session metadata datasets]
    set priorMetadata [glob -nocomplain -directory $metadataDir *]
    set status [catch {
        foreach src $norm rel $rawRels {
            if {$storagePolicy eq "reference"} {
                set dst $src
            } else {
                set dst [file join $txn $rel]
                file mkdir [file dirname $dst]
                file copy -- $src $dst
            }
            lappend stagedRaws $dst
            lappend rawHashes [sha256File $dst]
        }
        set cfgDict [dict create]
        foreach key [moduleConfigKeys $moduleId] {
            if {[info exists moduleCfg($moduleId,$key)]} { dict set cfgDict $key $moduleCfg($moduleId,$key) }
        }
        set request [dict create api_version 1 module_id $moduleId handler_id $hid \
            source_path [lindex $norm 0] source_paths $norm raw_path [lindex $stagedRaws 0] \
            raw_paths $stagedRaws session_path $session output_dir [file join $txn datasets] \
            dataset_id $proposedId contract $proposedContract config $cfgDict variables $variableMap inspection $inspect]
        dict for {k v} [acquisitionHandlerRequestCallbacks $moduleId] { dict set request $k $v }
        set importProc [acquisitionHandlerField $hid import_proc ""]
        set result [uplevel #0 [list $importProc $request]]
        if {$importToken ne [interactiveDocumentSessionToken] || [file normalize $::GX::currentSession] ne $session} {error {Session changed during import; no outputs were committed}}
        if {$storagePolicy eq "reference"} {
            foreach source $norm expected $rawHashes {
                if {![file isfile $source] || ![string equal -nocase [sha256File $source] $expected]} {
                    error "$moduleId: external RAW source changed during import: $source"
                }
            }
        }
        if {[dict exists $result outcome] && [dict get $result outcome] eq {registered_session_script}} {
            if {$moduleId ne {acq.text_document}} {error {This importer has not declared a registered Session script outcome}}
            lassign [acquisitionHandlerSafeDatasetPath $session [file join $txn datasets] [dict get $result source_path]] scriptSource unused
            set scriptReceipt [scriptRegistryImportSource $session $scriptSource [dict get $result script_id] [dict get $result name] [dict get $result language] [dict get $result provenance]]
            set ids [list [dict get $scriptReceipt reference]]
        } else {
        if {[catch {dict size $result}] || ![dict exists $result datasets]} {
            error "$moduleId: import_proc must return a dict with datasets."
        }
        set seenIds {}; set finalPayloads {}
        foreach ds [dict get $result datasets] {
            if {[catch {dict size $ds}] || ![dict exists $ds dataset_id] || ![dict exists $ds path]} {
                error "$moduleId: returned dataset requires dataset_id and path."
            }
            set id [acquisitionHandlerValidateDatasetId [dict get $ds dataset_id] "$moduleId returned Dataset ID"]
            if {[lsearch -exact $seenIds $id] >= 0 || [datasetField $id id ""] ne ""} {
                error "$moduleId: duplicate or existing Dataset ID '$id'."
            }
            lassign [_datasetMetadataPath $session $id] unused metadataPath
            if {[file exists $metadataPath]} {
                error "$moduleId: metadata destination already exists: $metadataPath"
            }
            lappend seenIds $id
            lassign [acquisitionHandlerSafeDatasetPath $session [file join $txn datasets] [dict get $ds path]] staged unused
            set final [file normalize [file join $session datasets [dict get $ds path]]]
            if {[file exists $final] || [lsearch -exact $finalPayloads $final] >= 0} {
                error "$moduleId: dataset payload destination already exists: $final"
            }
            lappend finalPayloads $final
        }
        if {![llength $finalPayloads]} { error "$moduleId: import_proc returned no datasets." }
        if {$storagePolicy eq "copy"} {
            foreach staged $stagedRaws final $finalRaws {
                file mkdir [file dirname $final]
                datasetAuthorityEnlist $final
                file rename -- $staged $final
                lappend moved $final
            }
        }
        foreach ds [dict get $result datasets] final $finalPayloads {
            set staged [file join $txn datasets [dict get $ds path]]
            file mkdir [file dirname $final]
            datasetAuthorityEnlist $final
            file rename -- $staged $final
            lappend moved $final
        }
        set ids [acquisitionHandlerRegisterResult $moduleId $session [lindex $rawRels 0] \
            [lindex $rawHashes 0] [file join $session datasets] $result]
        foreach id $ids {
            datasetRegister $id [list source_count [llength $norm] source_raw_list [join $rawRels {;}] \
                source_sha256_list [join $rawHashes {;}] acquisition_capabilities [join [acquisitionHandlerCapabilities $hid] {;}] \
                source_storage_policy $storagePolicy source_original_path [lindex $norm 0] \
                source_size_bytes [file size [lindex $norm 0]] source_mtime [file mtime [lindex $norm 0]]]
        }
        saveDatasetRegistry $session
        }
    } failure options]
    if {$status} {
        foreach path [lreverse $moved] { catch {file delete -- $path} }
        foreach path [glob -nocomplain -directory $metadataDir *] {
            if {[lsearch -exact $priorMetadata $path] < 0} { catch {file delete -- $path} }
        }
        if {$::GX::currentSession ne {} && [file normalize $::GX::currentSession] eq $session} {array unset datasetRegistry *;array set datasetRegistry $priorRegistry}
        if {$registryExisted} {
            catch {file copy -force -- $registrySnapshot $registryPath}
        } else {
            catch {file delete -- $registryPath}
        }
    }
    catch {file delete -force -- $txn}
    if {$status} { return -options $options $failure }
    acquisitionHandlerApplyInstrumentSuggestions $inspect
    if {[catch {acquisitionHandlerReceiptSave $session $moduleId $norm $ids} receiptError]} {guiLog "Import succeeded; operation receipt unavailable: $receiptError"}
    if {[info exists scriptReceipt]} {return $scriptReceipt}
    return $ids
}

proc ::GX::acquisitionHandlerStartCooperative {moduleId} {
    tailcall ::GX::acquisitionHandlerStartCooperative_atomic_v09781 $moduleId
}
proc ::GX::acquisitionHandlerAsyncFinalize {ok payload} {
    tailcall ::GX::acquisitionHandlerAsyncFinalize_atomic_v09781 $ok $payload
}

# Persist successful importer outcomes in the acquisition owner. Legacy Sessions
# remain honestly unqualified; scientific Dataset rows are never duplicated.
proc ::GX::acquisitionHandlerReceiptSave {session module sources outputs} {
    if {$session ne $::GX::currentSession} {error {Cannot record an import against another Session}}
    set id import-[clock microseconds]-[pid]
    set names {};foreach source $sources {lappend names [file tail $source]}
    set warnings {};foreach output $outputs {if {[datasetField $output id {}] ne {}} {set metadata [datasetMetadataRead $session $output];dict for {key value} $metadata {if {[string match *warning* $key] && $value ne {}} {dict set warnings $key $value}}}}
    set receipt [dict create schema gxtxt.acquisition_receipt.v1 id $id module_id $module handler_id [acquisitionHandlerLoadModule $module] state COMPLETED timestamp [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}] sources $names outputs $outputs warnings $warnings]
    if {[string length [encoding convertto utf-8 $receipt]]>65536} {error {Import receipt exceeds the bounded metadata limit}}
    set directory [file join $session metadata acquisitions]
    foreach parent [list [file join $session metadata] $directory] {if {![catch {file type $parent} type] && $type eq {link}} {error {Import receipt destination contains a symlink}}}
    file mkdir $directory
    resourceLifecycleWriteBytes [file join $directory $id.tcldict] [encoding convertto utf-8 $receipt]
    return $receipt
}
