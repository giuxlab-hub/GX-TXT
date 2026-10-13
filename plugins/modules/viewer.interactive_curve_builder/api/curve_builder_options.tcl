# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::InteractiveCurveBuilder {variable epoch;if {![info exists epoch]} {set epoch 0}}
proc ::GX::InteractiveCurveBuilder::_optionFields {} {
    return {auto_order {type boolean label {Default Auto-order (explicit review required)} default 0} display_scope {type choice label {Default source graph scope} values {full selected} default full}}
}
proc ::GX::InteractiveCurveBuilder::_optionsValidate {values} {
    set result {}
    dict for {key field} [_optionFields] {dict set result $key [::GX::uiFieldNormalize $field [::GX::datasetPublicationV2DictDefault $values $key [dict get $field default]]]}
    foreach key [dict keys $values] {if {![dict exists $result $key]} {error {Unknown Builder default}}}
    return $result
}
proc ::GX::InteractiveCurveBuilder::_temporal {rows} {
    set bindings {}
    foreach row $rows {
        foreach axis {x y z t} {
            set vid [dict get $row ${axis}_id];if {$vid eq {}} continue
            dict set bindings [list [dict get $row dataset_id] $vid] 1
        }
    }
    foreach binding [dict keys $bindings] {
        lassign $binding ds vid;set spec [::GX::datasetVariableV3ById $ds $vid]
        if {[::GX::datasetPublicationV2DictDefault [::GX::sessionInspectionDataset $ds] contract {}] eq "timeseries.table"} {return 1}
        if {[dict get $spec value_kind] in {elapsed_time absolute_time date datetime time} || [dict get $spec semantic_role] in {time elapsed_time absolute_time timestamp}} {return 1}
        set unit [dict get $spec unit];set definition [::GX::unitRegistryDefinition $unit]
        if {[dict get $definition canonical_unit] ne {}} {set unit [dict get $definition canonical_unit]}
        if {$unit ne {} && ![catch {::GX::unitTclDimensionKey $unit} dimension] && $dimension eq [::GX::unitTclDimensionKey s]} {return 1}
    }
    return 0
}
proc ::GX::InteractiveCurveBuilder::ordering {rows mode parameterMode {startIndex 0}} {
    _numeric
    if {[_temporal $rows]} {error {Automatic ordering is unavailable for temporal source axes. Preserve measured chronology; turn Auto-order OFF}}
    set groups {};set points {}
    foreach row $rows {
        dict set groups [list [dict get $row dataset_id] [dict get $row family_id] [dict get $row family_value] [::GX::datasetPublicationV2DictDefault $row member_id {}] [::GX::datasetPublicationV2DictDefault $row member_value {}]] 1
    }
    if {[dict size $groups]!=1} {error {Auto-order requires one Dataset and one exact Family/Member characteristic}}
    set policy [expr {$parameterMode eq "arc_length" ? "geometry_auto" : "x_monotone"}]
    set axes [expr {$policy eq "geometry_auto" ? ($mode eq "3d" ? {x y z} : {x y}) : $mode eq "3d" ? {t x} : {x y}}]
    if {$policy eq "geometry_auto"} {
        set units [_units $rows $mode $parameterMode]
        if {$mode eq "2d" && [dict get $units x] ne [dict get $units y]} {error {Planar arc length needs a common X/Y unit. Use functional X ordering or the existing parametric Dataset Curve Fit workflow for different physical axes}}
    }
    set data {}
    foreach axis $axes {foreach row $rows {lappend data [dict get $row $axis]}}
    set input [::GX::ScientificTransportv1::array [list [llength $rows] [llength $axes]] $data]
    set opts [::GX::ScientificTransportv1::struct [dict create policy [::GX::ScientificTransportv1::text $policy] start_index [::GX::ScientificTransportv1::array {1 1} [list $startIndex]]]]
    set receipt [::GX::NumericAPIv1::callOperation point_sequence_order [list $input] $opts]
    set ordered {}
    foreach index [dict get $receipt permutation] {lappend ordered [lindex $rows [expr {int($index)}]]}
    if {[llength $ordered]!=[llength $rows] || [llength [lsort -integer -unique [dict get $receipt permutation]]]!=[llength $rows]} {error {Numerical ordering is not a bijection}}
    dict set receipt enabled 1;dict set receipt original_rows $rows;dict set receipt ordered_rows $ordered
    dict set receipt mode $mode;dict set receipt parameter_mode $parameterMode
    return $receipt
}
proc ::GX::InteractiveCurveBuilder::_sourceIdentityLabel {value} {
    if {$value eq {}} {return {(empty)}}
    if {[regexp -nocase {^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$} $value]} {return "[string range $value 0 7]…"}
    if {[string length $value]>18} {return "[string range $value 0 14]…"}
    return $value
}
proc ::GX::InteractiveCurveBuilder::sourcePlotCaption {rows scope} {
    set sources {}
    foreach row $rows {dict set sources [dict get $row dataset_id] 1}
    set names [join [dict keys $sources] {, }]
    return "[expr {$scope eq "full" ? "Full Dataset" : "Selected subset"}] · [llength $rows] fit rows · $names"
}
proc ::GX::InteractiveCurveBuilder::sourcePlotSeries {rows {scope full} {useT 0}} {
    if {$scope ni {full selected}} {error {Source plot scope must be full or selected}}
    set contexts {};set index 0;set result {}
    foreach row $rows {
        set x [dict get $row [expr {$useT ? "t_id" : "x_id"}]]
        if {$x eq {}} continue
        set key [list [dict get $row dataset_id] $x [dict get $row y_id] [dict get $row family_id] [::GX::datasetPublicationV2DictDefault $row member_id {}]]
        dict lappend contexts $key [dict get $row row]
    }
    dict for {key ordinals} $contexts {
        lassign $key ds x y family member
        if {$family eq {} && $member eq {}} {
            set suggestions [_identitySuggestions $ds]
            set family [dict get $suggestions family];set member [dict get $suggestions member]
            if {$family eq {} && $member eq {} && [dict get $suggestions ambiguous]} {error {Choose explicit Family/Member variables before displaying this family Dataset}}
        }
        set selected [lsort -integer -unique $ordinals]
        set group [expr {$family ne {} ? $family : $member}]
        if {$group eq {}} {
            set fields [dict create dataset_id $ds x_variable_id $x y_variable_id $y axis left label "Source $ds"]
            if {$scope eq "selected"} {dict set fields source_row_ordinals $selected}
            set planned [list $fields]
        } else {
            set options [dict create dry_run 1 max_members 256 series_prefix builder_context[incr index] label_template {{member}} row_filters [list [dict create filter_variable_id $x predicate is_finite] [dict create filter_variable_id $y predicate is_finite]]]
            if {$family ne {} && $member ne {} && $member ne $family} {dict set options category_variable_id $member;dict set options category_behavior {Split into series};dict set options label_template {{member} / {category}}}
            if {$scope eq "selected"} {dict set options source_row_ordinals $selected}
            set planned [::GX::graphSeriesExpandGroups plot.dataset plot.dataset.xy $ds $x $y $group $options]
        }
        foreach fields $planned {
            set label [dict get $fields label]
            set identityFilters {};set labels {}
            foreach filter [::GX::datasetPublicationV2DictDefault $fields row_filters {}] {
                if {[dict get $filter predicate] eq "exact_equal" && [dict get $filter filter_variable_id] in [list $family $member]} {
                    lappend identityFilters $filter
                    lappend labels "[dict get $filter filter_variable_id]=[_sourceIdentityLabel [dict get $filter value]]"
                }
            }
            if {$labels ne {}} {set label [join $labels { / }]}
            set used 0
            foreach row $rows {
                if {[dict get $row dataset_id] ne $ds || [dict get $row [expr {$useT ? "t_id" : "x_id"}]] ne $x || [dict get $row y_id] ne $y} continue
                set matches 1
                foreach filter $identityFilters {
                    set role [expr {[dict get $filter filter_variable_id] eq $family ? "family" : "member"}]
                    if {![::GX::graphSeriesFilterRowMatch $filter [::GX::datasetPublicationV2DictDefault $row ${role}_value {}]]} {set matches 0;break}
                }
                if {$matches} {incr used}
            }
            if {$used} {append label " · fit $used"}
            if {$label eq {}} {set label {(empty key)}}
            set item [dict create id source_[incr index] dataset_id $ds x_variable_id $x y_variable_id $y axis left kind line_marker label $label source_row_continuity 1 style {line_width 1.0 marker_size 3}]
            foreach field {row_filters source_row_ordinals} {if {[dict exists $fields $field]} {dict set item $field [dict get $fields $field]}}
            lappend result $item
        }
    }
    return $result
}
proc ::GX::InteractiveCurveBuilder::_identitySuggestions {ds} {
    set family {};set member {}
    foreach variable [::GX::datasetVariableSchemaV3 $ds] {
        if {![dict get $variable enabled] || [dict get $variable rank]!=1} continue
        set role [dict get $variable semantic_role]
        if {$role in {family family_identity group_identity}} {lappend family [dict get $variable variable_id]}
        if {$role in {member_identity trace_identity curve_identity sweep_identity identifier}} {lappend member [dict get $variable variable_id]}
    }
    return [dict create family [expr {[llength $family]==1 ? [lindex $family 0] : {}}] member [expr {[llength $member]==1 ? [lindex $member 0] : {}}] ambiguous [expr {[llength $family]>1 || [llength $member]>1}]]
}
proc ::GX::InteractiveCurveBuilder::_uiScope {w} {
    variable ui
    if {![winfo exists $w] || $ui($w,session_token) ne [::GX::interactiveDocumentSessionToken]} {error {Session changed; reopen Curve Builder}}
}
proc ::GX::InteractiveCurveBuilder::_uiProgress {w epoch receipt} {
    variable ui;_uiScope $w
    if {$epoch!=$ui($w,epoch)} {error {Source request cancelled or changed}}
    set ui($w,status) "Reading exact source rows: [dict get $receipt completed_rows]"
}
proc ::GX::InteractiveCurveBuilder::_uiRowValues {row} {
    return [list {} [dict get $row dataset_id] [dict get $row row] [dict get $row family_value] [::GX::datasetPublicationV2DictDefault $row member_value {}] [dict get $row x] [dict get $row y] [::GX::datasetPublicationV2DictDefault $row z {}] [::GX::datasetPublicationV2DictDefault $row t {}]]
}
proc ::GX::InteractiveCurveBuilder::_uiInvalidate {w {clearSelection 0}} {
    variable ui
    if {![info exists ui($w,preview)]} return
    _uiClosePreview $w;set ui($w,preview) {};set ui($w,ordering) {};set ui($w,reviewed) 0
    set ui($w,epoch) [incr ::GX::InteractiveCurveBuilder::epoch]
    if {[winfo exists $w.preview.table]} {$w.preview.table delete [$w.preview.table children {}]}
    if {$clearSelection && [winfo exists $w.points.tree]} {_uiClearSelection $w}
}
proc ::GX::InteractiveCurveBuilder::_uiFilterValues {w role} {
    variable ui
    set ui($w,${role}_value) {};set ui($w,${role}_enabled) 0
    set values {};set diagnostic {No identity variable selected; filter is disabled}
    if {$ui($w,$role) ne {}} {
        set inventory [::GX::datasetProfileDistinct [_session] $ui($w,dataset) $ui($w,$role) {limit 256}]
        set values [dict get $inventory values]
        set diagnostic [expr {[dict get $inventory complete] ? "Canonical values (first [llength $values]); exact entry is supported" : {Bounded/incomplete discovery; enter an exact canonical value}}]
    }
    $w.source.${role}_value configure -values $values
    _uiInvalidate $w 1
    set ui($w,status) "$role: $diagnostic"
}
proc ::GX::InteractiveCurveBuilder::_uiMemberValues {w} {_uiFilterValues $w member}
proc ::GX::InteractiveCurveBuilder::_uiOrderReview {w} {
    variable ui
    if {[catch {
        _uiScope $w
        set receipt [ordering [_uiSelectedRows $w] $ui($w,mode) $ui($w,parameter_mode)]
        set ui($w,ordering) $receipt;set ui($w,reviewed) 0
        set d $w.orderReview;catch {destroy $d};toplevel $d;wm transient $d $w;wm title $d {Original and proposed processing order}
        ttk::label $d.note -text "[dict get $receipt policy]: [dict get $receipt changed_count] moved positions. [join [dict get $receipt warnings] {; }]" -wraplength 730
        pack $d.note -fill x -padx 8 -pady 8
        ttk::treeview $d.rows -columns {position original proposed family member} -show headings -height 12
        foreach {id label width} {position Position 70 original {Original row} 130 proposed {Proposed row} 130 family Family 140 member Member 140} {$d.rows heading $id -text $label;$d.rows column $id -width $width}
        set i 0
        foreach original [dict get $receipt original_rows] proposed [dict get $receipt ordered_rows] {
            $d.rows insert {} end -values [list [incr i] [dict get $original row] [dict get $proposed row] [dict get $proposed family_value] [::GX::datasetPublicationV2DictDefault $proposed member_value {}]]
        }
        ttk::scrollbar $d.scroll -command [list $d.rows yview];$d.rows configure -yscrollcommand [list $d.scroll set]
        pack $d.scroll -side right -fill y;pack $d.rows -fill both -expand 1
        ttk::frame $d.actions
        ttk::button $d.actions.compare -text {Compare connectivity…} -command [list ::GX::InteractiveCurveBuilder::_uiCompareOrder $w]
        ttk::button $d.actions.use -text {Use reviewed order} -command [list ::GX::InteractiveCurveBuilder::_uiOrderAccept $w $receipt]
        ttk::button $d.actions.original -text {Keep original / OFF} -command [list ::GX::InteractiveCurveBuilder::_uiOrderOriginal $w]
        pack $d.actions.compare $d.actions.use $d.actions.original -side left -padx 5;pack $d.actions -pady 8
    } message]} {_uiError $w $message}
}
proc ::GX::InteractiveCurveBuilder::_uiOrderAccept {w receipt} {
    variable ui;_uiScope $w
    if {[dict get $receipt original_rows] ne [_uiSelectedRows $w]} {error {Selection changed; review again}}
    set ui($w,auto_order) 1;set ui($w,ordering) $receipt;set ui($w,reviewed) 1
    destroy $w.orderReview;set ui($w,status) {Reviewed candidate selected. Preview uses only these exact source identities}
}
proc ::GX::InteractiveCurveBuilder::_uiOrderOriginal {w} {variable ui;set ui($w,auto_order) 0;_uiInvalidate $w;catch {destroy $w.orderReview}}
proc ::GX::InteractiveCurveBuilder::_uiCompareOrder {w} {
    variable ui;_uiScope $w
    set series {}
    foreach {key label} {original_rows {Original order} ordered_rows {Proposed order}} {
        set rows [dict get $ui($w,ordering) $key];set first [lindex $rows 0]
        lappend series [dict create label $label x_values [lmap row $rows {dict get $row x}] y_values [lmap row $rows {dict get $row y}] x_unit [dict get [_var [dict get $first dataset_id] [dict get $first x_id]] unit] y_unit [dict get [_var [dict get $first dataset_id] [dict get $first y_id]] unit]]
    }
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
    set f [file tempfile directory];close $f;file delete $directory
    set rendered [::GX::PlotDatasetAPIv3::renderTransientIndependentCurves2D $series {Connections only; measured point values are unchanged} $directory]
    _uiClosePreview $w;set ui($w,preview_dir) $directory
    set ui($w,preview_image) [image create photo -file [dict get $rendered artifact]]
    toplevel .interactive_curve_preview;wm title .interactive_curve_preview {Compare original / proposed connectivity}
    ttk::label .interactive_curve_preview.image -image $ui($w,preview_image);pack .interactive_curve_preview.image
    wm protocol .interactive_curve_preview WM_DELETE_WINDOW [list ::GX::InteractiveCurveBuilder::_uiClosePreview $w]
}
proc ::GX::InteractiveCurveBuilder::_uiMiddleMenus {w} {
    variable ui
    ttk::menubutton $w.actions.options -text Options -menu $w.actions.options.menu
    menu $w.actions.options.menu -tearoff 0 -postcommand [list ::GX::InteractiveCurveBuilder::_uiOptionStates $w]
    $w.actions.options.menu add checkbutton -label {Auto-order points (non-temporal)} -variable ::GX::InteractiveCurveBuilder::ui($w,auto_order) -command [list ::GX::InteractiveCurveBuilder::_uiInvalidate $w]
    $w.actions.options.menu add radiobutton -label {Show full Dataset} -variable ::GX::InteractiveCurveBuilder::ui($w,display_scope) -value full -command [list ::GX::InteractiveCurveBuilder::_uiDisplayScopeChanged $w]
    $w.actions.options.menu add radiobutton -label {Show selected characteristic / subset} -variable ::GX::InteractiveCurveBuilder::ui($w,display_scope) -value selected -command [list ::GX::InteractiveCurveBuilder::_uiDisplayScopeChanged $w]
    $w.actions.options.menu add command -label {Review original / proposed order…} -command [list ::GX::InteractiveCurveBuilder::_uiOrderReview $w]
    $w.actions.options.menu add command -label {Configuration…} -command [list ::GX::configurationModuleDialog viewer.interactive_curve_builder $w]
    $w.actions.options.menu add command -label {Cancel source request} -command [list ::GX::InteractiveCurveBuilder::_uiInvalidate $w]
    pack $w.actions.options -side left -padx 4
    ttk::menubutton $w.actions.workspace -text Workspace -menu $w.actions.workspace.menu
    menu $w.actions.workspace.menu -tearoff 0
    ::GX::sessionWorkspaceViewerMenu $w.actions.workspace.menu curve_builder [dict create current [list ::GX::InteractiveCurveBuilder::_uiWorkspaceCurrent $w] save [list ::GX::InteractiveCurveBuilder::_uiWorkspaceSave $w] close [list ::GX::InteractiveCurveBuilder::_uiClose $w] open ::GX::InteractiveCurveBuilder::open] $w
    pack $w.actions.workspace -side left -padx 4
    ::GX::uiMenuRowAttach $w.actions [pack slaves $w.actions] 2
}
proc ::GX::InteractiveCurveBuilder::_uiDisplayScopeChanged {w} {
    variable ui;_uiScope $w
    _uiClosePreview $w;set ui($w,preview) {}
    $w.preview.table delete [$w.preview.table children {}]
    set ui($w,status) "Source graph scope: $ui($w,display_scope). Fitting selection and reviewed ordering remain unchanged"
}
proc ::GX::InteractiveCurveBuilder::_uiOptionStates {w} {
    variable ui
    set rows [_uiSelectedRows $w]
    if {$rows eq {} && $ui($w,dataset) ne {}} {
        set binding [dict create dataset_id $ui($w,dataset)]
        foreach axis {x y z t} {dict set binding ${axis}_id [expr {$ui($w,mode) eq "2d" && $axis in {z t} ? {} : $ui($w,$axis)}]}
        set rows [list $binding]
    }
    set temporal [expr {$rows ne {} && ![catch {_temporal $rows} value] && $value}]
    $w.actions.options.menu entryconfigure 0 -state [expr {$temporal ? "disabled" : "normal"}]
    if {$temporal && $ui($w,auto_order)} {set ui($w,auto_order) 0;_uiInvalidate $w;set ui($w,status) {Auto-order disabled for temporal axes; measured chronology is authoritative}}
}
