# GX-TXT Repeatable Config / Model Resource API v1
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Additive v0.9.2 framework extension for descriptor-driven repeatable tables.
# v0.9.3.1 adds optional/clearable model selectors and descriptor-driven model kind filtering.
# It is intentionally generic: rows and typed columns are owned by the
# framework, not by individual scientific modules.  type=model cells are
# published as named mathematical-model resources with framework-owned
# parameter/bound editing.
#
# Example descriptor:
#   [config.parameter_models]
#   type=table
#   dynamic=1
#   min_rows=1
#   columns=parameter;uncertainty;model
#
#   [config.parameter_models.parameter]
#   type=variable
#   source=primary
#   required=1
#
#   [config.parameter_models.uncertainty]
#   type=variable
#   source=primary
#   required=0
#
#   [config.parameter_models.model]
#   type=model
#   required=1

namespace eval ::GX {
    variable repeatableConfigApiVersion 1
    variable modelResourceApiVersion 1
    variable repeatableRows
    variable repeatableValue
    variable repeatableNext
    variable repeatableWidget
    variable repeatableRefreshing
    variable modelParamValue
    array set repeatableRows {}
    array set repeatableValue {}
    array set repeatableNext {}
    array set repeatableWidget {}
    array set repeatableRefreshing {}
    array set modelParamValue {}
}

proc ::GX::repeatableConfigColumns {moduleId key} {
    return [splitList [moduleConfigField $moduleId $key columns ""]]
}

proc ::GX::repeatableConfigField {moduleId key field {default ""}} {
    return [moduleConfigField $moduleId $key $field $default]
}

proc ::GX::repeatableColumnField {moduleId key column field {default ""}} {
    variable moduleCatalog
    if {![info exists moduleCatalog($moduleId,dict)]} { return $default }
    return [descriptorValue $moduleCatalog($moduleId,dict) "config.$key.$column" $field $default]
}

proc ::GX::repeatableConfigIsTable {moduleId key} {
    return [expr {[string tolower [moduleConfigField $moduleId $key type string]] eq "table"}]
}

proc ::GX::repeatableConfigTableKeys {moduleId} {
    set out {}
    foreach key [moduleConfigKeys $moduleId] {
        if {[repeatableConfigIsTable $moduleId $key]} { lappend out $key }
    }
    return $out
}

proc ::GX::repeatableConfigRows {moduleId key} {
    variable repeatableRows
    repeatableConfigEnsure $moduleId $key
    return $repeatableRows($moduleId,$key)
}

# Typed snapshot adapters expose the existing Repeatable authority to scoped
# Configuration clients. They introduce no additional persistent table store.
proc ::GX::repeatableConfigSnapshot {module key} {
    set rows {}
    foreach row [repeatableConfigRows $module $key] {
        set values {}
        foreach column [repeatableConfigColumns $module $key] {
            dict set values $column $::GX::repeatableValue($module,$key,$row,$column)
        }
        lappend rows [dict create id $row values $values]
    }
    return [dict create api_id REPEATABLE_CONFIG_API_v1 rows $rows]
}
proc ::GX::repeatableConfigDefaultSnapshot {module key} {
    set rows {};set count [repeatableConfigField $module $key min_rows 0]
    for {set i 1} {$i<=$count} {incr i} {
        set values {}
        foreach column [repeatableConfigColumns $module $key] {dict set values $column [repeatableConfigDefaultForColumn $module $key $column]}
        lappend rows [dict create id row$i values $values]
    }
    return [dict create api_id REPEATABLE_CONFIG_API_v1 rows $rows]
}
proc ::GX::repeatableConfigValidateSnapshot {module key snapshot} {
    if {[catch {dict get $snapshot rows} rows] || [datasetPublicationV2DictDefault $snapshot api_id {}] ne "REPEATABLE_CONFIG_API_v1"} {error {Invalid Repeatable Configuration snapshot}}
    set min [repeatableConfigField $module $key min_rows 0]
    set max [repeatableConfigField $module $key max_rows 4096]
    if {[llength $rows]<$min || [llength $rows]>$max} {error "Table requires $min..$max rows"}
    set identities {};set result {}
    foreach row $rows {
        set id [dict get $row id]
        if {![regexp {^[A-Za-z][A-Za-z0-9_.-]*$} $id] || $id in $identities} {error {Invalid/duplicate configuration row identity}}
        lappend identities $id;set values [dict get $row values];set normalized {}
        foreach column [dict keys $values] {if {$column ni [repeatableConfigColumns $module $key]} {error "Unknown table column '$column'"}}
        foreach column [repeatableConfigColumns $module $key] {
            set type [repeatableColumnField $module $key $column type string]
            set descriptor [dict create type $type label [repeatableColumnField $module $key $column label $column]]
            foreach option {required min max alpha} {set v [repeatableColumnField $module $key $column $option {}];if {$v ne {}} {dict set descriptor $option $v}}
            set choices {}
            switch $type {
                variable {set choices [repeatableVariableValues $module $key $column]}
                model {set choices [repeatableModelValues $module $key $column]}
                choice {set choices [splitList [repeatableColumnField $module $key $column values {}]]}
            }
            if {$type ni [dict get [uiFieldApiInfo] types]} {dict set descriptor type string}
            if {$type in {variable model choice}} {dict set descriptor type choice;dict set descriptor values $choices}
            set value [datasetPublicationV2DictDefault $values $column [repeatableConfigDefaultForColumn $module $key $column]]
            dict set normalized $column [uiFieldNormalize $descriptor $value]
        }
        lappend result [dict create id $id values $normalized]
    }
    return [dict create api_id REPEATABLE_CONFIG_API_v1 rows $result]
}
proc ::GX::repeatableConfigApplySnapshot {module key snapshot} {
    set snapshot [repeatableConfigValidateSnapshot $module $key $snapshot]
    set ::GX::repeatableRows($module,$key) {}
    array unset ::GX::repeatableValue "$module,$key,*"
    foreach row [dict get $snapshot rows] {
        set id [dict get $row id];lappend ::GX::repeatableRows($module,$key) $id
        dict for {column value} [dict get $row values] {set ::GX::repeatableValue($module,$key,$id,$column) $value}
    }
    repeatableConfigRefreshWidget $module $key
    return $snapshot
}

proc ::GX::repeatableConfigNextRowId {moduleId key} {
    variable repeatableNext
    variable repeatableRows
    if {![info exists repeatableNext($moduleId,$key)]} { set repeatableNext($moduleId,$key) 0 }
    set rows [expr {[info exists repeatableRows($moduleId,$key)] ? $repeatableRows($moduleId,$key) : {}}]
    while 1 {
        incr repeatableNext($moduleId,$key)
        set rowId "row$repeatableNext($moduleId,$key)"
        if {[lsearch -exact $rows $rowId] < 0} { return $rowId }
    }
}

proc ::GX::repeatableConfigDefaultForColumn {moduleId key column} {
    set d [repeatableColumnField $moduleId $key $column default ""]
    if {$d ne ""} { return $d }
    return ""
}

proc ::GX::repeatableConfigAddRow {moduleId key {rowId ""}} {
    variable repeatableRows
    variable repeatableValue
    variable repeatableNext
    if {$rowId eq ""} { set rowId [repeatableConfigNextRowId $moduleId $key] }
    if {![info exists repeatableRows($moduleId,$key)]} { set repeatableRows($moduleId,$key) {} }
    if {[lsearch -exact $repeatableRows($moduleId,$key) $rowId] < 0} { lappend repeatableRows($moduleId,$key) $rowId }
    if {[regexp {^row([0-9]+)$} $rowId -> n]} {
        if {![info exists repeatableNext($moduleId,$key)] || $n > $repeatableNext($moduleId,$key)} { set repeatableNext($moduleId,$key) $n }
    }
    foreach c [repeatableConfigColumns $moduleId $key] {
        if {![info exists repeatableValue($moduleId,$key,$rowId,$c)]} {
            set repeatableValue($moduleId,$key,$rowId,$c) [repeatableConfigDefaultForColumn $moduleId $key $c]
        }
    }
    if {![info exists ::GX::repeatableRefreshing($moduleId,$key)] || !$::GX::repeatableRefreshing($moduleId,$key)} {
        catch {repeatableConfigRefreshWidget $moduleId $key}
    }
    catch {refreshManifestPreview}
    return $rowId
}

proc ::GX::repeatableConfigRemoveRow {moduleId key rowId} {
    variable repeatableRows
    variable repeatableValue
    repeatableConfigEnsure $moduleId $key
    set min [repeatableConfigField $moduleId $key min_rows 0]
    if {![string is integer -strict $min] || $min < 0} { set min 0 }
    if {[llength $repeatableRows($moduleId,$key)] <= $min} { return 0 }
    set i [lsearch -exact $repeatableRows($moduleId,$key) $rowId]
    if {$i < 0} { return 0 }
    set repeatableRows($moduleId,$key) [lreplace $repeatableRows($moduleId,$key) $i $i]
    foreach c [repeatableConfigColumns $moduleId $key] { catch {unset repeatableValue($moduleId,$key,$rowId,$c)} }
    catch {repeatableConfigRefreshWidget $moduleId $key}
    catch {refreshManifestPreview}
    return 1
}

proc ::GX::repeatableConfigEnsure {moduleId key} {
    variable repeatableRows
    if {![info exists repeatableRows($moduleId,$key)]} { set repeatableRows($moduleId,$key) {} }
    set min [repeatableConfigField $moduleId $key min_rows 0]
    if {![string is integer -strict $min] || $min < 0} { set min 0 }
    while {[llength $repeatableRows($moduleId,$key)] < $min} { repeatableConfigAddRow $moduleId $key }
    return $repeatableRows($moduleId,$key)
}

proc ::GX::repeatableVariableDatasetId {moduleId key column} {
    set source [string trim [repeatableColumnField $moduleId $key $column source [repeatableColumnField $moduleId $key $column source_role primary]]]
    if {$source eq ""} { set source primary }
    if {[llength [info commands ::GX::datasetSelectionSourceDataset]]} {
        set ds [datasetSelectionSourceDataset $moduleId $source]
        if {$ds ne ""} { return $ds }
    }
    variable moduleCfg
    if {$source eq "primary" && [info exists moduleCfg($moduleId,dataset_id)]} { return [string trim $moduleCfg($moduleId,dataset_id)] }
    return ""
}

proc ::GX::repeatableVariableValues {moduleId key column} {
    variable currentSession
    if {$currentSession ne "" && [file isdirectory $currentSession]} { catch {loadDatasetRegistry $currentSession} }
    set ds [repeatableVariableDatasetId $moduleId $key $column]
    if {$ds eq ""} { return {} }
    if {[llength [info commands ::GX::datasetVariableNamesById]]} { return [datasetVariableNamesById $ds] }
    return [splitList [datasetField $ds columns ""]]
}

# v0.9.3.1: descriptor-driven mathematical-model filtering and optional selectors.
# `kinds` is a semicolon/comma separated allow-list of model meta.kind values.
# `kind` is accepted as a singular compatibility alias.
proc ::GX::modelKindsNormalize {raw} {
    set out {}
    foreach k [splitList $raw] {
        set k [string tolower [string trim $k]]
        if {$k ne "" && [lsearch -exact $out $k] < 0} { lappend out $k }
    }
    return $out
}

proc ::GX::modelIdsForKinds {kinds {required 1}} {
    variable modelOrder
    set kinds [modelKindsNormalize $kinds]
    set out {}
    if {!$required} { lappend out "" }
    foreach mid $modelOrder {
        if {[modelField $mid descriptor ""] eq ""} continue
        if {[llength $kinds]} {
            set mk [string tolower [string trim [modelField $mid kind ""]]]
            if {[lsearch -exact $kinds $mk] < 0} continue
        }
        lappend out $mid
    }
    return $out
}

proc ::GX::scalarModelKinds {moduleId key} {
    set raw [moduleConfigField $moduleId $key kinds ""]
    if {[string trim $raw] eq ""} { set raw [moduleConfigField $moduleId $key kind ""] }
    return [modelKindsNormalize $raw]
}

proc ::GX::repeatableModelKinds {moduleId key column} {
    set raw [repeatableColumnField $moduleId $key $column kinds ""]
    if {[string trim $raw] eq ""} { set raw [repeatableColumnField $moduleId $key $column kind ""] }
    return [modelKindsNormalize $raw]
}

proc ::GX::scalarModelValues {moduleId key} {
    set required [expr {[moduleConfigField $moduleId $key required 0] ? 1 : 0}]
    return [modelIdsForKinds [scalarModelKinds $moduleId $key] $required]
}

proc ::GX::repeatableModelValues {moduleId key column} {
    set required [expr {[repeatableColumnField $moduleId $key $column required 0] ? 1 : 0}]
    return [modelIdsForKinds [repeatableModelKinds $moduleId $key $column] $required]
}

proc ::GX::modelKindAllowed {modelId kinds} {
    set kinds [modelKindsNormalize $kinds]
    if {![llength $kinds]} { return 1 }
    set mk [string tolower [string trim [modelField $modelId kind ""]]]
    return [expr {[lsearch -exact $kinds $mk] >= 0}]
}

proc ::GX::repeatableConfigValueChanged {moduleId key rowId column} {
    variable repeatableValue
    set typ [string tolower [repeatableColumnField $moduleId $key $column type string]]
    if {$typ eq "model"} {
        set mid [string trim $repeatableValue($moduleId,$key,$rowId,$column)]
        if {$mid ne ""} { catch {modelResourceParametersEnsure $moduleId "$key.$rowId" $mid} }
    }
    catch {refreshManifestPreview}
}

proc ::GX::repeatableConfigValidate {moduleId key} {
    variable repeatableValue
    repeatableConfigEnsure $moduleId $key
    set rows [repeatableConfigRows $moduleId $key]
    set min [repeatableConfigField $moduleId $key min_rows 0]
    if {![string is integer -strict $min] || $min < 0} { set min 0 }
    if {[llength $rows] < $min} { error "$moduleId: table '$key' requires at least $min row(s)." }
    set max [repeatableConfigField $moduleId $key max_rows ""]
    if {$max ne "" && [string is integer -strict $max] && [llength $rows] > $max} { error "$moduleId: table '$key' allows at most $max row(s)." }
    foreach rowId $rows {
        foreach c [repeatableConfigColumns $moduleId $key] {
            set typ [string tolower [repeatableColumnField $moduleId $key $c type string]]
            set req [expr {[repeatableColumnField $moduleId $key $c required 0] ? 1 : 0}]
            set v [expr {[info exists repeatableValue($moduleId,$key,$rowId,$c)] ? [string trim $repeatableValue($moduleId,$key,$rowId,$c)] : ""}]
            if {$req && $v eq ""} { error "$moduleId: table '$key' row '$rowId' requires '$c'." }
            if {$v eq ""} continue
            switch -- $typ {
                variable {
                    set vals [repeatableVariableValues $moduleId $key $c]
                    if {[lsearch -exact $vals $v] < 0} { error "$moduleId: table '$key' row '$rowId' variable '$v' is not available for column '$c'." }
                }
                model {
                    if {[modelField $v descriptor ""] eq ""} { error "$moduleId: table '$key' row '$rowId' references unknown model '$v'." }
                    set kinds [repeatableModelKinds $moduleId $key $c]
                    if {![modelKindAllowed $v $kinds]} {
                        error "$moduleId: table '$key' row '$rowId' model '$v' has kind '[modelField $v kind ""]', expected one of '[join $kinds {;}]'."
                    }
                    modelResourceParametersValidate $moduleId "$key.$rowId" $v
                }
                choice {
                    set vals [splitList [repeatableColumnField $moduleId $key $c values ""]]
                    if {[llength $vals] && [lsearch -exact $vals $v] < 0} { error "$moduleId: table '$key' row '$rowId' invalid '$c' value '$v'." }
                }
                integer { if {![string is integer -strict $v]} { error "$moduleId: table '$key' row '$rowId' '$c' must be an integer." } }
                number - float - double { if {![string is double -strict $v]} { error "$moduleId: table '$key' row '$rowId' '$c' must be numeric." } }
            }
        }
    }
    return 1
}

# -----------------------------------------------------------------------------
# Mathematical model resources and standard parameter/bound editor
# -----------------------------------------------------------------------------
proc ::GX::modelResourceParameterNames {modelId} { return [splitList [modelField $modelId param_names ""]] }

proc ::GX::modelResourceDescriptorValues {modelId attr} {
    set raw [modelField $modelId "param_$attr" ""]
    if {$raw eq ""} { return {} }
    # Model parameter lists use semicolons by contract.  splitList also accepts commas.
    return [splitList $raw]
}

proc ::GX::modelResourceParametersEnsure {moduleId owner modelId} {
    variable modelParamValue
    set names [modelResourceParameterNames $modelId]
    foreach attr {initial lower upper} {
        set defs [modelResourceDescriptorValues $modelId $attr]
        for {set i 0} {$i < [llength $names]} {incr i} {
            set p [lindex $names $i]
            set k "$moduleId,$owner,$modelId,$p,$attr"
            if {![info exists modelParamValue($k)]} { set modelParamValue($k) [expr {$i < [llength $defs] ? [lindex $defs $i] : ""}] }
        }
    }
}

proc ::GX::modelResourceParametersList {moduleId owner modelId attr} {
    variable modelParamValue
    modelResourceParametersEnsure $moduleId $owner $modelId
    set out {}
    foreach p [modelResourceParameterNames $modelId] {
        set k "$moduleId,$owner,$modelId,$p,$attr"
        lappend out [expr {[info exists modelParamValue($k)] ? $modelParamValue($k) : ""}]
    }
    return $out
}

proc ::GX::modelResourceParametersValidate {moduleId owner modelId} {
    variable modelParamValue
    if {$modelId eq ""} { return 1 }
    if {[modelField $modelId descriptor ""] eq ""} { error "$moduleId: unknown mathematical model '$modelId'." }
    modelResourceParametersEnsure $moduleId $owner $modelId
    foreach p [modelResourceParameterNames $modelId] {
        foreach attr {initial lower upper} {
            set v $modelParamValue($moduleId,$owner,$modelId,$p,$attr)
            if {[string trim $v] ne "" && ![string is double -strict $v]} { error "$moduleId/$owner: model '$modelId' parameter '$p' $attr must be numeric." }
        }
        set ini $modelParamValue($moduleId,$owner,$modelId,$p,initial)
        set lo $modelParamValue($moduleId,$owner,$modelId,$p,lower)
        set hi $modelParamValue($moduleId,$owner,$modelId,$p,upper)
        if {$lo ne "" && $hi ne "" && double($lo) > double($hi)} { error "$moduleId/$owner: model '$modelId' parameter '$p' has lower > upper." }
        if {$ini ne "" && $lo ne "" && double($ini) < double($lo)} { error "$moduleId/$owner: model '$modelId' parameter '$p' initial is below lower bound." }
        if {$ini ne "" && $hi ne "" && double($ini) > double($hi)} { error "$moduleId/$owner: model '$modelId' parameter '$p' initial is above upper bound." }
    }
    return 1
}

proc ::GX::modelResourceParametersReset {moduleId owner modelId} {
    variable modelParamValue
    foreach p [modelResourceParameterNames $modelId] {
        foreach attr {initial lower upper} { catch {unset modelParamValue($moduleId,$owner,$modelId,$p,$attr)} }
    }
    modelResourceParametersEnsure $moduleId $owner $modelId
    catch {modelResourceParameterDialogRefresh $moduleId $owner $modelId}
}

proc ::GX::modelResourceParameterDialogRefresh {moduleId owner modelId} {
    set w .modelResourceParameters
    if {![winfo exists $w]} return
    # Entry widgets are variable-backed; rebuilding is only required after Reset.
    if {[winfo exists $w.table]} { destroy $w.table }
    ttk::frame $w.table
    grid $w.table -row 1 -column 0 -sticky nsew -padx 8 -pady 6
    grid columnconfigure $w.table 0 -weight 1
    foreach {c h} {0 Parameter 1 Initial 2 Lower 3 Upper} { ttk::label $w.table.h$c -text $h; grid $w.table.h$c -row 0 -column $c -sticky w -padx 3 }
    modelResourceParametersEnsure $moduleId $owner $modelId
    set r 1
    foreach p [modelResourceParameterNames $modelId] {
        ttk::label $w.table.p$r -text $p
        grid $w.table.p$r -row $r -column 0 -sticky w -padx 3 -pady 2
        set c 1
        foreach attr {initial lower upper} {
            ttk::entry $w.table.${attr}$r -textvariable ::GX::modelParamValue($moduleId,$owner,$modelId,$p,$attr) -width 18
            grid $w.table.${attr}$r -row $r -column $c -sticky ew -padx 3 -pady 2
            incr c
        }
        incr r
    }
}

proc ::GX::modelResourceParameterDialogClose {moduleId owner modelId} {
    if {[catch {modelResourceParametersValidate $moduleId $owner $modelId} err]} { tk_messageBox -icon error -message $err; return }
    catch {refreshManifestPreview}
    destroy .modelResourceParameters
}

proc ::GX::modelResourceParameterDialog {moduleId owner modelId} {
    set modelId [string trim $modelId]
    if {$modelId eq ""} { tk_messageBox -icon info -message "Select a mathematical model first."; return }
    if {[modelField $modelId descriptor ""] eq ""} { tk_messageBox -icon error -message "Unknown mathematical model: $modelId"; return }
    modelResourceParametersEnsure $moduleId $owner $modelId
    set w .modelResourceParameters; catch {destroy $w}; toplevel $w
    wm title $w "Model parameters — $modelId"
    wm geometry $w 720x520
    grid columnconfigure $w 0 -weight 1; grid rowconfigure $w 1 -weight 1
    ttk::label $w.info -text "Framework-owned parameter/bound editor — $moduleId / $owner / $modelId" -anchor w
    grid $w.info -row 0 -column 0 -sticky ew -padx 8 -pady {8 2}
    modelResourceParameterDialogRefresh $moduleId $owner $modelId
    ttk::frame $w.buttons
    ttk::button $w.buttons.reset -text "Reset defaults" -command [list ::GX::modelResourceParametersReset $moduleId $owner $modelId]
    ttk::button $w.buttons.close -text "Close" -command [list ::GX::modelResourceParameterDialogClose $moduleId $owner $modelId]
    pack $w.buttons.reset -side left -padx 4; pack $w.buttons.close -side right -padx 4
    grid $w.buttons -row 2 -column 0 -sticky ew -padx 8 -pady 8
}

proc ::GX::modelResourceWriteSection {fd section moduleId owner modelId} {
    variable scriptDir
    if {$modelId eq ""} return
    modelResourceParametersValidate $moduleId $owner $modelId
    set descriptor [file normalize [modelField $modelId descriptor ""]]
    puts $fd "\n\[$section\]"
    putKV $fd api_version 1
    putKV $fd id $modelId
    putKV $fd descriptor_path $descriptor
    putKV $fd plugin_dir [file dirname $descriptor]
    foreach f {kind name version function y_unit x_column family_column y_column} { putKV $fd $f [modelField $modelId $f ""] }
    set script [modelField $modelId script ""]
    if {$script ne "" && [file pathtype $script] eq "relative"} { set script [file join $scriptDir $script] }
    putKV $fd script $script
    putKV $fd param_names [join [modelResourceParameterNames $modelId] ";"]
    foreach attr {initial lower upper} { putKV $fd "param_$attr" [join [modelResourceParametersList $moduleId $owner $modelId $attr] ";"] }
}

# -----------------------------------------------------------------------------
# Descriptor-driven table GUI
# -----------------------------------------------------------------------------
proc ::GX::repeatableVariableWidgetRefresh {w moduleId key column} {
    if {![winfo exists $w]} return
    set vals [repeatableVariableValues $moduleId $key $column]
    set required [expr {[repeatableColumnField $moduleId $key $column required 0] ? 1 : 0}]
    if {!$required} { set vals [linsert $vals 0 ""] }
    $w configure -values $vals
}

proc ::GX::repeatableModelWidgetRefresh {w moduleId key column} {
    if {![winfo exists $w]} return
    $w configure -values [repeatableModelValues $moduleId $key $column]
}

proc ::GX::repeatableConfigBuildCell {parent moduleId key rowId column guiRow guiCol} {
    variable repeatableValue
    variable modelOrder
    set typ [string tolower [repeatableColumnField $moduleId $key $column type string]]
    set required [expr {[repeatableColumnField $moduleId $key $column required 0] ? 1 : 0}]
    set wp "$parent.${rowId}_${column}"
    switch -- $typ {
        variable {
            set vals [repeatableVariableValues $moduleId $key $column]
            if {!$required} { set vals [linsert $vals 0 ""] }
            ttk::combobox $wp -textvariable ::GX::repeatableValue($moduleId,$key,$rowId,$column) -values $vals -state readonly -width 24 \
                -postcommand [list ::GX::repeatableVariableWidgetRefresh $wp $moduleId $key $column]
            bind $wp <<ComboboxSelected>> [list ::GX::repeatableConfigValueChanged $moduleId $key $rowId $column]
        }
        model {
            ttk::frame $wp
            ttk::combobox $wp.sel -textvariable ::GX::repeatableValue($moduleId,$key,$rowId,$column) \
                -values [repeatableModelValues $moduleId $key $column] -state readonly -width 24 \
                -postcommand [list ::GX::repeatableModelWidgetRefresh $wp.sel $moduleId $key $column]
            ttk::button $wp.params -text "Parameters..." -command [list ::GX::repeatableModelParametersOpen $moduleId $key $rowId $column]
            bind $wp.sel <<ComboboxSelected>> [list ::GX::repeatableConfigValueChanged $moduleId $key $rowId $column]
            pack $wp.sel -side left -fill x -expand 1; pack $wp.params -side left -padx {4 0}
        }
        choice {
            ttk::combobox $wp -textvariable ::GX::repeatableValue($moduleId,$key,$rowId,$column) -values [splitList [repeatableColumnField $moduleId $key $column values ""]] -state readonly -width 22
            bind $wp <<ComboboxSelected>> [list ::GX::repeatableConfigValueChanged $moduleId $key $rowId $column]
        }
        default {
            ttk::entry $wp -textvariable ::GX::repeatableValue($moduleId,$key,$rowId,$column) -width 24
            bind $wp <FocusOut> [list ::GX::repeatableConfigValueChanged $moduleId $key $rowId $column]
        }
    }
    grid $wp -row $guiRow -column $guiCol -sticky ew -padx 2 -pady 2
    grid columnconfigure $parent $guiCol -weight 1
}

proc ::GX::repeatableModelParametersOpen {moduleId key rowId column} {
    variable repeatableValue
    set mid [expr {[info exists repeatableValue($moduleId,$key,$rowId,$column)] ? $repeatableValue($moduleId,$key,$rowId,$column) : ""}]
    modelResourceParameterDialog $moduleId "$key.$rowId" $mid
}

proc ::GX::repeatableConfigRefreshWidget {moduleId key} {
    variable repeatableWidget
    variable repeatableRows
    variable repeatableValue
    variable repeatableRefreshing
    if {![info exists repeatableWidget($moduleId,$key)]} return
    set f $repeatableWidget($moduleId,$key)
    if {![winfo exists $f]} return
    set repeatableRefreshing($moduleId,$key) 1
    foreach c [winfo children $f] { destroy $c }
    repeatableConfigEnsure $moduleId $key
    set cols [repeatableConfigColumns $moduleId $key]
    set cidx 0
    foreach c $cols {
        ttk::label $f.h$cidx -text [repeatableColumnField $moduleId $key $c label $c]
        grid $f.h$cidx -row 0 -column $cidx -sticky w -padx 2 -pady {2 4}
        incr cidx
    }
    ttk::label $f.hact -text ""
    grid $f.hact -row 0 -column $cidx
    set rr 1
    foreach rowId $repeatableRows($moduleId,$key) {
        set cc 0
        foreach c $cols { repeatableConfigBuildCell $f $moduleId $key $rowId $c $rr $cc; incr cc }
        ttk::button $f.rm$rr -text "Remove" -command [list ::GX::repeatableConfigRemoveRow $moduleId $key $rowId]
        grid $f.rm$rr -row $rr -column $cc -sticky w -padx 4 -pady 2
        incr rr
    }
    ttk::button $f.add -text "+ Add" -command [list ::GX::repeatableConfigAddRow $moduleId $key]
    grid $f.add -row $rr -column 0 -sticky w -padx 2 -pady {5 2}
    ttk::label $f.hint -text "Framework-owned repeatable configuration. Rows are persisted in the session manifest and resolved into runtime.ini." -foreground #555555
    grid $f.hint -row $rr -column 1 -columnspan [expr {max(1,[llength $cols])}] -sticky w -padx 4 -pady {5 2}
    set repeatableRefreshing($moduleId,$key) 0
}

proc ::GX::repeatableConfigBuildWidget {parent moduleId key row} {
    variable repeatableWidget
    set label [moduleConfigField $moduleId $key label $key]
    ttk::label $parent.l$row -text $label
    ttk::frame $parent.w$row -relief groove -borderwidth 1
    set repeatableWidget($moduleId,$key) $parent.w$row
    grid $parent.l$row -row $row -column 0 -sticky ne -padx 4 -pady 4
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 4
    repeatableConfigRefreshWidget $moduleId $key
}

# Upgrade scalar type=model fields with the same standard Parameters... editor.
proc ::GX::scalarModelParametersOpen {moduleId key} {
    variable moduleCfg
    set mid [expr {[info exists moduleCfg($moduleId,$key)] ? [string trim $moduleCfg($moduleId,$key)] : ""}]
    modelResourceParameterDialog $moduleId $key $mid
}

proc ::GX::scalarModelSelectionChanged {moduleId key} {
    variable moduleCfg
    set mid [expr {[info exists moduleCfg($moduleId,$key)] ? [string trim $moduleCfg($moduleId,$key)] : ""}]
    if {$mid ne ""} { catch {modelResourceParametersEnsure $moduleId $key $mid} }
    catch {refreshManifestPreview}
}

proc ::GX::scalarModelWidgetRefresh {w moduleId key} {
    if {![winfo exists $w]} return
    $w configure -values [scalarModelValues $moduleId $key]
}

proc ::GX::validateScalarModelConfig {moduleId} {
    variable moduleCfg
    foreach key [moduleConfigKeys $moduleId] {
        if {[string tolower [moduleConfigField $moduleId $key type string]] ne "model"} continue
        set required [expr {[moduleConfigField $moduleId $key required 0] ? 1 : 0}]
        set mid [expr {[info exists moduleCfg($moduleId,$key)] ? [string trim $moduleCfg($moduleId,$key)] : ""}]
        if {$mid eq ""} {
            if {$required} { error "$moduleId: configuration '$key' requires a mathematical model." }
            continue
        }
        if {[modelField $mid descriptor ""] eq ""} { error "$moduleId: configuration '$key' references unknown mathematical model '$mid'." }
        set kinds [scalarModelKinds $moduleId $key]
        if {![modelKindAllowed $mid $kinds]} {
            error "$moduleId: configuration '$key' model '$mid' has kind '[modelField $mid kind ""]', expected one of '[join $kinds {;}]'."
        }
        modelResourceParametersValidate $moduleId $key $mid
    }
    return 1
}

proc ::GX::standardConfigWidget_before_numeric_expression_browser {parent id key row} {
    variable moduleCfg
    variable modelOrder
    set type [string tolower [moduleConfigField $id $key type string]]
    if {$type eq "table"} { return [repeatableConfigBuildWidget $parent $id $key $row] }
    if {$type eq "model"} {
        set label [moduleConfigField $id $key label $key]
        ttk::label $parent.l$row -text $label
        ttk::frame $parent.w$row
        ttk::combobox $parent.w$row.sel -textvariable ::GX::moduleCfg($id,$key) -values [scalarModelValues $id $key] -state readonly -width 32 \
            -postcommand [list ::GX::scalarModelWidgetRefresh $parent.w$row.sel $id $key]
        ttk::button $parent.w$row.params -text "Parameters..." -command [list ::GX::scalarModelParametersOpen $id $key]
        bind $parent.w$row.sel <<ComboboxSelected>> [list ::GX::scalarModelSelectionChanged $id $key]
        pack $parent.w$row.sel -side left -fill x -expand 1; pack $parent.w$row.params -side left -padx {4 0}
        grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
        grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
        if {[info exists moduleCfg($id,$key)] && [string trim $moduleCfg($id,$key)] ne ""} { catch {modelResourceParametersEnsure $id $key [string trim $moduleCfg($id,$key)]} }
        return
    }
    return [::GX::standardConfigWidget_v092_before_repeatable_config $parent $id $key $row]
}

# -----------------------------------------------------------------------------
# Manifest persistence
# -----------------------------------------------------------------------------
proc ::GX::manifestStringV2_v0933_before_plot3d {} {
    variable moduleOrder
    variable moduleCfg
    variable repeatableRows
    variable repeatableValue
    set out [::GX::manifestStringV2_v092_before_repeatable_config]
    append out "\n\[repeatable_config_api\]\n"; appendKV out version 1
    foreach id $moduleOrder {
        foreach key [repeatableConfigTableKeys $id] {
            repeatableConfigEnsure $id $key
            set rows [repeatableConfigRows $id $key]
            append out "\n\[repeatable_config.$id.$key\]\n"
            appendKV out api_version 1
            appendKV out rows [join $rows ";"]
            appendKV out columns [join [repeatableConfigColumns $id $key] ";"]
            foreach rowId $rows {
                append out "\n\[repeatable_config.$id.$key.$rowId\]\n"
                foreach c [repeatableConfigColumns $id $key] { appendKV out $c [expr {[info exists repeatableValue($id,$key,$rowId,$c)] ? $repeatableValue($id,$key,$rowId,$c) : ""}] }
            }
        }
        # Persist effective parameter/bound overrides for every selected scalar model.
        foreach key [moduleConfigKeys $id] {
            if {[string tolower [moduleConfigField $id $key type string]] ne "model"} continue
            set mid [expr {[info exists moduleCfg($id,$key)] ? [string trim $moduleCfg($id,$key)] : ""}]
            if {$mid eq "" || [modelField $mid descriptor ""] eq ""} continue
            modelResourceParametersEnsure $id $key $mid
            append out "\n\[model_parameters.$id.$key\]\n"; appendKV out model_id $mid; appendKV out names [join [modelResourceParameterNames $mid] ";"]
            foreach attr {initial lower upper} { appendKV out $attr [join [modelResourceParametersList $id $key $mid $attr] ";"] }
        }
        # And row-scoped model resources.
        foreach key [repeatableConfigTableKeys $id] {
            foreach rowId [repeatableConfigRows $id $key] {
                foreach c [repeatableConfigColumns $id $key] {
                    if {[string tolower [repeatableColumnField $id $key $c type string]] ne "model"} continue
                    set mid [expr {[info exists repeatableValue($id,$key,$rowId,$c)] ? [string trim $repeatableValue($id,$key,$rowId,$c)] : ""}]
                    if {$mid eq "" || [modelField $mid descriptor ""] eq ""} continue
                    set owner "$key.$rowId"
                    modelResourceParametersEnsure $id $owner $mid
                    append out "\n\[model_parameters.$id.$owner\]\n"; appendKV out model_id $mid; appendKV out names [join [modelResourceParameterNames $mid] ";"]
                    foreach attr {initial lower upper} { appendKV out $attr [join [modelResourceParametersList $id $owner $mid $attr] ";"] }
                }
            }
        }
    }
    return $out
}

proc ::GX::modelResourceLoadParameterSection {d moduleId owner modelId section} {
    variable modelParamValue
    if {$modelId eq "" || [modelField $modelId descriptor ""] eq ""} return
    modelResourceParametersEnsure $moduleId $owner $modelId
    set names [modelResourceParameterNames $modelId]
    foreach attr {initial lower upper} {
        set k "$section.$attr"
        if {![dict exists $d $k]} continue
        set vals [splitList [dict get $d $k]]
        for {set i 0} {$i < [llength $names]} {incr i} {
            if {$i < [llength $vals]} { set modelParamValue($moduleId,$owner,$modelId,[lindex $names $i],$attr) [lindex $vals $i] }
        }
    }
}

proc ::GX::loadManifestV2_v0933_before_plot3d {path} {
    variable moduleOrder
    variable moduleCfg
    variable repeatableRows
    variable repeatableValue
    variable repeatableNext
    variable modelParamValue
    ::GX::loadManifestV2_v092_before_repeatable_config $path
    array unset repeatableRows *
    array unset repeatableValue *
    array unset repeatableNext *
    array unset modelParamValue *
    set d [parseIni $path]
    foreach id $moduleOrder {
        foreach key [repeatableConfigTableKeys $id] {
            set sk "repeatable_config.$id.$key.rows"
            set rows [expr {[dict exists $d $sk] ? [splitList [dict get $d $sk]] : {}}]
            foreach rowId $rows {
                repeatableConfigAddRow $id $key $rowId
                foreach c [repeatableConfigColumns $id $key] {
                    set dk "repeatable_config.$id.$key.$rowId.$c"
                    if {[dict exists $d $dk]} { set repeatableValue($id,$key,$rowId,$c) [dict get $d $dk] }
                }
            }
            repeatableConfigEnsure $id $key
        }
        foreach key [moduleConfigKeys $id] {
            if {[string tolower [moduleConfigField $id $key type string]] ne "model"} continue
            set mid [expr {[info exists moduleCfg($id,$key)] ? [string trim $moduleCfg($id,$key)] : ""}]
            set sec "model_parameters.$id.$key"
            if {[dict exists $d "$sec.model_id"]} { set mid [dict get $d "$sec.model_id"] }
            if {$mid ne ""} { modelResourceLoadParameterSection $d $id $key $mid $sec }
        }
        foreach key [repeatableConfigTableKeys $id] {
            foreach rowId [repeatableConfigRows $id $key] {
                foreach c [repeatableConfigColumns $id $key] {
                    if {[string tolower [repeatableColumnField $id $key $c type string]] ne "model"} continue
                    set mid [expr {[info exists repeatableValue($id,$key,$rowId,$c)] ? [string trim $repeatableValue($id,$key,$rowId,$c)] : ""}]
                    set owner "$key.$rowId"; set sec "model_parameters.$id.$owner"
                    if {[dict exists $d "$sec.model_id"]} { set mid [dict get $d "$sec.model_id"] }
                    if {$mid ne ""} { modelResourceLoadParameterSection $d $id $owner $mid $sec }
                }
            }
        }
    }
}

# -----------------------------------------------------------------------------
# Runtime: resolved row map + named model resources.
# -----------------------------------------------------------------------------
proc ::GX::writeStandardRuntimeConfig_v0933_before_unit_selector {id} {
    variable moduleCfg
    variable repeatableValue
    validateScalarModelConfig $id
    set p [::GX::writeStandardRuntimeConfig_v092_before_repeatable_config $id]
    set tableKeys [repeatableConfigTableKeys $id]
    set scalarModels {}
    foreach key [moduleConfigKeys $id] {
        if {[string tolower [moduleConfigField $id $key type string]] eq "model"} { lappend scalarModels $key }
    }
    if {![llength $tableKeys] && ![llength $scalarModels]} { return $p }
    set fd [open $p a]; fconfigure $fd -encoding utf-8 -translation lf
    puts $fd "\n\[repeatable_config_api\]"; putKV $fd api_version 1
    set resourceIds {}

    foreach key $tableKeys {
        repeatableConfigValidate $id $key
        set rows [repeatableConfigRows $id $key]
        puts $fd "\n\[repeatable_config.$key\]"; putKV $fd api_version 1; putKV $fd rows [join $rows ";"]; putKV $fd columns [join [repeatableConfigColumns $id $key] ";"]
        foreach rowId $rows {
            puts $fd "\n\[repeatable_config.$key.$rowId\]"
            foreach c [repeatableConfigColumns $id $key] {
                set typ [string tolower [repeatableColumnField $id $key $c type string]]
                set v [expr {[info exists repeatableValue($id,$key,$rowId,$c)] ? [string trim $repeatableValue($id,$key,$rowId,$c)] : ""}]
                putKV $fd $c $v
                if {$typ eq "variable"} {
                    set source [string trim [repeatableColumnField $id $key $c source [repeatableColumnField $id $key $c source_role primary]]]
                    if {$source eq ""} { set source primary }
                    set ds [repeatableVariableDatasetId $id $key $c]
                    putKV $fd "${c}_source" $source
                    putKV $fd "${c}_dataset_id" $ds
                    putKV $fd "${c}_variable" $v
                    putKV $fd "${c}_unit" [expr {$v ne "" && $ds ne "" ? [datasetVariableUnit $ds $v] : ""}]
                } elseif {$typ eq "model" && $v ne ""} {
                    set section "model.$key.$rowId"
                    putKV $fd "${c}_resource" $section
                    lappend resourceIds "$key.$rowId"
                }
            }
        }
    }

    foreach key $scalarModels {
        set mid [expr {[info exists moduleCfg($id,$key)] ? [string trim $moduleCfg($id,$key)] : ""}]
        if {$mid eq ""} continue
        modelResourceParametersValidate $id $key $mid
        lappend resourceIds $key
    }
    puts $fd "\n\[model_resources\]"; putKV $fd api_version 1; putKV $fd ids [join $resourceIds ";"]

    foreach key $scalarModels {
        set mid [expr {[info exists moduleCfg($id,$key)] ? [string trim $moduleCfg($id,$key)] : ""}]
        if {$mid eq ""} continue
        modelResourceWriteSection $fd "model.$key" $id $key $mid
        # Backward compatibility: the historical special model_id contract keeps
        # [model], but parameter/bound edits now also reach that legacy section.
        if {$key eq "model_id"} {
            puts $fd "\n\[model\]"
            putKV $fd param_names [join [modelResourceParameterNames $mid] ";"]
            foreach attr {initial lower upper} { putKV $fd "param_$attr" [join [modelResourceParametersList $id $key $mid $attr] ";"] }
        }
    }
    foreach key $tableKeys {
        foreach rowId [repeatableConfigRows $id $key] {
            foreach c [repeatableConfigColumns $id $key] {
                if {[string tolower [repeatableColumnField $id $key $c type string]] ne "model"} continue
                set mid [expr {[info exists repeatableValue($id,$key,$rowId,$c)] ? [string trim $repeatableValue($id,$key,$rowId,$c)] : ""}]
                if {$mid eq ""} continue
                modelResourceWriteSection $fd "model.$key.$rowId" $id "$key.$rowId" $mid
            }
        }
    }
    close $fd
    return $p
}

proc ::GX::defaults_v0933_before_plot3d {} {
    variable repeatableRows
    variable repeatableValue
    variable repeatableNext
    variable repeatableWidget
    variable repeatableRefreshing
    variable modelParamValue
    ::GX::defaults_v092_before_repeatable_config
    array unset repeatableRows *
    array unset repeatableValue *
    array unset repeatableNext *
    array unset repeatableWidget *
    array unset repeatableRefreshing *
    array unset modelParamValue *
}
