# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::refreshGraphs_before_graph_workflow {} {
    variable ui
    variable currentSession
    variable graphUse
    if {![info exists ui(graphTree)] || ![winfo exists $ui(graphTree)]} return
    if {$currentSession ne ""} {
        set marker [file join $currentSession metadata .script_bridge_graph_update]
        if {[file isfile $marker]} {
            loadManifest [file join $currentSession metadata manifest.ini]
            file delete -- $marker
        }
    }
    set t $ui(graphTree)

    # Conserva ordine, spunte e grafico corrente durante un refresh/rerender.
    set oldOrder {}
    set oldUse [dict create]
    set selectedPath ""
    set oldSel [$t selection]
    if {[llength $oldSel] == 1 && [info exists ui(graphPath,[lindex $oldSel 0])]} {
        set selectedPath $ui(graphPath,[lindex $oldSel 0])
    }
    set analysisRoot [expr {$currentSession eq "" ? "" : [file normalize [file join $currentSession analysis]]}]
    if {$selectedPath ne "" && ($analysisRoot eq "" ||
        [string first "${analysisRoot}/" [file normalize $selectedPath]] != 0)} {
        set selectedPath ""
        clearGraphPreview
    }
    foreach id [$t children {}] {
        if {[info exists ui(graphPath,$id)]} {
            set pth $ui(graphPath,$id)
            if {$analysisRoot ne "" && [string first "${analysisRoot}/" [file normalize $pth]] == 0} {
                lappend oldOrder $pth
                dict set oldUse $pth [expr {[info exists graphUse($id)] ? $graphUse($id) : 1}]
            }
        }
    }

    foreach id [$t children {}] { $t delete $id }
    array unset graphUse *
    foreach k [array names ui "graphPath,*"] { unset ui($k) }
    if {$currentSession eq ""} { clearGraphPreview; return }

    set discovered {}
    set providerAliases [::GX::graphWorkflowProviderAliasPaths $currentSession]
    set root [file join $currentSession analysis]
    foreach f [walkFiles $root] {
        if {![string equal -nocase [file extension $f] ".png"]} continue
        if {[file normalize $f] in $providerAliases} continue
        if {[plotVariantPathCandidate $f] && [llength [plotVariantInfoForPath $f]] != 3} continue
        # Graph Provider API: a stale PNG from a previously enabled native
        # graph is hidden when that graph offering is no longer part of the
        # experiment. The artifact remains on disk and can be re-enabled.
        set ngi [nativeGraphInfoForPath $f]
        if {[llength $ngi] == 2 && [llength [info commands ::GX::moduleGraphIsEnabled]]} {
            lassign $ngi mid gid
            set variant [plotVariantInfoForPath $f]
            if {[llength $variant] == 3} {
                if {![plotVariantField $mid $gid [lindex $variant 2] enabled 1]} continue
            } elseif {![moduleGraphIsEnabled $mid $gid]} { continue }
        }
        lappend discovered $f
    }
    set discovered [lsort -unique $discovered]
    set files {}
    foreach f $oldOrder {
        if {[lsearch -exact $discovered $f] >= 0 && [lsearch -exact $files $f] < 0} { lappend files $f }
    }
    foreach f $discovered {
        if {[lsearch -exact $files $f] < 0} { lappend files $f }
    }

    set n 0
    set selectedId ""
    foreach f $files {
        incr n
        set id "g$n"
        set use [expr {[dict exists $oldUse $f] ? [dict get $oldUse $f] : 1}]
        if {![dict exists $oldUse $f] && [::GX::PlotClone::infoForPath $f] ne ""} {set use [::GX::PlotClone::useForPath $f]}
        set graphUse($id) $use
        set ui(graphPath,$id) $f
        set rel [string range $f [expr {[string length $currentSession]+1}] end]
        set module [lindex [file split $rel] 1]
        $t insert {} end -id $id -values [list [expr {$use ? "YES" : "NO"}] $module [graphDisplayTitle $f]]
        if {$f eq $selectedPath} { set selectedId $id }
    }
    if {$n > 0} {
        if {$selectedId eq ""} { set selectedId g1 }
        $t selection set $selectedId
        $t see $selectedId
        previewGraph
    } else {
        clearGraphPreview
    }
}
proc ::GX::refreshGraphs {} { ::GX::refreshGraphs_before_graph_workflow }

proc ::GX::graphDisplayTitle {path} {
    set clone [::GX::PlotClone::infoForPath $path]
    if {[dict exists $clone clone.title] && [string trim [dict get $clone clone.title]] ne ""} {return [dict get $clone clone.title]}
    set identity [graphUseIdentityForPath $path]
    if {[llength $identity] != 3} {return [file rootname [file tail $path]]}
    lassign $identity moduleId graphId variantId
    if {$variantId ne ""} {
        set variantTitle [string trim [plotVariantField $moduleId $graphId $variantId title ""]]
        if {$variantTitle ne ""} {return $variantTitle}
        set rendered ""
        if {[lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] title] >= 0} {set rendered [plotVariantConfigGet $moduleId $graphId $variantId title]}
        if {[string trim $rendered] ne "" && ![string equal -nocase $rendered auto]} {return $rendered}
        return [plotVariantField $moduleId $graphId $variantId title [file rootname [file tail $path]]]
    }
    if {[lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] title] >= 0} {
        set rendered [expr {[info exists ::GX::modulePlotCfg($moduleId,$graphId,title)] ? $::GX::modulePlotCfg($moduleId,$graphId,title) : ""}]
        if {[string trim $rendered] ne "" && ![string equal -nocase $rendered auto]} {return $rendered}
    }
    return [moduleGraphField $moduleId $graphId name [file rootname [file tail $path]]]
}

proc ::GX::graphPresentationDialog {} {
    variable ui
    set path [currentGraphPath]
    if {$path eq ""} return
    set identity [graphUseIdentityForPath $path]
    if {[llength $identity] != 3} {tk_messageBox -icon info -message "This image has no editable graph provider."; return}
    lassign $identity moduleId graphId variantId
    set key [graphKeyForPath $path]
    set fields {title x_label y_label y2_label}
    if {[lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] z_label] >= 0} {set fields {title x_label y_label z_label}}
    set w .graphpresentation
    catch {destroy $w}; toplevel $w; wm title $w "Title and labels — [graphDisplayTitle $path]"; wm transient $w .
    set ui(graphPresentationIdentity) $identity
    set ui(graphPresentationPath) $path
    set ui(graphPresentationFields) $fields
    set row 0
    foreach field $fields {
        if {$field ne "title" && [lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] $field] < 0 && $moduleId eq "plot.dataset"} continue
        set value ""
        if {[lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] $field] >= 0} {
            if {$variantId eq ""} {set value [expr {[info exists ::GX::modulePlotCfg($moduleId,$graphId,$field)] ? $::GX::modulePlotCfg($moduleId,$graphId,$field) : [moduleGraphConfigField $moduleId $graphId $field default ""]}]} else {set value [plotVariantConfigGet $moduleId $graphId $variantId $field]}
        } elseif {[info exists ::GX::axisOverride($key,$field)]} {set value $::GX::axisOverride($key,$field)}
        if {[string equal -nocase $value auto]} {set value ""}
        set ui(graphPresentation,$field) $value
        set label [dict get [dict create title "Graph title" x_label "X / bottom label" y_label "Y Left label" y2_label "Y Right label" z_label "Z label"] $field]
        ttk::label $w.l$row -text $label
        ttk::entry $w.e$row -textvariable ::GX::ui(graphPresentation,$field) -width 58
        grid $w.l$row -row $row -column 0 -sticky w -padx 8 -pady 4
        grid $w.e$row -row $row -column 1 -sticky ew -padx 8 -pady 4
        incr row
    }
    set ui(graphPresentationPanels) {}
    if {$moduleId eq "plot.dataset"} {
        modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
        set ref [::GX::PlotDatasetAPIv2::plotRefForArtifact $path]
        if {$ref ne ""} {
            set panelIds [::GX::PlotDatasetAPIv2::panelIds $ref]
            if {[llength $panelIds] > 1} {
                set ui(graphPresentationPanels) $panelIds
                foreach panelId $panelIds {
                    set panel [::GX::PlotDatasetAPIv2::panelInfo $ref $panelId]
                    set ui(graphPresentationPanel,$panelId,title) [expr {[dict exists $panel title] ? [dict get $panel title] : ""}]
                    foreach {axis fieldName label} {y_left y "Y Left" y_right y2 "Y Right"} {
                        set ui(graphPresentationPanel,$panelId,$axis) [expr {[dict exists $panel axes $axis label] ? [dict get $panel axes $axis label] : ""}]
                    }
                    ttk::separator $w.sep$row -orient horizontal;grid $w.sep$row -row $row -column 0 -columnspan 2 -sticky ew -pady 5;incr row
                    foreach {axis label} {title "Panel title" y_left "Panel Y Left label" y_right "Panel Y Right label"} {
                        ttk::label $w.l$row -text "$panelId — $label"
                        ttk::entry $w.e$row -textvariable ::GX::ui(graphPresentationPanel,$panelId,$axis) -width 58
                        grid $w.l$row -row $row -column 0 -sticky w -padx 8 -pady 3
                        grid $w.e$row -row $row -column 1 -sticky ew -padx 8 -pady 3
                        incr row
                    }
                }
            }
        }
    }
    ttk::label $w.hint -text "Leave a field empty to inherit its provider default.";grid $w.hint -row $row -column 0 -columnspan 2 -sticky w -padx 8;incr row
    ttk::frame $w.buttons;ttk::button $w.buttons.save -text Save -command ::GX::graphPresentationSave;ttk::button $w.buttons.cancel -text Cancel -command [list destroy $w]
    pack $w.buttons.save $w.buttons.cancel -side left -padx 5
    grid $w.buttons -row $row -column 1 -sticky e -padx 8 -pady 8
    grid columnconfigure $w 1 -weight 1
}

proc ::GX::graphPresentationSave {} {
    variable ui
    variable axisOverride
    variable modulePlotCfg
    lassign $ui(graphPresentationIdentity) moduleId graphId variantId
    set key [graphKeyForPath $ui(graphPresentationPath)]
    foreach field $ui(graphPresentationFields) {
        set value [string trim $ui(graphPresentation,$field)]
        if {[regexp {[\r\n]} $value]} {tk_messageBox -icon error -message "Titles and labels must be single-line.";return}
        if {[lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] $field] >= 0} {
            if {$variantId eq ""} {set modulePlotCfg($moduleId,$graphId,$field) [expr {$value eq "" ? "auto" : $value}]} else {plotVariantConfigSet $moduleId $graphId $variantId $field [expr {$value eq "" ? "auto" : $value}]}
        } else {set axisOverride($key,$field) $value}
    }
    if {$variantId ne ""} {plotVariantSet $moduleId $graphId $variantId [dict create title [expr {[string trim $ui(graphPresentation,title)] eq "" ? "Plot $variantId" : $ui(graphPresentation,title)}]]}
    if {$moduleId eq "plot.dataset" && [llength $ui(graphPresentationPanels)]} {
        set ref [::GX::PlotDatasetAPIv2::plotRefForArtifact $ui(graphPresentationPath)]
        foreach panelId $ui(graphPresentationPanels) {
            ::GX::PlotDatasetAPIv2::setPanelTitle $ref $panelId $ui(graphPresentationPanel,$panelId,title)
            set panel [::GX::PlotDatasetAPIv2::panelInfo $ref $panelId]
            foreach axis {y_left y_right} {
                set fields [expr {[dict exists $panel axes $axis] ? [dict get $panel axes $axis] : [dict create]}]
                dict set fields label [string trim $ui(graphPresentationPanel,$panelId,$axis)]
                ::GX::PlotDatasetAPIv2::setPanelAxis $ref $panelId $axis $fields
            }
        }
    }
    if {$::GX::currentSession ne ""} {writeManifest [file join $::GX::currentSession metadata manifest.ini]}
    destroy .graphpresentation
    refreshGraphs
}

proc ::GX::graphInfoDialog {} {
    set path [currentGraphPath]
    if {$path eq ""} return
    set identity [graphUseIdentityForPath $path]
    set normalized [file normalize $path]
    set relative $normalized
    if {$::GX::currentSession ne ""} {
        set prefix "[file normalize $::GX::currentSession]/"
        if {[string first $prefix $normalized] == 0} {set relative [string range $normalized [string length $prefix] end]}
    }
    set lines [list "Title: [graphDisplayTitle $path]" "Artifact filename: [file tail $path]" "Session path: $relative" "Absolute path: $normalized" "Image bytes: [file size $path]"]
    if {[llength $identity] == 3} {
        lassign $identity moduleId graphId variantId
        lappend lines "Module: $moduleId" "Graph: $graphId" "Variant: [expr {$variantId eq "" ? "base" : $variantId}]" "Type: [moduleGraphField $moduleId $graphId name $graphId]" "Provider identity: $moduleId / $graphId"
        if {$variantId ne ""} {lappend lines "Variant title: [plotVariantField $moduleId $graphId $variantId title ""]"}
        set kind [expr {[lsearch -exact [moduleGraphConfigKeys $moduleId $graphId] z_label] >= 0 ? "3D" : "2D"}]
        if {$moduleId eq "plot.dataset"} {
            modulePublicApiActivate plot.dataset PLOT_DATASET_API_v3
            set ref [::GX::PlotDatasetAPIv2::plotRefForArtifact $path]
            if {$ref ne ""} {
                set panelIds [::GX::PlotDatasetAPIv2::panelIds $ref]
                if {[llength $panelIds] > 1} {set kind "multi-panel 2D"}
                foreach series [::GX::graphSeriesList $moduleId $graphId $variantId 1] {
                    if {[dict exists $series axis] && [dict get $series axis] eq "right" && $kind eq "2D"} {set kind "dual-Y 2D"}
                    lappend lines "Series: [dict get $series series_id] — Dataset [dict get $series dataset_id]"
                }
                lappend lines "Panels: [llength $panelIds]"
                foreach panelId $panelIds {
                    set panel [::GX::PlotDatasetAPIv2::panelInfo $ref $panelId]
                    lappend lines "Panel $panelId: [expr {[dict exists $panel title] ? [dict get $panel title] : ""}]"
                    if {[dict exists $panel series]} {lappend lines "  Series: [llength [dict get $panel series]]"}
                }
            }
        }
        lappend lines "Dimensionality / plot kind: $kind"
    }
    set metadata [plotMetadataDictForPath $path]
    if {![catch {dict size $metadata}]} {dict for {field value} $metadata {lappend lines "$field: $value"}}
    if {[llength [info commands ::GX::graphResourceRefForPath]]} {
        if {![catch {set graphRef [graphResourceRefForPath $path]}]} {
            lappend lines "Graph Notes: [expr {[graphNotesExists $graphRef] ? "present" : "none"}]"
            set userMetadata [graphMetadataRead $graphRef]
            dict for {field value} $userMetadata {lappend lines "graph_metadata.$field: $value"}
        }
    }
    set document [annotationLoadDocument $path]
    if {[dict exists $document objects]} {lappend lines "Annotations: [llength [dict get $document objects]]"}
    set w .graphinfo;catch {destroy $w};toplevel $w;wm title $w "Graph info"
    text $w.text -width 84 -height 28 -wrap word
    $w.text insert end [join $lines "\n"];$w.text configure -state disabled
    ttk::button $w.close -text Close -command [list destroy $w]
    pack $w.text -fill both -expand 1 -padx 8 -pady 8;pack $w.close -anchor e -padx 8 -pady 8
}

proc ::GX::clearGraphPreview {} {
    variable ui
    foreach key {graphPreviewSourcePath graphPreviewLoadSig graphPreviewFitW graphPreviewFitH} {
        catch {unset ui($key)}
    }
    set ui(graphInfo) "No graph selected."
    if {[info exists ui(graphPreview)] && [winfo exists $ui(graphPreview)]} {
        $ui(graphPreview) delete all
    }
    catch {image delete ::GX::graphPreviewPhoto}
    catch {image delete ::GX::graphPreviewSource}
}

proc ::GX::deleteCurrentGraph {} {
    set path [currentGraphPath]
    if {$path eq ""} { return }
    if {[tk_messageBox -type yesno -icon question -title "Delete plot" \
            -message "Delete this plot and its Session-owned presentation and render artifacts?"] ne "yes"} { return }
    if {[catch {graphLifecycleDelete $path} reason]} {
        tk_messageBox -icon error -title "Delete plot" -message $reason
        return
    }
    refreshGraphs
}

proc ::GX::toggleGraph_before_graph_workflow {} {
    variable ui
    variable graphUse
    set t $ui(graphTree); set sel [$t selection]; if {[llength $sel] != 1} return
    set id [lindex $sel 0]; set graphUse($id) [expr {!$graphUse($id)}]
    set vals [$t item $id -values]; lset vals 0 [expr {$graphUse($id) ? "YES" : "NO"}]; $t item $id -values $vals
}
proc ::GX::toggleGraph {} { ::GX::toggleGraph_before_graph_workflow }

proc ::GX::setAllGraphs_before_graph_workflow {v} {
    variable ui; variable graphUse
    set t $ui(graphTree)
    foreach id [$t children {}] { set graphUse($id) $v; set vals [$t item $id -values]; lset vals 0 [expr {$v ? "YES" : "NO"}]; $t item $id -values $vals }
}
proc ::GX::setAllGraphs {v} { ::GX::setAllGraphs_before_graph_workflow $v }

proc ::GX::moveGraph {delta} {
    variable ui
    set t $ui(graphTree); set sel [$t selection]; if {[llength $sel] != 1} return
    set id [lindex $sel 0]; set kids [$t children {}]; set idx [lsearch -exact $kids $id]; set ni [expr {$idx+$delta}]
    if {$ni < 0 || $ni >= [llength $kids]} return
    $t move $id {} $ni; $t selection set $id
}

proc ::GX::previewGraph_annotation_base {} {
    variable ui
    if {![info exists ui(graphTree)]} return
    set t $ui(graphTree); set sel [$t selection]; if {[llength $sel] != 1} return
    set id [lindex $sel 0]; if {![info exists ui(graphPath,$id)]} return
    set src $ui(graphPath,$id); if {![file isfile $src]} return

    # Conserva il file sorgente reale. La preview viene sempre ricostruita da
    # questo PNG, mai da una miniatura precedente.
    set ui(graphPreviewSourcePath) $src
    loadGraphPreviewPhoto $src
    set mt [clock format [file mtime $src] -format "%Y-%m-%d %H:%M:%S"]
    set ui(graphInfo) "$src\n[file size $src] byte | session PNG modified: $mt\n[legendEffectiveDescription $src]"
}

proc ::GX::loadGraphPreviewPhoto {src} {
    variable ui
    variable currentSession
    if {![file isfile $src]} return
    if {$currentSession eq ""} return
    set analysisRoot [file normalize [file join $currentSession analysis]]
    if {[string first "${analysisRoot}/" [file normalize $src]] != 0} return
    if {![info exists ui(graphPreview)] || ![winfo exists $ui(graphPreview)]} return
    if {[info exists ui(graphPreviewBusy)] && $ui(graphPreviewBusy)} return

    set c $ui(graphPreview)
    set cw [winfo width $c]
    set chh [winfo height $c]
    # Durante la costruzione iniziale il canvas puo' essere ancora 1x1.
    # Non forziamo update/update idletasks: potrebbe generare Configure ricorsivi.
    if {$cw < 40 || $chh < 40} {
        scheduleGraphPreviewFit
        return
    }
    set maxw [expr {max(40,$cw-12)}]
    set maxh [expr {max(40,$chh-12)}]
    set mtime [file mtime $src]
    set fsize [file size $src]
    set sig "$src|$mtime|$fsize|${maxw}x${maxh}"
    if {[info exists ui(graphPreviewLoadSig)] && $ui(graphPreviewLoadSig) eq $sig && ![catch {image width ::GX::graphPreviewPhoto}]} {
        drawGraphPreview
        return
    }

    set ui(graphPreviewBusy) 1
    set ok 0
    set err ""
    try {
        set baseDir $currentSession
        if {$baseDir eq "" || ![file isdirectory $baseDir]} { set baseDir [file dirname $src] }
        set pdir [file join $baseDir report previews]
        catch {file mkdir $pdir}
        if {![file isdirectory $pdir]} { set pdir [file dirname $src] }
        set stem [format %08x [zlib crc32 $src]]
        set prev [file join $pdir "preview_${stem}.png"]
        set usedMagick 0
        if {![catch {set magick [runtimeToolResolve magick]}] && $magick ne ""} {
            set tmp "${prev}.tmp.[pid].png"
            catch {file delete -force $tmp}
            # '>' = solo riduzione. Il rapporto d'aspetto viene mantenuto e
            # non viene mai eseguito crop.
            set geom "${maxw}x${maxh}>"
            if {![catch {exec $magick $src -resize $geom $tmp} magerr] && [file isfile $tmp]} {
                catch {file delete -force $prev}
                file rename -force $tmp $prev
                set usedMagick 1
            } else {
                catch {file delete -force $tmp}
            }
        }

        catch {image delete ::GX::graphPreviewPhoto}
        if {$usedMagick} {
            if {[catch {image create photo ::GX::graphPreviewPhoto -file $prev} err]} {
                error $err
            }
            # Difesa ulteriore: una preview non deve mai eccedere il canvas.
            set pw [image width ::GX::graphPreviewPhoto]
            set ph [image height ::GX::graphPreviewPhoto]
            if {$pw > $maxw || $ph > $maxh} {
                catch {image delete ::GX::graphPreviewPhoto}
                set usedMagick 0
            }
        }

        if {!$usedMagick} {
            catch {image delete ::GX::graphPreviewSource}
            if {[catch {image create photo ::GX::graphPreviewSource -file $src} err]} {
                error $err
            }
            set iw [image width ::GX::graphPreviewSource]
            set ih [image height ::GX::graphPreviewSource]
            set sx [expr {int(ceil($iw/double($maxw)))}]
            set sy [expr {int(ceil($ih/double($maxh)))}]
            set sub [expr {max(1,max($sx,$sy))}]
            image create photo ::GX::graphPreviewPhoto
            ::GX::graphPreviewPhoto copy ::GX::graphPreviewSource -subsample $sub $sub
            catch {image delete ::GX::graphPreviewSource}
        }

        set ui(graphPreviewFitW) $maxw
        set ui(graphPreviewFitH) $maxh
        set ui(graphPreviewLoadSig) $sig
        set ok 1
    } on error {e opts} {
        set err $e
    } finally {
        set ui(graphPreviewBusy) 0
    }
    if {!$ok} {
        set ui(graphInfo) "Unable to display PNG: $err"
        return
    }
    drawGraphPreview
}

proc ::GX::onGraphPreviewConfigure {w h} {
    variable ui
    # <Configure> puo' arrivare molte volte durante un resize. Registriamo la
    # nuova dimensione ma ricalcoliamo la miniatura una sola volta a finestra
    # stabilizzata. Nessun update/update idletasks e nessuna ricorsione.
    if {$w < 2 || $h < 2} return
    set oldw [expr {[info exists ui(graphPreviewCanvasW)] ? $ui(graphPreviewCanvasW) : -1}]
    set oldh [expr {[info exists ui(graphPreviewCanvasH)] ? $ui(graphPreviewCanvasH) : -1}]
    set ui(graphPreviewCanvasW) $w
    set ui(graphPreviewCanvasH) $h
    drawGraphPreview
    if {$w != $oldw || $h != $oldh} { scheduleGraphPreviewFit }
}

proc ::GX::scheduleGraphPreviewFit {} {
    variable ui
    if {[info exists ui(graphPreviewFitAfter)] && $ui(graphPreviewFitAfter) ne ""} {
        catch {after cancel $ui(graphPreviewFitAfter)}
    }
    set ui(graphPreviewFitAfter) [after 300 ::GX::refreshGraphPreviewFit]
}

proc ::GX::refreshGraphPreviewFit {} {
    variable ui
    set ui(graphPreviewFitAfter) ""
    if {![info exists ui(graphPreview)] || ![winfo exists $ui(graphPreview)]} return
    if {[info exists ui(graphPreviewBusy)] && $ui(graphPreviewBusy)} return
    if {![info exists ui(graphPreviewSourcePath)]} return
    set src $ui(graphPreviewSourcePath)
    if {![file isfile $src]} return

    set c $ui(graphPreview)
    set cw [winfo width $c]; set chh [winfo height $c]
    if {$cw < 40 || $chh < 40} return
    set nw [expr {max(40,$cw-12)}]
    set nh [expr {max(40,$chh-12)}]
    set ow [expr {[info exists ui(graphPreviewFitW)] ? $ui(graphPreviewFitW) : -1}]
    set oh [expr {[info exists ui(graphPreviewFitH)] ? $ui(graphPreviewFitH) : -1}]
    # Soglia minima per evitare ricalcoli inutili causati da oscillazioni di
    # uno/due pixel del geometry manager.
    if {abs($nw-$ow) >= 6 || abs($nh-$oh) >= 6} {
        loadGraphPreviewPhoto $src
    } else {
        drawGraphPreview
    }
}

proc ::GX::openCurrentGraphWindow {} {
    variable ui
    set p [currentGraphPath]
    if {$p eq "" || ![file isfile $p]} {
        tk_messageBox -message "Select an existing plot."
        return
    }
    catch {destroy .graphfull}
    set ui(graphFullDestroyed) 0
    set ui(graphFullPath) $p
    set ui(graphFullAnnotations) 1
    set ui(graphFullScale) 1.0
    set ui(graphFullSelection) {}
    set w .graphfull
    toplevel $w
    wm title $w "Session PNG - [file tail $p]"
    set sw [winfo screenwidth .]; set sh [winfo screenheight .]
    set ww [expr {int($sw*0.94)}]; set wh [expr {int($sh*0.88)}]
    wm geometry $w "${ww}x${wh}+20+30"
    grid columnconfigure $w 0 -weight 1
    grid rowconfigure $w 1 -weight 1

    ttk::frame $w.top
    ttk::button $w.top.reload -text Reload -command ::GX::reloadGraphWindow
    ttk::checkbutton $w.top.annotations -text "Show annotations" -variable ::GX::ui(graphFullAnnotations) -command ::GX::reloadGraphWindow
    ttk::button $w.top.fit -text Fit -command ::GX::graphFullFit
    ttk::button $w.top.zi -text "Zoom +" -command {::GX::graphFullZoom 1.25}
    ttk::button $w.top.zo -text "Zoom -" -command {::GX::graphFullZoom 0.8}
    ttk::button $w.top.reset -text Reset -command {::GX::graphFullShow 1.0}
    ttk::button $w.top.fitarea -text "Fit area" -command ::GX::graphFullFitArea
    ttk::button $w.top.print -text Print -command ::GX::graphFullPrint
    ttk::button $w.top.copy -text "Copy graph" -command {::GX::graphFullCopy 0}
    ttk::button $w.top.copyarea -text "Copy area" -command {::GX::graphFullCopy 1}
    ttk::button $w.top.save -text "Save image..." -command {::GX::graphFullSave 0}
    ttk::button $w.top.savearea -text "Save selected area..." -command {::GX::graphFullSave 1}
    ttk::button $w.top.notes -text "Notes..." -command [list ::GX::graphNotesOpenForPath $p]
    ttk::button $w.top.close -text "Close" -command [list destroy $w]
    pack $w.top.reload $w.top.annotations $w.top.fit $w.top.zi $w.top.zo $w.top.reset $w.top.fitarea $w.top.print $w.top.copy $w.top.copyarea $w.top.save $w.top.savearea $w.top.notes $w.top.close -side left -padx 3
    grid $w.top -row 0 -column 0 -columnspan 2 -sticky ew -padx 5 -pady 5

    canvas $w.c -background #d9d9d9 -highlightthickness 0 -xscrollcommand [list $w.sx set] -yscrollcommand [list $w.sy set]
    ttk::scrollbar $w.sx -orient horizontal -command [list $w.c xview]
    ttk::scrollbar $w.sy -orient vertical -command [list $w.c yview]
    grid $w.c -row 1 -column 0 -sticky nsew
    grid $w.sy -row 1 -column 1 -sticky ns
    grid $w.sx -row 2 -column 0 -sticky ew
    ttk::label $w.info -textvariable ::GX::ui(graphFullInfo) -justify left -wraplength 1500
    grid $w.info -row 3 -column 0 -columnspan 2 -sticky ew -padx 7 -pady 5
    set ui(graphFullCanvas) $w.c
    bind $w.c <ButtonPress-1> {::GX::graphFullSelectStart %x %y}
    bind $w.c <B1-Motion> {::GX::graphFullSelectDrag %x %y}
    bind $w.c <ButtonRelease-1> {::GX::graphFullSelectEnd %x %y}
    bind $w <Destroy> {::GX::graphFullOnDestroy %W}
    reloadGraphWindow
}

proc ::GX::graphFullOnDestroy {widget} {
    variable ui
    if {$widget ne ".graphfull"} return
    if {[info exists ui(graphFullDestroyed)] && $ui(graphFullDestroyed)} return
    set ui(graphFullDestroyed) 1
    graphFullCleanup
}

proc ::GX::graphFullTempPath {} {
    set fd [file tempfile path [file join /tmp gxtxt_graph_viewer_]]
    close $fd
    file delete -- $path
    return "${path}.png"
}

proc ::GX::graphFullCleanup {} {
    variable ui
    foreach key {graphFullComposition graphFullDisplay graphFullCrop graphFullPdf} {
        if {[info exists ui($key)] && $ui($key) ne ""} {catch {file delete -- $ui($key)}; unset ui($key)}
    }
    catch {image delete ::GX::graphFullPhoto}
}

proc ::GX::reloadGraphWindow {} {
    variable ui
    if {![info exists ui(graphFullPath)]} return
    set p $ui(graphFullPath)
    if {![file isfile $p]} {
        set ui(graphFullInfo) "Il PNG non esiste piu': $p"
        return
    }
    if {![info exists ui(graphFullCanvas)] || ![winfo exists $ui(graphFullCanvas)]} return
    graphFullCleanup
    set source $p
    if {$ui(graphFullAnnotations) && [file isfile [annotationPathForPlot $p]]} {
        set source [graphFullTempPath]
        if {[catch {annotationRenderTo $p $source} err]} {
            set ui(graphFullInfo) "Unable to compose annotations: $err"
            return
        }
        set ui(graphFullComposition) $source
    }
    set ui(graphFullSource) $source
    if {[catch {set ui(graphFullDimensions) [annotationImageDimensions $source]} err]} {
        set ui(graphFullInfo) "Unable to inspect the graph: $err"
        return
    }
    set ui(graphFullSelection) {}
    graphFullShow $ui(graphFullScale)
}

proc ::GX::graphFullShow {scale} {
    variable ui
    if {![winfo exists .graphfull] || ![info exists ui(graphFullSource)]} return
    if {![string is double -strict $scale] || $scale <= 0} return
    set scale [expr {min(8.0,max(0.05,$scale))}]
    set ui(graphFullScale) $scale
    if {[info exists ui(graphFullDisplay)]} {catch {file delete -- $ui(graphFullDisplay)}; unset ui(graphFullDisplay)}
    set displayed $ui(graphFullSource)
    if {abs($scale-1.0) > 0.001} {
        set displayed [graphFullTempPath]
        if {[catch {exec [runtimeToolRequired python] [file join $::GX::scriptDir app graph_viewer_raster.py] scale $ui(graphFullSource) $displayed $scale} err]} {
            set ui(graphFullInfo) "Unable to scale graph: $err"; return
        }
        set ui(graphFullDisplay) $displayed
    }
    catch {image delete ::GX::graphFullPhoto}
    if {[catch {image create photo ::GX::graphFullPhoto -file $displayed} err]} {
        set ui(graphFullInfo) "Unable to read graph: $err"; return
    }
    set c $ui(graphFullCanvas)
    $c delete all
    set iw [image width ::GX::graphFullPhoto]; set ih [image height ::GX::graphFullPhoto]
    $c create image 0 0 -anchor nw -image ::GX::graphFullPhoto
    $c configure -scrollregion [list 0 0 $iw $ih]
    graphFullDrawSelection
    set p $ui(graphFullPath)
    set mt [clock format [file mtime $p] -format "%Y-%m-%d %H:%M:%S"]
    set ui(graphFullInfo) "$p\nOriginal: [join $ui(graphFullDimensions) { x }] px | view: [format %.0f [expr {$scale*100}]]% | annotations: [expr {$ui(graphFullAnnotations) ? {shown} : {hidden}}] | modified: $mt"
}

proc ::GX::graphFullFit {} {
    variable ui
    update idletasks
    lassign $ui(graphFullDimensions) iw ih
    if {$iw <= 0 || $ih <= 0} return
    graphFullShow [expr {min(double([winfo width $ui(graphFullCanvas)])/$iw,double([winfo height $ui(graphFullCanvas)])/$ih)}]
}
proc ::GX::graphFullZoom {factor} {
    variable ui
    graphFullShow [expr {$ui(graphFullScale)*$factor}]
}
proc ::GX::graphFullSelectPoint {x y} {
    variable ui
    set c $ui(graphFullCanvas)
    lassign $ui(graphFullDimensions) iw ih
    set s $ui(graphFullScale)
    return [list [expr {min($iw,max(0,[$c canvasx $x]/$s))}] [expr {min($ih,max(0,[$c canvasy $y]/$s))}]]
}
proc ::GX::graphFullSelectStart {x y} {
    variable ui
    set ui(graphFullSelection) [concat [graphFullSelectPoint $x $y] [graphFullSelectPoint $x $y]]
    graphFullDrawSelection
}
proc ::GX::graphFullSelectDrag {x y} {
    variable ui
    if {[llength $ui(graphFullSelection)] != 4} return
    set ui(graphFullSelection) [concat [lrange $ui(graphFullSelection) 0 1] [graphFullSelectPoint $x $y]]
    graphFullDrawSelection
}
proc ::GX::graphFullSelectEnd {x y} {graphFullSelectDrag $x $y}
proc ::GX::graphFullDrawSelection {} {
    variable ui
    set c $ui(graphFullCanvas)
    $c delete graphFullSelection
    if {[llength $ui(graphFullSelection)] != 4} return
    lassign $ui(graphFullSelection) x0 y0 x1 y1
    set s $ui(graphFullScale)
    $c create rectangle [expr {$x0*$s}] [expr {$y0*$s}] [expr {$x1*$s}] [expr {$y1*$s}] -outline #e02020 -width 2 -dash {5 3} -tags graphFullSelection
}
proc ::GX::graphFullSelectionBox {} {
    variable ui
    if {[llength $ui(graphFullSelection)] != 4} {error "Select an area first."}
    lassign $ui(graphFullSelection) x0 y0 x1 y1
    set box [list [expr {int(floor(min($x0,$x1)))}] [expr {int(floor(min($y0,$y1)))}] [expr {int(ceil(max($x0,$x1)))}] [expr {int(ceil(max($y0,$y1)))}]]
    lassign $box a b c d
    if {$a >= $c || $b >= $d} {error "Select an area with nonzero width and height."}
    return $box
}
proc ::GX::graphFullFitArea {} {
    variable ui
    if {[catch {lassign [graphFullSelectionBox] x0 y0 x1 y1} err]} {tk_messageBox -parent .graphfull -icon error -message $err; return}
    update idletasks
    set c $ui(graphFullCanvas)
    set scale [expr {min(double([winfo width $c])/($x1-$x0),double([winfo height $c])/($y1-$y0))}]
    graphFullShow $scale
    lassign $ui(graphFullDimensions) iw ih
    $c xview moveto [expr {double($x0)/$iw}]
    $c yview moveto [expr {double($y0)/$ih}]
}
proc ::GX::graphFullCopy {areaOnly} {
    variable ui
    if {[catch {
        set path [graphFullImagePath $areaOnly]
        if {[tk windowingsystem] eq "x11"} {
            graphFullClipboardX11 $path
        } else {
            set fd [open $path rb]; fconfigure $fd -translation binary -encoding binary
            try {set png [read $fd]} finally {close $fd}
            clipboard clear -displayof .graphfull
            clipboard append -displayof .graphfull -type image/png -format 8 -- $png
        }
    } err]} {
        set ui(graphFullInfo) "Image copy failed: $err. Use Save image or Save selected area."
        tk_messageBox -parent .graphfull -icon error -message $ui(graphFullInfo)
        return
    }
    set ui(graphFullInfo) "Copied [expr {$areaOnly ? {selected area} : {complete graph}}] at original image resolution."
}

proc ::GX::graphFullImagePath {areaOnly} {
    variable ui
    if {![info exists ui(graphFullSource)] || ![file isfile $ui(graphFullSource)]} {error "Displayed graph is unavailable."}
    if {!$areaOnly} {return $ui(graphFullSource)}
    set box [graphFullSelectionBox]
    if {[info exists ui(graphFullCrop)]} {catch {file delete -- $ui(graphFullCrop)}}
    set path [graphFullTempPath]
    set ui(graphFullCrop) $path
    exec [runtimeToolRequired python] [file join $::GX::scriptDir app graph_viewer_raster.py] crop $ui(graphFullSource) $path {*}$box
    if {![file isfile $path]} {error "Selected-area PNG was not created."}
    return $path
}

proc ::GX::graphFullSave {areaOnly} {
    variable ui
    set name [file rootname [file tail $ui(graphFullPath)]]
    if {$areaOnly} {append name _selected}
    if {[catch {set dest [workspaceSaveFile export_dir -parent .graphfull -title [expr {$areaOnly ? {Save selected area} : {Save image}}] -initialfile "${name}.png" -defaultextension .png -filetypes {{{PNG image} {.png}} {{All files} *}}]} err]} {
        tk_messageBox -parent .graphfull -icon error -message $err; return
    }
    if {$dest eq ""} return
    if {[file normalize $dest] eq [file normalize $ui(graphFullPath)]} {
        tk_messageBox -parent .graphfull -icon error -message "Choose a different file; the Session graph artifact cannot be overwritten."
        return
    }
    if {[catch {file copy -force -- [graphFullImagePath $areaOnly] $dest} err]} {
        tk_messageBox -parent .graphfull -icon error -message "Unable to save PNG: $err"; return
    }
    set ui(graphFullInfo) "Saved displayed [expr {$areaOnly ? {selected area} : {graph}}] to $dest."
}

proc ::GX::graphFullClipboardX11 {path} {
    variable ui
    if {![info exists ui(graphClipboardPipe)]} {
        set helper [file join $::GX::scriptDir app graph_clipboard_x11.py]
        set ui(graphClipboardPipe) [open [list | [runtimeToolRequired python] -u $helper] r+]
        fconfigure $ui(graphClipboardPipe) -buffering line -encoding utf-8
    }
    set pipe $ui(graphClipboardPipe)
    if {[catch {
        puts $pipe "SET [binary encode base64 -maxlen 0 [encoding convertto utf-8 $path]]"
        flush $pipe
        set response [gets $pipe]
        if {![string match "OK *" $response]} {error $response}
    } err]} {
        catch {close $pipe}; unset ui(graphClipboardPipe)
        error $err
    }
}
proc ::GX::graphFullPrint {} {
    variable ui; variable cfg; variable scriptDir
    if {[string trim $cfg(print_printer)] eq ""} {tk_messageBox -parent .graphfull -icon error -message "Configure a printer in GX-TXT first."; return}
    set pdf [graphFullTempPath]
    set pdf "[file rootname $pdf].pdf"
    set ui(graphFullPdf) $pdf
    set cmd [list [runtimeToolRequired python] [file join $scriptDir services printing gxtxt_compose_pdf.py] --output $pdf --page $cfg(print_page) --orientation $cfg(print_orientation) --rows 1 --cols 1 --margin-mm $cfg(print_margin_mm) --gap-mm $cfg(print_gap_mm) --title $cfg(print_title) --captions $cfg(print_captions) $ui(graphFullSource)]
    if {[catch {exec {*}$cmd 2>@1} err]} {tk_messageBox -parent .graphfull -icon error -message $err; return}
    set cmd [list lp -d $cfg(print_printer) -n $cfg(print_copies)]
    switch -- $cfg(print_duplex) {
        simplex {lappend cmd -o sides=one-sided}
        long {lappend cmd -o sides=two-sided-long-edge}
        short {lappend cmd -o sides=two-sided-short-edge}
    }
    lappend cmd $pdf
    if {[catch {exec {*}$cmd 2>@1} err]} {tk_messageBox -parent .graphfull -icon error -message $err; return}
    set ui(graphFullInfo) "Sent displayed graph to $cfg(print_printer): $err"
}

proc ::GX::refreshOpenGraphWindow {} {
    variable ui
    if {[winfo exists .graphfull] && [info exists ui(graphFullPath)] && [file isfile $ui(graphFullPath)]} {
        reloadGraphWindow
    }
}

proc ::GX::previewImageGeometry {} {
    variable ui
    if {![info exists ui(graphPreview)] || ![winfo exists $ui(graphPreview)]} { return {} }
    if {[catch {set iw [image width ::GX::graphPreviewPhoto]}] || $iw <= 0} { return {} }
    set ih [image height ::GX::graphPreviewPhoto]
    set c $ui(graphPreview)
    set ww [winfo width $c]; set wh [winfo height $c]
    if {$ww <= 1 || $wh <= 1} { return {} }
    set ox [expr {($ww-$iw)/2.0}]
    set oy [expr {($wh-$ih)/2.0}]
    return [list $ox $oy $iw $ih]
}

proc ::GX::drawLegendPickOverlay {px py} {
    variable ui
    if {![info exists ui(graphPreview)] || ![winfo exists $ui(graphPreview)]} return
    set geom [previewImageGeometry]
    if {[llength $geom] != 4} return
    lassign $geom ox oy iw ih
    set c $ui(graphPreview)
    $c delete legendPickOverlay
    set cx [expr {$ox+$px*$iw}]
    set cy [expr {$oy+(1.0-$py)*$ih}]
    # The real legend extent is calculated only by Octave/the graphics toolkit.
    # A fake box was misleading.  The crosshair is the actual contract: the
    # selected point is the requested CENTER of the legend.
    set r 11
    $c create oval [expr {$cx-$r}] [expr {$cy-$r}] [expr {$cx+$r}] [expr {$cy+$r}] -outline #CC6600 -width 2 -tags legendPickOverlay
    $c create line [expr {$cx-16}] $cy [expr {$cx+16}] $cy -fill #CC3300 -width 2 -tags legendPickOverlay
    $c create line $cx [expr {$cy-16}] $cx [expr {$cy+16}] -fill #CC3300 -width 2 -tags legendPickOverlay
    $c create text [expr {$cx+18}] [expr {$cy-18}] -anchor sw -text "legend center" -fill #662200 -tags legendPickOverlay
}
proc ::GX::drawGraphPreview_annotation_base {} {
    variable ui
    variable legendPickActive
    if {![info exists ui(graphPreview)] || ![winfo exists $ui(graphPreview)]} return
    set c $ui(graphPreview)
    $c delete all
    if {[catch {image width ::GX::graphPreviewPhoto}]} return
    set ww [winfo width $c]; set wh [winfo height $c]
    if {$ww <= 1 || $wh <= 1} { return }
    $c create image [expr {$ww/2.0}] [expr {$wh/2.0}] -image ::GX::graphPreviewPhoto -anchor center -tags graphImage
    if {$legendPickActive && [info exists ui(legendOverlayX)] && [info exists ui(legendOverlayY)]} {
        drawLegendPickOverlay $ui(legendOverlayX) $ui(legendOverlayY)
    }
}

# Expose the preview entry while later canvas extensions are sourced.
proc ::GX::drawGraphPreview {} { ::GX::drawGraphPreview_annotation_base }

proc ::GX::legendPreviewMotion {w x y} {
    variable legendPickActive
    variable ui
    if {!$legendPickActive} return
    set geom [previewImageGeometry]
    if {[llength $geom] != 4} return
    lassign $geom ox oy iw ih
    if {$x < $ox || $x > ($ox+$iw) || $y < $oy || $y > ($oy+$ih)} {
        $w delete legendPickOverlay
        return
    }
    set px [expr {($x-$ox)/double($iw)}]
    set py [expr {1.0-($y-$oy)/double($ih)}]
    set ui(legendOverlayX) $px
    set ui(legendOverlayY) $py
    drawLegendPickOverlay $px $py
}

proc ::GX::cancelLegendPick {} {
    variable legendPickActive
    variable ui
    if {!$legendPickActive} return
    set legendPickActive 0
    if {[info exists ui(graphPreview)] && [winfo exists $ui(graphPreview)]} {
        bind $ui(graphPreview) <Button-1> {}
        bind $ui(graphPreview) <Motion> {}
        bind $ui(graphPreview) <Button-3> {}
        $ui(graphPreview) configure -cursor {}
        $ui(graphPreview) delete legendPickOverlay
    }
    catch {unset ui(legendOverlayX)}
    catch {unset ui(legendOverlayY)}
    set ui(graphInfo) "Legend placement canceled."
}

proc ::GX::selectedGraphPaths_annotation_base {} {
    variable ui; variable graphUse
    set out {}; if {![info exists ui(graphTree)]} { return $out }
    foreach id [$ui(graphTree) children {}] {
        if {[info exists graphUse($id)] && $graphUse($id) && [info exists ui(graphPath,$id)]} { lappend out $ui(graphPath,$id) }
    }
    return $out
}
proc ::GX::graphBrowserCatalog {} {
    variable ui;variable currentSession
    set result {}
    if {$currentSession eq {} || ![info exists ui(graphTree)] || ![winfo exists $ui(graphTree)]} {return $result}
    set root [file normalize $currentSession]
    foreach row [$ui(graphTree) children {}] {
        if {![info exists ui(graphPath,$row)]} continue
        set path [file normalize $ui(graphPath,$row)]
        if {![string match $root/analysis/* $path] || ![file isfile $path]} continue
        set reference {};catch {set reference [graphResourceRefForPath $path]}
        lappend result [dict create path $path relative_path [string range $path [expr {[string length $root]+1}] end] title [graphDisplayTitle $path] reference $reference]
    }
    return $result
}
