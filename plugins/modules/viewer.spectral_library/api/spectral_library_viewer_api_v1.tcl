# GX-TXT Scientific Spectral Library Viewer backend API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SpectralLibraryViewer {
    variable version 1.0.14
    variable window .gx_spectral_library
    variable libraryId ""
    variable entityId ""
    variable searchText ""
    variable mode overlay
    variable reversed 1
    variable sessionDataset ""
    variable rankingDataset ""
    variable selectedIds {}
    variable spectra {}
    variable viewport {}
    variable fullRange {}
    variable documentId ""
    variable sessionToken ""
    variable dragX ""
    variable shownX {}
    variable statusText "Ready"
}

proc ::GX::SpectralLibraryViewer::apiInfo {} {
    return [dict create api_name SPECTRAL_LIBRARY_VIEWER_API_v1 api_version 1 module_id viewer.spectral_library backend spectral_library_tk]
}
proc ::GX::SpectralLibraryViewer::_hasSession {} {
    return [expr {![catch {::GX::sessionInspectionCurrentSession}]}]
}
proc ::GX::SpectralLibraryViewer::_dictDefault {value key default} {
    return [expr {[dict exists $value $key] ? [dict get $value $key] : $default}]
}
proc ::GX::SpectralLibraryViewer::_restoreState {} {
    variable documentId; variable sessionToken; variable libraryId; variable entityId
    variable mode; variable reversed; variable selectedIds
    variable sessionDataset; variable rankingDataset; variable viewport
    set documentId ""; set sessionToken ""
    if {![_hasSession]} { return }
    set sessionToken [::GX::interactiveDocumentSessionToken]
    set docs [::GX::interactiveDocumentList viewer.spectral_library spectral_library]
    if {![llength $docs]} { return }
    set documentId [dict get [lindex $docs 0] id]
    set payload [dict get [::GX::interactiveDocumentRead $documentId] payload]
    if {[catch {dict size $payload}]} { return }
    foreach key {libraryId entityId mode reversed selectedIds sessionDataset rankingDataset viewport} {
        if {[dict exists $payload $key]} { set $key [dict get $payload $key] }
    }
}
proc ::GX::SpectralLibraryViewer::_saveState {} {
    variable documentId; variable sessionToken; variable libraryId; variable entityId
    variable mode; variable reversed; variable selectedIds
    variable sessionDataset; variable rankingDataset; variable viewport
    if {![_hasSession]} { return }
    if {$sessionToken eq "" || $sessionToken ne [::GX::interactiveDocumentSessionToken]} {
        error "Spectral Viewer Session changed; stale state cannot be saved"
    }
    set payload [dict create libraryId $libraryId entityId $entityId mode $mode reversed $reversed \
        selectedIds $selectedIds sessionDataset $sessionDataset \
        rankingDataset $rankingDataset viewport $viewport]
    if {$documentId eq ""} {
        set result [::GX::interactiveDocumentCreate viewer.spectral_library spectral_library \
            gxtxt.spectral_library.viewer.state 1.0 $payload]
        set documentId [dict get $result id]
    } else {
        ::GX::interactiveDocumentUpdate $documentId $payload
    }
}
proc ::GX::SpectralLibraryViewer::_libraries {} {
    set managed [::GX::ScientificLibraryManagerAPIv1::queryCompatibleLibraries spectroscopy.ir.reference]
    set result $managed
    foreach libraryId [::GX::ReferenceLibraryAPIv1::listLibraries] {
        if {$libraryId ni $result} {lappend result $libraryId}
    }
    return $result
}
proc ::GX::SpectralLibraryViewer::_installLibrary {} {
    variable window; variable libraryId; variable entityId
    variable selectedIds; variable spectra; variable viewport; variable statusText
    set package [tk_getOpenFile -parent $window -title "Install IR reference library" \
        -filetypes {{{GX-TXT scientific libraries} {.zip}} {{All files} *}}]
    if {$package eq ""} {return}
    if {[catch {set installed [::GX::ScientificLibraryManagerAPIv1::installLibrary $package]} managedProblem]} {
        # The viewer also lists Scientific Reference Library API packages.  A
        # portable .gxsrl.zip must be installed through that API, whose import
        # verifies its exact member list, checksum and reference metadata.
        if {[catch {
            set importedId [::GX::ReferenceLibraryAPIv1::importLibrary $package]
            set info [::GX::ReferenceLibraryAPIv1::validateLibrary $importedId]
            set installed [dict create library_id $importedId \
                display_name [dict get $info name] version [dict get $info version]]
        } referenceProblem]} {
            tk_messageBox -parent $window -icon error -title "Library installation failed" \
                -message "$managedProblem\n$referenceProblem"
            return
        }
    }
    set libraryId [dict get $installed library_id]
    set entityId ""; set selectedIds {}; set spectra {}; set viewport {}
    $window.toolbar.library configure -values [_libraries]
    _libraryChanged
    set statusText "Installed [dict get $installed display_name] ([dict get $installed version])"
}
proc ::GX::SpectralLibraryViewer::_refreshSearch {} {
    variable window; variable libraryId; variable entityId; variable searchText; variable selectedIds
    set box $window.left.results
    $box delete 0 end
    if {$libraryId eq ""} { return }
    if {[string trim $searchText] eq ""} {
        set ids [::GX::ReferenceLibraryAPIv1::listSpectra $libraryId $entityId]
    } else {
        set ids [::GX::ReferenceLibraryAPIv1::search $libraryId $searchText]
        if {$entityId ne ""} {
            set inEntity [::GX::ReferenceLibraryAPIv1::listSpectra $libraryId $entityId]
            set allowed [dict create]
            foreach id $inEntity {dict set allowed $id 1}
            set filtered {}
            foreach id $ids {if {[dict exists $allowed $id]} {lappend filtered $id}}
            set ids $filtered
        }
    }
    foreach id $ids { $box insert end $id }
    set positions {}
    for {set i 0} {$i < [$box size]} {incr i} {
        if {[$box get $i] in $selectedIds} { lappend positions $i }
    }
    foreach i $positions { $box selection set $i }
    set ::GX::SpectralLibraryViewer::statusText "[llength $ids] spectra in $libraryId"
}
proc ::GX::SpectralLibraryViewer::_libraryChanged {} {
    variable window; variable libraryId; variable entityId; variable searchText
    variable selectedIds; variable spectra; variable viewport
    set entityId ""; set searchText ""
    set entities [expr {$libraryId eq "" ? {} : [::GX::ReferenceLibraryAPIv1::listEntities $libraryId]}]
    $window.left.entity configure -values [linsert $entities 0 ""]
    set selectedIds {}; set spectra {}; set viewport {}
    _refreshSearch
    _draw
    _saveState
}
proc ::GX::SpectralLibraryViewer::_entityChanged {} {
    variable selectedIds; variable spectra; variable viewport
    set selectedIds {}; set spectra {}; set viewport {}
    _refreshSearch
    _draw
    _saveState
}
proc ::GX::SpectralLibraryViewer::_metadataText {spectrum} {
    variable libraryId
    set lines [list "Library: $libraryId" \
        "Spectrum: [dict get $spectrum spectrum_id]" \
        "Name: [dict get $spectrum display_name]" \
        "Type: [dict get $spectrum spectrum_kind]" \
        "X: [dict get $spectrum x_quantity] [dict get $spectrum x_unit]" \
        "Y: [dict get $spectrum y_quantity] [dict get $spectrum y_unit]" \
        "Representation: [dict get $spectrum y_representation]" \
        "Samples: [dict get $spectrum sample_count]" \
        "Native range: [dict get $spectrum x_min] .. [dict get $spectrum x_max]" \
        "Source: [dict get $spectrum source_identity]"]
    set entityId [dict get $spectrum entity_id]
    if {$entityId ne ""} {
        if {![catch {set entity [::GX::ReferenceLibraryAPIv1::entityInfo $libraryId $entityId]}]} {
            foreach key {display_name compound_name cas formula inchikey phase} {
                if {[dict exists $entity $key]} { lappend lines "$key: [dict get $entity $key]" }
            }
        }
    }
    dict for {key value} [dict get $spectrum metadata] { lappend lines "$key: $value" }
    dict for {key value} [dict get $spectrum provenance] {
        if {$key in {license citation source_url}} { lappend lines "$key: $value" }
    }
    return [join $lines "\n"]
}
proc ::GX::SpectralLibraryViewer::_selectReferences {} {
    variable window; variable libraryId; variable selectedIds; variable spectra; variable viewport
    set selectedIds {}
    foreach i [$window.left.results curselection] {
        lappend selectedIds [$window.left.results get $i]
    }
    set selectedIds [lrange $selectedIds 0 3]
    set spectra {}
    foreach id $selectedIds {
        lappend spectra [::GX::ReferenceLibraryAPIv1::readSpectrum $libraryId $id]
    }
    set viewport {}
    set txt $window.right.metadata
    $txt configure -state normal
    $txt delete 1.0 end
    if {[llength $spectra]} { $txt insert end [_metadataText [lindex $spectra 0]] }
    $txt configure -state disabled
    _draw
    _saveState
}
proc ::GX::SpectralLibraryViewer::_sessionSpectra {} {
    if {[catch {set session [::GX::sessionInspectionCurrentSession]}]} { return {} }
    if {[catch {set datasets [::GX::sessionInspectionDatasetIds $session]}]} { return {} }
    set ids {}
    foreach id $datasets {
        if {[catch {set ds [::GX::sessionInspectionDataset $id $session]}]} continue
        set contract [_dictDefault $ds contract [_dictDefault $ds kind ""]]
        if {![catch {::GX::contractSatisfies $contract spectrum.scientific} ok] && $ok} {
            lappend ids $id
        }
    }
    return $ids
}
proc ::GX::SpectralLibraryViewer::_rankingDatasets {} {
    if {[catch {set session [::GX::sessionInspectionCurrentSession]}]} { return {} }
    if {[catch {set datasets [::GX::sessionInspectionDatasetIds $session]}]} { return {} }
    set ids {}
    foreach id $datasets {
        if {[string match *.ir.candidates $id]} { lappend ids $id }
    }
    return $ids
}
proc ::GX::SpectralLibraryViewer::_sessionSpectrum {} {
    variable sessionDataset
    if {$sessionDataset eq "" || [catch {set session [::GX::sessionInspectionCurrentSession]}]} { return {} }
    if {[catch {set handle [::GX::datasetAccessOpen $session $sessionDataset]}]} { return {} }
    try {
        set meta [::GX::datasetAccessMetadata $handle]
        set xId ""; set yId ""; set xUnit ""; set yUnit ""; set yName ""
        foreach variable [dict get $meta variables] {
            set id [dict get $variable variable_id]
            set role [_dictDefault $variable semantic_role ""]
            if {$xId eq "" && $role eq "independent"} { set xId $id; set xUnit [_dictDefault $variable unit ""] }
            if {$yId eq "" && $role in {measured derived}} {
                set yId $id; set yUnit [_dictDefault $variable unit ""]
                set yName [string tolower [_dictDefault $variable canonical [_dictDefault $variable name $id]]]
            }
        }
        if {$xId eq "" || $yId eq ""} { error "Session spectrum has no independent/response variable pair" }
        set rows [::GX::datasetAccessReadVariables $handle [list $xId $yId]]
        if {[string match *processed* $yName] || [string match *.ir.processed $sessionDataset]} {
            set representation processed_absorption_proxy
        } elseif {[string match *transmission* $yName]} {
            set representation transmission_signal
        } elseif {[string match *absorbance* $yName]} {
            set representation absorbance
        } else {
            set representation unknown
        }
        return [dict create spectrum_id "$sessionDataset:$yId" display_name "Session $sessionDataset" \
            x [dict get $rows $xId values] y [dict get $rows $yId values] \
            x_unit $xUnit y_unit $yUnit y_representation $representation]
    } finally { ::GX::datasetAccessClose $handle }
}
proc ::GX::SpectralLibraryViewer::_readRanking {} {
    variable window; variable rankingDataset
    set box $window.right.ranking
    $box delete 0 end
    if {$rankingDataset eq "" || [catch {set session [::GX::sessionInspectionCurrentSession]}]} { return }
    if {[catch {set handle [::GX::datasetAccessOpen $session $rankingDataset]}]} { return }
    try {
        set columns [dict create]
        foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {
            dict set columns [dict get $variable canonical] [dict get $variable variable_id]
        }
        set ids {}
        foreach name {rank library_id spectrum_id match_score} {
            if {![dict exists $columns $name]} {error "IR ranking Dataset lacks $name"}
            lappend ids [dict get $columns $name]
        }
        set rows [::GX::datasetAccessReadVariables $handle $ids]
        lassign $ids rankId libraryId spectrumId scoreId
        foreach rank [dict get $rows $rankId values] library [dict get $rows $libraryId values] \
            spectrum [dict get $rows $spectrumId values] score [dict get $rows $scoreId values] {
            $box insert end [format "%s | %.4f | %s | %s" $rank $score $library $spectrum]
        }
    } finally { ::GX::datasetAccessClose $handle }
    _saveState
}
proc ::GX::SpectralLibraryViewer::_rankingSelected {} {
    variable window; variable libraryId; variable entityId; variable selectedIds; variable searchText
    set pick [$window.right.ranking curselection]
    if {![llength $pick]} { return }
    set value [$window.right.ranking get [lindex $pick 0]]
    set parts [split $value |]
    if {[llength $parts] < 4} { return }
    set libraryId [string trim [lindex $parts 2]]
    set entityId ""
    $window.left.entity configure -values [linsert [::GX::ReferenceLibraryAPIv1::listEntities $libraryId] 0 ""]
    set spectrum [string trim [lindex $parts 3]]
    set searchText $spectrum
    set selectedIds [list $spectrum]
    _refreshSearch
    _selectReferences
}
proc ::GX::SpectralLibraryViewer::_comparisonTraces {} {
    variable spectra; variable mode; variable statusText
    set traces {}
    foreach spectrum $spectra {
        lappend traces [dict create label [dict get $spectrum display_name] \
            x [dict get $spectrum x] y [dict get $spectrum y] \
            x_unit [dict get $spectrum x_unit] y_representation [dict get $spectrum y_representation]]
    }
    set experiment [_sessionSpectrum]
    if {$experiment ne ""} {
        lappend traces [dict create label [dict get $experiment display_name] \
            x [dict get $experiment x] y [dict get $experiment y] \
            x_unit [dict get $experiment x_unit] y_representation [dict get $experiment y_representation]]
    }
    if {$mode eq "overlay" && [llength $traces] > 1} {
        set unit [dict get [lindex $traces 0] x_unit]
        set representation [dict get [lindex $traces 0] y_representation]
        foreach trace [lrange $traces 1 end] {
            if {[dict get $trace x_unit] ne $unit || [dict get $trace y_representation] ne $representation} {
                error "Overlay requires comparable X and intensity semantics; use Top / Bottom for unlike spectra"
            }
        }
    }
    if {$mode ni {difference ratio} || [llength $traces] < 2} { return $traces }
    set base [lindex $traces 0]
    set other [lindex $traces 1]
    if {[dict get $base x_unit] ne [dict get $other x_unit] ||
        [dict get $base y_representation] ne [dict get $other y_representation]} {
        set statusText "Difference/ratio requires equal coordinate and intensity semantics"
        return {}
    }
    set bx [dict get $base x]; set by [dict get $base y]
    set ox [dict get $other x]; set oy [dict get $other y]
    if {[lindex $bx 0] > [lindex $bx end]} { set bx [lreverse $bx]; set by [lreverse $by] }
    if {[lindex $ox 0] > [lindex $ox end]} { set ox [lreverse $ox]; set oy [lreverse $oy] }
    set target {}; set first {}
    foreach x $bx y $by {
        if {$x >= [lindex $ox 0] && $x <= [lindex $ox end]} { lappend target $x; lappend first $y }
    }
    if {[llength $target] < 2} { set statusText "No common spectral range"; return {} }
    ::GX::modulePublicApiActivate math.numeric NUMERIC_API_v1
    set interpolated [dict get [::GX::NumericAPIv1::resample $ox $oy $target [dict create method linear]] y]
    set values {}
    foreach a $first b $interpolated {
        if {$mode eq "difference"} { lappend values [expr {$a-$b}] } \
        elseif {abs($b)>1e-12} { lappend values [expr {$a/$b}] } \
        else { lappend values NaN }
    }
    return [list [dict create label "$mode: [dict get $base label] vs [dict get $other label]" \
        x $target y $values x_unit [dict get $base x_unit] y_representation $mode]]
}
proc ::GX::SpectralLibraryViewer::_drawTopBottom {canvas traces left right top bottom vmin vmax height} {
    variable reversed; variable sessionDataset; variable statusText
    $canvas delete all
    if {[llength $traces] < 2} {
        $canvas create text [expr {($left+$right)/2}] [expr {($top+$bottom)/2}] \
            -text "Top / Bottom needs an experimental and a reference spectrum (or two references)" \
            -width [expr {$right-$left-20}] -fill #555555
        set statusText "Select two spectra for Top / Bottom comparison"
        return
    }
    if {$sessionDataset ne ""} {
        set pair [list [lindex $traces end] [lindex $traces 0]]
        set names {Experimental Reference}
    } else {
        set pair [lrange $traces 0 1]
        set names {Reference_A Reference_B}
    }
    set middle [expr {($top+$bottom)/2.0}]
    set panels [list [list $top [expr {$middle-15}]] [list [expr {$middle+15}] $bottom]]
    set colors {#1260b2 #d65021}
    set index 0
    foreach trace $pair panel $panels role $names color $colors {
        lassign $panel panelTop panelBottom
        $canvas create rectangle $left $panelTop $right $panelBottom -outline #555555 -fill white
        set xx {}; set yy {}
        foreach x [dict get $trace x] y [dict get $trace y] {
            if {![string is double -strict $x] || ![string is double -strict $y] ||
                [regexp -nocase {nan|inf} "$x $y"] || $x < $vmin || $x > $vmax} {continue}
            lappend xx $x; lappend yy $y
        }
        if {[llength $xx] >= 2} {
            set ymin [lindex [lsort -real $yy] 0]
            set ymax [lindex [lsort -real $yy] end]
            set span [expr {max(1e-12,$ymax-$ymin)}]
            set ymin [expr {$ymin-0.06*$span}]
            set ymax [expr {$ymax+0.06*$span}]
            set coords {}
            set step [expr {max(1,int(ceil([llength $xx]/1600.0)))}]
            for {set i 0} {$i < [llength $xx]} {incr i $step} {
                set x [lindex $xx $i]; set y [lindex $yy $i]
                set f [expr {$reversed ? ($vmax-$x)/($vmax-$vmin) : ($x-$vmin)/($vmax-$vmin)}]
                lappend coords [expr {$left+$f*($right-$left)}] \
                    [expr {$panelBottom-($y-$ymin)/($ymax-$ymin)*($panelBottom-$panelTop)}]
            }
            if {[llength $coords] >= 4} {$canvas create line $coords -fill $color -width 2}
            $canvas create text [expr {$left-7}] $panelTop -text [format %.3g $ymax] -anchor e -fill #333333
            $canvas create text [expr {$left-7}] $panelBottom -text [format %.3g $ymin] -anchor e -fill #333333
        }
        $canvas create text [expr {$right+12}] [expr {$panelTop+8}] \
            -text "$role\n[dict get $trace label]\n([dict get $trace y_representation])" \
            -anchor nw -width 145 -fill $color
        for {set tick 0} {$tick <= 4} {incr tick} {
            set px [expr {$left+($right-$left)*$tick/4.0}]
            $canvas create line $px $panelTop $px $panelBottom -fill #eeeeee
            if {$index == 1} {
                set label [expr {$reversed ? $vmax-($vmax-$vmin)*$tick/4.0 : $vmin+($vmax-$vmin)*$tick/4.0}]
                $canvas create text $px [expr {$panelBottom+15}] -text [format %.0f $label] -anchor n -fill #333333
            }
        }
        incr index
    }
    $canvas create text [expr {($left+$right)/2}] [expr {$height-18}] \
        -text "Shared spectral coordinate ([dict get [lindex $pair 0] x_unit])" -fill #222222
    set statusText "Top / Bottom: shared X [format %.1f $vmin]–[format %.1f $vmax], independent Y scales"
}
proc ::GX::SpectralLibraryViewer::_draw {} {
    variable window; variable mode; variable reversed; variable viewport
    variable fullRange; variable shownX; variable statusText
    if {![winfo exists $window]} { return }
    set canvas $window.plot
    $canvas delete all
    set width [winfo width $canvas]
    set height [winfo height $canvas]
    if {$width < 400} { set width 850 }
    if {$height < 300} { set height 500 }
    set left 70; set right [expr {$width-165}]; set top 28; set bottom [expr {$height-62}]
    $canvas create rectangle $left $top $right $bottom -outline #555555 -fill white
    if {[catch {set traces [_comparisonTraces]} problem]} {
        set statusText "Comparison error: $problem"
        return
    }
    if {![llength $traces]} {
        $canvas create text [expr {($left+$right)/2}] [expr {($top+$bottom)/2}] \
            -text "Choose one or more reference spectra" -fill #555555
        return
    }
    set xmin Inf; set xmax -Inf
    foreach trace $traces {
        foreach x [dict get $trace x] {
            if {[string is double -strict $x] && ![regexp -nocase {nan|inf} $x]} {
                if {$x < $xmin} { set xmin $x }
                if {$x > $xmax} { set xmax $x }
            }
        }
    }
    if {$xmin >= $xmax} { set statusText "No finite spectral coordinates"; return }
    set fullRange [list $xmin $xmax]
    if {[llength $viewport] != 2 || [lindex $viewport 0] >= [lindex $viewport 1]} {
        set viewport $fullRange
    }
    set vmin [expr {max($xmin,[lindex $viewport 0])}]
    set vmax [expr {min($xmax,[lindex $viewport 1])}]
    if {$vmin >= $vmax} { set viewport $fullRange; lassign $viewport vmin vmax }
    set shownX [list $vmin $vmax $left $right]
    if {$mode eq "top_bottom"} {
        _drawTopBottom $canvas $traces $left $right $top $bottom $vmin $vmax $height
        return
    }
    set ymin Inf; set ymax -Inf
    set plotted {}
    set index 0
    foreach trace $traces {
        set xx {}; set yy {}
        foreach x [dict get $trace x] y [dict get $trace y] {
            if {$x < $vmin || $x > $vmax || ![string is double -strict $y] ||
                [regexp -nocase {nan|inf} $y]} { continue }
            lappend xx $x; lappend yy $y
        }
        if {![llength $xx]} { incr index; continue }
        if {$mode eq "overlay" && [llength $traces] > 1} {
            set localMin [lindex [lsort -real $yy] 0]
            set localMax [lindex [lsort -real $yy] end]
            set span [expr {max(1e-12,$localMax-$localMin)}]
            set yy [lmap value $yy {expr {($value-$localMin)/$span}}]
        } elseif {$mode eq "stacked"} {
            set localMin [lindex [lsort -real $yy] 0]
            set localMax [lindex [lsort -real $yy] end]
            set span [expr {max(1e-12,$localMax-$localMin)}]
            set yy [lmap value $yy {expr {($value-$localMin)/$span+1.3*$index}}]
        }
        foreach y $yy {
            if {$y < $ymin} { set ymin $y }
            if {$y > $ymax} { set ymax $y }
        }
        lappend plotted [dict create label [dict get $trace label] x $xx y $yy]
        incr index
    }
    if {$ymin >= $ymax} { set ymin [expr {$ymin-1}]; set ymax [expr {$ymax+1}] }
    set padding [expr {0.06*($ymax-$ymin)}]
    set ymin [expr {$ymin-$padding}]
    set ymax [expr {$ymax+$padding}]
    for {set tick 0} {$tick <= 4} {incr tick} {
        set px [expr {$left+($right-$left)*$tick/4.0}]
        set py [expr {$bottom-($bottom-$top)*$tick/4.0}]
        $canvas create line $px $top $px $bottom -fill #eeeeee
        $canvas create line $left $py $right $py -fill #eeeeee
        set xLabel [expr {$reversed ? $vmax-($vmax-$vmin)*$tick/4.0 : $vmin+($vmax-$vmin)*$tick/4.0}]
        set yLabel [expr {$ymin+($ymax-$ymin)*$tick/4.0}]
        $canvas create text $px [expr {$bottom+15}] -text [format %.0f $xLabel] -anchor n -fill #333333
        $canvas create text [expr {$left-7}] $py -text [format %.3g $yLabel] -anchor e -fill #333333
    }
    set colors {#1260b2 #d65021 #198048 #8044a8 #333333}
    set index 0
    foreach trace $plotted {
        set color [lindex $colors [expr {$index % [llength $colors]}]]
        set x [dict get $trace x]; set y [dict get $trace y]
        set count [llength $x]
        set skip [expr {max(1,int(ceil($count/1600.0)))}]
        set coords {}
        for {set i 0} {$i < $count} {incr i $skip} {
            set xv [lindex $x $i]; set yv [lindex $y $i]
            set fx [expr {$reversed ? ($vmax-$xv)/($vmax-$vmin) : ($xv-$vmin)/($vmax-$vmin)}]
            lappend coords [expr {$left+$fx*($right-$left)}] \
                [expr {$bottom-($yv-$ymin)/($ymax-$ymin)*($bottom-$top)}]
        }
        if {[llength $coords] >= 4} { $canvas create line $coords -fill $color -width 2 }
        set ly [expr {$top+18+$index*52}]
        $canvas create line [expr {$right+15}] $ly [expr {$right+38}] $ly -fill $color -width 2
        $canvas create text [expr {$right+44}] $ly -text [dict get $trace label] -anchor w \
            -width 112 -fill #222222
        incr index
    }
    $canvas create text [expr {($left+$right)/2}] [expr {$height-18}] \
        -text "Spectral coordinate ([dict get [lindex $traces 0] x_unit])" -fill #222222
    $canvas create text 18 [expr {($top+$bottom)/2}] -text "[expr {$mode eq "stacked" ? "Stacked normalized" : $mode eq "overlay" && [llength $traces] > 1 ? "Shape normalized 0–1" : "Native / derived intensity"}]" \
        -angle 90 -fill #222222
    set statusText "[llength $plotted] displayed; range [format %.1f $vmin]–[format %.1f $vmax]; $mode"
}
proc ::GX::SpectralLibraryViewer::_modeChanged {} {
    _draw
    _saveState
}
proc ::GX::SpectralLibraryViewer::_resetRange {} {
    variable viewport
    set viewport {}
    _draw
    _saveState
}
proc ::GX::SpectralLibraryViewer::_zoom {pixel delta} {
    variable shownX; variable viewport; variable fullRange
    if {[llength $shownX] != 4 || [llength $fullRange] != 2} { return }
    lassign $shownX lo hi left right
    set fraction [expr {max(0.0,min(1.0,($pixel-$left)/double($right-$left)))}]
    set center [expr {$lo+$fraction*($hi-$lo)}]
    set factor [expr {$delta > 0 ? 0.8 : 1.25}]
    set half [expr {($hi-$lo)*$factor/2.0}]
    set lo [expr {max([lindex $fullRange 0],$center-$half)}]
    set hi [expr {min([lindex $fullRange 1],$center+$half)}]
    if {$hi-$lo > 0} { set viewport [list $lo $hi]; _draw; _saveState }
}
proc ::GX::SpectralLibraryViewer::_dragStart {pixel} {
    variable dragX
    set dragX $pixel
}
proc ::GX::SpectralLibraryViewer::_dragMove {pixel} {
    variable dragX; variable shownX; variable viewport; variable fullRange
    if {$dragX eq "" || [llength $shownX] != 4} { return }
    lassign $shownX lo hi left right
    set shift [expr {($dragX-$pixel)*($hi-$lo)/double($right-$left)}]
    set newLo [expr {$lo+$shift}]; set newHi [expr {$hi+$shift}]
    if {$newLo >= [lindex $fullRange 0] && $newHi <= [lindex $fullRange 1]} {
        set viewport [list $newLo $newHi]
        _draw
    }
    set dragX $pixel
}
proc ::GX::SpectralLibraryViewer::_cursor {pixel} {
    variable shownX; variable reversed; variable statusText
    if {[llength $shownX] != 4} { return }
    lassign $shownX lo hi left right
    set f [expr {max(0.0,min(1.0,($pixel-$left)/double($right-$left)))}]
    set x [expr {$reversed ? $hi-$f*($hi-$lo) : $lo+$f*($hi-$lo)}]
    set statusText "Cursor: [format %.2f $x] on spectral X axis"
}
proc ::GX::SpectralLibraryViewer::_sessionChanged {} {
    variable viewport
    set viewport {}
    _draw
    _saveState
}
proc ::GX::SpectralLibraryViewer::_rankingChanged {} {
    _readRanking
    _saveState
}
proc ::GX::SpectralLibraryViewer::_openContext {context} {
    variable window; variable libraryId; variable statusText
    if {![dict exists $context library_id]} {return}
    set requestedLibrary [dict get $context library_id]
    if {$requestedLibrary ni [_libraries]} {
        error "IR library $requestedLibrary is not available in the spectral viewer"
    }
    set libraryId $requestedLibrary
    _libraryChanged
    if {![dict exists $context entry_id]} {return}
    set requestedEntry [dict get $context entry_id]
    set box $window.left.results
    set index [lsearch -exact [$box get 0 end] $requestedEntry]
    if {$index < 0} {
        error "IR reference $requestedEntry is not available in $requestedLibrary"
    }
    $box selection clear 0 end
    $box selection set $index
    $box see $index
    _selectReferences
    set statusText "Opened $requestedEntry in $requestedLibrary"
}
proc ::GX::SpectralLibraryViewer::_open {{context {}}} {
    variable window; variable libraryId; variable entityId; variable searchText; variable mode
    variable reversed; variable sessionDataset; variable rankingDataset
    variable selectedIds; variable spectra; variable viewport; variable statusText
    package require Tk
    if {[winfo exists $window]} {
        raise $window
        focus -force $window
        _openContext $context
        return [dict create status opened window $window]
    }
    set libraryId ""; set entityId ""; set searchText ""; set mode overlay; set reversed 1
    set sessionDataset ""; set rankingDataset ""; set selectedIds {}; set spectra {}; set viewport {}
    set statusText "Ready"
    _restoreState
    set libraries [_libraries]
    if {$libraryId ni $libraries} { set libraryId [lindex $libraries 0] }
    if {![llength $libraries]} {
        set statusText "No IR reference library is installed. Select Install library to add one."
    }
    set entities [expr {$libraryId eq "" ? {} : [::GX::ReferenceLibraryAPIv1::listEntities $libraryId]}]
    if {$entityId ni $entities} { set entityId "" }
    toplevel $window
    wm title $window "GX-TXT | Scientific Spectral Library"
    wm geometry $window 1200x760
    wm minsize $window 1000 560
    ttk::frame $window.toolbar
    grid $window.toolbar -row 0 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 8
    ttk::label $window.toolbar.libraryLabel -text "Library"
    ttk::combobox $window.toolbar.library -textvariable ::GX::SpectralLibraryViewer::libraryId \
        -values $libraries -state readonly -width 35
    ttk::button $window.toolbar.install -text "Install library..." \
        -command ::GX::SpectralLibraryViewer::_installLibrary
    ttk::label $window.toolbar.modeLabel -text "Compare"
    ttk::combobox $window.toolbar.mode -textvariable ::GX::SpectralLibraryViewer::mode \
        -values {overlay top_bottom stacked difference ratio} -state readonly -width 12
    ttk::checkbutton $window.toolbar.reverse -text "Reverse X" \
        -variable ::GX::SpectralLibraryViewer::reversed -command ::GX::SpectralLibraryViewer::_modeChanged
    ttk::button $window.toolbar.reset -text "Reset zoom" -command ::GX::SpectralLibraryViewer::_resetRange
    ttk::button $window.toolbar.import -text "Import spectra..." -command ::GX::SpectralLibraryViewer::ImportUI::open
    foreach widget {libraryLabel library install modeLabel mode reverse reset import} {
        pack $window.toolbar.$widget -side left -padx 4
    }
    ttk::frame $window.left -width 270
    ttk::frame $window.right -width 290
    canvas $window.plot -background white -highlightthickness 0
    grid $window.left -row 1 -column 0 -sticky ns -padx {8 4} -pady 4
    grid $window.plot -row 1 -column 1 -sticky nsew -padx 4 -pady 4
    grid $window.right -row 1 -column 2 -sticky ns -padx {4 8} -pady 4
    grid rowconfigure $window 1 -weight 1
    grid columnconfigure $window 1 -weight 1
    pack propagate $window.left 0
    pack propagate $window.right 0
    ttk::label $window.left.title -text "Reference spectra"
    ttk::label $window.left.entityTitle -text "Entity / material"
    ttk::combobox $window.left.entity -textvariable ::GX::SpectralLibraryViewer::entityId \
        -values [linsert $entities 0 ""] -state readonly -width 28
    ttk::entry $window.left.search -textvariable ::GX::SpectralLibraryViewer::searchText
    ttk::button $window.left.find -text "Search" -command ::GX::SpectralLibraryViewer::_refreshSearch
    listbox $window.left.results -selectmode extended -exportselection 0 -width 32
    ttk::scrollbar $window.left.scroll -command [list $window.left.results yview]
    ttk::scrollbar $window.left.xscroll -orient horizontal -command [list $window.left.results xview]
    $window.left.results configure -yscrollcommand [list $window.left.scroll set] \
        -xscrollcommand [list $window.left.xscroll set]
    pack $window.left.title -side top -anchor w -pady 4
    pack $window.left.entityTitle -side top -anchor w -pady 2
    pack $window.left.entity -side top -fill x -pady 2
    pack $window.left.search -side top -fill x
    pack $window.left.find -side top -fill x -pady 4
    pack $window.left.xscroll -side bottom -fill x
    pack $window.left.scroll -side right -fill y
    pack $window.left.results -side left -fill both -expand 1
    ttk::label $window.right.sessionTitle -text "Session spectrum"
    set sessionSpectra [_sessionSpectra]
    if {$sessionDataset ni $sessionSpectra} {set sessionDataset ""}
    ttk::combobox $window.right.session -textvariable ::GX::SpectralLibraryViewer::sessionDataset \
        -values [linsert $sessionSpectra 0 ""] -state readonly -width 32
    ttk::label $window.right.rankingTitle -text "IR candidates"
    set rankingDatasets [_rankingDatasets]
    if {$rankingDataset ni $rankingDatasets} {set rankingDataset ""}
    ttk::combobox $window.right.rankingPick -textvariable ::GX::SpectralLibraryViewer::rankingDataset \
        -values [linsert $rankingDatasets 0 ""] -state readonly -width 32
    listbox $window.right.ranking -height 7 -width 34 -exportselection 0
    ttk::label $window.right.metadataTitle -text "Reference metadata and provenance" -wraplength 280
    ttk::button $window.right.maintain -text "Update / remove reference..." \
        -command ::GX::SpectralLibraryViewer::MaintenanceUI::open
    text $window.right.metadata -wrap word -width 33 -state disabled -font TkFixedFont
    foreach widget {sessionTitle session rankingTitle rankingPick ranking metadataTitle maintain metadata} {
        pack $window.right.$widget -side top -fill x -pady 3
    }
    pack $window.right.metadata -expand 1 -fill both
    ttk::label $window.status -textvariable ::GX::SpectralLibraryViewer::statusText -anchor w
    grid $window.status -row 2 -column 0 -columnspan 3 -sticky ew -padx 8 -pady 4
    bind $window.toolbar.library <<ComboboxSelected>> ::GX::SpectralLibraryViewer::_libraryChanged
    bind $window.left.entity <<ComboboxSelected>> ::GX::SpectralLibraryViewer::_entityChanged
    bind $window.toolbar.mode <<ComboboxSelected>> ::GX::SpectralLibraryViewer::_modeChanged
    bind $window.left.search <Return> ::GX::SpectralLibraryViewer::_refreshSearch
    bind $window.left.results <<ListboxSelect>> ::GX::SpectralLibraryViewer::_selectReferences
    bind $window.right.session <<ComboboxSelected>> ::GX::SpectralLibraryViewer::_sessionChanged
    bind $window.right.rankingPick <<ComboboxSelected>> ::GX::SpectralLibraryViewer::_rankingChanged
    bind $window.right.ranking <<ListboxSelect>> ::GX::SpectralLibraryViewer::_rankingSelected
    bind $window.plot <Configure> ::GX::SpectralLibraryViewer::_draw
    bind $window.plot <MouseWheel> {::GX::SpectralLibraryViewer::_zoom %x %D}
    bind $window.plot <Button-4> {::GX::SpectralLibraryViewer::_zoom %x 1}
    bind $window.plot <Button-5> {::GX::SpectralLibraryViewer::_zoom %x -1}
    bind $window.plot <ButtonPress-1> {::GX::SpectralLibraryViewer::_dragStart %x}
    bind $window.plot <B1-Motion> {::GX::SpectralLibraryViewer::_dragMove %x}
    bind $window.plot <ButtonRelease-1> ::GX::SpectralLibraryViewer::_saveState
    bind $window.plot <Motion> {::GX::SpectralLibraryViewer::_cursor %x}
    _refreshSearch
    if {$rankingDataset ne ""} { catch {_readRanking} }
    if {[llength $selectedIds]} {
        set savedViewport $viewport
        set box $window.left.results
        $box selection clear 0 end
        for {set i 0} {$i < [$box size]} {incr i} {
            if {[$box get $i] in $selectedIds} { $box selection set $i }
        }
        _selectReferences
        set viewport $savedViewport
    }
    update idletasks
    _draw
    _saveState
    _openContext $context
    return [dict create status opened window $window]
}
proc ::GX::SpectralLibraryViewer::viewerDispatch {action scene} {
    switch -- $action {
        open - rerender {
            set context {}
            if {[dict exists $scene open_context]} {set context [dict get $scene open_context]}
            return [_open $context]
        }
        default { error "Unsupported Scientific Spectral Library Viewer action '$action'" }
    }
}

::GX::viewerBackendRegister spectral_library_tk ::GX::SpectralLibraryViewer::viewerDispatch
source [file join [file dirname [info script]] spectrum_import_ui_v1.tcl]
source [file join [file dirname [info script]] spectral_library_maintenance_ui_v1.tcl]
