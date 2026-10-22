# GX-TXT Dataset Variable Schema API v2
# SPDX-License-Identifier: GPL-3.0-or-later
# Dataset-scoped stable identities; source provenance is never edited here.
namespace eval ::GX {
    variable datasetVariableSchemaApiVersion 2
    variable moduleBindingIdentity
    variable datasetSchemaRegenerator
    array set datasetSchemaRegenerator {}
}

proc ::GX::datasetSchemaSplitNames {raw} {
    set names [splitList $raw]
    if {[llength $names] == 1} {
        set one [lindex $names 0]
        if {[llength $one] > 1} { set names $one }
    }
    return $names
}

proc ::GX::datasetSchemaCsvSplit {line separator {channel {}}} {
    # The common unquoted scientific row can be tokenized by Tcl's native
    # splitter; keep the full state machine for quoted CSV fields.
    if {[string first {"} $line] < 0} { return [split $line $separator] }
    set out {}; set buf ""; set quoted 0; set n [string length $line]
    for {set i 0} {$i < $n} {incr i} {
        set c [string index $line $i]
        if {$quoted} {
            if {$c eq "\""} {
                if {$i+1 < $n && [string index $line [expr {$i+1}]] eq "\""} { append buf "\""; incr i } else { set quoted 0 }
            } else { append buf $c }
        } elseif {$c eq $separator} {
            lappend out $buf; set buf ""
        } elseif {$c eq "\"" && $buf eq ""} {
            set quoted 1
        } else { append buf $c }
        if {$i==$n-1&&$quoted&&$channel ne {}} {
            if {[gets $channel continuation]<0} {error {Unterminated quoted CSV field}}
            # Continue the same parser state, without rescanning the growing
            # prefix. Embedded physical newlines belong to the text field.
            set line "\n$continuation";set n [string length $line];set i -1
        }
    }
    if {$quoted} { error "Unterminated quoted CSV field" }
    lappend out $buf
    return $out
}

proc ::GX::datasetSchemaDetectDelimiter {path} {
    set fd [open $path r]; fconfigure $fd -encoding utf-8 -translation auto
    set line ""; gets $fd line; close $fd
    set best ,; set max 0
    foreach sep [list , {;} "\t"] {
        if {[catch {set count [llength [datasetSchemaCsvSplit $line $sep]]}]} continue
        if {$count > $max} { set best $sep; set max $count }
    }
    return $best
}

proc ::GX::datasetSchemaRawHeaders {path headerRows separator} {
    set fd [open $path r]; fconfigure $fd -encoding utf-8 -translation auto
    set line ""
    for {set i 0} {$i < $headerRows} {incr i} { if {[gets $fd line] < 0} { close $fd; return {} } }
    close $fd
    return [datasetSchemaCsvSplit $line $separator]
}

# A compatible importer registers a RAW -> canonical reconstruction callback.
# Callback signature: dataset_id raw_path temporary_output delimiter header_rows active_map.
proc ::GX::datasetSchemaRegisterRegenerator {sourceModule commandPrefix} {
    variable datasetSchemaRegenerator
    if {$sourceModule eq "" || ![llength $commandPrefix]} { error "Regenerator requires source module and command prefix" }
    set datasetSchemaRegenerator($sourceModule) $commandPrefix
}

proc ::GX::datasetSchemaGenericCsvRebuild {datasetId input output delimiter headerRows mappings} {
    variable scriptDir
    set helper [file join $scriptDir plugins modules acq.generic_csv runtime canonicalize_csv.py]
    set cmd [list [runtimeToolRequired python] $helper --input $input --output $output --delimiter $delimiter --header-rows $headerRows]
    foreach item $mappings { lassign $item col name; lappend cmd --map "$col=$name" }
    if {[catch {exec {*}$cmd 2>@1} result]} { error "Canonical regeneration failed for $datasetId: $result" }
}

::GX::datasetSchemaRegisterRegenerator acq.generic_csv ::GX::datasetSchemaGenericCsvRebuild

proc ::GX::datasetSchemaEnsure {session id} {
    variable datasetRegistry
    if {[datasetField $id id ""] eq ""} { error "Unknown dataset: $id" }
    set rawNames [datasetField $id variables ""]
    if {$rawNames eq ""} { set rawNames [datasetField $id columns ""] }
    set names [datasetSchemaSplitNames $rawNames]
    set n [datasetField $id var_count ""]
    if {![string is integer -strict $n] || $n < 0} { set n [llength $names] }
    if {$n == 0 && [llength $names]} { set n [llength $names] }
    set datasetRegistry($id,var_count) $n
    set raw [datasetField $id source_raw ""]
    set headers {}
    if {$session ne "" && $raw ne ""} {
        set rawpath [expr {[file pathtype $raw] eq "absolute" ? $raw : [file join $session $raw]}]
        if {[file isfile $rawpath]} {
            set hr [datasetField $id source_header_rows 1]
            if {![string is integer -strict $hr] || $hr < 1} { set hr 1 }
            set sourceToken [datasetField $id source_delimiter ""]
            if {$sourceToken eq ""} {
                set sep [datasetSchemaDetectDelimiter $rawpath]
                set sourceToken [expr {$sep eq "\t" ? "tab" : ($sep eq ";" ? "semicolon" : "comma")}]
                set datasetRegistry($id,source_delimiter) $sourceToken
            }
            set sep [expr {$sourceToken eq "tab" ? "\t" : ($sourceToken eq "semicolon" ? ";" : ",")}]
            catch {set headers [datasetSchemaRawHeaders $rawpath $hr $sep]}
        }
    }
    set canonical [expr {$session eq "" ? "" : [datasetResolvePath $session $id]}]
    set storageProvider [string tolower [datasetField $id storage_provider ""]]
    set datasetFormat [string tolower [datasetField $id format ""]]
    set isTextTable [expr {$storageProvider in {"" csv} && $datasetFormat ni {hdf5 h5}}]
    if {$isTextTable && $canonical ne "" && [file isfile $canonical] && [datasetField $id canonical_delimiter ""] eq ""} {
        set sep [datasetSchemaDetectDelimiter $canonical]
        set datasetRegistry($id,canonical_delimiter) [expr {$sep eq "\t" ? "tab" : ($sep eq ";" ? "semicolon" : "comma")}]
    }
    set unitSummary [datasetField $id units ""]
    set roleSummary [datasetField $id semantic_roles ""]
    set units [expr {$unitSummary eq "" ? {} : [split [string map {, ;} $unitSummary] ";"]}]
    set roles [expr {$roleSummary eq "" ? {} : [split [string map {, ;} $roleSummary] ";"]}]
    set activeIndex 0
    for {set j 1} {$j <= $n} {incr j} {
        set prefix "var${j}_"
        set exists [info exists datasetRegistry($id,${prefix}canonical)]
        if {!$exists && $n == [llength $names]} {
            set datasetRegistry($id,${prefix}canonical) [lindex $names [expr {$j-1}]]
            set exists 1
        }
        if {![info exists datasetRegistry($id,${prefix}enabled)]} { set datasetRegistry($id,${prefix}enabled) [expr {$exists ? 1 : 0}] }
        if {![info exists datasetRegistry($id,${prefix}source_column)]} { set datasetRegistry($id,${prefix}source_column) $j }
        if {![info exists datasetRegistry($id,${prefix}original_header)]} {
            set datasetRegistry($id,${prefix}original_header) [expr {$j <= [llength $headers] ? [lindex $headers [expr {$j-1}]] : [datasetField $id ${prefix}canonical ""]}]
        }
        if {![info exists datasetRegistry($id,${prefix}variable_id)]} { set datasetRegistry($id,${prefix}variable_id) [format "v%04d" $j] }
        foreach {field def} {canonical "" unit "" canonical_unit "" to_canonical "" from_canonical "" display_label "" semantic_role "" semantic_source "" semantic_reason "" instrument_id "" instrument_channel "" source_channel "" value_kind number value_format "" decimal_separator . time_origin "" time_reference elapsed} {
            if {![info exists datasetRegistry($id,${prefix}$field)]} { set datasetRegistry($id,${prefix}$field) $def }
        }
        if {$datasetRegistry($id,${prefix}enabled)} {
            incr activeIndex
            if {$datasetRegistry($id,${prefix}unit) eq "" && $activeIndex <= [llength $units]} { set datasetRegistry($id,${prefix}unit) [lindex $units [expr {$activeIndex-1}]] }
            if {$datasetRegistry($id,${prefix}semantic_role) eq "" && $activeIndex <= [llength $roles]} { set datasetRegistry($id,${prefix}semantic_role) [lindex $roles [expr {$activeIndex-1}]] }
            set datasetRegistry($id,${prefix}canonical_position) $activeIndex
        } else {
            set datasetRegistry($id,${prefix}canonical_position) ""
        }
    }
    if {$isTextTable && $canonical ne "" && [file isfile $canonical]} { datasetSchemaInferValues $id $canonical }
    if {[llength [info commands ::GX::semanticRegistryInfer]]} { datasetSchemaInferSemantics $id }
    # v2 projection must not downgrade an already declared additive v3 schema.
    if {[datasetField $id variable_schema_api_version {}] ne "3"} {
        set datasetRegistry($id,variable_schema_api_version) 2
    }
}

proc ::GX::datasetSchemaInferValues {id path} {
    variable datasetRegistry
    # Publication v2 already supplies authoritative typed Variable declarations.
    # Re-inference can overwrite them and cannot parse embedded record newlines
    # with this legacy bounded line sampler. Canonical access owns those records.
    if {[datasetField $id publication_api_version {}] eq "2"} {return}
    set pending 0
    for {set j 1} {$j<=[datasetField $id var_count 0]} {incr j} {
        if {[datasetField $id var${j}_enabled 0]&&[datasetField $id var${j}_value_inferred {}] eq {}} {set pending 1;break}
    }
    if {!$pending} {return}
    set sep [datasetField $id canonical_delimiter comma]
    set char [expr {$sep eq "tab" ? "\t" : ($sep eq "semicolon" ? ";" : ",")}]
    set names [datasetSchemaSplitNames [datasetField $id variables [datasetField $id columns ""]]]
    set fd [open $path r]; fconfigure $fd -encoding utf-8 -translation auto
    gets $fd header
    set rows {}
    try {while {[llength $rows] < 25 && [gets $fd line] >= 0} {if {[string trim $line] ne ""} {lappend rows [datasetSchemaCsvSplit $line $char $fd]}}} finally {close $fd}
    set n [datasetField $id var_count 0]
    for {set j 1} {$j <= $n} {incr j} {
        if {![datasetField $id var${j}_enabled 0]} continue
        set name [datasetField $id var${j}_canonical ""]
        set col [lsearch -exact $names $name]
        if {$col < 0} continue
        set values {}; foreach r $rows { if {$col < [llength $r]} { set v [string trim [lindex $r $col] " \t\r\n\""]; if {$v ne ""} { lappend values $v } } }
        if {![llength $values]} continue
        if {[datasetField $id var${j}_value_inferred ""] ne ""} continue
        if {[datasetField $id var${j}_value_format ""] eq "" && [datasetField $id var${j}_unit ""] in {h min s}} {
            set hms 1; foreach v $values { if {![regexp {^[0-9]+:[0-5][0-9]:[0-5][0-9]([.,][0-9]+)?$} $v]} { set hms 0; break } }
            if {$hms} {
                set datasetRegistry($id,var${j}_value_kind) elapsed_time
                set datasetRegistry($id,var${j}_value_format) hms
                set datasetRegistry($id,var${j}_time_reference) elapsed
                set datasetRegistry($id,var${j}_value_inferred) 1
                continue
            }
        }
        # A textual categorical column is a string variable in the persistent
        # schema. Keep NaN/Inf and common missing markers compatible with
        # numeric scientific columns; the batch canonicalizer checks all rows.
        set textual 0
        foreach v $values {
            if {[string tolower $v] in {na n/a null}} continue
            if {[string is double -strict $v] || [regexp {^[+-]?[0-9]+,[0-9]+$} $v]} continue
            set textual 1
            break
        }
        if {$textual} {
            set datasetRegistry($id,var${j}_value_kind) text
            set datasetRegistry($id,var${j}_dtype) string
            set datasetRegistry($id,var${j}_value_inferred) 1
            continue
        }
        if {[datasetField $id var${j}_decimal_separator .] eq "."} {
            set comma 0; set valid 1
            foreach v $values {
                if {[string first , $v] < 0} { if {![string is double -strict $v]} {set valid 0;break}; continue }
                if {![regexp {^[+-]?[0-9]+,[0-9]+$} $v]} {set valid 0;break}
                # With semicolon or tab fields, a comma inside a numeric token
                # is a decimal mark even when it has three fractional digits.
                # A comma-delimited table retains the conservative heuristic
                # because quoted grouping and decimals are ambiguous there.
                if {$sep ne "," || [regexp {,[0-9]{1,2}$|,[0-9]{4,}$} $v]} {set comma 1}
            }
            if {$valid && $comma} { set datasetRegistry($id,var${j}_decimal_separator) , }
        }
        set datasetRegistry($id,var${j}_value_inferred) 1
    }
}

proc ::GX::datasetSchemaInferSemantics {id} {
    variable datasetRegistry
    set n [datasetField $id var_count 0]
    for {set j 1} {$j <= $n} {incr j} {
        if {[datasetField $id var${j}_schema_inherited 0]} { continue }
        set role [string trim [datasetField $id var${j}_semantic_role ""]]
        set source [datasetField $id var${j}_semantic_source ""]
        if {$source eq "" && $role ne "" && $role ne "Auto"} {
            set datasetRegistry($id,var${j}_semantic_source) importer
            set datasetRegistry($id,var${j}_semantic_reason) "Role supplied by importer or legacy dataset"
            continue
        }
        if {$source ni {"" inferred default}} continue
        set v [dict create canonical [datasetField $id var${j}_canonical ""] original_header [datasetField $id var${j}_original_header ""] unit [datasetField $id var${j}_unit ""] value_kind [datasetField $id var${j}_value_kind number] time_reference [datasetField $id var${j}_time_reference elapsed]]
        set result [semanticRegistryInfer $v]
        foreach field {semantic_role semantic_source semantic_reason} {
            set datasetRegistry($id,var${j}_$field) [dict get $result $field]
        }
    }
}

proc ::GX::datasetVariableSchema {id} {
    variable currentSession
    if {[datasetField $id variable_schema_api_version ""] ni {2 3}} { datasetSchemaEnsure $currentSession $id }
    set out {}; set n [datasetField $id var_count 0]
    for {set j 1} {$j <= $n} {incr j} {
        set v [dict create]
        foreach f {variable_id enabled source_column source_channel original_header canonical canonical_position unit canonical_unit to_canonical from_canonical display_label semantic_role semantic_source semantic_reason instrument_id instrument_channel value_kind value_format decimal_separator time_origin time_reference} { dict set v $f [datasetField $id var${j}_$f ""] }
        # Older writer registries may omit the source-format defaults. Their
        # public descriptors must remain valid when reopened in the editor.
        if {[dict get $v decimal_separator] eq ""} {dict set v decimal_separator .}
        if {[dict get $v time_reference] eq ""} {dict set v time_reference elapsed}
        lappend out $v
    }
    return $out
}

proc ::GX::datasetVariableById {id variableId} {
    foreach v [datasetVariableSchema $id] { if {[dict get $v variable_id] eq $variableId} { return $v } }
    error "Dataset $id has no variable_id $variableId"
}

proc ::GX::datasetVariableResolve {id token} {
    foreach v [datasetVariableSchema $id] { if {[dict get $v variable_id] eq $token} { return $v } }
    foreach v [datasetVariableSchema $id] { if {[dict get $v canonical] eq $token} { return $v } }
    error "Dataset $id has no variable $token"
}

proc ::GX::loadDatasetRegistry {session} {
    set ids [loadDatasetRegistry_v1_before_schema $session]
    foreach id $ids {
        datasetSchemaEnsure $session $id
        # Capture the authority baseline only after all available read-time
        # projections. A later inspection must not look like a pending edit.
        if {[info commands ::GX::datasetSchemaEnsureV3] ne {}} {datasetSchemaEnsureV3 $session $id}
    }
    if {[info commands ::GX::datasetAuthorityLoaded] ne {}} {datasetAuthorityLoaded $session}
    return $ids
}
proc ::GX::saveDatasetRegistry_before_canonical_v2 {session} {
    foreach id [datasetRegistryIds] { datasetSchemaEnsure $session $id }
    return [saveDatasetRegistry_v1_before_schema $session]
}

# Public transactional mutation. `changes` is a dictionary keyed by variable_id;
# each value is a dictionary of mutable schema fields. All source_* fields stay read-only.
proc ::GX::datasetVariableSchemaUpdate {id changes} {
    variable datasetRegistry
    variable currentSession
    if {$::GX::DatasetPrivate::activeContext ne {}} {_datasetNamespaceRequireModuleWrite $currentSession [dict get $::GX::DatasetPrivate::activeContext module_id] $id}
    variable scriptDir
    if {$currentSession eq "" || ![file isdirectory $currentSession]} { error "Open a session before editing dataset schema" }
    loadDatasetRegistry $currentSession
    if {[datasetField $id id ""] eq ""} { error "Unknown dataset: $id" }
    set coordinatePrior {}
    if {[_datasetCoordinateStored $currentSession $id] ne {}} {
        # A stale preexisting context stays stale. Only a verified context can
        # follow the schema owner's controlled cosmetic/column regeneration.
        catch {datasetCoordinateRead $currentSession $id;set coordinatePrior [_datasetCoordinateStored $currentSession $id]}
    }
    set before [array get datasetRegistry "$id,*"]
    set bindingBefore [array get ::GX::moduleBinding]
    set bindingIdBefore [array get ::GX::moduleBindingIdentity]
    set configBefore [array get ::GX::moduleCfg]
    set repeatBefore [array get ::GX::repeatableValue]
    set referenceBefore [array get ::GX::variableReferenceIdentity]
    set registryPath [datasetRegistryPath $currentSession]
    set manifestPath [file join $currentSession metadata manifest.ini]
    set suffix ".schema.[pid].backup"
    set registryBackup "$registryPath$suffix"
    set manifestBackup "$manifestPath$suffix"
    lassign [_datasetMetadataPath $currentSession $id] metadataRelative metadataPath
    foreach resource [list $registryPath $manifestPath $metadataPath [datasetResolvePath $currentSession $id]] {
        if {$resource ne {} && [_datasetDeletePathWithin $resource $currentSession]} {datasetAuthorityEnlist $resource}
    }
    set metadataBackup "$metadataPath$suffix"
    set metadataExisted [file isfile $metadataPath]
    if {$metadataExisted} {file copy -force -- $metadataPath $metadataBackup}
    set canonicalBackup ""
    set createdSchemaSnapshot ""
    if {[file isfile $registryPath]} { file copy -force -- $registryPath $registryBackup }
    if {[file isfile $manifestPath]} { file copy -force -- $manifestPath $manifestBackup }
    set old {}; foreach v [datasetVariableSchema $id] { dict set old [dict get $v variable_id] $v }
    set structural 0
    try {
        dict for {vid fields} $changes {
            if {![dict exists $old $vid]} { error "Unknown variable_id $vid in dataset $id" }
            set prev [dict get $old $vid]
            set j [string range $vid 1 end]
            if {![string is integer -strict $j] || $j < 1 || [datasetField $id var${j}_variable_id ""] ne $vid} {
                set j 0; set count [datasetField $id var_count 0]
                for {set k 1} {$k <= $count} {incr k} { if {[datasetField $id var${k}_variable_id ""] eq $vid} { set j $k; break } }
                if {!$j} { error "Unknown variable_id $vid" }
            }
            dict for {field value} $fields {
                if {$field ni {enabled canonical unit canonical_unit to_canonical from_canonical display_label semantic_role semantic_source instrument_id instrument_channel value_kind value_format decimal_separator time_origin time_reference}} { error "Field $field is not mutable" }
                if {[regexp {[\r\n]} $value]} { error "Schema fields must be single-line" }
                if {$field eq "enabled"} { if {$value ni {0 1}} { error "enabled must be 0 or 1" } }
                if {$field eq "canonical" && $value ne "" && ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $value]} { error "Invalid canonical name $value" }
                if {$field eq "value_kind" && $value ni {number text elapsed_time}} { error "Unsupported value_kind $value" }
                if {$field eq "value_format" && $value ni {"" hms}} { error "Unsupported value_format $value" }
                if {$field eq "decimal_separator" && $value ni {. ,}} { error "Unsupported decimal_separator $value" }
                if {$field eq "time_reference" && $value ni {elapsed absolute}} { error "Unsupported time_reference $value" }
                if {$field in {to_canonical from_canonical} && $value ne ""} { unitFormulaValidate $value }
                if {$field eq "semantic_source" && $value ni {user importer plugin generator inferred default}} { error "Unsupported semantic_source $value" }
                if {$field eq "semantic_role" && $value ni {"" Auto} && ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $value]} { error "Invalid semantic role ID $value" }
                if {$field in {enabled canonical} && $value ne [dict get $prev $field]} { set structural 1 }
                set datasetRegistry($id,var${j}_$field) $value
                if {$field in {value_kind value_format decimal_separator time_origin time_reference}} { set datasetRegistry($id,var${j}_value_inferred) 1 }
            }
            if {[dict exists $fields semantic_role]} {
                set role [string trim [dict get $fields semantic_role]]
                if {$role in {"" Auto}} {
                    set datasetRegistry($id,var${j}_semantic_role) ""
                    set datasetRegistry($id,var${j}_semantic_source) inferred
                    set datasetRegistry($id,var${j}_semantic_reason) ""
                } elseif {$role ne [dict get $prev semantic_role] && ![dict exists $fields semantic_source]} {
                    set datasetRegistry($id,var${j}_semantic_source) user
                    set datasetRegistry($id,var${j}_semantic_reason) "Explicit user choice"
                }
            }
            if {[dict exists $fields semantic_source] && [dict get $fields semantic_source] in {inferred default}} {
                set datasetRegistry($id,var${j}_semantic_role) ""
            }
        }
        set names {}; set units {}; set roles {}; set map {}; set sourceMap {}; set n [datasetField $id var_count 0]
        for {set j 1} {$j <= $n} {incr j} {
            if {![datasetField $id var${j}_enabled 0]} continue
            set name [string trim [datasetField $id var${j}_canonical ""]]
            if {$name eq "" || ![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $name]} { error "Enabled variable $j requires a valid canonical name" }
            if {[lsearch -exact $names $name] >= 0} { error "Duplicate canonical variable $name" }
            set canonicalUnit [datasetField $id var${j}_canonical_unit ""]
            set toFormula [datasetField $id var${j}_to_canonical ""]
            set fromFormula [datasetField $id var${j}_from_canonical ""]
            if {$canonicalUnit ne ""} {
                if {$toFormula eq "" || $fromFormula eq ""} { error "Canonical unit requires both conversion formulas for $name" }
                unitFormulaValidate $toFormula; unitFormulaValidate $fromFormula
            } elseif {$toFormula ne "" || $fromFormula ne ""} {
                error "Conversion formulas require canonical_unit for $name"
            }
            set valueKind [datasetField $id var${j}_value_kind number]
            set valueFormat [datasetField $id var${j}_value_format ""]
            set valueUnit [datasetField $id var${j}_unit ""]
            set timeReference [datasetField $id var${j}_time_reference elapsed]
            if {$valueKind eq "elapsed_time" && ($valueFormat ne "hms" || $valueUnit ni {s min h})} { error "Elapsed-time variable $name requires HMS format and unit s, min or h" }
            if {$valueKind ne "elapsed_time" && $valueFormat ne ""} { error "Value format $valueFormat requires elapsed_time for $name" }
            if {$timeReference eq "absolute" && $valueKind ne "elapsed_time"} { error "Absolute time reference requires elapsed_time for $name" }
            if {$timeReference eq "absolute" && [string trim [datasetField $id var${j}_time_origin ""]] eq ""} { error "Absolute time variable $name requires time_origin" }
            lappend names $name
            lappend units [datasetField $id var${j}_unit ""]
            lappend roles [datasetField $id var${j}_semantic_role ""]
            lappend sourceMap [list [datasetField $id var${j}_source_column $j] $name]
            set vid [datasetField $id var${j}_variable_id ""]
            if {[dict exists $old $vid] && [dict get $old $vid enabled]} { lappend map [list [dict get [dict get $old $vid] canonical_position] $name] }
        }
        if {$structural} {
            if {[datasetField $id format ""] ne "csv"} { error "Canonical restructuring requires a CSV dataset provider" }
            set canonical [datasetResolvePath $currentSession $id]
            if {![file isfile $canonical]} { error "Canonical dataset is missing: $canonical" }
            set expectedCanonical [datasetField $id canonical_sha256 ""]
            if {$expectedCanonical ne "" && [sha256File $canonical] ne $expectedCanonical} { error "Canonical SHA-256 mismatch; refusing schema rewrite" }
            set raw [datasetField $id source_raw ""]
            set useRaw 0
            if {$raw ne ""} {
                set rawpath [expr {[file pathtype $raw] eq "absolute" ? $raw : [file join $currentSession $raw]}]
                set provider [datasetField $id source_module ""]
                if {[file isfile $rawpath] && [info exists ::GX::datasetSchemaRegenerator($provider)]} { set useRaw 1 }
            }
            if {$useRaw} {
                set expected [datasetField $id source_sha256 ""]
                if {$expected ne "" && [sha256File $rawpath] ne $expected} { error "RAW SHA-256 mismatch; refusing canonical regeneration" }
                set input $rawpath; set mappings $sourceMap
                set delimiter [datasetField $id source_delimiter auto]
                set hr [datasetField $id source_header_rows 1]
            } else {
                set snapshotRel [datasetField $id schema_source_snapshot ""]
                if {$snapshotRel eq ""} {
                    # Preserve every currently available canonical column before
                    # dropping any. This is a derived schema source, never RAW.
                    foreach v [datasetVariableSchema $id] {
                        if {[dict get $v enabled] && ![dict get [dict get $old [dict get $v variable_id]] enabled]} { error "Re-enabling an originally omitted variable requires a RAW regeneration provider" }
                    }
                    if {![regexp {^[A-Za-z0-9_.-]+$} $id]} { error "Dataset ID cannot name a schema snapshot: $id" }
                    set snapshotRel [file join metadata schema_sources "${id}.csv"]
                    set snapshotPath [file join $currentSession $snapshotRel]
                    if {[file exists $snapshotPath]} { error "Unregistered schema snapshot already exists: $snapshotPath" }
                    file mkdir [file dirname $snapshotPath]
                    file copy -- $canonical $snapshotPath
                    set createdSchemaSnapshot $snapshotPath
                    set datasetRegistry($id,schema_source_snapshot) $snapshotRel
                    set datasetRegistry($id,schema_source_snapshot_sha256) [sha256File $snapshotPath]
                    dict for {vid v} $old {
                        if {![dict get $v enabled]} continue
                        set slot 0
                        for {set k 1} {$k <= [datasetField $id var_count 0]} {incr k} {
                            if {[datasetField $id var${k}_variable_id ""] eq $vid} { set slot $k; break }
                        }
                        if {$slot} { set datasetRegistry($id,var${slot}_schema_snapshot_column) [dict get $v canonical_position] }
                    }
                } else {
                    set snapshotPath [expr {[file pathtype $snapshotRel] eq "absolute" ? $snapshotRel : [file join $currentSession $snapshotRel]}]
                }
                if {![file isfile $snapshotPath]} { error "Schema source snapshot is missing: $snapshotPath" }
                set expectedSnapshot [datasetField $id schema_source_snapshot_sha256 ""]
                if {$expectedSnapshot ne "" && [sha256File $snapshotPath] ne $expectedSnapshot} { error "Schema source snapshot SHA-256 mismatch" }
                set mappings {}
                for {set j 1} {$j <= [datasetField $id var_count 0]} {incr j} {
                    if {![datasetField $id var${j}_enabled 0]} continue
                    set pos [datasetField $id var${j}_schema_snapshot_column ""]
                    if {$pos eq ""} { error "Variable [datasetField $id var${j}_variable_id] was not present in schema snapshot; RAW provider required" }
                    lappend mappings [list $pos [datasetField $id var${j}_canonical ""]]
                }
                set input $snapshotPath
                set delimiter [datasetField $id canonical_delimiter auto]; set hr 1
            }
            if {![llength $mappings]} { error "At least one variable must remain enabled" }
            set tmp [file join [file dirname $canonical] ".[file tail $canonical].schema.[pid].tmp"]
            set callback [expr {$useRaw ? $::GX::datasetSchemaRegenerator($provider) : "::GX::datasetSchemaGenericCsvRebuild"}]
            if {[catch {uplevel #0 [list {*}$callback $id $input $tmp $delimiter $hr $mappings]} result]} {
                catch {file delete -force -- $tmp}; error "Canonical regeneration failed: $result"
            }
            set newHash [sha256File $tmp]
            set canonicalBackup "$canonical$suffix"
            file copy -force -- $canonical $canonicalBackup
            file rename -force -- $tmp $canonical
            set datasetRegistry($id,canonical_sha256) $newHash
            set datasetRegistry($id,columns) [join $names ,]
            set datasetRegistry($id,variables) [join $names ,]
        }
        set datasetRegistry($id,units) [join $units ";"]
        set datasetRegistry($id,semantic_roles) [join $roles ";"]
        datasetSchemaEnsure $currentSession $id
        saveDatasetRegistry $currentSession
        _datasetCoordinateSchemaRebind $currentSession $id $coordinatePrior
        datasetSchemaRefreshBindings $id $old
        datasetSchemaRefreshVariableConfigs $id $old
        writeManifest $manifestPath
        set result [datasetVariableSchema $id]
        foreach backup [list $registryBackup $manifestBackup $canonicalBackup $metadataBackup] { if {$backup ne "" && [file exists $backup]} { file delete -force -- $backup } }
        return $result
    } on error {e options} {
        if {$metadataExisted && [file exists $metadataBackup]} {catch {file rename -force -- $metadataBackup $metadataPath}} elseif {!$metadataExisted} {catch {file delete -force -- $metadataPath}}
        if {[info exists tmp] && [file exists $tmp]} { catch {file delete -force -- $tmp} }
        if {$canonicalBackup ne "" && [file exists $canonicalBackup]} { catch {file rename -force -- $canonicalBackup $canonical} }
        if {$createdSchemaSnapshot ne "" && [file exists $createdSchemaSnapshot]} { catch {file delete -force -- $createdSchemaSnapshot} }
        if {[file exists $registryBackup]} { catch {file rename -force -- $registryBackup $registryPath} }
        if {[file exists $manifestBackup]} { catch {file rename -force -- $manifestBackup $manifestPath} }
        foreach key [array names datasetRegistry "$id,*"] { unset datasetRegistry($key) }
        array set datasetRegistry $before
        foreach {name state} [list moduleBinding $bindingBefore moduleBindingIdentity $bindingIdBefore moduleCfg $configBefore repeatableValue $repeatBefore variableReferenceIdentity $referenceBefore] {
            upvar 0 ::GX::$name a
            array unset a *
            array set a $state
        }
        return -options $options $e
    }
}

proc ::GX::datasetSchemaRefreshBindings {datasetId old} {
    variable moduleBinding
    variable moduleBindingIdentity
    variable moduleOrder
    foreach module $moduleOrder {
        foreach role [moduleBindingRoles $module] {
            if {![info exists moduleBinding($module,$role)]} continue
            set value $moduleBinding($module,$role)
            set dot [string first . $value]
            set source [expr {$dot > 0 ? [string range $value 0 [expr {$dot-1}]] : "primary"}]
            set oldName [expr {$dot > 0 ? [string range $value [expr {$dot+1}] end] : $value}]
            if {[analysisSourceDatasetFor $module $source] ne $datasetId} continue
            if {[info exists moduleBindingIdentity($module,$role)]} {
                set parts [split $moduleBindingIdentity($module,$role) |]
                if {[llength $parts] == 3} {
                    lassign $parts storedSource storedDataset vid
                    if {$storedSource ne $source || $storedDataset ne $datasetId} continue
                    if {[catch {set now [datasetVariableById $datasetId $vid]}]} continue
                    set moduleBinding($module,$role) [expr {$dot > 0 ? "$source.[dict get $now canonical]" : [dict get $now canonical]}]
                    continue
                }
                if {[llength $parts] == 2} {
                    lassign $parts storedSource storedVariable
                    if {$storedSource ne $source ||
                        [catch {set migrated [moduleBindingIdentityLegacyCandidate $module $role $source $storedVariable $value]}]} continue
                    set moduleBindingIdentity($module,$role) $migrated
                    set now [datasetVariableById $datasetId $storedVariable]
                    set moduleBinding($module,$role) [expr {$dot > 0 ? "$source.[dict get $now canonical]" : [dict get $now canonical]}]
                    continue
                }
            }
            dict for {vid v} $old {
                if {[dict get $v canonical] ne $oldName} continue
                set now [datasetVariableById $datasetId $vid]
                set moduleBinding($module,$role) [expr {$dot > 0 ? "$source.[dict get $now canonical]" : [dict get $now canonical]}]
                set moduleBindingIdentity($module,$role) "$source|$datasetId|$vid"
                break
            }
        }
    }
}

proc ::GX::analysisSourceDatasetVariables {datasetId} {
    set out {}
    foreach legacy [analysisSourceDatasetVariables_v1_before_schema $datasetId] {
        set name [dict get $legacy name]
        if {[catch {set v [datasetVariableResolve $datasetId $name]}]} { lappend out [dict merge $legacy [dict create variable_id "" value_kind number value_format "" decimal_separator . time_reference elapsed time_origin "" semantic_source default semantic_reason ""]]; continue }
        foreach field {variable_id value_kind value_format decimal_separator time_reference time_origin semantic_source semantic_reason} { dict set legacy $field [dict get $v $field] }
        lappend out $legacy
    }
    return $out
}

# Legacy source|variable_id records do not identify a dataset. Reconcile only
# when the current source and visible historical name identify one candidate.
proc ::GX::moduleBindingIdentityLegacyCandidate {module role source variableId value} {
    set dataset [analysisSourceDatasetFor $module $source]
    if {$dataset eq ""} { error "Binding $module.$role has no dataset for source $source" }
    set dot [string first . $value]
    set name [expr {$dot > 0 ? [string range $value [expr {$dot+1}] end] : $value}]
    set candidate ""
    if {![catch {set byId [datasetVariableById $dataset $variableId]}] &&
        ($name eq [dict get $byId canonical] || $name eq [dict get $byId original_header])} {
        set matches 0
        foreach ds [datasetRegistryIds] {
            if {[catch {set v [datasetVariableById $ds $variableId]}]} continue
            if {$name eq [dict get $v canonical] || $name eq [dict get $v original_header]} { incr matches }
        }
        if {$matches == 1} { set candidate $byId }
    }
    if {$candidate eq ""} { error "Binding $module.$role has ambiguous legacy variable_id $variableId; select a variable explicitly" }
    return "$source|$dataset|[dict get $candidate variable_id]"
}

# The GUI supplies a visible canonical name, never an ID token. Avoid the
# public Resolve helper's ID-first fallback if a name resembles another ID.
proc ::GX::moduleBindingVariableByName {dataset name} {
    set found {}
    foreach v [datasetVariableSchema $dataset] {
        if {[dict get $v canonical] eq $name} { lappend found $v }
    }
    if {[llength $found] != 1} { error "Dataset $dataset has no unambiguous variable named $name" }
    return [lindex $found 0]
}

# This is called only by a user selection in the framework-owned binding
# combobox. Dataset changes alone never clear a stable identity.
proc ::GX::moduleBindingGuiSelected {module role} {
    variable moduleBinding
    variable moduleBindingIdentity
    set value [string trim $moduleBinding($module,$role)]
    if {$value eq "" || $value eq "auto"} {
        catch {unset moduleBindingIdentity($module,$role)}
    } else {
        set value [analysisSourceNormalizeBinding $module $value]
        set dot [string first . $value]
        set source [expr {$dot > 0 ? [string range $value 0 [expr {$dot-1}]] : "primary"}]
        set name [expr {$dot > 0 ? [string range $value [expr {$dot+1}] end] : $value}]
        set dataset [analysisSourceDatasetFor $module $source]
        if {$dataset eq ""} { error "No dataset for source $source" }
        set v [moduleBindingVariableByName $dataset $name]
        set moduleBindingIdentity($module,$role) "$source|$dataset|[dict get $v variable_id]"
    }
    catch {refreshManifestPreview}
}

proc ::GX::manifestStringV2_before_variable_references {} {
    variable moduleOrder
    variable moduleBinding
    variable moduleBindingIdentity
    set out [manifestStringV2_before_variable_ids]
    append out "\n\[dataset_variable_schema_api\]\n"; appendKV out version 2
    foreach module $moduleOrder {
        set lines ""
        foreach role [moduleBindingRoles $module] {
            if {![info exists moduleBinding($module,$role)]} continue
            set binding [string trim $moduleBinding($module,$role)]
            if {$binding in {"" auto}} continue
            set dot [string first . $binding]
            set source [expr {$dot > 0 ? [string range $binding 0 [expr {$dot-1}]] : "primary"}]
            set name [expr {$dot > 0 ? [string range $binding [expr {$dot+1}] end] : $binding}]
            set dataset [analysisSourceDatasetFor $module $source]
            if {$dataset eq ""} continue
            if {[info exists moduleBindingIdentity($module,$role)]} {
                set parts [split $moduleBindingIdentity($module,$role) |]
                if {[llength $parts] == 2} {
                    lassign $parts oldSource variableId
                    if {$oldSource eq $source &&
                        ![catch {set migrated [moduleBindingIdentityLegacyCandidate $module $role $source $variableId $binding]}]} {
                        set moduleBindingIdentity($module,$role) $migrated
                    }
                }
                # A modern identity is immutable on save. The visible name may
                # be stale after a source change or a variable rename.
            } elseif {![catch {set v [moduleBindingVariableByName $dataset $name]}]} {
                set moduleBindingIdentity($module,$role) "$source|$dataset|[dict get $v variable_id]"
            }
            if {[info exists moduleBindingIdentity($module,$role)]} { appendKV lines $role $moduleBindingIdentity($module,$role) }
        }
        if {$lines ne ""} { append out "\n\[module_binding_variable_id.$module\]\n$lines" }
    }
    return $out
}

proc ::GX::loadManifestV2_before_variable_references {path} {
    variable moduleBindingIdentity
    array unset moduleBindingIdentity *
    loadManifestV2_before_variable_ids $path
    set d [parseIni $path]
    foreach key [dict keys $d] {
        if {![regexp {^module_binding_variable_id\.(.+)\.([^.]+)$} $key -> module role]} continue
        set moduleBindingIdentity($module,$role) [dict get $d $key]
    }
}

proc ::GX::resolveModuleBinding {module role {modelId ""}} {
    variable moduleBinding
    variable moduleBindingIdentity
    set value [resolveModuleBinding_before_variable_ids $module $role $modelId]
    set explicit [expr {[info exists moduleBinding($module,$role)] ? [string trim $moduleBinding($module,$role)] : "auto"}]
    if {$explicit in {"" auto} || ![info exists moduleBindingIdentity($module,$role)]} { return $value }
    set parts [split $moduleBindingIdentity($module,$role) |]
    if {[llength $parts] == 2} {
        lassign $parts source variableId
        set identity [moduleBindingIdentityLegacyCandidate $module $role $source $variableId $value]
        set moduleBindingIdentity($module,$role) $identity
        set parts [split $identity |]
    }
    if {[llength $parts] != 3} { error "Binding $module.$role has malformed variable identity" }
    lassign $parts source dataset variableId
    set dot [string first . $value]
    set valueSource [expr {$dot > 0 ? [string range $value 0 [expr {$dot-1}]] : "primary"}]
    if {$valueSource ne $source} { error "Binding $module.$role changed source; select a variable explicitly" }
    set current [analysisSourceDatasetFor $module $source]
    if {$current ne $dataset} {
        error "Binding $module.$role belongs to dataset $dataset, but source $source now uses $current; select a variable explicitly"
    }
    if {[catch {set v [datasetVariableById $dataset $variableId]}]} {
        error "Binding $module.$role refers to missing $dataset/$variableId"
    }
    if {![dict get $v enabled]} { error "Binding $module.$role refers to excluded $dataset/$variableId" }
    set qualified [expr {[moduleSupportsAnalysisSources $module] || $dot > 0}]
    return [expr {$qualified ? "$source.[dict get $v canonical]" : [dict get $v canonical]}]
}

proc ::GX::datasetInspectionLoadImportedVariables {id} {
    variable inspectVar
    variable inspectVarCount
    array unset inspectVar *
    set inspectVarCount 0
    foreach v [datasetVariableSchema $id] {
        incr inspectVarCount
        foreach field [dict keys $v] { set inspectVar($inspectVarCount,$field) [dict get $v $field] }
    }
}

proc ::GX::datasetSchemaTemporalApplicable {enabled valueKind} {
    return [expr {$enabled && $valueKind eq "elapsed_time"}]
}

proc ::GX::datasetSchemaGuiRefreshTemporal {frame j} {
    variable inspectVar
    set temporal [datasetSchemaTemporalApplicable $inspectVar($j,enabled) $inspectVar($j,value_kind)]
    foreach suffix {vf tr} {
        $frame.${suffix}$j configure -state [expr {$temporal ? "readonly" : "disabled"}]
    }
    $frame.to$j configure -state [expr {$temporal ? "normal" : "disabled"}]
    $frame.de$j configure -state [expr {$inspectVar($j,enabled) && $inspectVar($j,value_kind) ne "text" ? "readonly" : "disabled"}]
}

proc ::GX::datasetSchemaGuiCustomRole {frame j} {
    variable inspectVar
    if {$inspectVar($j,semantic_role) eq "Custom..."} {
        set inspectVar($j,semantic_role) ""
        focus $frame.r$j
    }
}

proc ::GX::datasetInspectionRenderMappingTable {frame mode key} {
    variable inspectVarCount
    datasetInspectionRenderMappingTable_v1_before_schema $frame $mode $key
    if {$mode ne "imported"} return
    $frame.h1 configure -text "RAW #"
    foreach {col title} {8 {Canonical #} 9 {Value kind} 10 {Value format} 11 {Source decimal} 12 {Time reference} 13 {Time origin} 14 {Semantic source} 15 {Inference / choice} 16 {Canonical unit} 17 {To canonical} 18 {From canonical} 19 {Display label}} {
        ttk::label $frame.h$col -text $title
        grid $frame.h$col -row 0 -column $col -sticky w -padx 3 -pady 2
    }
    for {set j 1} {$j <= $inspectVarCount} {incr j} {
        foreach w [list $frame.e$j $frame.n$j $frame.u$j $frame.r$j $frame.i$j $frame.ic$j] { catch {$w state !disabled} }
        ttk::label $frame.cp$j -textvariable ::GX::inspectVar($j,canonical_position)
        destroy $frame.u$j
        ttk::combobox $frame.u$j -textvariable ::GX::inspectVar($j,unit) -values [unitRegistryList] -state normal -width 14
        grid $frame.u$j -row $j -column 4 -padx 3 -pady 2
        destroy $frame.r$j
        ttk::combobox $frame.r$j -textvariable ::GX::inspectVar($j,semantic_role) -values [concat [semanticRegistryGuiValues] {Custom...}] -state normal -width 18
        grid $frame.r$j -row $j -column 5 -padx 3 -pady 2
        bind $frame.r$j <<ComboboxSelected>> [list ::GX::datasetSchemaGuiCustomRole $frame $j]
        $frame.e$j configure -command [list ::GX::datasetSchemaGuiRefreshTemporal $frame $j]
        ttk::combobox $frame.vk$j -textvariable ::GX::inspectVar($j,value_kind) -values {number text elapsed_time} -state readonly -width 13
        ttk::combobox $frame.vf$j -textvariable ::GX::inspectVar($j,value_format) -values {"" hms} -state readonly -width 10
        ttk::combobox $frame.de$j -textvariable ::GX::inspectVar($j,decimal_separator) -values {. ,} -state readonly -width 6
        ttk::combobox $frame.tr$j -textvariable ::GX::inspectVar($j,time_reference) -values {elapsed absolute} -state readonly -width 10
        ttk::entry $frame.to$j -textvariable ::GX::inspectVar($j,time_origin) -width 24
        ttk::label $frame.ss$j -textvariable ::GX::inspectVar($j,semantic_source)
        ttk::label $frame.sr$j -textvariable ::GX::inspectVar($j,semantic_reason) -wraplength 260
        ttk::entry $frame.cu$j -textvariable ::GX::inspectVar($j,canonical_unit) -width 15
        ttk::entry $frame.tc$j -textvariable ::GX::inspectVar($j,to_canonical) -width 26
        ttk::entry $frame.fc$j -textvariable ::GX::inspectVar($j,from_canonical) -width 26
        ttk::entry $frame.dl$j -textvariable ::GX::inspectVar($j,display_label) -width 18
        bind $frame.vk$j <<ComboboxSelected>> [list ::GX::datasetSchemaGuiRefreshTemporal $frame $j]
        foreach {col suffix} {8 cp 9 vk 10 vf 11 de 12 tr 13 to 14 ss 15 sr 16 cu 17 tc 18 fc 19 dl} { grid $frame.${suffix}$j -row $j -column $col -padx 3 -pady 2 }
        datasetSchemaGuiRefreshTemporal $frame $j
    }
}

proc ::GX::refreshNativeVariablesGui_before_temporal_set_gui_v1 {} {
    variable variableDatasetChoice
    refreshNativeVariablesGui_v1_before_schema
    lassign [datasetInspectionParseChoice $variableDatasetChoice] mode id
    if {[winfo exists .datasetMetadataEditor] &&
        ($mode ne "imported" || $::GX::datasetMetadataEditorDataset ne $id)} {
        destroy .datasetMetadataEditor
    }
    if {![winfo exists .top.nb.channels.bar]} return
    set f .top.nb.channels
    if {$mode eq "imported"} {$f.summary configure -text "Active Dataset: $id\nProvenance is read-only. Edit canonical schema in Variables and save."}
    if {![winfo exists $f.bar.save]} {
    ttk::button $f.bar.save -text "Save canonical schema"
    ttk::button $f.bar.metadata -text "Metadata..." -command ::GX::datasetMetadataOpenSelectedFromGui
    ttk::button $f.bar.rename -text "Rename..." -command ::GX::datasetRenameSelectedFromGui
    ttk::button $f.bar.delete -text "Delete..." -command ::GX::datasetDeleteSelectedFromGui
    ttk::button $f.bar.help -text "Variables help (?)" -command ::GX::datasetVariablesHelpToggle
    pack $f.bar.save $f.bar.metadata $f.bar.rename $f.bar.delete $f.bar.help -side left -padx 8
    ttk::frame $f.help
    text $f.help.text -wrap word -height 16 -width 120 -state normal
    ttk::scrollbar $f.help.scroll -orient vertical -command [list $f.help.text yview]
    $f.help.text configure -yscrollcommand [list $f.help.scroll set]
    pack $f.help.scroll -side right -fill y
    pack $f.help.text -side left -fill both -expand 1
    $f.help.text insert end [datasetVariablesHelpText]
    $f.help.text configure -state disabled
    }
    $f.bar.save configure -command [list ::GX::datasetSchemaSaveImportedFromGui $id]
    foreach button {save metadata rename delete} {$f.bar.$button state [expr {$mode eq "imported"?"!disabled":"disabled"}]}
}

proc ::GX::datasetVariablesHelpToggle {} {
    if {[winfo exists .top.nb.channels.views.help]} {.top.nb.channels.views select .top.nb.channels.views.help;return}
    set panel .top.nb.channels.help
    if {![winfo exists $panel]} return
    if {[winfo manager $panel] eq ""} {
        grid $panel -row 4 -column 0 -sticky nsew -padx 8 -pady 6
    } else {
        grid remove $panel
    }
}

proc ::GX::datasetVariablesHelpText {} {
    return [noteReadUtf8 [file join $::GX::scriptDir docs DATASET_VARIABLES_GUIDE.txt]]
}
proc ::GX::datasetVariablesHelpIndex {} {
    set f .top.nb.channels.help
    if {[winfo exists $f.index]} return
    listbox $f.index -width 34 -exportselection 0 -height 10
    pack $f.index -side left -fill y -before $f.text
    $f.text configure -wrap word -padx 16 -pady 10
    $f.text tag configure heading -font TkHeadingFont -spacing1 14 -spacing3 6
    set ::GX::datasetHelpMarks {}
    set line 0
    foreach text [split [datasetVariablesHelpText] \n] {
        incr line
        if {[regexp {^[0-9][0-9]\. } $text]} {
            $f.index insert end $text
            lappend ::GX::datasetHelpMarks $line.0
            $f.text tag add heading $line.0 $line.end
        }
    }
    bind $f.index <<ListboxSelect>> {
        set index [lindex [.top.nb.channels.help.index curselection] 0]
        if {$index ne {}} {.top.nb.channels.help.text yview [lindex $::GX::datasetHelpMarks $index]}
    }
}

proc ::GX::datasetSchemaSaveImportedFromGui {id} {
    variable inspectVar
    variable inspectVarCount
    set changes [dict create]
    for {set j 1} {$j <= $inspectVarCount} {incr j} {
        set fields [dict create]
        foreach f {enabled canonical unit canonical_unit to_canonical from_canonical display_label semantic_role instrument_id instrument_channel value_kind value_format decimal_separator time_reference time_origin} { dict set fields $f $inspectVar($j,$f) }
        dict set changes $inspectVar($j,variable_id) $fields
    }
    if {[catch {datasetVariableSchemaUpdate $id $changes} err]} {
        tk_messageBox -icon error -type ok -title "Canonical schema" -message $err
        return
    }
    refreshNativeVariablesGui
    catch {refreshGenericCsvPreview}
    catch {refreshManifestPreview}
    setStatus "Canonical schema saved for dataset $id." 100
}

proc ::GX::datasetInspectionRenderPreview_before_dataset_preview_v1 {w choice} {
    datasetInspectionRenderPreview_v1_before_schema $w $choice
    lassign [datasetInspectionParseChoice $choice] mode id
    if {$mode ne "imported"} return
    set content [$w get 1.0 end]
    set content [string map {CSV# RAW#} $content]
    set positions {}
    foreach v [datasetVariableSchema $id] {
        if {![dict get $v enabled]} continue
        lappend positions "[dict get $v canonical]=[dict get $v canonical_position] (RAW [dict get $v source_column])"
    }
    append content "\nCanonical positions: [join $positions {; }]\nExcluded RAW columns are shown with Use=no and are not canonical dataset fields.\n"
    $w configure -state normal; $w delete 1.0 end; $w insert end $content; $w configure -state disabled
}
proc ::GX::datasetInspectionRenderPreview {w choice} {
    return [::GX::datasetInspectionRenderPreview_before_dataset_preview_v1 $w $choice]
}

proc ::GX::datasetSchemaReferenceDataset {module source} {
    variable moduleCfg
    set ds [analysisSourceDatasetFor $module $source]
    if {$ds eq "" && $source eq "primary" && [info exists moduleCfg($module,dataset_id)]} { set ds $moduleCfg($module,dataset_id) }
    return $ds
}

proc ::GX::datasetSchemaRefreshVariableConfigs {datasetId old} {
    variable moduleOrder
    variable moduleCfg
    variable repeatableValue
    variable variableReferenceIdentity
    foreach module $moduleOrder {
        foreach key [moduleConfigKeys $module] {
            if {[string tolower [moduleConfigField $module $key type string]] ne "variable"} continue
            set source [moduleConfigField $module $key source primary]
            if {[datasetSchemaReferenceDataset $module $source] ne $datasetId || ![info exists moduleCfg($module,$key)]} continue
            set value $moduleCfg($module,$key)
            dict for {vid v} $old {
                if {[dict get $v canonical] ne $value} continue
                set moduleCfg($module,$key) [dict get [datasetVariableById $datasetId $vid] canonical]
                set variableReferenceIdentity($module,$key) "$source|$vid"
                break
            }
        }
        foreach table [repeatableConfigTableKeys $module] {
            foreach row [repeatableConfigRows $module $table] {
                foreach col [repeatableConfigColumns $module $table] {
                    if {[string tolower [repeatableColumnField $module $table $col type string]] ne "variable"} continue
                    if {[repeatableVariableDatasetId $module $table $col] ne $datasetId || ![info exists repeatableValue($module,$table,$row,$col)]} continue
                    set value $repeatableValue($module,$table,$row,$col)
                    dict for {vid v} $old {
                        if {[dict get $v canonical] ne $value} continue
                        set repeatableValue($module,$table,$row,$col) [dict get [datasetVariableById $datasetId $vid] canonical]
                        set variableReferenceIdentity($module,$table,$row,$col) "$datasetId|$vid"
                        break
                    }
                }
            }
        }
    }
}

proc ::GX::manifestStringV2_before_graph_series {} {
    variable moduleOrder
    variable moduleCfg
    variable repeatableValue
    variable variableReferenceIdentity
    set out [manifestStringV2_before_variable_references]
    foreach module $moduleOrder {
        set scalar ""
        foreach key [moduleConfigKeys $module] {
            if {[string tolower [moduleConfigField $module $key type string]] ne "variable" || ![info exists moduleCfg($module,$key)]} continue
            set source [moduleConfigField $module $key source primary]
            set ds [datasetSchemaReferenceDataset $module $source]
            if {$ds eq ""} continue
            if {![catch {set v [datasetVariableResolve $ds $moduleCfg($module,$key)]}]} { set variableReferenceIdentity($module,$key) "$ds|[dict get $v variable_id]" }
            if {[info exists variableReferenceIdentity($module,$key)]} { appendKV scalar $key $variableReferenceIdentity($module,$key) }
        }
        if {$scalar ne ""} { append out "\n\[variable_reference_id.$module\]\n$scalar" }
        foreach table [repeatableConfigTableKeys $module] {
            foreach row [repeatableConfigRows $module $table] {
                set lines ""
                foreach col [repeatableConfigColumns $module $table] {
                    if {[string tolower [repeatableColumnField $module $table $col type string]] ne "variable"} continue
                    set ds [repeatableVariableDatasetId $module $table $col]
                    if {$ds eq "" || ![info exists repeatableValue($module,$table,$row,$col)]} continue
                    if {![catch {set v [datasetVariableResolve $ds $repeatableValue($module,$table,$row,$col)]}]} { set variableReferenceIdentity($module,$table,$row,$col) "$ds|[dict get $v variable_id]" }
                    if {[info exists variableReferenceIdentity($module,$table,$row,$col)]} { appendKV lines $col $variableReferenceIdentity($module,$table,$row,$col) }
                }
                if {$lines ne ""} { append out "\n\[repeatable_variable_id.$module.$table.$row\]\n$lines" }
            }
        }
    }
    return $out
}

proc ::GX::loadManifestV2_before_graph_series {path} {
    variable variableReferenceIdentity
    array unset variableReferenceIdentity *
    loadManifestV2_before_variable_references $path
    set d [parseIni $path]
    foreach key [dict keys $d] {
        if {[regexp {^variable_reference_id\.(.+)\.([^.]+)$} $key -> module field]} { set variableReferenceIdentity($module,$field) [dict get $d $key] }
        if {[regexp {^repeatable_variable_id\.(.+)\.([^.]+)\.([^.]+)\.([^.]+)$} $key -> module table row col]} { set variableReferenceIdentity($module,$table,$row,$col) [dict get $d $key] }
    }
    datasetSchemaRestoreVariableConfigs
}

proc ::GX::datasetSchemaRestoreVariableConfigs {} {
    variable variableReferenceIdentity
    variable moduleCfg
    variable repeatableValue
    variable currentSession
    if {$currentSession eq "" || ![file isdirectory $currentSession]} return
    loadDatasetRegistry $currentSession
    foreach key [array names variableReferenceIdentity] {
        lassign [split $variableReferenceIdentity($key) |] ds vid
        if {[catch {set v [datasetVariableById $ds $vid]}]} continue
        set parts [split $key ,]
        if {[llength $parts] == 2} { lassign $parts module field; set moduleCfg($module,$field) [dict get $v canonical] }
        if {[llength $parts] == 4} { lassign $parts module table row col; set repeatableValue($module,$table,$row,$col) [dict get $v canonical] }
    }
}

proc ::GX::writeStandardRuntimeConfig_before_graph_series {id} {
    variable currentSession
    if {$currentSession ne "" && [file isdirectory $currentSession]} {
        loadDatasetRegistry $currentSession
        saveDatasetRegistry $currentSession
        datasetSchemaRestoreVariableConfigs
    }
    return [writeStandardRuntimeConfig_before_schema_v2 $id]
}
