# SPDX-License-Identifier: GPL-3.0-or-later
# Transient pair-table draft under the existing Axes dialog. PlotSpec v2 remains
# the sole persisted axis owner; UI Field owns table/fonts/clipboard/layout.
namespace eval ::GX::AxisTickEditor {variable state;array set state {}}
proc ::GX::axisTickDraftInit {axes ref shared parent} {
    variable ::GX::AxisTickEditor::state
    set state($axes,ref) $ref;set state($axes,pairs) {}
    if {[dict get $shared tick_positions] ne {}} {set state($axes,pairs) [::GX::PlotDatasetAPIv2::_axisTickPairs $shared {X axis}]}
    set state($axes,unit) [dict get $shared display_unit]
    set path [::GX::PlotDatasetAPIv2::_specPath $ref]
    set state($axes,stamp) [expr {[file isfile $path]?[sha256File $path]:{absent}}]
    set state($axes,summary) {};set state($axes,frame) $parent
    ttk::labelframe $parent -text {Custom X tick captions} -padding 6
    ttk::label $parent.summary -textvariable ::GX::AxisTickEditor::state($axes,summary) -justify left -wraplength 650
    ttk::button $parent.edit -text {Edit pairs…} -command [list ::GX::axisTickEditorOpen $axes]
    pack $parent.edit -side left -padx 5
    pack $parent.summary -side left -fill x -expand 1
    native2DViewportTooltip $parent.edit {Edit displayed numeric X positions and captions. Use pairs stages the Axes draft; Save applies it to this graph or Variant.}
    axisTickDraftSummary $axes
    bind $axes <Destroy> +[list ::GX::axisTickEditorDispose $axes %W $axes]
    return $parent
}
proc ::GX::axisTickEditorDispose {key actual expected} {
    if {$actual ne $expected} return
    variable ::GX::AxisTickEditor::state
    foreach name [array names state "$key,*"] {unset state($name)}
}
proc ::GX::axisTickDraftSummary {axes} {
    variable ::GX::AxisTickEditor::state
    set n [llength $state($axes,pairs)]
    set unit $state($axes,unit);if {$unit eq {}} {set unit {source / dimensionless}}
    set state($axes,summary) [expr {$n?"$n numeric X position / caption pairs · $unit\nShared by all panels; canonical samples remain unchanged.":{Automatic numeric X ticks (no custom captions).}}]
}
proc ::GX::axisTickDraftAutomatic {axes} {
    variable ::GX::AxisTickEditor::state
    if {![info exists state($axes,pairs)]} return
    set state($axes,pairs) {};axisTickDraftSummary $axes
}
proc ::GX::axisTickDraftCheck {axes} {
    variable ::GX::AxisTickEditor::state
    set path [::GX::PlotDatasetAPIv2::_specPath $state($axes,ref)]
    set stamp [expr {[file isfile $path]?[sha256File $path]:{absent}}]
    if {$stamp ne $state($axes,stamp)} {error {This graph or Variant changed while Axes was open. The draft is retained; cancel and reopen Axes before saving.}}
}
# Only the existing same-dialog panel presentation owner may acknowledge its
# own successful non-X mutation. Arbitrary writes still invalidate this draft.
proc ::GX::axisTickDraftOwnerMutationBegin {axes ref} {
    variable ::GX::AxisTickEditor::state
    if {![info exists state($axes,ref)]} {return {}}
    axisTickDraftCheck $axes
    foreach key {graph_id variant_id} {
        if {[dict get $ref $key] ne [dict get $state($axes,ref) $key]} {error {Panel presentation owner does not match this Axes draft.}}
    }
    return [dict create axes $axes stamp $state($axes,stamp) shared_x [::GX::PlotDatasetAPIv2::sharedXAxisGet $ref]]
}
proc ::GX::axisTickDraftOwnerMutationEnd {axes receipt} {
    if {$receipt eq {}} return
    variable ::GX::AxisTickEditor::state
    if {[dict get $receipt axes] ne $axes || ![info exists state($axes,ref)] || $state($axes,stamp) ne [dict get $receipt stamp]} {error {Axes draft owner changed during panel presentation.}}
    set ref $state($axes,ref)
    if {[::GX::PlotDatasetAPIv2::sharedXAxisGet $ref] ne [dict get $receipt shared_x]} {error {Shared X changed during panel presentation; reopen Axes before saving.}}
    set state($axes,stamp) [sha256File [::GX::PlotDatasetAPIv2::_specPath $ref]]
}
proc ::GX::axisTickDraftUnit {axes} {
    variable ui
    variable ::GX::AxisTickEditor::state
    set unit [string trim $ui(axisEdit,x_unit)]
    if {$unit in {{} auto inherit source}} {set unit [dict get [::GX::PlotDatasetAPIv2::sharedXAxisGet $state($axes,ref)] display_unit]}
    return $unit
}
proc ::GX::axisTickPairsFields {pairs} {
    set positions {};set captions {}
    foreach pair $pairs {lappend positions [lindex $pair 0];lappend captions [lindex $pair 1]}
    return [dict create tick_positions [join $positions {;}] tick_labels [join $captions {;}]]
}
proc ::GX::axisTickDraftFields {axes} {
    variable ::GX::AxisTickEditor::state
    axisTickDraftCheck $axes
    set fields [axisTickPairsFields $state($axes,pairs)]
    if {[llength $state($axes,pairs)]} {
        set target [axisTickDraftUnit $axes]
        set fields [::GX::PlotDatasetAPIv2::_axisTicksConvert $fields $state($axes,unit) $target]
        dict set fields display_unit $target
    }
    return $fields
}
proc ::GX::axisTickEditorOpen {axes} {
    variable ::GX::AxisTickEditor::state
    if {[catch {set fields [axisTickDraftFields $axes]} message]} {tk_messageBox -parent $axes -icon error -message $message;return}
    set w $axes.xticks
    if {[winfo exists $w]} {raise $w;return}
    toplevel $w;wm title $w {X tick positions and captions};wm transient $w $axes
    set state($w,pairs) {};if {[dict get $fields tick_positions] ne {}} {set state($w,pairs) [::GX::PlotDatasetAPIv2::_axisTickPairs $fields {X axis}]}
    set state($w,unit) [axisTickDraftUnit $axes];set state($w,position) {};set state($w,caption) {};set state($w,message) {Add a pair or select a row to edit. Captions cannot contain semicolons.}
    grid columnconfigure $w 0 -weight 1;grid rowconfigure $w 1 -weight 1
    set unit $state($w,unit);if {$unit eq {}} {set unit {source / dimensionless}}
    ttk::label $w.info -text "Position is a numeric X coordinate in $unit.\nUse pairs stages this Axes draft; the graph changes only when you Save Axes." -justify left -wraplength 650
    grid $w.info -row 0 -column 0 -sticky ew -padx 10 -pady 8
    uiFieldComponentCreate $w.rows table {columns {Position Caption} scrollbars both} {} {}
    set tree [uiFieldComponentTableWidget $w.rows];$tree configure -selectmode browse -height 7
    $tree column Position -width 150 -stretch 0;$tree column Caption -width 450 -stretch 1
    grid $w.rows -row 1 -column 0 -sticky nsew -padx 10 -pady 4
    bind $tree <<TreeviewSelect>> [list ::GX::axisTickEditorSelected $w]
    bind $tree <Delete> "[list ::GX::axisTickEditorChange $w remove];break"
    ttk::frame $w.input;grid columnconfigure $w.input 1 -weight 1
    foreach {name label row} {position Position 0 caption Caption 1} {
        ttk::label $w.input.${name}Label -text $label
        ttk::entry $w.input.$name -textvariable ::GX::AxisTickEditor::state($w,$name) -width 24
        grid $w.input.${name}Label -row $row -column 0 -sticky w -padx 3 -pady 3
        grid $w.input.$name -row $row -column 1 -sticky ew -padx 3 -pady 3
    }
    grid $w.input -row 2 -column 0 -sticky ew -padx 7 -pady 3
    ttk::frame $w.actions
    foreach {id label} {add {Add pair} update {Update selected} remove Remove up {Move up} down {Move down} clear {Clear / automatic}} {
        ttk::button $w.actions.$id -text $label -command [list ::GX::axisTickEditorChange $w $id]
    }
    grid $w.actions -row 3 -column 0 -sticky ew -padx 7 -pady 4
    bind $w.actions <Configure> [list ::GX::uiFieldControlsLayout $w.actions %w]
    ttk::label $w.message -textvariable ::GX::AxisTickEditor::state($w,message) -width 1 -wraplength 650 -justify left
    grid $w.message -row 4 -column 0 -sticky ew -padx 10 -pady 4
    bind $w.message <Configure> [list $w.message configure -wraplength %w]
    ttk::frame $w.finish
    ttk::button $w.finish.use -text {Use pairs} -command [list ::GX::axisTickEditorUse $axes $w]
    ttk::button $w.finish.cancel -text Cancel -command [list destroy $w]
    pack $w.finish.use $w.finish.cancel -side left -padx 4
    grid $w.finish -row 5 -column 0 -pady 8
    bind $w <Escape> "destroy $w;break"
    bind $w <Destroy> +[list ::GX::axisTickEditorDispose $w %W $w]
    axisTickEditorRows $w
    uiFieldWindowFit $w 760 550;wm minsize $w 460 400
    focus $w.input.position;grab set $w
}
proc ::GX::axisTickEditorRows {w {selected {}}} {
    variable ::GX::AxisTickEditor::state
    set tree [uiFieldComponentTableWidget $w.rows];$tree delete [$tree children {}]
    set i 0;foreach pair $state($w,pairs) {$tree insert {} end -id row[incr i] -values $pair}
    if {$selected ne {} && [$tree exists $selected]} {$tree selection set $selected;$tree focus $selected;$tree see $selected}
    axisTickEditorSelected $w
}
proc ::GX::axisTickEditorSelected {w} {
    variable ::GX::AxisTickEditor::state
    set tree [uiFieldComponentTableWidget $w.rows];set row [lindex [$tree selection] 0]
    foreach id {update remove up down} {$w.actions.$id state [expr {$row eq {}?{disabled}:{!disabled}}]}
    if {$row eq {}} return
    lassign [$tree item $row -values] state($w,position) state($w,caption)
    if {[$tree index $row]==0} {$w.actions.up state disabled}
    if {[$tree index $row]==[llength $state($w,pairs)]-1} {$w.actions.down state disabled}
}
proc ::GX::axisTickEditorChange {w operation} {
    variable ::GX::AxisTickEditor::state
    set tree [uiFieldComponentTableWidget $w.rows];set row [lindex [$tree selection] 0]
    set index [expr {$row eq {}?-1:[$tree index $row]}];set pairs $state($w,pairs);set selected {}
    if {[catch {
        switch -- $operation {
            add - update {
                set caption $state($w,caption)
                if {[string first {;} $caption]>=0} {error {A caption cannot contain a semicolon; it is the PlotSpec pair separator.}}
                set pair [list [string trim $state($w,position)] $caption]
                if {$operation eq {add}} {lappend pairs $pair;set index [expr {[llength $pairs]-1}]
                } elseif {$index>=0} {lset pairs $index $pair} else {return}
                ::GX::PlotDatasetAPIv2::_axisTickPairs [axisTickPairsFields $pairs] {X axis}
                set selected row[expr {$index+1}]
            }
            remove {if {$index<0} return;set pairs [lreplace $pairs $index $index]}
            up - down {
                set target [expr {$index+($operation eq {up}?-1:1)}]
                if {$index<0 || $target<0 || $target>=[llength $pairs]} return
                set pair [lindex $pairs $index];set pairs [lreplace $pairs $index $index];set pairs [linsert $pairs $target $pair];set selected row[expr {$target+1}]
            }
            clear {set pairs {};set state($w,position) {};set state($w,caption) {}}
            default {error {Unknown pair-table action}}
        }
    } message]} {set state($w,message) "Invalid pair: $message";return 0}
    set state($w,pairs) $pairs;set state($w,message) [expr {[llength $pairs]?{Pair draft updated. Use pairs to return to Axes.}:{Automatic numeric ticks: no custom caption pairs.}}]
    axisTickEditorRows $w $selected
    return 1
}
proc ::GX::axisTickEditorUse {axes w} {
    variable ::GX::AxisTickEditor::state
    if {[catch {axisTickDraftCheck $axes} message]} {set state($w,message) $message;return}
    set state($axes,pairs) $state($w,pairs);set state($axes,unit) $state($w,unit)
    axisTickDraftSummary $axes
    destroy $w;focus $state($axes,frame).edit
}
