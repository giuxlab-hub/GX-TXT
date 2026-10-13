# GX-TXT Plot Annotation API v1
# SPDX-License-Identifier: GPL-3.0-or-later
# Non-destructive plot annotations stored as UTF-8 JSON overlays.

namespace eval ::GX {
    variable annotationApiVersion 1
    variable annObjects {}
    variable annSelected -1
    variable annTool select
    variable annPlotPath ""
    variable annJsonPath ""
    variable annDirty 0
    variable annUndo {}
    variable annRedo {}
    variable annDragStart {}
    variable annDragObject {}
    variable annDragIndex -1
    variable annNextId 1
    variable annDpi 200
    variable annotationPrintOverridePaths {}
    variable annotationPrintOverrideActive 0
}

proc ::GX::annotationBridgePath {} { variable scriptDir; return [file join $scriptDir services annotations plot_annotation_bridge.py] }
proc ::GX::annotationRendererPath {} { variable scriptDir; return [file join $scriptDir services annotations plot_annotation_renderer.py] }

proc ::GX::annotationB64Encode {s} {
    set raw [encoding convertto utf-8 $s]
    return [string map [list "\n" "" "\r" ""] [binary encode base64 $raw]]
}
proc ::GX::annotationB64Decode {s} { return [encoding convertfrom utf-8 [binary decode base64 $s]] }

proc ::GX::annotationPathForPlot {plotPath} {
    set d [file join [file dirname $plotPath] annotations]
    set stem [file rootname [file tail $plotPath]]
    return [file join $d "${stem}.json"]
}

proc ::GX::graphSupportsAnnotations {path} {
    set native [nativeGraphInfoForPath $path]
    if {[llength $native] != 2} { return 0 }
    lassign $native moduleId graph
    set enabled [string tolower [string trim [moduleGraphField $moduleId $graph supports_annotations "0"]]]
    set editor [string tolower [string trim [moduleGraphField $moduleId $graph annotation_editor "none"]]]
    return [expr {$enabled in {1 true yes on} && $editor ne "none"}]
}

proc ::GX::annotationImageDimensions {path} {
    if {![file isfile $path]} { return {0 0} }
    set code {from PIL import Image; import sys; im=Image.open(sys.argv[1]); print("%d %d" % im.size)}
    if {[catch {exec [runtimeToolRequired python] -c $code $path} out]} { return {0 0} }
    set parts [split [string trim $out]]
    if {[llength $parts] != 2} { return {0 0} }
    return $parts
}

proc ::GX::annotationDefaultObject {type id} {
    set common [dict create id $id type $type visible 1 locked 0 z_index 0 space figure_norm]
    switch -- $type {
        text {
            return [dict merge $common [dict create x 0.5 y 0.5 text "Label" font_family sans font_size 12 font_unit pt bold 0 italic 0 color #000000 rotation_deg 0 h_align left v_align middle background "" border 0]]
        }
        line {
            return [dict merge $common [dict create x1 0.35 y1 0.5 x2 0.65 y2 0.5 stroke #000000 stroke_width 1.5 stroke_unit px dash solid]]
        }
        arrow {
            return [dict merge $common [dict create x1 0.35 y1 0.5 x2 0.65 y2 0.5 stroke #000000 stroke_width 1.5 stroke_unit px dash solid head triangle]]
        }
        rectangle - ellipse {
            return [dict merge $common [dict create x1 0.35 y1 0.35 x2 0.65 y2 0.65 stroke #000000 stroke_width 1.5 stroke_unit px dash solid fill "" fill_opacity 0]]
        }
        default { error "Unsupported annotation type: $type" }
    }
}

proc ::GX::annotationNormalizeObject {obj idx} {
    set type [expr {[dict exists $obj type] ? [dict get $obj type] : "text"}]
    set id [expr {[dict exists $obj id] && [string trim [dict get $obj id]] ne "" ? [dict get $obj id] : "${type}_[format %03d [expr {$idx+1}]]"}]
    set def [annotationDefaultObject $type $id]
    return [dict merge $def $obj]
}

proc ::GX::annotationLoadDocument {plotPath} {
    set json [annotationPathForPlot $plotPath]
    set native [nativeGraphInfoForPath $plotPath]
    set graph [expr {[llength $native] == 2 ? [lindex $native 1] : [graphKeyForPath $plotPath]}]
    set meta [dict create annotation_api_version 1 plot_id $graph base_plot [file tail $plotPath] enabled 1 width_px 0 height_px 0 dpi 200]
    set objects {}
    if {![file isfile $json]} {
        lassign [annotationImageDimensions $plotPath] iw ih
        dict set meta width_px $iw; dict set meta height_px $ih
        return [dict create meta $meta objects $objects path $json]
    }
    set bridge [annotationBridgePath]
    if {[catch {exec [runtimeToolRequired python] $bridge read $json} out]} { error "Cannot read annotation JSON: $out" }
    set objmap [dict create]
    foreach line [split $out "\n"] {
        if {$line eq ""} continue
        set p [split $line "\t"]
        if {[llength $p] < 3} continue
        if {[lindex $p 0] eq "META" && [llength $p] >= 3} {
            dict set meta [lindex $p 1] [annotationB64Decode [lindex $p 2]]
        } elseif {[lindex $p 0] eq "OBJ" && [llength $p] >= 4} {
            set idx [lindex $p 1]
            dict set objmap $idx [lindex $p 2] [annotationB64Decode [lindex $p 3]]
        }
    }
    foreach idx [lsort -integer [dict keys $objmap]] {
        lappend objects [annotationNormalizeObject [dict get $objmap $idx] $idx]
    }
    if {![dict exists $meta width_px] || ![string is double -strict [dict get $meta width_px]] || [dict get $meta width_px] <= 0 || ![dict exists $meta height_px] || ![string is double -strict [dict get $meta height_px]] || [dict get $meta height_px] <= 0} {
        lassign [annotationImageDimensions $plotPath] iw ih
        dict set meta width_px $iw; dict set meta height_px $ih
    }
    return [dict create meta $meta objects $objects path $json]
}

proc ::GX::annotationWriteTsv {path meta objects} {
    set fd [open $path w]
    fconfigure $fd -encoding utf-8 -translation lf
    foreach key {annotation_api_version plot_id base_plot enabled width_px height_px dpi} {
        set v [expr {[dict exists $meta $key] ? [dict get $meta $key] : ""}]
        puts $fd "META\t$key\t[annotationB64Encode $v]"
    }
    set i 0
    foreach obj $objects {
        foreach key [lsort [dict keys $obj]] {
            puts $fd "OBJ\t$i\t$key\t[annotationB64Encode [dict get $obj $key]]"
        }
        incr i
    }
    close $fd
}

proc ::GX::annotationSaveDocument {plotPath objects {enabled 1}} {
    variable cfg
    variable currentSession
    set json [annotationPathForPlot $plotPath]
    file mkdir [file dirname $json]
    lassign [annotationImageDimensions $plotPath] iw ih
    set native [nativeGraphInfoForPath $plotPath]
    set graph [expr {[llength $native] == 2 ? [lindex $native 1] : [graphKeyForPath $plotPath]}]
    set dpi [expr {[info exists cfg(analysis_png_dpi)] && [string is integer -strict $cfg(analysis_png_dpi)] ? $cfg(analysis_png_dpi) : 200}]
    set meta [dict create annotation_api_version 1 plot_id $graph base_plot [file tail $plotPath] enabled $enabled width_px $iw height_px $ih dpi $dpi]
    set tsv "${json}.tsv.[pid]"
    annotationWriteTsv $tsv $meta $objects
    set bridge [annotationBridgePath]
    if {[catch {exec [runtimeToolRequired python] $bridge write $tsv $json 2>@1} out]} {
        catch {file delete -force $tsv}
        error "Cannot save annotation JSON: $out"
    }
    catch {file delete -force $tsv}
    if {[catch {exec [runtimeToolRequired python] $bridge validate $json 2>@1} out]} { error "Annotation JSON validation failed: $out" }
    if {$currentSession ne ""} {
        set mf [file join $currentSession metadata manifest.ini]
        if {[file isdirectory [file dirname $mf]]} { catch {writeManifest $mf} }
    }
    return $json
}

# Public graph-addressed operations. Storage paths remain an implementation
# detail of the existing annotation service and current Session.
proc ::GX::plotAnnotationInfo {moduleId graphId {variantId ""}} {
    if {$::GX::currentSession eq ""} {error "Open a Session first"}
    graphAxisAddress $moduleId $graphId $variantId
    set supported [expr {[string tolower [moduleGraphField $moduleId $graphId supports_annotations 0]] in {1 true yes on}}]
    set editor [moduleGraphField $moduleId $graphId annotation_editor none]
    if {$editor eq "none"} {set supported 0}
    set types [splitList [moduleGraphField $moduleId $graphId annotation_types ""]]
    set spaces [splitList [moduleGraphField $moduleId $graphId annotation_coordinate_spaces ""]]
    return [dict create module_id $moduleId graph_id $graphId variant_id $variantId supported $supported editor $editor types $types coordinate_spaces $spaces]
}
proc ::GX::plotAnnotationTarget {moduleId graphId variantId {mutate 0}} {
    set info [plotAnnotationInfo $moduleId $graphId $variantId]
    if {$mutate && ![dict get $info supported]} {error "Graph does not declare annotation support"}
    set path [file normalize [graphAxisArtifactPath $moduleId $graphId $variantId]]
    set root [file normalize $::GX::currentSession]
    if {[string first "$root/" "$path/"] != 0} {error "Graph artifact is outside the current Session"}
    return $path
}
proc ::GX::plotAnnotationRead {moduleId graphId {variantId ""}} {
    set doc [annotationLoadDocument [plotAnnotationTarget $moduleId $graphId $variantId]]
    dict unset doc path
    return $doc
}
proc ::GX::plotAnnotationValidate {moduleId graphId variantId objects} {
    set info [plotAnnotationInfo $moduleId $graphId $variantId]
    if {![dict get $info supported]} {error "Graph does not declare annotation support"}
    set seen [dict create];set normalized {}
    set index 0
    foreach object $objects {
        if {[catch {dict size $object}]} {error "Annotation object must be a dictionary"}
        set type [expr {[dict exists $object type] ? [dict get $object type] : ""}]
        if {$type ni [dict get $info types]} {error "Annotation type '$type' is not declared by this graph"}
        set space [expr {[dict exists $object space] ? [dict get $object space] : "figure_norm"}]
        if {$space ni [dict get $info coordinate_spaces]} {error "Annotation coordinate space '$space' is not declared by this graph"}
        set id [expr {[dict exists $object id] ? [string trim [dict get $object id]] : ""}]
        if {$id eq ""} {error "Annotation object ID is required"}
        if {![regexp {^[A-Za-z_][A-Za-z0-9_.-]*$} $id]} {error "Invalid annotation object ID '$id'"}
        if {[dict exists $seen $id]} {error "Duplicate annotation object ID '$id'"}
        dict set seen $id 1
        set defaults [annotationDefaultObject $type $id]
        foreach field [dict keys $object] {
            if {![dict exists $defaults $field]} {error "Unknown annotation field '$field'"}
            set value [dict get $object $field]
            if {$field in {x y x1 y1 x2 y2 z_index stroke_width font_size rotation_deg fill_opacity}} {
                if {![string is double -strict $value] || [catch {set number [expr {double($value)}]}] || abs($number) == Inf || $number != $number} {
                    error "Annotation $field must be finite numeric"
                }
            }
            if {$field in {visible locked bold italic border} && $value ni {0 1}} {error "Annotation $field must be 0 or 1"}
        }
        lappend normalized [dict merge $defaults $object [dict create id $id space $space]]
        incr index
    }
    return $normalized
}
proc ::GX::plotAnnotationReplace {moduleId graphId variantId objects} {
    set path [plotAnnotationTarget $moduleId $graphId $variantId 1]
    set checked [plotAnnotationValidate $moduleId $graphId $variantId $objects]
    set current [annotationLoadDocument $path]
    annotationSaveDocument $path $checked [dict get [dict get $current meta] enabled]
    return [plotAnnotationRead $moduleId $graphId $variantId]
}
proc ::GX::plotAnnotationAdd {moduleId graphId variantId object} {
    set current [plotAnnotationRead $moduleId $graphId $variantId]
    set objects [dict get $current objects]
    if {![dict exists $object id] || [string trim [dict get $object id]] eq ""} {
        set used [dict create]
        foreach row $objects {dict set used [dict get $row id] 1}
        set i 1
        while {[dict exists $used [format "a%06d" $i]]} {incr i}
        dict set object id [format "a%06d" $i]
    }
    lappend objects $object
    return [plotAnnotationReplace $moduleId $graphId $variantId $objects]
}
proc ::GX::plotAnnotationUpdate {moduleId graphId variantId annotationId changes} {
    if {[dict exists $changes id] && [dict get $changes id] ne $annotationId} {error "Annotation ID cannot change"}
    set objects [dict get [plotAnnotationRead $moduleId $graphId $variantId] objects]
    set found 0;set updated {}
    foreach object $objects {
        if {[dict get $object id] eq $annotationId} {set object [dict merge $object $changes];set found 1}
        lappend updated $object
    }
    if {!$found} {error "Unknown annotation ID '$annotationId'"}
    return [plotAnnotationReplace $moduleId $graphId $variantId $updated]
}
proc ::GX::plotAnnotationRemove {moduleId graphId variantId annotationId} {
    set objects [dict get [plotAnnotationRead $moduleId $graphId $variantId] objects]
    set found 0;set kept {}
    foreach object $objects {
        if {[dict get $object id] eq $annotationId} {set found 1;continue}
        lappend kept $object
    }
    if {!$found} {error "Unknown annotation ID '$annotationId'"}
    return [plotAnnotationReplace $moduleId $graphId $variantId $kept]
}
proc ::GX::plotAnnotationClear {moduleId graphId {variantId ""}} {
    return [plotAnnotationReplace $moduleId $graphId $variantId {}]
}
proc ::GX::plotAnnotationSetEnabled {moduleId graphId variantId enabled} {
    if {$enabled ni {0 1}} {error "Annotation enabled state must be 0 or 1"}
    set path [plotAnnotationTarget $moduleId $graphId $variantId 1]
    set doc [annotationLoadDocument $path]
    annotationSaveDocument $path [dict get $doc objects] $enabled
    return [plotAnnotationRead $moduleId $graphId $variantId]
}

proc ::GX::annotationManifestEntries {} {
    variable currentSession
    set out {}
    if {$currentSession eq "" || ![file isdirectory [file join $currentSession analysis]]} { return $out }
    foreach f [walkFiles [file join $currentSession analysis]] {
        if {![string equal -nocase [file extension $f] ".json"]} continue
        if {[file tail [file dirname $f]] ne "annotations"} continue
        if {[catch {set doc [annotationLoadDocument [file join [file dirname [file dirname $f]] "[file rootname [file tail $f]].png"]]}]} continue
        set meta [dict get $doc meta]
        set plot [file join [file dirname [file dirname $f]] [dict get $meta base_plot]]
        if {![file isfile $plot]} continue
        set relPlot [string range $plot [expr {[string length $currentSession]+1}] end]
        set relJson [string range $f [expr {[string length $currentSession]+1}] end]
        lappend out [dict create plot_id [dict get $meta plot_id] plot_path $relPlot file $relJson enabled [dict get $meta enabled] api_version 1]
    }
    return $out
}

proc ::GX::annotationRenderTo {plotPath outputPath} {
    set json [annotationPathForPlot $plotPath]
    if {![file isfile $json]} {
        file mkdir [file dirname $outputPath]
        file copy -force $plotPath $outputPath
        return $outputPath
    }
    set renderer [annotationRendererPath]
    if {[catch {exec [runtimeToolRequired python] $renderer --base $plotPath --annotations $json --output $outputPath 2>@1} out]} {
        error "Annotation compositor failed: $out"
    }
    return $outputPath
}

proc ::GX::annotationOutputForPrint {plotPath} {
    variable currentSession
    if {![file isfile [annotationPathForPlot $plotPath]]} { return $plotPath }
    set root [expr {$currentSession ne "" ? [file join $currentSession report annotated_print] : [file join [file dirname $plotPath] .annotated_print]}]
    set module [file tail [file dirname $plotPath]]
    set out [file join $root $module [file tail $plotPath]]
    annotationRenderTo $plotPath $out
    return $out
}

proc ::GX::annotationCanvasAnchor {h v} {
    set h [string tolower $h]; set v [string tolower $v]
    if {$v in {middle center}} { set vv "" } elseif {$v eq "top"} { set vv n } else { set vv s }
    if {$h eq "center"} { set hh "" } elseif {$h eq "right"} { set hh e } else { set hh w }
    set a "$vv$hh"
    if {$a eq ""} { set a center }
    return $a
}

proc ::GX::annotationTkDash {dash scale} {
    switch -- $dash {
        dashed { return [list [expr {max(2,int(6*$scale))}] [expr {max(2,int(4*$scale))}]] }
        dotted { return [list [expr {max(1,int(2*$scale))}] [expr {max(2,int(4*$scale))}]] }
        default { return {} }
    }
}

proc ::GX::annotationDrawObject {c obj idx ox oy iw ih baseW baseH dpi tagsPrefix} {
    if {![dict get $obj visible]} { return {} }
    set type [dict get $obj type]
    set sx [expr {$baseW > 0 ? $iw/double($baseW) : 1.0}]
    set sy [expr {$baseH > 0 ? $ih/double($baseH) : 1.0}]
    set scale [expr {min($sx,$sy)}]
    set tags [list annLayer "${tagsPrefix}${idx}"]
    proc ::GX::__annxy {x y ox oy iw ih} { return [list [expr {$ox+$x*$iw}] [expr {$oy+(1.0-$y)*$ih}]] }
    set ids {}
    if {$type eq "text"} {
        lassign [__annxy [dict get $obj x] [dict get $obj y] $ox $oy $iw $ih] x y
        set size [expr {double([dict get $obj font_size])}]
        if {[dict get $obj font_unit] eq "pt"} { set size [expr {$size*$dpi/72.0}] }
        set pix [expr {max(1,int(round($size*$scale)))}]
        set fam [dict get $obj font_family]
        set style {}
        if {[dict get $obj bold]} { lappend style bold }
        if {[dict get $obj italic]} { lappend style italic }
        set font [linsert $style 0 $fam [expr {-$pix}]]
        set anchor [annotationCanvasAnchor [dict get $obj h_align] [dict get $obj v_align]]
        set bg [dict get $obj background]
        set text [dict get $obj text]
        if {$bg ne ""} {
            # text first to obtain bbox, then background below it
            set tid [$c create text $x $y -text $text -fill [dict get $obj color] -font $font -anchor $anchor -angle [dict get $obj rotation_deg] -tags $tags]
            lappend ids $tid
            set bb [$c bbox $tid]
            if {[llength $bb] == 4} {
                set rid [$c create rectangle [expr {[lindex $bb 0]-2}] [expr {[lindex $bb 1]-2}] [expr {[lindex $bb 2]+2}] [expr {[lindex $bb 3]+2}] -fill $bg -outline [expr {[dict get $obj border] ? [dict get $obj color] : $bg}] -tags $tags]
                $c lower $rid $tid
                lappend ids $rid
            }
        } else {
            set tid [$c create text $x $y -text $text -fill [dict get $obj color] -font $font -anchor $anchor -angle [dict get $obj rotation_deg] -tags $tags]
            lappend ids $tid
        }
    } elseif {$type in {line arrow rectangle ellipse}} {
        lassign [__annxy [dict get $obj x1] [dict get $obj y1] $ox $oy $iw $ih] x1 y1
        lassign [__annxy [dict get $obj x2] [dict get $obj y2] $ox $oy $iw $ih] x2 y2
        set width [expr {double([dict get $obj stroke_width])}]
        if {[dict get $obj stroke_unit] eq "pt"} { set width [expr {$width*$dpi/72.0}] }
        set width [expr {max(1,int(round($width*$scale)))}]
        set dash [annotationTkDash [dict get $obj dash] $scale]
        set stroke [dict get $obj stroke]
        if {$type in {line arrow}} {
            set cmd [list $c create line $x1 $y1 $x2 $y2 -fill $stroke -width $width -tags $tags]
            if {[llength $dash]} { lappend cmd -dash $dash }
            if {$type eq "arrow" && [dict get $obj head] ne "none"} { lappend cmd -arrow last }
            lappend ids [uplevel #0 $cmd]
        } else {
            set fill ""
            if {[dict exists $obj fill] && [string trim [dict get $obj fill]] ne "" && double([dict get $obj fill_opacity]) > 0} { set fill [dict get $obj fill] }
            set cmd [list $c create [expr {$type eq "rectangle" ? "rectangle" : "oval"}] $x1 $y1 $x2 $y2 -outline $stroke -width $width -fill $fill -tags $tags]
            if {[llength $dash]} { lappend cmd -dash $dash }
            lappend ids [uplevel #0 $cmd]
        }
    }
    return $ids
}

proc ::GX::annotationSortedIndexPairs {objects} {
    set pairs {}; set i 0
    foreach obj $objects {
        set z [expr {[dict exists $obj z_index] && [string is integer -strict [dict get $obj z_index]] ? [dict get $obj z_index] : $i}]
        lappend pairs [list $z $i $obj]
        incr i
    }
    return [lsort -integer -index 0 $pairs]
}

proc ::GX::annotationDrawPreviewOverlay {} {
    variable ui
    if {![info exists ui(graphPreviewSourcePath)] || ![file isfile $ui(graphPreviewSourcePath)]} return
    set json [annotationPathForPlot $ui(graphPreviewSourcePath)]
    if {![file isfile $json]} return
    set sig "$json|[file mtime $json]|[file size $json]"
    if {[info exists ui(annotationPreviewSig)] && $ui(annotationPreviewSig) eq $sig && [info exists ui(annotationPreviewDoc)]} {
        set doc $ui(annotationPreviewDoc)
    } else {
        if {[catch {set doc [annotationLoadDocument $ui(graphPreviewSourcePath)]}]} return
        set ui(annotationPreviewSig) $sig
        set ui(annotationPreviewDoc) $doc
    }
    set meta [dict get $doc meta]; set objects [dict get $doc objects]
    if {![dict get $meta enabled]} return
    set geom [previewImageGeometry]
    if {[llength $geom] != 4} return
    lassign $geom ox oy iw ih
    set c $ui(graphPreview)
    foreach pair [annotationSortedIndexPairs $objects] {
        lassign $pair z i obj
        catch {annotationDrawObject $c $obj $i $ox $oy $iw $ih [dict get $meta width_px] [dict get $meta height_px] [dict get $meta dpi] annPreview:}
    }
}

proc ::GX::annotationInfoForPlot {plotPath} {
    set json [annotationPathForPlot $plotPath]
    if {![file isfile $json]} { return "Annotations: none" }
    if {[catch {set doc [annotationLoadDocument $plotPath]} err]} { return "Annotations: ERROR - $err" }
    return "Annotations: [llength [dict get $doc objects]] object(s), JSON: [file tail $json]"
}

# ---------------------------- Editor -----------------------------------------
proc ::GX::annotationPushUndo {} {
    variable annObjects; variable annUndo; variable annRedo
    lappend annUndo $annObjects
    if {[llength $annUndo] > 50} { set annUndo [lrange $annUndo end-49 end] }
    set annRedo {}
}
proc ::GX::annotationUndo {} {
    variable annObjects; variable annUndo; variable annRedo; variable annSelected; variable annDirty
    if {![llength $annUndo]} return
    lappend annRedo $annObjects
    set annObjects [lindex $annUndo end]
    set annUndo [lrange $annUndo 0 end-1]
    set annSelected -1; set annDirty 1
    annotationEditorRender; annotationLoadProps
}
proc ::GX::annotationRedo {} {
    variable annObjects; variable annUndo; variable annRedo; variable annSelected; variable annDirty
    if {![llength $annRedo]} return
    lappend annUndo $annObjects
    set annObjects [lindex $annRedo end]
    set annRedo [lrange $annRedo 0 end-1]
    set annSelected -1; set annDirty 1
    annotationEditorRender; annotationLoadProps
}
proc ::GX::annotationNextId {type} {
    variable annNextId
    set id "${type}_[format %03d $annNextId]"
    incr annNextId
    return $id
}
proc ::GX::annotationNormFromCanvas {c x y} {
    variable annPlotPath
    set xx [$c canvasx $x]; set yy [$c canvasy $y]
    if {[catch {set iw [image width ::GX::annBasePhoto]}] || $iw <= 0} { return {} }
    set ih [image height ::GX::annBasePhoto]
    set nx [expr {min(1.0,max(0.0,$xx/double($iw)))}]
    set ny [expr {min(1.0,max(0.0,1.0-$yy/double($ih)))}]
    return [list $nx $ny]
}
proc ::GX::annotationFindObjectAt {c x y} {
    set xx [$c canvasx $x]; set yy [$c canvasy $y]
    set hits [$c find overlapping [expr {$xx-4}] [expr {$yy-4}] [expr {$xx+4}] [expr {$yy+4}]]
    foreach item [lreverse $hits] {
        foreach tag [$c gettags $item] {
            if {[regexp {^annObj:([0-9]+)$} $tag -> idx]} { return $idx }
        }
    }
    return -1
}
proc ::GX::annotationTranslateObject {obj dx dy} {
    set type [dict get $obj type]
    if {$type eq "text"} {
        dict set obj x [expr {min(1,max(0,double([dict get $obj x])+$dx))}]
        dict set obj y [expr {min(1,max(0,double([dict get $obj y])+$dy))}]
    } else {
        foreach k {x1 x2} { dict set obj $k [expr {min(1,max(0,double([dict get $obj $k])+$dx))}] }
        foreach k {y1 y2} { dict set obj $k [expr {min(1,max(0,double([dict get $obj $k])+$dy))}] }
    }
    return $obj
}
proc ::GX::annotationEditorPress {w x y} {
    variable annTool; variable annObjects; variable annSelected; variable annDragStart; variable annDragObject; variable annDragIndex; variable annDirty
    set pos [annotationNormFromCanvas $w $x $y]
    if {[llength $pos] != 2} return
    lassign $pos nx ny
    if {$annTool eq "select"} {
        set idx [annotationFindObjectAt $w $x $y]
        set annSelected $idx
        set annDragIndex $idx
        set annDragStart [list $nx $ny]
        set annDragObject [expr {$idx >= 0 ? [lindex $annObjects $idx] : {}}]
        annotationLoadProps; annotationEditorRender
        return
    }
    if {$annTool eq "text"} {
        annotationPushUndo
        set obj [annotationDefaultObject text [annotationNextId text]]
        dict set obj x $nx; dict set obj y $ny; dict set obj z_index [llength $annObjects]
        lappend annObjects $obj
        set annSelected [expr {[llength $annObjects]-1}]
        set annDirty 1
        annotationEditorRender; annotationLoadProps
        set annTool select
        return
    }
    set annDragStart [list $nx $ny]
    set annDragIndex -1
    $w delete annTemp
}
proc ::GX::annotationEditorDrag {w x y} {
    variable annTool; variable annObjects; variable annSelected; variable annDragStart; variable annDragObject; variable annDragIndex
    set pos [annotationNormFromCanvas $w $x $y]
    if {[llength $pos] != 2 || [llength $annDragStart] != 2} return
    lassign $pos nx ny; lassign $annDragStart sx sy
    if {$annTool eq "select" && $annDragIndex >= 0 && [dict get $annDragObject locked] == 0} {
        set obj [annotationTranslateObject $annDragObject [expr {$nx-$sx}] [expr {$ny-$sy}]]
        lset annObjects $annDragIndex $obj
        annotationEditorRender
        return
    }
    if {$annTool ni {line arrow rectangle ellipse}} return
    set iw [image width ::GX::annBasePhoto]; set ih [image height ::GX::annBasePhoto]
    set x1 [expr {$sx*$iw}]; set y1 [expr {(1-$sy)*$ih}]; set x2 [expr {$nx*$iw}]; set y2 [expr {(1-$ny)*$ih}]
    $w delete annTemp
    if {$annTool in {line arrow}} {
        $w create line $x1 $y1 $x2 $y2 -fill #CC3300 -width 2 -arrow [expr {$annTool eq "arrow" ? "last" : "none"}] -tags annTemp
    } elseif {$annTool eq "rectangle"} {
        $w create rectangle $x1 $y1 $x2 $y2 -outline #CC3300 -width 2 -dash {6 4} -tags annTemp
    } else {
        $w create oval $x1 $y1 $x2 $y2 -outline #CC3300 -width 2 -dash {6 4} -tags annTemp
    }
}
proc ::GX::annotationEditorRelease {w x y} {
    variable annTool; variable annObjects; variable annSelected; variable annDragStart; variable annDragIndex; variable annDirty
    set pos [annotationNormFromCanvas $w $x $y]
    if {[llength $pos] != 2 || [llength $annDragStart] != 2} { set annDragStart {}; return }
    lassign $pos nx ny; lassign $annDragStart sx sy
    if {$annTool eq "select"} {
        if {$annDragIndex >= 0 && (abs($nx-$sx) > 0.0005 || abs($ny-$sy) > 0.0005)} {
            # The pre-drag snapshot must be the undo state.
            variable annDragObject; variable annUndo; variable annRedo
            lappend annUndo [lreplace $annObjects $annDragIndex $annDragIndex $annDragObject]
            if {[llength $annUndo] > 50} { set annUndo [lrange $annUndo end-49 end] }
            set annRedo {}; set annDirty 1
        }
        set annDragStart {}; set annDragIndex -1
        annotationLoadProps; annotationEditorRender
        return
    }
    if {$annTool in {line arrow rectangle ellipse}} {
        if {abs($nx-$sx) > 0.002 || abs($ny-$sy) > 0.002} {
            annotationPushUndo
            set obj [annotationDefaultObject $annTool [annotationNextId $annTool]]
            dict set obj x1 $sx; dict set obj y1 $sy; dict set obj x2 $nx; dict set obj y2 $ny; dict set obj z_index [llength $annObjects]
            lappend annObjects $obj; set annSelected [expr {[llength $annObjects]-1}]; set annDirty 1
        }
        set annTool select
    }
    set annDragStart {}; $w delete annTemp
    annotationEditorRender; annotationLoadProps
}

proc ::GX::annotationEditorRender {} {
    variable annObjects; variable annSelected; variable ui; variable annPlotPath
    if {![info exists ui(annCanvas)] || ![winfo exists $ui(annCanvas)]} return
    set c $ui(annCanvas); $c delete annLayer; $c delete annSelection
    if {[catch {set iw [image width ::GX::annBasePhoto]}]} return
    set ih [image height ::GX::annBasePhoto]
    variable annDpi
    set dpi $annDpi
    foreach pair [annotationSortedIndexPairs $annObjects] {
        lassign $pair z i obj
        catch {annotationDrawObject $c $obj $i 0 0 $iw $ih $iw $ih $dpi annObj:}
    }
    if {$annSelected >= 0 && $annSelected < [llength $annObjects]} {
        set ids [$c find withtag "annObj:$annSelected"]
        set bb {}
        foreach id $ids {
            set b [$c bbox $id]
            if {[llength $b] != 4} continue
            if {[llength $bb] != 4} { set bb $b } else { set bb [list [expr {min([lindex $bb 0],[lindex $b 0])}] [expr {min([lindex $bb 1],[lindex $b 1])}] [expr {max([lindex $bb 2],[lindex $b 2])}] [expr {max([lindex $bb 3],[lindex $b 3])}]] }
        }
        if {[llength $bb] == 4} { $c create rectangle [expr {[lindex $bb 0]-4}] [expr {[lindex $bb 1]-4}] [expr {[lindex $bb 2]+4}] [expr {[lindex $bb 3]+4}] -outline #0066CC -width 1 -dash {4 3} -tags annSelection }
    }
    set ui(annStatus) "[llength $annObjects] object(s)[expr {$::GX::annDirty ? " - modified" : ""}]"
}

proc ::GX::annotationLoadProps {} {
    variable annObjects; variable annSelected; variable ui
    foreach {k def} {visible 1 locked 0 color #000000 stroke #000000 stroke_width 1.5 stroke_unit px dash solid fill "" fill_opacity 0 head triangle font_family sans font_size 12 font_unit pt bold 0 italic 0 rotation_deg 0 h_align left v_align middle background "" border 0 z_index 0 type ""} { set ui(annProp,$k) $def }
    if {[info exists ui(annTextWidget)] && [winfo exists $ui(annTextWidget)]} { $ui(annTextWidget) delete 1.0 end }
    if {$annSelected < 0 || $annSelected >= [llength $annObjects]} { set ui(annProp,type) "No selection"; return }
    set obj [lindex $annObjects $annSelected]
    foreach k [dict keys $obj] { if {[info exists ui(annProp,$k)]} { set ui(annProp,$k) [dict get $obj $k] } }
    set type [dict get $obj type]; set ui(annProp,type) $type
    if {$type eq "text" && [info exists ui(annTextWidget)] && [winfo exists $ui(annTextWidget)]} { $ui(annTextWidget) insert 1.0 [dict get $obj text] }
}

proc ::GX::annotationApplyProps {} {
    variable annObjects; variable annSelected; variable ui; variable annDirty
    if {$annSelected < 0 || $annSelected >= [llength $annObjects]} return
    annotationPushUndo
    set obj [lindex $annObjects $annSelected]
    set type [dict get $obj type]
    foreach k {visible locked} { dict set obj $k $ui(annProp,$k) }
    if {$type eq "text"} {
        foreach k {font_family font_size font_unit bold italic color rotation_deg h_align v_align background border} { dict set obj $k $ui(annProp,$k) }
        dict set obj text [$ui(annTextWidget) get 1.0 end-1c]
    } else {
        foreach k {stroke stroke_width stroke_unit dash} { dict set obj $k $ui(annProp,$k) }
        if {$type in {rectangle ellipse}} { foreach k {fill fill_opacity} { dict set obj $k $ui(annProp,$k) } }
        if {$type eq "arrow"} { dict set obj head $ui(annProp,head) }
    }
    lset annObjects $annSelected $obj; set annDirty 1
    annotationEditorRender
}

proc ::GX::annotationDeleteSelected {} {
    variable annObjects; variable annSelected; variable annDirty
    if {$annSelected < 0 || $annSelected >= [llength $annObjects]} return
    annotationPushUndo; set annObjects [lreplace $annObjects $annSelected $annSelected]; set annSelected -1; set annDirty 1
    annotationEditorRender; annotationLoadProps
}
proc ::GX::annotationReorderSelected {dir} {
    variable annObjects; variable annSelected; variable annDirty
    if {$annSelected < 0 || $annSelected >= [llength $annObjects]} return
    set ni [expr {$dir > 0 ? [llength $annObjects]-1 : 0}]
    if {$ni == $annSelected} return
    annotationPushUndo
    set obj [lindex $annObjects $annSelected]
    set annObjects [lreplace $annObjects $annSelected $annSelected]
    set annObjects [linsert $annObjects $ni $obj]
    set annSelected $ni
    set i 0; set tmp {}
    foreach o $annObjects { dict set o z_index $i; lappend tmp $o; incr i }
    set annObjects $tmp; set annDirty 1
    annotationEditorRender; annotationLoadProps
}

proc ::GX::annotationSaveEditor {{closeAfter 0}} {
    variable annPlotPath; variable annObjects; variable annDirty; variable ui
    if {$annPlotPath eq ""} return
    if {[catch {set p [annotationSaveDocument $annPlotPath $annObjects]} err]} { tk_messageBox -icon error -title "Annotations" -message $err; return }
    set annDirty 0; set ui(annStatus) "Saved: $p"
    catch {unset ui(annotationPreviewSig)}; catch {unset ui(annotationPreviewDoc)}; catch {set ui(graphPreviewLoadSig) ""; previewGraph; refreshManifestPreview}
    if {$closeAfter} { destroy .annedit }
}
proc ::GX::annotationEditorClose {} {
    variable annDirty
    if {$annDirty} {
        set r [tk_messageBox -icon question -type yesnocancel -title "Annotations" -message "Save annotation changes before closing?"]
        if {$r eq "cancel"} return
        if {$r eq "yes"} { annotationSaveEditor 1; return }
    }
    catch {destroy .annedit}
}

proc ::GX::annotateCurrentGraph {} {
    variable annObjects; variable annSelected; variable annPlotPath; variable annJsonPath; variable annDirty; variable annUndo; variable annRedo; variable annNextId; variable annDpi; variable annTool; variable ui
    set p [currentGraphPath]
    if {$p eq "" || ![file isfile $p]} { tk_messageBox -message "Select a plot first."; return }
    if {![graphSupportsAnnotations $p]} { tk_messageBox -message "The selected plot does not declare supports_annotations=1 with a standard annotation editor."; return }
    if {[catch {set doc [annotationLoadDocument $p]} err]} { tk_messageBox -icon error -title "Annotations" -message $err; return }
    set annPlotPath $p; set annJsonPath [dict get $doc path]; set annObjects [dict get $doc objects]; set annDpi [dict get [dict get $doc meta] dpi]; set annSelected -1; set annDirty 0; set annUndo {}; set annRedo {}; set annTool select
    set annNextId 1
    foreach o $annObjects { if {[regexp {_([0-9]+)$} [dict get $o id] -> n] && $n >= $annNextId} { set annNextId [expr {$n+1}] } }
    set w .annedit; catch {destroy $w}; toplevel $w; wm title $w "Plot annotations - [file tail $p]"; wm protocol $w WM_DELETE_WINDOW ::GX::annotationEditorClose
    set sw [winfo screenwidth .]; set sh [winfo screenheight .]; wm geometry $w "[expr {int($sw*.95)}]x[expr {int($sh*.90)}]+10+25"
    grid columnconfigure $w 0 -weight 1; grid rowconfigure $w 1 -weight 1
    ttk::frame $w.tools
    foreach {tool label} {select Select text Text line Line arrow Arrow rectangle Rectangle ellipse Ellipse} {
        ttk::radiobutton $w.tools.$tool -text $label -variable ::GX::annTool -value $tool
        pack $w.tools.$tool -side left -padx 2
    }
    ttk::separator $w.tools.sep -orient vertical; pack $w.tools.sep -side left -fill y -padx 6
    ttk::button $w.tools.undo -text "Undo" -command ::GX::annotationUndo; ttk::button $w.tools.redo -text "Redo" -command ::GX::annotationRedo
    ttk::button $w.tools.del -text "Delete" -command ::GX::annotationDeleteSelected; ttk::button $w.tools.back -text "Send back" -command {::GX::annotationReorderSelected -1}; ttk::button $w.tools.front -text "Bring front" -command {::GX::annotationReorderSelected 1}
    pack $w.tools.undo $w.tools.redo $w.tools.del $w.tools.back $w.tools.front -side left -padx 2
    ttk::label $w.tools.note -text "Base PNG is read-only; Save writes only the JSON annotation layer."; pack $w.tools.note -side right -padx 8
    grid $w.tools -row 0 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 5
    ttk::frame $w.view; grid columnconfigure $w.view 0 -weight 1; grid rowconfigure $w.view 0 -weight 1
    canvas $w.view.c -background #d9d9d9 -highlightthickness 0 -xscrollcommand [list $w.view.sx set] -yscrollcommand [list $w.view.sy set]
    ttk::scrollbar $w.view.sx -orient horizontal -command [list $w.view.c xview]; ttk::scrollbar $w.view.sy -orient vertical -command [list $w.view.c yview]
    grid $w.view.c -row 0 -column 0 -sticky nsew; grid $w.view.sy -row 0 -column 1 -sticky ns; grid $w.view.sx -row 1 -column 0 -sticky ew
    grid $w.view -row 1 -column 0 -sticky nsew -padx {5 2} -pady 5
    catch {image delete ::GX::annBasePhoto}; image create photo ::GX::annBasePhoto -file $p
    set iw [image width ::GX::annBasePhoto]; set ih [image height ::GX::annBasePhoto]
    $w.view.c create image 0 0 -anchor nw -image ::GX::annBasePhoto -tags annBase; $w.view.c configure -scrollregion [list 0 0 $iw $ih]
    set ui(annCanvas) $w.view.c
    bind $w.view.c <ButtonPress-1> {::GX::annotationEditorPress %W %x %y}
    bind $w.view.c <B1-Motion> {::GX::annotationEditorDrag %W %x %y}
    bind $w.view.c <ButtonRelease-1> {::GX::annotationEditorRelease %W %x %y}
    ttk::labelframe $w.props -text "Selected object properties"; grid columnconfigure $w.props 1 -weight 1
    set r 0
    ttk::label $w.props.typeL -text "Type"; ttk::label $w.props.type -textvariable ::GX::ui(annProp,type); grid $w.props.typeL -row $r -column 0 -sticky e -padx 3 -pady 2; grid $w.props.type -row $r -column 1 -sticky w; incr r
    foreach {key label widget values} {
        visible Visible check {}
        locked Locked check {}
        stroke {Stroke / color} entry {}
        stroke_width {Stroke width} entry {}
        stroke_unit {Stroke unit} combo {px pt}
        dash {Line style} combo {solid dashed dotted}
        fill Fill entry {}
        fill_opacity {Fill opacity 0..1} entry {}
        head {Arrow head} combo {triangle open none}
        font_family {Font family} entry {}
        font_size {Font size} entry {}
        font_unit {Font unit} combo {px pt}
        bold Bold check {}
        italic Italic check {}
        color {Text color} entry {}
        rotation_deg {Text rotation [deg]} entry {}
        h_align {Text horizontal align} combo {left center right}
        v_align {Text vertical align} combo {top middle bottom}
        background {Text background} entry {}
        border {Text border} check {}
    } {
        ttk::label $w.props.l$key -text $label
        if {$widget eq "check"} {
            ttk::checkbutton $w.props.w$key -variable ::GX::ui(annProp,$key)
        } elseif {$widget eq "combo"} {
            ttk::combobox $w.props.w$key -textvariable ::GX::ui(annProp,$key) -values $values -state readonly -width 16
        } else {
            ttk::entry $w.props.w$key -textvariable ::GX::ui(annProp,$key) -width 18
        }
        grid $w.props.l$key -row $r -column 0 -sticky e -padx 3 -pady 1; grid $w.props.w$key -row $r -column 1 -sticky ew -padx 3 -pady 1; incr r
    }
    ttk::label $w.props.lt -text "Text"; text $w.props.text -height 4 -width 28 -wrap word
    grid $w.props.lt -row $r -column 0 -sticky ne -padx 3 -pady 2; grid $w.props.text -row $r -column 1 -sticky ew -padx 3 -pady 2; incr r
    set ui(annTextWidget) $w.props.text
    ttk::button $w.props.apply -text "Apply properties" -command ::GX::annotationApplyProps; grid $w.props.apply -row $r -column 0 -columnspan 2 -pady 6
    grid $w.props -row 1 -column 1 -sticky ns -padx {2 5} -pady 5
    ttk::frame $w.bottom; ttk::label $w.bottom.status -textvariable ::GX::ui(annStatus); ttk::button $w.bottom.save -text "Save JSON" -command ::GX::annotationSaveEditor; ttk::button $w.bottom.saveclose -text "Save && close" -command {::GX::annotationSaveEditor 1}; ttk::button $w.bottom.close -text "Close" -command ::GX::annotationEditorClose
    pack $w.bottom.status -side left -fill x -expand 1 -padx 5; pack $w.bottom.save $w.bottom.saveclose $w.bottom.close -side left -padx 3
    grid $w.bottom -row 2 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 5
    annotationEditorRender; annotationLoadProps
}

proc ::GX::exportAnnotatedGraphs {} {
    variable cfg; variable currentSession
    set imgs [selectedGraphPaths]
    if {[llength $imgs] == 0} { tk_messageBox -message "No plot selected."; return }
    set d [tk_chooseDirectory -title "Annotated plot export folder" -initialdir [expr {$cfg(export_dir) ne "" ? $cfg(export_dir) : [pwd]}]]
    if {$d eq ""} return
    set cfg(export_dir) $d; set count 0
    foreach f $imgs {
        if {$currentSession ne "" && [string first $currentSession $f] == 0} { set rel [string range $f [expr {[string length $currentSession]+1}] end] } else { set rel [file tail $f] }
        set dst [file join $d $rel]; file mkdir [file dirname $dst]
        if {[catch {annotationRenderTo $f $dst} err]} { tk_messageBox -icon error -title "Annotated export" -message $err; return }
        incr count
    }
    setStatus "Exported $count annotated plot(s) to $d"
}

# ---------------------------- Integration wrappers ---------------------------
proc ::GX::drawGraphPreview_v090_before_plot_region {} {
    ::GX::drawGraphPreview_annotation_base
    catch {annotationDrawPreviewOverlay}
}
proc ::GX::drawGraphPreview {} { ::GX::drawGraphPreview_v090_before_plot_region }

proc ::GX::previewGraph_before_layout_controls {} {
    variable ui
    ::GX::previewGraph_annotation_base
    if {[info exists ui(graphPreviewSourcePath)]} { append ui(graphInfo) "\n[annotationInfoForPlot $ui(graphPreviewSourcePath)]" }
}

# Print/PDF automatically uses an ephemeral composited PNG when a JSON layer exists.
proc ::GX::selectedGraphPaths {} {
    variable annotationPrintOverrideActive; variable annotationPrintOverridePaths
    if {$annotationPrintOverrideActive} { return $annotationPrintOverridePaths }
    return [::GX::selectedGraphPaths_annotation_base]
}
proc ::GX::composePdf {} {
    variable annotationPrintOverrideActive; variable annotationPrintOverridePaths
    set base [::GX::selectedGraphPaths_annotation_base]
    set annotationPrintOverridePaths {}
    foreach p $base {
        if {[catch {lappend annotationPrintOverridePaths [annotationOutputForPrint $p]} err]} { tk_messageBox -icon error -title "Annotated print" -message $err; return 0 }
    }
    set annotationPrintOverrideActive 1
    try { return [::GX::composePdf_annotation_base] } finally { set annotationPrintOverrideActive 0; set annotationPrintOverridePaths {} }
}

# Manifest Format 2 references annotation documents; object payload remains in JSON.
proc ::GX::manifestStringV2_v070_graph_provider_base {} {
    set out [::GX::manifestStringV2_annotation_base]
    set entries [annotationManifestEntries]
    append out "\n\[plot_annotations\]\n"; appendKV out api_version 1; appendKV out count [llength $entries]
    set i 0
    foreach e $entries {
        incr i; append out "\n\[plot_annotation.$i\]\n"
        foreach k {plot_id plot_path file enabled api_version} { appendKV out $k [dict get $e $k] }
    }
    return $out
}
proc ::GX::loadManifestV2_v070_graph_provider_base {path} {
    ::GX::loadManifestV2_annotation_base $path
    # References are intentionally not copied into memory: JSON is authoritative.
    # Validate references opportunistically without blocking older sessions.
    set d [parseIni $path]
    if {[dict exists $d plot_annotations.count]} {
        set n [dict get $d plot_annotations.count]
        if {[string is integer -strict $n] && $n > 0} {
            for {set i 1} {$i <= $n} {incr i} {
                set k "plot_annotation.$i.file"
                if {[dict exists $d $k]} { guiLog "Annotation layer reference: [dict get $d $k]" }
            }
        }
    }
}

# Descriptor-driven GUI: standard annotation controls appear only for supported plots.
proc ::GX::augmentStandardGui_v081_before_csv_batch {} {
    ::GX::augmentStandardGui_annotation_base
    set f .top.nb.graphs
    if {[winfo exists $f.actions] && ![winfo exists $f.actions.annotate]} {
        ttk::button $f.actions.annotate -text "Annotate..." -command ::GX::annotateCurrentGraph
        ttk::button $f.actions.exportann -text "Export annotated..." -command ::GX::exportAnnotatedGraphs
        pack $f.actions.annotate $f.actions.exportann -side left -padx 3 -before $f.actions.clone
    }
}
