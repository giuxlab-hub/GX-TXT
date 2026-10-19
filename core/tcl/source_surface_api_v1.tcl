# SPDX-License-Identifier: GPL-3.0-or-later
# One source view/edit adapter. Tk owns Unicode input and Undo; C++ owns lexing.
namespace eval ::GX::SourceSurface {variable state;variable serial 0;variable pending {};variable configurationSubscription {};variable categories {comment string escape keyword definition builtin number constant bridge decorator tag attribute identifier}}
proc ::GX::sourceSurfaceApiInfo {} {return [dict create api_id SOURCE_SURFACE_API_v1 api_version 1 modes {read_only editable} native_lexer gxtxt.native_source.v1 gui_adapter TkText operations {create set get ready scan configure themes palette fold breakpoints location function_at replace refresh} language_families {javascript c python octave fortran xml html perl tcl tk markdown} source_mutation styling_never]}
proc ::GX::sourceSurfaceConfigurationRegister {} {
    configurationRegister source.theme [dict create group Appearance label {Source color theme} type choice values {Automatic {Readable Light} {Rich Dark} {High Contrast Light} {High Contrast Dark} Custom} default {Readable Light} scope user]
    configurationRegister source.schemes [dict create group Appearance label {Saved source color schemes} type string default {} scope user]
    foreach language {javascript c python octave fortran xml html perl tcl tk markdown} {configurationRegister source.highlight.$language [dict create group Appearance label "[string totitle $language] source highlighting" type boolean default 1 scope user]}
    foreach category {background foreground selection caret gutter breakpoint current_line search comment string escape keyword definition builtin number constant bridge decorator tag attribute identifier} {configurationRegister source.color.$category [dict create group Appearance label "Source $category color (blank = preset)" type string default {} scope user validator ::GX::sourceSurfaceColorValidate]}
    foreach language {python octave} {configurationRegister scripts.editor_layout.$language [dict create group Appearance label "[string totitle $language] editor panel layout" type string default {left 1 right 1 properties 1 fractions {.19 .78} source_fraction .40} scope user]}
    configurationRegister editor.breakpoints [dict create group Appearance label {Source breakpoint presentation by exact revision} type string default {} scope user]
    if {$::GX::SourceSurface::configurationSubscription eq {}} {set ::GX::SourceSurface::configurationSubscription [configurationSubscribe ::GX::_sourceSurfaceConfigurationChanged]}
}
proc ::GX::sourceSurfacePalette {{theme {}}} {
    if {$theme eq {}} {set theme [configurationGet source.theme]}
    if {$theme eq {Automatic}} {set theme {Readable Light};if {[string match -nocase *dark* [configurationGet ui.theme]]} {set theme {Rich Dark}}}
    if {$theme in {{Rich Dark} {High Contrast Dark}}} {
        set p {background #111827 foreground #f3f4f6 selection #374e7a caret #ffffff gutter #cbd5e1 breakpoint #ef4444 current_line #28415c search #6c5014 comment #a7b7cc string #a7e3a1 escape #f9a8d4 keyword #c4b5fd definition #93c5fd builtin #f9c98b number #f7bd82 constant #f0abfc bridge #67e8f9 decorator #f9a8d4 tag #93c5fd attribute #f9c98b identifier #f3f4f6}
    } else {set p {background #ffffff foreground #111827 selection #c7ddff caret #111827 gutter #374151 breakpoint #D32F2F current_line #e0efff search #ffe699 comment #425c42 string #8d2300 escape #85204b keyword #4f249c definition #004b87 builtin #6c3500 number #77328b constant #7d187a bridge #00534e decorator #85204b tag #004b87 attribute #743800 identifier #111827}}
    if {$theme in {{High Contrast Light} {High Contrast Dark}}} {
        dict set p background [expr {$theme eq {High Contrast Dark}?{#000000}:{#ffffff}}]
        dict set p foreground [expr {$theme eq {High Contrast Dark}?{#ffffff}:{#000000}}]
        dict set p identifier [dict get $p foreground]
    }
    foreach category [dict keys $p] {
        set value [configurationGet source.color.$category]
        if {$value ne {}} {if {![regexp {^#[0-9a-fA-F]{6}$} $value]} {error "Invalid custom source color: $category"};dict set p $category $value}
    }
    return $p
}
proc ::GX::sourceSurfaceScan {language source} {documentNativeEnsure;return [::GX::NativeDocument::scan $language $source]}
proc ::GX::sourceSurfaceCreate {parent {options {}}} {
    variable ::GX::SourceSurface::state
    set o [dict merge {mode read_only language python change_command {} theme {} notice {}} $options]
    if {[dict get $o mode] ni {read_only editable}} {error {Source mode must be read_only or editable}}
    ttk::frame $parent
    text $parent.text -undo [expr {[dict get $o mode] eq {editable}}] -autoseparators 1 -maxundo 1000 -wrap none -font TkFixedFont -tabs {32} -padx 6 -pady 4 -exportselection 0
    canvas $parent.lines -width 64 -highlightthickness 0 -takefocus 0
    ttk::scrollbar $parent.v -command [list $parent.text yview]
    ttk::scrollbar $parent.h -orient horizontal -command [list $parent.text xview]
    $parent.text configure -yscrollcommand [list ::GX::_sourceSurfaceScroll $parent] -xscrollcommand [list $parent.h set]
    grid $parent.lines -row 0 -column 0 -sticky ns;grid $parent.text -row 0 -column 1 -sticky nsew
    grid $parent.v -row 0 -column 2 -sticky ns;grid $parent.h -row 1 -column 1 -sticky ew
    set state($parent,status) {}
    ttk::label $parent.status -textvariable ::GX::SourceSurface::state($parent,status) -wraplength 640
    grid $parent.status -row 2 -column 0 -columnspan 3 -sticky ew
    grid rowconfigure $parent 0 -weight 1;grid columnconfigure $parent 1 -weight 1
    set state($parent,options) $o;set state($parent,revision) 0;set state($parent,timer) {};set state($parent,request) {};set state($parent,model) {tokens {} folds {}};set state($parent,modelReady) 0;set state($parent,modelSource) {};set state($parent,folded) {};set state($parent,breakpoints) {};set state($parent,disabled) {};set state($parent,hoverTimer) {};set state($parent,line) 0
    bind $parent.text <<Modified>> [list ::GX::_sourceSurfaceModified $parent]
    bind $parent.text <Configure> [list ::GX::_sourceSurfaceGutter $parent]
    bind $parent.lines <Motion> [list ::GX::_sourceSurfaceHoverSchedule $parent %x %y]
    bind $parent.lines <Leave> [list ::GX::_sourceSurfaceHoverCancel $parent]
    bind $parent.lines <Button-3> [list ::GX::_sourceSurfaceContext $parent %X %Y %y]
    bind $parent.text <F9> [list ::GX::_sourceSurfaceBreakpointKey $parent toggle]
    bind $parent.text <Control-Shift-F9> [list ::GX::_sourceSurfaceBreakpointKey $parent clear]
    bind $parent.lines <Button-1> [list ::GX::_sourceSurfaceGutterClick $parent %x %y]
    bind $parent <Destroy> [list ::GX::_sourceSurfaceDestroy $parent %W]
    sourceSurfaceConfigure $parent $o
    if {[dict get $o mode] eq {read_only}} {$parent.text configure -state disabled}
    return $parent.text
}
proc ::GX::_sourceSurfaceDestroy {p actual} {
    if {$p ne $actual} return
    variable ::GX::SourceSurface::state
    _sourceSurfaceHoverCancel $p
    if {[info exists state($p,timer)] && $state($p,timer) ne {}} {after cancel $state($p,timer)}
    if {[info exists state($p,request)] && $state($p,request) ne {}} {catch {scriptJobRequestCancel $state($p,request)}}
    array unset state $p,*
}
proc ::GX::sourceSurfaceParent {widget} {if {[string match *.text $widget]} {return [winfo parent $widget]};return $widget}
proc ::GX::sourceSurfaceGet {widget} {set p [sourceSurfaceParent $widget];return [$p.text get 1.0 end-1c]}
proc ::GX::sourceSurfaceReady {widget} {
    set p [sourceSurfaceParent $widget]
    return [expr {$::GX::SourceSurface::state($p,modelReady) && $::GX::SourceSurface::state($p,modelSource) eq [sourceSurfaceGet $p]}]
}
proc ::GX::_sourceSurfaceInvalidateModel {p} {
    variable ::GX::SourceSurface::state
    set state($p,modelReady) 0;set state($p,modelSource) {}
    set state($p,model) {tokens {} folds {} line_count 0 truncated 0 executable_lines {}}
}
proc ::GX::sourceSurfaceSet {widget source} {
    set p [sourceSurfaceParent $widget];set t $p.text
    incr ::GX::SourceSurface::state($p,revision)
    _sourceSurfaceInvalidateModel $p
    sourceSurfaceResetPresentation $p
    set old [$t cget -state];$t configure -state normal;$t delete 1.0 end;$t insert 1.0 $source;$t edit reset;$t edit modified 0;$t configure -state $old
    sourceSurfaceRefresh $p
}
proc ::GX::sourceSurfaceConfigure {widget options} {
    variable ::GX::SourceSurface::state
    if {[dict exists $options mode]&&[dict get $options mode] ni {read_only editable}} {error {Source mode must be read_only or editable}}
    set p [sourceSurfaceParent $widget];set state($p,options) [dict merge $state($p,options) $options]
    if {[dict exists $options mode]} {$p.text configure -state [expr {[dict get $options mode] eq {editable}?{normal}:{disabled}}] -undo [expr {[dict get $options mode] eq {editable}}]}
    set palette [sourceSurfacePalette [dict get $state($p,options) theme]]
    $p.text configure -background [dict get $palette background] -foreground [dict get $palette foreground] -insertbackground [dict get $palette caret] -selectbackground [dict get $palette selection] -selectforeground [dict get $palette foreground]
    $p.lines configure -background [dict get $palette background]
    foreach category $::GX::SourceSurface::categories {$p.text tag configure source_$category -foreground [dict get $palette $category]}
    $p.text tag configure source_current -background [dict get $palette current_line]
    $p.text tag configure search_hit -background [dict get $palette search]
    _sourceSurfaceGutter $p
    sourceSurfaceRefresh $p
}
proc ::GX::sourceSurfaceRefreshAll {} {
    foreach key [array names ::GX::SourceSurface::state *,options] {set p [string range $key 0 end-8];if {[winfo exists $p]} {sourceSurfaceConfigure $p {}}}
}
proc ::GX::sourceSurfaceFunctionAt {widget line} {
    variable ::GX::SourceSurface::state
    set p [sourceSurfaceParent $widget];set found 0;set name {<script>}
    # Display labels come from the structural owner's validated fold ranges.
    # Runtime stepping and selected frames remain native interpreter facts.
    foreach fold [dict get $state($p,model) folds] {
        lassign $fold first last
        if {$first>$line || $last<$line || $first<$found} continue
        set header [$p.text get $first.0 $first.end]
        if {[regexp {^[[:space:]]*(?:async[[:space:]]+)?def[[:space:]]+([[:alnum:]_]+)} $header -> symbol] ||
            [regexp {^[[:space:]]*function[[:space:]]+(?:(?:\[[^]]*\]|[[:alnum:]_]+)[[:space:]]*=[[:space:]]*)?([[:alnum:]_]+)} $header -> symbol]} {
            set found $first;set name $symbol
        }
    }
    return $name
}
proc ::GX::_sourceSurfaceModified {p} {
    if {![winfo exists $p.text] || ![$p.text edit modified]} return
    variable ::GX::SourceSurface::state
    $p.text edit modified 0
    incr state($p,revision)
    _sourceSurfaceInvalidateModel $p
    set state($p,line) 0;$p.text tag remove source_current 1.0 end
    if {$state($p,breakpoints) ne {} || $state($p,disabled) ne {}} {set state($p,breakpoints) {};set state($p,disabled) {};set state($p,status) {Source edited; breakpoint positions were cleared. Set them again before Debug.};event generate $p.text <<SourceBreakpointsInvalidated>>}
    foreach tag [$p.text tag names] {if {[string match source_fold_* $tag]} {$p.text tag delete $tag}}
    set state($p,folded) {}
    set callback [dict get $state($p,options) change_command]
    if {$callback ne {}} {uplevel #0 $callback}
    sourceSurfaceRefresh $p
}
proc ::GX::sourceSurfaceRefresh {widget} {
    variable ::GX::SourceSurface::state
    set p [sourceSurfaceParent $widget]
    if {$state($p,timer) ne {}} {after cancel $state($p,timer)}
    set state($p,timer) [after 140 [list ::GX::_sourceSurfacePrepare $p]]
}
proc ::GX::_sourceSurfacePrepare {p} {
    if {![winfo exists $p]} return
    variable ::GX::SourceSurface::state
    set state($p,timer) {}
    if {$state($p,request) ne {}} {catch {scriptJobRequestCancel $state($p,request)};set state($p,request) {}}
    set source [sourceSurfaceGet $p];set revision [incr state($p,revision)]
    set state($p,pendingSource) $source
    set request [dict create source $source language [dict get $state($p,options) language]]
    set command [list [auto_execok tclsh] [file join $::GX::scriptDir core tcl source_surface_request.tcl] $::GX::scriptDir]
    set state($p,request) [scriptJobAsync $command $request [list ::GX::_sourceSurfacePrepared $p $revision] {timeout_ms 30000 max_bytes 67108864 ui_lifetime 1 label {Native source model}}]
}
proc ::GX::_sourceSurfacePrepared {p revision response} {
    variable ::GX::SourceSurface::state
    if {![winfo exists $p] || $state($p,revision)!=$revision} return
    set state($p,request) {}
    if {![dict get $response ok]} {set state($p,error) [dict get $response error];set state($p,status) $state($p,error);return}
    if {![info exists state($p,pendingSource)] || $state($p,pendingSource) ne [sourceSurfaceGet $p]} return
    set state($p,model) [dict get $response result]
    set state($p,modelSource) $state($p,pendingSource);set state($p,modelReady) 1
    set state($p,status) [expr {[dict get $state($p,model) truncated] ? {Highlighting reached its bounded token limit; source remains unchanged.} : [dict get $state($p,options) notice]}]
    if {[info exists state($p,breakpointWait)]} {unset state($p,breakpointWait);set state($p,status) {Source structure is ready. Set the breakpoint on the intended executable line.}}
    foreach category $::GX::SourceSurface::categories {$p.text tag remove source_$category 1.0 end}
    set language [dict get $state($p,options) language]
    if {$language in {matlab matlab-octave}} {set language octave}
    if {$language eq {cpp}} {set language c}
    if {[catch {configurationGet source.highlight.$language} enabled]} {set enabled 1}
    if {$enabled} {after idle [list ::GX::_sourceSurfaceTags $p $revision 0]}
    _sourceSurfaceGutter $p
}
proc ::GX::_sourceSurfaceTags {p revision offset} {
    variable ::GX::SourceSurface::state
    if {![winfo exists $p] || $state($p,revision)!=$revision} return
    set tokens [dict get $state($p,model) tokens]
    foreach token [lrange $tokens $offset [expr {$offset+249}]] {
        if {[dict exists $token end_line]} {set first "[dict get $token line].[dict get $token column]";set last "[dict get $token end_line].[dict get $token end_column]"} else {set first "1.0 + [dict get $token start] chars";set last "1.0 + [dict get $token end] chars"}
        $p.text tag add source_[dict get $token category] $first $last
    }
    incr offset 250
    if {$offset<[llength $tokens]} {after 1 [list ::GX::_sourceSurfaceTags $p $revision $offset]}
    $p.text tag raise sel
}
proc ::GX::_sourceSurfaceScroll {p first last} {if {![winfo exists $p]} return;$p.v set $first $last;_sourceSurfaceGutter $p}
proc ::GX::_sourceSurfaceGutter {p} {
    variable ::GX::SourceSurface::state
    if {![winfo exists $p.lines] || ![info exists state($p,options)]} return
    set c $p.lines;set t $p.text;$c delete all
    set font [$t cget -font];set height [font metrics $font -linespace]
    set lane [expr {max(14,int(ceil($height*.9)))}]
    set count [lindex [split [$t index end-1c] .] 0]
    set width [expr {3*$lane+[font measure $font $count]+8}]
    set state($p,lane) $lane
    if {[$c cget -width]!=$width} {$c configure -width $width}
    set palette [sourceSurfacePalette [dict get $state($p,options) theme]]
    set folds {};foreach fold [dict get $state($p,model) folds] {dict set folds [lindex $fold 0] 1}
    set index [$t index @0,0]
    for {set visible 0} {$visible<1000} {incr visible} {
        set n [lindex [split $index .] 0]
        set info [$t dlineinfo $n.0]
        if {$info eq {}} break
        if {[lindex $info 3]>0} {
            # dlineinfo height is clipped at the viewport edge; its baseline
            # remains the physical font baseline. Never squeeze a partial row.
            set y [expr {[lindex $info 1]+[lindex $info 4]-[font metrics $font -ascent]+$height/2.0}]
            $c create text [expr {$width-4}] $y -text $n -anchor e -font $font -fill [dict get $palette gutter] -tags [list line_number physical_$n]
            set r [expr {max(3,min($lane/2.0-3,$height*.28))}];set x [expr {$lane/2.0}]
            if {$n in $state($p,breakpoints)} {$c create oval [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] [expr {$y+$r}] -fill [dict get $palette breakpoint] -outline [dict get $palette breakpoint] -tags breakpoint}
            if {$n in $state($p,disabled)} {$c create oval [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] [expr {$y+$r}] -outline [dict get $palette breakpoint] -width 1.5 -tags disabled_breakpoint}
            if {$n==$state($p,line)} {
                set x [expr {$lane*1.5}];set r [expr {$lane*.34}]
                $c create polygon [expr {$x-$r}] [expr {$y-$r*.4}] $x [expr {$y-$r*.4}] $x [expr {$y-$r}] [expr {$x+$r}] $y $x [expr {$y+$r}] $x [expr {$y+$r*.4}] [expr {$x-$r}] [expr {$y+$r*.4}] -fill #F5C542 -outline #805b00 -tags execution_pointer
            }
            if {[dict exists $folds $n]} {
                set x [expr {$lane*2.5}];set r [expr {max(2,$lane*.18)}]
                if {$n in $state($p,folded)} {set points [list [expr {$x-$r}] [expr {$y-$r}] [expr {$x+$r}] $y [expr {$x-$r}] [expr {$y+$r}]]} else {set points [list [expr {$x-$r}] [expr {$y-$r}] $x [expr {$y+$r}] [expr {$x+$r}] [expr {$y-$r}]]}
                $c create line {*}$points -fill [dict get $palette gutter] -width 1.5 -capstyle round -joinstyle round -tags fold_chevron
            }
        }
        # Display-line iteration skips elided physical lines completely; their
        # zero-height dlineinfo must never paint duplicate line numbers.
        set next [$t index "$index + 1 display lines"]
        if {[$t compare $next <= $index] || [$t compare $next >= end]} break
        set index $next
    }
}
proc ::GX::_sourceSurfaceGutterClick {p x y} {
    variable ::GX::SourceSurface::state
    _sourceSurfaceHoverCancel $p
    set line [lindex [split [$p.text index @0,$y] .] 0];set lane $state($p,lane)
    if {$x<$lane} {
        if {[catch {sourceSurfaceBreakpoints $p toggle $line} reason]} {set state($p,status) $reason}
    } elseif {$x<2*$lane} {
        if {$state($p,line)>0} {$p.text see $state($p,line).0;focus $p.text}
    } elseif {$x<3*$lane} {
        foreach fold [dict get $state($p,model) folds] {if {[lindex $fold 0]==$line} {sourceSurfaceFold $p toggle $line;break}}
    } else {$p.text mark set insert $line.0;focus $p.text}
}
proc ::GX::_sourceSurfaceBreakpointKey {p operation} {
    if {[catch {sourceSurfaceBreakpoints $p $operation [lindex [split [$p.text index insert] .] 0]} reason]} {set ::GX::SourceSurface::state($p,status) $reason}
    return -code break
}
proc ::GX::_sourceSurfaceHoverCancel {p} {
    variable ::GX::SourceSurface::state
    if {[info exists state($p,hoverTimer)] && $state($p,hoverTimer) ne {}} {catch {after cancel $state($p,hoverTimer)};set state($p,hoverTimer) {}}
    catch {destroy .gxViewportTip}
}
proc ::GX::_sourceSurfaceHoverSchedule {p x y} {
    _sourceSurfaceHoverCancel $p
    set ::GX::SourceSurface::state($p,hoverTimer) [after 500 [list ::GX::_sourceSurfaceHover $p $x $y]]
}
proc ::GX::_sourceSurfaceHover {p x y} {
    if {![winfo exists $p]} return
    set lane $::GX::SourceSurface::state($p,lane);set line [lindex [split [$p.text index @0,$y] .] 0]
    set label "Line $line"
    if {$x<$lane} {
        set marker {no breakpoint}
        if {$line in $::GX::SourceSurface::state($p,breakpoints)} {set marker {enabled breakpoint}}
        if {$line in $::GX::SourceSurface::state($p,disabled)} {set marker {disabled breakpoint}}
        append label " — $marker; toggle with F9"
    } elseif {$x<2*$lane} {append label { — execution pointer}} elseif {$x<3*$lane} {append label { — fold / unfold}} else {append label { — source line}}
    native2DViewportTooltipShow $p.lines $label
    wm geometry .gxViewportTip +[expr {[winfo pointerx $p]+12}]+[expr {[winfo pointery $p]+20}]
}
proc ::GX::_sourceSurfaceContext {p x y localY} {
    set m $p.gutterMenu;catch {destroy $m};menu $m -tearoff 0
    set line [lindex [split [$p.text index @0,$localY] .] 0]
    foreach {op label} {toggle {Toggle breakpoint} enable {Enable breakpoint} disable {Disable breakpoint} remove {Remove breakpoint} clear {Clear all breakpoints}} {$m add command -label "$label — line $line" -command [list ::GX::_sourceSurfaceContextAction $p $op $line]}
    $m add separator;$m add command -label {Fold / unfold current block} -command [list ::GX::sourceSurfaceFold $p toggle $line]
    uiMenuPopup $m $x $y
}
proc ::GX::_sourceSurfaceContextAction {p op line} {if {[catch {sourceSurfaceBreakpoints $p $op $line} message]} {set ::GX::SourceSurface::state($p,status) $message}}
proc ::GX::_sourceSurfaceBreakpointSave {p} {
    variable ::GX::SourceSurface::state
    if {![info exists state($p,document_identity)] || [lindex $state($p,document_identity) 0] eq {}} return
    set key $state($p,document_identity)
    if {[string match session:* [lindex $key 0]] && $::GX::currentSession ne {}} {lappend key [sessionInspectionCurrentSession]}
    set saved [configurationGet editor.breakpoints]
    if {[catch {dict size $saved}]} {set saved {}}
    dict set saved $key [dict create enabled $state($p,breakpoints) disabled $state($p,disabled)]
    while {[dict size $saved]>128} {dict unset saved [lindex [dict keys $saved] 0]}
    configurationSet editor.breakpoints $saved;configurationSave {editor.breakpoints}
}
proc ::GX::sourceSurfaceBreakpoints {widget {operation get} {line 0}} {
    variable ::GX::SourceSurface::state;set p [sourceSurfaceParent $widget]
    if {$operation in {lock unlock}} {set state($p,breakpoints_locked) [expr {$operation eq {lock}}];return}
    if {$operation eq {describe}} {
        set result {}
        foreach n [lsort -integer -unique [concat $state($p,breakpoints) $state($p,disabled)]] {lappend result [dict create line $n enabled [expr {$n in $state($p,breakpoints)}]]}
        return $result
    }
    if {$operation ne {get}} {
        if {[info exists state($p,breakpoints_locked)] && $state($p,breakpoints_locked)} {error {Stop Debug before changing breakpoints; the active native Job uses its immutable admitted snapshot}}
        if {[dict get $state($p,options) mode] ne {editable}} {error {Read-only source cannot have editable breakpoints}}
        if {$operation ni {toggle enable disable remove clear}} {error {Unknown breakpoint operation}}
        if {$operation in {toggle enable}} {
            if {![sourceSurfaceReady $p]} {set state($p,breakpointWait) 1;error {Source structure is updating; try the breakpoint again when it is ready.}}
            set text [string trim [$p.text get $line.0 "$line.0 lineend"]]
            if {$line<1 || $text eq {} || [regexp {^(#|%|//)} $text]} {error "Line $line is not an executable statement; no breakpoint set"}
            set language [dict get $state($p,options) language]
            if {$language eq {python} && (![dict exists $state($p,model) executable_lines] || $line ni [dict get $state($p,model) executable_lines])} {error "Line $line has no executable Python instruction in the current validated source; no breakpoint set"}
            if {$language eq {octave} && [regexp {^(end[a-z]*|else|otherwise|function)(\s|;|$)} $text]} {error "Line $line is an Octave declaration/block delimiter; choose an executable statement inside the block"}
        }
        if {$operation eq {clear}} {set state($p,breakpoints) {};set state($p,disabled) {}} else {
            set enabled [expr {$line in $state($p,breakpoints)}]
            foreach key {breakpoints disabled} {set i [lsearch -exact $state($p,$key) $line];if {$i>=0} {set state($p,$key) [lreplace $state($p,$key) $i $i]}}
            if {$operation eq {enable} || ($operation eq {toggle} && !$enabled)} {lappend state($p,breakpoints) $line}
            if {$operation eq {disable}} {lappend state($p,disabled) $line}
        }
        set state($p,breakpoints) [lsort -integer -unique $state($p,breakpoints)]
        _sourceSurfaceBreakpointSave $p;_sourceSurfaceGutter $p
        event generate $p.text <<SourceBreakpointsChanged>>
    }
    return $state($p,breakpoints)
}
proc ::GX::sourceSurfaceLocation {widget line} {
    variable ::GX::SourceSurface::state;set p [sourceSurfaceParent $widget];set state($p,line) $line
    $p.text tag remove source_current 1.0 end
    if {$line>0} {
        foreach fold [dict get $state($p,model) folds] {
            lassign $fold first last
            if {$line>$first && $line<=$last && $first in $state($p,folded)} {
                $p.text tag delete source_fold_$first
                set at [lsearch -exact $state($p,folded) $first]
                set state($p,folded) [lreplace $state($p,folded) $at $at]
            }
        }
        $p.text tag add source_current $line.0 "$line.0 lineend";$p.text see $line.0
    }
    _sourceSurfaceGutter $p
}
proc ::GX::sourceSurfaceFold {widget operation {line 0}} {
    variable ::GX::SourceSurface::state;set p [sourceSurfaceParent $widget]
    if {$operation eq {unfold_all}} {foreach tag [$p.text tag names] {if {[string match source_fold_* $tag]} {$p.text tag delete $tag}};set state($p,folded) {};_sourceSurfaceGutter $p;return}
    if {$line==0} {set line [lindex [split [$p.text index insert] .] 0]}
    if {$operation ne {fold_all}} {set target -1;foreach fold [dict get $state($p,model) folds] {lassign $fold first last;if {$first<=$line && $last>=$line && $first>$target} {set target $first}};if {$target>=0} {set line $target}}
    foreach fold [dict get $state($p,model) folds] {
        lassign $fold first last
        if {$operation ne {fold_all} && $first!=$line} continue
        set tag source_fold_$first
        if {$operation eq {toggle} && $first in $state($p,folded)} {$p.text tag delete $tag;set i [lsearch -exact $state($p,folded) $first];set state($p,folded) [lreplace $state($p,folded) $i $i]
        } else {$p.text tag configure $tag -elide 1;$p.text tag add $tag [expr {$first+1}].0 [expr {$last+1}].0;if {$first ni $state($p,folded)} {lappend state($p,folded) $first}}
    }
    _sourceSurfaceGutter $p
}
proc ::GX::sourceSurfaceReplace {widget source} {
    set p [sourceSurfaceParent $widget]
    if {[dict get $::GX::SourceSurface::state($p,options) mode] ne {editable}} {error {Read-only source surface cannot be edited}}
    set t $p.text;$t configure -autoseparators 0;$t edit separator
    try {$t delete 1.0 end;$t insert 1.0 $source} finally {$t edit separator;$t configure -autoseparators 1}
    sourceSurfaceRefresh $p
}
proc ::GX::sourceSurfaceDatasetLanguage {id} {
    set m [datasetMetadataRead $::GX::currentSession $id]
    if {[dict exists $m code.language]} {return [dict get $m code.language]}
    return plaintext
}
proc ::GX::sourceSurfaceAppearanceBuild {parent} {
    set p $parent.source
    ttk::labelframe $p -text {Source colors and syntax — independent of the GUI theme} -padding 8
    pack $p -fill x -padx 8 -pady 5
    set row 0
    foreach id {source.theme source.highlight.python source.highlight.octave source.highlight.javascript source.highlight.c source.highlight.fortran source.highlight.xml source.highlight.html source.highlight.perl source.highlight.tcl source.highlight.tk} {
        set field [dict get [configurationFields] $id]
        set ::GX::configurationUi($id) [configurationGet $id]
        set name [string map {. _} $id]
        ttk::label $p.l_$name -text [dict get $field label]
        uiFieldCreate $p.v_$name $field ::GX::configurationUi($id)
        grid $p.l_$name -row $row -column 0 -sticky w;grid $p.v_$name -row $row -column 1 -sticky ew;incr row
    }
    set ::GX::configurationUi(sourceToken) comment
    ttk::combobox $p.token -values {background foreground selection caret gutter breakpoint current_line search comment string escape keyword definition builtin number constant bridge decorator tag attribute identifier} -textvariable ::GX::configurationUi(sourceToken) -state readonly
    ttk::button $p.color -text {Choose token color…} -command ::GX::sourceSurfaceAppearanceChoose
    ttk::button $p.resetToken -text {Reset token} -command {set ::GX::configurationUi(source.color.$::GX::configurationUi(sourceToken)) {};::GX::sourceSurfaceAppearancePreview}
    grid $p.token -row $row -column 0;grid $p.color -row $row -column 1;grid $p.resetToken -row $row -column 2;incr row
    foreach id [dict keys [configurationFields]] {if {[string match source.color.* $id]} {set ::GX::configurationUi($id) [configurationGet $id]}}
    ttk::button $p.preview -text {Preview source colors} -command ::GX::sourceSurfaceAppearancePreview
    ttk::button $p.reset -text {Reset source palette} -command {foreach key [array names ::GX::configurationUi source.color.*] {set ::GX::configurationUi($key) {}};set ::GX::configurationUi(source.theme) {Readable Light};::GX::sourceSurfaceAppearancePreview}
    grid $p.preview -row $row -column 0;grid $p.reset -row $row -column 1;incr row
    set ::GX::configurationUi(sourceScheme) {}
    ttk::combobox $p.scheme -values [dict keys [configurationGet source.schemes]] -textvariable ::GX::configurationUi(sourceScheme)
    ttk::frame $p.schemeActions
    foreach {action label} {save {Save scheme} load {Load scheme} delete {Delete scheme}} {ttk::button $p.schemeActions.$action -text $label -command [list ::GX::sourceSurfaceScheme $action];pack $p.schemeActions.$action -side left -padx 2}
    grid $p.scheme -row $row -column 0 -sticky ew;grid $p.schemeActions -row $row -column 1 -columnspan 2 -sticky w;incr row
    set a [sourceSurfaceCreate $p.python {mode read_only language python}]
    set b [sourceSurfaceCreate $p.octave {mode read_only language octave}]
    $a configure -height 9 -width 44;$b configure -height 9 -width 44
    grid $p.python -row $row -column 0 -sticky nsew;grid $p.octave -row $row -column 1 -columnspan 2 -sticky nsew
    sourceSurfaceSet $a "# Python — live native lexer\nimport math\ndef measure(x):\n    \"\"\"A physical measurement.\"\"\"\n    return math.sin(x) + 2.5\nprint(measure(1.0))\n"
    sourceSurfaceSet $b "% GNU Octave — live native lexer\nfunction y = measure(x)\n  if x > 0\n    y = sin(x) + 2.5;\n  endif\nendfunction\ndisp(measure(1));\n"
    grid columnconfigure $p 0 -weight 1;grid columnconfigure $p 1 -weight 1
    set ::GX::configurationUi(sourcePreviewStatus) {Preview changes are temporary. Save user defaults applies source colors to every open surface.}
    ttk::label $p.status -textvariable ::GX::configurationUi(sourcePreviewStatus) -wraplength 800
    grid $p.status -row [expr {$row+1}] -column 0 -columnspan 3 -sticky ew
}
proc ::GX::sourceSurfaceAppearanceChoose {} {
    set key source.color.$::GX::configurationUi(sourceToken)
    set chosen [tk_chooseColor -title {Source token color}]
    if {$chosen ne {}} {set ::GX::configurationUi($key) $chosen;set ::GX::configurationUi(source.theme) Custom;sourceSurfaceAppearancePreview}
}
proc ::GX::sourceSurfaceAppearancePreview {} {
    variable configurationValues
    set prior $configurationValues
    try {
        foreach id [dict keys [configurationFields]] {if {[string match source.* $id] && [info exists ::GX::configurationUi($id)]} {dict set configurationValues $id $::GX::configurationUi($id)}}
        set p .top.nb.configuration.sections.appearance.canvas.content.source
        foreach language {python octave} {sourceSurfaceConfigure $p.$language {}}
        set palette [sourceSurfacePalette]
        set low {}
        foreach category {foreground comment string escape keyword definition builtin number constant bridge decorator tag attribute identifier} {
            if {[sourceSurfaceContrast [dict get $palette $category] [dict get $palette background]]<4.5} {lappend low $category}
        }
        set ::GX::configurationUi(sourcePreviewStatus) [expr {$low eq {} ? {Preview: all text categories meet 4.5:1 contrast. Save to apply to open surfaces.} : "Low contrast warning: $low. Your chosen colors are preserved; review before saving."}]
    } finally {set configurationValues $prior}
}
proc ::GX::sourceSurfaceContrast {foreground background} {
    set values {}
    foreach color [list $foreground $background] {
        set sum 0.0
        foreach index {1 3 5} weight {.2126 .7152 .0722} {
            scan [string range $color $index [expr {$index+1}]] %x byte;set v [expr {$byte/255.0}]
            set v [expr {$v<=.04045 ? $v/12.92 : pow(($v+.055)/1.055,2.4)}];set sum [expr {$sum+$weight*$v}]
        }
        lappend values $sum
    }
    lassign $values a b;return [expr {(max($a,$b)+.05)/(min($a,$b)+.05)}]
}
proc ::GX::_sourceSurfaceConfigurationChanged {id args} {if {([string match source.* $id] || $id eq {ui.theme}) && [llength [info commands winfo]] && [dict exists [configurationFields] source.color.identifier]} {sourceSurfaceRefreshAll}}

proc ::GX::sourceSurfaceScheme {operation} {
    set name [string trim $::GX::configurationUi(sourceScheme)]
    if {$name eq {} || [string length $name]>80 || [regexp {[\r\n]} $name]} {set ::GX::configurationUi(sourcePreviewStatus) {Enter a scheme name of 1–80 characters};return}
    set schemes [configurationGet source.schemes]
    if {[catch {dict size $schemes}]} {set schemes {}}
    switch -- $operation {
        save {
            set values {};dict for {id field} [configurationFields] {if {[string match source.* $id] && $id ne {source.schemes} && [info exists ::GX::configurationUi($id)]} {dict set values $id [configurationValidate $id $::GX::configurationUi($id)]}}
            dict set schemes $name $values
        }
        load {if {![dict exists $schemes $name]} {return};dict for {id value} [dict get $schemes $name] {if {[dict exists [configurationFields] $id] && $id ne {source.schemes}} {set ::GX::configurationUi($id) [configurationValidate $id $value]}};sourceSurfaceAppearancePreview;return}
        delete {if {[dict exists $schemes $name]} {dict unset schemes $name}}
        default {error {Unknown source scheme action}}
    }
    configurationSet source.schemes $schemes;configurationSave {source.schemes}
    set chooser .top.nb.configuration.sections.appearance.source.scheme
    if {[winfo exists $chooser]} {$chooser configure -values [dict keys $schemes]}
    set ::GX::configurationUi(sourcePreviewStatus) "Source scheme $operation completed: $name"
}

proc ::GX::sourceSurfaceFind {widget pattern {direction forward}} {
    if {$pattern eq {}} {return {}}
    set p [sourceSurfaceParent $widget];set t $p.text
    set previous [$t tag ranges search_hit]
    set backwardStart {insert - 1c}
    if {[llength $previous]==2 && [$t compare insert == [lindex $previous 1]] && [string equal -nocase [$t get {*}$previous] $pattern]} {
        set backwardStart "[lindex $previous 0] - 1c"
    }
    $t tag remove search_hit 1.0 end
    if {$direction eq {backward}} {set found [$t search -backwards -nocase -- $pattern $backwardStart 1.0];if {$found eq {}} {set found [$t search -backwards -nocase -- $pattern end 1.0]}
    } else {set found [$t search -nocase -- $pattern {insert + 1c} end];if {$found eq {}} {set found [$t search -nocase -- $pattern 1.0 end]}}
    if {$found eq {}} {return {}}
    set stop "$found + [string length $pattern] chars"
    $t tag configure search_hit -background [dict get [sourceSurfacePalette [dict get $::GX::SourceSurface::state($p,options) theme]] search]
    $t tag add search_hit $found $stop;$t mark set insert $stop;$t see $found;focus $t
    return $found
}

proc ::GX::sourceSurfaceResetPresentation {widget} {
    variable ::GX::SourceSurface::state;set p [sourceSurfaceParent $widget]
    foreach tag [$p.text tag names] {if {[string match source_fold_* $tag]} {$p.text tag delete $tag}}
    set state($p,folded) {};set state($p,breakpoints) {};set state($p,disabled) {};set state($p,line) 0
    $p.text tag remove source_current 1.0 end
}
proc ::GX::sourceSurfaceDocumentIdentity {widget identity} {
    variable ::GX::SourceSurface::state;set p [sourceSurfaceParent $widget]
    if {![info exists state($p,document_identity)] || $state($p,document_identity) ne $identity} {
        sourceSurfaceResetPresentation $p;set state($p,document_identity) $identity
        set key $identity
        if {[string match session:* [lindex $identity 0]] && $::GX::currentSession ne {}} {lappend key [sessionInspectionCurrentSession]}
        set saved [configurationGet editor.breakpoints]
        if {![catch {dict get $saved $key} points]} {
            foreach {field option} {breakpoints enabled disabled disabled} {if {[dict exists $points $option]} {set state($p,$field) [dict get $points $option]}}
        }
        _sourceSurfaceGutter $p
    }
}

proc ::GX::sourceSurfaceColorValidate {value} {if {$value ne {} && ![regexp {^#[0-9A-Fa-f]{6}$} $value]} {error {Source color must be blank (preset) or #RRGGBB}};return $value}
