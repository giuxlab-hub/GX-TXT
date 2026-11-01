# SPDX-License-Identifier: GPL-3.0-or-later
# Shared Document record/source/Undo owner; the semantic model is always derived.
proc ::GX::_umlEditorGrant {record operation} {
    if {$operation ni [dict get $record options uml_operations]} {error "UML operation is not admitted: $operation"}
}
proc ::GX::umlEditorMount {parent options} {
    variable ::GX::DocumentSource::editors;variable ::GX::DocumentSource::editorSerial
    set options [dict merge {kind uml mode editable pane diagram initial {} dataset_id {} capability {} toolbar 0 on_change {} on_command {} uml_operations {umlDocumentRead umlDocumentParse umlDocumentLayout umlDocumentEdit umlDocumentWrite umlDocumentExport}} $options]
    if {[dict get $options mode] ni {editable read_only} || [dict get $options pane] ni {diagram source metadata}} {error {UML Document requires editable/read_only mode and diagram/source/metadata pane}}
    foreach operation {umlDocumentRead umlDocumentParse umlDocumentLayout} {if {$operation ni [dict get $options uml_operations]} {error "UML operation is not admitted: $operation"}}
    if {[dict get $options mode] eq {editable} && {umlDocumentEdit} ni [dict get $options uml_operations]} {error {Editable UML requires admitted umlDocumentEdit}}
    set text [dict get $options initial];set baseline {};set id [dict get $options dataset_id]
    if {$id ne {}} {
        set read [umlDocumentRead $id [dict create capability [dict get $options capability]]]
        set baseline [dict get $read description];set text [dict get $read source]
    }
    umlDocumentParse $text
    if {![winfo exists $parent]} {ttk::frame $parent}
    set handle uml-editor#[incr editorSerial]
    dict set editors $handle [dict create parent $parent options $options baseline $baseline baseline_text $text session [_documentEditorSessionToken] source {} preview {} assets {} asset_owner {} photos {} image_pairs {} zoom 1.0 destination_id {} diagram {} parsed {} selected {} last_valid_source {} render_error {} refreshing 0 splitters {.32 .84} sash_drag 0 view {source 1 diagram 1 outline 1 properties 0 diagnostics 0}]
    ttk::label $parent.status -wraplength 700 -anchor w
    pack $parent.status -side bottom -fill x -padx 5 -pady 4
    if {[dict get $options mode] eq {editable}} {
        ttk::panedwindow $parent.pw -orient horizontal;pack $parent.pw -fill both -expand 1
        foreach name {source diagram outline properties diagnostics} {ttk::frame $parent.pw.$name}
        set source [sourceSurfaceCreate $parent.pw.source.surface [dict create mode editable language plaintext find_bar 1 change_command [list ::GX::_umlEditorChanged $handle]]]
        sourceSurfaceSet $source $text;pack $parent.pw.source.surface -fill both -expand 1
        dict set editors $handle source $source
        # Search remains the existing SourceSurface controls. Keep the initial
        # narrow source pane useful until the user requests Find or Replace.
        grid remove $parent.pw.source.surface.find
        foreach {sequence operation} {<Control-f> find <Control-h> replace <Escape> hide} {
            bind $source $sequence "[list ::GX::_umlEditorSearch $handle $operation];break"
        }
        foreach control {query previous next replace.value replace.current replace.all} {
            bind $parent.pw.source.surface.find.$control <Escape> "[list ::GX::_umlEditorSearch $handle hide];break"
        }
        ttk::treeview $parent.pw.outline.tree -show tree -selectmode browse
        _uiFieldTreeFontRows $parent.pw.outline.tree GXUmlOutline.Treeview
        bind $parent.pw.outline.tree <<ThemeChanged>> [list ::GX::_uiFieldTreeFontRows $parent.pw.outline.tree GXUmlOutline.Treeview]
        bind $parent.pw.outline.tree <Map> [list ::GX::_uiFieldTreeFontRows $parent.pw.outline.tree GXUmlOutline.Treeview]
        bind $parent.pw.outline.tree <<ThemeChanged>> +[list after idle [list ::GX::_umlEditorOutlineWidth $handle]]
        bind $parent.pw.outline.tree <Map> +[list after idle [list ::GX::_umlEditorOutlineWidth $handle]]
        ttk::scrollbar $parent.pw.outline.scroll -command [list $parent.pw.outline.tree yview]
        ttk::scrollbar $parent.pw.outline.horizontal -orient horizontal -command [list $parent.pw.outline.tree xview]
        $parent.pw.outline.tree configure -yscrollcommand [list $parent.pw.outline.scroll set] -xscrollcommand [list $parent.pw.outline.horizontal set]
        $parent.pw.outline.tree column #0 -stretch 0
        pack $parent.pw.outline.scroll -side right -fill y;pack $parent.pw.outline.horizontal -side bottom -fill x;pack $parent.pw.outline.tree -fill both -expand 1
        bind $parent.pw.outline.tree <<TreeviewSelect>> [list ::GX::_umlEditorOutlineSelect $handle]
        bind $parent.pw.outline.tree <Double-Button-1> [list ::GX::_umlEditorProperties $handle]
        foreach pane {properties diagnostics} {
            text $parent.pw.$pane.text -state disabled -wrap word -width 30 -exportselection 0
            ttk::scrollbar $parent.pw.$pane.scroll -command [list $parent.pw.$pane.text yview]
            $parent.pw.$pane.text configure -yscrollcommand [list $parent.pw.$pane.scroll set]
            pack $parent.pw.$pane.scroll -side right -fill y;pack $parent.pw.$pane.text -fill both -expand 1
            uiTextEditingAttach [winfo toplevel $parent] [list $parent.pw.$pane.text]
        }
        ttk::button $parent.pw.properties.apply -text {Edit selected properties…} -command [list ::GX::_umlEditorProperties $handle]
        pack $parent.pw.properties.apply -side bottom -fill x
        bind $parent.pw <ButtonPress-1> +[list ::GX::_umlEditorSashPress $handle %x %y]
        bind $parent.pw <ButtonRelease-1> +[list ::GX::_umlEditorSashRelease $handle]
        bind $parent.pw <Configure> +[list after idle [list ::GX::_umlEditorSashes $handle]]
        _umlEditorView $handle
    } elseif {[dict get $options pane] eq {source}} {
        set source [sourceSurfaceCreate $parent.surface {mode read_only language plaintext find_bar 1}]
        sourceSurfaceSet $source $text;pack $parent.surface -fill both -expand 1
        dict set editors $handle source $source
    } elseif {[dict get $options pane] eq {metadata}} {
        text $parent.metadata -state normal -wrap word -exportselection 0
        ttk::scrollbar $parent.metadataScroll -orient vertical -command [list $parent.metadata yview]
        $parent.metadata configure -yscrollcommand [list $parent.metadataScroll set]
        pack $parent.metadataScroll -side right -fill y
        $parent.metadata insert end [_umlEditorMetadataText $baseline $text]
        $parent.metadata configure -state disabled;pack $parent.metadata -fill both -expand 1
        uiTextEditingAttach [winfo toplevel $parent] [list $parent.metadata]
    } else {ttk::frame $parent.diagram;pack $parent.diagram -fill both -expand 1}
    bind $parent <Destroy> +[list ::GX::_documentEditorDestroyed $handle %W]
    if {[dict get $editors $handle source] ne {}} {
        set source [dict get $editors $handle source]
        foreach {sequence operation} {<F8> zoom_in <F7> zoom_out <Control-0> zoom_reset <Control-s> save_existing <Control-S> publish_new <Control-Shift-s> publish_new} {
            bind $source $sequence "[list ::GX::_documentEditorHostCommand $handle $operation];break"
        }
        if {[dict get $options mode] eq {editable}} {
            foreach {sequence operation} {<Control-n> new <Control-o> open} {bind $source $sequence "[list ::GX::_documentEditorHostCommand $handle $operation];break"}
        }
    }
    _umlEditorChanged $handle
    return $handle
}
proc ::GX::_umlEditorTextSet {widget value} {$widget configure -state normal;$widget delete 1.0 end;$widget insert end $value;$widget configure -state disabled}
proc ::GX::_umlEditorSearch {handle operation} {
    set record [_documentEditorRecord $handle];set source [dict get $record source]
    if {$source eq {}} {error {Select the Source pane to search literal text}}
    set surface [sourceSurfaceParent $source]
    if {$operation eq {hide}} {grid remove $surface.find;focus $source;return}
    grid $surface.find
    if {$operation eq {replace}} {_sourceSurfaceReplaceControls $surface;focus $surface.find.replace.value} else {focus $surface.find.query}
}
proc ::GX::_umlEditorChanged {handle args} {
    variable ::GX::DocumentSource::editors
    if {[catch {set record [_documentEditorRecord $handle]}] || [dict get $record refreshing]} return
    dict set editors $handle refreshing 1
    try {
        set text [_documentEditorText $record]
        if {[catch {set parsed [umlDocumentParse $text]} message]} {
            # A user's literal over-budget/invalid UTF-8 draft stays visible;
            # it cannot be saved/captured as an admitted UML document.
            set parsed [dict create valid 0 source $text source_sha256 [_umlDigest $text] family {} elements {} relations {} messages {} frames {} diagnostics [list [_umlDiagnostic 1 BOUNDS $message]]]
        }
        set declared [datasetPublicationV2DictDefault [dict get $record baseline] declared_profile {}]
        if {$declared ne {} && $declared ne {gxtxt.plantuml.v1}} {dict set parsed valid 0;dict set parsed diagnostics [list [_umlDiagnostic 1 PROFILE {Declared UML profile is unsupported; exact source remains inspectable}]]}
        dict set editors $handle parsed $parsed
        set parent [dict get $record parent];set editable [expr {[dict get $record options mode] eq {editable}}]
        set wantsDiagram [expr {$editable || [dict get $record options pane] eq {diagram}}]
        set diagnostic {}
        foreach item [dict get $parsed diagnostics] {append diagnostic "Line [dict get $item line]: [dict get $item message]\n"}
        if {$wantsDiagram && [dict get $parsed valid]} {
            set view [dict get $record diagram]
            if {[catch {
                if {$view eq {}} {
                    set container [expr {$editable?"$parent.pw.diagram":"$parent.diagram"}]
                    set callbacks [dict create editable $editable on_select [list ::GX::_umlEditorSelect $handle]]
                    if {$editable} {dict set callbacks on_move [list ::GX::_umlEditorMove $handle];dict set callbacks on_activate [list ::GX::_umlEditorActivate $handle]}
                    set view [umlDiagramMount $container $text $callbacks]
                    dict set editors $handle diagram $view
                } else {umlDiagramCommand $view source_set [dict create source $text]}
                dict set editors $handle last_valid_source $text
            } message]} {append diagnostic "Diagram unavailable: $message\n";dict set editors $handle render_error $message
            } else {dict set editors $handle render_error {}}
        }
        set good [expr {[dict get $parsed valid] && $diagnostic eq {}}]
        set caption [expr {$good?"[string totitle [dict get $parsed family]] diagram — current source":"Source diagnostics — draft retained"}]
        if {!$good && [dict get $editors $handle last_valid_source] ne {}} {append caption "; diagram shows last valid source SHA [string range [_umlDigest [dict get $editors $handle last_valid_source]] 0 11]"}
        $parent.status configure -text $caption
        if {$editable} {
            _umlEditorTextSet $parent.pw.diagnostics.text $diagnostic
            _umlEditorOutline $handle
            _umlEditorSelectionDetails $handle
        }
    } finally {if {[dict exists $editors $handle]} {dict set editors $handle refreshing 0}}
    set record [_documentEditorRecord $handle];set receipt [umlEditorCommand $handle inspect]
    set callback [dict get $record options on_change]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $handle $receipt]}
    event generate [dict get $record parent] <<GXDocumentChanged>> -data $receipt
}
proc ::GX::_umlEditorOutline {handle} {
    set record [_documentEditorRecord $handle];set tree [dict get $record parent].pw.outline.tree
    set selected [dict get $record selected];set previousItems [$tree children {}];$tree delete $previousItems
    set parsed [dict get $record parsed]
    if {![dict get $parsed valid]} return
    dict for {id item} [dict get $parsed elements] {
        $tree insert {} end -id $id -text "[dict get $item type]: [dict get $item name]" -values [list [dict get $item line]]
        if {[dict exists $item members]} {foreach member [dict get $item members] {$tree insert $id end -id [dict get $member id] -text [dict get $member text] -values [list [dict get $member line]]}}
    }
    foreach category {relations messages} {foreach item [dict get $parsed $category] {$tree insert {} end -id [dict get $item id] -text "[dict get $item from] → [dict get $item to]: [dict get $item label]" -values [list [dict get $item line]]}}
    dict for {id item} [dict get $parsed frames] {$tree insert {} end -id $id -text "[dict get $item kind]: [dict get $item label]" -values [list [dict get $item line]]}
    _umlEditorOutlineWidth $handle
    # A different diagram starts at the beginning of its labels. Keep the
    # user's horizontal position while editing the same semantic identities.
    set retained 0
    foreach id $previousItems {if {[$tree exists $id]} {set retained 1;break}}
    if {!$retained} {$tree xview moveto 0}
    if {$selected ne {} && [$tree exists $selected]} {$tree selection set $selected}
}
proc ::GX::_umlEditorOutlineWidth {handle} {
    if {[catch {set record [_documentEditorRecord $handle]}]} return
    set tree [dict get $record parent].pw.outline.tree
    if {![winfo exists $tree]} return
    set font [ttk::style lookup [$tree cget -style] -font]
    if {$font eq {}} {set font TkDefaultFont}
    set width 200
    foreach id [$tree children {}] {
        set width [expr {max($width,48+[font measure $font [$tree item $id -text]])}]
        foreach child [$tree children $id] {set width [expr {max($width,68+[font measure $font [$tree item $child -text]])}]}
    }
    $tree column #0 -width $width
}
proc ::GX::_umlEditorOutlineSelect {handle} {
    set record [_documentEditorRecord $handle];set tree [dict get $record parent].pw.outline.tree
    set id [lindex [$tree selection] 0];if {$id eq {} || $id eq [dict get $record selected]} return
    _umlEditorSelect $handle {} $id
}
proc ::GX::_umlEditorSelect {handle view id} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorRecord $handle];dict set editors $handle selected $id
    if {[dict get $record options mode] eq {editable}} {
        set tree [dict get $record parent].pw.outline.tree
        if {$id ne {} && [$tree exists $id]} {$tree selection set $id;$tree see $id}
        if {$id ne {} && ![catch {set item [umlDocumentInspectElement [dict get $record parsed] $id]}]} {
            set source [dict get $record source];set line [dict get $item line]
            $source mark set insert $line.0;$source see $line.0
        }
        _umlEditorSelectionDetails $handle
    }
    if {$view eq {} && [dict get $record diagram] ne {} && [dict exists [dict get $::GX::UmlV1::views [dict get $record diagram]] plan hit_map $id]} {umlDiagramCommand [dict get $record diagram] select [dict create id $id]}
}
proc ::GX::_umlEditorSelectionDetails {handle} {
    set record [_documentEditorRecord $handle];set id [dict get $record selected];set value {Select a semantic item in the diagram or outline.}
    if {$id ne {} && ![catch {set item [umlDocumentInspectElement [dict get $record parsed] $id]}]} {
        set value "Stable identity: $id\n"
        foreach key {type name kind from to label text visibility line order} {if {[dict exists $item $key]} {append value "\n$key: [dict get $item $key]"}}
    }
    _umlEditorTextSet [dict get $record parent].pw.properties.text $value
}
proc ::GX::_umlEditorDiagramCurrent {handle view} {
    if {[catch {set record [_documentEditorRecord $handle]}]} {return 0}
    if {$view ne [dict get $record diagram] || ![dict get $record parsed valid] || [dict get $record render_error] ne {} || [catch {set shown [umlDiagramCommand $view inspect]}]} {return 0}
    return [expr {[dict get $shown source_sha256] eq [_umlDigest [_documentEditorText $record]]}]
}
proc ::GX::_umlEditorMove {handle view id x y} {
    if {![_umlEditorDiagramCurrent $handle $view]} {
        if {![catch {set record [_documentEditorRecord $handle]}]} {[dict get $record parent].status configure -text {The displayed diagram is from an older source. Correct source diagnostics before moving its elements.}}
        return
    }
    umlEditorCommand $handle semantic_edit [dict create operation position_set request [dict create id $id x [expr {round($x)}] y [expr {round($y)}]]]
}
proc ::GX::_umlEditorActivate {handle view id} {
    if {![_umlEditorDiagramCurrent $handle $view]} {
        if {![catch {set record [_documentEditorRecord $handle]}]} {[dict get $record parent].status configure -text {The displayed diagram is from an older source. Use the current Source/Outline to inspect diagnostics.}}
        return
    }
    _umlEditorProperties $handle
}
proc ::GX::_umlEditorProperties {handle} {
    set record [_documentEditorRecord $handle];set id [dict get $record selected]
    if {$id eq {}} {error {Select a UML semantic item first}}
    set item [umlDocumentInspectElement [dict get $record parsed] $id]
    if {[dict exists $item type]} {set operation element_rename;set key name
    } elseif {[dict exists $item visibility]} {set operation member_edit;set key text
    } elseif {[dict exists $item arrow]} {set operation relation_edit;set key {}
    } elseif {[dict exists $item frames]} {set operation message_edit;set key {}
    } else {set operation frame_edit;set key label}
    if {$key ne {}} {
        set fields [dict create $key [dict create type string label [string totitle $key]]];set value [dict get $item $key]
        if {$operation eq {member_edit}} {set value "[dict get $item visibility] $value"}
        set initial [dict create $key $value]
    } else {
        set fields {};set initial {}
        foreach key {from to kind label} {dict set fields $key [dict create type string label [string totitle $key]];dict set initial $key [dict get $item $key]}
        if {$operation eq {relation_edit}} {
            dict set fields marker {type choice label {Marker endpoint (left/from or right/to)} values {start end}};dict set initial marker [dict get $item marker]
            foreach key {left_multiplicity right_multiplicity} {dict set fields $key [dict create type string label [string map {_ { }} $key]];dict set initial $key [dict get $item $key]}
        }
    }
    uiFieldFormCreate [dict get $record parent].properties_dialog {UML semantic properties} $fields $initial [list ::GX::_umlEditorApplyForm $handle $operation [dict create id $id] [dict get [dict get $record parsed] source_sha256]] [winfo toplevel [dict get $record parent]]
}
proc ::GX::_umlEditorApplyForm {handle operation fixed expected values} {
    set record [_documentEditorRecord $handle]
    if {[_umlDigest [_documentEditorText $record]] ne $expected} {error {Source changed while properties were open; review current item before applying}}
    return [umlEditorCommand $handle semantic_edit [dict create operation $operation request [dict merge $values $fixed]]]
}
proc ::GX::_umlEditorApplyFrameForm {handle expected choices values} {
    foreach key {first last} {
        set label [dict get $values $key]
        if {![dict exists $choices $label]} {error {Select an actual message from the current source}}
        dict set values $key [dict get $choices $label]
    }
    return [_umlEditorApplyForm $handle frame_add {} $expected $values]
}
proc ::GX::_umlEditorAction {handle action} {
    set record [_documentEditorRecord $handle];_umlEditorGrant $record umlDocumentEdit
    set parsed [umlDocumentParse [_documentEditorText $record]]
    if {![dict get $parsed valid]} {error {Correct current source diagnostics before semantic editing}}
    set selected [dict get $record selected];set fields {};set values {};set fixed {};set operation {};set frameChoices {}
    set aliases [dict keys [dict get $parsed elements]]
    if {$action eq {edit_selected}} {return [_umlEditorProperties $handle]}
    if {$action eq {auto_layout}} {return [umlEditorCommand $handle semantic_edit {operation layout_reset request {}}]}
    if {$action eq {delete_selected}} {
        set item [umlDocumentInspectElement $parsed $selected]
        set fixed [dict create id $selected]
        if {[dict exists $item type]} {set operation element_delete;dict set fixed cascade 1;set message {Delete the selected element and its connected relationships/messages?}
        } elseif {[dict exists $item visibility]} {set operation member_delete;set message {Delete the selected member?}
        } elseif {[dict exists $item arrow]} {set operation relation_delete;set message {Delete the selected relationship?}
        } elseif {[dict exists $item frames]} {set operation message_delete;set message {Delete the selected message?}
        } else {set operation frame_delete;set message {Remove the control frame and its branch guards, preserving message order?}}
        set expected [dict get $parsed source_sha256]
        if {[tk_messageBox -parent [winfo toplevel [dict get $record parent]] -type yesno -default no -icon question -message $message] ne {yes}} {return}
        return [_umlEditorApplyForm $handle $operation $fixed $expected {}]
    }
    if {$action in {message_up message_down}} {
        set messages [dict get $parsed messages];set index -1
        set index [lsearch -exact [lmap item $messages {dict get $item id}] $selected]
        if {$index<0} {error {Select a sequence message to reorder}}
        if {$action eq {message_up}} {
            if {$index==0} {error {Message is already first}}
            set destination [dict create before [dict get [lindex $messages [expr {$index-1}]] id]]
        } else {
            if {$index==[llength $messages]-1} {error {Message is already last}}
            set destination [dict create after [dict get [lindex $messages [expr {$index+1}]] id]]
        }
        return [umlEditorCommand $handle semantic_edit [dict create operation message_move request [dict merge [dict create id $selected] $destination]]]
    }
    switch -- $action {
        add_class - add_interface - add_participant - add_actor {
            set operation element_add;dict set fixed type [string range $action 4 end]
            foreach key {alias name} {dict set fields $key [dict create type string label [string totitle $key]];dict set values $key {}}
        }
        add_member {
            set operation member_add;set owners {}
            dict for {id item} [dict get $parsed elements] {if {[dict get $item type] in {class interface}} {lappend owners $id}}
            if {![llength $owners]} {error {Create a class/interface before adding a member}}
            dict set fields owner [dict create type choice label Owner values $owners]
            dict set fields text {type string label {Member with visibility (+ - # ~)}}
            set values [dict create owner [expr {$selected in $owners?$selected:[lindex $owners 0]}] text {+ operation(): Type}]
        }
        add_relation - add_message {
            if {![llength $aliases]} {error {Declare the endpoint elements first}}
            set operation [expr {$action eq {add_relation}?{relation_add}:{message_add}}]
            foreach key {from to} {dict set fields $key [dict create type choice label [string totitle $key] values $aliases];dict set values $key [lindex $aliases 0]}
            dict set fields kind [dict create type choice label Kind values [expr {$operation eq {relation_add}?{association dependency generalization realization composition aggregation}:{sync async reply}}]]
            dict set values kind [lindex [dict get $fields kind values] 0]
            dict set fields label {type string label Label};dict set values label {}
            if {$operation eq {relation_add}} {
                dict set fields marker {type choice label {Marker endpoint} values {start end}};dict set values marker end
                foreach key {left_multiplicity right_multiplicity} {dict set fields $key [dict create type string label [string map {_ { }} $key]];dict set values $key {}}
            }
        }
        add_frame {
            set operation frame_add;set labels {};set number 0
            foreach item [dict get $parsed messages] {
                set label "[incr number]. [dict get $item from] → [dict get $item to]: [string range [dict get $item label] 0 159]"
                lappend labels $label;dict set frameChoices $label [dict get $item id]
            }
            if {![llength $labels]} {error {Create messages before wrapping a control frame}}
            dict set fields kind {type choice label Kind values {alt opt loop}};dict set values kind alt
            dict set fields label {type string label {Condition / description}};dict set values label condition
            foreach key {first last} {dict set fields $key [dict create type choice label [string totitle $key] values $labels];dict set values $key [lindex $labels [expr {$key eq {first}?0:[llength $labels]-1}]]}
        }
        default {error {Unknown finite UML semantic action}}
    }
    set apply [list ::GX::_umlEditorApplyForm $handle $operation $fixed [dict get $parsed source_sha256]]
    if {$operation eq {frame_add}} {set apply [list ::GX::_umlEditorApplyFrameForm $handle [dict get $parsed source_sha256] $frameChoices]}
    uiFieldFormCreate [dict get $record parent].semantic_dialog {UML semantic edit} $fields $values $apply [winfo toplevel [dict get $record parent]]
}
proc ::GX::_umlEditorView {handle} {
    set record [_documentEditorRecord $handle];set pw [dict get $record parent].pw
    set index 0
    foreach key {source diagram outline properties diagnostics} {
        set path $pw.$key
        if {[dict get $record view $key]} {if {$path ni [$pw panes]} {$pw add $path -weight 1};$pw insert $index $path;incr index
        } elseif {$path in [$pw panes]} {$pw forget $path}
    }
    after idle [list ::GX::_umlEditorSashes $handle]
}
proc ::GX::_umlEditorSashPress {handle x y} {
    if {[catch {set record [_documentEditorRecord $handle]}]} return
    dict set ::GX::DocumentSource::editors $handle sash_drag [expr {[[dict get $record parent].pw identify $x $y] ne {}}]
}
proc ::GX::_umlEditorSashRelease {handle} {
    if {[catch {set record [_documentEditorRecord $handle]}] || ![dict get $record sash_drag]} return
    set pw [dict get $record parent].pw;set width [winfo width $pw];set values {}
    for {set index 0} {$index<[llength [$pw panes]]-1} {incr index} {lappend values [expr {[$pw sashpos $index]/double(max(1,$width))}]}
    dict set ::GX::DocumentSource::editors $handle splitters $values;dict set ::GX::DocumentSource::editors $handle sash_drag 0
}
proc ::GX::_umlEditorSashes {handle} {
    if {[catch {set record [_documentEditorRecord $handle]}] || [dict get $record sash_drag]} return
    set pw [dict get $record parent].pw;set width [winfo width $pw]
    if {$width<20} return
    set count [expr {[llength [$pw panes]]-1}];set values [dict get $record splitters]
    if {[llength $values]!=$count} {set values {};for {set i 1} {$i<=$count} {incr i} {lappend values [expr {$i/double($count+1)}]}}
    for {set i 0} {$i<$count} {incr i} {$pw sashpos $i [expr {round([lindex $values $i]*$width)}]}
}
proc ::GX::_umlEditorDraftValidate {draft} {
    # This typed document envelope has its own body budget, independently of
    # the 16 KiB semantic-control request boundary.
    set allowed {schema text baseline baseline_text last_valid_source selected view splitters viewport cursor selection xview yview destination_id}
    dict for {key value} $draft {if {$key ni $allowed} {error {Unknown UML draft field}}}
    foreach key {schema text baseline baseline_text last_valid_source selected view splitters viewport destination_id} {if {![dict exists $draft $key]} {error "Missing UML draft field: $key"}}
    if {[string bytelength $draft]>16777216} {error {UML draft exceeds 16 MiB}}
    if {[dict get $draft schema] ne {gxtxt.uml_draft.v1}} {error {Unsupported UML draft schema}}
    foreach key {text baseline_text last_valid_source} {
        set parsed [umlDocumentParse [dict get $draft $key]]
        if {$key eq {last_valid_source} && [dict get $draft $key] ne {} && ![dict get $parsed valid]} {error {Saved last-valid UML diagram source has diagnostics}}
    }
    set baseline [dict get $draft baseline]
    if {$baseline ne {}} {
        _umlRequest $baseline {dataset_id kind contract format media_type producer immutable sha256 revision declared_profile} {dataset_id kind contract producer immutable sha256 revision}
        datasetPublicationV2ValidateId dataset [dict get $baseline dataset_id]
        if {[dict get $baseline kind] ne {uml} || [dict get $baseline contract] ne {document.uml} || ![string is boolean -strict [dict get $baseline immutable]] || ![regexp {^[0-9a-f]{64}$} [dict get $baseline sha256]] || [string length [dict get $baseline revision]]>16384} {error {Invalid saved UML canonical baseline}}
        if {[_umlDigest [dict get $draft baseline_text]] ne [dict get $baseline sha256]} {error {Saved UML baseline text differs from its source SHA}}
    }
    set view [dict get $draft view];_umlRequest $view {source diagram outline properties diagnostics} {source diagram outline properties diagnostics}
    dict for {key value} $view {if {![string is boolean -strict $value]} {error {UML panel visibility must be boolean}}}
    set previous 0
    if {[llength [dict get $draft splitters]]>4} {error {Too many UML splitter positions}}
    foreach value [dict get $draft splitters] {if {![string is double -strict $value] || !($value>=$previous && $value<=1)} {error {UML splitters require ordered finite normalized positions}};set previous $value}
    set viewport [dict get $draft viewport];_umlRequest $viewport {mode zoom pan selected} {mode zoom pan selected}
    if {[dict get $viewport mode] ni {fit manual} || ![string is double -strict [dict get $viewport zoom]] || !([dict get $viewport zoom]>=.005 && [dict get $viewport zoom]<=8) || [llength [dict get $viewport pan]]!=2} {error {Invalid saved UML viewport}}
    foreach value [dict get $viewport pan] {if {![string is double -strict $value] || ![expr {abs($value)<=1000000}]} {error {Invalid saved UML pan}}}
    foreach id [list [dict get $draft selected] [dict get $viewport selected]] {if {$id ne {} && ![regexp {^[A-Za-z_][A-Za-z0-9_]{0,63}$} $id]} {error {Invalid saved semantic identity}}}
    foreach key {cursor selection} {foreach value [datasetPublicationV2DictDefault $draft $key {}] {if {![regexp {^[1-9][0-9]*\.[0-9]+$} $value]} {error {Invalid saved UML source index}}}}
    if {[llength [datasetPublicationV2DictDefault $draft selection {}]] ni {0 2}} {error {Source selection needs zero or two indices}}
    foreach key {xview yview} {foreach value [datasetPublicationV2DictDefault $draft $key {}] {if {![string is double -strict $value] || !($value>=0 && $value<=1)} {error {Invalid saved source scroll anchor}}};if {[llength [datasetPublicationV2DictDefault $draft $key {}]]>1} {error {Saved UML scroll state requires one anchor}}}
    set destination [dict get $draft destination_id];if {$destination ne {}} {datasetPublicationV2ValidateId dataset $destination}
    return $draft
}
proc ::GX::umlEditorCommand {handle operation {request {}}} {
    variable ::GX::DocumentSource::editors
    set record [_documentEditorRecord $handle];set options [dict get $record options];set parent [dict get $record parent]
    set source [dict get $record source];set text [_documentEditorText $record];set baseline [dict get $record baseline]
    set editable [expr {[dict get $options mode] eq {editable}}];set id [datasetPublicationV2DictDefault $baseline dataset_id {}]
    if {$operation in {draft_set semantic_edit new new_sequence open save_existing publish_new cut paste undo redo replace properties restore add_class add_interface add_participant add_actor add_member add_relation add_message add_frame edit_selected delete_selected message_up message_down auto_layout}} {
        if {!$editable} {error {UML document is read-only}}
        _umlEditorGrant $record umlDocumentEdit
    }
    switch -- $operation {
        inspect {
            set valid [expr {[dict get $record session] eq [_documentEditorSessionToken]}]
            set can [expr {$valid && $editable && {umlDocumentWrite} in [dict get $options uml_operations] && [datasetPublicationV2DictDefault $baseline can_replace 0]}]
            if {$can && $id ne {} && [datasetField $id sha256 {}] ne [dict get $baseline sha256]} {set can 0}
            return [dict create status [expr {$valid?{ready}:{session_changed}}] kind uml dataset_id $id dirty [_documentEditorDirty $record $text] can_replace $can read_only [expr {!$editable}] session [dict get $record session] sha256 [datasetPublicationV2DictDefault $baseline sha256 {}] revision [datasetPublicationV2DictDefault $baseline revision {}] permission_state binding_snapshot_revalidated_on_save source_sha256 [_umlDigest $text] source_valid [dict get $record parsed valid] diagnostics [dict get $record parsed diagnostics] diagram_source_sha256 [expr {[dict get $record last_valid_source] eq {}?{}:[_umlDigest [dict get $record last_valid_source]]}] association {state unassociated} selected [dict get $record selected]]
        }
        draft_get {return [dict create text $text assets {}]}
        capture {
            set saved {}
            if {$baseline ne {}} {
                foreach key {dataset_id kind contract format media_type producer immutable sha256 revision declared_profile} {if {[dict exists $baseline $key]} {dict set saved $key [dict get $baseline $key]}}
                dict set saved revision [lreplace [dict get $saved revision] 1 1 portable]
            }
            set viewport {mode fit zoom 1.0 pan {0 0} selected {}}
            if {[dict get $record diagram] ne {}} {set viewport [umlDiagramCommand [dict get $record diagram] capture]}
            set state [dict create schema gxtxt.uml_draft.v1 text $text baseline $saved baseline_text [dict get $record baseline_text] last_valid_source [dict get $record last_valid_source] selected [dict get $record selected] view [dict get $record view] splitters [dict get $record splitters] viewport $viewport destination_id [dict get $record destination_id]]
            if {$source ne {}} {dict set state cursor [$source index insert];dict set state selection [$source tag ranges sel];dict set state xview [list [lindex [$source xview] 0]];dict set state yview [list [lindex [$source yview] 0]]}
            return [_umlEditorDraftValidate $state]
        }
        restore {
            _umlEditorDraftValidate $request
            set saved [dict get $request baseline]
            if {$saved ne {}} {
                if {![catch {set current [umlDocumentDescribe [dict get $saved dataset_id] [dict create capability [dict get $options capability]]]}] && [_datasetRevisionPortableEqual [dict get $current revision] [dict get $saved revision]]} {set saved $current
                } else {dict set saved can_replace 0}
            }
            dict set editors $handle baseline $saved;dict set editors $handle baseline_text [dict get $request baseline_text]
            dict set editors $handle destination_id [dict get $request destination_id]
            dict set editors $handle selected [dict get $request selected]
            dict set editors $handle view [dict get $request view];dict set editors $handle splitters [dict get $request splitters]
            _umlEditorView $handle
            # Recreate the explicitly labelled last-valid presentation first;
            # restore never publishes a canonical source or trusts a model blob.
            set last [dict get $request last_valid_source]
            if {$last ne {}} {sourceSurfaceSet $source $last;_umlEditorChanged $handle}
            sourceSurfaceSet $source [dict get $request text];_umlEditorChanged $handle
            set diagram [dict get $editors $handle diagram]
            if {$diagram ne {}} {umlDiagramCommand $diagram restore [dict get $request viewport]}
            if {[dict exists $request cursor]} {$source mark set insert [dict get $request cursor]}
            $source tag remove sel 1.0 end
            if {[llength [datasetPublicationV2DictDefault $request selection {}]]} {$source tag add sel {*}[dict get $request selection]}
            foreach axis {x y} {if {[dict exists $request ${axis}view]} {$source ${axis}view moveto [lindex [dict get $request ${axis}view] 0]}}
        }
        draft_set {umlDocumentParse [dict get $request text];sourceSurfaceReplace $source [dict get $request text];_umlEditorChanged $handle}
        semantic_edit {
            set result [umlDocumentEdit $text [_umlDigest $text] [dict get $request operation] [dict get $request request]]
            sourceSurfaceReplace $source [dict get $result source];_umlEditorChanged $handle
            return $result
        }
        properties {_umlEditorProperties $handle}
        add_class - add_interface - add_participant - add_actor - add_member - add_relation - add_message - add_frame - edit_selected - delete_selected - message_up - message_down - auto_layout {_umlEditorAction $handle $operation}
        render {_umlEditorChanged $handle}
        select {_umlEditorSelect $handle {} [dict get $request id]}
        zoom_in - zoom_out - zoom_reset - fit {if {[dict get $record diagram] eq {}} {error {No valid UML diagram is available}};umlDiagramCommand [dict get $record diagram] $operation}
        view_source - view_diagram - view_outline - view_properties - view_diagnostics {
            if {!$editable} {error {Read-only panes are selected by their Preview host}}
            set key [string range $operation 5 end];dict set editors $handle view $key [expr {![dict get $record view $key]}];_umlEditorView $handle
        }
        reset_layout {
            if {$editable} {dict set editors $handle view {source 1 diagram 1 outline 1 properties 0 diagnostics 0};dict set editors $handle splitters {.32 .84};_umlEditorView $handle
            } elseif {[dict get $record diagram] ne {}} {umlDiagramCommand [dict get $record diagram] fit}
        }
        new - new_sequence {
            if {[_documentEditorDirty $record $text] && ![datasetPublicationV2DictDefault $request discard_confirmed 0]} {error {Unsaved UML draft; review Save/Discard/Cancel before New}}
            set value "@startuml\n' @gx-family [expr {$operation eq {new_sequence}?{sequence}:{class}}]\n@enduml\n"
            sourceSurfaceSet $source $value;dict set editors $handle baseline {};dict set editors $handle baseline_text $value;dict set editors $handle destination_id {};_umlEditorChanged $handle
        }
        open {
            if {[_documentEditorDirty $record $text] && ![datasetPublicationV2DictDefault $request discard_confirmed 0]} {error {Unsaved UML draft; review Save/Discard/Cancel before Open}}
            _umlEditorGrant $record umlDocumentRead
            set read [umlDocumentRead [dict get $request dataset_id] [dict create capability [dict get $options capability]]]
            sourceSurfaceSet $source [dict get $read source];dict set editors $handle baseline [dict get $read description];dict set editors $handle baseline_text [dict get $read source];dict set editors $handle session [_documentEditorSessionToken];dict set editors $handle selected {};_umlEditorChanged $handle
        }
        save_existing - publish_new {
            _umlEditorGrant $record umlDocumentWrite
            set save [dict create mode [expr {$operation eq {save_existing}?{replace_existing}:{new}}] dataset_id [expr {$operation eq {save_existing}?$id:[dict get $request dataset_id]}] text $text expected_session [dict get $record session]]
            if {$operation eq {save_existing}} {if {$baseline eq {}} {error {Save Existing requires a bound canonical UML Dataset}};dict set save expected_revision [dict get $baseline revision];dict set save expected_sha256 [dict get $baseline sha256]
            } elseif {$id ne {}} {dict set save source_dataset_id $id;dict set save source_revision [dict get $baseline revision]}
            set saved [umlDocumentWrite [dict get $options capability] $save]
            dict set editors $handle baseline $saved;dict set editors $handle baseline_text $text;dict set editors $handle destination_id [dict get $saved dataset_id];_umlEditorChanged $handle
        }
        export {_umlEditorGrant $record umlDocumentExport;return [umlDocumentExport $text [dict get $request format] [datasetPublicationV2DictDefault $request options {}]]}
        cut - copy - paste - select_all - undo - redo {
            if {$source eq {}} {error {Select the Source pane for literal text operations}}
            focus $source;uiTextEdit [winfo toplevel $parent] $operation
            if {$editable} {_umlEditorChanged $handle}
        }
        find - replace {
            _umlEditorSearch $handle $operation
        }
        dispose {destroy $parent;return {status closed}}
        default {error "Unsupported finite UML editor operation: $operation"}
    }
    return [umlEditorCommand $handle inspect]
}
# Presentation availability for exact shared primary IDs. Native operation grants
# remain independently checked by the broker and actual command owner.
proc ::GX::_viewerGuiUmlActionEnabled {window action} {
    set handles {}
    dict for {component handle} [datasetPublicationV2DictDefault [dict get $::GX::ViewerGui::instances $window] document_editors {}] {
        if {[catch {set record [_documentEditorRecord $handle]}]} continue
        if {[datasetPublicationV2DictDefault [dict get $record options] kind markdown] eq {uml} && [dict get $record options mode] eq {editable}} {lappend handles $handle}
    }
    if {[llength $handles]!=1} {return {}}
    set record [_documentEditorRecord [lindex $handles 0]];set parsed [dict get $record parsed]
    set valid [dict get $parsed valid];set family [dict get $parsed family];set selected [dict get $record selected]
    set grant [dict get $record options uml_operations]
    switch -- $action {
        add_class - add_interface {return [expr {$valid && $family eq {class} && {umlDocumentEdit} in $grant}]}
        add_member - add_relation {return [expr {$valid && $family eq {class} && [dict size [dict get $parsed elements]]>0 && {umlDocumentEdit} in $grant}]}
        add_actor - add_participant {return [expr {$valid && $family eq {sequence} && {umlDocumentEdit} in $grant}]}
        add_message {return [expr {$valid && $family eq {sequence} && [dict size [dict get $parsed elements]]>0 && {umlDocumentEdit} in $grant}]}
        add_frame {return [expr {$valid && $family eq {sequence} && [llength [dict get $parsed messages]]>0 && {umlDocumentEdit} in $grant}]}
        edit_selected - delete_selected {return [expr {$valid && $selected ne {} && {umlDocumentEdit} in $grant && ![catch {umlDocumentInspectElement $parsed $selected}]}]}
        message_up - message_down {
            if {!$valid || $family ne {sequence} || {umlDocumentEdit} ni $grant} {return 0}
            set messages [dict get $parsed messages];set ids [lmap item $messages {dict get $item id}];set index [lsearch -exact $ids $selected]
            set next [expr {$index+($action eq {message_up}?-1:1)}]
            return [expr {$index>=0 && $next>=0 && $next<[llength $messages] && [dict get [lindex $messages $index] frame_context] eq [dict get [lindex $messages $next] frame_context]}]
        }
        save_existing {
            set baseline [dict get $record baseline]
            return [expr {$valid && {umlDocumentWrite} in $grant && [dict get $record session] eq [_documentEditorSessionToken] && [datasetPublicationV2DictDefault $baseline can_replace 0]}]
        }
        publish_new {return [expr {$valid && {umlDocumentWrite} in $grant && $::GX::currentSession ne {} && [dict get $record session] eq [_documentEditorSessionToken]}]}
        export_source {return [expr {{umlDocumentExport} in $grant}]}
        export_png - export_svg {return [expr {$valid && [dict get $record render_error] eq {} && [dict get $record diagram] ne {} && {umlDocumentExport} in $grant}]}
        text_undo - text_redo {return [[dict get $record source] edit [expr {$action eq {text_undo}?{canundo}:{canredo}}]]}
        auto_layout {return [expr {$valid && {umlDocumentEdit} in $grant}]}
        fit - zoom_in - zoom_out - zoom_reset {return [expr {[dict get $record diagram] ne {}}]}
        default {return {}}
    }
}

proc ::GX::_umlEditorMetadataValue {value} {
    if {$value eq {}} {return {Not declared}}
    return $value
}
proc ::GX::_umlEditorMetadataText {baseline source} {
    set text "UML document\n\nNotation: PlantUML-compatible GX-TXT subset; no full PlantUML or UML compliance claim.\n\n"
    set actualSha [_umlDigest $source]
    set canonicalSha [_umlMetadataField $baseline sha256 {}]
    if {$canonicalSha eq {}} {set verification {Local source; no canonical snapshot}} elseif {$canonicalSha eq $actualSha} {
        set verification {Exact source matches the canonical snapshot SHA-256}
    } else {set verification {Source differs from the canonical snapshot; parsed facts describe this text only}}
    append text "Source verification: $verification\n\n"
    # Always derive facts from literal source. Caller-supplied parse receipts and
    # declared metadata never become semantic or publication authority here.
    if {[catch {set parsed [umlDocumentParse $source]} reason]} {
        append text "Supported-profile parse: unavailable — $reason\n\n"
        set parsed {}
    } else {
        set family [dict get $parsed family]
        if {$family eq {}} {set family {Undetermined}} else {set family [string totitle $family]}
        append text "Diagram type (parsed): $family\n\nProfile (parsed): [dict get $parsed profile]\n\nModel schema: [dict get $parsed schema]\n\nParser version: [dict get $parsed parser_version]\n\n"
        append text "Supported-profile syntax: [expr {[dict get $parsed valid]?{Valid}:{Invalid; diagnostics follow}}]\n\n"
        append text "Elements: [dict size [dict get $parsed elements]]; relationships: [llength [dict get $parsed relations]]; messages: [llength [dict get $parsed messages]]; control frames: [dict size [dict get $parsed frames]]\n\n"
        foreach diagnostic [dict get $parsed diagnostics] {append text "Line [dict get $diagnostic line]: [dict get $diagnostic message]\n\n"}
    }
    append text "Source SHA-256 (parsed): $actualSha\n\n"
    foreach {key label} {dataset_id {Dataset ID} contract Contract format Format media_type {Media type} source_module {Source module (Registry)} producer_module {Producer module (declared)} producer_version {Producer version (declared)} namespace Namespace provenance {Provenance (declared)} source {Source (declared)}} {
        append text "$label: [_umlEditorMetadataValue [_umlMetadataField $baseline $key {}]]\n\n"
    }
    append text "Ownership: canonical producer and namespace above; immutable = [_umlEditorMetadataValue [_umlMetadataField $baseline immutable {}]].\n\n"
    set metadata [_umlMetadataField $baseline metadata {}]
    append text "Source Dataset IDs (declared): [_umlEditorMetadataValue [_umlMetadataField $baseline source_dataset_ids {}]]\n\n"
    foreach {key label} {document.source_snapshot_sha256 {Source snapshot SHA-256 (declared)} document.source_revision_state {Source revision state (declared)} document.source_revision {Source revision token (declared)}} {
        append text "$label: [_umlEditorMetadataValue [_umlMetadataField $metadata $key {}]]\n\n"
    }
    foreach {key label parsedKey} {declared_profile {Profile (declared)} profile declared_family {Diagram type (declared)} family declared_parser_version {Parser version (declared)} parser_version declared_source_sha256 {Source SHA-256 (declared)} source_sha256} {
        set declared [_umlMetadataField $baseline $key {}]
        append text "$label: [_umlEditorMetadataValue $declared]"
        if {$key eq {declared_profile} && $declared ne {} && $declared ne {gxtxt.plantuml.v1}} {
            append text { — unsupported declared profile; original source remains inspectable}
        } elseif {$declared ne {} && $parsed ne {} && $declared ne [dict get $parsed $parsedKey]} {append text { — differs from the parsed source}}
        append text "\n\n"
    }
    append text "Producer version currently installed: [_umlEditorMetadataValue [_umlMetadataField $baseline installed_producer_version {}]]\n\n"
    append text "Producer dependencies currently installed (descriptor declaration): [_umlEditorMetadataValue [_umlMetadataField $baseline installed_producer_dependencies {}]]\n\nThese describe the current installation, not the source's production environment.\n\n"
    append text "Source dependencies: external includes, macros and image assets are unsupported by gxtxt.plantuml.v1. No external source dependency is inferred.\n\n"
    set assets [_umlMetadataField $baseline assets {}]
    if {$assets eq {}} {append text "Managed resources (declared): None\n\n"} else {
        append text "Managed resources (declared; unsupported as UML source inputs):\n"
        dict for {name reference} $assets {
            if {[catch {set info [interactiveDocumentResourceInfo $reference]}]} {append text "$name — unavailable\n"} else {append text "$name — SHA-256 [dict get $info sha256], [dict get $info size_bytes] bytes\n"}
        }
        append text \n
    }
    append text "Canonical SHA-256: [_umlEditorMetadataValue $canonicalSha]\n\nFull Dataset revision (technical, inspectable):\n[_umlMetadataField $baseline revision {No canonical revision}]\n"
    return $text
}
proc ::GX::_umlEditorPreviewReceiptCommitted {handle id token before after sha} {
    if {$::GX::DatasetPrivate::activeContext ne {} || ![datasetAuthorityActive $::GX::currentSession]} {error {Readonly UML Preview receipt acknowledgement requires its CORE transaction}}
    if {[catch {set record [_documentEditorRecord $handle]}]} {return 0}
    set options [dict get $record options];set baseline [dict get $record baseline]
    if {[dict get $options mode] ne {read_only} || [datasetPublicationV2DictDefault $options kind markdown] ne {uml}
        || ![dict exists $baseline dataset_id] || [dict get $baseline dataset_id] ne $id
        || [dict get $record session] ne $token || $token ne [_documentEditorSessionToken]
        || [dict get $baseline revision] ne $before || [dict get $baseline sha256] ne $sha
        || [datasetRevisionToken $id] ne $after || [_umlDigest [_documentEditorText $record]] ne $sha
        || [dict get $record parsed source_sha256] ne $sha} {return 0}
    set description [umlDocumentDescribe $id [dict create capability [dict get $options capability]]]
    if {[dict get $description session] ne $token || [dict get $description revision] ne $after
        || [dict get $description sha256] ne $sha} {return 0}
    foreach key {kind contract format media_type producer immutable declared_profile declared_family declared_parser_version declared_source_sha256} {
        if {[datasetPublicationV2DictDefault $description $key {}] ne [datasetPublicationV2DictDefault $baseline $key {}]} {return 0}
    }
    set widget [dict get $record parent].metadata
    if {[winfo exists $widget]} {
        # Change only the literal metadata snapshot. Source, semantic model,
        # diagram/worker lifetimes, user focus and clipboard remain untouched.
        set cursor [$widget index insert];set selection [$widget tag ranges sel]
        set x [lindex [$widget xview] 0];set top [$widget index @0,0]
        set state [$widget cget -state]
        try {
            $widget configure -state normal
            $widget delete 1.0 end
            $widget insert end [_umlEditorMetadataText $description [_documentEditorText $record]]
            $widget mark set insert $cursor
            if {[llength $selection]} {$widget tag add sel {*}$selection}
            # Text estimates total wrapped height lazily. A fractional yview can
            # drift after replacement; retain the actual first display index.
            $widget xview moveto $x;$widget yview $top
        } finally {$widget configure -state $state}
    }
    dict set ::GX::DocumentSource::editors $handle baseline $description
    return 1
}
