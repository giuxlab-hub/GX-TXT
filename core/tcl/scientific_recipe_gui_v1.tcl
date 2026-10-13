# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::scientificRecipeDialog {window owner contextCommand parent} {
    if {[winfo exists $window]} {raise $window;return}
    toplevel $window;wm title $window "Scientific Recipe Recorder";wm transient $window $parent
    ttk::label $window.description -text "Semantic operations with logical IDs, units and source fingerprints. Replay replaces this Workbench state as one Undo action. Python prepares the same validated proposal in Script Workspace and an installed Builder extension." -wraplength 640 -justify left
    pack $window.description -fill x -padx 10 -pady 8
    ttk::treeview $window.steps -columns {api operation targets results unit} -show headings -height 12
    foreach {key label width} {api {Public API} 240 operation Operation 160 targets Targets 130 results Results 130 unit Unit 65} {$window.steps heading $key -text $label;$window.steps column $key -width $width}
    ttk::scrollbar $window.scroll -orient horizontal -command [list $window.steps xview];$window.steps configure -xscrollcommand [list $window.scroll set]
    pack $window.scroll -side bottom -fill x;pack $window.steps -fill both -expand 1 -padx 10
    ttk::frame $window.actions;pack $window.actions -side bottom -fill x -padx 10 -pady 8 -before $window.steps
    foreach {key label action} {refresh Refresh refresh validate {Validate replay} validate replay {Replay current recipe} replay export {Export recipe as Python script…} export} {
        ttk::button $window.actions.$key -text $label -command [list ::GX::_scientificRecipeGuiSafe $window $owner $contextCommand $action];pack $window.actions.$key -side left -padx 3
    }
    bind $window.actions <Configure> [list ::GX::uiFieldControlsLayout $window.actions %w]
    ttk::label $window.status -text {} -wraplength 640 -justify left;pack $window.status -side bottom -fill x -padx 10 -pady 5 -before $window.steps
    bind $window.steps <Configure> [list ::GX::uiFieldInspectionColumnsSchedule $window.steps]
    wm geometry $window 900x470;wm minsize $window 620 340;bind $window <Escape> [list destroy $window]
    _scientificRecipeGuiSafe $window $owner $contextCommand refresh
}
proc ::GX::_scientificRecipeGuiSafe {window owner contextCommand action} {
    if {[catch {
        set context [uplevel #0 $contextCommand];set encoded [scientificRecipeCapture $owner $context]
        if {$action eq "refresh"} {
            $window.steps delete [$window.steps children {}]
            foreach step [dict get [scientificRecipeDecode $encoded] steps] {$window.steps insert {} end -values [list [dict get $step api_id] [datasetPublicationV2DictDefault $step semantic_operation [dict get $step operation]] [dict get $step targets] [dict get $step result_ids] [dict get $step working_unit]]}
            uiFieldInspectionColumnsFit $window.steps
            set message "[llength [$window.steps children {}]] recorded semantic operations."
        } elseif {$action eq "validate"} {scientificRecipeValidate $encoded;set message "Replay validated: APIs, plugins, units, logical references, resources and Dataset fingerprints."} elseif {$action eq "replay"} {
            scientificRecipeReplay $owner $context $encoded;set message "Recipe replay committed as one Undo action."
        } else {
            set path [tk_getSaveFile -parent $window -title "Export recipe as Python script" -defaultextension .py -filetypes {{{Python script} {.py}}}]
            if {$path eq {}} return
            scientificRecipeExportPython $encoded $path;set message "Python script exported. Open it in Script Workspace or build profile W without changing its source."
        }
    } message]} {$window.status configure -text "Failed: $message";return}
    $window.status configure -text $message
}
