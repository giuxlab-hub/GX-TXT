# SPDX-License-Identifier: GPL-3.0-or-later
# Complete Native3D mesh operations; this module holds no geometry algorithms.
proc ::GX::Workbench3D::meshPairForm {} {
    variable model;variable selection;variable scene
    set choices {};set names {}
    dict for {id record} [dict get $model objects] {
        if {[dict get $record kind] ne "mesh"||[dict get $record locked]} continue
        set label "[dict get $record name] · $id";lappend choices $label;dict set names $label $id
    }
    if {[llength $choices]<2} {error "Select two unlocked complete meshes; tessellate a B-Rep first"}
    set defaults [lrange $choices 0 1];set selected {}
    foreach id $selection {dict for {label item} $names {if {$item eq $id} {lappend selected $label}}}
    if {[llength $selected]>=2} {set defaults [lrange $selected 0 1]}
    set fields [dict create target [dict create type choice label {First mesh} values $choices] tool [dict create type choice label {Second mesh} values $choices] operation [dict create type choice label Operation values {Append Merge Stitch Bridge}] tolerance [dict create type number label "Weld / stitch tolerance or maximum bridge gap ([dict get $model working_unit])" required 1 min 0] name [dict create type string label {Derived object name} required 1]]
    set values [dict create target [lindex $defaults 0] tool [lindex $defaults 1] operation Append tolerance 1e-8 name {Derived mesh}]
    ::GX::uiFieldFormCreate $::GX::Engine3D::window.meshPair "Derive complete mesh — sources preserved" $fields $values [list ::GX::Workbench3D::meshPairApply [::GX::native3DGeometrySceneInfo $scene] $names] $::GX::Engine3D::window
}
proc ::GX::Workbench3D::meshPairApply {captured names values} {
    variable model;variable scene;variable tokens;variable busy;variable selection;variable panel
    if {$busy} {error "Finish the current operation first"}
    if {[::GX::native3DGeometrySceneInfo $scene] ne $captured} {error "Geometry document changed; reopen the mesh operation"}
    set a [dict get $names [dict get $values target]];set b [dict get $names [dict get $values tool]]
    if {$a eq $b} {error "Choose two different source meshes"}
    foreach id [list $a $b] {if {![dict exists $model objects $id]||[dict get $model objects $id kind] ne "mesh"||[dict get $model objects $id locked]} {error "Both sources must be unlocked complete meshes"}}
    set action mesh_[string tolower [dict get $values operation]]
    if {$action eq "mesh_bridge"&&[dict get $values tolerance]<=0} {error "Maximum bridge gap must be positive"}
    set before $model;set priorTokens $tokens;set receipt {};set busy 1
    try {
        set receipt [call $action [dict create base [dict get $tokens $a] tool [dict get $tokens $b] tolerance [dict get $values tolerance]]]
        set id [installObject $receipt [dict get $values name]]
        set sources {};set bindings {}
        foreach source [list $a $b] {dict set sources $source [dict get $before objects $source];foreach binding [dict get $before objects $source source_bindings] {if {$binding ni $bindings} {lappend bindings $binding}}}
        dict set model objects $id source_bindings $bindings
        dict set model objects $id provenance [dict create operation $action parameters [dict remove $values name] source_snapshots $sources kernel NATIVE_3D_GEOMETRY_API_v1 boolean 0]
        commit $before $action [dict remove $values name] [list $a $b] [list $id]
    } on error {message options} {
        set model $before;set tokens $priorTokens
        if {$receipt ne {}&&[catch {call delete [dict create object_token [dict get $receipt object_token]]} cleanup]} {append message "; derived mesh cleanup failed: $cleanup"}
        return -options $options $message
    } finally {set busy 0}
    set selection [list $id];projectSelection
    ::GX::Engine3D::rerender
}
proc ::GX::Workbench3D::meshInspection {action parameters} {
    variable tokens;variable model
    set id [selected];dict set parameters object_token [dict get $tokens $id]
    set result [call $action $parameters]
    set window $::GX::Engine3D::window.meshInspection
    if {[winfo exists $window]} {destroy $window};toplevel $window;wm title $window "Native mesh inspection — $id"
    wm geometry $window 850x450
    ttk::label $window.summary -wraplength 820 -justify left
    ttk::treeview $window.tree -columns {kind identity value} -show headings -selectmode extended
    foreach key {kind identity value} {$window.tree heading $key -text [string totitle $key];$window.tree column $key -width [expr {$key eq "value"?440:170}] -minwidth 120 -stretch 0}
    ttk::scrollbar $window.y -orient vertical -command [list $window.tree yview];$window.tree configure -yscrollcommand [list $window.y set]
    ttk::scrollbar $window.x -orient horizontal -command [list $window.tree xview];$window.tree configure -xscrollcommand [list $window.x set]
    ttk::button $window.close -text Close -command [list destroy $window]
    grid $window.summary -row 0 -column 0 -columnspan 2 -sticky ew -padx 6 -pady 6
    grid $window.tree -row 1 -column 0 -sticky nsew;grid $window.y -row 1 -column 1 -sticky ns
    grid $window.x -row 2 -column 0 -sticky ew;grid $window.close -row 3 -column 0 -columnspan 2 -sticky ew
    grid rowconfigure $window 1 -weight 1;grid columnconfigure $window 0 -weight 1
    if {$action eq "mesh_boundaries"} {
        set omitted [dict get $result loops_truncated]
        foreach edge [dict get $result edges] {$window.tree insert {} end -values [list edge $edge {source vertex indices}]}
        foreach loop [dict get $result loops] {
            if {[dict get $loop truncated]} {set omitted 1}
            foreach index [dict get $loop source_indices] point [dict get $loop world_points] {$window.tree insert {} end -values [list "loop [dict get $loop loop_index]" $index $point]}
        }
        $window.summary configure -text "Complete mesh: [dict get $result edge_count] boundary edges, [dict get $result loop_count] loops. Coordinates: [dict get $model working_unit] in world space. Bounded display: edges omitted=[dict get $result edges_truncated], loop data omitted=$omitted. No geometry was changed."
    } else {
        foreach pair [dict get $result pairs] {$window.tree insert {} end -values [list intersection "[dict get $pair triangle_a] / [dict get $pair triangle_b]" [dict get $pair witness]]}
        $window.summary configure -text "Complete mesh: [dict get $result intersecting_pairs] nonadjacent intersecting triangle pairs. World witnesses: [dict get $model working_unit]. Bounded display omitted=[dict get $result truncated]. No geometry was changed."
    }
    bind $window <Escape> [list destroy $window]
    return $result
}
