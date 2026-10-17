# Scientific Image Inspector — article figure composition and safe annotation layer.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII {variable figureFormatVersion 2}
proc ::GX::SII::figureValidInt {value low high name} {
    if {![string is integer -strict $value] || $value<$low || $value>$high} {error "$name must be an integer between $low and $high"}
    return $value
}
proc ::GX::SII::figureColor {color} {
    if {![regexp {^#[0-9a-fA-F]{6}$} $color]} {error {Color must use #RRGGBB notation}}
    return $color
}
proc ::GX::SII::figureText {text} {
    # Magick interprets percent escapes, @file payloads and escaped draw clauses.
    # Permit ordinary Unicode text, excluding the CLI-specific expansion/control syntax.
    if {[string length $text] > 256 || [regexp {[%@\\\r\n\x00]} $text]} {
        error {Annotation text is limited to 256 characters without %, @, backslashes or control characters}
    }
    return $text
}
proc ::GX::SII::validateAnnotation {a width height} {
    if {[catch {dict size $a}]} {error {Invalid annotation dictionary}}
    set kind [get $a kind ""]
    if {$kind ni {text line arrow rectangle ellipse}} {error {Unsupported annotation type}}
    set result [dict create kind $kind]
    foreach key {x1 y1} {
        set v [get $a $key ""]
        dict set result $key [figureValidInt $v 0 [expr {$key eq "x1" ? $width : $height}] $key]
    }
    if {$kind ne "text"} {
        foreach key {x2 y2} {
            set v [get $a $key ""]
            dict set result $key [figureValidInt $v 0 [expr {$key eq "x2" ? $width : $height}] $key]
        }
        # Native2D sketch_create rejects zero-length lines/arrow shafts and
        # rectangles without positive area. Validate BEFORE the Workspace or
        # History is mutated; old invalid Workspace records remain preserved
        # but are safely excluded from presentation until explicitly edited.
        set x1 [dict get $result x1];set y1 [dict get $result y1]
        set x2 [dict get $result x2];set y2 [dict get $result y2]
        if {$kind in {line arrow} && $x1==$x2 && $y1==$y2} {
            error "Cannot create $kind: drag to a different endpoint (zero-length lines are invalid in Native2D)."
        }
        if {$kind eq "rectangle" && ($x1==$x2 || $y1==$y2)} {
            error {Cannot create rectangle: both width and height must be nonzero.}
        }
    }
    dict set result color [figureColor [get $a color #FFCC00]]
    dict set result stroke [figureValidInt [get $a stroke 4] 1 40 Stroke]
    if {$kind eq "text"} {
        dict set result text [figureText [get $a text A]]
        dict set result size [figureValidInt [get $a size 46] 8 1200 {Font size}]
        set family [get $a font_family DejaVu-Sans]
        if {![regexp {^[a-zA-Z0-9 _.-]{1,90}$} $family]} {error {Invalid font family}}
        dict set result font_family $family
        set unit [get $a font_unit px]
        if {$unit ni {px pt}} {error {Font unit must be px or pt}}
        dict set result font_unit $unit
        set displaySize [get $a font_value [dict get $result size]]
        if {![string is double -strict $displaySize] || $displaySize<1 || $displaySize>1200} {error {Font display size out of bounds}}
        dict set result font_value $displaySize
        if {[dict exists $a font_dpi]} {
            dict set result font_dpi [figureValidInt [dict get $a font_dpi] 36 2400 {Font rendering DPI}]
        }
        foreach dim {box_width box_height} {
            if {[dict exists $a $dim]} {dict set result $dim [figureValidInt [dict get $a $dim] 1 12000 $dim]}
        }
    }
    set angle [get $a rotation 0]
    if {![string is double -strict $angle] || ![expr {abs(double($angle))<=3600}]} {error {Invalid annotation rotation}}
    dict set result rotation [expr {double($angle)}]
    if {[dict exists $a pivot_x] != [dict exists $a pivot_y]} {
        error {Annotation pivot requires both x and y coordinates}
    }
    foreach {key bound} [list pivot_x $width pivot_y $height] {
        set v [get $a $key {}]
        if {$v eq {}} continue
        if {![string is double -strict $v] || ![expr {double($v)>=0 && double($v)<=$bound}]} {error "Invalid $key"}
        dict set result $key [expr {double($v)}]
    }
    # User-facing stable names are distinct from immutable object identifiers.
    set name [get $a name {}]
    if {$name ne {}} {
        if {[string length $name] > 100 || [regexp {[\r\n\x00]} $name]} {error {Annotation name must be a single line of at most 100 characters}}
        dict set result name $name
    }
    if {[dict exists $a id]} {
        if {![regexp {^ann[0-9]+$} [dict get $a id]]} {error {Invalid annotation ID}}
        dict set result id [dict get $a id]
    }
    return $result
}
# Image-space clockwise rotation. Native2D owns retained affine geometry;
# the image recipe retains just the angle and pivot, not display samples.
proc ::GX::SII::annotationPivot {a} {
    if {[dict exists $a pivot_x] && [dict exists $a pivot_y]} {
        return [list [dict get $a pivot_x] [dict get $a pivot_y]]
    }
    if {[dict get $a kind] eq "text"} {return [list [dict get $a x1] [dict get $a y1]]}
    return [list [expr {([dict get $a x1]+[dict get $a x2])/2.0}] [expr {([dict get $a y1]+[dict get $a y2])/2.0}]]
}
proc ::GX::SII::annotationTransformPoint {a x y} {
    lassign [annotationPivot $a] px py
    set rad [expr {double([get $a rotation 0])*acos(-1)/180.0}]
    set cs [expr {cos($rad)}];set sn [expr {sin($rad)}]
    return [list [expr {$px+$cs*($x-$px)-$sn*($y-$py)}] [expr {$py+$sn*($x-$px)+$cs*($y-$py)}]]
}
proc ::GX::SII::annotationInversePoint {a x y} {
    lassign [annotationPivot $a] px py
    set rad [expr {-double([get $a rotation 0])*acos(-1)/180.0}]
    set cs [expr {cos($rad)}];set sn [expr {sin($rad)}]
    return [list [expr {$px+$cs*($x-$px)-$sn*($y-$py)}] [expr {$py+$sn*($x-$px)+$cs*($y-$py)}]]
}
proc ::GX::SII::annotationNativeMatrix {a height} {
    # Image origin is top-left; Native2D world origin is bottom-left.
    lassign [annotationPivot $a] px py
    set py [expr {$height-$py}]
    set rad [expr {-double([get $a rotation 0])*acos(-1)/180.0}]
    set cs [expr {cos($rad)}];set sn [expr {sin($rad)}]
    return [list $cs [expr {-$sn}] $sn $cs \
        [expr {$px-$cs*$px+$sn*$py}] [expr {$py-$sn*$px-$cs*$py}]]
}
proc ::GX::SII::figurePlan {panels width height margin gutter layout} {
    figureValidInt $width 120 12000 Width
    figureValidInt $height 120 12000 Height
    figureValidInt $margin 0 1000 Margin
    figureValidInt $gutter 0 1000 Gutter
    if {[llength $panels] < 1 || [llength $panels] > 12} {error {Figure supports between 1 and 12 panels}}
    set count [llength $panels]
    switch -- $layout {
        horizontal {set columns $count}
        vertical {set columns 1}
        grid {set columns [expr {int(ceil(sqrt($count)))}]}
        default {error {Figure layout must be horizontal, vertical or grid}}
    }
    set rows [expr {int(ceil(double($count)/$columns))}]
    set cellw [expr {int(floor(double($width - 2*$margin - ($columns-1)*$gutter)/$columns))}]
    set cellh [expr {int(floor(double($height - 2*$margin - ($rows-1)*$gutter)/$rows))}]
    if {$cellw < 24 || $cellh < 24} {error {Margins and gutters leave insufficient panel area}}
    set out {};set index 0
    foreach p $panels {
        set col [expr {$index%$columns}];set row [expr {$index/$columns}]
        lappend out [dict create panel $p index $index x [expr {$margin+$col*($cellw+$gutter)}] y [expr {$margin+$row*($cellh+$gutter)}] width $cellw height $cellh]
        incr index
    }
    return $out
}
proc ::GX::SII::figureVerifyPanels {panels} {
    set checked {}
    foreach p $panels {
        set id [get $p source_id ""]
        set source [sourceInfo $id]
        if {[get $p source_sha ""] ne [dict get $source sha256]} {error "Source image $id has changed since it was added"}
        lappend checked [dict create source_id $id source_sha [dict get $source sha256] steps [validateSteps [get $p steps {}]]]
    }
    return $checked
}
proc ::GX::SII::figureCreate {panels settings annotations output {format png16}} {
    set panels [figureVerifyPanels $panels]
    set w [figureValidInt [get $settings width 2400] 120 12000 Width]
    set h [figureValidInt [get $settings height 1600] 120 12000 Height]
    if {wide($w)*wide($h)>80000000} {error {Figure export limited to 80 megapixels}}
    set margin [figureValidInt [get $settings margin 32] 0 1000 Margin]
    set gutter [figureValidInt [get $settings gutter 24] 0 1000 Gutter]
    set layout [get $settings layout grid]
    set background [figureColor [get $settings background #FFFFFF]]
    if {$format ni {png16 tiff16 tiff32f png8 jpeg webp}} {error {Unsupported figure export format}}
    set plan [figurePlan $panels $w $h $margin $gutter $layout]
    set overlay {}
    foreach a $annotations {lappend overlay [validateAnnotation $a $w $h]}
    set tmpfiles {}
    try {
        set base [tempFile .miff];lappend tmpfiles $base
        run [list [magickPath] {*}[limits] -size ${w}x${h} xc:$background -depth 16 MIFF:$base] 35000
        foreach slot $plan {
            set p [dict get $slot panel]
            set source [sourceInfo [dict get $p source_id]]
            set processed [tempFile .miff];lappend tmpfiles $processed
            processFile [dict get $source path] [dict get $p steps] $processed miff
            set placed [tempFile .miff];lappend tmpfiles $placed
            set cw [dict get $slot width];set ch [dict get $slot height]
            # Resize inside panel box; dimensions/offsets use actual bounded ImageMagick output.
            run [list [magickPath] {*}[limits] MIFF:$processed -resize ${cw}x${ch} -depth 16 MIFF:$placed] 35000
            set dims [inspectFile $placed]
            set px [expr {[dict get $slot x]+int(($cw-[dict get $dims width])/2)}]
            set py [expr {[dict get $slot y]+int(($ch-[dict get $dims height])/2)}]
            set merged [tempFile .miff];lappend tmpfiles $merged
            run [list [magickPath] {*}[limits] MIFF:$base MIFF:$placed -gravity northwest -geometry +${px}+${py} -compose Over -composite MIFF:$merged] 35000
            foreach previous [list $base $processed $placed] {catch {file delete -- $previous}}
            set base $merged
        }
        # Build one controlled draw command per shape; never accept arbitrary MVG strings.
        foreach a $overlay {
            set kind [dict get $a kind];set color [dict get $a color];set stroke [dict get $a stroke]
            set x [dict get $a x1];set y [dict get $a y1]
            set merged [tempFile .miff];lappend tmpfiles $merged
            if {$kind eq "text"} {
                lassign [annotationTransformPoint $a $x $y] tx ty
                set angle [get $a rotation 0]
                # ImageMagick -annotate rotates glyphs about their placement;
                # rotating the anchor first implements a user-defined pivot.
                set argv [list [magickPath] {*}[limits] MIFF:$base -fill $color -stroke none -font [get $a font_family {DejaVu-Sans}] -pointsize [dict get $a size] -gravity northwest -annotate "${angle}x${angle}+[expr {round($tx)}]+[expr {round($ty)}]" [dict get $a text] MIFF:$merged]
            } else {
                set x2 [dict get $a x2];set y2 [dict get $a y2]
                set command ""
                switch -- $kind {
                    line - arrow {
                        set command "line $x,$y $x2,$y2"
                        if {$kind eq "arrow"} {
                            set angle [expr {atan2($y2-$y,$x2-$x)}];set wing [expr {max(9,4*$stroke)}]
                            set a1 [expr {$angle+2.65}];set a2 [expr {$angle-2.65}]
                            append command " line $x2,$y2 [expr {round($x2+$wing*cos($a1))}],[expr {round($y2+$wing*sin($a1))}]"
                            append command " line $x2,$y2 [expr {round($x2+$wing*cos($a2))}],[expr {round($y2+$wing*sin($a2))}]"
                        }
                    }
                    rectangle {set command "rectangle $x,$y $x2,$y2"}
                    ellipse {
                        set cx [expr {($x+$x2)/2.0}];set cy [expr {($y+$y2)/2.0}]
                        set rx [expr {max(1,abs($x2-$x)/2.0)}];set ry [expr {max(1,abs($y2-$y)/2.0)}]
                        set command "ellipse $cx,$cy $rx,$ry 0,360"
                    }
                }
                set angle [get $a rotation 0]
                if {$angle!=0} {
                    lassign [annotationPivot $a] px py
                    # Trusted geometry operands; command never contains user text.
                    set command "push graphic-context translate $px,$py rotate $angle translate -$px,-$py $command pop graphic-context"
                }
                set argv [list [magickPath] {*}[limits] MIFF:$base -fill none -stroke $color -strokewidth $stroke -draw $command MIFF:$merged]
            }
            run $argv 35000
            catch {file delete -- $base}
            set base $merged
        }
        set args {}
        switch -- $format {
            png16 {set args [list -depth 16 PNG:$output]}
            tiff16 {set args [list -depth 16 -compress Zip TIFF:$output]}
            tiff32f {set args [list -define quantum:format=floating-point -depth 32 -compress Zip TIFF:$output]}
            png8 {set args [list -depth 8 PNG:$output]}
            jpeg {set args [list -background $background -alpha remove -alpha off -quality 90 -depth 8 JPEG:$output]}
            webp {set args [list -background $background -alpha remove -alpha off -quality 88 -depth 8 WEBP:$output]}
        }
        run [list [magickPath] {*}[limits] MIFF:$base {*}$args] 35000
        if {![file isfile $output] || [file size $output]<1} {error {Figure renderer produced no output}}
        return [dict create output $output width $w height $h format $format panel_count [llength $panels] annotation_count [llength $annotations]]
    } finally {foreach p $tmpfiles {catch {file delete -- $p}}}
}
proc ::GX::SII::figurePublish {panels settings annotations outputId {format png16} {manifest {}}} {
    set output [tempFile [expr {$format eq "png16" ? ".png" : ".tif"}]]
    try {
        figureCreate $panels $settings $annotations $output $format
        set sources {};set shas {}
        foreach panel [figureVerifyPanels $panels] {
            lappend sources [dict get $panel source_id]
            dict set shas [dict get $panel source_id] [dict get $panel source_sha]
        }
        set sources [lsort -unique $sources]
        if {$manifest eq {}} {set manifest [makeManifest [dict get [lindex $panels 0] source_id] {} $panels $settings $annotations $format {}]}
        dict set manifest output dataset_id $outputId
        dict set manifest output expected_sha256 [::GX::sha256File $output]
        dict set manifest output raster_properties [inspectFile $output]
        manifestValidate $manifest
        set request [dict create dataset_id $outputId contract image.raster \
            format [expr {$format eq "png16" ? "png" : "tiff"}] \
            source_file $output storage_kind binary \
            media_type [expr {$format eq "png16" ? "image/png" : "image/tiff"}] \
            source_dataset_ids $sources provenance {Scientific Image Inspector article figure; non-destructive composition} \
            structured_metadata [dict create image.editor scientific_image_inspector image.source_sha256_map $shas image.panels $panels image.figure_settings $settings image.annotations $annotations image.engine [magickVersion] image.inspector.manifest $manifest image.inspector.manifest_schema scientific_image_inspector.manifest.v1]]
        return [::GX::datasetFilePublicationPublish [::GX::sessionInspectionCurrentSession] $::GX::SII::moduleId $request]
    } finally {catch {file delete -- $output}}
}
