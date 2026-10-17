# SPDX-License-Identifier: GPL-3.0-or-later
# Shared declarative value and widget authority. Scientific alpha is never
# inferred from presentation opacity; callers declare the field's semantics.
namespace eval ::GX::UiField {
    variable widgets {}
    variable errors
    variable alpha
    variable rgb
    variable forms {}
    variable formValues
    variable formStatus
}
proc ::GX::uiFieldApiInfo {} {
    return [dict create api_id UI_FIELD_API_v1 api_version 1 types {string integer double number boolean choice color path file command} color_format #RRGGBB alpha_format {rgb #RRGGBB alpha 0..1} host_operations {uiFieldFormCreate uiFieldFormSectionEnabled uiFieldViewerShellCreate uiFieldSelectorWithinViewer uiFieldSelectorPost uiFieldSelectorClose uiMenuPopup uiMenuWorkarea uiMenuRowAttach}]
}

# Viewer-bounded choice projection. The combobox remains the value/variable
# owner; a native listbox in its Viewer replaces only platform popdown placement.
proc ::GX::uiFieldSelectorWithinViewer {widget viewer} {
    if {[winfo class $widget] ne "TCombobox" || [winfo toplevel $widget] ne $viewer} {error {Expected a combobox inside its owning Viewer}}
    set tag GXBoundedSelector$widget
    if {$tag in [bindtags $widget]} {return $widget}
    bindtags $widget [linsert [bindtags $widget] 0 $tag]
    set resizeTag GXBoundedSelectorViewer$widget
    bindtags $viewer [linsert [bindtags $viewer] 0 $resizeTag]
    bind $resizeTag <Configure> [list ::GX::_uiFieldSelectorViewerChanged $widget $viewer %W]
    foreach sequence {<Button-1> <Key-Down> <Key-Up> <Key-space> <Key-Return>} {
        bind $tag $sequence [format {::GX::uiFieldSelectorPost %s %s; break} [list $widget] [list $viewer]]
    }
    bind $tag <Escape> [list ::GX::uiFieldSelectorClose $widget $viewer]
    bind $widget <Destroy> +[list ::GX::_uiFieldSelectorDestroyed $widget $viewer %W]
    return $widget
}
proc ::GX::_uiFieldSelectorPanel {widget viewer} {return $viewer.gxSelector_[binary encode hex [encoding convertto utf-8 $widget]]}
proc ::GX::_uiFieldSelectorDestroyed {widget viewer destroyed} {
    if {$widget eq $destroyed} {
        catch {destroy [_uiFieldSelectorPanel $widget $viewer]}
        set resizeTag GXBoundedSelectorViewer$widget
        bind $resizeTag <Configure> {}
        if {[winfo exists $viewer]} {set tags [bindtags $viewer];set i [lsearch -exact $tags $resizeTag];if {$i>=0} {bindtags $viewer [lreplace $tags $i $i]}}
        bind GXBoundedSelector$widget <Button-1> {}
        foreach sequence {<Key-Down> <Key-Up> <Key-space> <Key-Return> <Escape>} {bind GXBoundedSelector$widget $sequence {}}
    }
}
proc ::GX::uiFieldSelectorClose {widget viewer {accept 0}} {
    set panel [_uiFieldSelectorPanel $widget $viewer]
    if {![winfo exists $panel]} return
    set selected [$panel.options curselection]
    set value [expr {$selected eq {}?{}:[$panel.options get [lindex $selected 0]]}]
    catch {grab release $panel};destroy $panel
    if {[winfo exists $widget]} {
        focus $widget
        if {$accept && $selected ne {}} {$widget set $value;event generate $widget <<ComboboxSelected>>}
    }
}
proc ::GX::_uiFieldSelectorClick {widget viewer x y} {
    set panel [_uiFieldSelectorPanel $widget $viewer]
    if {$x<0 || $y<0 || $x>=[winfo width $panel] || $y>=[winfo height $panel]} {uiFieldSelectorClose $widget $viewer}
}
proc ::GX::_uiFieldSelectorTab {widget viewer} {
    uiFieldSelectorClose $widget $viewer
    if {[winfo exists $widget]} {focus [tk_focusNext $widget]}
}
proc ::GX::uiFieldSelectorPost {widget viewer} {
    if {![winfo exists $widget] || ![winfo viewable $viewer] || [$widget instate disabled]} return
    set panel [_uiFieldSelectorPanel $widget $viewer]
    if {[winfo exists $panel]} {uiFieldSelectorClose $widget $viewer;return}
    set values [$widget cget -values]
    if {$values eq {}} return
    update idletasks
    set width [winfo width $viewer];set height [winfo height $viewer]
    if {$width<24 || $height<24} return
    set x [expr {[winfo rootx $widget]-[winfo rootx $viewer]}]
    set y [expr {[winfo rooty $widget]-[winfo rooty $viewer]}]
    set line [expr {[font metrics TkDefaultFont -linespace]+6}]
    set desired [expr {min(12,[llength $values])*$line+6}]
    set below [expr {max(0,$height-$y-[winfo height $widget]-4)}]
    set above [expr {max(0,$y-4)}]
    set ph [expr {min($desired,max($above,$below),$height-8)}]
    # A very short Viewer uses an interior scrollable projection over its body.
    if {$ph<$line+6} {set ph [expr {$height-8}];set py 4
    } elseif {$below>=$desired} {set py [expr {$y+[winfo height $widget]}]
    } elseif {$above>=$below} {set py [expr {$y-$ph}]
    } else {set py [expr {$y+[winfo height $widget]}]}
    set pw [expr {min($width-8,max(160,[winfo width $widget]))}]
    set px [expr {max(4,min($x,$width-$pw-4))}]
    set py [expr {max(4,min($py,$height-$ph-4))}]
    ttk::frame $panel -relief solid -borderwidth 1
    listbox $panel.options -exportselection 0 -activestyle dotbox -selectmode browse -height 1 -borderwidth 0 -yscrollcommand [list $panel.scroll set]
    ttk::scrollbar $panel.scroll -command [list $panel.options yview]
    pack $panel.scroll -side right -fill y;pack $panel.options -fill both -expand 1
    foreach value $values {$panel.options insert end $value}
    set selected [lsearch -exact $values [$widget get]]
    if {$selected<0} {set selected 0}
    $panel.options selection set $selected;$panel.options activate $selected;$panel.options see $selected
    place $panel -x $px -y $py -width $pw -height $ph
    raise $panel;focus $panel.options;grab $panel
    bind $panel <Button-1> [list ::GX::_uiFieldSelectorClick $widget $viewer %x %y]
    bind $panel.options <ButtonRelease-1> "[list ::GX::uiFieldSelectorClose $widget $viewer 1];break"
    bind $panel.options <Return> "[list ::GX::uiFieldSelectorClose $widget $viewer 1];break"
    bind $panel.options <Escape> "[list ::GX::uiFieldSelectorClose $widget $viewer];break"
    bind $panel.options <Tab> [format {::GX::_uiFieldSelectorTab %s %s; break} [list $widget] [list $viewer]]
    bind $panel <Configure> [list ::GX::_uiFieldSelectorResize $widget $viewer $width $height %W]
    bind $panel <<ViewerResized>> [list ::GX::_uiFieldSelectorResize $widget $viewer $width $height %W]
}
proc ::GX::_uiFieldSelectorResize {widget viewer width height changed} {
    set panel [_uiFieldSelectorPanel $widget $viewer]
    if {![winfo exists $viewer] || ![winfo exists $panel]} return
    set vw [winfo width $viewer];set vh [winfo height $viewer]
    if {$vw==$width && $vh==$height} return
    if {$vw<24 || $vh<24} {uiFieldSelectorClose $widget $viewer;return}
    set info [place info $panel];set pw [expr {min([dict get $info -width],$vw-8)}];set ph [expr {min([dict get $info -height],$vh-8)}]
    set px [expr {max(4,min([dict get $info -x],$vw-$pw-4))}];set py [expr {max(4,min([dict get $info -y],$vh-$ph-4))}]
    if {[dict get $info -x]!=$px || [dict get $info -y]!=$py || [dict get $info -width]!=$pw || [dict get $info -height]!=$ph} {place configure $panel -x $px -y $py -width $pw -height $ph}
}
proc ::GX::uiFieldColor {value {withAlpha 0}} {
    set opacity 1.0
    if {$withAlpha && ![catch {dict size $value}] && [dict exists $value rgb]} {
        foreach key [dict keys $value] {if {$key ni {rgb alpha}} {error "Unknown color field '$key'"}}
        set opacity [datasetPublicationV2DictDefault $value alpha 1.0]
        set value [dict get $value rgb]
    }
    set names [dict create white #FFFFFF black #000000 red #FF0000 blue #0000FF green #008000 yellow #FFFF00 cyan #00FFFF magenta #FF00FF gray #808080 grey #808080 orange #FFA500]
    set value [string trim $value]
    if {[dict exists $names [string tolower $value]]} {set value [dict get $names [string tolower $value]]}
    if {[regexp {^#([0-9a-fA-F])([0-9a-fA-F])([0-9a-fA-F])$} $value -> r g b]} {set value "#$r$r$g$g$b$b"}
    if {![regexp {^#[0-9a-fA-F]{6}$} $value]} {error "Enter an RGB color as #RRGGBB"}
    set value [string toupper $value]
    if {![string is double -strict $opacity] || $opacity != $opacity || abs($opacity)==Inf || $opacity<0 || $opacity>1} {error "Color opacity must be a finite number from 0 to 1"}
    if {$withAlpha} {return [dict create rgb $value alpha [format %.17g $opacity]]}
    return $value
}
proc ::GX::uiFieldNormalize {descriptor value} {
    set type [string tolower [datasetPublicationV2DictDefault $descriptor type string]]
    if {$type ni [dict get [uiFieldApiInfo] types]} {error "Unsupported UI field type '$type'"}
    set required [datasetPublicationV2DictDefault $descriptor required 0]
    set inherit [datasetPublicationV2DictDefault $descriptor allow_inherit 0]
    if {[string trim $value] eq ""} {
        if {$inherit} {return ""}
        if {$required} {error "[datasetPublicationV2DictDefault $descriptor label Value] is required"}
        if {$type in {string path file command choice color}} {return ""}
    }
    switch -- $type {
        integer {
            if {![string is entier -strict $value]} {error "Enter an integer"}
            set value [expr {$value+0}]
        }
        double - number {
            if {![string is double -strict $value] || [catch {expr {double($value)}} number] || $number!=$number || abs($number)==Inf} {error "Enter a finite number"}
            set value [format %.17g $number]
        }
        boolean {
            if {![string is boolean -strict $value]} {error "Enter a boolean value"}
            set value [expr {$value ? 1 : 0}]
        }
        choice {
            set choices [datasetPublicationV2DictDefault $descriptor values {}]
            if {$value ni $choices} {error "Choose one of: [join $choices {, }]"}
        }
        color {return [uiFieldColor $value [datasetPublicationV2DictDefault $descriptor alpha 0]]}
        path - file - command {
            set value [string trim $value]
            if {[regexp {[\r\n]} $value]} {error "Enter a single-line path or command"}
        }
        default {set value [string trim $value]}
    }
    if {$type in {integer double number}} {
        if {[dict exists $descriptor min] && $value < [dict get $descriptor min]} {error "Value must be at least [dict get $descriptor min]"}
        if {[dict exists $descriptor max] && $value > [dict get $descriptor max]} {error "Value must be at most [dict get $descriptor max]"}
    }
    return $value
}
proc ::GX::uiFieldColorComponents {value} {
    if {![catch {dict size $value}] && [dict exists $value rgb]} {return [uiFieldColor $value 1]}
    return [dict create rgb [uiFieldColor $value] alpha 1.0]
}
proc ::GX::uiFieldColorToRGBA {value} {
    set color [uiFieldColorComponents $value]
    scan [string range [dict get $color rgb] 1 end] %2x%2x%2x r g b
    return [list [expr {$r/255.0}] [expr {$g/255.0}] [expr {$b/255.0}] [dict get $color alpha]]
}
proc ::GX::uiFieldColorFromRGBA {rgba} {
    if {[llength $rgba]!=4} {error "Expected normalized RGBA components"}
    foreach component $rgba {uiFieldNormalize {type number min 0 max 1 required 1} $component}
    lassign $rgba r g b alpha
    return [dict create rgb [format #%02X%02X%02X [expr {round($r*255)}] [expr {round($g*255)}] [expr {round($b*255)}]] alpha [format %.17g $alpha]]
}
proc ::GX::uiFieldColorComposite {foreground background} {
    lassign [uiFieldColorToRGBA $foreground] r g b alpha
    lassign [uiFieldColorToRGBA $background] br bg bb ba
    set outAlpha [expr {$alpha+$ba*(1-$alpha)}]
    if {$outAlpha==0} {return {rgb #000000 alpha 0}}
    return [uiFieldColorFromRGBA [list [expr {($r*$alpha+$br*$ba*(1-$alpha))/$outAlpha}] [expr {($g*$alpha+$bg*$ba*(1-$alpha))/$outAlpha}] [expr {($b*$alpha+$bb*$ba*(1-$alpha))/$outAlpha}] $outAlpha]]
}
proc ::GX::uiFieldCreate {widget descriptor variableName {changed ""}} {
    variable ::GX::UiField::widgets
    variable ::GX::UiField::errors
    variable ::GX::UiField::alpha
    upvar #0 $variableName value
    if {![info exists value]} {set value [datasetPublicationV2DictDefault $descriptor default ""]}
    set type [datasetPublicationV2DictDefault $descriptor type string]
    ttk::frame $widget
    grid columnconfigure $widget 0 -weight 1
    set initial $value
    if {![catch {uiFieldNormalize $descriptor $value} normalized]} {set initial $normalized}
    dict set widgets $widget [dict create descriptor $descriptor variable $variableName changed $changed committed $initial]
    set errors($widget) ""
    switch -- $type {
        boolean {ttk::checkbutton $widget.entry -variable $variableName -command [list ::GX::uiFieldCommit $widget]}
        choice {
            ttk::combobox $widget.entry -textvariable $variableName -state readonly -width 24 -values [datasetPublicationV2DictDefault $descriptor values {}]
            bind $widget.entry <<ComboboxSelected>> [list ::GX::uiFieldCommit $widget]
        }
        default {
            ttk::entry $widget.entry -textvariable $variableName -width 24
            bind $widget.entry <Return> [list ::GX::uiFieldCommit $widget]
            bind $widget.entry <FocusOut> [list ::GX::uiFieldCommit $widget]
        }
    }
    grid $widget.entry -row 0 -column 0 -sticky ew
    if {$type eq "color"} {
        set ::GX::UiField::rgb($widget) $value
        $widget.entry configure -textvariable ::GX::UiField::rgb($widget)
        # A named button supplies meaning and keyboard focus as well as a swatch.
        button $widget.swatch -text "Choose color…" -command [list ::GX::uiFieldChooseColor $widget] -takefocus 1 -padx 5
        grid $widget.swatch -row 0 -column 1 -padx {5 0}
        if {[datasetPublicationV2DictDefault $descriptor alpha 0]} {
            set alpha($widget) 1.0
            ttk::label $widget.opacityLabel -text "Opacity (0–1)"
            ttk::entry $widget.opacity -textvariable ::GX::UiField::alpha($widget) -width 8
            bind $widget.opacity <Return> [list ::GX::uiFieldCommitAlpha $widget]
            bind $widget.opacity <FocusOut> [list ::GX::uiFieldCommitAlpha $widget]
            grid $widget.opacityLabel -row 1 -column 0 -sticky e -pady 3
            grid $widget.opacity -row 1 -column 1 -sticky ew -pady 3
        }
        uiFieldRefreshColor $widget
    }
    if {[dict exists $descriptor default]} {
        ttk::button $widget.reset -text Reset -command [list ::GX::uiFieldReset $widget default]
        if {$type eq "color"} {grid $widget.reset -row 3 -column 0 -sticky w -pady 3} else {grid $widget.reset -row 0 -column 2 -padx 5}
    }
    if {[datasetPublicationV2DictDefault $descriptor allow_inherit 0]} {
        ttk::button $widget.inherit -text Inherit -command [list ::GX::uiFieldReset $widget inherit]
        if {$type eq "color"} {grid $widget.inherit -row 3 -column 1 -sticky w -pady 3} else {grid $widget.inherit -row 0 -column 3 -padx 5}
    }
    ttk::label $widget.error -textvariable ::GX::UiField::errors($widget) -wraplength 480
    grid $widget.error -row 2 -column 0 -columnspan 4 -sticky w
    if {[datasetPublicationV2DictDefault $descriptor compact 0]} {grid remove $widget.error}
    bind $widget <Destroy> [list ::GX::uiFieldDestroy $widget %W]
    if {$type eq "color"} {bind $widget <Configure> [list ::GX::uiFieldColorLayout $widget %w]}
    return $widget
}
proc ::GX::uiFieldColorLayout {widget width} {
    variable ::GX::UiField::widgets
    if {![dict exists $widgets $widget]} return
    set portrait [expr {$width < [winfo reqwidth $widget.entry]+[winfo reqwidth $widget.swatch]+20}]
    if {[dict exists $widgets $widget portrait] && [dict get $widgets $widget portrait]==$portrait} return
    dict set widgets $widget portrait $portrait
    if {$portrait} {
        grid configure $widget.entry -columnspan 2
        grid configure $widget.swatch -row 1 -column 0 -columnspan 2 -sticky w -padx 0 -pady 4
        set row 2
    } else {
        grid configure $widget.entry -columnspan 1
        grid configure $widget.swatch -row 0 -column 1 -columnspan 1 -sticky ew -padx {5 0} -pady 0
        set row 1
    }
    if {[winfo exists $widget.opacity]} {
        grid configure $widget.opacityLabel -row $row
        grid configure $widget.opacity -row $row
    }
    grid configure $widget.error -row [expr {$row+1}]
    foreach child {reset inherit} {
        if {[winfo exists $widget.$child]} {grid configure $widget.$child -row [expr {$row+2}]}
    }
}
proc ::GX::uiFieldDestroy {widget actual} {
    if {$widget ne $actual} return
    variable ::GX::UiField::widgets
    dict unset widgets $widget
    unset -nocomplain ::GX::UiField::errors($widget) ::GX::UiField::alpha($widget) ::GX::UiField::rgb($widget)
}
proc ::GX::uiFieldCommit {widget} {
    variable ::GX::UiField::widgets;variable ::GX::UiField::errors
    if {![dict exists $widgets $widget]} return
    set state [dict get $widgets $widget]
    upvar #0 [dict get $state variable] value
    set candidate $value
    if {[dict get $state descriptor type] eq "color"} {
        set candidate $::GX::UiField::rgb($widget)
        if {$candidate ne "" && [datasetPublicationV2DictDefault [dict get $state descriptor] alpha 0]} {
            set candidate [dict create rgb $candidate alpha $::GX::UiField::alpha($widget)]
        }
    }
    if {[catch {uiFieldNormalize [dict get $state descriptor] $candidate} canonical]} {
        set errors($widget) $canonical
        if {[datasetPublicationV2DictDefault [dict get $state descriptor] compact 0]} {grid $widget.error}
        $widget.entry state invalid
        return 0
    }
    if {[datasetPublicationV2DictDefault [dict get $state descriptor] compact 0]} {grid remove $widget.error}
    set value $canonical;set errors($widget) "";$widget.entry state !invalid
    if {[dict get $state descriptor type] eq "color"} {uiFieldRefreshColor $widget}
    dict set widgets $widget committed $canonical
    if {$canonical ne [dict get $state committed] && [dict get $state changed] ne ""} {uplevel #0 [list {*}[dict get $state changed] $value]}
    return 1
}
proc ::GX::uiFieldColorReadableText {background} {
    set color [dict get [uiFieldColorComposite $background #FFFFFF] rgb]
    scan [string range $color 1 end] %2x%2x%2x r g b
    set luminance 0.0
    foreach component [list $r $g $b] weight {.2126 .7152 .0722} {
        set normalized [expr {$component/255.0}]
        set linear [expr {$normalized<=.04045 ? $normalized/12.92 : pow(($normalized+.055)/1.055,2.4)}]
        set luminance [expr {$luminance+$weight*$linear}]
    }
    return [expr {$luminance>.179 ? "#000000" : "#FFFFFF"}]
}
proc ::GX::uiFieldRefreshColor {widget} {
    variable ::GX::UiField::widgets;variable ::GX::UiField::alpha
    set state [dict get $widgets $widget]
    upvar #0 [dict get $state variable] value
    if {$value eq ""} {set ::GX::UiField::rgb($widget) "";$widget.swatch configure -text "Choose color… (inherit)" -background #D9D9D9 -foreground #000000;return}
    if {[catch {uiFieldColorComponents $value} components]} return
    set rgb [dict get $components rgb]
    set ::GX::UiField::rgb($widget) $rgb
    set foreground [uiFieldColorReadableText $rgb]
    $widget.swatch configure -text "Choose color… $rgb" -background $rgb -foreground $foreground
    set alpha($widget) [dict get $components alpha]
}
proc ::GX::uiFieldChooseColor {widget} {
    variable ::GX::UiField::widgets
    set state [dict get $widgets $widget]
    upvar #0 [dict get $state variable] value
    set initial #FFFFFF;set opacity 1
    if {$value ne "" && ![catch {uiFieldColorComponents $value} components]} {set initial [dict get $components rgb];set opacity [dict get $components alpha]}
    set chosen [tk_chooseColor -parent [winfo toplevel $widget] -title "Choose RGB color" -initialcolor $initial]
    if {$chosen eq ""} return
    set value [expr {[datasetPublicationV2DictDefault [dict get $state descriptor] alpha 0] ? [dict create rgb $chosen alpha $opacity] : $chosen}]
    uiFieldRefreshColor $widget
    uiFieldCommit $widget
}
proc ::GX::uiFieldCommitAlpha {widget} {
    variable ::GX::UiField::widgets;variable ::GX::UiField::alpha;variable ::GX::UiField::errors
    set state [dict get $widgets $widget]
    upvar #0 [dict get $state variable] value
    if {[catch {uiFieldColorComponents $value} components]} {set errors($widget) $components;return 0}
    return [uiFieldCommit $widget]
}
proc ::GX::uiFieldReset {widget mode} {
    variable ::GX::UiField::widgets
    set state [dict get $widgets $widget]
    upvar #0 [dict get $state variable] value
    set value [expr {$mode eq "inherit" ? "" : [dict get $state descriptor default]}]
    if {[dict get $state descriptor type] eq "color"} {uiFieldRefreshColor $widget}
    uiFieldCommit $widget
}
proc ::GX::uiFieldFormCreate {window title fields initial apply {parent ""} {sections {}}} {
    variable ::GX::UiField::forms
    variable ::GX::UiField::formValues
    variable ::GX::UiField::formStatus
    if {[winfo exists $window]} {destroy $window}
    toplevel $window;wm title $window $title;wm geometry $window 650x620
    wm minsize $window 430 300
    if {$parent ne ""} {wm transient $window $parent}
    ttk::frame $window.actions
    ttk::button $window.actions.apply -text Apply -command [list ::GX::uiFieldFormApply $window]
    ttk::button $window.actions.close -text Close -command [list destroy $window]
    pack $window.actions.apply $window.actions.close -side left -padx 4
    pack $window.actions -side bottom -anchor e -padx 8 -pady 8
    set formStatus($window) ""
    ttk::label $window.status -textvariable ::GX::UiField::formStatus($window) -wraplength 580
    pack $window.status -side bottom -fill x -padx 8
    ttk::scrollbar $window.scroll -orient vertical -command [list $window.viewport yview]
    canvas $window.viewport -highlightthickness 0 -width 600
    $window.viewport configure -yscrollcommand [list $window.scroll set]
    ttk::frame $window.viewport.content -padding 8
    $window.viewport create window 0 0 -window $window.viewport.content -anchor nw -tags content
    bind $window.viewport <Configure> [list ::GX::uiFieldFormLayout $window %w]
    bind $window.viewport.content <Configure> [list $window.viewport configure -scrollregion [list 0 0 %w %h]]
    pack $window.scroll -side right -fill y
    pack $window.viewport -fill both -expand 1
    set mapping {};set row 0;set sectionRows {}
    if {$sections ne {}} {
        ttk::notebook $window.viewport.content.sections
        grid $window.viewport.content.sections -row 0 -column 0 -sticky nsew
        bind $window.viewport.content.sections <<NotebookTabChanged>> [list ::GX::uiFieldFormSectionLayout $window]
        dict for {section title} $sections {
            ttk::frame $window.viewport.content.sections.$section -padding 6
            $window.viewport.content.sections add $window.viewport.content.sections.$section -text $title
            grid columnconfigure $window.viewport.content.sections.$section 1 -weight 1
            dict set sectionRows $section 0
        }
    }
    dict for {key descriptor} $fields {
        set formValues($window,$key) [datasetPublicationV2DictDefault $initial $key [datasetPublicationV2DictDefault $descriptor default ""]]
        set frame $window.viewport.content
        set section [datasetPublicationV2DictDefault $descriptor section {}]
        if {$section ne {}&&$sections ne {}} {set frame $frame.sections.$section}
        ttk::label $frame.label$row -text [datasetPublicationV2DictDefault $descriptor label $key]
        if {$sections ne {}} {dict set descriptor compact 1}
        uiFieldCreate $frame.field$row $descriptor ::GX::UiField::formValues($window,$key)
        if {$sections ne {}&&$section ne {}} {
            set sr [dict get $sectionRows $section];dict incr sectionRows $section
            grid $frame.label$row -row $sr -column 0 -sticky nw -padx 4 -pady 2
            grid $frame.field$row -row $sr -column 1 -sticky ew -padx 4 -pady 2
        } else {
            grid $frame.label$row -row [expr {2*$row}] -column 0 -sticky nw -padx 5 -pady {6 1}
            grid $frame.field$row -row [expr {2*$row+1}] -column 0 -sticky ew -padx 5 -pady {1 6}
        }
        foreach child {entry opacity swatch reset inherit} {
            if {[winfo exists $frame.field$row.$child]} {bind $frame.field$row.$child <FocusIn> +[list ::GX::uiFieldFormSee $window $frame.field$row]}
        }
        dict set mapping $key $frame.field$row
        incr row
    }
    grid columnconfigure $window.viewport.content 0 -weight 1
    dict set forms $window [dict create fields $fields widgets $mapping apply $apply]
    bind $window <Escape> [list destroy $window]
    bind $window <Destroy> [list ::GX::uiFieldFormDestroy $window %W]
    if {$sections ne {}} {after idle [list ::GX::uiFieldFormSectionLayout $window]}
    return $window
}
proc ::GX::uiFieldFormLayout {window width} {
    if {![winfo exists $window.viewport]} return
    $window.viewport itemconfigure content -width $width
    set wrap [expr {max(100,$width-26)}]
    foreach child [winfo children $window.viewport.content] {
        if {[string match $window.viewport.content.label* $child]} {$child configure -wraplength $wrap}
        if {[winfo exists $child.error]} {$child.error configure -wraplength $wrap}
    }
    $window.status configure -wraplength $wrap
}
proc ::GX::uiFieldFormSectionEnabled {window section enabled} {
    variable ::GX::UiField::forms
    set enabled [uiFieldNormalize {type boolean} $enabled]
    set notebook $window.viewport.content.sections;set tab $notebook.$section
    if {![dict exists $forms $window]||![winfo exists $notebook]||$tab ni [$notebook tabs]} {error {Unknown form section}}
    $notebook tab $tab -state [expr {$enabled?"normal":"disabled"}]
    return $enabled
}
proc ::GX::uiFieldFormSee {window widget} {
    if {![winfo exists $window.viewport]} return
    set notebook $window.viewport.content.sections
    if {[winfo exists $notebook]} {foreach tab [$notebook tabs] {if {[string match ${tab}.* $widget]} {$notebook select $tab;break}}}
    uiFieldScrollSee $window.viewport $window.viewport.content $widget
}
proc ::GX::uiFieldScrollSee {viewport content widget} {
    if {![winfo exists $viewport]||![winfo exists $widget]} return
    set total [winfo reqheight $content]
    # Root-coordinate differences also cover nested controls and widgets
    # packed into a different geometry parent, without depending on ancestry.
    set y [expr {[winfo rooty $widget]-[winfo rooty $content]}];set h [winfo height $widget]
    set top [$viewport canvasy 0];set bottom [$viewport canvasy [winfo height $viewport]]
    if {$y<$top} {$viewport yview moveto [expr {$y/double(max(1,$total))}]}
    if {$y+$h>$bottom} {$viewport yview moveto [expr {max(0,($y+$h-[winfo height $viewport])/double(max(1,$total)))}]}
}
proc ::GX::uiFieldFormApply {window} {
    variable ::GX::UiField::forms
    variable ::GX::UiField::formValues
    variable ::GX::UiField::formStatus
    set form [dict get $forms $window];set values {}
    if {[catch {
        dict for {key descriptor} [dict get $form fields] {
            set widget [dict get $form widgets $key]
            if {![uiFieldCommit $widget]} {focus $widget.entry;error "$key: $::GX::UiField::errors($widget)"}
            dict set values $key [uiFieldNormalize $descriptor $formValues($window,$key)]
        }
        uplevel #0 [list {*}[dict get $form apply] $values]
    } message]} {if {[dict exists $forms $window]&&[winfo exists $window]} {set formStatus($window) $message};return 0}
    if {[dict exists $forms $window]&&[winfo exists $window]} {set formStatus($window) "Applied."}
    return 1
}
proc ::GX::uiFieldFormDestroy {window actual} {
    if {$window ne $actual} return
    variable ::GX::UiField::forms
    dict unset forms $window
    array unset ::GX::UiField::formValues "$window,*"
    unset -nocomplain ::GX::UiField::formStatus($window)
}

# Existing standard-module widget dispatch remains authoritative for special
# fields (Dataset, Selection, repeatable rows, units and scientific definitions).
rename ::GX::standardConfigWidget ::GX::standardConfigWidget_before_ui_field
proc ::GX::standardConfigWidget {parent id key row} {
    variable moduleCfg
    set type [string tolower [moduleConfigField $id $key type string]]
    if {$type ni {color double number}} {tailcall ::GX::standardConfigWidget_before_ui_field $parent $id $key $row}
    set descriptor [dict create type $type label [moduleConfigField $id $key label $key] default [moduleConfigField $id $key default ""]]
    foreach option {required min max alpha allow_inherit} {
        set value [moduleConfigField $id $key $option ""]
        if {$value ne ""} {dict set descriptor $option $value}
    }
    ttk::label $parent.l$row -text [dict get $descriptor label]
    uiFieldCreate $parent.w$row $descriptor ::GX::moduleCfg($id,$key)
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 3
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 3
}

# Validate pending typed input before constructing a standard-module runtime.
rename ::GX::writeStandardRuntimeConfig ::GX::writeStandardRuntimeConfig_before_ui_field
proc ::GX::writeStandardRuntimeConfig {id} {
    variable ::GX::UiField::widgets
    dict for {widget state} $widgets {
        # Match the complete module prefix; keys never contain comma/parenthesis.
        if {[string first "::GX::moduleCfg($id," [dict get $state variable]] != 0} continue
        if {![uiFieldCommit $widget]} {error "$id: $::GX::UiField::errors($widget)"}
    }
    tailcall ::GX::writeStandardRuntimeConfig_before_ui_field $id
}

# Adaptive shared control rows; keep labels beside their inputs.
# UI-only placement: reserve room for native decorations/taskbars on forwarded
# displays, which do not expose the remote OS working-area API to Tk.
proc ::GX::uiFieldWindowFit {window {width {}} {height {}}} {
    if {![winfo exists $window]||[wm overrideredirect $window]||[winfo class $window] eq "ComboboxPopdown"} return
    set availableWidth [expr {max(240,[winfo screenwidth $window]-40)}]
    set availableHeight [expr {max(180,[winfo screenheight $window]-100)}]
    if {$width eq {}} {
        set width [winfo width $window];set height [winfo height $window]
        set x [winfo x $window];set y [winfo y $window]
    } else {set x 20;set y 20}
    # USPosition prevents forwarded multiwindow servers from auto-placing a
    # correctly sized client below the remote working area.
    set positionChanged [expr {[wm positionfrom $window] ne "user"}]
    wm positionfrom $window user
    lassign [wm minsize $window] minWidth minHeight
    wm minsize $window [expr {min($minWidth,$availableWidth)}] [expr {min($minHeight,$availableHeight)}]
    set width [expr {min($width,$availableWidth)}];set height [expr {min($height,$availableHeight)}]
    set x [expr {max(20,min($x,$availableWidth-$width+20))}]
    set y [expr {max(20,min($y,$availableHeight-$height+20))}]
    if {$width>1&&$height>1} {
        set geometry ${width}x${height}+${x}+${y}
        if {$positionChanged||[wm geometry $window] ne $geometry} {wm geometry $window $geometry}
    }
}
proc ::GX::uiFieldWindowMapped {widget} {
    if {[winfo exists $widget]&&[winfo toplevel $widget] eq $widget} {
        after idle [list ::GX::uiFieldWindowFit $widget]
    }
}
# Appearance is host presentation only. Persistent choices belong solely to
# CONFIGURATION_API_v1. Apply once before any theme-dependent widget construction:
# Tk theme switches discard custom styles, and live font changes invalidate native
# embed layout. System/default leaves all interpreter font/theme defaults intact.
proc ::GX::uiAppearanceInitialize {} {
    if {[info exists ::GX::ui(appearanceInitialized)]} return
    set ::GX::ui(appearanceInitialized) 1
    set ::GX::ui(appearanceWarning) {}
    set baselineTheme [ttk::style theme use]
    set theme [configurationGet ui.theme]
    if {$theme ne "system"} {
        if {$theme ni [ttk::style theme names] || [catch {ttk::style theme use $theme} reason]} {
            ttk::style theme use $baselineTheme
            set ::GX::ui(appearanceWarning) "Saved theme '$theme' is unavailable; using $baselineTheme. Choose an installed theme and Save."
        }
    }
    set family [configurationGet ui.font_family]
    set size [configurationGet ui.font_size]
    if {$family ne "system" && $family ni [font families]} {
        append ::GX::ui(appearanceWarning) " Saved font '$family' is unavailable; using interpreter fonts."
        set family system
    }
    set baselineSize [font actual TkDefaultFont -size]
    if {$baselineSize < 0} {set baselineSize [expr {abs($baselineSize)/[tk scaling]}]}
    set delta [expr {$size eq "system" ? 0 : $size-$baselineSize}]
    foreach name {TkDefaultFont TkTextFont TkMenuFont TkHeadingFont TkCaptionFont TkSmallCaptionFont TkIconFont TkTooltipFont TkFixedFont} {
        if {$name ni [font names]} continue
        if {$family ne "system" && $name ne "TkFixedFont"} {font configure $name -family $family}
        if {$size ne "system"} {
            set base [font actual $name -size]
            # Pixel-sized named fonts retain their unit rather than treating pixels
            # as points. The default size ratio preserves their relative sizing.
            set adjusted [expr {$base < 0 ? -max(8,int(abs($base)*double($size)/$baselineSize)) : int(max(8,$base+$delta))}]
            font configure $name -size $adjusted
        }
    }
}
proc ::GX::uiAppearanceEffective {} {
    return "ttk: [ttk::style theme use] | Tk [package present Tk] | GUI: [font actual TkDefaultFont -family] [font actual TkDefaultFont -size] | Heading: [font actual TkHeadingFont -family] [font actual TkHeadingFont -size] | Mono: [font actual TkFixedFont -family] [font actual TkFixedFont -size] | Tk scaling: [format %.3f [tk scaling]]"
}
# VcXsrv mirrors redirected pixmaps through root-shadow damage. Retain dev089's
# one complete-region notification after map paint, with configurable timing.
# The server gate remains mandatory; this never redraws other windows/pixels.
proc ::GX::uiFieldComboboxStatus {} {
    if {![configurationGet ui.x11_popup_repair_enabled]} {return {disabled by user}}
    if {[tk windowingsystem] ne "x11" || ![string match {*HC-Consult*} [winfo server .]]} {return {not applicable on this X server}}
    if {[info exists ::GX::ui(comboboxDamageUnavailable)]} {return "native helper unavailable: $::GX::ui(comboboxDamageUnavailable)"}
    return {active for recognized server}
}
proc ::GX::uiFieldComboboxInstall {} {
    if {![configurationGet ui.x11_popup_repair_enabled]} {
        if {[info exists ::GX::ui(comboboxDamageTimers)]} {
            dict for {popup timer} $::GX::ui(comboboxDamageTimers) {after cancel $timer}
            set ::GX::ui(comboboxDamageTimers) {}
        }
        return
    }
    if {[tk windowingsystem] ne "x11" || ![string match {*HC-Consult*} [winfo server .]]} return
    if {![llength [info commands ::GX::UiX11::popupDamage]]} {
        if {[catch {load [file join $::GX::scriptDir core nativegui libgxtxt_ui_x11.so] Gxtxtuix11} reason]} {
            set ::GX::ui(comboboxDamageUnavailable) $reason
            return
        }
    }
    unset -nocomplain ::GX::ui(comboboxDamageUnavailable)
    if {[info exists ::GX::ui(comboboxDamageInstalled)]} return
    set ::GX::ui(comboboxDamageInstalled) 1
    set ::GX::ui(comboboxDamageTimers) {}
    bind ComboboxPopdown <Map> +[list ::GX::uiFieldComboboxPopupMapped %W]
    bind ComboboxPopdown <Unmap> +[list ::GX::uiFieldComboboxPopupCancel %W]
    bind ComboboxPopdown <Destroy> +[list ::GX::uiFieldComboboxPopupCancel %W]
}
proc ::GX::uiFieldComboboxPopupCancel {popup} {
    if {[info exists ::GX::ui(comboboxDamageTimers)] && [dict exists $::GX::ui(comboboxDamageTimers) $popup]} {
        after cancel [dict get $::GX::ui(comboboxDamageTimers) $popup]
        dict unset ::GX::ui(comboboxDamageTimers) $popup
    }
}
proc ::GX::uiFieldComboboxPopupMapped {popup} {
    uiFieldComboboxPopupCancel $popup
    if {[uiFieldComboboxStatus] ne "active for recognized server"} return
    dict set ::GX::ui(comboboxDamageTimers) $popup [after [configurationGet ui.x11_popup_repair_delay_ms] [list ::GX::uiFieldComboboxPopupDamage $popup]]
}
proc ::GX::uiFieldComboboxPopupDamage {popup} {
    uiFieldComboboxPopupCancel $popup
    # Recheck policy and window lifecycle at execution, including pending timers
    # when the user disables repair or closes/reopens a popup rapidly.
    if {![winfo exists $popup] || ![winfo ismapped $popup] || [uiFieldComboboxStatus] ne "active for recognized server"} return
    if {[catch {::GX::UiX11::popupDamage $popup} reason]} {
        set ::GX::ui(comboboxDamageUnavailable) $reason
        if {[llength [info commands ::GX::configurationAppearanceRefresh]]} {configurationAppearanceRefresh}
    }
}
proc ::GX::uiFieldControlsLayout {frame width {children {}}} {
    if {$children eq {}} {set children [winfo children $frame]}
    foreach child $children {pack forget $child}
    # Keep each label next to its input when wrapping. Treating them as
    # unrelated cells split labels from fields at larger fonts/narrow widths.
    set groups {};set index 0
    while {$index<[llength $children]} {
        set child [lindex $children $index];incr index
        set next [lindex $children $index]
        if {[winfo class $child] in {TLabel Label}&&$next ne ""&&[winfo class $next] in {Entry TEntry Combobox TCombobox Spinbox TSpinbox Scale TScale}} {
            $child configure -wraplength [expr {max(64,$width-[winfo reqwidth $next]-18)}]
            lappend groups [list $child $next];incr index
        } else {
            if {[winfo class $child] in {TLabel Label}} {$child configure -wraplength [expr {max(64,$width-18)}]}
            lappend groups [list $child]
        }
    }
    # Use every available row width before adding another row. A fixed six-
    # group ceiling could push core editing controls below a Workbench pane.
    for {set columns [llength $groups]} {$columns>=1} {incr columns -1} {
        set sizes [lrepeat [expr {2*$columns}] 0];set i 0
        foreach group $groups {
            set col [expr {$i%$columns}]
            set part 0
            foreach child $group {
                set cell [expr {2*$col+$part}];incr part
                lset sizes $cell [expr {max([lindex $sizes $cell],[winfo reqwidth $child]+6)}]
            }
            incr i
        }
        set total 0;foreach size $sizes {incr total $size}
        if {$total<=$width || $columns==1} break
    }
    set heights {};set i 0
    foreach group $groups {
        set row [expr {$i/$columns}];set col [expr {2*($i%$columns)}];incr i
        set span [expr {[llength $group]==1 ? 2 : 1}]
        foreach child $group {
            dict set heights $row [expr {max([datasetPublicationV2DictDefault $heights $row 0],[winfo reqheight $child]+4)}]
            set info [grid info $child]
            if {$info eq {} || [dict get $info -row]!=$row || [dict get $info -column]!=$col||[dict get $info -columnspan]!=$span} {
                grid $child -row $row -column $col -columnspan $span -sticky w -padx 3 -pady 2
            }
            incr col
        }
    }
    set height 0;dict for {row pixels} $heights {incr height $pixels}
    return [dict create columns $columns rows [dict size $heights] height $height]
}
namespace eval ::GX::UiField {variable tableLayoutAfter {}}
proc ::GX::uiFieldInspectionColumnsFit {tree} {
    ttk::style configure GXInspection.Treeview -font TkDefaultFont -rowheight [expr {[font metrics TkDefaultFont -linespace]+8}]
    if {[$tree cget -style] ne "GXInspection.Treeview"} {$tree configure -style GXInspection.Treeview}
    foreach column [$tree cget -columns] {
        set width [expr {[font measure TkHeadingFont [$tree heading $column -text]]+22}]
        foreach id [$tree children {}] {set width [expr {max($width,[font measure TkDefaultFont [$tree set $id $column]]+22)}]}
        set width [expr {min(32767,$width)}]
        if {[$tree column $column -width]!=$width||[$tree column $column -stretch]} {$tree column $column -width $width -stretch 0}
        $tree column $column -minwidth [expr {[font measure TkHeadingFont [$tree heading $column -text]]+22}]
    }
}
proc ::GX::uiFieldInspectionColumnsSchedule {tree} {
    variable ::GX::UiField::tableLayoutAfter
    if {[dict exists $tableLayoutAfter $tree]} {return}
    dict set tableLayoutAfter $tree [after idle [list ::GX::_uiFieldInspectionColumnsApply $tree]]
}
proc ::GX::_uiFieldInspectionColumnsApply {tree} {
    variable ::GX::UiField::tableLayoutAfter
    dict unset tableLayoutAfter $tree
    if {[winfo exists $tree]} {uiFieldInspectionColumnsFit $tree}
}

source [file join [file dirname [info script]] ui_menu_api_v1.tcl]
source [file join [file dirname [info script]] ui_text_editing_v1.tcl]

proc ::GX::uiFieldFormSectionLayout {window} {
    set notebook $window.viewport.content.sections
    if {![winfo exists $notebook]} return
    set tab [$notebook select];if {$tab eq {}} return
    update idletasks
    $notebook configure -height [winfo reqheight $tab]
    lassign [uiMenuWorkarea $window [winfo rootx $window] [winfo rooty $window]] left top areaWidth areaHeight
    set chrome [expr {[font metrics TkDefaultFont -linespace]+54+[winfo reqheight $window.actions]+[winfo reqheight $window.status]}]
    set desired [expr {max(300,min($areaHeight-90,[winfo reqheight $tab]+$chrome))}]
    set width [winfo width $window];if {$width<430} {set width 760}
    wm geometry $window ${width}x$desired
    $window.viewport yview moveto 0
}

source [file join [file dirname [info script]] ui_field_viewer_regions_v1.tcl]

proc ::GX::_uiFieldSelectorViewerChanged {widget viewer changed} {
    set panel [_uiFieldSelectorPanel $widget $viewer]
    if {$changed eq $viewer && [winfo exists $panel]} {event generate $panel <<ViewerResized>>}
}
