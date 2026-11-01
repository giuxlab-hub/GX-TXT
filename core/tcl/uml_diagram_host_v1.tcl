# SPDX-License-Identifier: GPL-3.0-or-later
# Shared source-bound UML presentation on the existing Native2D surface/chrome.
# These records are disposable view lifetimes, not another document/model store.
namespace eval ::GX::UmlV1 {variable views {};variable viewSerial 0}
proc ::GX::_umlTransformPrimitives {primitives scale tx ty} {
    set result {}
    foreach primitive $primitives {
        set coords {};foreach {x y} [dict get $primitive coords] {lappend coords [expr {$x*$scale+$tx}] [expr {$y*$scale+$ty}]}
        dict set primitive coords $coords
        if {[dict exists $primitive font_size]} {dict set primitive font_size [expr {max(1,min(256,[dict get $primitive font_size]*$scale))}]}
        if {[dict exists $primitive width]} {dict set primitive width [expr {max(.6,[dict get $primitive width]*$scale)}]}
        lappend result $primitive
    }
    return $result
}
proc ::GX::umlDiagramMount {parent source {options {}}} {
    variable ::GX::UmlV1::views;variable ::GX::UmlV1::viewSerial
    _umlRequest $options {editable on_select on_move on_activate font_size controls} {}
    set options [dict merge {editable 0 on_select {} on_move {} on_activate {} font_size {} controls 1} $options]
    # Live diagrams follow the user's actual UI font. Layout and painting use
    # the same pixel size; explicitly sized callers and exports keep their size.
    if {[dict get $options font_size] eq {}} {
        set size [font actual TkDefaultFont -size]
        if {$size>0} {set size [expr {$size*[winfo fpixels . 1p]}]} else {set size [expr {-$size}]}
        dict set options font_size [expr {max(14.,min(32.,$size))}]
    }
    foreach key {editable controls} {if {![string is boolean -strict [dict get $options $key]]} {error {UML view switches must be boolean}}}
    foreach key {on_select on_move on_activate} {
        set prefix [dict get $options $key]
        if {$prefix ne {} && (![llength $prefix] || ![llength [info commands [lindex $prefix 0]]])} {error {UML view callbacks require trusted live CORE commands}}
    }
    set parsed [umlDocumentParse $source]
    if {![dict get $parsed valid]} {error {A UML Diagram requires valid current source; inspect its source diagnostics}}
    native2DEnsure
    if {![llength [info commands ::gx::native2d::text_metrics]] || ![dict get [::gx::native2d::text_engine_info] available]} {error {The shared UML shaped-text capability is unavailable; original source remains inspectable}}
    set plan [umlDocumentLayout $parsed [dict create font_size [dict get $options font_size]]]
    if {![winfo exists $parent]} {ttk::frame $parent}
    ::gx::native2d::surface $parent.canvas -background #ffffff
    pack $parent.canvas -fill both -expand 1
    set handle uml-view#[incr viewSerial]
    dict set views $handle [dict create parent $parent canvas $parent.canvas source $source plan $plan options $options zoom 1.0 pan {0 0} selected {} drag {} pending {} fit_pending 1 viewport_mode fit]
    native2DViewportHostCreate $parent $parent.canvas {} [list ::GX::_umlDiagramSchedule $handle]
    if {[dict get $options controls]} {
        set actions {};foreach action {fit_all zoom_in zoom_out} {dict set actions $action [list ::GX::umlDiagramCommand $handle [expr {$action eq {fit_all}?{fit}:$action}]]}
        native2DViewportControls $parent.canvas {fit_all zoom_in zoom_out} $actions
        set chrome [native2DViewportPanelWidget $parent.canvas controls]
        bind $chrome <Configure> +[list ::GX::_umlDiagramConfigure $handle]
    }
    bind $parent.canvas <Configure> +[list ::GX::_umlDiagramConfigure $handle]
    bind $parent.canvas <Destroy> +[list ::GX::_umlDiagramDestroyed $handle %W]
    bind $parent.canvas <Button-4> [list ::GX::umlDiagramCommand $handle zoom_in]
    bind $parent.canvas <Button-5> [list ::GX::umlDiagramCommand $handle zoom_out]
    bind $parent.canvas <Double-Button-1> [list ::GX::_umlDiagramActivate $handle]
    bind $parent.canvas <ButtonPress-1> [list ::GX::_umlDiagramPointer $handle start %x %y]
    bind $parent.canvas <B1-Motion> [list ::GX::_umlDiagramPointer $handle move %x %y]
    bind $parent.canvas <ButtonRelease-1> [list ::GX::_umlDiagramPointer $handle end %x %y]
    bind $parent.canvas <ButtonPress-2> [list ::GX::_umlDiagramPan $handle start %x %y]
    bind $parent.canvas <B2-Motion> [list ::GX::_umlDiagramPan $handle move %x %y]
    foreach {key operation} {<F8> zoom_in <F7> zoom_out <Control-0> zoom_reset <Home> fit} {bind $parent.canvas $key [list ::GX::umlDiagramCommand $handle $operation]}
    foreach {key delta} {<Left> {30 0} <Right> {-30 0} <Up> {0 30} <Down> {0 -30}} {bind $parent.canvas $key [list ::GX::umlDiagramCommand $handle pan [dict create dx [lindex $delta 0] dy [lindex $delta 1]]]}
    bind $parent.canvas <Return> [list ::GX::_umlDiagramActivate $handle]
    _umlDiagramSchedule $handle
    return $handle
}
proc ::GX::_umlView {handle} {
    if {![dict exists $::GX::UmlV1::views $handle]} {error {UML view lifetime ended}}
    set view [dict get $::GX::UmlV1::views $handle]
    if {![winfo exists [dict get $view canvas]]} {error {UML view lifetime ended}}
    return $view
}
proc ::GX::_umlDiagramDestroyed {handle actual} {
    if {![dict exists $::GX::UmlV1::views $handle] || [dict get $::GX::UmlV1::views $handle canvas] ne $actual} return
    set pending [dict get $::GX::UmlV1::views $handle pending]
    if {$pending ne {}} {after cancel $pending}
    dict unset ::GX::UmlV1::views $handle
}
proc ::GX::_umlDiagramSchedule {handle} {
    if {![dict exists $::GX::UmlV1::views $handle] || [dict get $::GX::UmlV1::views $handle pending] ne {}} return
    dict set ::GX::UmlV1::views $handle pending [after idle [list ::GX::_umlDiagramDraw $handle]]
}
proc ::GX::_umlDiagramConfigure {handle} {
    if {![dict exists $::GX::UmlV1::views $handle]} return
    if {[dict get $::GX::UmlV1::views $handle viewport_mode] eq {fit}} {dict set ::GX::UmlV1::views $handle fit_pending 1}
    _umlDiagramSchedule $handle
}
proc ::GX::_umlDiagramDraw {handle} {
    if {[catch {set view [_umlView $handle]}]} return
    dict set ::GX::UmlV1::views $handle pending {}
    set canvas [dict get $view canvas]
    if {[winfo width $canvas]<20 || [winfo height $canvas]<20} return
    if {[dict get $view fit_pending]} {umlDiagramCommand $handle fit;set view [_umlView $handle]}
    set scale [dict get $view zoom];lassign [dict get $view pan] tx ty
    set primitives [_umlTransformPrimitives [dict get $view plan primitives] $scale $tx $ty]
    set selected [dict get $view selected]
    if {$selected ne {} && [dict exists $view plan hit_map $selected]} {
        set bounds [dict get $view plan hit_map $selected bounds];set coords {}
        foreach {x y} $bounds {lappend coords [expr {$x*$scale+$tx}] [expr {$y*$scale+$ty}]}
        set drag [dict get $view drag]
        if {$drag ne {} && [dict exists $drag delta]} {lassign [dict get $drag delta] dx dy;set moved {};foreach {x y} $coords {lappend moved [expr {$x+$dx}] [expr {$y+$dy}]};set coords $moved}
        lappend primitives [_umlPrimitive rectangle $coords stroke #1674c4 width 2.5]
    }
    $canvas draw $primitives
}
proc ::GX::_umlDiagramSelect {handle id} {
    set view [_umlView $handle]
    if {$id ne {} && ![dict exists $view plan hit_map $id]} {error {Selected UML item is not in the current source}}
    dict set ::GX::UmlV1::views $handle selected $id
    _umlDiagramSchedule $handle
    set callback [dict get $view options on_select]
    if {$callback ne {}} {uplevel #0 [list {*}$callback $handle $id]}
}
proc ::GX::_umlDiagramPointer {handle phase x y} {
    set view [_umlView $handle];set canvas [dict get $view canvas]
    if {$phase eq {start}} {
        focus $canvas
        set id [umlDiagramCommand $handle hit [dict create x $x y $y]]
        _umlDiagramSelect $handle $id
        set drag {}
        if {$id ne {} && [dict get $view options editable] && [dict get $view plan hit_map $id kind] eq {element}} {set drag [dict create id $id start [list $x $y] delta {0 0}]}
        dict set ::GX::UmlV1::views $handle drag $drag
    } elseif {[dict get $view drag] ne {}} {
        lassign [dict get $view drag start] sx sy
        set dx [expr {$x-$sx}];set dy [expr {$y-$sy}]
        if {[dict get $view plan family] eq {sequence}} {set dy 0}
        if {$phase eq {move}} {dict set ::GX::UmlV1::views $handle drag delta [list $dx $dy];_umlDiagramSchedule $handle;return}
        dict set ::GX::UmlV1::views $handle drag {}
        if {hypot($dx,$dy)>=4} {
            set id [dict get $view drag id];set callback [dict get $view options on_move]
            lassign [dict get $view plan hit_map $id bounds] left top right bottom
            if {[dict get $view plan family] eq {sequence}} {set top 0}
            if {$callback ne {}} {uplevel #0 [list {*}$callback $handle $id [expr {$left+$dx/[dict get $view zoom]}] [expr {$top+$dy/[dict get $view zoom]}]]}
        }
        _umlDiagramSchedule $handle
    }
}
proc ::GX::_umlDiagramPan {handle phase x y} {
    set view [_umlView $handle]
    if {$phase eq {start}} {dict set ::GX::UmlV1::views $handle pan_drag [list $x $y {*}[dict get $view pan]];return}
    if {![dict exists $view pan_drag]} return
    lassign [dict get $view pan_drag] sx sy tx ty
    dict set ::GX::UmlV1::views $handle pan [list [expr {$tx+$x-$sx}] [expr {$ty+$y-$sy}]]
    dict set ::GX::UmlV1::views $handle viewport_mode manual
    _umlDiagramSchedule $handle
}
proc ::GX::_umlDiagramActivate {handle} {
    set view [_umlView $handle];set callback [dict get $view options on_activate]
    if {$callback ne {} && [dict get $view selected] ne {}} {uplevel #0 [list {*}$callback $handle [dict get $view selected]]}
}
proc ::GX::umlDiagramCommand {handle operation {request {}}} {
    set view [_umlView $handle]
    switch -- $operation {
        inspect {return [dict create source_sha256 [dict get $view plan source_sha256] layout_sha256 [dict get $view plan layout_sha256] bounds [dict get $view plan bounds] selected [dict get $view selected] zoom [dict get $view zoom] pan [dict get $view pan] renderer Native2D.C++.Cairo]}
        source_set {
            _umlRequest $request {source} {source}
            set parsed [umlDocumentParse [dict get $request source]]
            if {![dict get $parsed valid]} {error {UML diagram source has diagnostics; the previous source-bound view is retained}}
            set plan [umlDocumentLayout $parsed [dict create font_size [dict get $view options font_size]]]
            dict set ::GX::UmlV1::views $handle source [dict get $request source]
            dict set ::GX::UmlV1::views $handle plan $plan
            if {[dict get $view viewport_mode] eq {fit}} {dict set ::GX::UmlV1::views $handle fit_pending 1}
            if {[dict get $view selected] ne {} && ![dict exists $plan hit_map [dict get $view selected]]} {dict set ::GX::UmlV1::views $handle selected {}}
        }
        fit {
            set canvas [dict get $view canvas];lassign [dict get $view plan bounds] x1 y1 x2 y2
            # The shared chrome owns its actual font/theme-dependent size.
            # Reserve its painted area instead of hiding a title beneath it.
            set top 58.
            if {[dict get $view options controls]} {
                set chrome [native2DViewportPanelWidget $canvas controls]
                if {[winfo exists $chrome]} {
                    if {[winfo ismapped $chrome] && [winfo height $chrome]>1} {
                        set top [expr {max($top,[winfo rooty $chrome]+[winfo height $chrome]-[winfo rooty $canvas]+8.)}]
                    } else {set top [expr {max($top,[winfo reqheight $chrome]+16.)}]}
                }
            }
            set scale [expr {max(.005,min(1.5,([winfo width $canvas]-48.)/max(1,$x2-$x1),([winfo height $canvas]-$top-24.)/max(1,$y2-$y1)))}]
            dict set ::GX::UmlV1::views $handle zoom $scale
            dict set ::GX::UmlV1::views $handle pan [list [expr {24-$x1*$scale}] [expr {$top-$y1*$scale}]]
            dict set ::GX::UmlV1::views $handle fit_pending 0
            dict set ::GX::UmlV1::views $handle viewport_mode fit
        }
        zoom_in - zoom_out - zoom_reset {
            set old [dict get $view zoom];set scale [expr {$operation eq {zoom_reset}?1.0:($old*($operation eq {zoom_in}?1.25:.8))}]
            set scale [expr {max(.005,min(8.,$scale))}]
            set canvas [dict get $view canvas];set cx [expr {[winfo width $canvas]/2.}];set cy [expr {[winfo height $canvas]/2.}]
            lassign [dict get $view pan] tx ty
            dict set ::GX::UmlV1::views $handle zoom $scale
            dict set ::GX::UmlV1::views $handle pan [list [expr {$cx-($cx-$tx)*$scale/$old}] [expr {$cy-($cy-$ty)*$scale/$old}]]
            dict set ::GX::UmlV1::views $handle fit_pending 0
            dict set ::GX::UmlV1::views $handle viewport_mode manual
        }
        pan {
            _umlRequest $request {dx dy} {dx dy}
            foreach key {dx dy} {set v [dict get $request $key];if {![string is double -strict $v] || ![expr {abs($v)<=10000}]} {error {Pan delta must be finite and bounded}}}
            lassign [dict get $view pan] x y
            dict set ::GX::UmlV1::views $handle pan [list [expr {$x+[dict get $request dx]}] [expr {$y+[dict get $request dy]}]]
            dict set ::GX::UmlV1::views $handle viewport_mode manual
        }
        select {_umlRequest $request {id} {id};_umlDiagramSelect $handle [dict get $request id]}
        hit {
            _umlRequest $request {x y} {x y}
            lassign [dict get $view pan] tx ty
            set x [expr {([dict get $request x]-$tx)/[dict get $view zoom]}];set y [expr {([dict get $request y]-$ty)/[dict get $view zoom]}]
            set best {};set area 1e30
            dict for {id item} [dict get $view plan hit_map] {
                lassign [dict get $item bounds] x1 y1 x2 y2
                if {$x<$x1 || $x>$x2 || $y<$y1 || $y>$y2} continue
                if {[dict exists $item path]} {
                    set tolerance [expr {max(3.,5./[dict get $view zoom])}]
                    set close 0;set previous {}
                    foreach {px py} [dict get $item path] {
                        if {$previous ne {}} {
                            lassign $previous ax ay;set dx [expr {$px-$ax}];set dy [expr {$py-$ay}]
                            set denominator [expr {$dx*$dx+$dy*$dy}]
                            set t [expr {$denominator?max(0.,min(1.,(($x-$ax)*$dx+($y-$ay)*$dy)/$denominator)):0.}]
                            if {hypot($x-$ax-$t*$dx,$y-$ay-$t*$dy)<=$tolerance} {set close 1;break}
                        }
                        set previous [list $px $py]
                    }
                    if {!$close} continue
                }
                set size [expr {abs(($x2-$x1)*($y2-$y1))}]
                if {$size<$area} {set best $id;set area $size}
            }
            return $best
        }
        capture {
            # Fit is a portable user intent; its geometry-derived scale/offset
            # must not dirty a new/cold document when the window is mapped.
            if {[dict get $view viewport_mode] eq {fit}} {return [dict create mode fit zoom 1.0 pan {0 0} selected [dict get $view selected]]}
            return [dict create mode manual zoom [dict get $view zoom] pan [dict get $view pan] selected [dict get $view selected]]
        }
        restore {
            _umlRequest $request {mode zoom pan selected} {mode zoom pan selected}
            if {[dict get $request mode] ni {fit manual}} {error {Invalid UML viewport mode}}
            set zoom [dict get $request zoom]
            if {![string is double -strict $zoom] || !($zoom>=.005 && $zoom<=8) || [llength [dict get $request pan]]!=2} {error {Invalid UML viewport state}}
            foreach value [dict get $request pan] {if {![string is double -strict $value] || ![expr {abs($value)<=1000000}]} {error {Invalid UML pan state}}}
            dict set ::GX::UmlV1::views $handle zoom $zoom;dict set ::GX::UmlV1::views $handle pan [dict get $request pan]
            set id [dict get $request selected];if {$id ne {} && ![dict exists $view plan hit_map $id]} {set id {}}
            dict set ::GX::UmlV1::views $handle selected $id
            dict set ::GX::UmlV1::views $handle viewport_mode [dict get $request mode]
            dict set ::GX::UmlV1::views $handle fit_pending [expr {[dict get $request mode] eq {fit}}]
        }
        dispose {destroy [dict get $view canvas];return {status closed}}
        default {error {Unknown finite UML diagram view operation}}
    }
    _umlDiagramSchedule $handle
    return [umlDiagramCommand $handle inspect]
}
proc ::GX::umlDocumentExport {source format {options {}}} {
    if {$format ni {source png svg}} {error {UML export supports exact source, PNG or SVG}}
    _umlRequest $options {width height font_size} {}
    set parsed [umlDocumentParse $source];set plan {}
    if {$format ne {source} && ![dict get $parsed valid]} {error {Visual export requires the current valid UML source; raw source export remains available}}
    set allocation [resourceManagementAllocate uml_document_export [dict create category temporary lifetime viewer retention_seconds 0]]
    try {
        if {$format eq {source}} {
            set path [file join [dict get $allocation path] diagram.puml]
            set file [open $path {WRONLY CREAT EXCL} 0600]
            try {fconfigure $file -translation binary -encoding binary;puts -nonewline $file [encoding convertto utf-8 $source]} finally {close $file}
        } else {
            set width [datasetPublicationV2DictDefault $options width 1600];set height [datasetPublicationV2DictDefault $options height 1200]
            foreach v [list $width $height] {if {![string is integer -strict $v] || $v<64 || $v>8192} {error {Export dimensions must be integers between 64 and 8192}}}
            if {$width*$height>16777216} {error {UML export exceeds 16 megapixels}}
            native2DEnsure
            if {![llength [info commands ::gx::native2d::text_metrics]] || ![dict get [::gx::native2d::text_engine_info] available]} {error {The shared UML shaped-text export capability is unavailable; exact source export remains available}}
            set plan [umlDocumentLayout $parsed [dict create font_size [datasetPublicationV2DictDefault $options font_size 14]]]
            set path [file join [dict get $allocation path] diagram.$format]
            lassign [dict get $plan bounds] x1 y1 x2 y2
            set scale [expr {min(($width-40.)/max(1,$x2-$x1),($height-40.)/max(1,$y2-$y1))}]
            set primitives [_umlTransformPrimitives [dict get $plan primitives] $scale [expr {20-$x1*$scale}] [expr {20-$y1*$scale}]]
            ::gx::native2d::render $path $width $height $primitives
        }
        if {[file size $path]>16777216} {error {UML export exceeds 16 MiB}}
        return [dict create schema gxtxt.uml.export.v1 allocation $allocation path $path format $format sha256 [sha256File $path] \
            source_sha256 [dict get $parsed source_sha256] source_valid [dict get $parsed valid] layout_sha256 [datasetPublicationV2DictDefault $plan layout_sha256 {}] \
            renderer [expr {$format eq {source}?{exact_UTF8_source}:{Native2D.C++.Cairo}}]]
    } on error {message opts} {documentInteractiveAllocationRelease $allocation;return -options $opts $message}
}
proc ::GX::umlDocumentExportRelease {receipt} {
    set id [dict get $receipt allocation id];set actual [resourceManagementInspect $id]
    if {[dict get $actual subsystem] ne {uml_document_export} || [dict get $actual owner_pid]!=[pid]} {error {Export receipt does not belong to this UML host}}
    documentInteractiveAllocationRelease $actual
}
