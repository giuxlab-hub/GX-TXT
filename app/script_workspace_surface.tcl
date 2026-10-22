# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::scriptWorkspaceDecodeUtf8 {bytes} {
    set source [encoding convertfrom utf-8 $bytes]
    if {[encoding convertto utf-8 $source] ne $bytes} {error {Source must contain valid UTF-8 bytes.}}
    return $source
}
proc ::GX::scriptWorkspaceExplorerPresentation {tree} {
    # Keep script names readable when fixed provenance columns overflow.
    # The existing horizontal scrollbar exposes ID and update time on demand.
    $tree column name -minwidth 150
}
proc ::GX::scriptWorkspaceReferenceScroll {parent text} {
    ttk::scrollbar $parent.refScroll -command [list $text yview]
    $text configure -yscrollcommand [list $parent.refScroll set]
    pack $parent.refScroll -side right -fill y
    pack configure $text -side left -fill both -expand 1
}
# Optional Analysis surface for the always-available CORE Script Execution API.
namespace eval ::GX {
    variable scriptWorkspaceChoice ""
    variable scriptRunUi
    variable scriptAnalysisWidgets {}
}

proc ::GX::scriptAnalysisReferences {{language ""}} {
    set refs {}
    foreach item [scriptRegistryList session] {
        if {$language ne "" && [dict get $item language] ne $language} continue
        lappend refs "session:[dict get $item id]"
    }
    return $refs
}

proc ::GX::scriptAnalysisSelectorWidget {parent id key row} {
    variable moduleCfg
    variable scriptAnalysisWidgets
    ttk::label $parent.l$row -text "Session registered script"
    ttk::frame $parent.w$row
    ttk::combobox $parent.w$row.choice -textvariable ::GX::moduleCfg($id,$key) -state readonly -width 42
    ttk::button $parent.w$row.library -text "Script Library..." -command ::GX::scriptLibraryDialog
    ttk::label $parent.w$row.info -wraplength 640 -anchor w
    grid $parent.l$row -row $row -column 0 -sticky e -padx 4 -pady 2
    grid $parent.w$row -row $row -column 1 -sticky ew -padx 4 -pady 2
    grid $parent.w$row.info -row 1 -column 0 -columnspan 2 -sticky w
    grid $parent.w$row.choice -row 0 -column 0 -sticky ew
    grid $parent.w$row.library -row 0 -column 1 -sticky e
    grid columnconfigure $parent.w$row 0 -weight 1
    set widget $parent.w$row
    if {[lsearch -exact $scriptAnalysisWidgets [list $widget $id]] < 0} { lappend scriptAnalysisWidgets [list $widget $id] }
    bind $parent.w$row.choice <<ComboboxSelected>> {::GX::scriptAnalysisRefresh; catch {::GX::refreshManifestPreview}}
    scriptAnalysisRefresh
}

proc ::GX::scriptAnalysisRefresh {} {
    variable scriptAnalysisWidgets
    foreach id {analysis.octave_script analysis.python_script} {
        scriptAnalysisSyncRequiredApis $id
    }
    set keep {}
    foreach entry $scriptAnalysisWidgets {
        lassign $entry w id
        if {![winfo exists $w]} continue
        lappend keep $entry
        set language [expr {$id eq "analysis.python_script" ? "Python" : "Octave"}]
        set refs [scriptAnalysisReferences $language]
        $w.choice configure -values $refs
        set ref [expr {[info exists ::GX::moduleCfg($id,registered_script)] ? $::GX::moduleCfg($id,registered_script) : ""}]
        if {$ref eq ""} {
            $w.info configure -text "Assign a user script to this Session in Script Library, then select it here."
        } elseif {$ref ni $refs} {
            $w.info configure -text "Unavailable Session script: $ref"
        } elseif {[catch {set m [scriptRegistryDescribe $ref]} reason]} {
            $w.info configure -text $reason
        } else {
            $w.info configure -text "[dict get $m language] | ID [dict get $m id] | [dict get $m name] | version [dict get $m version] | revision [dict get $m revision] | SHA-256 [dict get $m sha256] | required APIs [dict get $m required_apis]"
        }
    }
    set scriptAnalysisWidgets $keep
}

proc ::GX::scriptAnalysisSyncRequiredApis {id} {
    variable moduleCfg
    if {$id ni {analysis.octave_script analysis.python_script}} { return 0 }
    if {![info exists moduleCfg($id,source_mode)] || $moduleCfg($id,source_mode) ne "registered_script"} { return 0 }
    if {![info exists moduleCfg($id,registered_script)]} { return 0 }
    set ref [string trim $moduleCfg($id,registered_script)]
    if {![string match "session:*" $ref]} { return 0 }
    if {[catch {set metadata [scriptRegistryDescribe $ref]}]} { return 0 }
    set moduleCfg($id,required_apis) [dict get $metadata required_apis]
    return 1
}

proc ::GX::scriptWorkspaceReferences {} {
    set refs {}
    foreach item [scriptRegistryList] {
        lappend refs "[dict get $item scope]:[dict get $item id]"
    }
    return $refs
}

proc ::GX::scriptWorkspaceRefreshChoices {} {
    scriptAnalysisRefresh
    set w .top.nb.analysis.scriptWorkspace
    if {![winfo exists $w]} return
    set refs [scriptWorkspaceReferences]
    $w.choice configure -values $refs
    if {$::GX::scriptWorkspaceChoice ni $refs} {
        set ::GX::scriptWorkspaceChoice [expr {[llength $refs] ? [lindex $refs 0] : ""}]
    }
    $w.run state [expr {$::GX::scriptWorkspaceChoice ne "" && $::GX::currentSession ne "" ? "!disabled" : "disabled"}]
    if {[winfo exists $w.delete]} {
        $w.delete state [expr {$::GX::scriptWorkspaceChoice ne "" ? "!disabled" : "disabled"}]
    }
}

proc ::GX::scriptWorkspaceDeleteSelected {} {
    set reference $::GX::scriptWorkspaceChoice
    if {$reference eq ""} return
    scriptLibraryRemoveReference $reference
}

proc ::GX::rebuildNativeAnalysisGui {} {
    ::GX::rebuildNativeAnalysisGui_before_core_script_surface
    if {![coreUiSurfaceVisible script_workspace]} return
    set host .top.nb.analysis
    set row 0
    foreach id $::GX::moduleOrder { if {[moduleIsRunnableAnalysis $id]} { incr row } }
    ttk::labelframe $host.scriptWorkspace -text "Scripts (CORE)"
    grid $host.scriptWorkspace -row $row -column 0 -sticky ew -padx 6 -pady 6
    grid columnconfigure $host.scriptWorkspace 1 -weight 1
    ttk::label $host.scriptWorkspace.intro -text "Run a registered user or Session script through CORE Script Execution. Session scripts are revisioned snapshots."
    grid $host.scriptWorkspace.intro -row 0 -column 0 -columnspan 3 -sticky w -padx 5 -pady 5
    ttk::label $host.scriptWorkspace.label -text "Registered script"
    ttk::combobox $host.scriptWorkspace.choice -textvariable ::GX::scriptWorkspaceChoice -state readonly -width 45
    ttk::button $host.scriptWorkspace.library -text "Script Library..." -command ::GX::scriptLibraryDialog
    ttk::button $host.scriptWorkspace.run -text "Run registered script..." -command ::GX::scriptWorkspaceRunDialog
    ttk::button $host.scriptWorkspace.delete -text "Delete selected..." -command ::GX::scriptWorkspaceDeleteSelected
    grid $host.scriptWorkspace.label -row 1 -column 0 -sticky e -padx 5 -pady 4
    grid $host.scriptWorkspace.choice -row 1 -column 1 -sticky ew -padx 5 -pady 4
    grid $host.scriptWorkspace.library -row 1 -column 2 -padx 5 -pady 4
    grid $host.scriptWorkspace.run -row 2 -column 1 -sticky w -padx 5 -pady 4
    grid $host.scriptWorkspace.delete -row 2 -column 2 -sticky w -padx 5 -pady 4
    ttk::button $host.scriptWorkspace.jobs -text {Script Jobs…} -command ::GX::scriptJobsDialog
    grid $host.scriptWorkspace.jobs -row 3 -column 1 -sticky w -padx 5 -pady 4
    scriptWorkspaceRefreshChoices
}

proc ::GX::scriptWorkspaceSessionToken {} {
    # User source has no scientific lifetime. Never invent a Session to edit it.
    if {$::GX::currentSession eq {}} {return {}}
    return [interactiveDocumentSessionToken]
}
proc ::GX::scriptWorkspaceDefaultScope {} {return [expr {$::GX::currentSession eq {} ? {user} : {session}}]}
proc ::GX::scriptWorkspaceEditorSessionValid {parent token {scope session}} {
    if {$scope eq {user}} {return 1}
    if {$::GX::currentSession eq {} || $token eq {} || $token ne [interactiveDocumentSessionToken]} {
        tk_messageBox -parent $parent -icon error -title {Editor Session changed} -message {The editor belongs to a different or closed Session. Export any unsaved buffer if needed, then reopen the editor in the intended Session before saving, deleting, registering or opening its Runner.}
        return 0
    }
    return 1
}
proc ::GX::scriptWorkspaceOpenEditorRunner {parent reference dirty saveCommand expectedSha sessionToken} {
    if {![scriptWorkspaceEditorSessionValid $parent $sessionToken]} {return 0}
    if {![regexp {^(session|user):.+$} $reference]} {
        tk_messageBox -parent $parent -icon info -title {Open Script Runner} -message {Save or explicitly register this script in Session or User scope first. Existing legacy documents remain unchanged. Run > Script Library is available for other registered scripts.}
        return 0
    }
    if {[catch {set metadata [scriptRegistryDescribe $reference]} failure]} {
        tk_messageBox -parent $parent -icon error -title {Registered script unavailable} -message $failure
        return 0
    }
    if {$dirty} {
        set message {This editor has unsaved changes. Yes: save changes and open the Runner. No: open the last saved revision and keep the editor changes. Cancel: return to editing. Opening the Runner does not submit a Job.}
        if {[dict get $metadata sha256] ne $expectedSha} {append message { The registered source also changed outside this editor: saving requires a reload; No opens the newer saved source shown in the Runner.}}
        set answer [tk_messageBox -parent $parent -icon question -type yesnocancel -default cancel -title {Choose the Runner revision} -message $message]
        switch -- $answer {
            yes {if {![uplevel #0 $saveCommand]} {return 0}}
            no {}
            default {return 0}
        }
    } elseif {[dict get $metadata sha256] ne $expectedSha} {
        set answer [tk_messageBox -parent $parent -icon warning -type okcancel -default cancel -title {Saved revision changed} -message {The registered source changed since this editor loaded it. Open the Runner for the newer saved revision? Its SHA and metadata will be shown before any Job can be submitted. The editor buffer remains unchanged.}]
        if {$answer ne "ok"} {return 0}
    }
    scriptWorkspaceRunDialog $reference
    return 1
}

proc ::GX::scriptWorkspaceRunDialog {{reference {}} {previous {}}} {
    variable scriptRunUi
    if {$::GX::currentSession eq {} || ![file isdirectory $::GX::currentSession]} {
        tk_messageBox -parent . -icon info -title {Script Runner requires a Session} -message {Open the intended scientific Session before reviewing or running a registered script. No Job has been submitted.}
        return
    }
    if {$reference eq {}} {set reference $::GX::scriptWorkspaceChoice}
    if {$reference eq ""} { error "Select a registered script first." }
    set m [scriptRegistryDescribe $reference]
    set w .gxtxtScriptRun
    if {$previous eq {} && [winfo exists $w] && $scriptRunUi(reference) eq $reference && $scriptRunUi(session_token) eq [interactiveDocumentSessionToken] && [dict get $scriptRunUi(metadata) sha256] eq [dict get $m sha256]} {
        raise $w;focus $w
        return $w
    }
    catch {destroy $w}
    toplevel $w
    wm title $w "Run [dict get $m name]"
    grid columnconfigure $w 1 -weight 1
    set scriptRunUi(reference) $reference
    set scriptRunUi(session_token) [interactiveDocumentSessionToken]
    set scriptRunUi(rerun) [expr {$previous ne {}}]
    set scriptRunUi(reviewed) 0
    set row 0
    set reviewInfo "[dict get $m language]  $reference  v[dict get $m version]  SHA-256: [dict get $m sha256]"
    if {[datasetPublicationV2DictDefault $m default_arguments {}] ne {}} {append reviewInfo "\nSaved default arguments: [dict get $m default_arguments]"}
    ttk::label $w.info -text $reviewInfo -wraplength 600
    grid $w.info -row $row -column 0 -columnspan 2 -sticky ew -padx 8 -pady 8
    incr row
    dict for {name descriptor} [dict get $m parameters] {
        set scriptRunUi(parameter,$name) [dict get $descriptor default]
        ttk::label $w.l_$name -text "$name ([dict get $descriptor type])"
        uiFieldCreate $w.e_$name $descriptor ::GX::scriptRunUi(parameter,$name)
        grid $w.l_$name -row $row -column 0 -sticky e -padx 6 -pady 4
        grid $w.e_$name -row $row -column 1 -sticky ew -padx 6 -pady 4
        incr row
    }
    set scriptRunUi(metadata) $m
    set row [scriptRunBindingsBuild $w $row]
    if {$previous ne {}} {
        set review "NEW Job after explicit review. Historical [dict get $previous id] stays unchanged.\nOriginal $reference revision [scriptJobField $previous script_revision] SHA [scriptJobField $previous source_sha256]\nAvailable $reference revision [dict get $m revision] SHA [dict get $m sha256]"
        dict for {name value} [scriptJobField $previous parameters {}] {
            if {[dict exists $m parameters $name]} {set scriptRunUi(parameter,$name) $value} else {append review "\nPrevious parameter '$name' is absent from the current Script; review its new schema."}
        }
        dict for {alias binding} [scriptJobField $previous inputs {}] {
            scriptRunBindingAdd
            set n $scriptRunUi(input_count);set id [dict get $binding dataset_id]
            set scriptRunUi(alias,$n) $alias;set scriptRunUi(label,$n) [datasetPublicationV2DictDefault $binding label {}]
            set available [expr {$id in $scriptRunUi(eligible)}]
            if {$available && [dict exists $binding revision]} {
                if {[catch {datasetRevisionToken $id $::GX::currentSession} revision] || $revision ne [dict get $binding revision]} {set available 0;append review "\nInput $alias / $id revision changed: explicitly rebind it."}
            }
            if {$available} {set scriptRunUi(dataset,$n) $id} else {append review "\nInput $alias / $id is missing, changed or outside current namespace: choose a valid binding."}
        }
        set output [scriptJobField $previous output {}]
        if {[dict exists $output dataset_id]} {
            set scriptRunUi(output_id) [dict get $output dataset_id]
            set scriptRunUi(output_label) [datasetPublicationV2DictDefault $output label {}]
            if {[datasetField $scriptRunUi(output_id) id {}] ne {}} {append review "\nOutput $scriptRunUi(output_id) already exists: choose a new ID or deliberately request an authorized owned replacement."}
        }
        $w.info configure -text "[$w.info cget -text]\n$review"
        grid $w.bindings
        ttk::checkbutton $w.review -text {I reviewed the current Script, parameters, inputs and output request} -variable ::GX::scriptRunUi(reviewed)
        grid $w.review -row $row -column 0 -columnspan 2 -sticky w -padx 8 -pady 5
        incr row
    }
    ttk::button $w.run -text Run -command ::GX::scriptWorkspaceRunCommit
    ttk::button $w.cancel -text Close -command [list destroy $w]
    grid $w.run -row $row -column 0 -padx 8 -pady 8
    grid $w.cancel -row $row -column 1 -sticky w -padx 8 -pady 8
    incr row
    ttk::label $w.status -textvariable ::GX::scriptRunUi(status) -wraplength 600
    grid $w.status -row $row -column 0 -columnspan 2 -sticky ew -padx 8 -pady 6
    set scriptRunUi(status) "Ready to run in the current Session."
}

proc ::GX::scriptWorkspaceRunCommit {} {
    variable scriptRunUi
    set w .gxtxtScriptRun
    if {[catch {
        if {$scriptRunUi(session_token) ne [interactiveDocumentSessionToken]} {error {Session changed; reopen the Run review}}
        if {$scriptRunUi(rerun) && !$scriptRunUi(reviewed)} {error {Explicit review is required before creating a new Job}}
        if {[dict get [scriptRegistryDescribe $scriptRunUi(reference)] sha256] ne [dict get $scriptRunUi(metadata) sha256]} {error {Registered Script changed during review; reopen Run and review the current revision}}
        set supplied [dict create]
        dict for {name descriptor} [dict get $scriptRunUi(metadata) parameters] {
            if {$scriptRunUi(parameter,$name) ne ""} {dict set supplied $name $scriptRunUi(parameter,$name)}
        }
        set inputs {}
        for {set n 1} {$n <= $scriptRunUi(input_count)} {incr n} {
            if {![winfo exists $w.bindings.r$n]} continue
            set alias $scriptRunUi(alias,$n)
            if {[dict exists $inputs $alias]} {error "Duplicate input alias '$alias'"}
            dict set inputs $alias [dict create dataset_id $scriptRunUi(dataset,$n) label $scriptRunUi(label,$n)]
        }
        set output {}
        if {$scriptRunUi(output_id) ne {}} {set output [dict create dataset_id $scriptRunUi(output_id) label $scriptRunUi(output_label) replace_owned $scriptRunUi(replace)]}
        set options [dict create session $scriptRunUi(session) namespace $scriptRunUi(namespace) inputs $inputs output $output]
        if {[info exists scriptRunUi(importOverride)] && $scriptRunUi(importOverride)} {dict set options import_policy continue}
        scriptJobSubmit $scriptRunUi(reference) $supplied $options ::GX::scriptWorkspaceSubmitted
        $w.run state disabled
        set scriptRunUi(status) {Submitting immutable script snapshot…}
    } reason]} {set scriptRunUi(status) "Submission failed: $reason"}
}

# The horizontal editor panes never change ownership when an assistant opens.
# Assistants share a lower notebook; a separate bindtag survives client Destroy
# bindings and releases presentation state even when the client replaces its own.
namespace eval ::GX::WorkspaceAssist {variable panels {};variable state}
proc ::GX::scriptWorkspaceViewMenu {editor menu language} {
    variable ::GX::WorkspaceAssist::state
    set state($editor,language) $language
    foreach {key label value} {left {Script Explorer / Registered scripts} 1 right {GX-TXT Bridge Snippets} 1 debug Debugger 0} {
        set state($editor,$key) $value
        $menu add checkbutton -label $label -variable ::GX::WorkspaceAssist::state($editor,$key) -command [list ::GX::scriptWorkspacePaneToggle $editor $key]
    }
    $menu add separator
    foreach {key label} {stack {Call Stack} variables {Variables / Locals} output {Debug Output / Console} breakpoints Breakpoints} {
        set state($editor,debug_$key) 0
        $menu add checkbutton -label $label -variable ::GX::WorkspaceAssist::state($editor,debug_$key) -command [list ::GX::scriptWorkspaceDebugPaneToggle $editor $key]
    }
    $menu add separator
    $menu add checkbutton -label {API Browser} -variable ::GX::ApiBrowser::state($editor.p.left.apiSplit,visible) -command [list ::GX::apiBrowserToggle $editor.p.left]
    $menu add command -label {Focus source / restore panes} -command [list ::GX::scriptWorkspaceFocusSource $editor]
    $menu add command -label {Reset editor layout} -command [list ::GX::scriptWorkspaceLayoutReset $editor]
    $menu add separator
    set state($editor,properties) 1
    $menu add checkbutton -label {Script properties / parameters} -variable ::GX::WorkspaceAssist::state($editor,properties) -command [list ::GX::scriptWorkspacePropertiesToggle $editor 1]
    $menu configure -postcommand [list ::GX::scriptWorkspaceViewRefresh $editor]
}
proc ::GX::scriptWorkspaceFindLayout {editor width} {
    variable ::GX::WorkspaceAssist::state
    set row $editor.p.center.find
    if {![winfo exists $row]} return
    set mode [expr {$width<360 ? {wrapped} : {inline}}]
    if {[info exists state($editor,findMode)] && $state($editor,findMode) eq $mode} return
    set state($editor,findMode) $mode
    foreach child [winfo children $row] {pack forget $child;grid forget $child}
    $row.e configure -width 8
    grid columnconfigure $row 1 -weight 1
    grid $row.l -row 0 -column 0 -sticky w -padx {0 5}
    if {$mode eq {wrapped}} {
        grid $row.e -row 0 -column 1 -columnspan 3 -sticky ew
        grid $row.prev -row 1 -column 2 -sticky e -padx {0 5} -pady {3 0}
        grid $row.next -row 1 -column 3 -sticky e -pady {3 0}
    } else {
        grid $row.e -row 0 -column 1 -sticky ew -padx {0 5}
        grid $row.prev -row 0 -column 2 -padx {0 5}
        grid $row.next -row 0 -column 3
    }
}
proc ::GX::scriptWorkspaceLayoutInit {editor} {
    variable ::GX::WorkspaceAssist::state
    bind GXScriptWorkspaceAssistant <Destroy> {::GX::scriptWorkspaceAssistDestroyed %W %W}
    set center $editor.p.center
    if {[winfo exists $center.work]} return
    apiBrowserMount $editor.p.left $state($editor,language)
    ttk::panedwindow $center.work -orient vertical
    pack $center.work -side top -fill both -expand 1 -before $center.edit
    pack forget $center.edit
    $center.work add $center.edit -weight 3
    raise $center.edit
    # Reserve Find before the expanding source/assistant region at short sizes.
    pack configure $center.find -before $center.work
    bind $center.find <Configure> [list ::GX::scriptWorkspaceFindLayout $editor %w]
    scriptWorkspaceFindLayout $editor [winfo width $center.find]
    ttk::notebook $center.work.tools
    ttk::button $center.propertiesToggle -text {Show script properties / parameters} -command [list ::GX::scriptWorkspacePropertiesToggle $editor]
    set state($editor,propertyPack) {}
    foreach name {props desc params} {if {[winfo exists $center.$name]} {dict set state($editor,propertyPack) $center.$name [pack info $center.$name]}}
    set state($editor,focus) {}
    set state($editor,restoreSides) {}
    set state($editor,fractions) {.19 .78};set state($editor,sourceFraction) .40
    bind $editor.p <ButtonRelease-1> +[list ::GX::scriptWorkspaceLayoutRemember $editor]
    bind $center.work <ButtonRelease-1> +[list ::GX::scriptWorkspaceLayoutRemember $editor]
    bind $center.work <Configure> [list ::GX::scriptWorkspaceVerticalSize $editor %h]
    bind $editor <Destroy> +[list ::GX::scriptWorkspaceLayoutDestroyed $editor %W]
    # Initial fractions use the actual mapped width, never child request widths.
    set state($editor,initialTimer) [after 150 [list ::GX::scriptWorkspaceLayoutRestore $editor]]
}
proc ::GX::scriptWorkspaceViewRefresh {editor} {
    variable ::GX::WorkspaceAssist::state
    if {![winfo exists $editor.p]} return
    foreach side {left right} {set state($editor,$side) [expr {"$editor.p.$side" in [$editor.p panes]}]}
    set tools $editor.p.center.work.tools
    foreach key {stack variables output breakpoints} {
        if {[info exists ::GX::ScriptDebug::state($editor.p.debug,$key)]} {
            set widget $::GX::ScriptDebug::state($editor.p.debug,$key)
            set state($editor,debug_$key) [expr {[winfo exists $widget] && [winfo ismapped $widget]}]
        } else {set state($editor,debug_$key) 0}
    }
    set state($editor,debug) [expr {[winfo exists $editor.p.debug] && $tools in [$editor.p.center.work panes] && [$tools tab $editor.p.debug -state] ne {hidden}}]
}
proc ::GX::scriptWorkspacePaneToggle {editor key} {
    variable ::GX::WorkspaceAssist::state
    scriptWorkspaceLayoutFractions $editor
    if {$key eq {debug}} {
        set tools $editor.p.center.work.tools
        if {$state($editor,debug)} {
            if {![winfo exists $editor.p.debug]} {scriptDebugOpen $editor $state($editor,language)} else {scriptWorkspaceAssistMount $editor $editor.p.debug}
        } elseif {[winfo exists $editor.p.debug]} {
            $tools hide $editor.p.debug
            scriptWorkspaceAssistReconcile $editor
        }
    } else {
        set p $editor.p;set w $p.$key
        set state($editor,layoutPending) 1
        if {$state($editor,$key)} {if {$w ni [$p panes]} {if {$key eq {left}} {$p insert 0 $w -weight 1} else {$p add $w -weight 1}}} elseif {$w in [$p panes]} {$p forget $w}
        scriptWorkspaceLayoutSchedule $editor
    }
    scriptWorkspaceViewRefresh $editor
    scriptWorkspaceLayoutRemember $editor
}
proc ::GX::scriptWorkspaceLayoutSchedule {editor} {
    variable ::GX::WorkspaceAssist::state
    if {[info exists state($editor,layoutTimer)]} {after cancel $state($editor,layoutTimer)}
    set state($editor,layoutPending) 1
    set state($editor,layoutTimer) [after idle [list ::GX::scriptWorkspaceLayoutSettle $editor]]
}
proc ::GX::scriptWorkspaceLayoutSettle {editor} {
    variable ::GX::WorkspaceAssist::state
    if {![winfo exists $editor.p]} return
    unset -nocomplain state($editor,layoutTimer)
    # ttk computes pane allocation lazily on add/forget. Let that allocation
    # finish while remembering is suspended, then apply the retained geometry.
    update idletasks
    if {![winfo exists $editor.p]} return
    scriptWorkspaceHorizontalSize $editor
    update idletasks
    if {![winfo exists $editor.p]} return
    set state($editor,layoutPending) 0
    scriptWorkspaceLayoutRemember $editor
}
proc ::GX::scriptWorkspaceHorizontalSize {editor} {
    if {![winfo exists $editor.p]} return
    variable ::GX::WorkspaceAssist::state
    lassign $state($editor,fractions) left right
    set p $editor.p;set width [winfo width $p]
    if {$width<10} return
    set sides [$p panes]
    if {[llength $sides]<2} return
    set minimum [expr {min(120,max(60,int($width*.10)))}]
    set sourceMinimum [expr {min(240,max(100,int($width*.30)))}]
    set leftPixel [expr {max($minimum,min(int($width*$left),int(($width-$sourceMinimum)/2)))}]
    set rightPixel [expr {min($width-$minimum,max(int($width*$right),$leftPixel+$sourceMinimum))}]
    if {"$p.left" in $sides} {$p sashpos 0 $leftPixel}
    if {"$p.right" in $sides} {$p sashpos [expr {[llength $sides]-2}] $rightPixel}
}
proc ::GX::scriptWorkspaceVerticalSize {editor height} {
    variable ::GX::WorkspaceAssist::state
    set work $editor.p.center.work
    if {![winfo exists $work] || $height<180 || "$work.tools" ni [$work panes]} return
    # Preserve the chosen source fraction when resizing the parent. Native
    # panedwindow weights alone otherwise consume most of the source on shrink.
    $work sashpos 0 [expr {max(70,min($height-160,int($height*$state($editor,sourceFraction))))}]
}
proc ::GX::scriptWorkspaceLayoutReset {editor} {
    variable ::GX::WorkspaceAssist::state
    if {![winfo exists $editor.p]} return
    set p $editor.p
    set state($editor,fractions) {.19 .78};set state($editor,sourceFraction) .40
    set state($editor,layoutPending) 1
    foreach side {left right} {if {"$p.$side" ni [$p panes]} {if {$side eq {left}} {$p insert 0 $p.$side -weight 1} else {$p add $p.$side -weight 1}}}
    scriptWorkspaceLayoutSchedule $editor
    set state($editor,restoreSides) {}
    scriptWorkspaceViewRefresh $editor
    scriptWorkspaceLayoutRemember $editor
}
proc ::GX::scriptWorkspaceFocusSource {editor} {
    variable ::GX::WorkspaceAssist::state
    set p $editor.p
    scriptWorkspaceLayoutFractions $editor
    set state($editor,layoutPending) 1
    if {$state($editor,restoreSides) eq {}} {
        set state($editor,restoreSides) [$p panes]
        foreach side {left right} {if {"$p.$side" in [$p panes]} {$p forget $p.$side}}
    } else {
        foreach side {left right} {set w $p.$side;if {$w in $state($editor,restoreSides) && $w ni [$p panes]} {if {$side eq {left}} {$p insert 0 $w -weight 1} else {$p add $w -weight 1}}}
        set state($editor,restoreSides) {}
    }
    scriptWorkspaceLayoutSchedule $editor
    focus $p.center.edit.text
    scriptWorkspaceViewRefresh $editor
}
proc ::GX::scriptWorkspaceAssistMount {editor panel} {
    variable ::GX::WorkspaceAssist::state
    scriptWorkspaceLayoutInit $editor
    set work $editor.p.center.work;set tools $work.tools
    if {![dict exists $::GX::WorkspaceAssist::panels $panel]} {
        dict set ::GX::WorkspaceAssist::panels $panel $editor
        set title [expr {[file tail [string map {. /} $panel]] eq {debug} ? {Debugger} : {Import assistant}}]
        $tools add $panel -text $title
        bindtags $panel [linsert [bindtags $panel] 1 GXScriptWorkspaceAssistant]
    } else {$tools add $panel}
    if {$tools ni [$work panes]} {
        set state($editor,focus) [focus]
        $work add $tools -weight 2
        update idletasks
        $work sashpos 0 [expr {max(100,int([winfo height $work]*$state($editor,sourceFraction)))}]
    }
    $tools select $panel
    scriptWorkspaceViewRefresh $editor
    return $panel
}
proc ::GX::scriptWorkspaceAssistReconcile {editor} {
    variable ::GX::WorkspaceAssist::state
    if {![winfo exists $editor.p.center.work]} return
    set work $editor.p.center.work;set tools $work.tools;set visible 0
    foreach tab [$tools tabs] {if {[$tools tab $tab -state] ne {hidden}} {incr visible}}
    if {!$visible && $tools in [$work panes]} {
        $work forget $tools
        if {[info exists state($editor,focus)] && [winfo exists $state($editor,focus)]} {focus $state($editor,focus)}
    }
    scriptWorkspaceViewRefresh $editor
}
proc ::GX::scriptWorkspaceAssistDestroyed {panel actual} {
    if {$actual ne $panel || ![dict exists $::GX::WorkspaceAssist::panels $panel]} return
    set editor [dict get $::GX::WorkspaceAssist::panels $panel]
    dict unset ::GX::WorkspaceAssist::panels $panel
    if {[winfo exists $editor.p.center.work.tools]} {
        catch {$editor.p.center.work.tools forget $panel}
        scriptWorkspaceAssistReconcile $editor
    }
}
proc ::GX::scriptWorkspaceLayoutDestroyed {editor actual} {
    if {$editor ne $actual} return
    variable ::GX::WorkspaceAssist::state
    if {[info exists state($editor,initialTimer)]} {catch {after cancel $state($editor,initialTimer)}}
    if {[info exists state($editor,layoutTimer)]} {after cancel $state($editor,layoutTimer)}
    dict for {panel owner} $::GX::WorkspaceAssist::panels {if {$owner eq $editor} {dict unset ::GX::WorkspaceAssist::panels $panel}}
    array unset state $editor,*
}

proc ::GX::scriptWorkspaceLayoutFractions {editor} {
    variable ::GX::WorkspaceAssist::state
    if {![winfo exists $editor.p] || [winfo width $editor.p]<10 || ([info exists state($editor,layoutPending)] && $state($editor,layoutPending))} return
    set p $editor.p;set panes [$p panes];set width [winfo width $p]
    lassign $state($editor,fractions) left right
    if {"$p.left" in $panes && [llength $panes]>1} {
        set position [$p sashpos 0]
        if {$position>=40 && $position<$width-100} {set left [expr {$position/double($width)}]}
    }
    if {"$p.right" in $panes && [llength $panes]>1} {
        set position [$p sashpos [expr {[llength $panes]-2}]]
        if {$position>100 && $position<=$width-40} {set right [expr {$position/double($width)}]}
    }
    set state($editor,fractions) [list $left $right]
}
proc ::GX::scriptWorkspaceLayoutRemember {editor} {
    variable ::GX::WorkspaceAssist::state
    if {![winfo exists $editor.p] || ![info exists state($editor,language)]} return
    scriptWorkspaceLayoutFractions $editor
    set work $editor.p.center.work
    if {"$work.tools" in [$work panes] && [winfo height $work]>10} {set state($editor,sourceFraction) [expr {[$work sashpos 0]/double([winfo height $work])}]}
    set key scripts.editor_layout.[string tolower $state($editor,language)]
    set prior [configurationGet $key]
    if {[catch {dict size $prior}]} {set prior {}}
    set value [dict merge $prior [dict create properties $state($editor,properties) left [expr {"$editor.p.left" in [$editor.p panes]}] right [expr {"$editor.p.right" in [$editor.p panes]}] fractions $state($editor,fractions) source_fraction $state($editor,sourceFraction)]]
    configurationSet $key $value;configurationSave [list $key]
}
proc ::GX::scriptWorkspaceLayoutRestore {editor} {
    variable ::GX::WorkspaceAssist::state
    if {![winfo exists $editor.p]} return
    set key scripts.editor_layout.[string tolower $state($editor,language)]
    set saved [configurationGet $key]
    if {![dict exists $saved properties]} {dict set saved properties 1}
    if {[catch {
        foreach side {left right properties} {if {![string is boolean -strict [dict get $saved $side]]} {error {Invalid side visibility}}}
        foreach value [concat [dict get $saved fractions] [dict get $saved source_fraction]] {if {![string is double -strict $value] || $value<=.05 || $value>=.95} {error {Invalid splitter fraction}}}
        if {[llength [dict get $saved fractions]]!=2} {error {Two horizontal splitter fractions required}}
        lassign [dict get $saved fractions] savedLeft savedRight
        if {$savedRight-$savedLeft<.10} {error {Source pane requires usable width}}
    }]} {set saved {left 1 right 1 properties 1 fractions {.19 .78} source_fraction .40}}
    set state($editor,properties) [dict get $saved properties]
    scriptWorkspacePropertiesToggle $editor 1 0
    set state($editor,fractions) [dict get $saved fractions];set state($editor,sourceFraction) [dict get $saved source_fraction]
    foreach side {left right} {
        set pane $editor.p.$side
        if {![dict get $saved $side] && $pane in [$editor.p panes]} {$editor.p forget $pane}
    }
    scriptWorkspaceLayoutSchedule $editor
    scriptWorkspaceViewRefresh $editor
}
proc ::GX::scriptWorkspaceDebugPaneToggle {editor key} {
    variable ::GX::WorkspaceAssist::state
    set visible $state($editor,debug_$key)
    set p $editor.p.debug
    if {![winfo exists $p]} {scriptDebugOpen $editor $state($editor,language)}
    scriptWorkspaceAssistMount $editor $p
    if {$key in {stack variables}} {
        set panes $p.book.live.p;set child $panes.$key
        if {$visible} {if {$child ni [$panes panes]} {if {$key eq {stack}} {$panes insert 0 $child -weight 2} else {$panes add $child -weight 3}}} elseif {$child in [$panes panes]} {$panes forget $child}
        if {[llength [$panes panes]]==0} {pack forget $panes;pack $p.book.live.empty -fill both -expand 1} else {pack forget $p.book.live.empty;pack $panes -fill both -expand 1}
        $p.book tab $p.book.live -state normal;$p.book select $p.book.live
    } else {
        if {$visible} {$p.book tab $p.book.$key -state normal;$p.book select $p.book.$key} else {$p.book hide $p.book.$key}
    }
    update idletasks;scriptWorkspaceViewRefresh $editor
}

proc ::GX::scriptWorkspacePropertiesToggle {editor {fromMenu 0} {persist 1}} {
    variable ::GX::WorkspaceAssist::state
    if {!$fromMenu} {set state($editor,properties) [expr {!$state($editor,properties)}]}
    set center $editor.p.center
    if {$state($editor,properties)} {
        pack forget $center.propertiesToggle
        dict for {widget options} $state($editor,propertyPack) {pack $widget {*}$options -before $center.find}
    } else {
        dict for {widget options} $state($editor,propertyPack) {pack forget $widget}
        pack $center.propertiesToggle -side top -fill x -before $center.find
    }
    if {$persist} {scriptWorkspaceLayoutRemember $editor}
}
