# SPDX-License-Identifier: GPL-3.0-or-later
# Shared presentation of the existing Development/Bridge declaration catalog.
source [file join [file dirname [info script]] api_catalog_service_v1.tcl]
namespace eval ::GX::ApiBrowser {variable state;variable serial 0}
proc ::GX::apiBrowserCreate {w language {options {}}} {
    variable ::GX::ApiBrowser::state
    ttk::frame $w
    set state($w,language) $language;set state($w,query) {};set state($w,generation) 0;set state($w,request) {};set state($w,catalog) {}
    set state($w,project) {};set state($w,cpp_context) {status NO_PROJECT requests {}};set state($w,offset) 0
    set state($w,scope) [datasetPublicationV2DictDefault $options scope editor]
    set state($w,enabled) [datasetPublicationV2DictDefault $options enabled 1]
    set state($w,selectedRecord) {};set state($w,total) 0;set state($w,count) 0
    set state($w,api_filter) [datasetPublicationV2DictDefault $options api_id {}]
    set state($w,provider_filter) [datasetPublicationV2DictDefault $options provider_id {}]
    set state($w,surface) [expr {$language eq {Public}?{All public}:($language eq {Cpp}?{C++ documentation}:{Script Bridge})}]
    set state($w,status) {Installed declarations}
    ttk::frame $w.tools
    ttk::label $w.tools.title -text [datasetPublicationV2DictDefault $options title {API Browser}] -font TkHeadingFont
    if {$state($w,scope) eq {editor}} {
        ttk::button $w.tools.refresh -text \u21bb -width 0 -command [list ::GX::apiBrowserRefresh $w]
        bind $w.tools.refresh <Enter> [list ::GX::plotsToolbarTipSchedule $w.tools.refresh {Reload indexed API view}]
        bind $w.tools.refresh <Leave> ::GX::plotsToolbarTipHide
    }
    ttk::entry $w.tools.query -width 12 -textvariable ::GX::ApiBrowser::state($w,query)
    grid $w.tools.title -row 0 -column 0 -sticky w
    if {$state($w,scope) eq {editor}} {grid $w.tools.refresh -row 0 -column 1 -sticky e}
    grid $w.tools.query -row 1 -column 0 -columnspan 2 -sticky ew -pady 3
    ttk::combobox $w.tools.surface -state readonly -width 15 -textvariable ::GX::ApiBrowser::state($w,surface) -values [expr {$state($w,scope) eq {editor} && $language eq {Cpp}?{{C++ documentation} {C++ SDK} {Trusted host}}:{{All public} {Script Bridge} {C++ documentation} {C++ SDK} {Trusted host}}}]
    if {$state($w,scope) eq {catalog} || $language eq {Cpp}} {grid $w.tools.surface -row 2 -column 0 -columnspan 2 -sticky ew}
    bind $w.tools.surface <<ComboboxSelected>> [list ::GX::apiBrowserFilterChanged $w]
    ttk::frame $w.pages
    ttk::button $w.pages.previous -text {Previous} -command [list ::GX::apiBrowserPage $w -1]
    ttk::button $w.pages.next -text {Next} -command [list ::GX::apiBrowserPage $w 1]
    pack $w.pages.previous -side left;pack $w.pages.next -side right
    pack $w.pages -side bottom -fill x
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
    # Before population the shared inspection owner sets readable font rows
    # while its empty-#0 guard preserves this Browser's column/scroll policy.
    uiFieldInspectionColumnsFit $w.body.list.tree
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
    bind $w.tools.query <Return> [list ::GX::apiBrowserFilterChanged $w]
    set state($w,presentation) [datasetPublicationV2DictDefault $options presentation full]
    if {$state($w,presentation) eq {compact}} {
        # An explicitly empty title lets an enclosing notebook supply it.
        # Other compact callers retain their default/custom title semantics.
        if {[$w.tools.title cget -text] eq {}} {
            grid forget $w.tools.title
            grid $w.tools.query -row 0 -column 0 -columnspan 1 -sticky ew -pady 3
            if {[winfo manager $w.tools.surface] eq {grid}} {grid $w.tools.surface -row 1 -column 0 -columnspan 2 -sticky ew}
        }
        $w.manual configure -text Manual
        $w.pages.previous configure -width 0;$w.pages.next configure -width 0
        pack forget $w.pages.previous $w.pages.next $w.manual
        grid $w.manual -in $w.pages -row 0 -column 0
        bind $w.pages <Configure> [list ::GX::uiFieldControlsLayout $w.pages %w [list $w.manual $w.pages.previous $w.pages.next]]
        ::GX::uiFieldControlsLayout $w.pages 360 [list $w.manual $w.pages.previous $w.pages.next]
        foreach {control tip} [list $w.manual {Open selected API manual} $w.pages.previous {Previous page of API declarations} $w.pages.next {Next page of API declarations}] {
            bind $control <Enter> [list ::GX::plotsToolbarTipSchedule $control $tip]
            bind $control <Leave> ::GX::plotsToolbarTipHide
        }
        $w.body.list.tree configure -height 3;$w.body.details.text configure -height 4
        bind $w.body <Configure> +[list ::GX::apiBrowserCompactSchedule $w]
    }
    apiBrowserEnabled $w $state($w,enabled)
    after idle [list ::GX::apiBrowserRefresh $w]
    return $w
}
proc ::GX::apiBrowserDispose {w actual} {
    variable ::GX::ApiBrowser::state
    if {$w ne $actual} return
    if {[info exists state($w,sessionTrace)]} {trace remove variable ::GX::currentSession {write unset} $state($w,sessionTrace)}
    foreach key {request searchTimer sessionTimer rowTimer compactTimer} {
        if {[info exists state($w,$key)] && $state($w,$key) ne {}} {
            if {$key eq {request}} {apiCatalogCancel $state($w,$key)} else {after cancel $state($w,$key)}
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
    if {$state($w,request) ne {}} {apiCatalogCancel $state($w,request)}
    set generation [incr state($w,generation)]
    set state($w,status) {Reconciling installed API catalog…}
    apiBrowserStatusShow $w 1
    set state($w,request) [apiCatalogRequest [list ::GX::apiBrowserReceived $w $generation]]
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
    if {![dict get $response ok]} {
        catch {apiBrowserSearch $w}
        set state($w,status) "Catalog unavailable or stale: [string range [dict get $response error] 0 500]"
        apiBrowserStatusShow $w 1
        return
    }
    set state($w,cpp_context) [apiCatalogProjectContext $state($w,project)]
    apiBrowserSearch $w
}
proc ::GX::apiBrowserFilterChanged {w} {set ::GX::ApiBrowser::state($w,offset) 0;apiBrowserSearch $w}
proc ::GX::apiBrowserPage {w direction} {
    variable ::GX::ApiBrowser::state
    if {!$state($w,enabled)} return
    if {$direction>0 && $state($w,offset)+$state($w,count)>=$state($w,total)} return
    if {$direction<0 && $state($w,offset)<=0} return
    set state($w,offset) [expr {max(0,$state($w,offset)+$direction*250)}]
    apiBrowserSearch $w
}
proc ::GX::apiBrowserSearchSchedule {w} {
    variable ::GX::ApiBrowser::state
    if {[info exists state($w,searchTimer)]} {after cancel $state($w,searchTimer)}
    set state($w,offset) 0
    set state($w,searchTimer) [after 150 [list ::GX::apiBrowserSearch $w]]
}
proc ::GX::apiBrowserSearch {w} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $w] || ![info exists state($w,catalog)]} return
    unset -nocomplain state($w,searchTimer)
    switch $state($w,surface) {
        {All public} {set surface {host script_bridge cpp_sdk}}
        {C++ documentation} {set surface {host cpp_sdk}}
        {Script Bridge} {set surface script_bridge}
        {C++ SDK} {set surface cpp_sdk}
        {Trusted host} {set surface host}
        {All surfaces} {set surface {host script_bridge cpp_sdk}}
    }
    if {[catch {set response [apiCatalogQuery [dict create surface $surface language [expr {$state($w,language) eq {Public}?{}:$state($w,language)}] query [string range $state($w,query) 0 255] api_id $state($w,api_filter) provider_id $state($w,provider_filter) offset $state($w,offset) limit 250]]} reason]} {
        set state($w,status) "Catalog unavailable: $reason";apiBrowserStatusShow $w 1;return
    }
    set tree $w.body.list.tree;set selected [$tree selection];if {![llength $selected] && $state($w,selectedRecord) ne {}} {set selected [list $state($w,selectedRecord)]};set expanded {}
    foreach node [$tree children {}] {if {[$tree item $node -open]} {lappend expanded $node}}
    $tree delete [$tree children {}]
    unset -nocomplain state($w,selectedApi)
    $w.body.details.text configure -state normal;$w.body.details.text delete 1.0 end;$w.body.details.text configure -state disabled
    set state($w,rows) {};set state($w,catalog) {};set count 0
    foreach record [dict get $response rows] {
        set api [dict get $record api_id];set node family:$api
        if {![$tree exists $node]} {
            set familyRecord [apiCatalogGet $node];set family [dict get $familyRecord payload]
            dict set state($w,catalog) $api $family
            $tree insert {} end -id $node -text $api -open [expr {$node in $expanded}]
            dict set state($w,rows) $node [dict create api $api row $family surface family runtime_state [dict get $familyRecord runtime_state]]
        }
        set child [dict get $record id];set item [dict get $record payload]
        dict set item runtime_state [dict get $record runtime_state]
        set suffix [dict get $record surface]
        $tree insert $node end -id $child -text "[dict get $record title] · $suffix"
        dict set state($w,rows) $child $item
        incr count
    }
    set total [dict get $response total];set state($w,total) $total;set state($w,count) $count
    $w.pages.previous configure -state [expr {$state($w,offset)>0?{normal}:{disabled}}]
    $w.pages.next configure -state [expr {$state($w,offset)+$count<$total?{normal}:{disabled}}]
    set state($w,status) "[dict get $response freshness] · $count/$total records · $state($w,language)"
    if {$state($w,offset)>0} {append state($w,status) " · from [expr {$state($w,offset)+1}]"}
    apiBrowserStatusShow $w [expr {$state($w,presentation) ne {compact} || !$count || [dict get $response freshness] ne {current}}]
    apiBrowserEnabled $w $state($w,enabled)
    event generate $w <<ApiCatalogView>>
    if {[llength $selected] && [$tree exists [lindex $selected 0]]} {$tree selection set [lindex $selected 0];$tree see [lindex $selected 0];apiBrowserSelect $w}
}
proc ::GX::apiBrowserHostContractsText {contracts {selectedOperation {}}} {
    # CORE's older reference metadata has signature/parameters/result.description;
    # provider documentation may additionally declare command/arguments/result.type.
    # Neither form is an invocation grant, and missing fields are never inferred.
    if {[catch {dict size $contracts}]} {return "Host documentation unavailable: invalid operation metadata.\n"}
    set detail {}
    dict for {operation contract} $contracts {
        if {$selectedOperation ne {} && $operation ne $selectedOperation} continue
        if {[catch {dict size $contract}]} {append detail "$operation: invalid host documentation; consult the owner manual.\n\n";continue}
        set command [datasetPublicationV2DictDefault $contract command {}]
        set arguments [datasetPublicationV2DictDefault $contract arguments [datasetPublicationV2DictDefault $contract signature {not declared}]]
        if {$command ne {}} {append detail "$operation: $command $arguments\n"
        } else {append detail "$operation: $arguments\nHost command: not declared in this reference metadata; consult the owner manual.\n"}
        set parameters [datasetPublicationV2DictDefault $contract parameters {}]
        if {[catch {dict size $parameters}]} {append detail "Parameter metadata unavailable; consult the owner manual.\n"
        } else {
            dict for {name parameter} $parameters {
                if {[catch {dict size $parameter}]} {append detail "  $name: invalid parameter documentation.\n";continue}
                append detail "  $name ([datasetPublicationV2DictDefault $parameter type {not declared}]): [datasetPublicationV2DictDefault $parameter description {See owner manual}]\n"
            }
        }
        set result [datasetPublicationV2DictDefault $contract result {}]
        if {[catch {dict size $result}]} {append detail "Result metadata unavailable; consult the owner manual.\n"
        } else {append detail "Result ([datasetPublicationV2DictDefault $result type {not declared}]): [datasetPublicationV2DictDefault $result description {See owner manual}]\n"}
        append detail "Context: [datasetPublicationV2DictDefault $contract context {not declared}]\n"
        if {[dict exists $contract example]} {append detail "Host example: [dict get $contract example]\n"}
        append detail "\n"
    }
    return $detail
}
proc ::GX::apiBrowserSelect {w} {
    variable ::GX::ApiBrowser::state
    set id [lindex [$w.body.list.tree selection] 0]
    if {$id eq {} || ![dict exists $state($w,rows) $id] || !$state($w,enabled)} return
    set state($w,selectedRecord) $id
    set item [dict get $state($w,rows) $id];set row [dict get $item row]
    if {[dict get $item surface] eq {cpp_sdk}} {set row [apiCatalogProjectMethod $row $state($w,cpp_context)]}
    if {$state($w,language) eq {Cpp} && [dict get $item surface] eq {family}} {
        set api [dict get $item api]
        if {[dict exists $state($w,cpp_context) requests $api]} {
            dict set row cpp_project_status [dict get $state($w,cpp_context) requests $api status]
            dict set row cpp_project_request [dict get $state($w,cpp_context) requests $api request]
        } else {dict set row cpp_project_status [expr {[dict get $state($w,cpp_context) status] eq {SAVED_PROJECT_METADATA}?{NOT_REQUESTED}:[dict get $state($w,cpp_context) status]}];dict set row cpp_project_request {}}
    }
    if {$state($w,surface) eq {Script Bridge} && [dict get $item surface] eq {family}} {
        # The safe script reference must not list unrelated host/SDK operations
        # as this language's exports, even inside the family detail pane.
        foreach key {host_operation_contracts host_entrypoint host_arguments allowed_operations operation_shapes sdk_exposed authorization_reason design_operations laboratory_operations profiles new_viewer_admission} {dict unset row $key}
        set operations {}
        foreach child [$w.body.list.tree children $id] {if {[dict exists $state($w,rows) $child operation]} {lappend operations [dict get $state($w,rows) $child operation]}}
        dict set row operations $operations
        dict set row availability_scope {Registered language exports on this indexed page; runtime state is separate}
    }
    set state($w,selectedApi) [dict get $item api]
    set detail "[dict get $item api]\nSurface: [dict get $item surface]\n"
    if {[dict exists $item operation]} {append detail "Operation: [dict get $item operation]\n"}
    append detail "\n"
    append detail "[expr {$::GX::currentSession eq {} ? {No Session.} : {Session: }}]"
    if {$::GX::currentSession ne {}} {append detail [file tail $::GX::currentSession]}
    append detail "\nCatalog: $::GX::ApiCatalog::freshness\n"
    if {[dict exists $item runtime_state]} {dict for {key value} [dict get $item runtime_state] {append detail "$key: $value\n"}}
    if {[dict exists $item catalog_meta]} {dict for {key value} [dict get $item catalog_meta] {if {$key ni {arguments result_contract}} {append detail "$key: $value\n"}}}
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
            if {[dict exists $row $key]} {set label [expr {$key in {enabled available}?"packaged_reference_$key":$key}];append detail "$label: [dict get $row $key]\n\n"}
        }
        if {[dict exists $row host_operation_contracts]} {
            append detail "Trusted host documentation only. These Tcl signatures do not authorize Script Bridge or C++ SDK calls.\n\n"
            append detail [apiBrowserHostContractsText [dict get $row host_operation_contracts] [datasetPublicationV2DictDefault $item operation {}]]
        }
        if {![dict exists $row operations] && ![dict exists $row script_descriptor]} {append detail "Exact operation signatures are not declared in this row. Open the owner manual; no argument or result type is inferred.\n"}
        if {[dict exists $row script_descriptor]} {append detail "Script Bridge exports are catalogued separately. Registration does not prove external tools/runtime availability or an active script.\n"}
    }
    event generate $w <<ApiCatalogSelection>>
    set text $w.body.details.text;$text configure -state normal;$text delete 1.0 end;$text insert end [string range $detail 0 262143];$text configure -state disabled
}
proc ::GX::apiBrowserManual {w} {
    variable ::GX::ApiBrowser::state
    if {![info exists state($w,selectedApi)]} {set state($w,status) {Select an API family or operation first.};apiBrowserStatusShow $w 1;return}
    set module viewer.interface_builder
    if {$state($w,language) in {Octave Python}} {set module [scriptAnalysisModule $state($w,language)]}
    if {[catch {documentationBrowserOpenApiWindow $state($w,selectedApi) $module [winfo toplevel $w]} reason]} {set state($w,status) "API manual unavailable: $reason";apiBrowserStatusShow $w 1;return}
    event generate $w <<ApiCatalogManual>>
}
proc ::GX::apiBrowserStatusShow {w visible} {
    if {![winfo exists $w.status]} return
    set mapped [expr {[winfo manager $w.status] ne {}}]
    if {$mapped==$visible} return
    if {$visible} {
        set before [expr {$::GX::ApiBrowser::state($w,presentation) eq {compact}?"$w.pages":"$w.manual"}]
        pack $w.status -side bottom -fill x -before $before
    } else {pack forget $w.status}
    set split [winfo parent $w]
    if {[info exists ::GX::ApiBrowser::state($split,visible)]} {apiBrowserSplitLayout $split}
    if {$::GX::ApiBrowser::state($w,presentation) eq {compact}} {apiBrowserCompactSchedule $w}
}
proc ::GX::apiBrowserMinimumHeight {browser} {
    set line [font metrics TkDefaultFont -linespace]
    set tree $browser.body.list.tree
    set row [expr {max($line,int(ceil(double([winfo reqheight $tree]-2)/max(1,[$tree cget -height]))))}]
    set scroll [winfo reqheight $browser.body.list.x]
    set status [expr {[winfo manager $browser.status] eq {} ? 0 : [winfo reqheight $browser.status]}]
    set textLine [font metrics [$browser.body.details.text cget -font] -linespace]
    set manual [expr {[winfo manager $browser.manual] eq {pack} ? [winfo reqheight $browser.manual] : 0}]
    set listMinimum [expr {3*$row+$scroll+4}]
    set detailMinimum [expr {4*$textLine+6}]
    return [dict create browser [expr {[winfo reqheight $browser.tools]+$manual+[winfo reqheight $browser.pages]+$status+$listMinimum+$detailMinimum+9}] explorer [expr {2*$line+$scroll+8}] list $listMinimum details $detailMinimum]
}
proc ::GX::apiBrowserCompactSchedule {w} {
    variable ::GX::ApiBrowser::state
    if {![winfo exists $w] || ![info exists state($w,presentation)]} return
    if {[info exists state($w,compactTimer)]} {after cancel $state($w,compactTimer)}
    set state($w,compactTimer) [after idle [list ::GX::apiBrowserCompactApply $w]]
}
proc ::GX::apiBrowserCompactApply {w} {
    variable ::GX::ApiBrowser::state
    unset -nocomplain state($w,compactTimer)
    if {![winfo exists $w.body] || ![winfo ismapped $w.body]} return
    set minimum [apiBrowserMinimumHeight $w]
    set needed [dict get $minimum browser]
    if {![info exists state($w,minimumHeight)] || $state($w,minimumHeight)!=$needed} {
        set state($w,minimumHeight) $needed
        event generate $w <<ApiBrowserLayout>> -when tail
    }
    set low [dict get $minimum list]
    set high [expr {[winfo height $w.body]-[dict get $minimum details]-5}]
    if {$high<$low} return
    set position [$w.body sashpos 0]
    set desired [expr {max($low,min($position,$high))}]
    if {$position!=$desired} {$w.body sashpos 0 $desired}
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
    if {[winfo exists $split]} {set editor [winfo toplevel $split];if {[info exists ::GX::WorkspaceAssist::state($editor,noteFocus)] && $::GX::WorkspaceAssist::state($editor,noteFocus)} {return}}
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
    apiCatalogInvalidate
    if {![llength [info commands winfo]]} return
    foreach name [array names state *,request] {
        set w [string range $name 0 end-8]
        if {[winfo exists $w]} {after idle [list ::GX::apiBrowserRefresh $w]}
    }
}

# Presentation state is bounded and contains no grants, handles or scientific data.
proc ::GX::apiBrowserCapture {w} {
    variable ::GX::ApiBrowser::state
    set result {};foreach key {query surface offset selectedRecord} {dict set result $key $state($w,$key)}
    return $result
}
proc ::GX::apiBrowserRestore {w value} {
    variable ::GX::ApiBrowser::state
    if {[catch {dict size $value}] || [string bytelength $value]>4096} {error {Invalid API Catalog presentation state}}
    foreach key [dict keys $value] {if {$key ni {query surface offset selectedRecord}} {error {Unknown API Catalog presentation field}}}
    set query [datasetPublicationV2DictDefault $value query {}]
    set surface [datasetPublicationV2DictDefault $value surface $state($w,surface)]
    set offset [datasetPublicationV2DictDefault $value offset 0]
    if {[string length $query]>256 || $surface ni {{All public} {Script Bridge} {C++ documentation} {C++ SDK} {Trusted host}} || ![string is integer -strict $offset] || $offset<0 || $offset>50000} {error {Invalid API Catalog presentation limits}}
    if {$state($w,scope) eq {editor} && $state($w,language) in {Python Octave} && $surface ne {Script Bridge}} {error {Script editors require the registered Script Bridge surface}}
    set state($w,query) $query;set state($w,surface) $surface;set state($w,offset) $offset
    set state($w,selectedRecord) [datasetPublicationV2DictDefault $value selectedRecord {}]
    apiBrowserSearch $w
}
proc ::GX::apiBrowserEnabled {w enabled} {
    if {![string is boolean -strict $enabled]} {error {API Catalog enabled must be boolean}}
    set ::GX::ApiBrowser::state($w,enabled) $enabled
    foreach widget [list $w.tools.query $w.tools.refresh $w.manual $w.body.list.tree] {if {[winfo exists $widget]} {$widget state [expr {$enabled?{!disabled}:{disabled}}]}}
    $w.tools.surface configure -state [expr {$enabled?{readonly}:{disabled}}]
    variable ::GX::ApiBrowser::state
    set previous [expr {$enabled && $state($w,offset)>0}]
    set next [expr {$enabled && $state($w,offset)+$state($w,count)<$state($w,total)}]
    $w.pages.previous state [expr {$previous?{!disabled}:{disabled}}]
    $w.pages.next state [expr {$next?{!disabled}:{disabled}}]
}
proc ::GX::apiBrowserCatalogStatusChanged {} {
    foreach name [array names ::GX::ApiBrowser::state *,language] {
        set w [string range $name 0 end-9]
        if {[winfo exists $w.body.list.tree]} {apiBrowserSearch $w}
    }
}
