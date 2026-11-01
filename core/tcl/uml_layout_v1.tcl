# SPDX-License-Identifier: GPL-3.0-or-later
# Semantic layout only. The existing Native2D primitive painter owns pixels and
# PNG/SVG export; Editor and Preview consume this same source-bound plan.
namespace eval ::GX::UmlV1 {variable metricsCache {};variable metricsBytes 0;variable metricsWork 0;variable lineHeight 21;variable labelWork 0}
proc ::GX::_umlMetrics {text size} {
    variable ::GX::UmlV1::metricsCache;variable ::GX::UmlV1::metricsBytes;variable ::GX::UmlV1::metricsWork
    set key [list $size $text]
    if {[dict exists $metricsCache $key]} {return [dict get $metricsCache $key]}
    incr metricsWork
    if {$metricsWork>12000} {error {UML layout exceeds its bounded font-measurement budget; simplify labels while retaining source}}
    if {[llength [info commands ::gx::native2d::text_metrics]]} {
        set metrics [::gx::native2d::text_metrics {DejaVu Sans} $size $text]
    } elseif {[llength [info commands ::font]]} {
        set font [list {DejaVu Sans} -[expr {round($size)}]]
        set metrics [dict create width [font measure $font $text] height [font metrics $font -linespace] engine Tk]
    } else {
    # Headless conservative layout is explicitly identified in its receipt.
        set wide [regexp -all {[^\x00-\u02ff]} $text]
        set metrics [dict create width [expr {ceil($size*([string length $text]*.65+$wide*.35))}] height [expr {ceil($size*1.45)}] engine conservative_headless]
    }
    if {[dict size $metricsCache]<4096 && $metricsBytes+[string bytelength $key]<1048576} {dict set metricsCache $key $metrics;incr metricsBytes [string bytelength $key]}
    return $metrics
}
proc ::GX::_umlWidth {text size} {dict get [_umlMetrics $text $size] width}
proc ::GX::_umlWrap {text size width} {
    set lines {};set line {}
    foreach word [regexp -all -inline {\S+} $text] {
        if {$line ne {} && [_umlWidth "$line $word" $size]>$width} {lappend lines $line;set line {}}
        if {[_umlWidth $line$word $size]<=$width} {append line $word { };continue}
        for {set index 0} {$index<[string length $word]} {incr index} {
            set character [string index $word $index];scan $character %c code
            # Keep Tcl 8.x's internal surrogate pair together before measuring.
            if {$code>=0xd800 && $code<=0xdbff} {append character [string index $word [incr index]]}
            if {$line ne {} && [_umlWidth $line$character $size]>$width} {lappend lines $line;set line {}}
            append line $character
        }
        append line { }
    }
    if {[string trimright $line] ne {}} {lappend lines [string trimright $line]}
    if {![llength $lines]} {set lines [list {}]}
    return $lines
}
proc ::GX::_umlPrimitive {type coords args} {
    return [dict merge [dict create type $type coords $coords stroke #293d50 fill {} width 1.4] $args]
}
proc ::GX::_umlText {x y text size {anchor nw}} {
    return [_umlPrimitive text [list $x $y] text $text font_family {DejaVu Sans} font_size $size fill #172f43 anchor $anchor text_engine PangoCairo text_engine_version 1]
}
proc ::GX::_umlTextLines {x y lines size primitivesVar {anchor nw}} {
    upvar 1 $primitivesVar primitives
    foreach line $lines {lappend primitives [_umlText $x $y [string trimright $line] $size $anchor];set y [expr {$y+$::GX::UmlV1::lineHeight}]}
}
proc ::GX::_umlArrow {point previous kind primitivesVar {semanticId {}}} {
    upvar 1 $primitivesVar primitives
    lassign $point x y;lassign $previous px py
    set dx [expr {$x-$px}];set dy [expr {$y-$py}];set length [expr {hypot($dx,$dy)}]
    if {$length<.001} return
    set ux [expr {$dx/$length}];set uy [expr {$dy/$length}]
    set nx [expr {-$uy}];set ny $ux
    set ax [expr {$x-12*$ux}];set ay [expr {$y-12*$uy}]
    set a [list [expr {$ax+6*$nx}] [expr {$ay+6*$ny}]];set b [list [expr {$ax-6*$nx}] [expr {$ay-6*$ny}]]
    set first [llength $primitives]
    switch -- $kind {
        generalization - realization {lappend primitives [_umlPrimitive polygon [list $x $y {*}$a {*}$b] fill #ffffff]}
        aggregation - composition {
            set middleX [expr {$x-8*$ux}];set middleY [expr {$y-8*$uy}]
            set coords [list $x $y [expr {$middleX+5*$nx}] [expr {$middleY+5*$ny}] [expr {$x-16*$ux}] [expr {$y-16*$uy}] [expr {$middleX-5*$nx}] [expr {$middleY-5*$ny}]]
            lappend primitives [_umlPrimitive polygon $coords fill [expr {$kind eq {composition}?{#293d50}:{#ffffff}}]]
        }
        sync {lappend primitives [_umlPrimitive polygon [list $x $y {*}$a {*}$b] fill #293d50]}
        default {lappend primitives [_umlPrimitive polyline [list {*}$a $x $y {*}$b]]}
    }
    for {set index $first} {$index<[llength $primitives]} {incr index} {
        set primitive [lindex $primitives $index]
        dict set primitive semantic_id $semanticId;dict set primitive semantic_role arrow_head
        lset primitives $index $primitive
    }
}
proc ::GX::_umlRouteClear {coords boxes {routes {}}} {
    set px [lindex $coords 0];set py [lindex $coords 1]
    foreach {x y} [lrange $coords 2 end] {
        dict for {id box} $boxes {
            lassign [dict get $box bounds] left top right bottom
            if {abs($y-$py)<.001} {
                if {$y>$top+1 && $y<$bottom-1 && max(min($x,$px),$left+1)<min(max($x,$px),$right-1)} {return 0}
            } elseif {abs($x-$px)<.001} {
                if {$x>$left+1 && $x<$right-1 && max(min($y,$py),$top+1)<min(max($y,$py),$bottom-1)} {return 0}
            } else {error {UML connector routing must be orthogonal}}
        }
        foreach route $routes {
            lassign $route rx ry
            foreach {ex ey} [lrange $route 2 end] {
                if {abs($y-$py)<.001 && abs($ey-$ry)<.001 && abs($y-$ry)<1 && min(max($x,$px),max($rx,$ex))-max(min($x,$px),min($rx,$ex))>2} {return 0}
                if {abs($x-$px)<.001 && abs($ex-$rx)<.001 && abs($x-$rx)<1 && min(max($y,$py),max($ry,$ey))-max(min($y,$py),min($ry,$ey))>2} {return 0}
                set rx $ex;set ry $ey
            }
        }
        set px $x;set py $y
    }
    return 1
}
proc ::GX::_umlNearest {values origin {count 24}} {
    set sorted {};foreach value [lsort -real -unique $values] {lappend sorted [list [expr {abs($value-$origin)}] $value]}
    set result {};foreach item [lrange [lsort -real -index 0 $sorted] 0 [expr {$count-1}]] {lappend result [lindex $item 1]}
    return $result
}
proc ::GX::_umlRoute {from to boxes fromLane toLane bias routes} {
    lassign [dict get $boxes $from bounds] ax ay ar ab
    lassign [dict get $boxes $to bounds] bx by br bb
    set acx [expr {max($ax+12,min($ar-12,($ax+$ar)/2.+$fromLane))}];set acy [expr {max($ay+12,min($ab-12,($ay+$ab)/2.+$fromLane))}]
    set bcx [expr {max($bx+12,min($br-12,($bx+$br)/2.+$toLane))}];set bcy [expr {max($by+12,min($bb-12,($by+$bb)/2.+$toLane))}]
    if {$from eq $to} {return [list $ar [expr {$ay+25}] [expr {$ar+45}] [expr {$ay+25}] [expr {$ar+45}] [expr {$ab-20}] $ar [expr {$ab-20}]]}
    set xs [list [expr {($acx+$bcx)/2.}]];set ys [list [expr {($acy+$bcy)/2.}]]
    dict for {id box} $boxes {lassign [dict get $box bounds] x1 y1 x2 y2;lappend xs [expr {$x1-24}] [expr {$x2+24}];lappend ys [expr {$y1-24}] [expr {$y2+24}]}
    set vertical {}
    if {$ab<=$by} {lappend vertical [list $acx $ab $bcx $by]} elseif {$bb<=$ay} {lappend vertical [list $acx $ay $bcx $bb]}
    lappend vertical [list $acx $ay $bcx $by] [list $acx $ab $bcx $bb]
    set horizontal {}
    if {$ar<=$bx} {lappend horizontal [list $ar $acy $bx $bcy]} elseif {$br<=$ax} {lappend horizontal [list $ax $acy $br $bcy]}
    lappend horizontal [list $ax $acy $bx $bcy] [list $ar $acy $br $bcy]
    # Favor the gap between hierarchy rows before lateral paths. Every candidate
    # is checked against every actual semantic box, including variable heights.
    foreach ports $vertical {
        lassign $ports sx sy ex ey
        foreach mid [_umlNearest [concat [list [expr {($sy+$ey)/2.+$bias}]] $ys] [expr {($sy+$ey)/2.+$bias}]] {
            set coords [list $sx $sy $sx $mid $ex $mid $ex $ey]
            if {[_umlRouteClear $coords $boxes $routes]} {return $coords}
        }
    }
    foreach ports $horizontal {
        lassign $ports sx sy ex ey
        foreach mid [_umlNearest [concat [list [expr {($sx+$ex)/2.+$bias}]] $xs] [expr {($sx+$ex)/2.+$bias}]] {
            set coords [list $sx $sy $mid $sy $mid $ey $ex $ey]
            if {[_umlRouteClear $coords $boxes $routes]} {return $coords}
        }
    }
    # A longer hierarchy edge may need a clear inter-column channel. Bound the
    # search; a routing refusal never turns a connector through a class into PASS.
    foreach ports $vertical {
        lassign $ports sx sy ex ey
        foreach exit [_umlNearest $ys $sy 6] {
            if {![_umlRouteClear [list $sx $sy $sx $exit] $boxes]} continue
            foreach enter [_umlNearest $ys $ey 6] {
                if {![_umlRouteClear [list $ex $enter $ex $ey] $boxes]} continue
                foreach channel [_umlNearest $xs [expr {($sx+$ex)/2.}] 16] {
                    set coords [list $sx $sy $sx $exit $channel $exit $channel $enter $ex $enter $ex $ey]
                    if {[_umlRouteClear $coords $boxes $routes]} {return $coords}
                }
            }
        }
    }
    error {No bounded connector route avoids semantic boxes; adjust layout while retaining source}
}
proc ::GX::_umlMultiplicityLabel {point neighbor text size primitivesVar} {
    upvar 1 $primitivesVar primitives
    if {$text eq {}} return
    lassign $point x y;lassign $neighbor px py
    if {abs($px-$x)>abs($py-$y)} {
        set x [expr {$px>$x?$x+9:$x-[_umlWidth $text $size]-9}];set y [expr {$y-$::GX::UmlV1::lineHeight-6}]
    } else {set x [expr {$x+9}];set y [expr {$py>$y?$y+6:$y-$::GX::UmlV1::lineHeight-6}]}
    lappend primitives [_umlText $x $y $text $size]
}
proc ::GX::_umlLabelClear {bounds obstacles routes} {
    variable ::GX::UmlV1::labelWork
    lassign $bounds left top right bottom
    foreach obstacle $obstacles {
        if {[incr labelWork]>250000} {error {UML relationship labels exceed the bounded clearance budget; adjust layout while retaining source}}
        lassign $obstacle x1 y1 x2 y2
        if {$left<$x2+6 && $right>$x1-6 && $top<$y2+6 && $bottom>$y1-6} {return 0}
    }
    foreach route $routes {
        lassign $route px py
        foreach {x y} [lrange $route 2 end] {
            if {[incr labelWork]>250000} {error {UML relationship labels exceed the bounded clearance budget; adjust layout while retaining source}}
            if {$left<max($px,$x)+3 && $right>min($px,$x)-3 && $top<max($py,$y)+3 && $bottom>min($py,$y)-3} {return 0}
            set px $x;set py $y
        }
    }
    return 1
}
proc ::GX::_umlRelationshipLabel {coords lines size obstacles routes} {
    set width 0;set height 0;set row 0
    foreach text $lines {
        set metrics [_umlMetrics [string trimright $text] $size]
        set width [expr {max($width,[dict get $metrics width])}]
        set height [expr {max($height,$row*$::GX::UmlV1::lineHeight+[dict get $metrics height])}]
        incr row
    }
    set segments {};lassign $coords px py
    foreach {x y} [lrange $coords 2 end] {
        set length [expr {hypot($x-$px,$y-$py)}]
        if {$length>.001} {lappend segments [list $length $px $py $x $y]}
        set px $x;set py $y
    }
    # Try both adjacent sides before increasing the clearance. A lower route
    # must not inherit an unconditional "above" placement inside its class.
    foreach gap {8 24 48 96} {
        foreach segment [lsort -real -index 0 -decreasing $segments] {
            lassign $segment length ax ay bx by
            foreach fraction {.5 .25 .75} {
                set x [expr {$ax+($bx-$ax)*$fraction}];set y [expr {$ay+($by-$ay)*$fraction}]
                if {abs($ay-$by)<.001} {
                    set candidates [list [list [expr {$x-$width/2.}] [expr {$y-$gap-$height}]] [list [expr {$x-$width/2.}] [expr {$y+$gap}]]]
                } else {
                    set candidates [list [list [expr {$x+$gap}] [expr {$y-$height/2.}]] [list [expr {$x-$gap-$width}] [expr {$y-$height/2.}]]]
                }
                foreach candidate $candidates {
                    lassign $candidate left top
                    set bounds [list $left $top [expr {$left+$width}] [expr {$top+$height}]]
                    if {[_umlLabelClear $bounds $obstacles $routes]} {return $bounds}
                }
            }
        }
    }
    error {No bounded relationship label placement avoids semantic boxes and connectors; adjust layout while retaining source}
}
proc ::GX::_umlClassLayout {model size primitivesVar hitsVar} {
    upvar 1 $primitivesVar primitives $hitsVar hits
    set line $::GX::UmlV1::lineHeight;set ranks {};set boxes {};set groups {}
    dict for {id item} [dict get $model elements] {dict set ranks $id 0}
    for {set pass 0} {$pass<[dict size $ranks]} {incr pass} {
        set changed 0
        foreach rel [dict get $model relations] {
            if {[dict get $rel kind] ne {generalization}} continue
            set base [dict get $rel [expr {[dict get $rel marker] eq {start}?{from}:{to}}]]
            set child [dict get $rel [expr {[dict get $rel marker] eq {start}?{to}:{from}}]]
            if {[dict get $ranks $child]<[dict get $ranks $base]+1} {dict set ranks $child [expr {[dict get $ranks $base]+1}];set changed 1}
        }
        if {!$changed} break
    }
    dict for {id item} [dict get $model elements] {dict lappend groups [dict get $ranks $id] $id}
    set top 90
    foreach rank [lsort -integer [dict keys $groups]] {
        set x 50;set column 0;set rowHeight 0
        foreach id [dict get $groups $rank] {
            set item [dict get $model elements $id];set attrs {};set ops {};set width 180
            set names [_umlWrap [dict get $item name] $size 390]
            foreach name $names {set width [expr {max($width,[_umlWidth $name $size]+28)}]}
            foreach member [dict get $item members] {
                set lines [_umlWrap "[dict get $member visibility] [dict get $member text]" $size 390]
                foreach text $lines {set width [expr {max($width,[_umlWidth $text $size]+28)}]}
                set row [dict create item $member lines $lines]
                if {[dict get $member kind] eq {operation}} {lappend ops $row} else {lappend attrs $row}
            }
            set header [expr {20+[llength $names]*$line+([dict get $item type] eq {interface}?$line:0)}]
            set ah [expr {14+$line*max(1,[llength $attrs])}];set oh [expr {14+$line*max(1,[llength $ops])}]
            foreach row $attrs {set ah [expr {$ah+([llength [dict get $row lines]]-1)*$line}]}
            foreach row $ops {set oh [expr {$oh+([llength [dict get $row lines]]-1)*$line}]}
            set height [expr {$header+$ah+$oh}];set y $top;set left $x
            if {[dict exists $model positions $id]} {set left [dict get $model positions $id x];set y [dict get $model positions $id y]}
            dict set boxes $id [dict create bounds [list $left $y [expr {$left+$width}] [expr {$y+$height}]] header $header ah $ah names $names attrs $attrs ops $ops]
            set x [expr {$x+$width+100}];set rowHeight [expr {max($rowHeight,$height)}]
            incr column
            if {$column==3} {set top [expr {$top+$rowHeight+100}];set rowHeight 0;set x 50;set column 0}
        }
        if {$column} {set top [expr {$top+$rowHeight+100}]}
    }
    # Relationships are painted first so boxes mask their owned interior.
    set ordinal 0;set incident {};set used {};set routes {};set annotations {};set labelRequests {}
    foreach relation [dict get $model relations] {dict incr incident [dict get $relation from];dict incr incident [dict get $relation to]}
    foreach rel [dict get $model relations] {
        incr ordinal
        set offsets {}
        foreach endpoint {from to} {
            set id [dict get $rel $endpoint];set index [datasetPublicationV2DictDefault $used $id 0];dict incr used $id
            lappend offsets [expr {($index-([dict get $incident $id]-1)/2.)*18}]
        }
        set coords [_umlRoute [dict get $rel from] [dict get $rel to] $boxes {*}$offsets [expr {(($ordinal%7)-3)*12}] $routes]
        lappend routes $coords
        set primitive [_umlPrimitive polyline $coords]
        dict set primitive semantic_id [dict get $rel id];dict set primitive semantic_role connector
        if {[dict get $rel kind] in {realization dependency}} {dict set primitive dash {5 4}}
        lappend primitives $primitive
        set kind [dict get $rel kind];set at [dict get $rel marker]
        if {$kind ne {association}} {
            if {$at eq {start}} {_umlArrow [lrange $coords 0 1] [lrange $coords 2 3] $kind primitives [dict get $rel id]} else {_umlArrow [lrange $coords end-1 end] [lrange $coords end-3 end-2] $kind primitives [dict get $rel id]}
        }
        lassign [lrange $coords 0 1] sx sy;lassign [lrange $coords end-1 end] ex ey
        if {[dict get $rel label] ne {}} {lappend labelRequests [list [dict get $rel id] $coords [_umlWrap [dict get $rel label] $size 240]]}
        _umlMultiplicityLabel [lrange $coords 0 1] [lrange $coords 2 3] [dict get $rel left_multiplicity] $size annotations
        _umlMultiplicityLabel [lrange $coords end-1 end] [lrange $coords end-3 end-2] [dict get $rel right_multiplicity] $size annotations
        set minX $sx;set minY $sy;set maxX $sx;set maxY $sy
        foreach {x y} $coords {set minX [expr {min($minX,$x)}];set minY [expr {min($minY,$y)}];set maxX [expr {max($maxX,$x)}];set maxY [expr {max($maxY,$y)}]}
        dict set hits [dict get $rel id] [dict create kind relationship path $coords bounds [list [expr {$minX-8}] [expr {$minY-8}] [expr {$maxX+12}] [expr {$maxY+24}]]]
    }
    # Label placement sees every already admitted route, without changing any
    # endpoint, path, arrow or cardinality. Reserve title/cardinality text too.
    set obstacles {};dict for {id box} $boxes {lappend obstacles [dict get $box bounds]}
    foreach primitive [concat $primitives $annotations] {
        if {[dict get $primitive type] ne {text}} continue
        lassign [dict get $primitive coords] x y
        set metrics [_umlMetrics [dict get $primitive text] [dict get $primitive font_size]]
        lappend obstacles [list $x $y [expr {$x+[dict get $metrics width]}] [expr {$y+[dict get $metrics height]}]]
    }
    foreach request $labelRequests {
        lassign $request id coords lines
        set bounds [_umlRelationshipLabel $coords $lines $size $obstacles $routes]
        lappend obstacles $bounds;lassign $bounds x y
        set labelPrimitives {};_umlTextLines $x $y $lines $size labelPrimitives
        foreach primitive $labelPrimitives {dict set primitive semantic_id $id;dict set primitive semantic_role relationship_label;lappend annotations $primitive}
    }
    dict for {id box} $boxes {
        lassign [dict get $box bounds] x y right bottom
        lappend primitives [_umlPrimitive rectangle [list $x $y $right $bottom] fill #f8fbff width 1.7]
        set header [dict get $box header];set attrEnd [expr {$y+$header+[dict get $box ah]}]
        lappend primitives [_umlPrimitive rectangle [list $x $y $right [expr {$y+$header}]] fill #e9f1fa]
        lappend primitives [_umlPrimitive line [list $x $attrEnd $right $attrEnd]]
        set ty [expr {$y+10}]
        if {[dict get $model elements $id type] eq {interface}} {lappend primitives [_umlText [expr {$x+12}] $ty «interface» $size];set ty [expr {$ty+$line}]}
        _umlTextLines [expr {$x+12}] $ty [dict get $box names] $size primitives
        set ty [expr {$y+$header+7}]
        foreach section {attrs ops} {
            if {$section eq {ops}} {set ty [expr {$attrEnd+7}]}
            foreach row [dict get $box $section] {
                set member [dict get $row item];set lines [dict get $row lines]
                dict set hits [dict get $member id] [dict create kind member owner $id bounds [list $x $ty $right [expr {$ty+$line*[llength $lines]}]]]
                _umlTextLines [expr {$x+12}] $ty $lines $size primitives
                set ty [expr {$ty+$line*[llength $lines]}]
            }
        }
        dict set hits $id [dict create kind element bounds [dict get $box bounds]]
    }
    lappend primitives {*}$annotations
}
proc ::GX::_umlSequenceLayout {model size primitivesVar hitsVar} {
    upvar 1 $primitivesVar primitives $hitsVar hits
    set line $::GX::UmlV1::lineHeight;set boxes {};set x 70;set headerBottom 105
    dict for {id item} [dict get $model elements] {
        set names [_umlWrap [dict get $item name] $size 220];set width 150
        foreach name $names {set width [expr {max($width,[_umlWidth $name $size]+28)}]}
        set height [expr {22+$line*[llength $names]+([dict get $item type] eq {actor}?48:0)}]
        set left $x;if {[dict exists $model positions $id]} {set left [dict get $model positions $id x]}
        dict set boxes $id [dict create x $left width $width height $height names $names center [expr {$left+$width/2.}]]
        set x [expr {$x+$width+100}];set headerBottom [expr {max($headerBottom,65+$height)}]
    }
    set events {}
    foreach message [dict get $model messages] {lappend events [list [dict get $message line] message [dict get $message id] $message]}
    dict for {id frame} [dict get $model frames] {
        lappend events [list [dict get $frame line] open $id $frame]
        set close [dict get $frame close_span];set lineNo [expr {1+[regexp -all \n [string range [dict get $model source] 0 [expr {[lindex $close 0]-1}]]]}]
        lappend events [list $lineNo close $id $frame]
        foreach branch [dict get $frame branches] {lappend events [list [dict get $branch line] branch $id $branch]}
    }
    set y [expr {$headerBottom+40}];set messageRows {};set frameRows {};set branchRows {}
    foreach event [lsort -integer -index 0 $events] {
        lassign $event lineNo kind id item
        switch -- $kind {
            open {dict set frameRows $id top $y;set y [expr {$y+36}]}
            close {set y [expr {$y+18}];dict set frameRows $id bottom $y;set y [expr {$y+12}]}
            branch {lappend branchRows [dict create id $id y $y label [dict get $item label]];set y [expr {$y+30}]}
            message {
                set from [dict get $boxes [dict get $item from] center];set to [dict get $boxes [dict get $item to] center]
                set wrap [expr {$from==$to?200:max(100,abs($to-$from)-20)}]
                set lines [_umlWrap [dict get $item label] $size $wrap]
                dict set messageRows $id [dict create y $y lines $lines height [expr {$line*[llength $lines]+30}]]
                set y [expr {$y+$line*[llength $lines]+40}]
            }
        }
    }
    set bottom [expr {max($headerBottom+160,$y+20)}];set left 1e9;set right -1e9
    dict for {id box} $boxes {set left [expr {min($left,[dict get $box x]-35)}];set right [expr {max($right,[dict get $box x]+[dict get $box width]+35)}]}
    if {![dict size $boxes]} {set left 30;set right 500}
    dict for {id frame} [dict get $model frames] {
        set x1 [expr {$left+12*[dict get $frame depth]}];set x2 [expr {$right-12*[dict get $frame depth]}]
        set y1 [dict get $frameRows $id top];set y2 [dict get $frameRows $id bottom]
        lappend primitives [_umlPrimitive rectangle [list $x1 $y1 $x2 $y2] fill {} width 1.6]
        lappend primitives [_umlPrimitive rectangle [list $x1 $y1 [expr {min($x2,$x1+110)}] [expr {$y1+27}]] fill #e9f1fa]
        lappend primitives [_umlText [expr {$x1+7}] [expr {$y1+4}] [dict get $frame kind] $size]
        _umlTextLines [expr {$x1+120}] [expr {$y1+4}] [_umlWrap "\[[dict get $frame label]\]" $size [expr {max(100,$x2-$x1-135)}]] $size primitives
        dict set hits $id [dict create kind frame bounds [list $x1 $y1 $x2 $y2]]
    }
    foreach branch $branchRows {
        set frame [dict get $model frames [dict get $branch id]];set x1 [expr {$left+12*[dict get $frame depth]}];set x2 [expr {$right-12*[dict get $frame depth]}];set yy [dict get $branch y]
        lappend primitives [_umlPrimitive line [list $x1 $yy $x2 $yy] dash {5 4}]
        lappend primitives [_umlText [expr {$x1+10}] [expr {$yy+5}] "\[[dict get $branch label]\]" $size]
    }
    dict for {id box} $boxes {
        set xx [dict get $box x];set cx [dict get $box center];set rightBox [expr {$xx+[dict get $box width]}];set hh [dict get $box height]
        lappend primitives [_umlPrimitive line [list $cx [expr {65+$hh}] $cx $bottom] dash {6 5} stroke #8093a7]
        set ty 75
        if {[dict get $model elements $id type] eq {actor}} {
            lappend primitives [_umlPrimitive oval [list [expr {$cx-8}] 65 [expr {$cx+8}] 81] fill #f8fbff]
            lappend primitives [_umlPrimitive line [list $cx 81 $cx 101]] [_umlPrimitive line [list [expr {$cx-14}] 87 [expr {$cx+14}] 87]] [_umlPrimitive polyline [list [expr {$cx-12}] 114 $cx 101 [expr {$cx+12}] 114]]
            set ty 120
        } else {lappend primitives [_umlPrimitive rectangle [list $xx 65 $rightBox [expr {65+$hh}]] fill #e9f1fa width 1.7]}
        _umlTextLines [expr {$xx+12}] $ty [dict get $box names] $size primitives
        dict set hits $id [dict create kind element bounds [list $xx 65 $rightBox [expr {65+$hh}]]]
    }
    foreach item [dict get $model messages] {
        set id [dict get $item id];set row [dict get $messageRows $id];set yy [dict get $row y]
        set from [dict get $boxes [dict get $item from] center];set to [dict get $boxes [dict get $item to] center]
        set labelX [expr {min($from,$to)+10}]
        _umlTextLines $labelX $yy [dict get $row lines] $size primitives
        set arrowY [expr {$yy+$line*[llength [dict get $row lines]]+10}]
        if {$from==$to} {set coords [list $from $arrowY [expr {$from+45}] $arrowY [expr {$from+45}] [expr {$arrowY+15}] $to [expr {$arrowY+15}]]} else {set coords [list $from $arrowY $to $arrowY]}
        set p [_umlPrimitive polyline $coords];if {[dict get $item kind] eq {reply}} {dict set p dash {5 4}}
        lappend primitives $p
        _umlArrow [lrange $coords end-1 end] [lrange $coords end-3 end-2] [dict get $item kind] primitives $id
        dict set hits $id [dict create kind message bounds [list [expr {min($from,$to)-10}] $yy [expr {max($from,$to)+60}] [expr {$arrowY+19}]]]
    }
}
proc ::GX::umlDocumentLayout {receipt {options {}}} {
    _umlRequest $options {font_size} {}
    set size [datasetPublicationV2DictDefault $options font_size 14]
    if {![string is double -strict $size] || !($size>=10 && $size<=32)} {error {UML layout font size must be finite between 10 and 32 pixels}}
    set model [_umlReceipt $receipt];set primitives {};set hits {}
    set ::GX::UmlV1::metricsCache {};set ::GX::UmlV1::metricsBytes 0;set ::GX::UmlV1::metricsWork 0;set ::GX::UmlV1::labelWork 0
    set texts [list M «interface»]
    dict for {id item} [dict get $model elements] {lappend texts [dict get $item name];foreach member [dict get $item members] {lappend texts "[dict get $member visibility] [dict get $member text]"}}
    foreach key {relations messages} {foreach item [dict get $model $key] {lappend texts [dict get $item label]}}
    dict for {id frame} [dict get $model frames] {lappend texts [dict get $frame label]}
    set height [expr {$size*1.45}]
    foreach text $texts {set height [expr {max($height,[dict get [_umlMetrics $text $size] height]+3)}]}
    set ::GX::UmlV1::lineHeight $height
    if {[dict get $model title] ne {}} {lappend primitives [_umlText 50 20 [dict get $model title] [expr {$size+3}]]}
    if {[dict get $model family] eq {class}} {_umlClassLayout $model $size primitives hits} else {_umlSequenceLayout $model $size primitives hits}
    if {![dict size [dict get $model elements]]} {lappend primitives [_umlText 50 80 {Empty diagram — add a declared element} $size]}
    set minX 0;set minY 0;set maxX 500;set maxY 240
    foreach p $primitives {
        set coords [dict get $p coords]
        foreach {x y} $coords {set minX [expr {min($minX,$x-20)}];set minY [expr {min($minY,$y-20)}];set maxX [expr {max($maxX,$x+30)}];set maxY [expr {max($maxY,$y+30)}]}
        if {[dict get $p type] eq {text}} {
            set metrics [_umlMetrics [dict get $p text] [dict get $p font_size]]
            set maxX [expr {max($maxX,[lindex $coords 0]+[dict get $metrics width]+20)}]
            set maxY [expr {max($maxY,[lindex $coords 1]+[dict get $metrics height]+20)}]
        }
    }
    if {[llength $primitives]>50000} {error {UML layout exceeds 50000 shared Native2D primitives}}
    set sha [_umlDigest [list [dict get $model source_sha256] $size $primitives $hits]]
    return [dict create schema gxtxt.uml.layout.v1 profile gxtxt.plantuml.v1 parser_version 1 source_sha256 [dict get $model source_sha256] \
        family [dict get $model family] renderer Native2D.C++.Cairo font_size $size text_engine PangoCairo text_engine_version 1 font_metrics [dict get [_umlMetrics M $size] engine] \
        bounds [list $minX $minY $maxX $maxY] primitives $primitives hit_map $hits layout_sha256 $sha]
}
