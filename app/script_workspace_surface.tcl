# SPDX-License-Identifier: GPL-3.0-or-later
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

proc ::GX::scriptWorkspaceEditorSessionValid {parent token} {
    if {$::GX::currentSession eq {} || $token ne [interactiveDocumentSessionToken]} {
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
    if {$reference eq {}} {set reference $::GX::scriptWorkspaceChoice}
    if {$reference eq ""} { error "Select a registered script first." }
    set m [scriptRegistryDescribe $reference]
    set w .gxtxtScriptRun
    catch {destroy $w}
    toplevel $w
    wm title $w "Run [dict get $m name]"
    grid columnconfigure $w 1 -weight 1
    set scriptRunUi(reference) $reference
    set scriptRunUi(session_token) [interactiveDocumentSessionToken]
    set scriptRunUi(rerun) [expr {$previous ne {}}]
    set scriptRunUi(reviewed) 0
    set row 0
    ttk::label $w.info -text "[dict get $m language]  $reference  v[dict get $m version]  SHA-256: [dict get $m sha256]" -wraplength 600
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
        scriptJobSubmit $scriptRunUi(reference) $supplied $options ::GX::scriptWorkspaceSubmitted
        $w.run state disabled
        set scriptRunUi(status) {Submitting immutable script snapshot…}
    } reason]} {set scriptRunUi(status) "Submission failed: $reason"}
}
