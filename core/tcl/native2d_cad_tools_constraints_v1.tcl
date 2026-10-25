# SPDX-License-Identifier: GPL-3.0-or-later
# Shared advanced relationship/dimension GUI controllers. Native2D C owns all
# references, inference, solving and projected primitives; consumers own science.
proc ::GX::native2DCadDimensionKinds {} {
    return {distance angle radius diameter lock_x lock_y horizontal_distance vertical_distance point_line_distance line_distance axis_angle}
}
oo::define ::GX::Native2DCadCanvas::Advanced {
    variable host relationState relationRegions editor editorOptions editorValue editorAfter editorLayoutBusy
    method RelationInit {} {
        if {![info exists relationState]} {set relationState {mode {} kind {} references {} specification {} annotation {} geometry {} existing 0 selected {} hover {} status idle error {} annotation_drag {}}}
        if {![info exists relationRegions]} {set relationRegions {}}
        if {![info exists editor]} {set editor {};set editorOptions {};set editorValue {};set editorAfter {};set editorLayoutBusy 0}
    }
    method relationState {} {my RelationInit;return $relationState}
    method RelationObjects {specification} {
        set result {};foreach field {a b axis} {if {[dict exists $specification $field] && [dict get $specification $field]!=0} {lappend result [dict get $specification $field]}}
        return [lsort -integer -unique $result]
    }
    method RelationSame {a b} {
        expr {[dict get $a object]==[dict get $b object] && [dict get $a entity] eq [dict get $b entity] && [dict get $a index]==[dict get $b index]}
    }
    method RelationSelect {} {
        set members {}
        foreach ref [dict get $relationState references] {
            set kind [::GX::datasetPublicationV2DictDefault $ref semantic_kind [dict get $ref entity]]
            lappend members [dict create kind $kind id [dict get $ref object] index [expr {$kind eq {object}?0:[dict get $ref index]}]]
        }
        $host select $members
    }
    method constraint {action args} {
        my RelationInit
        if {$action ni {state cancel present pick}} {my Require}
        set cad [my context]
        if {$action in {present pick} && ($cad eq {} || ![llength [info commands $cad]] || ![dict get [$cad state] alive])} {return {}}
        switch -- $action {
            state {return $relationState}
            cancel {return [my relationCancel constraint_cancel]}
            options {
                set refs [expr {[llength $args] ? [lindex $args 0] : [dict get $relationState references]}]
                if {[llength $refs]<1 || [llength $refs]>3} {return {}}
                set available [$cad relationship options $refs];set result {}
                dict for {kind spec} $available {if {[dict get $spec general_solver] || $kind eq {fixed}} {dict set result $kind $spec}}
                return $result
            }
            start {
                lassign $args kind refs
                if {![regexp {^[a-z][a-z_]*$} $kind] || $kind in [::GX::native2DCadDimensionKinds]} {error {Choose a geometric constraint tool; dimensions use the dimension controller}}
                $host cancel advanced_tool_change
                $host tool select
                dict set relationState mode constraint;dict set relationState kind $kind;dict set relationState references $refs;dict set relationState status collecting
                my RelationSelect
                set available [my constraint options $refs]
                if {[dict exists $available $kind]} {dict set relationState specification [dict get $available $kind];dict set relationState status ready}
                return $relationState
            }
            input {
                lassign $args ref mode;if {$mode eq {}} {set mode add}
                if {[dict get $relationState mode] ne {constraint}} {error {Start a constraint tool first}}
                set refs [dict get $relationState references];set found -1;set i 0
                foreach old $refs {if {[my RelationSame $ref $old]} {set found $i;break};incr i}
                if {$mode eq {subtract}} {if {$found>=0} {set refs [lreplace $refs $found $found]}} elseif {$mode eq {replace}} {set refs [list $ref]} elseif {$mode eq {add}} {if {$found<0} {lappend refs $ref}} else {error {Unknown native reference selection mode}}
                if {[llength $refs]>3} {error {Constraints accept at most three native references}}
                dict set relationState references $refs;my RelationSelect
                set kind [dict get $relationState kind];set options [my constraint options $refs]
                dict set relationState specification {};dict set relationState error {}
                if {[dict exists $options $kind]} {
                    dict set relationState specification [dict get $options $kind];dict set relationState status ready
                } elseif {[llength $refs]>=[expr {$kind eq {symmetry}?3:$kind eq {fixed}?1:2}]} {
                    dict set relationState references {};my RelationSelect;dict set relationState status rejected
                    dict set relationState error {The selected native references do not support this relationship}
                } else {dict set relationState status collecting}
                return $relationState
            }
            apply {
                lassign $args existing spec
                if {$existing eq {}} {set existing 0}
                if {$existing==0} {dict unset spec anchor}
                set objects [my RelationObjects $spec]
                if {[dict exists $spec annotation] && [::GX::datasetPublicationV2DictDefault $spec placed 0]} {
                    set annotation [dict get $spec annotation];set reference [::GX::datasetPublicationV2DictDefault $spec driven 0]
                    set command [list $cad relationship dimension_apply $existing $spec $reference $annotation]
                } else {set command [list $cad relationship apply $existing $spec]}
                set receipt [my Run constraint.apply $objects $command [dict create specification $spec existing $existing]]
                dict set relationState status committed;dict set relationState specification $receipt
                if {[dict get $relationState mode] eq {constraint}} {dict set relationState mode {}}
                return $receipt
            }
            reference_proposal {
                set receipt [$cad relationship get [lindex $args 0]]
                if {[dict get $receipt kind] ni [::GX::native2DCadDimensionKinds]} {error {This relationship is not a dimension}}
                dict set receipt value [dict get $receipt measured_value]
                dict set receipt driven [expr {![dict get $receipt driven]}]
                return $receipt
            }
            inspect {return [$cad relationship get {*}$args]}
            list {return [$cad relationship list]}
            manage {
                lassign $args id operation value
                set receipt [$cad relationship get $id];set objects [my RelationObjects $receipt]
                switch -- $operation {
                    remove {set command [list $cad relationship remove $id]}
                    toggle {set command [list $cad relationship enable $id [dict get $receipt disabled]]}
                    enable - disable {set enabled [expr {$operation eq {enable}}];if {$enabled==![dict get $receipt disabled]} {return $receipt};set command [list $cad relationship enable $id $enabled]}
                    update {set command [list $cad relationship update $id $value]}
                    reference {
                        return [my constraint apply $id [my constraint reference_proposal $id]]
                    }
                    default {error {Unknown relationship management operation}}
                }
                set result [my Run constraint.$operation $objects $command [dict create existing $id specification $receipt]]
                if {$operation eq {remove}} {return [dict create id $id removed 1]}
                return [$cad relationship get $id]
            }
            present {return [my RelationPresent {*}$args]}
            pick {
                lassign $args xy regions
                set best {};set score Inf
                foreach id [lreverse [dict keys $regions]] {
                    set candidate [::GX::Native2D::core sketch_relationship_hit_score [my scene] $id $xy [dict get $regions $id]]
                    if {$candidate<=$score && $candidate<=7} {set best $id;set score $candidate}
                }
                return $best
            }
            default {error {Unknown shared constraint operation}}
        }
    }
    method dimension {action args} {
        my RelationInit
        if {$action ni {state cancel editor_destroy editor_layout editor_update editor_commit editor_value dispose}} {my Require}
        set cad [my context]
        switch -- $action {
            state {return $relationState}
            start {
                lassign $args forced refs
                if {$forced ne {} && $forced ni [::GX::native2DCadDimensionKinds]} {error {Unsupported native dimension kind}}
                $host cancel advanced_tool_change
                $host tool select
                dict set relationState mode dimension;dict set relationState kind $forced
                dict set relationState references [expr {[llength $refs]<=2?$refs:{}}];dict set relationState status collecting
                return $relationState
            }
            input {
                lassign $args ref modifiers
                if {$modifiers eq {}} {set modifiers 0}
                set refs [dict get $relationState references];set spec [dict get $relationState specification]
                set another [expr {$ref ne {} && ([llength $refs]==0 || ([llength $refs]==1 && ![my RelationSame $ref [lindex $refs 0]] && ($modifiers&5 || [dict get $ref entity] eq {control})))}]
                if {$spec eq {} && $ref ne {} && [llength $refs]>=1 && [dict get [lindex $refs 0] entity] ne {control}} {set refs {};set another 1}
                if {$another} {lappend refs $ref;dict set relationState references $refs;dict set relationState specification {};my RelationSelect}
                return [dict merge $relationState [dict create selected $another]]
            }
            preview {
                set refs [dict get $relationState references]
                dict set relationState specification {};dict set relationState geometry {};dict set relationState error {}
                if {$refs eq {}} {return $relationState}
                set annotation [::GX::Native2D::core world [my scene] [lindex $args 0]]
                try {
                    set forced [dict get $relationState kind]
                    if {$forced eq {}} {set spec [$cad relationship dimension_infer $refs $annotation]} else {
                        set available [$cad relationship options $refs]
                        if {![dict exists $available $forced]} {error {The selected native references do not support this dimension}}
                        set spec [dict get $available $forced]
                    }
                    set data [dict create specification $spec annotation $annotation objects [my RelationObjects $spec]]
                    if {![my Notify admit dimension.preview $data 1]} {error {Dimension preview was not admitted}}
                    set geometry [$cad relationship dimension_preview $spec $annotation]
                    dict set relationState specification $spec;dict set relationState geometry $geometry;dict set relationState annotation $annotation;dict set relationState status preview
                    my Notify preview dimension [dict merge $data [dict create geometry $geometry]]
                } on error {message options} {
                    dict set relationState status rejected;dict set relationState error $message
                }
                return $relationState
            }
            edit {
                set receipt [$cad relationship get [lindex $args 0]]
                if {[dict get $receipt kind] ni [::GX::native2DCadDimensionKinds]} {error {This relationship has no editable dimension}}
                if {[dict get $receipt driven]} {error {Reference dimensions are read-only; explicitly switch to driving first}}
                dict set relationState mode dimension;dict set relationState specification $receipt;dict set relationState annotation [dict get $receipt annotation];dict set relationState existing [dict get $receipt id]
                return $relationState
            }
            apply {
                lassign $args existing spec reference annotation
                return [my Run dimension.apply [my RelationObjects $spec] [list $cad relationship dimension_apply $existing $spec $reference $annotation] [dict create existing $existing specification $spec driven $reference annotation $annotation]]
            }
            annotation_start {
                lassign $args id device
                set receipt [$cad relationship get $id]
                if {[dict get $receipt kind] ni [::GX::native2DCadDimensionKinds]} {error {Only a dimension has this annotation workflow}}
                dict set relationState annotation_drag [dict create id $id specification $receipt start $device target [dict get $receipt annotation] changed 0]
                return [dict get $relationState annotation_drag]
            }
            annotation_move {
                set drag [dict get $relationState annotation_drag]
                if {$drag eq {}} {return {}}
                set target [::GX::Native2D::core world [my scene] [lindex $args 0]]
                dict set drag target $target;dict set drag changed [expr {$target ne [dict get $drag specification annotation]}]
                dict set relationState annotation_drag $drag
                return [dict merge $drag [dict create geometry [$cad relationship dimension_preview [dict get $drag specification] $target]]]
            }
            annotation_reset {
                set id [lindex $args 0];set receipt [$cad relationship get $id]
                if {[dict get $receipt kind] ni [::GX::native2DCadDimensionKinds]} {error {Only a dimension has this annotation workflow}}
                set point [$cad relationship location $id]
                return [my Run dimension.annotation [my RelationObjects $receipt] [list $cad relationship state $id [dict create placed 1 annotation $point]] [dict create existing $id specification $receipt annotation $point]]
            }
            annotation_commit {
                set drag [dict get $relationState annotation_drag];dict set relationState annotation_drag {}
                if {$drag eq {} || ![dict get $drag changed]} {return [dict create changed 0]}
                set id [dict get $drag id];set changes [dict create placed 1 annotation [dict get $drag target]]
                set result [my Run dimension.annotation [my RelationObjects [dict get $drag specification]] [list $cad relationship state $id $changes] [dict create existing $id specification [dict get $drag specification] annotation [dict get $drag target]]]
                return [dict merge $result [dict create changed 1]]
            }
            draw {return [my DimensionDraw {*}$args]}
            editor_create {return [my EditorCreate {*}$args]}
            editor_value {if {[llength $args]} {set editorValue [lindex $args 0]};return $editorValue}
            editor_commit {return [my EditorCommit {*}$args]}
            editor_update {return [my EditorUpdate {*}$args]}
            editor_layout {set editorAfter {};return [my EditorLayout]}
            editor_destroy {if {[lindex $args 0] eq $editor} {my EditorForget};return}
            cancel {return [my relationCancel dimension_cancel]}
            dispose {my EditorClose;return}
            default {error {Unknown shared dimension operation}}
        }
    }
    method RelationPresent {canvas ids {options {}}} {
        set defaults {selected {} hover {} show_constraints 1 show_dimensions 1 format_command {}}
        foreach key [dict keys $options] {if {![dict exists $defaults $key]} {error {Unknown relationship presentation option}}}
        set options [dict merge $defaults $options];set result {};set ordinals {};set cad [my context]
        foreach id $ids {
            set receipt [$cad relationship get $id];set kind [dict get $receipt kind];set dimensional [expr {$kind in [::GX::native2DCadDimensionKinds]}]
            if {$dimensional && ![dict get $options show_dimensions] || !$dimensional && ![dict get $options show_constraints]} continue
            set selected [expr {$id eq [dict get $options selected]}];set hover [expr {$id eq [dict get $options hover]}]
            set color [expr {$selected?{#b45400}:$hover?{#146d9b}:[dict get $receipt disabled]?{#777777}:{#744096}}]
            set tags [list constraint_marker native_constraint_$id]
            if {$dimensional} {
                set geometry [$cad relationship dimension_geometry $id]
                set drag [dict get $relationState annotation_drag]
                if {$drag ne {} && [dict get $drag id]==$id} {
                    set geometry [$cad relationship dimension_preview $receipt [dict get $drag target]]
                    dict set geometry driven [dict get $receipt driven]
                }
                set format [dict get $options format_command]
                if {$format eq {}} {set text [format %.5g [dict get $geometry value]];if {[dict get $geometry driven]} {set text "($text)"}} else {set text [uplevel #0 [list {*}$format $receipt [dict get $geometry value] [dict get $geometry driven]]]}
                dict set result $id [my DimensionDraw $canvas $geometry $text $color [dict create selected $selected tags $tags]]
            } else {
                lassign [::GX::Native2D::core device [my scene] [$cad relationship location $id]] x y
                set object [dict get $receipt a];set ordinal [::GX::datasetPublicationV2DictDefault $ordinals $object 0];dict incr ordinals $object
                set x [expr {$x+18+32*($ordinal%4)}];set y [expr {$y+22+30*($ordinal/4)}]
                set glyph [dict get {fixed F horizontal H vertical V coincident ● parallel ∥ perpendicular ⊥ tangent T equal_length = equal_radius = concentric ◎ collinear CL midpoint M point_on_line PL point_on_curve PC symmetry SY curvature G2} $kind]
                $canvas create rectangle [expr {$x-13}] [expr {$y-12}] [expr {$x+13}] [expr {$y+12}] -fill white -outline $color -width [expr {$selected||$hover?2:1}] -tags $tags
                $canvas create text $x $y -text $glyph -font TkDefaultFont -fill $color -tags $tags
                dict set result $id [list [expr {$x-17}] [expr {$y-16}] [expr {$x+17}] [expr {$y+16}]]
            }
        }
        set relationRegions $result;return $result
    }
    method DimensionDraw {canvas geometry text color {options {}}} {
        set options [dict merge {selected 0 tags {} font TkDefaultFont background white} $options]
        set selected [dict get $options selected];set tags [dict get $options tags];set font [dict get $options font]
        set dash [expr {[dict get $geometry driven]?{4 3}:{}}]
        foreach line [dict get $geometry lines] {$canvas create line {*}[concat {*}$line] -fill $color -width [expr {$selected?1.2:0.75}] -dash $dash -tags $tags}
        lassign [dict get $geometry label] x y
        set width [expr {[font measure $font $text]+14}]
        $canvas create rectangle [expr {$x-$width/2}] [expr {$y-12}] [expr {$x+$width/2}] [expr {$y+12}] -fill [dict get $options background] -outline $color -width [expr {$selected?3:1}] -tags $tags
        $canvas create text $x $y -text $text -fill $color -font $font -tags $tags
        set halfWidth [expr {max(52,([font measure $font $text]+24)/2)}];set halfHeight [expr {max(14,([font metrics $font -linespace]+12)/2)}]
        return [list [expr {$x-$halfWidth}] [expr {$y-$halfHeight}] [expr {$x+$halfWidth}] [expr {$y+$halfHeight}]]
    }
    method EditorCreate {widget options} {
        my EditorClose
        set defaults {specification {} existing 0 annotation {} value {} title Dimension message {Enter a value; Escape cancels.} parse_command {} commit_command {} accepted_command {} cancel_command {} guard_command {} native_unit {} display_unit {} absolute 0 canvas {} anchor_device {} width 280 reference_only 0 focus 1}
        foreach key [dict keys $options] {if {![dict exists $defaults $key]} {error "Unknown dimension editor option: $key"}}
        set editorOptions [dict merge $defaults $options];set editor $widget
        if {[winfo exists $editor]} {error {The dimension editor widget already exists}}
        set editorValue [dict get $editorOptions value]
        ::GX::uiFieldComponentCreate $editor panel {} {} {}
        $editor configure -padding 5 -relief ridge -borderwidth 2
        ::GX::uiFieldComponentCreate $editor.title label [dict create text [dict get $editorOptions title] wraplength 270] {} {}
        ::GX::uiFieldComponentCreate $editor.value entry {width 18} [info object namespace [self]]::editorValue {}
        ::GX::uiFieldComponentCreate $editor.commit action [dict create label [expr {[dict get $editorOptions reference_only]?{Add reference measurement}:{✓ Enter}}]] {} [list [self] dimension editor_commit [dict get $editorOptions reference_only]]
        ::GX::uiFieldComponentCreate $editor.reference action {label {Create as reference}} {} [list [self] dimension editor_commit 1]
        ::GX::uiFieldComponentCreate $editor.message label [dict create text [dict get $editorOptions message] wraplength 270] {} {}
        pack $editor.title $editor.value $editor.commit $editor.message -fill x
        bind $editor.value <Return> "[list [self] dimension editor_commit [dict get $editorOptions reference_only]];break"
        bind $editor.value <Escape> "[list [self] dimension cancel];break"
        bind $editor <Destroy> +[list [self] dimension editor_destroy %W]
        bind $editor <Configure> +[list [self] dimension editor_update {}]
        my EditorSchedule
        return $editor
    }
    method EditorSchedule {} {
        if {$editor eq {} || ![winfo exists $editor] || $editorLayoutBusy || $editorAfter ne {}} return
        set editorAfter [after idle [list [self] dimension editor_layout]]
    }
    method EditorUpdate {changes} {
        if {$editor eq {} || ![winfo exists $editor]} return
        foreach key [dict keys $changes] {
            switch -- $key {
                value {set editorValue [dict get $changes $key]}
                message - title {$editor.$key configure -text [dict get $changes $key]}
                default {error {Unsupported dimension editor update}}
            }
        }
        my EditorSchedule
        return $editor
    }
    method EditorLayout {} {
        if {$editor eq {} || ![winfo exists $editor] || $editorLayoutBusy} return
        set editorLayoutBusy 1
        try {
            set canvas [dict get $editorOptions canvas]
            if {$canvas ne {} && [winfo exists $canvas]} {
                set width [expr {max(80,min([dict get $editorOptions width],[winfo width $canvas]-20))}]
                set wrapChanged 0
                foreach child [list $editor.title $editor.message] {
                    set wrap [expr {max(30,$width-14)}]
                    if {[$child cget -wraplength]!=$wrap} {$child configure -wraplength $wrap;set wrapChanged 1}
                }
                set height [winfo reqheight $editor]
                set height [expr {min($height,max(30,[winfo height $canvas]-16))}]
                lassign [dict get $editorOptions anchor_device] x y
                set x [expr {max(8,min($x,[winfo width $canvas]-$width-8))}]
                set y [expr {max(8,min($y+18,[winfo height $canvas]-$height-8))}]
                place $editor -in $canvas -x $x -y $y -width $width -height $height
                raise $editor
            }
        } finally {set editorLayoutBusy 0}
        if {[dict get $editorOptions focus]} {focus $editor.value;$editor.value selection range 0 end;dict set editorOptions focus 0}
        if {[info exists wrapChanged] && $wrapChanged} {my EditorSchedule}
    }
    method EditorForget {} {
        if {$editorAfter ne {}} {after cancel $editorAfter}
        set editorAfter {};set editor {};set editorOptions {}
    }
    method EditorClose {} {
        if {$editor ne {} && [winfo exists $editor]} {set widget $editor;my EditorForget;destroy $widget} else {my EditorForget}
    }
    method EditorParse {text} {
        set spec [dict get $editorOptions specification];set parse [dict get $editorOptions parse_command]
        if {$parse ne {}} {return [uplevel #0 [list {*}$parse $spec $text]]}
        set from [dict get $editorOptions display_unit];set to [dict get $editorOptions native_unit]
        set text [string trim $text]
        if {[regexp {^([+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)\s+(\S+)$} $text -> value unit]} {set from $unit} else {set value [::GX::uiFieldNormalize {type number} $text]}
        if {$from ne $to} {
            set plan [::GX::unitRegistryAffinePlan $from $to]
            if {![dict get $plan affine]} {error {Dimension input requires an explicit affine unit relation}}
            set value [expr {$value*[dict get $plan scale]+([dict get $editorOptions absolute]?[dict get $plan offset]:0)}]
        }
        set value [::GX::uiFieldNormalize {type number} $value]
        return [dict create value $value expression $value]
    }
    method EditorCommit {{reference 0}} {
        if {$editor eq {} || ![winfo exists $editor]} {error {The dimension editor has closed}}
        set widget $editor
        try {
            my Require
            set guard [dict get $editorOptions guard_command]
            if {$guard ne {} && ![uplevel #0 [list {*}$guard]]} {error {The dimension editor scientific owner is stale}}
            set parsed [my EditorParse $editorValue];set spec [dict get $editorOptions specification]
            dict set spec value [dict get $parsed value];dict set spec annotation [dict get $editorOptions annotation];dict set spec placed 1;dict set spec driven $reference
            set event [dict create specification $spec existing [dict get $editorOptions existing] expression [dict get $parsed expression] reference $reference annotation [dict get $editorOptions annotation]]
            set commit [dict get $editorOptions commit_command]
            if {$commit eq {}} {set receipt [my dimension apply [dict get $event existing] $spec $reference [dict get $event annotation]]} else {set receipt [uplevel #0 [list {*}$commit $event]]}
            set accepted [dict get $editorOptions accepted_command]
            if {$accepted ne {}} {uplevel #0 [list {*}$accepted [dict merge $event [dict create receipt $receipt]]]}
        } on error {message options} {
            if {[winfo exists $widget]} {
                $widget.message configure -text "Dimension rejected: $message."
                if {$message in {{constraint violation} locked} && !$reference} {$widget.message configure -text {This driving dimension conflicts with the sketch. Create a reference measurement instead?};pack $widget.reference -fill x}
                my EditorSchedule
            }
            return [dict create status rejected error $message]
        }
        my EditorClose
        dict set relationState specification {};dict set relationState references {};dict set relationState annotation {};dict set relationState geometry {};dict set relationState existing 0;dict set relationState status committed
        $host refresh final
        return [dict create status committed receipt $receipt]
    }
    method relationCancel {{reason cancel}} {
        my RelationInit
        set mode [dict get $relationState mode];set cancel [::GX::datasetPublicationV2DictDefault $editorOptions cancel_command {}]
        my EditorClose
        set relationState {mode {} kind {} references {} specification {} annotation {} geometry {} existing 0 selected {} hover {} status idle error {} annotation_drag {}}
        if {$cancel ne {}} {uplevel #0 [list {*}$cancel $reason]}
        if {$mode ne {}} {my Notify cancelled $mode [dict create reason $reason]}
        return $relationState
    }
    method relationOverlay {} {
        my RelationInit
        if {[dict get [$host configure] external_render]} return
        set canvas [$host canvas]
        $canvas delete constraint_marker cad_relation_preview
        set cad [my context]
        if {$cad eq {} || ![llength [info commands $cad]] || ![dict get [$cad state] alive]} return
        set ids [lmap receipt [$cad relationship list] {dict get $receipt id}]
        my constraint present $canvas $ids [dict create selected [dict get $relationState selected] hover [dict get $relationState hover]]
        # A proposal is only native projected geometry until an explicit commit.
        # Existing annotation drags are already substituted by RelationPresent.
        if {[dict get $relationState mode] eq {dimension} && [dict get $relationState status] eq {preview} && [dict get $relationState specification] ne {} && [dict get $relationState geometry] ne {}} {
            set geometry [$cad relationship dimension_preview [dict get $relationState specification] [dict get $relationState annotation]]
            dict set relationState geometry $geometry
            set text [format %.5g [dict get $geometry value]]
            if {[dict get $geometry driven]} {set text "($text)"}
            my DimensionDraw $canvas $geometry $text #2a7b60 [dict create tags cad_relation_preview]
        }
    }
    method relationEvent {phase args} {
        my RelationInit
        set mode [dict get $relationState mode]
        set annotation [dict get $relationState annotation_drag]
        if {$annotation ne {}} {
            if {$phase eq {move}} {my dimension annotation_move [lrange $args 0 1];$host refresh interaction;return 1}
            if {$phase eq {up}} {my dimension annotation_commit;$host refresh final;return 1}
            if {$phase eq {key} && [lindex $args 0] eq {Escape}} {dict set relationState annotation_drag {};$host refresh final;return 1}
        }
        if {$mode eq {}} {
            if {[dict get [$host configure] external_render] || [$host tool] ne {select}} {return 0}
            if {$phase eq {down}} {
                set xy [lrange $args 0 1];set modifiers [lindex $args 2]
                if {$modifiers eq {}} {set modifiers 0}
                set id [my constraint pick $xy $relationRegions];set geometry [$host pick $xy detail]
                if {$modifiers&5 || ($geometry ne {} && [dict get $geometry entity] eq {control} && $id ne [dict get $relationState selected])} {return 0}
                if {$id ne {}} {
                    $host select {}
                    dict set relationState selected $id
                    set receipt [[my context] relationship get $id]
                    if {[dict get $receipt kind] in [::GX::native2DCadDimensionKinds] && [dict get $receipt placed]} {my dimension annotation_start $id $xy}
                    my Notify selected relationship [dict create existing $id receipt $receipt]
                    $host refresh final;return 1
                }
            } elseif {$phase eq {move}} {
                set hover [my constraint pick [lrange $args 0 1] $relationRegions]
                if {$hover ne [dict get $relationState hover]} {dict set relationState hover $hover;$host refresh interaction}
            }
            return 0
        }
        if {$phase eq {key} && [lindex $args 0] eq {Escape}} {my relationCancel escape;$host refresh final;return 1}
        if {$editor ne {}} {return [expr {$phase in {down move up key}}]}
        set xy [lrange $args 0 1]
        if {$phase eq {move} && $mode eq {dimension}} {my dimension preview $xy;$host refresh interaction;return 1}
        if {$phase eq {down}} {
            set ref [$host pick $xy detail];set modifiers [lindex $args 2];if {$modifiers eq {}} {set modifiers 0}
            if {$mode eq {constraint}} {
                if {$ref eq {}} {return 1}
                set state [my constraint input $ref [expr {$modifiers&1?{subtract}:{add}}]]
                if {[dict get $state status] eq {ready}} {my constraint apply 0 [dict get $state specification]}
            } else {
                set state [my dimension input $ref $modifiers]
                if {![dict get $state selected] && [dict get $state specification] ne {}} {
                    set state [my dimension preview $xy]
                    if {[dict get $state specification] ne {}} {
                        set spec [dict get $state specification]
                        my dimension editor_create [$host canvas].dimensionEditor [dict create specification $spec annotation [dict get $state annotation] value [dict get $spec value] canvas [$host canvas] anchor_device $xy]
                    }
                } else {my dimension preview $xy}
            }
            $host refresh interaction;return 1
        }
        return [expr {$phase eq {up}}]
    }
}
