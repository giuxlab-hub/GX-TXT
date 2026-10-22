# SPDX-License-Identifier: GPL-3.0-or-later
# Both editing surfaces are clients of CONFIGURATION_API_v1; arrays are drafts.
namespace eval ::GX::ConfigurationEditor {variable values;variable expected;variable session;variable scope;variable status;variable contexts {};variable refresh {};variable catalogRefresh 0}
proc ::GX::configurationModuleEditorBuild {parent module {scope user}} {
    variable ::GX::ConfigurationEditor::values
    variable ::GX::ConfigurationEditor::expected
    variable ::GX::ConfigurationEditor::session
    variable ::GX::ConfigurationEditor::contexts
    if {[dict exists $contexts $parent] && ([dict get $contexts $parent module] ne $module || [dict get $contexts $parent scope] ne $scope)} {set ::GX::ConfigurationEditor::status($parent) {}}
    dict set contexts $parent [dict create module $module scope $scope]
    # Rich forms hold their own unsaved drafts and captured conflict token.
    # A notification must not destroy them while rebuilding the projection.
    foreach child [winfo children $parent] {if {[winfo toplevel $child] ne $child} {destroy $child}}
    set ::GX::ConfigurationEditor::scope($parent) $scope
    ttk::frame $parent.scope
    ttk::label $parent.scope.label -text {Edit scope:}
    ttk::combobox $parent.scope.choice -state readonly -values {user session} -width 12 -textvariable ::GX::ConfigurationEditor::scope($parent)
    bind $parent.scope.choice <<ComboboxSelected>> [list ::GX::configurationModuleEditorScope $parent $module]
    pack $parent.scope.label $parent.scope.choice -side left -padx 4
    pack $parent.scope -fill x -pady 5
    ttk::label $parent.meaning -text {User defaults are global. Session overrides inherit until explicitly changed. Reset applies only to this field and scope.} -wraplength 410
    pack $parent.meaning -fill x -pady 4
    set fields [configurationModuleFields $module];set row 0
    if {$fields eq {}} {ttk::label $parent.none -text {No configurable settings declared.};pack $parent.none -anchor w;return}
    dict for {id descriptor} $fields {
        if {![datasetPublicationV2DictDefault $descriptor visible 1]} continue
        set resolved [configurationResolve $id];set allowed [expr {$scope in [dict get $resolved scopes] && ($scope ne "session" || $::GX::currentSession ne {})}]
        set current [expr {$scope eq "user" ? [dict get $resolved user] : [dict get $resolved effective]}]
        set key "$parent,$scope,$id"
        if {![info exists values($key)] || $values($key) eq $expected($key)} {
            set values($key) $current;set expected($key) $current;set session($key) [::GX::_configurationSessionToken]
        }
        ttk::labelframe $parent.f$row -text [dict get $descriptor label] -padding 6
        set f $parent.f$row;pack $f -fill x -pady 4
        set effective [dict get $resolved effective]
        if {[dict exists $descriptor structured_fields]} {set effective {structured settings}}
        if {[dict get $descriptor module_type] eq "table"} {set effective "[llength [datasetPublicationV2DictDefault $effective rows {}]] table rows"}
        ttk::label $f.effective -text "Effective: $effective · [dict get $resolved origin]\nApplies: [datasetPublicationV2DictDefault $descriptor application next_invocation]" -wraplength 410
        pack $f.effective -fill x
        if {!$allowed} {
            ttk::label $f.unavailable -text [expr {$scope eq "session" && $::GX::currentSession eq {} ? {Open a Session to edit overrides.} : "Available scopes: [join [dict get $resolved scopes] {, }]."}] -wraplength 410
            pack $f.unavailable -fill x;incr row;continue
        }
        if {[dict exists $descriptor structured_fields]} {
            ttk::button $f.edit -text "Edit [dict get $descriptor label]…" -command [list ::GX::configurationStructuredEditor $parent $scope $id]
            pack $f.edit -anchor w -pady 4
        } elseif {[dict get $descriptor module_type] eq "table"} {
            ttk::button $f.edit -text {Edit table…} -command [list ::GX::configurationTableEditor $parent $scope $id]
            pack $f.edit -anchor w
        } elseif {[dict get $descriptor module_type] eq "numeric_operation_browser"} {
            ttk::button $f.edit -text {Browse numeric operations…} -command [list ::GX::numericExpressionBrowserOpen $module]
            pack $f.edit -anchor w
        } else {
            set descriptor [configurationEditorDescriptor $descriptor]
            uiFieldCreate $f.value $descriptor ::GX::ConfigurationEditor::values($key)
            pack $f.value -fill x
            if {[datasetPublicationV2DictDefault $descriptor readonly 0]} {setWidgetTreeState $f.value 0}
        }
        if {[dict exists $descriptor description]} {ttk::label $f.help -text [dict get $descriptor description] -wraplength 410;pack $f.help -fill x}
        if {[datasetPublicationV2DictDefault $descriptor readonly 0] && [winfo exists $f.edit]} {$f.edit state disabled}
        ttk::frame $f.actions;pack $f.actions -fill x
        ttk::button $f.actions.reset -text [expr {$scope eq "session" && "user" in [dict get $resolved scopes] ? {Reset to User default} : {Reset to module default}}] -command [list ::GX::configurationModuleEditorReset $parent $scope $id]
        pack $f.actions.reset -side left
        if {[datasetPublicationV2DictDefault $descriptor readonly 0]} {$f.actions.reset state disabled}
        incr row
    }
    ttk::frame $parent.actions;pack $parent.actions -fill x -pady 8 -before $parent.meaning
    ttk::button $parent.actions.apply -text [expr {$scope eq "user" ? {Save User defaults} : {Save Session overrides}}] -command [list ::GX::configurationModuleEditorSave $parent $scope]
    ttk::button $parent.actions.reload -text {Reload / discard drafts} -command [list ::GX::configurationModuleEditorReload $parent $module $scope]
    pack $parent.actions.apply $parent.actions.reload -side left -padx 3
    if {![info exists ::GX::ConfigurationEditor::status($parent)]} {set ::GX::ConfigurationEditor::status($parent) {}}
    ttk::label $parent.status -textvariable ::GX::ConfigurationEditor::status($parent) -wraplength 410
    pack $parent.status -fill x -before $parent.meaning
    configurationEditorScrollBindings $parent
}
proc ::GX::configurationEditorScrollBindings {widget} {
    if {[winfo class $widget] in {TButton TEntry TCombobox TCheckbutton Treeview}} {bind $widget <FocusIn> +[list ::GX::configurationEditorSee $widget]}
    foreach child [winfo children $widget] {configurationEditorScrollBindings $child}
}
proc ::GX::configurationEditorSee {widget} {
    set parent [winfo parent $widget]
    while {$parent ne {}} {
        if {[winfo class $parent] eq "Canvas" && [winfo exists $parent.content]} {
            uiFieldScrollSee $parent $parent.content $widget;return
        }
        set parent [winfo parent $parent]
    }
}
proc ::GX::configurationEditorDescriptor {descriptor} {
    set type [dict get $descriptor module_type];set module [dict get $descriptor module_id];set key [dict get $descriptor module_key]
    set choices {}
    switch $type {
        dataset {set choices [datasetRegistryIds]}
        variable {
            set ds [datasetSelectionSourceDataset $module [moduleConfigField $module $key source primary]]
            if {$ds ne {}} {set choices [datasetVariableNamesById $ds]}
        }
        selection {set choices [datasetSelectionCompatibleIds $module $key]}
        model {set choices [scalarModelValues $module $key]}
        registered_script {foreach s [scriptRegistryList] {lappend choices "[dict get $s scope]:[dict get $s id]"}}
        analysis_definition {set choices [analysisDefinitionIdsForConfig $module $key]}
        unit {set choices [unitRegistryList]}
        temporal_set {set choices [temporalSetCompatibleIds $module $key]}
    }
    if {[dict exists $descriptor choices_provider]} {set choices [uplevel #0 [dict get $descriptor choices_provider]]}
    if {$type in {dataset variable selection model registered_script analysis_definition unit temporal_set} || [dict exists $descriptor choices_provider]} {
        dict set descriptor type choice;dict set descriptor values [lsort -unique [linsert $choices 0 {}]]
    }
    return $descriptor
}
proc ::GX::configurationModuleEditorScope {parent module} {configurationModuleEditorBuild $parent $module $::GX::ConfigurationEditor::scope($parent)}
proc ::GX::configurationModuleEditorReset {parent scope id} {
    set key "$parent,$scope,$id";set resolved [configurationResolve $id]
    if {$scope eq "session" && "user" in [dict get $resolved scopes]} {
        set ::GX::ConfigurationEditor::values($key) [dict get $resolved user]
        set ::GX::ConfigurationEditor::session($key,clear) 1
    } else {
        set value [dict get $resolved factory]
        set descriptor [dict get [configurationFields] $id]
        if {[dict get $descriptor module_type] eq "table" && $value eq {}} {set value [repeatableConfigDefaultSnapshot [dict get $descriptor module_id] [dict get $descriptor module_key]]}
        set ::GX::ConfigurationEditor::values($key) $value
        unset -nocomplain ::GX::ConfigurationEditor::session($key,clear)
    }
}
proc ::GX::configurationModuleEditorPending {parent scope} {
    variable ::GX::ConfigurationEditor::values
    variable ::GX::ConfigurationEditor::expected
    variable ::GX::ConfigurationEditor::session
    set result {}
    foreach key [array names values "$parent,$scope,*"] {
        set id [string range $key [string length "$parent,$scope,"] end]
        set clear [expr {[info exists session($key,clear)] && $session($key,clear)}]
        if {$values($key) eq $expected($key) && !$clear} continue
        lappend result [dict create id $id scope $scope value [configurationValidate $id $values($key)] expected $expected($key) session_token $session($key) clear $clear]
    }
    return $result
}
proc ::GX::configurationModuleEditorSave {parent scope} {
    if {[catch {configurationCommit [configurationModuleEditorPending $parent $scope]} message]} {
        set ::GX::ConfigurationEditor::status($parent) $message;return 0
    }
    configurationModuleEditorAccept $parent $scope
    set ::GX::ConfigurationEditor::status($parent) {Saved through CORE.}
    return 1
}
proc ::GX::configurationModuleEditorAccept {parent scope} {
    foreach key [array names ::GX::ConfigurationEditor::values "$parent,$scope,*"] {
        set ::GX::ConfigurationEditor::expected($key) $::GX::ConfigurationEditor::values($key)
        unset -nocomplain ::GX::ConfigurationEditor::session($key,clear)
    }
}
proc ::GX::configurationModuleEditorReload {parent module scope} {
    array unset ::GX::ConfigurationEditor::values "$parent,$scope,*"
    configurationModuleEditorBuild $parent $module $scope
}
proc ::GX::configurationStructuredEditor {parent scope id} {
    set descriptor [dict get [configurationFields] $id]
    set key "$parent,$scope,$id"
    set fields [uplevel #0 [dict get $descriptor structured_fields]]
    set values [configurationValidate $id $::GX::ConfigurationEditor::values($key)]
    uiFieldFormCreate $parent.structured [dict get $descriptor label] $fields $values [list ::GX::configurationDraftApply $parent $scope $id $::GX::ConfigurationEditor::expected($key) $::GX::ConfigurationEditor::session($key)] [winfo toplevel $parent]
}
proc ::GX::configurationDraftApply {parent scope id starting token values} {
    if {$starting ne [configurationScopedValue $id $scope]} {error {Configuration conflict: settings changed while this form was open. Your form is preserved; close and reopen to reconcile.}}
    if {$scope eq "session" && $token ne [_configurationSessionToken]} {error {Session changed while this form was open; reopen settings.}}
    configurationStructuredDraft $parent $scope $id $values
}
proc ::GX::configurationStructuredDraft {parent scope id values} {
    set ::GX::ConfigurationEditor::values($parent,$scope,$id) [configurationValidate $id $values]
}
proc ::GX::configurationModuleDialog {module {parent .}} {
    configurationModuleDiscover $module
    set w .gxModuleSettings_[string map {. _ - _} $module]
    if {[winfo exists $w]} {raise $w;return $w}
    toplevel $w;wm title $w "Settings — [moduleField $module name $module]";wm transient $w $parent;wm geometry $w 620x660
    canvas $w.viewport -highlightthickness 0;ttk::scrollbar $w.scroll -command [list $w.viewport yview]
    $w.viewport configure -yscrollcommand [list $w.scroll set]
    ttk::frame $w.viewport.content -padding 8
    $w.viewport create window 0 0 -window $w.viewport.content -anchor nw -tags content
    bind $w.viewport <Configure> [list $w.viewport itemconfigure content -width %w]
    bind $w.viewport.content <Configure> [list $w.viewport configure -scrollregion [list 0 0 %w %h]]
    pack $w.scroll -side right -fill y;pack $w.viewport -fill both -expand 1
    configurationModuleEditorBuild $w.viewport.content $module
    return $w
}
proc ::GX::configurationEditorChanged {id} {
    if {$id eq {}} {set ::GX::ConfigurationEditor::catalogRefresh 1}
    if {$::GX::ConfigurationEditor::refresh ne {}} return
    set ::GX::ConfigurationEditor::refresh [after idle ::GX::configurationEditorRefresh]
}
proc ::GX::configurationEditorRefresh {} {
    set ::GX::ConfigurationEditor::refresh {}
    if {$::GX::ConfigurationEditor::catalogRefresh} {set ::GX::ConfigurationEditor::catalogRefresh 0;configurationModulesReload}
    dict for {parent context} $::GX::ConfigurationEditor::contexts {
        if {[winfo exists $parent]} {configurationModuleEditorBuild $parent [dict get $context module] [dict get $context scope]}
    }
}
proc ::GX::configurationModulesPending {} {
    set result {}
    foreach category {services exports} {
        set parent .top.nb.configuration.sections.modules.kinds.$category.browser.split.detail.viewport.content.editor
        lappend result {*}[configurationModuleEditorPending $parent user]
    }
    return $result
}
proc ::GX::configurationModulesSaved {} {
    foreach category {services exports} {
        configurationModuleEditorAccept .top.nb.configuration.sections.modules.kinds.$category.browser.split.detail.viewport.content.editor user
    }
    configurationEditorChanged {}
}

namespace eval ::GX::ConfigurationEditor {variable tables {};variable tableSerial 0}
proc ::GX::configurationTableEditor {parent scope id} {
    variable ::GX::ConfigurationEditor::tables
    set w $parent.table;catch {destroy $w};toplevel $w;wm title $w {Module Configuration table};wm geometry $w 740x480
    set descriptor [dict get [configurationFields] $id]
    set module [dict get $descriptor module_id];set key [dict get $descriptor module_key]
    dict set tables $w [dict create parent $parent scope $scope id $id module $module key $key snapshot $::GX::ConfigurationEditor::values($parent,$scope,$id) expected $::GX::ConfigurationEditor::expected($parent,$scope,$id) token $::GX::ConfigurationEditor::session($parent,$scope,$id)]
    set columns [repeatableConfigColumns $module $key]
    ttk::treeview $w.rows -columns $columns -show {tree headings} -selectmode browse
    $w.rows heading #0 -text Row;$w.rows column #0 -width 90 -stretch 0
    foreach column $columns {$w.rows heading $column -text [repeatableColumnField $module $key $column label $column];$w.rows column $column -width 120 -stretch 0}
    ttk::scrollbar $w.x -orient horizontal -command [list $w.rows xview];ttk::scrollbar $w.y -command [list $w.rows yview]
    $w.rows configure -xscrollcommand [list $w.x set] -yscrollcommand [list $w.y set]
    pack $w.x -side bottom -fill x;pack $w.y -side right -fill y
    ttk::frame $w.actions;pack $w.actions -side bottom -fill x
    foreach {label action} {{Add row} add {Edit row…} edit {Remove row} remove {Apply to draft} apply Close close} {
        ttk::button $w.actions.$action -text $label -command [list ::GX::configurationTableAction $w $action]
        pack $w.actions.$action -side left -padx 3 -pady 6
    }
    ttk::label $w.status -text {Changes remain drafts until Save User defaults / Save Session overrides.};pack $w.status -side bottom -fill x
    pack $w.rows -fill both -expand 1
    configurationTableRefresh $w
    return $w
}
proc ::GX::configurationTableRefresh {w} {
    set table [dict get $::GX::ConfigurationEditor::tables $w]
    $w.rows delete [$w.rows children {}]
    foreach row [dict get $table snapshot rows] {
        set values [lmap column [repeatableConfigColumns [dict get $table module] [dict get $table key]] {dict get $row values $column}]
        $w.rows insert {} end -id [dict get $row id] -text [dict get $row id] -values $values
    }
}
proc ::GX::configurationTableAction {w action} {
    variable ::GX::ConfigurationEditor::tables
    if {[catch {
        set table [dict get $tables $w];set module [dict get $table module];set key [dict get $table key]
        set rows [dict get $table snapshot rows]
        switch $action {
            close {destroy $w;dict unset tables $w}
            apply {
                configurationDraftApply [dict get $table parent] [dict get $table scope] [dict get $table id] [dict get $table expected] [dict get $table token] [dict get $table snapshot]
                $w.status configure -text {Table validated and staged. Save its scope to commit.}
            }
            add {
                set id [repeatableConfigNextRowId $module $key];set values {}
                foreach column [repeatableConfigColumns $module $key] {dict set values $column [repeatableConfigDefaultForColumn $module $key $column]}
                lappend rows [dict create id $id values $values]
                dict set tables $w snapshot rows $rows;configurationTableRefresh $w
                $w.rows selection set $id
                configurationTableAction $w edit
            }
            edit - remove {
                set id [$w.rows selection];if {[llength $id]!=1} {error {Select one row}}
                set index 0
                foreach row $rows {if {[dict get $row id] eq $id} break;incr index}
                if {$action eq "remove"} {dict set tables $w snapshot rows [lreplace $rows $index $index];configurationTableRefresh $w;return}
                set fields {}
                foreach column [repeatableConfigColumns $module $key] {
                    set type [repeatableColumnField $module $key $column type string]
                    set descriptor [dict create type $type label [repeatableColumnField $module $key $column label $column] default [repeatableConfigDefaultForColumn $module $key $column]]
                    foreach option {required min max alpha} {set v [repeatableColumnField $module $key $column $option {}];if {$v ne {}} {dict set descriptor $option $v}}
                    set choices {}
                    switch $type {
                        variable {set choices [repeatableVariableValues $module $key $column]}
                        model {set choices [repeatableModelValues $module $key $column]}
                        choice {set choices [splitList [repeatableColumnField $module $key $column values {}]]}
                    }
                    if {$type ni [dict get [uiFieldApiInfo] types]} {dict set descriptor type string}
                    if {$type in {variable model choice}} {dict set descriptor type choice;dict set descriptor values $choices}
                    dict set fields $column $descriptor
                }
                uiFieldFormCreate $w.row "Table row $id" $fields [dict get $row values] [list ::GX::configurationTableRowDraft $w $id] $w
            }
        }
    } message]} {if {[winfo exists $w.status]} {$w.status configure -text $message}}
}
proc ::GX::configurationTableRowDraft {w id values} {
    set rows [dict get $::GX::ConfigurationEditor::tables $w snapshot rows];set index 0
    foreach row $rows {if {[dict get $row id] eq $id} break;incr index}
    dict set ::GX::ConfigurationEditor::tables $w snapshot rows [lreplace $rows $index $index [dict create id $id values $values]]
    configurationTableRefresh $w
}
