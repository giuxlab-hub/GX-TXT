# SPDX-License-Identifier: GPL-3.0-or-later
# Shared presentation of the existing Development/Bridge declaration catalog.
namespace eval ::GX::ApiBrowser {variable state;variable serial 0}
proc ::GX::apiBrowserCreate {w language} {
    variable ::GX::ApiBrowser::state
    ttk::frame $w
    set state($w,language) $language;set state($w,query) {};set state($w,generation) 0;set state($w,request) {};set state($w,catalog) {}
    set state($w,project) {};set state($w,cpp_context) {}
    set state($w,status) {Installed declarations}
    ttk::frame $w.tools
    ttk::label $w.tools.title -text {API Browser} -font TkHeadingFont
    ttk::button $w.tools.refresh -text \u21bb -width 0 -command [list ::GX::apiBrowserRefresh $w]
    bind $w.tools.refresh <Enter> [list ::GX::plotsToolbarTipSchedule $w.tools.refresh {Refresh API declarations}]
    bind $w.tools.refresh <Leave> ::GX::plotsToolbarTipHide
    ttk::entry $w.tools.query -width 12 -textvariable ::GX::ApiBrowser::state($w,query)
    grid $w.tools.title -row 0 -column 0 -sticky w
    grid $w.tools.refresh -row 0 -column 1 -sticky e
    grid $w.tools.query -row 1 -column 0 -columnspan 2 -sticky ew -pady 3
    grid columnconfigure $w.tools 0 -weight 1
    pack $w.tools -fill x
    bind $w.tools.query <KeyRelease> [list ::GX::apiBrowserSearchSchedule $w]
    # A one-line status leaves the reference panes usable in narrow editors.
    # Full scientific/admission context belongs to the scrollable details.
    ttk::label $w.status -textvariable ::GX::ApiBrowser::state($w,status) -width 1 -anchor w
    ttk::button $w.manual -text {API manual} -width 0 -command [list ::GX::apiBrowserManual $w]
    pack $w.status -side bottom -fill x;pack $w.manual -side bottom -fill x
    ttk::panedwindow $w.body -orient vertical;pack $w.body -fill both -expand 1
    foreach side {list details} {ttk::frame $w.body.$side;$w.body add $w.body.$side -weight 1}
    ttk::treeview $w.body.list.tree -show tree -selectmode browse -height 6
    $w.body.list.tree column #0 -width 240 -minwidth 100 -stretch 0
    ttk::scrollbar $w.body.list.y -command [list $w.body.list.tree yview]
    ttk::scrollbar $w.body.list.x -orient horizontal -command [list $w.body.list.tree xview]
    $w.body.list.tree configure -yscrollcommand [list $w.body.list.y set] -xscrollcommand [list $w.body.list.x set]
    pack $w.body.list.x -side bottom -fill x;pack $w.body.list.y -side right -fill y;pack $w.body.list.tree -fill both -expand 1
    text $w.body.details.text -wrap word -width 30 -height 7 -state disabled
    uiTextEditingAttach [winfo toplevel $w] [list $w.tools.query $w.body.details.text]
    ttk::scrollbar $w.body.details.y -command [list $w.body.details.text yview]
    $w.body.details.text configure -yscrollcommand [list $w.body.details.y set]
    pack $w.body.details.y -side right -fill y;pack $w.body.details.text -fill both -expand 1
    bind $w.body.list.tree <<TreeviewSelect>> [list ::GX::apiBrowserSelect $w]
    bind $w.body.list.tree <Configure> +[list ::GX::apiBrowserRowLayoutSchedule $w]
    bind $w <Destroy> +[list ::GX::apiBrowserDispose $w %W]
    set state($w,sessionTrace) [list ::GX::apiBrowserSessionChanged $w]
    trace add variable ::GX::currentSession {write unset} $state($w,sessionTrace)
    after idle [list ::GX::apiBrowserRefresh $w]
    return $w
}
proc ::GX::apiBrowserDispose {w actual} {
    variable ::GX::ApiBrowser::state
    if {$w ne $actual} return
    if {[info exists state($w,sessionTrace)]} {trace remove variable ::GX::currentSession {write unset} $state($w,sessionTrace)}
    foreach key {request searchTimer sessionTimer rowTimer} {
        if {[info exists state($w,$key)] && $state($w,$key) ne {}} {
            if {$key eq {request}} {scriptJobRequestCancel $state($w,$key)} else {after cancel $state($w,$key)}
        }
    }
    array unset state $w,*
}
proc ::GX::apiBrowserRowLayoutSchedule {w} {
    variable ::GX::ApiBrowser::state
    if {[info exists state($w,rowTimer)]} {after cancel $state($w,rowTimer)}
    set state($w,rowTimer) [after idle [list ::GX::apiBrowserRowLayout $w]]
}
proc ::GX::apiBrowserRowLayout {w} {
    variable ::GX::ApiBrowser::state
    unset -nocomplain state($w,rowTimer)
    set tree $w.body.list.tree
    if {![winfo exists $tree]} return
    set selected [$tree selection]
    if {[llength $selected]!=1} return
    set id [lindex $selected 0];set box [$tree bbox $id]
    # Preserve deliberate scrolling away from a selection. Only repair a
    # visible row cut by the new viewport's bottom edge during allocation.
    if {[llength $box]!=4} return
    lassign $box x y width height
    if {$y>=0 && $y+$height<=[winfo height $tree]} return
    $tree see $id
    set box [$tree bbox $id]
    if {[llength $box]==4} {
        lassign $box x y width height
        if {$y+$height>[winfo height $tree]} {$tree yview scroll 1 units} elseif {$y<0} {$tree yview scroll -1 units}
    }
}
proc ::GX::apiBrowserSessionChanged {w args} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $w] || ![info exists state($w,catalog)]} return
    if {[info exists state($w,sessionTimer)]} {after cancel $state($w,sessionTimer)}
    # Session context refreshes the cached reference only: no metadata worker,
    # renderer, Bridge activation or scientific operation is reconstructed.
    set state($w,sessionTimer) [after idle [list ::GX::apiBrowserSessionUpdated $w]]
}
proc ::GX::apiBrowserSessionUpdated {w} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $w] || ![info exists state($w,catalog)]} return
    unset -nocomplain state($w,sessionTimer)
    # Only the selected reference contains Session context. Rebuilding an
    # unchanged tree would collapse its ancestors and hide the selected row.
    apiBrowserSelect $w
}
proc ::GX::apiBrowserRefresh {w} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $w] || ![info exists state($w,request)]} return
    if {$state($w,request) ne {}} {scriptJobRequestCancel $state($w,request)}
    set generation [incr state($w,generation)]
    set state($w,status) {Reading declarations…}
    apiBrowserStatusShow $w 1
    set command [list /usr/bin/python3 -I -B [file join $::GX::scriptDir core python gxtxt_viewer_development.py] --api-browser-tcl]
    if {$state($w,project) ne {}} {lappend command --project $state($w,project)}
    set state($w,request) [scriptJobAsync $command {} [list ::GX::apiBrowserReceived $w $generation] {timeout_ms 25000 max_bytes 16777216 process_group 1 ui_lifetime 1 label {API metadata discovery}}]
}
proc ::GX::apiBrowserProjectSet {w project} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $w] || ![info exists state($w,project)]} return
    set state($w,project) [expr {$project eq {} ? {} : [file normalize $project]}]
}
proc ::GX::apiBrowserReceived {w generation response} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $w] || ![info exists state($w,generation)] || $generation!=$state($w,generation)} return
    set state($w,request) {}
    if {![dict get $response ok]} {set state($w,status) "Metadata unavailable: [string range [dict get $response error] 0 1000]";return}
    if {[catch {set state($w,catalog) [dict get $response result apis];dict size $state($w,catalog)} reason]} {set state($w,status) "Invalid metadata: $reason";return}
    set state($w,cpp_context) [datasetPublicationV2DictDefault [dict get $response result] cpp_context {}]
    apiBrowserSearch $w
}
proc ::GX::apiBrowserSearchSchedule {w} {
    variable ::GX::ApiBrowser::state
    if {[info exists state($w,searchTimer)]} {after cancel $state($w,searchTimer)}
    set state($w,searchTimer) [after 150 [list ::GX::apiBrowserSearch $w]]
}
proc ::GX::apiBrowserSearch {w} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $w] || ![info exists state($w,catalog)]} return
    set query [string tolower [string range $state($w,query) 0 255]]
    set tree $w.body.list.tree;set selected [$tree selection];$tree delete [$tree children {}]
    unset -nocomplain state($w,selectedApi)
    $w.body.details.text configure -state normal;$w.body.details.text delete 1.0 end;$w.body.details.text configure -state disabled
    set state($w,rows) {};set count 0;set total 0
    foreach api [lsort -dictionary [dict keys $state($w,catalog)]] {
        set row [dict get $state($w,catalog) $api]
        if {$query ne {} && [string first $query [string tolower "$api $row"]]<0} continue
        incr total;if {$count>=250} continue
        incr count;set node family:$api;set title $api
        if {[datasetPublicationV2DictDefault $row deprecated 0] eq {1}} {append title { · deprecated}}
        $tree insert {} end -id $node -text $title
        dict set state($w,rows) $node [dict create api $api row $row surface family]
        set n 0
        foreach provider [datasetPublicationV2DictDefault $row providers {}] {
            set child $node.provider:[dict get $provider provider]:[dict get $provider version]
            $tree insert $node end -id $child -text "[dict get $provider provider] · v[dict get $provider version]"
            dict set state($w,rows) $child [dict create api $api row $provider surface host]
        }
        if {[string equal -nocase $state($w,language) Cpp]} {
            dict for {method descriptor} [datasetPublicationV2DictDefault $row cpp_methods {}] {
                set child $node.cpp:$method
                $tree insert $node end -id $child -text "Host::$method · C++"
                dict set state($w,rows) $child [dict create api $api row $descriptor surface cpp_sdk operation $method]
            }
        }
        if {[dict exists $row script_descriptor]} {
            dict for {operation descriptor} [dict get $row script_descriptor operations] {
                set child $node.operation:$operation
                $tree insert $node end -id $child -text "$operation · Python/Octave"
                dict set state($w,rows) $child [dict create api $api row $descriptor surface script_bridge operation $operation provider [dict get $row script_descriptor provider_id]]
            }
        }
    }
    set context [expr {$::GX::currentSession eq {}?{no Session}:{Session open; no active script implied}}]
    set state($w,status) "$count/$total families · $state($w,language)"
    # The selected scrollable reference owns full admission/Session context.
    # Retain the status for pending/error/empty results, without permanently
    # consuming a reference line for a redundant successful family count.
    apiBrowserStatusShow $w [expr {$count==0}]
    if {[llength $selected] && [$tree exists [lindex $selected 0]]} {$tree selection set [lindex $selected 0];apiBrowserSelect $w}
}
proc ::GX::apiBrowserSelect {w} {
    variable ::GX::ApiBrowser::state
    set id [lindex [$w.body.list.tree selection] 0]
    if {$id eq {} || ![dict exists $state($w,rows) $id]} return
    set item [dict get $state($w,rows) $id];set row [dict get $item row]
    set state($w,selectedApi) [dict get $item api]
    set detail "[dict get $item api]\nSurface: [dict get $item surface]\n\n"
    append detail "[expr {$::GX::currentSession eq {} ? {No Session.} : {Session: }}]"
    if {$::GX::currentSession ne {}} {append detail [file tail $::GX::currentSession]}
    append detail "\n"
    if {[string equal -nocase $state($w,language) Cpp]} {
        append detail "Saved C++ project: [datasetPublicationV2DictDefault $state($w,cpp_context) status NO_PROJECT]\n"
        foreach key {profile project reason} {if {[dict exists $state($w,cpp_context) $key]} {append detail "$key: [dict get $state($w,cpp_context) $key]\n"}}
        append detail "Request admission is separate from source validation, Build and active runtime grants.\n\n"
    } else {
        append detail "Reference discovery does not activate a managed Script Bridge.\n\n"
    }
    if {[dict get $item surface] eq {script_bridge}} {
        append detail "Purpose: [dict get $row summary]\nProvider: [dict get $item provider]\n\nArguments (actual declaration):\n"
        set names {}
        foreach argument [dict get $row arguments] {
            set required [expr {[datasetPublicationV2DictDefault $argument required 1]?{required}:{optional}}]
            append detail "[dict get $argument name] ($required): [datasetPublicationV2DictDefault $argument kind {See owner manual}]\n"
            lappend names [dict get $argument name]
        }
        foreach key {argument_convention context} {
            if {[dict exists $row $key]} {append detail "\n$key: [dict get $row $key]\n"}
        }
        append detail "\nRegistered Script Bridge result: [dict get $row result_contract]\n"
        if {[string equal -nocase $state($w,language) Cpp]} {
            set methods [datasetPublicationV2DictDefault [dict get $state($w,catalog) [dict get $item api]] cpp_methods {}]
            set matched 0
            dict for {method contract} $methods {
                if {[lindex [split [dict get $contract operation] .] 0] ne [dict get $item operation]} continue
                set matched 1
                append detail "\nActual C++ SDK mapping:\n"
                dict for {key value} $contract {append detail "$key: $value\n"}
            }
            if {!$matched} {append detail "\nNOT_AVAILABLE as a direct C++ SDK method. This Script Bridge operation is not a gx::Host invoke-any-API facility. See the family for its finite declared C++ form methods, if any.\n"}
        } elseif {[string equal -nocase $state($w,language) Python]} {
            append detail "\nPython syntax (active managed Bridge required):\ngxtxt_api_call(\"[dict get $item api]\", \"[dict get $item operation]\", \[[join $names {, }]\])\n"
        } elseif {[string equal -nocase $state($w,language) Octave]} {
            append detail "\nOctave syntax (active managed Bridge required):\ngxtxt_api_call('[dict get $item api]', '[dict get $item operation]', {[join $names {, }]})\n"
        }
    } elseif {[dict get $item surface] eq {cpp_sdk}} {
        dict for {key value} $row {append detail "$key: $value\n\n"}
    } else {
        foreach key {name summary provider provider_version version version_conflict enabled available availability_scope deprecated superseded_by new_viewer_admission documentation capabilities operations design_operations laboratory_operations profiles host_entrypoint host_arguments result_contract metadata_error sdk_exposed allowed_operations operation_shapes authorization_reason cpp_project_status cpp_project_request} {
            if {[dict exists $row $key]} {append detail "$key: [dict get $row $key]\n\n"}
        }
        if {[dict exists $row host_operation_contracts]} {
            append detail "Trusted host documentation only. These Tcl signatures do not authorize Script Bridge or C++ SDK calls.\n\n"
            dict for {operation contract} [dict get $row host_operation_contracts] {
                append detail "$operation: [dict get $contract command] [dict get $contract arguments]\n"
                dict for {name parameter} [dict get $contract parameters] {
                    append detail "  $name ([dict get $parameter type]): [dict get $parameter description]\n"
                }
                append detail "Result ([dict get $contract result type]): [dict get $contract result description]\nContext: [dict get $contract context]\n"
                if {[dict exists $contract example]} {append detail "Host example: [dict get $contract example]\n"}
                append detail "\n"
            }
        }
        if {![dict exists $row operations] && ![dict exists $row script_descriptor]} {append detail "Exact operation signatures are not declared in this row. Open the owner manual; no argument or result type is inferred.\n"}
        if {[dict exists $row script_descriptor]} {append detail "Registered Python/Octave operations are listed below this family. Registration does not prove external tools/runtime availability or an active script.\n"}
    }
    set text $w.body.details.text;$text configure -state normal;$text delete 1.0 end;$text insert end [string range $detail 0 262143];$text configure -state disabled
}
proc ::GX::apiBrowserManual {w} {
    variable ::GX::ApiBrowser::state
    if {![info exists state($w,selectedApi)]} {set state($w,status) {Select an API family or operation first.};apiBrowserStatusShow $w 1;return}
    if {[catch {documentationBrowserOpenApi $state($w,selectedApi)} reason]} {set state($w,status) "API manual unavailable: $reason";apiBrowserStatusShow $w 1}
}
proc ::GX::apiBrowserStatusShow {w visible} {
    if {![winfo exists $w.status]} return
    set mapped [expr {[winfo manager $w.status] ne {}}]
    if {$mapped==$visible} return
    if {$visible} {pack $w.status -side bottom -fill x -before $w.manual} else {pack forget $w.status}
    set split [winfo parent $w]
    if {[info exists ::GX::ApiBrowser::state($split,visible)]} {apiBrowserSplitLayout $split}
}
proc ::GX::apiBrowserMinimumHeight {browser} {
    set line [font metrics TkDefaultFont -linespace]
    set tree $browser.body.list.tree
    set row [expr {max($line,int(double([winfo reqheight $tree])/max(1,[$tree cget -height])))}]
    set scroll [winfo reqheight $browser.body.list.x]
    set status [expr {[winfo manager $browser.status] eq {} ? 0 : [winfo reqheight $browser.status]}]
    return [dict create browser [expr {[winfo reqheight $browser.tools]+[winfo reqheight $browser.manual]+$status+3*$row+4*$line+$scroll+16}] explorer [expr {2*$line+$scroll+8}]]
}
proc ::GX::apiBrowserMount {left language} {
    variable ::GX::ApiBrowser::state
    set split $left.apiSplit
    if {[winfo exists $split]} {return $split}
    set children [pack slaves $left]
    ttk::panedwindow $split -orient vertical
    ttk::frame $split.explorer
    foreach child $children {
        set options [pack info $child];pack forget $child;dict set options -in $split.explorer;pack $child {*}$options
        # Geometry -in preserves the existing widget's physical parent and
        # bindings. Raise that sibling above the newly created split container.
        raise $child $split
    }
    $split add $split.explorer -weight 1
    apiBrowserCreate $split.browser $language
    set state($split,language) [string tolower $language];set state($split,fraction) .45;set state($split,visible) 1;set state($split,pending) 1
    set saved [configurationGet scripts.editor_layout.[string tolower $language]]
    if {[catch {dict size $saved}]} {set saved {}}
    if {[dict exists $saved api_fraction] && [string is double -strict [dict get $saved api_fraction]] && [dict get $saved api_fraction]>.1 && [dict get $saved api_fraction]<.9} {set state($split,fraction) [dict get $saved api_fraction]}
    if {[dict exists $saved api_visible] && [string is boolean -strict [dict get $saved api_visible]]} {set state($split,visible) [dict get $saved api_visible]}
    if {$state($split,visible)} {$split add $split.browser -weight 1}
    pack $split -fill both -expand 1
    bind $split <Configure> [list ::GX::apiBrowserSplitLayout $split]
    bind $split <ButtonRelease-1> [list ::GX::apiBrowserSplitRemember $split]
    bind $split <Destroy> [list ::GX::apiBrowserSplitDispose $split %W]
    return $split
}
proc ::GX::apiBrowserSplitLayout {split} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $split] || ![info exists state($split,visible)] || !$state($split,visible) || [winfo height $split]<100} return
    set state($split,pending) 1
    if {[info exists state($split,layoutAfter)]} {after cancel $state($split,layoutAfter)}
    set state($split,layoutAfter) [after idle [list ::GX::apiBrowserSplitApply $split]]
}
proc ::GX::apiBrowserSplitApply {split} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $split] || ![info exists state($split,visible)]} return
    unset -nocomplain state($split,layoutAfter)
    # As in scriptWorkspaceLayoutSettle, drain ttk's deferred add/forget
    # allocation before setting a retained sash, while remembering is suspended.
    update idletasks
    if {![winfo exists $split] || ![info exists state($split,visible)]} return
    if {!$state($split,visible) || [llength [$split panes]]<2 || "$split.browser" ni [$split panes]} {set state($split,pending) 0;return}
    # Tk allocates newly added panes on idle; applying before that allocation
    # can leave the restored Browser with zero height despite a valid sash.
    set height [winfo height $split];set browser $split.browser
    # Retain enough space for three reference rows and four detail lines,
    # adapting to the actual font/chrome rather than assuming a fixed DPI.
    set line [font metrics TkDefaultFont -linespace]
    set tree $browser.body.list.tree
    set row [expr {max($line,int(double([winfo reqheight $tree])/max(1,[$tree cget -height])))}]
    set minimum [apiBrowserMinimumHeight $browser]
    set needed [dict get $minimum browser]
    set explorerMinimum [dict get $minimum explorer]
    set position [expr {int($height*$state($split,fraction))}]
    set maximum [expr {max($explorerMinimum,$height-$needed)}]
    $split sashpos 0 [expr {max($explorerMinimum,min($position,$maximum))}]
    update idletasks
    if {[winfo exists $browser.body]} {
        set bodyHeight [winfo height $browser.body]
        set listMinimum [expr {3*$row+[winfo reqheight $browser.body.list.x]+4}]
        set maximum [expr {max($listMinimum,$bodyHeight-4*$line-9)}]
        $browser.body sashpos 0 [expr {max($listMinimum,min(int($bodyHeight*.5),$maximum))}]
    }
    after idle [list ::GX::apiBrowserSplitSettled $split]
}
proc ::GX::apiBrowserSplitDispose {split actual} {
    variable ::GX::ApiBrowser::state
    if {$split ne $actual} return
    if {[info exists state($split,layoutAfter)]} {after cancel $state($split,layoutAfter)}
    array unset state $split,*
}
proc ::GX::apiBrowserSplitSettled {split} {variable ::GX::ApiBrowser::state;if {[winfo exists $split]} {set state($split,pending) 0}}
proc ::GX::apiBrowserSplitRemember {split} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $split] || ![info exists state($split,language)]} return
    if {!$state($split,pending) && [llength [$split panes]]>1 && "$split.browser" in [$split panes] && [winfo height $split]>100} {set fraction [expr {[$split sashpos 0]/double([winfo height $split])}];if {$fraction>.1 && $fraction<.9} {set state($split,fraction) $fraction}}
    set key scripts.editor_layout.$state($split,language);set value [configurationGet $key]
    if {[catch {dict size $value}]} {set value {}}
    dict set value api_fraction $state($split,fraction);dict set value api_visible $state($split,visible)
    configurationSet $key $value;configurationSave [list $key]
}
proc ::GX::apiBrowserToggle {left} {
    variable ::GX::ApiBrowser::state
    set split $left.apiSplit
    apiBrowserSplitRemember $split
    if {$state($split,visible)} {
        if {"$split.browser" ni [$split panes]} {$split add $split.browser -weight 1}
        apiBrowserSplitLayout $split
    } elseif {"$split.browser" in [$split panes]} {$split forget $split.browser}
    apiBrowserSplitRemember $split
}
proc ::GX::apiBrowserCatalogChanged {} {
    variable ::GX::ApiBrowser::state
    if {![llength [info commands winfo]]} return
    foreach name [array names state *,request] {
        set w [string range $name 0 end-8]
        if {[winfo exists $w]} {after idle [list ::GX::apiBrowserRefresh $w]}
    }
}
