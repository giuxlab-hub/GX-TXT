# GX-TXT plot.dataset public Plot Specification API v2
# SPDX-License-Identifier: GPL-3.0-or-later
#
# PLOT_DATASET_API_v2 is a high-level, declarative facade over plot.dataset.
# PLOT_DATASET_API_v1 remains stable and is intentionally not modified.
# v2 uses CORE Graph Series for series identity/bindings and stores only
# plot.dataset-owned presentation/uncertainty/annotation state in a sidecar
# PlotSpec. Consumers do not need to drive the GUI or write private files.

namespace eval ::GX::PlotDatasetAPIv2 {
    variable apiDir [file dirname [file normalize [info script]]]
    variable apiVersion 2
    variable schemaId PLOT_DATASET_PLOTSPEC_v2
    variable moduleId plot.dataset
    variable supportedKinds {auto line scatter line_marker step errorbar band bar histogram box_whisker}
    variable styleFields {color line_style line_width marker marker_size marker_fill opacity}
    variable axisFields {label display_unit scale direction min max tick_positions tick_labels major_step minor_grid}
    variable errorFields {mode variable_id lower_variable_id upper_variable_id}
    variable annotationTypes {reference_line reference_region text}
}

proc ::GX::PlotDatasetAPIv2::_error {message} {
    return -code error "plot.dataset API v2: $message"
}

proc ::GX::PlotDatasetAPIv2::_here {} { variable apiDir; return $apiDir }

proc ::GX::PlotDatasetAPIv2::_requireFramework {} {
    foreach cmd {
        ::GX::moduleField ::GX::moduleGraphIds ::GX::moduleGraphField
        ::GX::datasetField ::GX::datasetVariableById ::GX::datasetVariableSchema
        ::GX::parseIni ::GX::descriptorValue ::GX::putKV
    } {
        if {![llength [info commands $cmd]]} {_error "required GX-TXT public service is unavailable: $cmd"}
    }
    if {![llength [info commands ::GX::PlotDatasetAPIv1::apiInfo]]} {
        set v1 [file join [_here] plot_dataset_api_v1.tcl]
        if {![file isfile $v1]} {_error "PLOT_DATASET_API_v1 entrypoint is unavailable"}
        source $v1
    }
    ::GX::PlotDatasetAPIv1::apiInfo
    if {$::GX::currentSession ne "" && [file isdirectory $::GX::currentSession]} {
        catch {::GX::loadDatasetRegistry $::GX::currentSession}
    }
}

proc ::GX::PlotDatasetAPIv2::_descriptor {} {
    variable moduleId
    set path [::GX::moduleField $moduleId descriptor ""]
    if {$path eq "" || ![file isfile $path]} {_error "module descriptor is unavailable"}
    return [::GX::parseIni $path]
}

proc ::GX::PlotDatasetAPIv2::capabilities {} {
    _requireFramework
    set d [_descriptor]
    return [::GX::splitList [::GX::descriptorValue $d public_api.PLOT_DATASET_API_v2 capabilities ""]]
}
proc ::GX::PlotDatasetAPIv2::supports {capability} { expr {[lsearch -exact [capabilities] $capability] >= 0} }
proc ::GX::PlotDatasetAPIv2::requireCapability {capability} {
    if {![supports $capability]} {_error "capability '$capability' is not supported"}
    return 1
}
proc ::GX::PlotDatasetAPIv2::apiInfo {} {
    variable apiVersion; variable moduleId; variable schemaId
    _requireFramework
    return [dict create api_name PLOT_DATASET_API_v2 api_version $apiVersion plotspec_schema $schemaId \
        module_id $moduleId module_version [::GX::moduleField $moduleId version ""] capabilities [capabilities]]
}

proc ::GX::PlotDatasetAPIv2::_bool {v label} {
    set q [string tolower [string trim $v]]
    if {$q in {1 true yes on}} {return 1}
    if {$q in {0 false no off}} {return 0}
    _error "$label must be boolean"
}
proc ::GX::PlotDatasetAPIv2::_numOrAuto {v label} {
    set q [string trim $v]
    if {$q eq "" || [string equal -nocase $q auto]} {return $q}
    if {![string is double -strict $q]} {_error "$label must be numeric, blank or auto"}
    return $q
}
proc ::GX::PlotDatasetAPIv2::_dictOrEmpty {d label} {
    if {$d eq ""} {return [dict create]}
    if {[catch {dict size $d}]} {_error "$label must be a dict"}
    return $d
}
proc ::GX::PlotDatasetAPIv2::_validId {id label} {
    if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $id]} {_error "invalid $label '$id'"}
    return $id
}

proc ::GX::PlotDatasetAPIv2::newSpec {args} {
    variable schemaId
    # auto preserves pre-3.2 consumers: more than one panel implies multi-panel
    # unless the caller explicitly sets the new toggle.
    array set o {-graph_id plot.dataset.xy -title auto -panel_id main -multi_panel auto}
    if {[llength $args] % 2} {_error "newSpec expects option/value pairs"}
    foreach {k v} $args {
        if {![info exists o($k)]} {_error "unknown newSpec option '$k'"}
        set o($k) $v
    }
    set panel [dict create id $o(-panel_id) axes [dict create] series {} annotations {}]
    set spec [dict create schema $schemaId graph_type cartesian_2d graph_id $o(-graph_id) title $o(-title)         defaults [dict create style [dict create]] panels [list $panel] output [dict create]]
    if {![string equal -nocase [string trim $o(-multi_panel)] auto]} {
        dict set spec multi_panel [_bool $o(-multi_panel) multi_panel]
    }
    return $spec
}

# One shared PlotSpec X definition serves the module editor and CORE Plot tab.
proc ::GX::PlotDatasetAPIv2::sharedXAxisGet {plotRef} {
    set spec [loadSpec $plotRef 1]
    if {[dict get $spec graph_id] eq "plot.dataset.xyz"} {_error "shared X grid applies to 2D plots"}
    set result [dict create scale linear major_step "" minor_grid off]
    foreach panel [dict get $spec panels] {
        foreach field {scale major_step minor_grid} {
            if {[dict exists $panel axes x $field] && [string trim [dict get $panel axes x $field]] ne ""} {
                dict set result $field [string tolower [dict get $panel axes x $field]]
            }
        }
    }
    return $result
}

proc ::GX::PlotDatasetAPIv2::sharedXAxisSet {plotRef fields} {
    if {[catch {dict size $fields}]} {_error "shared X fields must be a dict"}
    dict for {field value} $fields {
        if {$field ni {scale major_step minor_grid}} {_error "unknown shared X field '$field'"}
        if {$field eq "scale" && [string tolower $value] ni {linear log}} {_error "X scale must be linear or log"}
        if {$field eq "minor_grid" && [string tolower $value] ni {off auto}} {_error "X minor grid must be off or auto"}
        if {$field eq "major_step" && $value ne "" &&
            (![string is double -strict $value] || $value <= 0)} {_error "X major step must be positive or blank"}
    }
    set spec [loadSpec $plotRef 1]
    if {[dict get $spec graph_id] eq "plot.dataset.xyz"} {_error "shared X grid applies to 2D plots"}
    set panels {}
    foreach panel [dict get $spec panels] {
        dict for {field value} $fields {
            if {$field eq "major_step" && $value eq ""} {catch {dict unset panel axes x $field}} \
            else {dict set panel axes x $field [expr {$field eq "major_step" ? $value : [string tolower $value]}]}
        }
        lappend panels $panel
    }
    dict set spec panels $panels
    saveSpec $plotRef $spec
    # A legacy CORE X override can shadow PlotSpec during the final PNG
    # pass. A public shared-X write takes ownership of these fields too.
    if {[llength [info commands ::GX::plotVariantKey]] && [info exists ::GX::axisOverride]} {
        set key [::GX::plotVariantKey [dict get $plotRef graph_id] [dict get $plotRef variant_id]]
        foreach field {x_scale x_step} {set ::GX::axisOverride($key,$field) ""}
    }
    return [sharedXAxisGet $plotRef]
}

proc ::GX::PlotDatasetAPIv2::_normalizeStyle {style} {
    variable styleFields
    set style [_dictOrEmpty $style style]
    set out [dict create]
    foreach f $styleFields {if {[dict exists $style $f]} {dict set out $f [dict get $style $f]}}
    dict for {k v} $style {if {$k ni $styleFields} {_error "unknown style field '$k'"}}
    return $out
}
proc ::GX::PlotDatasetAPIv2::_validateStyle {style where} {
    set style [_normalizeStyle $style]
    if {[dict exists $style color]} {
        set v [string trim [dict get $style color]]
        if {$v ne "" && ![string equal -nocase $v auto] && ![regexp {^#[0-9A-Fa-f]{6}$} $v]} {_error "$where style.color must be auto or #RRGGBB"}
    }
    if {[dict exists $style line_style]} {
        set v [string tolower [string trim [dict get $style line_style]]]
        if {$v ni {auto inherit solid dashed dotted dashdot none}} {_error "$where style.line_style is invalid"}
    }
    if {[dict exists $style line_width]} {
        set v [string trim [dict get $style line_width]]
        if {$v ni {auto inherit ""} && (![string is double -strict $v] || $v <= 0)} {_error "$where style.line_width must be positive, auto or inherit"}
    }
    if {[dict exists $style marker]} {
        set v [string tolower [string trim [dict get $style marker]]]
        if {$v ni {auto inherit none circle square diamond triangle_up triangle_down plus x star}} {_error "$where style.marker is invalid"}
    }
    if {[dict exists $style marker_size]} {
        set v [string trim [dict get $style marker_size]]
        if {$v ni {auto inherit ""} && (![string is double -strict $v] || $v <= 0)} {_error "$where style.marker_size must be positive, auto or inherit"}
    }
    if {[dict exists $style marker_fill]} {
        set v [string tolower [string trim [dict get $style marker_fill]]]
        if {$v ni {auto inherit none full}} {_error "$where style.marker_fill is invalid"}
    }
    if {[dict exists $style opacity]} {
        set v [string trim [dict get $style opacity]]
        if {$v ni {auto inherit ""} && (![string is double -strict $v] || $v < 0 || $v > 1)} {_error "$where style.opacity must be between 0 and 1, auto or inherit"}
    }
    return $style
}

proc ::GX::PlotDatasetAPIv2::_validateAxis {axis where} {
    variable axisFields
    set axis [_dictOrEmpty $axis $where]
    dict for {k v} $axis {if {$k ni $axisFields} {_error "unknown $where field '$k'"}}
    if {[dict exists $axis scale]} {
        set v [string tolower [string trim [dict get $axis scale]]]
        if {$v ni {auto linear log}} {_error "$where scale must be auto, linear or log"}
    }
    if {[dict exists $axis direction]} {
        set v [string tolower [string trim [dict get $axis direction]]]
        if {$v ni {auto normal reverse}} {_error "$where direction must be auto, normal or reverse"}
    }
    foreach f {major_step minor_grid} {
        if {[dict exists $axis $f] && ![string match "*axis x" $where]} {
            _error "$where $f is supported only for X"
        }
    }
    if {[dict exists $axis major_step]} {
        set v [string trim [dict get $axis major_step]]
        if {$v ne "" && (![string is double -strict $v] || $v <= 0)} {
            _error "$where major_step must be positive or blank"
        }
    }
    if {[dict exists $axis minor_grid] && [string tolower [string trim [dict get $axis minor_grid]]] ni {off auto}} {
        _error "$where minor_grid must be off or auto"
    }
    foreach f {min max} {if {[dict exists $axis $f]} {_numOrAuto [dict get $axis $f] "$where $f"}}
    if {[dict exists $axis min] && [dict exists $axis max]} {
        set a [string trim [dict get $axis min]]; set b [string trim [dict get $axis max]]
        if {[string is double -strict $a] && [string is double -strict $b] && $a >= $b} {_error "$where min must be less than max"}
    }
    if {[dict exists $axis tick_positions] != [dict exists $axis tick_labels]} {
        _error "$where tick_positions and tick_labels must be supplied together"
    }
    if {[dict exists $axis tick_positions]} {
        if {![string match "*axis x" $where]} {_error "$where custom ticks are supported only for X"}
        set positions [split [dict get $axis tick_positions] {;}]
        set labels [split [dict get $axis tick_labels] {;}]
        if {[llength $positions] != [llength $labels] || [llength $positions] < 1} {_error "$where tick positions/labels count mismatch"}
        foreach p $positions l $labels {
            set p [string trim $p]
            if {![string is double -strict $p] || [expr {abs(double($p)) > 1e300}]} {_error "$where tick positions must be finite numbers"}
            if {[string trim $l] eq "" || [regexp {[\r\n]} $l]} {_error "$where tick labels must be nonempty single-line text"}
        }
    }
    return $axis
}

proc ::GX::PlotDatasetAPIv2::_validateError {e where datasetId} {
    variable errorFields
    set e [_dictOrEmpty $e $where]
    dict for {k v} $e {if {$k ni $errorFields} {_error "unknown $where field '$k'"}}
    set mode [expr {[dict exists $e mode] ? [string tolower [string trim [dict get $e mode]]] : "none"}]
    if {$mode ni {none symmetric asymmetric}} {_error "$where mode must be none, symmetric or asymmetric"}
    if {$mode eq "symmetric"} {
        if {![dict exists $e variable_id] || [string trim [dict get $e variable_id]] eq ""} {_error "$where symmetric mode requires variable_id"}
        _validateAuxVariable $datasetId [dict get $e variable_id] "$where variable_id"
    } elseif {$mode eq "asymmetric"} {
        foreach f {lower_variable_id upper_variable_id} {
            if {![dict exists $e $f] || [string trim [dict get $e $f]] eq ""} {_error "$where asymmetric mode requires $f"}
            _validateAuxVariable $datasetId [dict get $e $f] "$where $f"
        }
    }
    return $e
}

proc ::GX::PlotDatasetAPIv2::_validateAuxVariable {datasetId variableId label} {
    if {[catch {set v [::GX::datasetVariableById $datasetId [string trim $variableId]]} err]} {_error "$label is invalid: $err"}
    if {![dict get $v enabled]} {_error "$label references a Use=no variable"}
    return $v
}

proc ::GX::PlotDatasetAPIv2::_validateSeries {s index} {
    variable supportedKinds
    if {[catch {dict size $s}]} {_error "panel series #$index must be a dict"}
    foreach f {id dataset_id x_variable_id y_variable_id axis} {
        if {![dict exists $s $f] || [string trim [dict get $s $f]] eq ""} {_error "panel series #$index requires '$f'"}
    }
    _validId [dict get $s id] "series ID"
    set ds [string trim [dict get $s dataset_id]]
    if {[::GX::datasetField $ds id ""] eq ""} {_error "series '[dict get $s id]' references unknown dataset '$ds'"}
    foreach f {x_variable_id y_variable_id} {_validateAuxVariable $ds [dict get $s $f] "series '[dict get $s id]' $f"}
    if {[dict exists $s family_variable_id] && [string trim [dict get $s family_variable_id]] ne ""} {
        _validateAuxVariable $ds [dict get $s family_variable_id] "series '[dict get $s id]' family_variable_id"
    }
    foreach field {secondary_variable_id ordering_variable_id} {
        if {![dict exists $s $field] || [string trim [dict get $s $field]] eq ""} continue
        set variable [_validateAuxVariable $ds [dict get $s $field] "series '[dict get $s id]' $field"]
        if {$field eq "ordering_variable_id"} {
            set schema [::GX::datasetVariableV3ById $ds [dict get $variable variable_id]]
            if {[dict get $schema dtype] eq "string"} {_error "series '[dict get $s id]' ordering_variable_id must be numeric"}
        }
    }
    if {[dict exists $s row_filters]} {
        if {[catch {::GX::graphSeriesNormalizeFilters $ds [dict get $s row_filters]} err]} {_error "series '[dict get $s id]' row_filters: $err"}
    }
    if {[dict exists $s source_row_ordinals]} {::GX::graphSeriesNormalizeRowOrdinals [dict get $s source_row_ordinals]}
    if {[dict exists $s source_row_continuity]} {_bool [dict get $s source_row_continuity] source_row_continuity}
    if {[dict exists $s family_label_prefix] && [regexp {[\r\n]} [dict get $s family_label_prefix]]} {_error "series '[dict get $s id]' family_label_prefix must be single-line"}
    set axis [string tolower [string trim [dict get $s axis]]]
    if {$axis ni {left right}} {_error "series '[dict get $s id]' axis must be left or right"}
    set kind [expr {[dict exists $s kind] ? [string tolower [string trim [dict get $s kind]]] : "auto"}]
    if {$kind ni $supportedKinds} {_error "series '[dict get $s id]' kind '$kind' is not supported by API v2"}
    if {[dict exists $s family_variable_id] && [string trim [dict get $s family_variable_id]] ne ""} {
        if {$kind ni {auto line scatter line_marker step}} {_error "series '[dict get $s id]' family grouping supports only line, scatter, line_marker or step"}
        foreach incompatible {x_error y_error band bar_bounds bar_width bar_baseline histogram_bins histogram_normalization box_whisker_iqr box_show_outliers} {
            if {[dict exists $s $incompatible]} {_error "series '[dict get $s id]' family grouping does not accept $incompatible"}
        }
    }
    if {[dict exists $s enabled]} {_bool [dict get $s enabled] "series '[dict get $s id]' enabled"}
    if {[dict exists $s order] && (![string is integer -strict [dict get $s order]] || [dict get $s order] < 0)} {_error "series '[dict get $s id]' order must be a nonnegative integer"}
    if {[dict exists $s style]} {_validateStyle [dict get $s style] "series '[dict get $s id]'"}
    if {[dict exists $s step_mode]} {
        set m [string tolower [string trim [dict get $s step_mode]]]
        if {$m ni {pre post mid}} {_error "series '[dict get $s id]' step_mode must be pre, post or mid"}
    }
    foreach e {x_error y_error} {if {[dict exists $s $e]} {_validateError [dict get $s $e] "series '[dict get $s id]' $e" $ds}}
    if {[dict exists $s band]} {
        set b [_dictOrEmpty [dict get $s band] "series '[dict get $s id]' band"]
        foreach f {lower_variable_id upper_variable_id} {
            if {![dict exists $b $f] || [string trim [dict get $b $f]] eq ""} {_error "series '[dict get $s id]' band requires $f"}
            _validateAuxVariable $ds [dict get $b $f] "series '[dict get $s id]' band $f"
        }
        dict for {k v} $b {if {$k ni {lower_variable_id upper_variable_id draw_center}} {_error "unknown band field '$k'"}}
        if {[dict exists $b draw_center]} {_bool [dict get $b draw_center] "band draw_center"}
    } elseif {$kind eq "band"} {
        _error "series '[dict get $s id]' kind=band requires a band dict"
    }
    if {[dict exists $s bar_bounds]} {
        set b [_dictOrEmpty [dict get $s bar_bounds] "series '[dict get $s id]' bar_bounds"]
        foreach f {lower_variable_id upper_variable_id} {
            if {![dict exists $b $f] || [string trim [dict get $b $f]] eq ""} {_error "series '[dict get $s id]' bar_bounds requires $f"}
            _validateAuxVariable $ds [dict get $b $f] "series '[dict get $s id]' bar_bounds $f"
        }
        dict for {k v} $b {if {$k ni {lower_variable_id upper_variable_id}} {_error "unknown bar_bounds field '$k'"}}
    }
    if {[dict exists $s bar_width]} {
        set w [string trim [dict get $s bar_width]]
        if {$w ne "" && ![string equal -nocase $w auto] && (![string is double -strict $w] || $w <= 0)} {_error "series '[dict get $s id]' bar_width must be positive or auto"}
    }
    if {[dict exists $s bar_baseline]} {
        set b [string trim [dict get $s bar_baseline]]
        if {$b ne "" && ![string equal -nocase $b auto] && ![string is double -strict $b]} {_error "series '[dict get $s id]' bar_baseline must be numeric or auto"}
    }
    if {[dict exists $s histogram_bins]} {
        set bins [string tolower [string trim [dict get $s histogram_bins]]]
        if {$bins ne "auto" && (![string is integer -strict $bins] || $bins < 2 || $bins > 512)} {
            _error "series '[dict get $s id]' histogram_bins must be auto or an integer from 2 to 512"
        }
    }
    if {[dict exists $s histogram_normalization]} {
        set normalization [string tolower [string trim [dict get $s histogram_normalization]]]
        if {$normalization ni {count probability density}} {
            _error "series '[dict get $s id]' histogram_normalization must be count, probability or density"
        }
    }
    if {[dict exists $s box_whisker_iqr]} {
        set multiplier [string trim [dict get $s box_whisker_iqr]]
        if {![string is double -strict $multiplier] || $multiplier <= 0} {
            _error "series '[dict get $s id]' box_whisker_iqr must be positive"
        }
    }
    if {[dict exists $s box_show_outliers]} {
        _bool [dict get $s box_show_outliers] "series '[dict get $s id]' box_show_outliers"
    }
    if {$kind in {histogram box_whisker}} {
        foreach incompatible {x_error y_error band bar_bounds step_mode bar_width bar_baseline family_variable_id family_label_prefix} {
            if {[dict exists $s $incompatible]} {
                _error "series '[dict get $s id]' kind=$kind does not accept $incompatible"
            }
        }
        if {$kind eq "histogram" && ([dict exists $s box_whisker_iqr] || [dict exists $s box_show_outliers])} {
            _error "series '[dict get $s id]' histogram does not accept box/whisker options"
        }
        if {$kind eq "box_whisker" && ([dict exists $s histogram_bins] || [dict exists $s histogram_normalization])} {
            _error "series '[dict get $s id]' box_whisker does not accept histogram options"
        }
    }
    if {$kind eq "errorbar"} {
        set hasError 0
        foreach ek {x_error y_error} {
            if {[dict exists $s $ek]} {
                set em [expr {[dict exists $s $ek mode] ? [string tolower [string trim [dict get $s $ek mode]]] : "none"}]
                if {$em ne "none"} {set hasError 1}
            }
        }
        if {!$hasError} {_error "series '[dict get $s id]' kind=errorbar requires x_error and/or y_error"}
    }
    return 1
}

proc ::GX::PlotDatasetAPIv2::_validateAnnotation {a index} {
    variable annotationTypes
    if {[catch {dict size $a}]} {_error "annotation #$index must be a dict"}
    if {![dict exists $a type]} {_error "annotation #$index requires type"}
    set t [string tolower [string trim [dict get $a type]]]
    if {$t ni $annotationTypes} {_error "annotation #$index type '$t' is unsupported"}
    set axis [expr {[dict exists $a axis] ? [string tolower [string trim [dict get $a axis]]] : "x"}]
    if {$axis ni {x left right}} {_error "annotation #$index axis must be x, left or right"}
    if {$t eq "reference_line"} {
        if {![dict exists $a value] || ![string is double -strict [dict get $a value]]} {_error "reference_line annotation requires numeric value"}
    } elseif {$t eq "reference_region"} {
        foreach f {min max} {if {![dict exists $a $f] || ![string is double -strict [dict get $a $f]]} {_error "reference_region annotation requires numeric $f"}}
        if {[dict get $a min] >= [dict get $a max]} {_error "reference_region min must be less than max"}
    } else {
        foreach f {x y} {if {![dict exists $a $f] || ![string is double -strict [dict get $a $f]]} {_error "text annotation requires numeric $f"}}
        if {![dict exists $a label] || [string trim [dict get $a label]] eq "" || [regexp {[\r\n]} [dict get $a label]]} {_error "text annotation requires a nonempty single-line label"}
    }
    if {[dict exists $a color]} {_validateStyle [dict create color [dict get $a color]] "annotation #$index"}
    if {[dict exists $a line_style]} {_validateStyle [dict create line_style [dict get $a line_style]] "annotation #$index"}
    if {[dict exists $a line_width]} {_validateStyle [dict create line_width [dict get $a line_width]] "annotation #$index"}
    return 1
}


proc ::GX::PlotDatasetAPIv2::_sharedXAxisCheck {panels} {
    set shared [dict create]
    foreach p $panels {
        if {![dict exists $p axes x]} continue
        set ax [dict get $p axes x]
        foreach f {display_unit scale min max tick_positions tick_labels major_step minor_grid} {
            if {![dict exists $ax $f]} continue
            set v [string trim [dict get $ax $f]]
            if {$v eq "" || [string equal -nocase $v auto]} continue
            if {[dict exists $shared $f] && [dict get $shared $f] ne $v} {
                _error "shared-X panels have conflicting axis.x $f values ('[dict get $shared $f]' vs '$v')"
            }
            dict set shared $f $v
        }
    }
    return $shared
}

proc ::GX::PlotDatasetAPIv2::_validateGridSpec {spec} {
    if {![dict exists $spec graph_id] || [dict get $spec graph_id] ne "plot.dataset.xyz"} {
        _error "cartesian_3d requires graph_id plot.dataset.xyz"
    }
    foreach key {dataset_id x_variable_id y_variable_id z_variable_id} {
        if {![dict exists $spec $key] || [string trim [dict get $spec $key]] eq ""} {_error "cartesian_3d requires $key"}
    }
    set dataset [dict get $spec dataset_id]
    foreach key {x_variable_id y_variable_id z_variable_id family_variable_id color_variable_id} {
        if {![dict exists $spec $key] || [string trim [dict get $spec $key]] eq ""} continue
        if {[catch {::GX::datasetVariableById $dataset [dict get $spec $key]} err]} {_error "invalid $key: $err"}
    }
    if {[dict exists $spec config]} {
        set config [_dictOrEmpty [dict get $spec config] config]
        set allowed [::GX::moduleGraphConfigKeys plot.dataset plot.dataset.xyz]
        dict for {key value} $config {
            if {$key ni $allowed} {_error "unknown 3D graph config '$key'"}
            if {[regexp {[\r\n]} $value]} {_error "3D graph config must be single-line"}
        }
        if {[dict exists $config plot_type] && [dict get $config plot_type] ni {line3 scatter3 surface mesh contour3 trisurf heatmap}} {
            _error "unsupported 3D plot_type"
        }
    }
    if {[dict exists $spec title] && [regexp {[\r\n]} [dict get $spec title]]} {_error "3D title must be single-line"}
    return $spec
}

proc ::GX::PlotDatasetAPIv2::_applyGridSpec {ref spec} {
    if {[dict get $ref graph_id] ne "plot.dataset.xyz" || [dict get $ref variant_id] eq ""} {
        _error "cartesian_3d requires a persistent plot.dataset.xyz variant"
    }
    set variant [dict get $ref variant_id]
    set dataset [dict get $spec dataset_id]
    foreach {role key} {x x_variable_id y y_variable_id z z_variable_id family family_variable_id color color_variable_id} {
        set variable [expr {[dict exists $spec $key] ? [string trim [dict get $spec $key]] : ""}]
        if {$variable eq ""} {::GX::plotVariantBindingSet plot.dataset plot.dataset.xyz $variant $role "" ""} else {
            ::GX::plotVariantBindingSet plot.dataset plot.dataset.xyz $variant $role $dataset $variable
        }
    }
    if {[dict exists $spec title]} {::GX::plotVariantConfigSet plot.dataset plot.dataset.xyz $variant title [dict get $spec title]}
    if {[dict exists $spec config]} {
        dict for {key value} [dict get $spec config] {
            ::GX::plotVariantConfigSet plot.dataset plot.dataset.xyz $variant $key $value
        }
    }
    return [::GX::PlotDatasetAPIv1::readPlot $ref]
}

proc ::GX::PlotDatasetAPIv2::validateSpec {spec} {
    variable schemaId
    _requireFramework
    if {[catch {dict size $spec}]} {_error "PlotSpec must be a dict"}
    set schema [expr {[dict exists $spec schema] ? [dict get $spec schema] : $schemaId}]
    if {$schema ne $schemaId} {_error "unsupported PlotSpec schema '$schema'"}
    set gt [expr {[dict exists $spec graph_type] ? [string tolower [string trim [dict get $spec graph_type]]] : "cartesian_2d"}]
    if {$gt eq "cartesian_3d"} {
        _validateGridSpec $spec
        return 1
    }
    if {$gt ne "cartesian_2d"} {_error "graph_type '$gt' is not supported"}
    set gid [expr {[dict exists $spec graph_id] ? [dict get $spec graph_id] : "plot.dataset.xy"}]
    if {$gid ni {plot.dataset.xy plot.dataset.xy_region}} {_error "API v2 supports only plot.dataset.xy and plot.dataset.xy_region"}
    if {[dict exists $spec multi_panel]} {_bool [dict get $spec multi_panel] multi_panel}
    if {![dict exists $spec panels]} {_error "PlotSpec requires panels"}
    set panels [dict get $spec panels]
    if {![llength $panels]} {_error "PlotSpec requires at least one panel"}
    if {$gid eq "plot.dataset.xy_region" && ([llength $panels] != 1 || ([dict exists $spec multi_panel] && [_bool [dict get $spec multi_panel] multi_panel]))} {
        _error "plot.dataset.xy_region remains single-panel because rectangle selection has one Y domain"
    }

    if {[dict exists $spec defaults]} {
        set defs [_dictOrEmpty [dict get $spec defaults] defaults]
        dict for {k v} $defs {if {$k ne "style"} {_error "unknown defaults field '$k'"}}
        if {[dict exists $defs style]} {_validateStyle [dict get $defs style] defaults}
    }
    if {[dict exists $spec output]} {
        set out [_dictOrEmpty [dict get $spec output] output]
        dict for {k v} $out {
            if {$k ne "extra_format"} {_error "unknown output field '$k'"}
            if {[string tolower [string trim $v]] ni {none svg pdf}} {_error "output.extra_format must be none, svg or pdf"}
        }
    }

    set seenPanels {}
    set seenSeries {}
    set totalSeries 0
    set distributionKind ""
    set ordinarySeries 0
    set pi 0
    foreach p $panels {
        incr pi
        if {[catch {dict size $p}]} {_error "panel #$pi must be a dict"}
        if {![dict exists $p id] || [string trim [dict get $p id]] eq ""} {_error "panel #$pi requires id"}
        set pid [_validId [dict get $p id] "panel ID"]
        if {[lsearch -exact $seenPanels $pid] >= 0} {_error "duplicate panel ID '$pid'"}
        lappend seenPanels $pid
        if {[dict exists $p title] && [regexp {[\r\n]} [dict get $p title]]} {_error "panel '$pid' title must be single-line"}
        if {[dict exists $p axes]} {
            set axes [_dictOrEmpty [dict get $p axes] "panel '$pid' axes"]
            dict for {k v} $axes {
                if {$k ni {x y_left y_right}} {_error "unknown panel '$pid' axis '$k'"}
                _validateAxis $v "panel '$pid' axis $k"
            }
        }
        set series [expr {[dict exists $p series] ? [dict get $p series] : {}}]
        set si 0
        foreach s $series {
            incr si; incr totalSeries
            _validateSeries $s $si
            set sid [dict get $s id]
            if {[lsearch -exact $seenSeries $sid] >= 0} {_error "series ID '$sid' appears in more than one panel"}
            lappend seenSeries $sid
            set seriesKind [expr {[dict exists $s kind] ? [string tolower [string trim [dict get $s kind]]] : "auto"}]
            if {$seriesKind in {histogram box_whisker}} {
                if {$distributionKind ne "" && $distributionKind ne $seriesKind} {_error "histogram and box_whisker series may not be mixed in one plot"}
                set distributionKind $seriesKind
                if {[string tolower [dict get $s axis]] ne "left"} {_error "$seriesKind series must use the left axis"}
            } else {
                set ordinarySeries 1
            }
        }
        set ai 0
        foreach a [expr {[dict exists $p annotations] ? [dict get $p annotations] : {}}] {
            incr ai; _validateAnnotation $a $ai
        }
    }
    if {$totalSeries == 0} {_error "PlotSpec requires at least one series across its panels"}
    if {$distributionKind ne ""} {
        if {$ordinarySeries} {_error "$distributionKind series may not be mixed with Cartesian trace kinds"}
        if {$gid ne "plot.dataset.xy"} {_error "$distributionKind is supported only by plot.dataset.xy"}
        set multiPanel [expr {[dict exists $spec multi_panel] ? [_bool [dict get $spec multi_panel] multi_panel] : [llength $panels] > 1}]
        if {[llength $panels] != 1 || $multiPanel} {_error "$distributionKind requires one single panel"}
    }
    _sharedXAxisCheck $panels
    return 1
}
proc ::GX::PlotDatasetAPIv2::_plotRef {graphId variantId} { return [::GX::PlotDatasetAPIv1::openPlot $graphId $variantId] }
proc ::GX::PlotDatasetAPIv2::_normalizePlotRef {plotRef} {
    if {[catch {dict size $plotRef}]} {_error "plot reference must be a dict"}
    foreach k {graph_id variant_id} {if {![dict exists $plotRef $k]} {_error "plot reference is missing '$k'"}}
    return [_plotRef [dict get $plotRef graph_id] [dict get $plotRef variant_id]]
}

proc ::GX::PlotDatasetAPIv2::_specPath {plotRef} {
    set ref [_normalizePlotRef $plotRef]
    if {$::GX::currentSession eq "" || ![file isdirectory $::GX::currentSession]} {_error "no open GX-TXT session"}
    set gid [string map {. _ / _ \\ _} [dict get $ref graph_id]]
    set vid [dict get $ref variant_id]; if {$vid eq ""} {set vid base}
    set dir [file join $::GX::currentSession metadata plot.dataset plotspec_v2]
    return [file join $dir "${gid}--${vid}.ini"]
}

proc ::GX::PlotDatasetAPIv2::_writeOpt {fd key dictValue field} {
    if {[dict exists $dictValue $field]} {
        ::GX::putKV $fd "${key}.${field}.present" 1
        ::GX::putKV $fd "${key}.${field}.value" [dict get $dictValue $field]
    }
}
proc ::GX::PlotDatasetAPIv2::_readOpt {d section prefix field outVar} {
    upvar 1 $outVar out
    if {[::GX::descriptorValue $d $section "${prefix}.${field}.present" 0]} {
        dict set out $field [::GX::descriptorValue $d $section "${prefix}.${field}.value" ""]
    }
}


proc ::GX::PlotDatasetAPIv2::saveSpec {plotRef spec} {
    variable schemaId; variable styleFields; variable axisFields; variable errorFields
    _requireFramework; validateSpec $spec
    set ref [_normalizePlotRef $plotRef]
    if {[dict get $spec graph_id] ne [dict get $ref graph_id]} {_error "PlotSpec graph_id does not match plot reference"}
    set path [_specPath $ref]; file mkdir [file dirname $path]
    set tmp "${path}.tmp.[pid].[clock clicks]"
    set fd [open $tmp w]; fconfigure $fd -encoding utf-8 -translation lf
    set code [catch {
        puts $fd "; plot.dataset PlotSpec v2 — public persistent presentation state"
        puts $fd "\[plotspec\]"
        ::GX::putKV $fd schema $schemaId
        ::GX::putKV $fd api_version 2
        ::GX::putKV $fd graph_type [dict get $spec graph_type]
        ::GX::putKV $fd graph_id [dict get $ref graph_id]
        ::GX::putKV $fd variant_id [dict get $ref variant_id]
        set panels [dict get $spec panels]
        ::GX::putKV $fd panel_count [llength $panels]
        if {[dict exists $spec multi_panel]} {::GX::putKV $fd multi_panel_present 1; ::GX::putKV $fd multi_panel [_bool [dict get $spec multi_panel] multi_panel]} else {::GX::putKV $fd multi_panel_present 0}
        if {[dict exists $spec title]} {::GX::putKV $fd title_present 1; ::GX::putKV $fd title [dict get $spec title]} else {::GX::putKV $fd title_present 0}
        set output [expr {[dict exists $spec output] ? [dict get $spec output] : [dict create]}]
        ::GX::putKV $fd output_extra_format [expr {[dict exists $output extra_format] ? [string tolower [string trim [dict get $output extra_format]]] : "none"}]
        set ds [expr {[dict exists $spec defaults style] ? [dict get $spec defaults style] : [dict create]}]
        foreach f $styleFields {_writeOpt $fd default_style $ds $f}

        set pi 0
        foreach p $panels {
            incr pi
            set psec "panel.$pi"
            puts $fd "\n\[$psec\]"
            ::GX::putKV $fd id [dict get $p id]
            if {[dict exists $p title]} {::GX::putKV $fd title_present 1; ::GX::putKV $fd title [dict get $p title]} else {::GX::putKV $fd title_present 0}
            set axes [expr {[dict exists $p axes] ? [dict get $p axes] : [dict create]}]
            foreach a {x y_left y_right} {
                set ad [expr {[dict exists $axes $a] ? [dict get $axes $a] : [dict create]}]
                foreach f $axisFields {_writeOpt $fd "axis.$a" $ad $f}
            }
            set series [expr {[dict exists $p series] ? [dict get $p series] : {}}]
            ::GX::putKV $fd series_count [llength $series]
            set i 0
            foreach s $series {
                incr i; set sec "$psec.series.$i"; puts $fd "\n\[$sec\]"
                foreach f {id dataset_id x_variable_id y_variable_id family_variable_id secondary_variable_id ordering_variable_id family_label_prefix source_row_ordinals source_row_continuity axis label enabled kind order step_mode bar_width bar_baseline histogram_bins histogram_normalization box_whisker_iqr box_show_outliers} {
                    if {[dict exists $s $f]} {::GX::putKV $fd $f [dict get $s $f]}
                }
                set st [expr {[dict exists $s style] ? [dict get $s style] : [dict create]}]
                foreach f $styleFields {_writeOpt $fd style $st $f}
                foreach ek {x_error y_error} {
                    set ed [expr {[dict exists $s $ek] ? [dict get $s $ek] : [dict create]}]
                    foreach f $errorFields {_writeOpt $fd $ek $ed $f}
                }
                if {[dict exists $s band]} {
                    set b [dict get $s band]
                    foreach f {lower_variable_id upper_variable_id draw_center} {_writeOpt $fd band $b $f}
                }
                if {[dict exists $s bar_bounds]} {
                    set b [dict get $s bar_bounds]
                    foreach f {lower_variable_id upper_variable_id} {_writeOpt $fd bar_bounds $b $f}
                }
            }
            set annotations [expr {[dict exists $p annotations] ? [dict get $p annotations] : {}}]
            # Series are separate INI sections. Return to the owning panel so
            # annotation_count is read from panel.N rather than the last series.
            puts $fd "\n\[$psec\]"
            ::GX::putKV $fd annotation_count [llength $annotations]
            set i 0
            foreach a $annotations {
                incr i; set sec "$psec.annotation.$i"; puts $fd "\n\[$sec\]"
                foreach f {type axis value min max x y label color line_style line_width opacity} {
                    if {[dict exists $a $f]} {::GX::putKV $fd $f [dict get $a $f]}
                }
            }
        }
    } err opts]
    close $fd
    if {$code} {catch {file delete -force $tmp}; return -options $opts $err}
    file rename -force -- $tmp $path
    return [file normalize $path]
}


proc ::GX::PlotDatasetAPIv2::_seriesScientificStale {s} {
    foreach f {dataset_id x_variable_id y_variable_id} {
        if {![dict exists $s $f] || [string trim [dict get $s $f]] eq ""} {return 1}
    }
    set ds [string trim [dict get $s dataset_id]]
    if {[::GX::datasetField $ds id ""] eq ""} {return 1}
    foreach f {x_variable_id y_variable_id} {
        if {[catch {::GX::datasetVariableById $ds [dict get $s $f]}]} {return 1}
    }
    return 0
}

proc ::GX::PlotDatasetAPIv2::_seriesAuxSanitize {s} {
    set ds [dict get $s dataset_id]
    foreach ek {x_error y_error} {
        if {![dict exists $s $ek]} continue
        set e [dict get $s $ek]
        set mode [expr {[dict exists $e mode] ? [string tolower [string trim [dict get $e mode]]] : "none"}]
        set ok 1
        if {$mode eq "symmetric"} {
            if {![dict exists $e variable_id] || [catch {::GX::datasetVariableById $ds [dict get $e variable_id]}]} {set ok 0}
        } elseif {$mode eq "asymmetric"} {
            foreach f {lower_variable_id upper_variable_id} {
                if {![dict exists $e $f] || [catch {::GX::datasetVariableById $ds [dict get $e $f]}]} {set ok 0; break}
            }
        }
        if {!$ok} {dict unset s $ek}
    }
    if {[dict exists $s band]} {
        set b [dict get $s band]; set ok 1
        foreach f {lower_variable_id upper_variable_id} {
            if {![dict exists $b $f] || [catch {::GX::datasetVariableById $ds [dict get $b $f]}]} {set ok 0; break}
        }
        if {!$ok} {
            dict unset s band
            if {[dict exists $s kind] && [string equal -nocase [dict get $s kind] band]} {dict set s kind auto}
        }
    }
    return $s
}

proc ::GX::PlotDatasetAPIv2::_removeDeadPlotArtifacts {ref} {
    if {[catch {set a [::GX::PlotDatasetAPIv1::artifacts $ref]}]} {return}
    foreach key {graph_artifact render_cache summary} {
        if {[dict exists $a $key]} {catch {file delete -force -- [dict get $a $key]}}
    }
}

proc ::GX::PlotDatasetAPIv2::_seriesEquivalent {a b} {
    set aKeys [lsort [dict keys $a]]
    set bKeys [lsort [dict keys $b]]
    if {$aKeys ne $bKeys} {return 0}
    foreach key $aKeys {
        set av [dict get $a $key]
        set bv [dict get $b $key]
        if {$key in {style x_error y_error band}} {
            if {[lsort [dict keys $av]] ne [lsort [dict keys $bv]]} {return 0}
            foreach subkey [dict keys $av] {
                if {[dict get $av $subkey] ne [dict get $bv $subkey]} {return 0}
            }
        } elseif {$av ne $bv} {
            return 0
        }
    }
    return 1
}

proc ::GX::PlotDatasetAPIv2::_reconcilePersistedSpec {ref spec} {
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    set generic [::GX::graphSeriesList plot.dataset $graphId $variantId 1]
    set byId [dict create]
    foreach item $generic {dict set byId [dict get $item series_id] $item}

    set changed 0
    set seen [dict create]
    set panels {}
    foreach panel [dict get $spec panels] {
        set kept {}
        foreach series [dict get $panel series] {
            if {[_seriesScientificStale $series]} {set changed 1; continue}
            set sid [dict get $series id]
            # Graph Series owns scientific identity. PlotSpec owns presentation
            # and panel membership. Keeping a PlotSpec-only series would revive
            # a deleted Graph Series and can make caches render obsolete data.
            if {![dict exists $byId $sid] || [dict exists $seen $sid]} {
                set changed 1
                continue
            }
            set cleaned [_seriesAuxSanitize $series]
            set synced [_seriesFromGeneric [dict get $byId $sid] [_presentationFromSeries $cleaned]]
            if {![_seriesEquivalent $synced $series]} {set changed 1}
            lappend kept $synced
            dict set seen $sid 1
        }
        dict set panel series $kept
        lappend panels $panel
    }

    # A newly committed Graph Series has no provider presentation yet. Put it in
    # the first existing panel with neutral defaults so it cannot disappear from
    # a multipanel render merely because derived runtime/cache predates the edit.
    set missing {}
    foreach item $generic {
        set sid [dict get $item series_id]
        if {![dict exists $seen $sid]} {
            lappend missing [_seriesFromGeneric $item [dict create kind auto]]
        }
    }
    if {[llength $missing]} {
        set first [lindex $panels 0]
        foreach item $missing {dict lappend first series $item}
        lset panels 0 $first
        set changed 1
    }

    set total 0
    foreach panel $panels {incr total [llength [dict get $panel series]]}
    if {$total == 0} {
        removeSpec $ref
        _removeDeadPlotArtifacts $ref
        return [deriveSpec $ref]
    }
    dict set spec panels $panels
    if {$changed} {saveSpec $ref $spec}
    return $spec
}

proc ::GX::PlotDatasetAPIv2::loadSpec {plotRef {deriveIfMissing 1}} {
    variable schemaId; variable styleFields; variable axisFields; variable errorFields
    _requireFramework
    set ref [_normalizePlotRef $plotRef]; set path [_specPath $ref]
    if {![file isfile $path]} {
        if {!$deriveIfMissing} {_error "no PlotSpec v2 is persisted for this plot"}
        return [deriveSpec $ref]
    }
    set d [::GX::parseIni $path]
    if {[::GX::descriptorValue $d plotspec schema ""] ne $schemaId} {_error "invalid persisted PlotSpec schema"}
    set spec [dict create schema $schemaId graph_type [::GX::descriptorValue $d plotspec graph_type cartesian_2d] \
        graph_id [dict get $ref graph_id] defaults [dict create style [dict create]] panels {} output [dict create]]
    dict set spec output extra_format [::GX::descriptorValue $d plotspec output_extra_format none]
    if {[::GX::descriptorValue $d plotspec multi_panel_present 0]} {dict set spec multi_panel [_bool [::GX::descriptorValue $d plotspec multi_panel 0] multi_panel]}
    if {[::GX::descriptorValue $d plotspec title_present 0]} {dict set spec title [::GX::descriptorValue $d plotspec title ""]}
    set dst [dict create]; foreach f $styleFields {_readOpt $d plotspec default_style $f dst}; dict set spec defaults style $dst
    set pc [::GX::descriptorValue $d plotspec panel_count 1]
    if {![string is integer -strict $pc] || $pc < 1} {_error "invalid persisted PlotSpec panel_count"}
    for {set pi 1} {$pi <= $pc} {incr pi} {
        set psec "panel.$pi"
        set p [dict create id [::GX::descriptorValue $d $psec id "panel$pi"] axes [dict create] series {} annotations {}]
        if {[::GX::descriptorValue $d $psec title_present 0]} {dict set p title [::GX::descriptorValue $d $psec title ""]}
        foreach a {x y_left y_right} {
            set ad [dict create]; foreach f $axisFields {_readOpt $d $psec "axis.$a" $f ad}; if {[dict size $ad]} {dict set p axes $a $ad}
        }
        set n [::GX::descriptorValue $d $psec series_count 0]
        for {set i 1} {$i <= $n} {incr i} {
            set sec "$psec.series.$i"; set s [dict create]
            foreach f {id dataset_id x_variable_id y_variable_id family_variable_id secondary_variable_id ordering_variable_id family_label_prefix source_row_ordinals source_row_continuity axis label enabled kind order step_mode bar_width bar_baseline histogram_bins histogram_normalization box_whisker_iqr box_show_outliers} {
                set marker [::GX::descriptorValue $d $sec $f "__PLOT_DATASET_MISSING__"]
                if {$marker ne "__PLOT_DATASET_MISSING__"} {dict set s $f $marker}
            }
            set st [dict create]; foreach f $styleFields {_readOpt $d $sec style $f st}; if {[dict size $st]} {dict set s style $st}
            foreach ek {x_error y_error} {
                set ed [dict create]; foreach f $errorFields {_readOpt $d $sec $ek $f ed}; if {[dict size $ed]} {dict set s $ek $ed}
            }
            set b [dict create]; foreach f {lower_variable_id upper_variable_id draw_center} {_readOpt $d $sec band $f b}; if {[dict size $b]} {dict set s band $b}
            set bb [dict create]; foreach f {lower_variable_id upper_variable_id} {_readOpt $d $sec bar_bounds $f bb}; if {[dict size $bb]} {dict set s bar_bounds $bb}
            dict lappend p series $s
        }
        set n [::GX::descriptorValue $d $psec annotation_count 0]
        for {set i 1} {$i <= $n} {incr i} {
            set sec "$psec.annotation.$i"; set a [dict create]
            foreach f {type axis value min max x y label color line_style line_width opacity} {
                set marker [::GX::descriptorValue $d $sec $f "__PLOT_DATASET_MISSING__"]
                if {$marker ne "__PLOT_DATASET_MISSING__"} {dict set a $f $marker}
            }
            dict lappend p annotations $a
        }
        dict lappend spec panels $p
    }
    # Backward compatibility: 3.1.x multi-panel PlotSpecs had no explicit toggle.
    if {![dict exists $spec multi_panel]} {dict set spec multi_panel [expr {$pc > 1 ? 1 : 0}]}
    # Deleted datasets/variables are ordinary session lifecycle changes. Remove
    # stale provider state instead of making every plot.dataset editor/render fail.
    set spec [_reconcilePersistedSpec $ref $spec]
    set total 0
    foreach p [dict get $spec panels] {incr total [llength [dict get $p series]]}
    if {$total > 0} {validateSpec $spec}
    return $spec
}
# Reconcile only live base/variant identities. Orphan provider sidecars from an
# explicitly deleted variant are not treated as plots and never recreate it.
proc ::GX::PlotDatasetAPIv2::reconcilePersistentPlots {} {
    set refs [list [_plotRef plot.dataset.xy ""] [_plotRef plot.dataset.xy_region ""]]
    foreach graphId {plot.dataset.xy plot.dataset.xy_region} {
        foreach variantId [::GX::plotVariantIds plot.dataset $graphId] {
            lappend refs [_plotRef $graphId $variantId]
        }
    }
    foreach ref $refs {
        set path [_specPath $ref]
        if {[file isfile $path]} {loadSpec $ref 0}
    }
    return 1
}

proc ::GX::PlotDatasetAPIv2::deriveSpec {plotRef} {
    variable schemaId
    set ref [_normalizePlotRef $plotRef]
    set r [::GX::PlotDatasetAPIv1::readPlot $ref]
    set p [dict create id main axes [dict create] series {} annotations {}]
    foreach s [dict get $r series] {
        set d [dict create id [dict get $s series_id] dataset_id [dict get $s dataset_id] x_variable_id [dict get $s x_variable_id] \
            y_variable_id [dict get $s y_variable_id] axis [dict get $s axis] label [dict get $s label] enabled [dict get $s enabled] \
            order [dict get $s order] kind auto]
        dict lappend p series $d
    }
    set title [expr {[dict exists $r config title] ? [dict get $r config title] : "auto"}]
    return [dict create schema $schemaId graph_type cartesian_2d graph_id [dict get $ref graph_id] title $title multi_panel 0 \
        defaults [dict create style [dict create]] panels [list $p] output [dict create]]
}

proc ::GX::PlotDatasetAPIv2::removeSpec {plotRef} {
    set p [_specPath [_normalizePlotRef $plotRef]]
    if {[file exists $p]} {file delete -force -- $p; return 1}
    return 0
}


proc ::GX::PlotDatasetAPIv2::applySpec {plotRef spec} {
    _requireFramework; validateSpec $spec
    set ref [_normalizePlotRef $plotRef]
    if {[dict get $spec graph_id] ne [dict get $ref graph_id]} {_error "PlotSpec graph_id does not match plot reference"}
    if {[dict get $spec graph_type] eq "cartesian_3d"} {return [_applyGridSpec $ref $spec]}
    set desired {}
    set graphId [dict get $ref graph_id]
    set variantId [dict get $ref variant_id]
    set existingIds [::GX::graphSeriesIds plot.dataset $graphId $variantId]
    set existing [dict create]
    foreach id $existingIds {
        dict set existing $id [::GX::PlotDatasetAPIv1::_seriesCoreFields [::GX::graphSeriesSnapshot plot.dataset $graphId $id $variantId]]
    }
    set rank 0
    foreach p [dict get $spec panels] {
        foreach s [expr {[dict exists $p series] ? [dict get $p series] : {}}] {
            incr rank; set sid [dict get $s id]; lappend desired $sid
            set core [dict create dataset_id [dict get $s dataset_id] x_variable_id [dict get $s x_variable_id] y_variable_id [dict get $s y_variable_id] \
                axis [dict get $s axis] label [expr {[dict exists $s label] ? [dict get $s label] : ""}] enabled [expr {[dict exists $s enabled] ? [_bool [dict get $s enabled] enabled] : 1}] \
                order [expr {[dict exists $s order] ? [dict get $s order] : $rank}]]
            foreach key {secondary_variable_id ordering_variable_id row_filters source_row_ordinals} {
                if {[dict exists $s $key]} {dict set core $key [dict get $s $key]}
            }
            if {[dict exists $existing $sid]} {
                set core [dict merge [dict get $existing $sid] $core]
                if {$core eq [dict get $existing $sid]} continue
            }
            ::GX::graphSeriesSet plot.dataset $graphId $sid $core $variantId
        }
    }
    foreach old $existingIds {
        if {[lsearch -exact $desired $old] < 0} {::GX::graphSeriesRemove plot.dataset $graphId $old $variantId}
    }
    if {[dict exists $spec title]} {::GX::PlotDatasetAPIv1::setTitle $ref [dict get $spec title]}
    saveSpec $ref $spec
    return [readPlot $ref]
}
proc ::GX::PlotDatasetAPIv2::createPlotFromSpec {spec {kind base} {sourceVariant ""}} {
    validateSpec $spec
    if {[dict get $spec graph_type] eq "cartesian_3d" && $kind ne "variant"} {_error "3D PlotSpec requires a persistent variant"}
    set ref [::GX::PlotDatasetAPIv1::createPlot [dict get $spec graph_id] $kind $sourceVariant]
    if {$kind eq "variant" && $sourceVariant eq ""} {
        ::GX::plotVariantResetInheritedDataView plot.dataset [dict get $ref graph_id] [dict get $ref variant_id]
    }
    applySpec $ref $spec
    return $ref
}

proc ::GX::PlotDatasetAPIv2::readPlot {plotRef} {
    set ref [_normalizePlotRef $plotRef]
    set base [::GX::PlotDatasetAPIv1::readPlot $ref]
    if {[dict get $ref graph_id] eq "plot.dataset.xyz"} {return $base}
    set spec [loadSpec $ref 1]
    return [dict merge $base [dict create plotspec $spec plotspec_path [_specPath $ref]]]
}
proc ::GX::PlotDatasetAPIv2::artifacts {plotRef} {::GX::PlotDatasetAPIv1::artifacts [_normalizePlotRef $plotRef]}
proc ::GX::PlotDatasetAPIv2::_gridRender {ref operation} {
    # CORE's Variant serializer already projects the Variant's primary Dataset
    # and exact bindings, preserving the base runtime. Replacing the module's
    # primary source here makes its existing base bindings appear stale before
    # that projection (for example a Builder XYZ publication beside a 2-D plot).
    if {$operation eq "render"} {return [::GX::PlotDatasetAPIv1::render $ref]}
    return [::GX::PlotDatasetAPIv1::rerender $ref]
}
proc ::GX::PlotDatasetAPIv2::render {plotRef} {
    set ref [_normalizePlotRef $plotRef]
    if {[dict get $ref graph_id] eq "plot.dataset.xyz"} {return [_gridRender $ref render]}
    if {[file isfile [_specPath $ref]]} {validateSpec [loadSpec $ref 0]}
    return [::GX::PlotDatasetAPIv1::render $ref]
}
proc ::GX::PlotDatasetAPIv2::rerender {plotRef} {
    set ref [_normalizePlotRef $plotRef]
    if {[dict get $ref graph_id] eq "plot.dataset.xyz"} {return [_gridRender $ref rerender]}
    if {[file isfile [_specPath $ref]]} {validateSpec [loadSpec $ref 0]}
    return [::GX::PlotDatasetAPIv1::rerender $ref]
}


proc ::GX::PlotDatasetAPIv2::_findSeriesLocation {spec seriesId} {
    set pi 0
    foreach p [dict get $spec panels] {
        set si 0
        foreach s [expr {[dict exists $p series] ? [dict get $p series] : {}}] {
            if {[dict get $s id] eq $seriesId} {return [list $pi $si]}
            incr si
        }
        incr pi
    }
    _error "unknown series '$seriesId'"
}

proc ::GX::PlotDatasetAPIv2::_findSeriesIndex {spec seriesId} {
    lassign [_findSeriesLocation $spec $seriesId] _ si
    return $si
}
proc ::GX::PlotDatasetAPIv2::_presentationKeys {} {
    return {kind style family_variable_id family_label_prefix source_row_continuity step_mode bar_width bar_baseline histogram_bins histogram_normalization box_whisker_iqr box_show_outliers x_error y_error band bar_bounds}
}

proc ::GX::PlotDatasetAPIv2::_presentationFromSeries {series} {
    set out [dict create]
    foreach key [_presentationKeys] {
        if {[dict exists $series $key]} { dict set out $key [dict get $series $key] }
    }
    if {![dict exists $out kind]} { dict set out kind auto }
    return $out
}

proc ::GX::PlotDatasetAPIv2::_seriesFromGeneric {generic presentation} {
    foreach key {series_id dataset_id x_variable_id y_variable_id axis} {
        if {![dict exists $generic $key] || [string trim [dict get $generic $key]] eq ""} {
            _error "Series Editor context is missing '$key'"
        }
    }
    set s [dict create \
        id [dict get $generic series_id] \
        dataset_id [dict get $generic dataset_id] \
        x_variable_id [dict get $generic x_variable_id] \
        y_variable_id [dict get $generic y_variable_id] \
        axis [dict get $generic axis] \
        label [expr {[dict exists $generic label] ? [dict get $generic label] : ""}] \
        enabled [expr {[dict exists $generic enabled] ? [dict get $generic enabled] : 1}] \
        order [expr {[dict exists $generic order] ? [dict get $generic order] : 0}]]
    foreach key {secondary_variable_id ordering_variable_id row_filters source_row_ordinals} {
        if {[dict exists $generic $key] && [dict get $generic $key] ne ""} {dict set s $key [dict get $generic $key]}
    }
    dict for {key value} $presentation { dict set s $key $value }
    return $s
}

proc ::GX::PlotDatasetAPIv2::_validatedPresentationForGeneric {generic fields} {
    if {[catch {dict size $fields}]} {_error "presentation fields must be a dict"}
    foreach key [dict keys $fields] {
        if {$key ni [_presentationKeys]} {_error "unknown presentation field '$key'"}
    }
    set s [_seriesFromGeneric $generic $fields]
    _validateSeries $s 1
    return [_presentationFromSeries $s]
}

# Persist provider-owned state after CORE has committed the generic Graph Series.
# The binding snapshot in PlotSpec is synchronized to the committed generic
# series, while the stable series_id remains the provider-state key.

proc ::GX::PlotDatasetAPIv2::_savePresentationForGeneric {plotRef generic presentation {targetPanel ""}} {
    set ref [_normalizePlotRef $plotRef]
    set presentation [_validatedPresentationForGeneric $generic $presentation]
    set sid [dict get $generic series_id]
    set spec [loadSpec $ref 1]
    set panels [dict get $spec panels]
    set oldPi -1; set oldSi -1
    catch {lassign [_findSeriesLocation $spec $sid] oldPi oldSi}
    if {$targetPanel eq ""} {
        if {$oldPi >= 0} {set targetPanel [dict get [lindex $panels $oldPi] id]} else {set targetPanel [dict get [lindex $panels 0] id]}
    }
    set targetPi -1; set pi 0
    foreach p $panels {if {[dict get $p id] eq $targetPanel} {set targetPi $pi; break}; incr pi}
    if {$targetPi < 0} {_error "unknown panel '$targetPanel'"}
    set updated [_seriesFromGeneric $generic $presentation]

    if {$oldPi >= 0 && $oldPi == $targetPi} {
        set p [lindex $panels $oldPi]; set ss [dict get $p series]
        lset ss $oldSi $updated
        dict set p series $ss; lset panels $oldPi $p
    } else {
        if {$oldPi >= 0} {
            set p [lindex $panels $oldPi]; set ss [dict get $p series]
            set ss [lreplace $ss $oldSi $oldSi]
            dict set p series $ss; lset panels $oldPi $p
        }
        set p [lindex $panels $targetPi]; set ss [dict get $p series]
        lappend ss $updated
        dict set p series $ss; lset panels $targetPi $p
    }
    dict set spec panels $panels
    validateSpec $spec
    saveSpec $ref $spec
    return $updated
}

proc ::GX::PlotDatasetAPIv2::_variantPresentationGraphs {} {
    return {plot.dataset.xy plot.dataset.xy_region}
}

proc ::GX::PlotDatasetAPIv2::_initializeVariantPresentation {graphId sourceVariant targetVariant} {
    if {$graphId ni [_variantPresentationGraphs]} { return 0 }
    if {$targetVariant eq ""} { return 0 }
    set target [_plotRef $graphId $targetVariant]
    set targetPath [_specPath $target]
    if {[file isfile $targetPath]} { return 1 }
    set source [_plotRef $graphId $sourceVariant]
    set sourcePath [_specPath $source]
    if {![file isfile $sourcePath] && ![llength [::GX::graphSeriesIds plot.dataset $graphId $sourceVariant]]} {
        # No provider state exists yet. CORE may legitimately create an empty
        # variant before any scientific series has been configured.
        return 0
    }
    # loadSpec(...,1) intentionally derives a structurally valid PlotSpec when
    # the source has Graph Series but no explicit provider sidecar. saveSpec
    # then materializes a physically independent target sidecar; later edits
    # cannot leak backward.
    set spec [loadSpec $source 1]
    saveSpec $target $spec
    return 1
}

proc ::GX::PlotDatasetAPIv2::_variantCreateTrace {command code result op} {
    if {$op ne "leave" || $code != 0} { return }
    if {[llength $command] < 3} { return }
    set moduleId [lindex $command 1]
    set graphId [lindex $command 2]
    set sourceVariant [expr {[llength $command] >= 4 ? [lindex $command 3] : ""}]
    if {$moduleId ne "plot.dataset" || $graphId ni [_variantPresentationGraphs]} { return }
    set targetVariant [string trim $result]
    if {$targetVariant eq ""} { return }
    if {[catch {_initializeVariantPresentation $graphId $sourceVariant $targetVariant} err]} {
        # Do not corrupt the CORE variant transaction if provider-state copying
        # fails. The Series Editor build path retries base initialization for a
        # normal New-from-base variant and exposes any later provider error.
        puts stderr "plot.dataset: variant PlotSpec initialization failed for $graphId/$targetVariant: $err"
    }
}

proc ::GX::PlotDatasetAPIv2::_installVariantCreateTrace {} {
    set command ::GX::plotVariantCreate
    if {![llength [info commands $command]]} { return 0 }
    set callback ::GX::PlotDatasetAPIv2::_variantCreateTrace
    foreach item [trace info execution $command] {
        if {[lindex $item 0] eq "leave" && [lindex $item 1] eq $callback} { return 1 }
    }
    trace add execution $command leave $callback
    return 1
}

proc ::GX::PlotDatasetAPIv2::_ensureVariantPresentationForEditor {context} {
    if {[dict get $context module_id] ne "plot.dataset"} { return }
    set graphId [dict get $context graph_id]
    set variantId [dict get $context variant_id]
    if {$variantId eq "" || $graphId ni [_variantPresentationGraphs]} { return }
    set ref [_plotRef $graphId $variantId]
    if {[file isfile [_specPath $ref]]} { return }
    # Fallback for a New-from-base variant created before this public API was
    # activated. Normal/duplicate creation while the provider is active is
    # handled by _variantCreateTrace and therefore preserves the exact source.
    _initializeVariantPresentation $graphId "" $variantId
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionPlotRef {context} {
    if {[dict get $context module_id] ne "plot.dataset"} {
        _error "Series Editor context belongs to another module"
    }
    return [_plotRef [dict get $context graph_id] [dict get $context variant_id]]
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionEnsureUi {} {
    if {[llength [info commands ::GX::PlotDatasetAPIv2::_seriesExtensionBuildGui]]} { return }
    set adapter [file join [_here] .. ui plot_dataset_editor_v2.tcl]
    if {![file isfile $adapter]} {_error "optional v2 editor is unavailable"}
    source $adapter
    if {![llength [info commands ::GX::PlotDatasetAPIv2::_seriesExtensionBuildGui]]} {
        _error "Series Editor presentation adapter is unavailable"
    }
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionBuild {context} {
    _ensureVariantPresentationForEditor $context
    _seriesExtensionEnsureUi
    return [::GX::PlotDatasetAPIv2::_seriesExtensionBuildGui $context]
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionLoad {context} {
    _seriesExtensionEnsureUi
    return [::GX::PlotDatasetAPIv2::_seriesExtensionLoadGui $context]
}


proc ::GX::PlotDatasetAPIv2::_seriesExtensionValidate {context} {
    _seriesExtensionEnsureUi
    set generic [dict get $context generic_series]
    if {$generic eq ""} {_error "select or define a series before saving presentation settings"}
    set fields [::GX::PlotDatasetAPIv2::_seriesExtensionCollectGui $context]
    set panelId ""
    if {[dict exists $fields __panel_id]} {set panelId [dict get $fields __panel_id]; dict unset fields __panel_id}
    set presentation [_validatedPresentationForGeneric $generic $fields]
    return [dict create presentation $presentation panel_id $panelId]
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionSave {context validatedState} {
    set ref [_seriesExtensionPlotRef $context]
    set generic [dict get $context generic_series]
    if {$generic eq ""} {_error "Series Editor save context has no committed series"}
    set presentation [expr {[dict exists $validatedState presentation] ? [dict get $validatedState presentation] : $validatedState}]
    set panelId [expr {[dict exists $validatedState panel_id] ? [dict get $validatedState panel_id] : ""}]
    return [_savePresentationForGeneric $ref $generic $presentation $panelId]
}
proc ::GX::PlotDatasetAPIv2::_seriesExtensionClose {context} {
    if {[llength [info commands ::GX::PlotDatasetAPIv2::_seriesExtensionCloseGui]]} {
        catch {::GX::PlotDatasetAPIv2::_seriesExtensionCloseGui $context}
    }
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionTableValues {context} {
    set ref [_plotRef [dict get $context graph_id] [dict get $context variant_id]]
    set sid [dict get $context series_id]
    if {$sid eq ""} {return [dict create panel ""]}
    if {[catch {set spec [loadSpec $ref 1]}]} {return [dict create panel ""]}
    foreach p [dict get $spec panels] {
        foreach s [dict get $p series] {
            if {[dict get $s id] eq $sid} {return [dict create panel [dict get $p id]]}
        }
    }
    return [dict create panel ""]
}

proc ::GX::PlotDatasetAPIv2::_seriesExtensionTableValuesBatch {context} {
    set ref [_plotRef [dict get $context graph_id] [dict get $context variant_id]]
    set values [dict create]
    if {[catch {set spec [loadSpec $ref 1]}]} {return $values}
    foreach panel [dict get $spec panels] {
        foreach series [dict get $panel series] {
            dict set values [dict get $series id] [dict create panel [dict get $panel id]]
        }
    }
    return $values
}

proc ::GX::PlotDatasetAPIv2::_registerSeriesEditorExtension {} {
    if {![llength [info commands ::GX::seriesEditorExtensionRegister]]} { return 0 }
    set providerId plot.dataset.presentation
    if {![catch {set existing [::GX::seriesEditorExtensionDefinition $providerId]}]} {
        if {[dict get $existing module_id] eq "plot.dataset" &&
            [dict get $existing graph_ids] eq {plot.dataset.xy plot.dataset.xy_region}} {
            return 1
        }
        _error "Series Editor extension provider ID '$providerId' is already registered with another definition"
    }
    ::GX::seriesEditorExtensionRegister $providerId [dict create \
        module_id plot.dataset \
        graph_ids {plot.dataset.xy;plot.dataset.xy_region} \
        table_columns [list [dict create id panel heading Panel width 90]] \
        table_values_proc ::GX::PlotDatasetAPIv2::_seriesExtensionTableValues \
        table_values_batch_proc ::GX::PlotDatasetAPIv2::_seriesExtensionTableValuesBatch \
        build_proc ::GX::PlotDatasetAPIv2::_seriesExtensionBuild \
        load_proc ::GX::PlotDatasetAPIv2::_seriesExtensionLoad \
        validate_proc ::GX::PlotDatasetAPIv2::_seriesExtensionValidate \
        save_proc ::GX::PlotDatasetAPIv2::_seriesExtensionSave \
        close_proc ::GX::PlotDatasetAPIv2::_seriesExtensionClose]
    return 1
}


proc ::GX::PlotDatasetAPIv2::_graphConfigPlotRef {context} {
    if {[dict get $context module_id] ne "plot.dataset"} {_error "Graph Configuration context belongs to another module"}
    return [_plotRef [dict get $context graph_id] [dict get $context variant_id]]
}

proc ::GX::PlotDatasetAPIv2::_graphConfigEnsureUi {} {
    if {[llength [info commands ::GX::PlotDatasetAPIv2::_graphConfigBuildGui]]} { return }
    set adapter [file join [_here] .. ui plot_dataset_editor_v2.tcl]
    if {![file isfile $adapter]} {_error "optional v2 editor is unavailable"}
    source $adapter
    if {![llength [info commands ::GX::PlotDatasetAPIv2::_graphConfigBuildGui]]} {_error "Graph Configuration adapter is unavailable"}
}

proc ::GX::PlotDatasetAPIv2::_graphConfigBuild {context} {
    _ensureVariantPresentationForEditor $context
    _graphConfigEnsureUi
    return [::GX::PlotDatasetAPIv2::_graphConfigBuildGui $context]
}
proc ::GX::PlotDatasetAPIv2::_graphConfigClose {context} {
    if {[llength [info commands ::GX::PlotDatasetAPIv2::_graphConfigCloseGui]]} {catch {::GX::PlotDatasetAPIv2::_graphConfigCloseGui $context}}
}
proc ::GX::PlotDatasetAPIv2::_registerGraphConfigExtension {} {
    if {![llength [info commands ::GX::graphConfigExtensionRegister]]} { return 0 }
    set providerId plot.dataset.graph_configuration
    if {![catch {set existing [::GX::graphConfigExtensionDefinition $providerId]}]} {
        if {[dict get $existing module_id] eq "plot.dataset" && [dict get $existing graph_ids] eq {plot.dataset.xy}} {return 1}
        _error "Graph Configuration extension provider ID '$providerId' is already registered with another definition"
    }
    ::GX::graphConfigExtensionRegister $providerId [dict create \
        module_id plot.dataset graph_ids {plot.dataset.xy} \
        build_proc ::GX::PlotDatasetAPIv2::_graphConfigBuild \
        close_proc ::GX::PlotDatasetAPIv2::_graphConfigClose]
    return 1
}

# Axis Configuration Extension API v1 integration. This is artifact-based so
# plots created through PLOT_DATASET_API_v2 receive the same extended panel
# controls even when another module is the consumer.
proc ::GX::PlotDatasetAPIv2::_axisConfigExtensionMatch {path} {
    if {[catch {set ref [plotRefForArtifact $path]}] || $ref eq ""} {return 0}
    if {[catch {set enabled [multiPanelEnabled $ref]}] || !$enabled} {return 0}
    return [expr {[llength [panelIds $ref]] > 1}]
}

proc ::GX::PlotDatasetAPIv2::_axisConfigEnsureUi {} {
    if {[llength [info commands ::GX::PlotDatasetAPIv2::_axisConfigBuildGui]]} {return}
    set adapter [file join [_here] .. ui plot_dataset_editor_v2.tcl]
    if {![file isfile $adapter]} {_error "optional v2 editor is unavailable"}
    source $adapter
    if {![llength [info commands ::GX::PlotDatasetAPIv2::_axisConfigBuildGui]]} {_error "Axis Configuration adapter is unavailable"}
}

proc ::GX::PlotDatasetAPIv2::_axisConfigBuild {context} {
    _axisConfigEnsureUi
    return [::GX::PlotDatasetAPIv2::_axisConfigBuildGui $context]
}

proc ::GX::PlotDatasetAPIv2::_axisConfigClose {context} {
    if {[llength [info commands ::GX::PlotDatasetAPIv2::_axisConfigCloseGui]]} {catch {::GX::PlotDatasetAPIv2::_axisConfigCloseGui $context}}
}

proc ::GX::PlotDatasetAPIv2::_registerAxisConfigExtension {} {
    if {![llength [info commands ::GX::axisConfigExtensionRegister]]} {return 0}
    set providerId plot.dataset.axis_configuration
    if {![catch {set existing [::GX::axisConfigExtensionDefinition $providerId]}]} {return 1}
    ::GX::axisConfigExtensionRegister $providerId [dict create \
        match_proc ::GX::PlotDatasetAPIv2::_axisConfigExtensionMatch \
        build_proc ::GX::PlotDatasetAPIv2::_axisConfigBuild \
        close_proc ::GX::PlotDatasetAPIv2::_axisConfigClose]
    return 1
}

proc ::GX::PlotDatasetAPIv2::setSeriesPresentation {plotRef seriesId fields} {
    set ref [_normalizePlotRef $plotRef]
    set spec [loadSpec $ref 1]
    lassign [_findSeriesLocation $spec $seriesId] pi si
    set panel [lindex [dict get $spec panels] $pi]
    set item [lindex [dict get $panel series] $si]
    set generic [dict create \
        series_id [dict get $item id] \
        dataset_id [dict get $item dataset_id] \
        x_variable_id [dict get $item x_variable_id] \
        y_variable_id [dict get $item y_variable_id] \
        axis [dict get $item axis] \
        label [expr {[dict exists $item label] ? [dict get $item label] : ""}] \
        enabled [expr {[dict exists $item enabled] ? [dict get $item enabled] : 1}] \
        order [expr {[dict exists $item order] ? [dict get $item order] : 0}]]
    set merged [_presentationFromSeries $item]
    if {[catch {dict size $fields}]} {_error "presentation fields must be a dict"}
    foreach key [dict keys $fields] {
        if {$key ni [_presentationKeys]} {_error "unknown presentation field '$key'"}
        dict set merged $key [dict get $fields $key]
    }
    return [_savePresentationForGeneric $ref $generic $merged [dict get $panel id]]
}

proc ::GX::PlotDatasetAPIv2::multiPanelEnabled {plotRef} {
    set spec [loadSpec [_normalizePlotRef $plotRef] 1]
    if {[dict exists $spec multi_panel]} {return [_bool [dict get $spec multi_panel] multi_panel]}
    return [expr {[llength [dict get $spec panels]] > 1}]
}

proc ::GX::PlotDatasetAPIv2::setMultiPanel {plotRef state} {
    set ref [_normalizePlotRef $plotRef]
    set spec [loadSpec $ref 1]
    set enabled [_bool $state multi_panel]
    if {[dict get $spec graph_id] eq "plot.dataset.xy_region" && $enabled} {_error "plot.dataset.xy_region remains single-panel"}
    dict set spec multi_panel $enabled
    saveSpec $ref $spec
    return $enabled
}

proc ::GX::PlotDatasetAPIv2::_panelIndex {spec panelId} {
    set i 0
    foreach p [dict get $spec panels] {
        if {[dict get $p id] eq $panelId} {return $i}
        incr i
    }
    _error "unknown panel '$panelId'"
}

proc ::GX::PlotDatasetAPIv2::panelInfo {plotRef panelId} {
    set spec [loadSpec [_normalizePlotRef $plotRef] 1]
    return [lindex [dict get $spec panels] [_panelIndex $spec $panelId]]
}

proc ::GX::PlotDatasetAPIv2::setPanelTitle {plotRef panelId title} {
    set ref [_normalizePlotRef $plotRef]
    set spec [loadSpec $ref 1]
    set idx [_panelIndex $spec $panelId]
    set panel [lindex [dict get $spec panels] $idx]
    set title [string trim $title]
    if {[regexp {[\r\n]} $title]} {_error "panel title must be single-line"}
    if {$title eq ""} {catch {dict unset panel title}} else {dict set panel title $title}
    set panels [dict get $spec panels]; lset panels $idx $panel; dict set spec panels $panels
    saveSpec $ref $spec
    return $panel
}

proc ::GX::PlotDatasetAPIv2::setPanelAxis {plotRef panelId axis fields} {
    if {$axis ni {x y_left y_right}} {_error "panel axis must be x, y_left or y_right"}
    set ref [_normalizePlotRef $plotRef]
    set spec [loadSpec $ref 1]
    set idx [_panelIndex $spec $panelId]
    set clean [dict create]
    if {[catch {dict size $fields}]} {_error "panel axis fields must be a dict"}
    dict for {key value} $fields {
        if {$key ni {label display_unit scale min max major_step minor_grid}} {_error "unknown panel axis field '$key'"}
        set value [string trim $value]
        if {$value ne ""} {dict set clean $key $value}
    }
    _validateAxis $clean "panel '$panelId' axis $axis"
    set panels [dict get $spec panels]; set panel [lindex $panels $idx]
    if {[dict size $clean]} {dict set panel axes $axis $clean} else {catch {dict unset panel axes $axis}}
    lset panels $idx $panel; dict set spec panels $panels
    saveSpec $ref $spec
    return $panel
}


proc ::GX::PlotDatasetAPIv2::plotRefForArtifact {path} {
    _requireFramework
    set target [file normalize $path]
    foreach graphId [::GX::moduleGraphIds plot.dataset] {
        set refs [list [_plotRef $graphId ""]]
        if {[llength [info commands ::GX::plotVariantIds]]} {
            foreach variantId [::GX::plotVariantIds plot.dataset $graphId] {
                if {[catch {lappend refs [_plotRef $graphId $variantId]}]} continue
            }
        }
        foreach ref $refs {
            if {[catch {set a [::GX::PlotDatasetAPIv1::artifacts $ref]}]} continue
            if {[file normalize [dict get $a graph_artifact]] eq $target} {return $ref}
        }
    }
    return {}
}

proc ::GX::PlotDatasetAPIv2::panelIdsForArtifact {path} {
    set ref [plotRefForArtifact $path]
    if {$ref eq ""} {return {}}
    return [panelIds $ref]
}

proc ::GX::PlotDatasetAPIv2::panelIds {plotRef} {
    set spec [loadSpec [_normalizePlotRef $plotRef] 1]
    set out {}
    foreach p [dict get $spec panels] {lappend out [dict get $p id]}
    return $out
}

proc ::GX::PlotDatasetAPIv2::addPanel {plotRef panelId} {
    set ref [_normalizePlotRef $plotRef]; set panelId [_validId [string trim $panelId] "panel ID"]
    set spec [loadSpec $ref 1]
    if {[dict get $spec graph_id] eq "plot.dataset.xy_region"} {_error "plot.dataset.xy_region remains single-panel"}
    foreach p [dict get $spec panels] {if {[dict get $p id] eq $panelId} {_error "panel '$panelId' already exists"}}
    dict lappend spec panels [dict create id $panelId axes [dict create] series {} annotations {}]
    dict set spec multi_panel 1
    saveSpec $ref $spec
    return $spec
}

proc ::GX::PlotDatasetAPIv2::removePanel {plotRef panelId} {
    set ref [_normalizePlotRef $plotRef]; set spec [loadSpec $ref 1]
    set panels [dict get $spec panels]
    if {[llength $panels] <= 1} {_error "cannot remove the last panel"}
    set out {}; set found 0
    foreach p $panels {
        if {[dict get $p id] eq $panelId} {
            set found 1
            if {[llength [dict get $p series]]} {_error "panel '$panelId' still contains series; move them before removing the panel"}
            continue
        }
        lappend out $p
    }
    if {!$found} {_error "unknown panel '$panelId'"}
    dict set spec panels $out; saveSpec $ref $spec; return $spec
}

proc ::GX::PlotDatasetAPIv2::movePanel {plotRef panelId delta} {
    set ref [_normalizePlotRef $plotRef]; set spec [loadSpec $ref 1]; set panels [dict get $spec panels]
    set idx -1; set i 0; foreach p $panels {if {[dict get $p id] eq $panelId} {set idx $i;break}; incr i}
    if {$idx < 0} {_error "unknown panel '$panelId'"}
    if {![string is integer -strict $delta] || $delta == 0} {_error "panel move delta must be a nonzero integer"}
    set j [expr {$idx+$delta}]; if {$j < 0 || $j >= [llength $panels]} {return $spec}
    set a [lindex $panels $idx]; set b [lindex $panels $j]; lset panels $idx $b; lset panels $j $a
    dict set spec panels $panels; saveSpec $ref $spec; return $spec
}

proc ::GX::PlotDatasetAPIv2::setSeriesPanel {plotRef seriesId panelId} {
    set ref [_normalizePlotRef $plotRef]; set spec [loadSpec $ref 1]; set panels [dict get $spec panels]
    lassign [_findSeriesLocation $spec $seriesId] pi si
    set target -1; set i 0; foreach p $panels {if {[dict get $p id] eq $panelId} {set target $i;break}; incr i}
    if {$target < 0} {_error "unknown panel '$panelId'"}
    if {$target == $pi} {return $spec}
    set source [lindex $panels $pi]; set ss [dict get $source series]; set item [lindex $ss $si]
    set ss [lreplace $ss $si $si]; dict set source series $ss; lset panels $pi $source
    set dest [lindex $panels $target]; set ds [dict get $dest series]; lappend ds $item; dict set dest series $ds; lset panels $target $dest
    dict set spec panels $panels; saveSpec $ref $spec; return $spec
}
proc ::GX::PlotDatasetAPIv2::openEditor {plotRef} {
    _requireFramework
    if {![llength [info commands toplevel]]} {_error "Tk is unavailable"}
    if {![llength [info commands ::GX::PlotDatasetAPIv2::_openEditorGui]]} {
        set adapter [file join [_here] .. ui plot_dataset_editor_v2.tcl]
        if {![file isfile $adapter]} {_error "optional v2 editor is unavailable"}
        source $adapter
    }
    return [::GX::PlotDatasetAPIv2::_openEditorGui $plotRef]
}

# Registration itself is host-independent.  The Tk adapter is loaded lazily by
# build_proc only when CORE opens the standard Series editor.
::GX::PlotDatasetAPIv2::_installVariantCreateTrace
::GX::PlotDatasetAPIv2::_registerSeriesEditorExtension
::GX::PlotDatasetAPIv2::_registerGraphConfigExtension
::GX::PlotDatasetAPIv2::_registerAxisConfigExtension
