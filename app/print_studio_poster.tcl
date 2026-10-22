# SPDX-License-Identifier: GPL-3.0-or-later
# Editable physical layout on the existing Print canvas and recipe/History.
namespace eval ::GX::PrintStudio {array set state {posterReview 0 posterSelection {} posterGesture {} layout_mode poster page_background #ffffff}}
proc ::GX::printStudioIsPoster {} {return [expr {[info exists ::GX::PrintStudio::state(recipe)] && [datasetPublicationV2DictDefault [dict get $::GX::PrintStudio::state(recipe) page] layout_mode grid] eq {poster}}]}
proc ::GX::printStudioPosterFrame {recipe {height 65}} {
    set page [dict get $recipe page];lassign [printRecipePageSize $page] width paperHeight
    set margin [dict get $page margin_mm];set gap [dict get $page gap_mm];set columns [dict get $page columns]
    set w [expr {($width-2*$margin-($columns-1)*$gap)/$columns}]
    set h [expr {min($height,$paperHeight-2*$margin)}]
    if {min($w,$h)<1} {error {Margins and columns leave no poster object area.}}
    set index [llength [dict get $recipe items]];set rows [expr {max(1,int(($paperHeight-2*$margin+$gap)/($h+$gap)))}]
    return [dict create page [expr {1+$index/($columns*$rows)}] x_mm [expr {$margin+($index%$columns)*($w+$gap)}] y_mm [expr {$margin+(($index/$columns)%$rows)*($h+$gap)}] width_mm $w height_mm $h]
}
proc ::GX::printStudioPosterInsert {kind} {
    variable ::GX::PrintStudio::state
    printStudioDocumentSession
    if {![printStudioIsPoster]} {error {Choose Poster layout in Page setup before inserting authored objects.}}
    set presentation text;set text {Body text};set style {font_size 11 foreground #142334 background #ffffff padding_mm 3};set height 65
    switch $kind {
        heading {set text {Poster heading};dict set style font_size 24;dict set style weight bold;set height 32}
        body {}
        annotation {set text {Annotation};set presentation annotation;dict set style background #fff2b3;dict set style font_size 10;set height 35}
        block {set presentation box;set text {};dict set style background #dde9f6;dict set style border #406080;dict set style border_pt 1}
        separator {set presentation separator;set text {};set height 4;dict set style padding_mm 1;dict set style border_pt 1}
        default {error {Unknown authored poster object.}}
    }
    set id print_[clock microseconds]
    set item [dict create id $id source_kind literal source_id {} source_signature {} presentation $presentation options {} caption {} text $text style $style frame [printStudioPosterFrame $state(recipe) $height]]
    set state(currentPage) [dict get $item frame page]
    set recipe $state(recipe);dict lappend recipe items $item;set state(posterSelection) $id
    printStudioEdit $recipe "Inserted $kind"
    $::GX::ui(printQueue) selection set $id
    printStudioItemSelected
    if {$presentation in {text annotation}} {printStudioPosterProperties}
}
proc ::GX::printStudioPosterItem {id} {
    foreach item [dict get $::GX::PrintStudio::state(recipe) items] {if {[dict get $item id] eq $id} {return $item}}
    error {The selected poster object no longer exists.}
}
proc ::GX::printStudioPosterProperties {} {
    variable ::GX::PrintStudio::state
    if {![printStudioIsPoster]} {error {Choose Poster layout to edit physical object properties.}}
    set id [lindex [$::GX::ui(printQueue) selection] 0];set item [printStudioPosterItem $id]
    set fields [dict create page {type integer min 1 max 200 label {Paper page}} x_mm {type number label {X from left (mm)}} y_mm {type number label {Y from top (mm)}} width_mm {type number label {Width (mm)}} height_mm {type number label {Height (mm)}} caption {type string label {Caption / source attribution}} font_size {type number min 6 max 96 label {Font size (pt)}} foreground {type color label {Text / separator color}} background {type color label {Object background}} border {type color label {Border color}} border_pt {type number min 0 max 12 label {Border width (pt)}} padding_mm {type number min 0 max 30 label {Padding (mm)}} weight {type choice values {normal bold} label {Font weight}} align {type choice values {left center right} label {Paragraph alignment}}]
    set initial [dict merge {font_size 10 foreground #142334 background #ffffff border #406080 border_pt 0 padding_mm 2 weight normal align left} [datasetPublicationV2DictDefault $item style {}] [dict get $item frame] [dict create caption [dict get $item caption]]]
    if {[dict get $item presentation] eq {table}} {
        dict set fields table_start {type string label {Table first source row (zero-based; blank = 0)}}
        dict set fields table_count {type string label {Table row count (1–10000; blank = default 200)}}
        dict set initial table_start [datasetPublicationV2DictDefault [dict get $item options] start {}]
        dict set initial table_count [datasetPublicationV2DictDefault [dict get $item options] count {}]
    }
    set state(posterPropertyItem) $item;set state(posterPropertyToken) [interactiveDocumentSessionToken]
    set form .gxPrintObjectProperties
    uiFieldFormCreate $form {Poster object — physical layout and content} $fields $initial [list ::GX::printStudioPosterPropertiesApply $id] .
    if {[dict get $item source_kind] eq {literal} && [dict get $item presentation] in {text annotation}} {
        set body $form.viewport.content
        ttk::label $body.textLabel -text {Authored paragraph (inert document text)}
        text $body.authored -height 8 -width 40 -wrap word -undo 1 -font TkTextFont
        $body.authored insert 1.0 [dict get $item text];$body.authored edit reset
        grid $body.textLabel -row 40 -column 0 -sticky w
        grid $body.authored -row 41 -column 0 -sticky ew
        bind $body.authored <FocusIn> +[list ::GX::uiFieldFormSee $form $body.authored]
    }
}
proc ::GX::printStudioPosterPropertiesApply {id values} {
    variable ::GX::PrintStudio::state
    if {[interactiveDocumentSessionToken] ne $state(posterPropertyToken) || [printStudioPosterItem $id] ne $state(posterPropertyItem)} {error {This object or Session changed; reopen its properties before applying.}}
    set item $state(posterPropertyItem);set frame {};set style {}
    foreach key {page x_mm y_mm width_mm height_mm} {dict set frame $key [dict get $values $key]}
    foreach key {font_size foreground background border border_pt padding_mm weight align} {dict set style $key [dict get $values $key]}
    dict set item frame $frame;dict set item style $style;dict set item caption [dict get $values caption]
    if {[dict get $item presentation] eq {table}} {dict set item options [printStudioTableRangeOptions [dict get $item options] [dict get $values table_start] [dict get $values table_count]]}
    if {[winfo exists .gxPrintObjectProperties.viewport.content.authored]} {dict set item text [.gxPrintObjectProperties.viewport.content.authored get 1.0 end-1c]}
    printStudioPosterReplace $id $item {Poster object properties changed}
    set state(posterPropertyItem) $item
    if {[dict get $item presentation] eq {table}} {printStudioItemSelected}
}
proc ::GX::printStudioPosterReplace {id replacement description} {
    variable ::GX::PrintStudio::state
    set items {};foreach item [dict get $state(recipe) items] {lappend items [expr {[dict get $item id] eq $id ? $replacement : $item}]}
    set recipe $state(recipe);dict set recipe items $items;printStudioEdit $recipe $description
}
proc ::GX::printStudioPosterAfterEdit {} {
    variable ::GX::PrintStudio::state
    set state(posterReview) 0;set state(posterGesture) {}
    if {$state(posterSelection) ne {} && [catch {printStudioPosterItem $state(posterSelection)}]} {set state(posterSelection) {}}
    if {[printStudioIsPoster]} {printStudioPosterDraw}
}
proc ::GX::printStudioPosterPhotos {result} {
    variable ::GX::PrintStudio::state
    foreach key [array names state objectPhoto,*] {catch {image delete $state($key)};unset state($key)}
    foreach key [array names state objectContent,*] {unset state($key)}
    foreach object [datasetPublicationV2DictDefault $result objects {}] {
        set id [dict get $object id]
        set state(objectPhoto,$id) [image create photo -file [dict get $object path]]
        foreach item [dict get $state(document) recipe items] {if {[dict get $item id] eq $id} {dict unset item frame;set state(objectContent,$id) [printRecipeAssetIdentity $item];break}}
    }
    unset -nocomplain state(objectKey)
}
proc ::GX::printStudioPosterObjectRequest {key objects} {
    variable ::GX::PrintStudio::state
    unset -nocomplain state(objectTimer)
    if {![info exists state(objectKey)] || $state(objectKey) ne $key || ![info exists state(document)]} return
    if {[info exists state(objectRequest)]} {set state(objectPending) [list $key $objects];printDocumentCancel $state(objectRequest);return}
    set state(objectPending) {}
    set state(objectRequest) [printDocumentRequest object_preview [dict merge [printStudioDocumentArguments] [dict create objects $objects]] [list ::GX::printStudioPosterObjectsPrepared $key]]
}
proc ::GX::printStudioPosterObjectsPrepared {key response} {
    variable ::GX::PrintStudio::state
    unset -nocomplain state(objectRequest)
    if {[info exists state(objectPending)] && $state(objectPending) ne {}} {
        if {[dict get $response ok]} {printDocumentRelease [dict get $response result resource_id]}
        lassign $state(objectPending) next objects;set state(objectPending) {}
        printStudioPosterObjectRequest $next $objects;return
    }
    if {![info exists state(document)] || ![info exists state(objectKey)] || $state(objectKey) ne $key} {if {[dict get $response ok]} {printDocumentRelease [dict get $response result resource_id]};return}
    if {![dict get $response ok]} {set ::GX::ui(printStatus) "Prepared object scaling unavailable: [dict get $response error]";return}
    set result [dict get $response result]
    try {
        foreach object [dict get $result objects] {
            set id [dict get $object id]
            set photo [image create photo -file [dict get $object path]]
            if {[info exists state(objectPhoto,$id)]} {image delete $state(objectPhoto,$id)}
            set state(objectPhoto,$id) $photo
        }
        # Inert provenance for the current display; native tokens are not saved.
        set state(objectProjection) [dict create pdf_sha256 [dict get $result pdf_sha256] projection [dict get $result projection] objects [dict get $result objects]]
    } finally {printDocumentRelease [dict get $result resource_id]}
    printStudioPosterDraw
}
proc ::GX::printStudioPosterDraw {} {
    variable ::GX::PrintStudio::state;variable ui
    if {![printStudioIsPoster] || $state(posterReview) || ![info exists ui(printPageCanvas)] || ![winfo exists $ui(printPageCanvas)]} return
    set canvas $ui(printPageCanvas);set page [dict get $state(recipe) page];lassign [printRecipePageSize $page] w h
    set width [printStudioPagePixelWidth $canvas [expr {$w*72/25.4}] [expr {$h*72/25.4}]]
    set scale [expr {double($width)/$w}]
    set state(posterScale) $scale;set state(posterLeft) [expr {max(16,([winfo width $canvas]-$width)/2)}];set state(posterTop) 16
    set left $state(posterLeft);set top $state(posterTop)
    $canvas delete all
    $canvas create rectangle $left $top [expr {$left+$width}] [expr {$top+$h*$scale}] -fill [datasetPublicationV2DictDefault $page background #ffffff] -outline #303c48 -tags paper
    set columns [dict get $page columns];set margin [dict get $page margin_mm];set gap [dict get $page gap_mm]
    for {set column 1} {$column<$columns} {incr column} {
        set x [expr {$left+($margin+$column*($w-2*$margin+$gap)/$columns-$gap/2)*$scale}]
        $canvas create line $x [expr {$top+$margin*$scale}] $x [expr {$top+($h-$margin)*$scale}] -fill #c2cbd5 -dash {3 5} -tags guide
    }
    set pages 1;set projections {}
    foreach item [dict get $state(recipe) items] {
        set frame [dict get $item frame];set id [dict get $item id];set pages [expr {max($pages,[dict get $frame page])}]
        if {[dict get $frame page]!=$state(currentPage)} continue
        set x [expr {$left+[dict get $frame x_mm]*$scale}];set y [expr {$top+[dict get $frame y_mm]*$scale}]
        set right [expr {$x+[dict get $frame width_mm]*$scale}];set bottom [expr {$y+[dict get $frame height_mm]*$scale}]
        set tags [list object object:$id]
        set style [datasetPublicationV2DictDefault $item style {}]
        $canvas create rectangle $x $y $right $bottom -fill [datasetPublicationV2DictDefault $style background #edf2f7] -outline #a3afbc -tags $tags
        set content $item;dict unset content frame
        set retained [expr {[info exists state(objectContent,$id)] && $state(objectContent,$id) eq [printRecipeAssetIdentity $content]}]
        if {$retained && [info exists state(objectPhoto,$id)]} {
            $canvas create image $x $y -anchor nw -image $state(objectPhoto,$id) -tags $tags
            if {abs([image width $state(objectPhoto,$id)]-($right-$x))>=2 || abs([image height $state(objectPhoto,$id)]-($bottom-$y))>=2} {lappend projections [dict create id $id width [expr {max(1,round($right-$x))}] height [expr {max(1,round($bottom-$y))}]]}
        } else {
            $canvas create text [expr {$x+5}] [expr {$y+5}] -anchor nw -width [expr {max(1,$right-$x-10)}] -font TkSmallCaptionFont -fill #23364b -text "[dict get $item presentation] · [dict get $item caption]\nUpdate Preview to prepare exact content" -tags $tags
        }
        if {$id eq $state(posterSelection)} {
            $canvas create rectangle $x $y $right $bottom -outline #0064b5 -width 2 -dash {6 3} -tags [list selection object:$id]
            foreach {corner hx hy} [list nw $x $y ne $right $y sw $x $bottom se $right $bottom] {$canvas create rectangle [expr {$hx-4}] [expr {$hy-4}] [expr {$hx+4}] [expr {$hy+4}] -fill white -outline #004b8a -width 2 -tags [list handle handle:$corner object:$id]}
        }
    }
    # Selection controls own the pick priority, including Tk's tolerant hits
    # near a later object's edge. Keep them above every document object.
    $canvas raise selection
    $canvas raise handle
    if {$projections ne {} && [info exists state(document)]} {
        set key [list [interactiveDocumentSessionToken] [dict get $state(document) pdf_sha256] $state(currentPage) $projections]
        if {![info exists state(objectKey)] || $state(objectKey) ne $key} {
            set state(objectKey) $key
            if {[info exists state(objectTimer)]} {after cancel $state(objectTimer)}
            set state(objectTimer) [after idle [list ::GX::printStudioPosterObjectRequest $key $projections]]
        }
    }
    set state(pageCount) $pages;$ui(printPageNumber) configure -to $pages
    $canvas configure -scrollregion [list 0 0 [expr {max([winfo width $canvas],$left+$width+16)}] [expr {$top+$h*$scale+16}]]
}
proc ::GX::printStudioPosterPress {x y} {
    variable ::GX::PrintStudio::state;variable ui
    set canvas $ui(printPageCanvas);focus $canvas
    if {![printStudioIsPoster] || $state(posterReview)} {$canvas scan mark $x $y;set state(posterGesture) {mode pan};return}
    set hit [$canvas find withtag current];set id {};set corner {}
    if {$hit ne {}} {foreach tag [$canvas gettags $hit] {if {[string match object:* $tag]} {set id [string range $tag 7 end]};if {[string match handle:* $tag]} {set corner [string range $tag 7 end]}}}
    set state(posterSelection) $id
    if {$id eq {}} {set state(posterGesture) {};printStudioPosterDraw;return}
    $ui(printQueue) selection set $id;printStudioItemSelected
    set item [printStudioPosterItem $id]
    set state(posterGesture) [dict create mode [expr {$corner eq {} ? {move} : {resize}}] corner $corner id $id original $item candidate [dict get $item frame] x [$canvas canvasx $x] y [$canvas canvasy $y] revision $state(revision) token [interactiveDocumentSessionToken] last_x 0 last_y 0]
    printStudioPosterDraw
}
proc ::GX::printStudioPosterMotion {x y} {
    variable ::GX::PrintStudio::state;variable ui
    if {$state(posterGesture) eq {}} return
    set canvas $ui(printPageCanvas);set g $state(posterGesture)
    if {[dict get $g mode] eq {pan}} {$canvas scan dragto $x $y 1;return}
    set dx [expr {([$canvas canvasx $x]-[dict get $g x])/$state(posterScale)}];set dy [expr {([$canvas canvasy $y]-[dict get $g y])/$state(posterScale)}]
    set f [dict get $g original frame];set next $f
    if {[dict get $g mode] eq {move}} {
        dict set next x_mm [expr {[dict get $f x_mm]+$dx}];dict set next y_mm [expr {[dict get $f y_mm]+$dy}]
        $canvas move object:[dict get $g id] [expr {($dx-[dict get $g last_x])*$state(posterScale)}] [expr {($dy-[dict get $g last_y])*$state(posterScale)}]
    } else {
        set corner [dict get $g corner]
        foreach axis {x y} amount [list $dx $dy] size {width_mm height_mm} low {w n} {
            set key ${axis}_mm;set a [dict get $f $key];set length [dict get $f $size]
            if {[string first $low $corner]>=0} {dict set next $key [expr {$a+$amount}];dict set next $size [expr {$length-$amount}]} else {dict set next $size [expr {$length+$amount}]}
        }
        $canvas delete provisional
        set px [expr {$state(posterLeft)+[dict get $next x_mm]*$state(posterScale)}];set py [expr {$state(posterTop)+[dict get $next y_mm]*$state(posterScale)}]
        $canvas create rectangle $px $py [expr {$px+[dict get $next width_mm]*$state(posterScale)}] [expr {$py+[dict get $next height_mm]*$state(posterScale)}] -outline #0064b5 -width 3 -dash {4 3} -tags provisional
    }
    dict set g candidate $next;dict set g last_x $dx;dict set g last_y $dy;set state(posterGesture) $g
    set ::GX::ui(printStatus) "Provisional [dict get $g mode] · X [format %.1f [dict get $next x_mm]] / Y [format %.1f [dict get $next y_mm]] mm · [format %.1f [dict get $next width_mm]] × [format %.1f [dict get $next height_mm]] mm · release to commit, Escape to cancel"
}
proc ::GX::printStudioPosterRelease {} {
    variable ::GX::PrintStudio::state
    if {$state(posterGesture) eq {}} return
    set g $state(posterGesture);set state(posterGesture) {}
    if {[dict get $g mode] eq {pan}} return
    if {[catch {
        if {$state(revision)!=[dict get $g revision] || [interactiveDocumentSessionToken] ne [dict get $g token]} {error {Composition changed during the gesture; no edit committed.}}
        set item [dict get $g original];dict set item frame [dict get $g candidate]
        printStudioPosterReplace [dict get $g id] $item "Poster object [dict get $g mode]"
    } message]} {set ::GX::ui(printStatus) $message}
    printStudioPosterDraw
}
proc ::GX::printStudioPosterEscape {} {set ::GX::PrintStudio::state(posterGesture) {};printStudioPosterDraw;set ::GX::ui(printStatus) {Provisional layout gesture cancelled; recipe unchanged.}}
proc ::GX::printStudioPosterReview {review} {
    variable ::GX::PrintStudio::state
    if {$review && ![printStudioDocumentReady]} {error {Update Preview before reviewing the current PDF.}}
    set state(posterReview) $review
    if {$review} {unset -nocomplain state(pageKey);printStudioPageRequest} else {printStudioPosterDraw}
}
