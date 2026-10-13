# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::Workbench3D {variable organizationNative {};variable organizationScene {}}
proc ::GX::Workbench3D::organizationCollection {kind} {return [dict get {selection_set selection_sets layer layers saved_view views} $kind]}
proc ::GX::Workbench3D::organizationMemberState {member} {
    variable model
    set id [dict get $member object_id]
    if {![dict exists $model objects $id]} {return missing}
    if {[dict get $model objects $id geometry] ne [dict get $member source_geometry]} {return stale}
    return current
}
proc ::GX::Workbench3D::organizationCaptureMembers {} {
    variable selection;variable model
    set members {};foreach id $selection {if {![dict exists $model objects $id]} {error "Select accepted geometry objects"};lappend members [dict create object_id $id source_geometry [dict get $model objects $id geometry]]}
    if {$members eq {}} {error "Select one or more accepted objects"};return $members
}
proc ::GX::Workbench3D::organizationSync {} {
    variable scene;variable model;variable tokens;variable organizationNative;variable organizationScene;variable module;variable provider
    if {$scene ne $organizationScene} {set organizationNative {};set organizationScene $scene}
    dict for {key native} $organizationNative {lassign $key kind id;call ${kind}_delete [dict create id $native]};set organizationNative {}
    foreach kind {selection_set layer saved_view} {
        set collection [organizationCollection $kind]
        if {![dict exists $model $collection]} {dict set model $collection {}}
        dict for {id record} [dict get $model $collection] {
            set request [dict create name [dict get $record name]];set valid 1;set members {}
            if {$kind eq "saved_view"} {
                set visibility {};dict for {object visible} [dict get $record visibility] {if {![dict exists $tokens $object]} {set valid 0;break};dict set visibility [dict get $tokens $object] $visible}
                if {!$valid} continue
                dict set request visibility $visibility;dict set request view [dict get $record view];dict set request working_unit [dict get $record working_unit]
            } elseif {$kind eq "selection_set"} {
                foreach member [dict get $record members] {if {[organizationMemberState $member] ne "current"} {set valid 0;break};set nativeMember [dict create object_token [dict get $tokens [dict get $member object_id]]];if {[dict exists $member anchor]} {dict set nativeMember anchor [dict get $member anchor]};lappend members $nativeMember}
                if {!$valid} continue
                dict set request members $members
            } else {
                foreach key {visible selectable locked opacity color} {dict set request $key [dict get $record $key]}
            }
            set native [dict get [call ${kind}_create $request] id];dict set organizationNative [list $kind $id] $native
            if {$kind eq "layer"} {
                set members {};foreach object [dict get $record members] {if {![dict exists $tokens $object]} continue;lappend members [dict create object_token [dict get $tokens $object]]
                    if {$object ni [::GX::viewerLayerIds $module $provider]} continue
                    set presentation [::GX::viewerLayerGet $module $provider $object]
                    dict set presentation visible [expr {[dict get $record visible]&&[dict get $model objects $object visible]}]
                    dict set presentation opacity [dict get $record opacity];dict set presentation base_color [join [dict get $record color] {;}]
                    ::GX::viewerLayerSet $module $provider $object $presentation
                }
                call layer_assign [dict create id $native members $members]
            }
        }
    }
    dict for {id record} [dict get $model objects] {call geometry_role [dict create object_token [dict get $tokens $id] role [::GX::datasetPublicationV2DictDefault $record geometry_role regular]]}
}
proc ::GX::Workbench3D::organizationRefresh {} {
    variable model
    set d $::GX::Engine3D::window.organization
    if {![winfo exists $d.tree]} return
    set chosen [$d.tree selection];$d.tree delete [$d.tree children {}]
    foreach kind {selection_set layer saved_view} {
        dict for {id record} [dict get $model [organizationCollection $kind]] {
            set status current;set count 0
            if {$kind eq "selection_set"} {set count [llength [dict get $record members]];foreach member [dict get $record members] {set state [organizationMemberState $member];if {$state ne "current"} {set status $state}}} elseif {$kind eq "layer"} {set count [llength [dict get $record members]]} else {if {[dict get $record working_unit] ne [dict get $model working_unit]} {set status {different unit}};dict for {object visible} [dict get $record visibility] {if {![dict exists $model objects $object]} {set status missing}}}
            $d.tree insert {} end -id "$kind:$id" -values [list $kind $id [dict get $record name] $count $status]
        }
    }
    foreach row $chosen {if {[$d.tree exists $row]} {$d.tree selection add $row}}
    ::GX::uiFieldInspectionColumnsFit $d.tree
}
proc ::GX::Workbench3D::organizationPanel {} {
    set d $::GX::Engine3D::window.organization
    if {[winfo exists $d]} {raise $d;organizationRefresh;return}
    toplevel $d;wm title $d "Selection Sets, Layers and Saved Views";wm transient $d $::GX::Engine3D::window
    ttk::label $d.note -text {Groups transform geometry. Selection Sets capture stable reusable references. Layers control presentation. Saved Views restore camera, clipping and plane without changing geometry. Stale references require explicit recapture.} -wraplength 760 -justify left;pack $d.note -fill x -padx 10 -pady 8
    $d.note configure -font TkDefaultFont
    bind $d.note <Configure> [list ::GX::_workbenchExtensionActionWrap $d.note %w]
    ttk::treeview $d.tree -columns {kind id name members state} -show headings -selectmode browse -height 11
    foreach {key label width} {kind Kind 150 id ID 140 name Name 240 members Members 90 state State 160} {$d.tree heading $key -text $label;$d.tree column $key -width $width -stretch 0}
    ttk::scrollbar $d.x -orient horizontal -command [list $d.tree xview];$d.tree configure -xscrollcommand [list $d.x set];pack $d.x -side bottom -fill x;pack $d.tree -fill both -expand 1
    ttk::frame $d.actions;pack $d.actions -side bottom -fill x -padx 8 -pady 6 -before $d.tree
    foreach {key label action} {set {New Selection Set…} selection_set layer {New Layer…} layer view {Capture Saved View…} saved_view edit {Edit / recapture…} edit apply {Activate / restore} apply remove Remove remove} {ttk::button $d.actions.$key -text $label -command [list ::GX::Workbench3D::safe [list ::GX::Workbench3D::organizationAction $action]];pack $d.actions.$key -side left}
    bind $d.actions <Configure> [list ::GX::uiFieldControlsLayout $d.actions %w]
    bind $d.tree <Configure> [list ::GX::uiFieldInspectionColumnsSchedule $d.tree]
    wm geometry $d 940x440;wm minsize $d 620 300;bind $d <Escape> [list destroy $d];organizationRefresh
}
proc ::GX::Workbench3D::organizationAction {action} {
    variable model;variable selection;variable module;variable provider;variable organizationNative;variable panel
    set d $::GX::Engine3D::window.organization;set id {};set kind $action
    if {$action in {edit apply remove}} {set rows [$d.tree selection];if {[llength $rows]!=1} {error "Select one organization record"};lassign [split [lindex $rows 0] :] kind id}
    set collection [organizationCollection $kind]
    if {$action eq "remove"} {set before $model;dict unset model $collection $id;commit $before delete_$kind [dict create id $id] {} {};organizationRefresh;return}
    if {$action eq "apply"} {
        if {$kind eq "layer"} {error "Layer presentation applies immediately; use Edit to change it"}
        if {![dict exists $organizationNative [list $kind $id]]} {error "Record has stale/missing references; recapture it explicitly"}
        set native [dict get $organizationNative [list $kind $id]]
        if {$kind eq "selection_set"} {call selection_set_activate [dict create id $native mode replace];set selection [lmap member [dict get $model $collection $id members] {dict get $member object_id}];$panel.objects selection set $selection;return}
        set receipt [call saved_view_restore [dict create id $native working_unit [dict get $model working_unit]]];set before $model
        foreach object [dict keys [::GX::datasetPublicationV2DictDefault [dict get $model $collection $id] object_styles {}]] {if {![dict exists $model objects $object]} {error "Saved view has missing object $object"}}
        foreach layer [dict keys [::GX::datasetPublicationV2DictDefault [dict get $model $collection $id] layer_presentation {}]] {if {![dict exists $model layers $layer]} {error "Saved view has missing Layer $layer"}}
        ::GX::viewerSceneSet $module $provider [dict get $receipt view]
        dict for {object visible} [dict get $model $collection $id visibility] {dict set model objects $object visible $visible}
        dict for {object style} [::GX::datasetPublicationV2DictDefault [dict get $model $collection $id] object_styles {}] {if {![dict exists $model objects $object]} {error "Saved view has missing object $object"};dict set model objects $object style $style}
        dict for {layer fields} [::GX::datasetPublicationV2DictDefault [dict get $model $collection $id] layer_presentation {}] {if {![dict exists $model layers $layer]} {error "Saved view has missing Layer $layer"};dict for {key value} $fields {dict set model layers $layer $key $value}}
        dict set model view [dict get $receipt view]
        foreach {field key} {cameraPosition camera_position cameraTarget camera_target cameraUp camera_up planeOrigin working_plane_origin planeNormal working_plane_normal planeU working_plane_u_axis} {set ::GX::Engine3D::$field [dict get $receipt view $key]}
        commit $before restore_saved_view [dict create id $id] {} {};::GX::Engine3D::rerender;return
    }
    set fields [dict create name {type string label Name required 1} recapture {type boolean label {Replace references from current selection / view}}]
    set values [dict create name [string totitle [string map {_ { }} $kind]] recapture [expr {$id eq {}}]]
    if {$id ne {}} {dict set values name [dict get $model $collection $id name]}
    if {$kind eq "selection_set"} {
        dict set fields member_kind {type choice label {Capture whole objects or B-Rep sub-object anchors} values {object brep_vertex brep_edge brep_face}}
        dict set fields index {type integer min 0 label {Sub-object index (zero based)}}
        foreach {key label} {parameter {Edge parameter} u {Face U parameter} v {Face V parameter}} {dict set fields $key [dict create type number label $label]}
        dict set values member_kind object;dict set values index 0;foreach key {parameter u v} {dict set values $key 0}
    }
    if {$kind eq "layer"} {foreach {key spec default} {visible {type boolean label Visible} 1 selectable {type boolean label Selectable} 1 locked {type boolean label {Lock geometry edits}} 0 opacity {type number min 0 max 1 label Opacity} 1 color {type color label {Layer color} alpha 0} #C7D1E6} {dict set fields $key $spec;set value $default;if {$id ne {}} {set value [dict get $model layers $id $key];if {$key eq "color"} {set value [::GX::uiFieldColorFromRGBA [concat $value 1]]}};dict set values $key $value}}
    ::GX::uiFieldFormCreate $d.parameters "[string totitle $kind] parameters" $fields $values [list ::GX::Workbench3D::organizationApply $kind $id] $d
}
proc ::GX::Workbench3D::organizationApply {kind id values} {
    variable model;variable module;variable provider
    set before $model;set collection [organizationCollection $kind]
    if {$id eq {}} {set id [nextId next_organization $kind]}
    set record [::GX::datasetPublicationV2DictDefault [dict get $model $collection] $id {}];dict set record name [dict get $values name]
    if {[dict get $values recapture]||![dict exists $model $collection $id]} {
        if {$kind eq "saved_view"} {
            dict set record view [::GX::viewerSceneGet $module $provider];dict set record working_unit [dict get $model working_unit];set visibility {};set styles {}
            dict for {object info} [dict get $model objects] {dict set visibility $object [dict get $info visible];dict set styles $object [dict get $info style]};dict set record visibility $visibility;dict set record object_styles $styles
            set layers {};dict for {layer info} [dict get $model layers] {foreach key {visible opacity color} {dict set layers $layer $key [dict get $info $key]}};dict set record layer_presentation $layers
        } elseif {$kind eq "selection_set"} {
            set members [organizationCaptureMembers];set captured {}
            foreach member $members {
                if {[dict get $values member_kind] ne "object"} {
                    set anchor [dict create kind [dict get $values member_kind] index [dict get $values index]]
                    foreach key {parameter u v} {dict set anchor $key [dict get $values $key]}
                    call anchor_describe [dict create object_token [dict get $::GX::Workbench3D::tokens [dict get $member object_id]] anchor $anchor]
                    dict set member anchor $anchor
                };lappend captured $member
            };dict set record members $captured
        } else {dict set record members [lmap member [organizationCaptureMembers] {dict get $member object_id}]}
    }
    if {$kind eq "layer"} {foreach key {visible selectable locked opacity} {dict set record $key [dict get $values $key]};dict set record color [lrange [::GX::uiFieldColorToRGBA [dict get $values color]] 0 2]}
    dict set model $collection $id $record
    try {commit $before edit_$kind [dict create id $id parameters $values] {} [list $id]} on error {message options} {set model $before;return -options $options $message}
    organizationRefresh;::GX::Engine3D::rerender;return $id
}
rename ::GX::Workbench3D::refresh ::GX::Workbench3D::refresh_organization_base
proc ::GX::Workbench3D::refresh {} {refresh_organization_base;organizationSync;organizationRefresh}
rename ::GX::Workbench3D::publish ::GX::Workbench3D::publish_organization_base
proc ::GX::Workbench3D::publish {} {variable model;set id [selected];if {[::GX::datasetPublicationV2DictDefault [dict get $model objects $id] geometry_role regular] ne "regular"} {error "Reference/construction geometry is excluded from normal Dataset publication; make an explicit regular copy first"};tailcall publish_organization_base}
rename ::GX::Workbench3D::detailsForm ::GX::Workbench3D::detailsForm_organization_base
proc ::GX::Workbench3D::detailsForm {} {
    variable selection;variable model
    detailsForm_organization_base
    set id [lindex $selection 0];set section [expr {[dict exists $model objects $id] ? "objects" : "profiles"}]
    set d $::GX::Engine3D::window.details;set form [dict get $::GX::UiField::forms $d]
    set fields [dict get $form fields];dict set fields geometry_role {type choice label {Scientific geometry role} values {regular construction reference}}
    set values {};foreach key [dict keys [dict get $form fields]] {dict set values $key $::GX::UiField::formValues($d,$key)};dict set values geometry_role [::GX::datasetPublicationV2DictDefault [dict get $model $section $id] geometry_role [expr {$section eq "objects" ? "regular" : "construction"}]]
    destroy $d
    ::GX::uiFieldFormCreate $d "Details — $id" $fields $values [list ::GX::Workbench3D::detailsApply $section $id] $::GX::Engine3D::window
}
rename ::GX::Workbench3D::detailsApply ::GX::Workbench3D::detailsApply_organization_base
proc ::GX::Workbench3D::detailsApply {section id values} {
    variable model
    if {[catch {dict size [dict get $values attributes]}]} {error "Attributes must contain key/value pairs"}
    set before $model;set rgba [::GX::uiFieldColorToRGBA [dict get $values color]]
    foreach key {name visible locked geometry_role} {dict set model $section $id $key [dict get $values $key]}
    dict set model $section $id attrs [dict get $values attributes]
    dict set model $section $id style base_color [join [lrange $rgba 0 2] {;}];dict set model $section $id style opacity [lindex $rgba 3]
    try {commit $before set_attributes [dict remove $values color] [list $id] [list $id]} on error {message options} {set model $before;return -options $options $message}
    ::GX::Engine3D::rerender
}
rename ::GX::Workbench3D::buildPanel ::GX::Workbench3D::buildPanel_organization_base
proc ::GX::Workbench3D::buildPanel {window} {
    variable panel;buildPanel_organization_base $window
    ttk::button $panel.organization -text "Selection Sets / Layers / Saved Views…" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::organizationPanel];pack $panel.organization -fill x -before $panel.status
    ttk::button $panel.exportGeometry -text "Export geometry / unit sidecar…" -command [list ::GX::Workbench3D::safe ::GX::Workbench3D::geometryExportOpen];pack $panel.exportGeometry -fill x -before $panel.status
}
proc ::GX::Workbench3D::geometryExportContext {} {
    variable model;variable document
    set id [selected];set context [extensionContext]
    dict set context presentation_snapshot [dict create api_id NATIVE3D_GEOMETRY_EXPORT_SNAPSHOT_v1 api_version 1 document_id $document working_unit [dict get $model working_unit] object_id $id object [dict get $model objects $id]]
    return $context
}
proc ::GX::Workbench3D::geometryExportOpen {} {::GX::workbenchExtensionExportDialog $::GX::Engine3D::window.geometryExport [geometryExportContext] $::GX::Engine3D::window}
proc ::GX::Workbench3D::organizationSelectable {id} {
    variable model
    foreach layer [dict values [::GX::datasetPublicationV2DictDefault $model layers {}]] {if {$id in [dict get $layer members]&&![dict get $layer selectable]} {return 0}};return 1
}
rename ::GX::Workbench3D::hostSelection ::GX::Workbench3D::hostSelection_organization_base
proc ::GX::Workbench3D::hostSelection {pick} {if {![organizationSelectable [dict get $pick layer_id]]} {set ::GX::Workbench3D::status "Object is not selectable in its Layer";return};tailcall hostSelection_organization_base $pick}
rename ::GX::Workbench3D::selectTree ::GX::Workbench3D::selectTree_organization_base
proc ::GX::Workbench3D::selectTree {} {
    variable panel
    set actual [$panel.objects selection];set wanted [lmap id $actual {if {![organizationSelectable $id]} continue;set id}]
    if {$wanted ne $actual} {$panel.objects selection set $wanted}
    selectTree_organization_base
}
