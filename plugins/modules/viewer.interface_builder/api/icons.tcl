# SPDX-License-Identifier: GPL-3.0-or-later
# Typed icon inspector; persistence, validation and rendering stay CORE owned.
namespace eval ::GX::InterfaceBuilder {variable icon;array set icon {search {} selected {} id {} title {} category Project license GPL-3.0-or-later presentation icon_text icon_position left icon_size 24 icon_spacing 4 icon_disabled {} icon_hover {} icon_selected {} status {Choose a project icon or import an owned PNG/SVG.}}}
proc ::GX::InterfaceBuilder::icons {} {
    variable icon;variable s;set w .gxInterfaceIcons
    if {[winfo exists $w]} {raise $w;return $w}
    foreach c [dict get [design] components] {
        if {[dict get $c id] ne $s(selected)} continue
        set p [dict get $c properties]
        foreach {key fallback} {presentation icon_text icon_position left icon_size 24 icon_spacing 4 icon_disabled {} icon_hover {} icon_selected {}} {set icon($key) [::GX::datasetPublicationV2DictDefault $p $key $fallback]}
        if {[dict exists $p icon] && [dict exists [design] icons [dict get $p icon]]} {set icon(selected) [dict get $p icon]}
    }
    toplevel $w;wm title $w {Project Icon Library};wm geometry $w 900x740;wm minsize $w 640 500
    ttk::frame $w.top -padding 8;pack $w.top -fill x
    ttk::label $w.top.label -text {Find category or name:}
    ttk::entry $w.top.search -textvariable ::GX::InterfaceBuilder::icon(search)
    pack $w.top.label -side left;pack $w.top.search -side left -fill x -expand 1
    bind $w.top.search <KeyRelease> ::GX::InterfaceBuilder::iconsRefresh
    ttk::panedwindow $w.body -orient horizontal;pack $w.body -fill both -expand 1 -padx 8
    ttk::frame $w.body.library
    set f [::GX::uiFieldScrollableCreate $w.body.inspector 370]
    $w.body add $w.body.library -weight 2;$w.body add $w.body.inspector -weight 2
    ttk::treeview $w.body.library.tree -columns {category dimensions} -show {tree headings} -selectmode browse -height 12
    $w.body.library.tree heading #0 -text {Icon / logical ID};$w.body.library.tree column #0 -width 180
    foreach {id title} {category Category dimensions Pixels} {$w.body.library.tree heading $id -text $title;$w.body.library.tree column $id -width 95}
    ttk::scrollbar $w.body.library.scroll -command [list $w.body.library.tree yview]
    ttk::scrollbar $w.body.library.horizontal -orient horizontal -command [list $w.body.library.tree xview]
    $w.body.library.tree configure -yscrollcommand [list $w.body.library.scroll set] -xscrollcommand [list $w.body.library.horizontal set]
    pack $w.body.library.scroll -side right -fill y;pack $w.body.library.horizontal -side bottom -fill x;pack $w.body.library.tree -fill both -expand 1
    bind $w.body.library.tree <<TreeviewSelect>> ::GX::InterfaceBuilder::iconSelected
    foreach {event target} {<Home> first <End> last <Return> focused <space> focused} {
        bind $w.body.library.tree $event "[list ::GX::InterfaceBuilder::iconKeyboard $w.body.library.tree $target];break"
    }
    set row 0
    ttk::label $f.command_label -text {Command target (containers only)}
    grid $f.command_label -row $row -column 0 -sticky w;incr row
    ttk::combobox $f.command -state disabled -textvariable ::GX::InterfaceBuilder::icon(command)
    bind $f.command <<ComboboxSelected>> ::GX::InterfaceBuilder::iconTargetChanged
    grid $f.command -row $row -column 0 -sticky ew;incr row
    foreach {key label values} {id {Logical ID} {} title Name {} category Category {} license {License / ownership} {} presentation Presentation {icon_text icon_only text_only} icon_position {Icon position} {left right top bottom} icon_size {Logical pixels} {16 24 32 48} icon_spacing {Image / text gap} {0 2 4 6 8 12}} {
        ttk::label $f.l$key -text $label;grid $f.l$key -row $row -column 0 -sticky w -padx 3 -pady {5 1};incr row
        if {$values eq {}} {ttk::entry $f.$key -textvariable ::GX::InterfaceBuilder::icon($key)} else {ttk::combobox $f.$key -state readonly -values $values -textvariable ::GX::InterfaceBuilder::icon($key);bind $f.$key <<ComboboxSelected>> ::GX::InterfaceBuilder::iconPreview}
        grid $f.$key -row $row -column 0 -sticky ew -padx 3;incr row
    }
    foreach {key label} {icon_disabled {Disabled icon} icon_hover {Hover icon} icon_selected {Selected icon}} {
        ttk::label $f.l$key -text $label;grid $f.l$key -row $row -column 0 -sticky w -padx 3 -pady {5 1};incr row
        ttk::combobox $f.$key -state readonly -values [list {}] -textvariable ::GX::InterfaceBuilder::icon($key)
        bind $f.$key <<ComboboxSelected>> ::GX::InterfaceBuilder::iconPreview
        grid $f.$key -row $row -column 0 -sticky ew -padx 3;incr row
    }
    grid columnconfigure $f 0 -weight 1
    ttk::labelframe $f.preview -text {State preview} -padding 2
    set cell 0
    foreach {state label} {normal Normal disabled Disabled hover Hover selected Selected} {
        ttk::button $f.preview.$state -text $label
        grid $f.preview.$state -row [expr {$cell/2}] -column [expr {$cell%2}] -sticky ew -padx 4 -pady 3
        incr cell
    }
    grid columnconfigure $f.preview {0 1} -weight 1
    grid $f.preview -row $row -column 0 -sticky ew -pady 10;incr row
    ttk::label $f.info -text {} -wraplength 300;grid $f.info -row $row -column 0 -sticky ew
    bind $f <Configure> +[list ::GX::InterfaceBuilder::iconInspectorWidth $f %w]
    ttk::frame $w.actions -padding 6;pack $w.actions -fill x
    foreach {id label method} {import {Import PNG/SVG…} iconImport shared {Add shared icon…} iconShared assign {Assign to component} iconAssign clear {Remove binding} iconClear rename {Rename ID / metadata} iconRename remove {Delete icon} iconRemove close Close iconClose} {
        ttk::button $w.actions.$id -text $label -command [list ::GX::InterfaceBuilder::safe $method];pack $w.actions.$id -side left -padx 2
    }
    bind $w.actions <Configure> [list ::GX::uiFieldControlsLayout $w.actions %w]
    ttk::label $w.status -textvariable ::GX::InterfaceBuilder::icon(status) -wraplength 800 -padding 8;pack $w.status -fill x
    # Reserve command/status rows before allocating the scrollable pane. At
    # large fonts the tree's requested height must not hide Close or Assign.
    pack configure $w.status -side bottom -before $w.body
    pack configure $w.actions -side bottom -before $w.body
    bind $w.status <Configure> [list $w.status configure -wraplength %w]
    bind $w <Escape> [list destroy $w]
    set icon(command) {};iconTargetChanged;iconsRefresh;return $w
}
proc ::GX::InterfaceBuilder::iconTargetChanged {args} {
    variable icon;variable s
    set f .gxInterfaceIcons.body.inspector.scroll.content
    foreach c [dict get [design] components] {
        if {[dict get $c id] ne $s(selected)} continue
        set p [dict get $c properties];set type [dict get $c type]
        if {$type in {command_toolbar menu context_menu}} {
            set choices [dict get $p actions]
            $f.command configure -state readonly -values $choices
            if {$icon(command) ni $choices} {set icon(command) [lindex $choices 0]}
            set p [::GX::datasetPublicationV2DictDefault [::GX::datasetPublicationV2DictDefault $p command_icons {}] $icon(command) {}]
        } else {$f.command configure -state disabled -values {};set icon(command) {}}
        set nativeMenu [expr {$type in {menu context_menu}}]
        foreach {key fallback} {presentation icon_text icon_position left icon_size 24 icon_spacing 4 icon_disabled {} icon_hover {} icon_selected {}} {
            if {$nativeMenu && $key eq {icon_spacing}} {set fallback 0}
            set icon($key) [::GX::datasetPublicationV2DictDefault $p $key $fallback]
        }
        $f.presentation configure -values [expr {$nativeMenu ? {icon_text text_only} : {icon_text icon_only text_only}}]
        $f.icon_spacing configure -values [expr {$nativeMenu ? {0} : {0 2 4 6 8 12}}]
        foreach key {icon_hover icon_selected} {$f.$key configure -state [expr {$nativeMenu ? {disabled} : {readonly}}]}
        if {[dict exists $p icon]} {set icon(selected) [dict get $p icon]}
        if {$nativeMenu} {set icon(status) {Native menus: normal/disabled images, image+text or text and native placement. Custom spacing, hover/selected images and icon-only tooltips unavailable.}}
    }
    iconPreview
}
proc ::GX::InterfaceBuilder::iconClose {} {destroy .gxInterfaceIcons}
proc ::GX::InterfaceBuilder::iconKeyboard {tree target} {
    set rows [$tree children {}]
    switch -- $target {
        first {set id [lindex $rows 0]}
        last {set id [lindex $rows end]}
        focused {set id [$tree focus]}
    }
    if {$id ne {} && [$tree exists $id]} {$tree focus $id;$tree selection set $id;$tree see $id}
}
proc ::GX::InterfaceBuilder::iconInspectorWidth {frame width} {
    foreach widget [winfo children $frame] {
        if {[winfo class $widget] eq {TLabel}} {$widget configure -wraplength [expr {max(100,$width-12)}]}
    }
    iconPreviewLayout $frame
}
proc ::GX::InterfaceBuilder::iconPreviewLayout {frame} {
    set preview $frame.preview
    if {![winfo exists $preview]} return
    set width [winfo width $preview];set needed 0
    foreach state {normal disabled hover selected} {set needed [expr {max($needed,[winfo reqwidth $preview.$state])}]}
    set columns [expr {$width>=2*$needed+20 ? 2 : 1}]
    set cell 0
    foreach state {normal disabled hover selected} {
        grid $preview.$state -row [expr {$cell/$columns}] -column [expr {$cell%$columns}] -sticky ew -padx 2 -pady 3
        incr cell
    }
    grid columnconfigure $preview 0 -weight 1
    grid columnconfigure $preview 1 -weight [expr {$columns==2}]
}
proc ::GX::InterfaceBuilder::iconsRefresh {args} {
    variable icon;set tree .gxInterfaceIcons.body.library.tree
    if {![winfo exists $tree]} return
    set ids [concat [list {}] [dict keys [::GX::datasetPublicationV2DictDefault [design] icons {}]]]
    foreach key {icon_disabled icon_hover icon_selected} {
        set control .gxInterfaceIcons.body.inspector.scroll.content.$key
        if {[winfo exists $control]} {$control configure -values $ids}
        if {$icon($key) ni $ids} {set icon($key) {}}
    }
    $tree delete [$tree children {}]
    dict for {id asset} [::GX::datasetPublicationV2DictDefault [design] icons {}] {
        if {$icon(search) ne {}&&[string first [string tolower $icon(search)] [string tolower "$id [dict get $asset title] [dict get $asset category]"]]<0} continue
        $tree insert {} end -id $id -text "$id · [dict get $asset title]" -image [::GX::viewerGuiIconPhoto $asset 24] -values [list [dict get $asset category] "[dict get $asset width]×[dict get $asset height]"]
    }
    ::GX::uiFieldInspectionColumnsFit $tree
    set rowHeight [expr {[font metrics TkDefaultFont -linespace]+8}]
    set textWidth [expr {[font measure TkHeadingFont {Icon / logical ID}]+24}]
    foreach id [$tree children {}] {
        set photo [$tree item $id -image]
        set rowHeight [expr {max($rowHeight,[image height $photo]+8)}]
        set textWidth [expr {max($textWidth,[font measure TkDefaultFont [$tree item $id -text]]+[image width $photo]+28)}]
    }
    ttk::style configure GXProjectIcons.Treeview -font TkDefaultFont -rowheight $rowHeight
    $tree configure -style GXProjectIcons.Treeview
    $tree column #0 -width $textWidth -stretch 0
    if {$icon(selected) ne {}&&[$tree exists $icon(selected)]} {
        $tree selection set $icon(selected);$tree focus $icon(selected)
    } else {
        # Native Treeview keyboard navigation requires an item focus. Filtering
        # may hide the assigned resource; focus the first visible row without
        # silently changing the component's binding or inspector selection.
        set first [lindex [$tree children {}] 0]
        if {$first ne {}} {$tree focus $first}
    }
}
proc ::GX::InterfaceBuilder::iconSelected {} {
    variable icon
    set id [lindex [.gxInterfaceIcons.body.library.tree selection] 0]
    if {$id eq {}} return
    set icon(selected) $id;set icon(id) $id;set a [dict get [design] icons $id]
    foreach k {title category license} {set icon($k) [dict get $a $k]}
    .gxInterfaceIcons.body.inspector.scroll.content.info configure -text "[dict get $a source_format] · alpha [dict get $a alpha]\nSHA-256: [dict get $a sha256]\nProject-owned embedded bytes; generated package uses relative resources. Empty state choices keep the normal native image."
    iconPreview
}
proc ::GX::InterfaceBuilder::iconPreview {args} {
    variable icon
    if {![dict exists [design] icons $icon(selected)]} return
    set p {};foreach k {presentation icon_position icon_size icon_spacing icon_disabled icon_hover icon_selected} {dict set p $k $icon($k)}
    foreach {state flags} {normal {!disabled !selected !active} disabled {disabled !selected !active} hover {!disabled !selected active} selected {!disabled selected !active}} {
        set widget .gxInterfaceIcons.body.inspector.scroll.content.preview.$state
        ::GX::uiFieldIconApply $widget $p [dict get [design] icons $icon(selected)] [dict get [design] icons]
        $widget state $flags
    }
    iconPreviewLayout .gxInterfaceIcons.body.inspector.scroll.content
}
proc ::GX::InterfaceBuilder::iconImport {{path {}} {sharedSource {}}} {
    variable icon
    if {$path eq {}} {set path [tk_getOpenFile -parent .gxInterfaceIcons -title {Import an owned PNG or safe SVG} -filetypes {{{Icon images} {.png .svg}}}];if {$path eq {}} return}
    set id [string tolower [regsub -all {[^a-zA-Z0-9_]} [file rootname [file tail $path]] _]]
    if {![regexp {^[a-z]} $id]} {set id icon_$id}
    set title [file rootname [file tail $path]]
    if {$sharedSource ne {}} {set id [dict get $sharedSource id];set title [dict get $sharedSource title]}
    set asset [::GX::viewerGuiIconImport $path $title $icon(category) $icon(license)]
    dict for {other item} [::GX::datasetPublicationV2DictDefault [design] icons {}] {if {[dict get $asset sha256] eq [dict get $item sha256]} {set icon(selected) $other;set icon(status) "Duplicate bytes: using existing $other";iconsRefresh;return}}
    set base $id;set n 1;while {[dict exists [design] icons $id]} {set id ${base}_[incr n]}
    apply icon put $id $asset;set icon(selected) $id;iconsRefresh;set icon(status) "Imported owned $id. Choose the target component in Builder and Assign."
}
proc ::GX::InterfaceBuilder::iconShared {} {
    variable icon
    set catalog [dict get [::GX::viewerGuiIconCatalog] icons]
    set first [lindex [dict values $catalog] 0]
    set path [tk_getOpenFile -parent .gxInterfaceIcons -title {Shared original GPL icon catalog} -initialdir [file dirname [dict get $first path]] -filetypes {{{SVG icon} .svg}}]
    if {$path eq {}} return
    set selected {}
    dict for {id entry} $catalog {if {[dict get $entry path] eq [file normalize $path]} {set selected $entry;break}}
    if {$selected eq {}} {error {Choose a declared shared icon; use Import for other owned assets}}
    if {[::GX::sha256File $path] ne [dict get $selected sha256]} {error {Shared icon changed; reopen its catalog}}
    set icon(category) [dict get $selected category];set icon(license) [dict get $selected license]
    iconImport $path $selected
}
proc ::GX::InterfaceBuilder::iconAssign {} {
    variable icon;variable s
    if {$icon(selected) eq {}} {error {Choose an icon first}}
    # Apply all typed presentation fields as one existing model transaction.
    set d [design];set components {};set found 0;set p {}
    foreach c [dict get $d components] {
        if {[dict get $c id] eq $s(selected)} {
            set cap [dict get [::GX::viewerGuiComponentCapabilities] [dict get $c type]]
            set target {}
            if {[dict exists $cap properties command_icons]} {
                if {$icon(command) ni [dict get $c properties actions]} {error {Choose an existing native command target}}
                set target $icon(command)
                set binding [dict create icon $icon(selected)]
                foreach k {presentation icon_position icon_size icon_spacing icon_disabled icon_hover icon_selected} {dict set binding $k $icon($k)}
                dict set c properties command_icons $target $binding
            } else {
                if {![dict exists $cap properties icon]} {error {This native component does not expose an icon capability}}
                dict set c properties icon $icon(selected)
                foreach k {presentation icon_position icon_size icon_spacing icon_disabled icon_hover icon_selected} {dict set c properties $k $icon($k)}
            }
            set p [dict get $c properties];set found 1
        };lappend components $c
    }
    if {!$found} {error {Select a compatible Builder component}}
    dict set d components $components
    set s(model) [::GX::viewerGuiDesignModelEdit $s(model) properties $s(selected) $p]
    refresh;set icon(status) "Assigned $icon(selected) to $s(selected); command and handler identity preserved."
}
proc ::GX::InterfaceBuilder::iconClear {} {
    variable s;variable icon
    foreach c [dict get [design] components] {
        if {[dict get $c id] ne $s(selected)} continue
        set p [dict get $c properties]
        if {[dict get $c type] in {command_toolbar menu context_menu}} {
            if {[dict exists $p command_icons $icon(command)]} {dict unset p command_icons $icon(command)}
            apply properties $s(selected) $p
        } else {apply properties $s(selected) {icon {} icon_disabled {} icon_hover {} icon_selected {}}}
    }
    set icon(status) {Removed selected icon binding; command identity preserved.}
}
proc ::GX::InterfaceBuilder::iconRename {} {
    variable icon
    set old $icon(selected);set a [dict get [design] icons $old]
    foreach k {title category license} {dict set a $k $icon($k)}
    if {$old ne $icon(id)} {
        apply icon rename $old $icon(id);set icon(selected) $icon(id)
        foreach key {icon_disabled icon_hover icon_selected} {if {$icon($key) eq $old} {set icon($key) $icon(id)}}
    }
    apply icon put $icon(selected) $a;iconsRefresh
    set icon(status) "Saved icon $icon(selected) metadata; all logical bindings preserved."
}
proc ::GX::InterfaceBuilder::iconRemove {} {variable icon;apply icon remove $icon(selected);set icon(selected) {};iconsRefresh}
