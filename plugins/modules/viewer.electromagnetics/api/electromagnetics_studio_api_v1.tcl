# GX-TXT Electromagnetics Studio Viewer Provider adapter.
# SPDX-License-Identifier: GPL-3.0-or-later
# All user-visible strings are English; physics/solver/publishing live in CORE.
namespace eval ::GX::ElectromagneticsStudio {
    variable root [file normalize [file join [file dirname [info script]] ..]]
    variable window .gxtxt_electromagnetics_studio
    variable state
    array set state {}
}
proc ::GX::ElectromagneticsStudio::_close {} {
    variable window
    ::GX::sessionWorkspaceViewerAction em_models [_callbacks] $window close
}
proc ::GX::ElectromagneticsStudio::_closeWindow {} {
    variable state;variable window
    if {[info exists state(poll)]} {after cancel $state(poll);unset state(poll)}
    catch {destroy $window}
}
proc ::GX::ElectromagneticsStudio::_core {} {
    ::GX::modulePublicApiActivate math.electromagnetic_simulation ELECTROMAGNETIC_SIMULATION_API_v1
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
}
proc ::GX::ElectromagneticsStudio::_setStatus {message} {
    variable state
    set state(status) $message
}
proc ::GX::ElectromagneticsStudio::_invoke {command} {
    variable state;variable window
    if {![winfo exists $window]} return
    if {[catch {if {$state(token) ne [::GX::interactiveDocumentSessionToken]} {error {Electromagnetics window belongs to a previous Session; reopen it.}};uplevel #0 $command} failure options]} {_setStatus "Error: $failure";tk_messageBox -parent $window -icon error -title {Electromagnetics Studio} -message $failure}
    _controls
}
proc ::GX::ElectromagneticsStudio::_collect {} {
    variable state;set model {}
    foreach key {kind model_id formulation half_width_m height_m mesh_size_m radius_m current_density_A_m2 mu_r voltage_V eps_r} {dict set model $key $state($key)}
    return $model
}
proc ::GX::ElectromagneticsStudio::_loadDict {model} {
    variable state
    dict for {key value} $model {if {$key in {kind model_id formulation half_width_m height_m mesh_size_m radius_m current_density_A_m2 mu_r voltage_V eps_r}} {set state($key) $value}}
    _teaching;_controls
}
proc ::GX::ElectromagneticsStudio::_new {kind} {
    variable state;_core;_loadDict [::GX::ElectromagneticSimulation::defaultModel $kind]
    set state(document) {};set state(saved_model) {};set state(job) {};set state(dataset) {};set state(last_result) {};set state(busy) 0
    _setStatus "New unsaved $kind model, SI units. Managed Jobs continue independently of this window.";_controls
}
proc ::GX::ElectromagneticsStudio::_kindChanged {} {
    variable state
    _teaching;_controls;_setStatus {Physics changed in the draft. Save to commit a new Workspace revision.}
}
proc ::GX::ElectromagneticsStudio::_validate {} {
    _core
    set result [::GX::ElectromagneticSimulation::validate [_collect]]
    _setStatus "Model validated (not yet meshed or solved)."
    _writeResult "Model validation only:\n$result\n\nA successful solver receipt is required before publication."
}
proc ::GX::ElectromagneticsStudio::_saveModel {} {
    variable state;_core
    set saved [::GX::ElectromagneticSimulation::saveModel [_collect] $state(document) $state(workspace_name)]
    set state(document) [dict get $saved id];set state(workspace_name) [dict get $saved name];set state(saved_model) [::GX::ElectromagneticSimulation::loadModel $state(document)]
    _setStatus "Saved Session Workspace $state(document).";return $state(document)
}
proc ::GX::ElectromagneticsStudio::_duplicate {} {variable window;::GX::sessionWorkspaceViewerAction em_models [_callbacks] $window duplicate}
proc ::GX::ElectromagneticsStudio::_openModel {} {variable window;::GX::sessionWorkspaceDialog $window em_models [_callbacks]}
proc ::GX::ElectromagneticsStudio::_callbacks {} {
    dict create current ::GX::ElectromagneticsStudio::_current dirty ::GX::ElectromagneticsStudio::_dirty save ::GX::ElectromagneticsStudio::_saveModel open ::GX::ElectromagneticsStudio::open close ::GX::ElectromagneticsStudio::_closeWindow discard ::GX::ElectromagneticsStudio::_closeWindow
}
proc ::GX::ElectromagneticsStudio::_current {} {variable state;return $state(document)}
proc ::GX::ElectromagneticsStudio::_dirty {} {
    variable state
    if {[catch {set model [dict get [::GX::ElectromagneticSimulation::validate [_collect]] model]}]} {return 1}
    return [expr {$model ne $state(saved_model)}]
}
proc ::GX::ElectromagneticsStudio::open {{context {}}} {
    variable state;variable window
    if {[winfo exists $window]&&$state(token) ne [::GX::interactiveDocumentSessionToken]} {_closeWindow}
    set result [_make]
    if {[dict exists $context workspace_id]} {set id [dict get $context workspace_id];if {$id eq {new}} {set state(workspace_name) [dict get $context workspace_name];_saveModel} else {_loadDict [::GX::ElectromagneticSimulation::loadModel $id];set state(document) $id;set state(workspace_name) [dict get [::GX::sessionWorkspaceGet $id] name];set state(saved_model) [_collect];_reconnect};_controls}
    return $result
}
proc ::GX::ElectromagneticsStudio::_reconnect {} {
    variable state
    if {$state(document) eq {}} return
    foreach job [::GX::scriptJobList] {
        if {[catch {set status [::GX::scientificExecutionStatus [dict get $job id]]}]} continue
        if {[dict get $status provider_id] ne {math.electromagnetic_simulation.fem2d}||![dict exists $status source_identities workspace id]||[dict get $status source_identities workspace id] ne $state(document)} continue
        set state(job) [dict get $job id];set state(busy) [expr {[dict get $status state] in {QUEUED PREPARING RUNNING FINALIZING CANCELLING}}]
        _poll $state(job) $state(token);break
    }
}
proc ::GX::ElectromagneticsStudio::_poll {job token} {
    variable state;variable window
    if {![winfo exists $window]||[catch {::GX::interactiveDocumentSessionToken} current]||$state(token) ne $token||$state(job) ne $job||$token ne $current} return
    set status [::GX::ElectromagneticSimulation::jobStatus $job];set phase [dict get $status state]
    if {$phase in {QUEUED PREPARING RUNNING FINALIZING CANCELLING}} {_setStatus "Managed FEM Job $job: $phase";set state(poll) [after 250 [list ::GX::ElectromagneticsStudio::_poll $job $token]];return}
    _finished [dict create ok [expr {$phase eq {COMPLETED}}] job_id $job status $phase error "Managed Job ended as $phase; its CORE log is retained."]
}
proc ::GX::ElectromagneticsStudio::_run {} {
    variable state;_core
    if {$state(busy)} {error {The current model already has an active managed Job.}}
    _saveModel
    set state(job) [::GX::ElectromagneticSimulation::runAsync [_collect] {} $state(document)]
    set state(busy) 1;set state(dataset) {};_writeResult "Real Gmsh/GetDP Job submitted: $state(job)"
    _poll $state(job) $state(token);_controls
}
proc ::GX::ElectromagneticsStudio::_finished {outcome} {
    variable state;variable window
    if {![winfo exists $window]||[dict get $outcome job_id] ne $state(job)} return
    set state(busy) 0
    if {[dict get $outcome ok]} {
        set receipt [::GX::ElectromagneticSimulation::resultDescribe $state(job)]
        set preview [::GX::ElectromagneticSimulation::resultPreview $state(job) 0 8]
        set state(last_result) $receipt
        _setStatus "Actual FEM completed: [dict get $receipt mesh_triangles] cells; independent weak residual [format %.3g [dict get $receipt independent_relative_weak_residual]]."
        _writeResult "ACTUAL FEM RECEIPT
$receipt

CELL-CENTROID PREVIEW, NOT NODAL DATA
[dict get $preview header]
[join [dict get $preview rows] \n]"
        foreach id [::GX::sessionInspectionDatasetIds] {set metadata [::GX::datasetMetadataRead [::GX::sessionInspectionCurrentSession] $id];if {[dict exists $metadata em.job_id]&&[dict get $metadata em.job_id] eq $state(job)&&[dict exists $metadata em.cells_dataset_id]&&[dict get $metadata em.cells_dataset_id] eq $id} {set state(dataset) $id;break}}
    } else {_setStatus [dict get $outcome error];_writeResult [::GX::scientificExecutionLog $state(job) 0 65536]}
    _controls
}
proc ::GX::ElectromagneticsStudio::_cancel {} {
    variable state
    if {$state(job) eq "" || !$state(busy)} {error "No active solver job can be cancelled."}
    set receipt [::GX::ElectromagneticSimulation::cancel $state(job)]
    _setStatus "Cancellation requested; awaiting backend termination."
}
proc ::GX::ElectromagneticsStudio::_publish {} {
    variable state
    if {$state(busy) || $state(job) eq ""} {error "Complete a real FEM solve before publishing."}
    set id [string trim $state(output_id)]
    set published [::GX::ElectromagneticSimulation::publish $state(job) $id]
    set state(dataset) [dict get $published dataset_id]
    _setStatus "Published canonical Dataset $state(dataset) (new identity, no source replacement)."
}
proc ::GX::ElectromagneticsStudio::_openDataset {} {
    variable state
    if {$state(dataset) eq ""} {error "Publish a completed field Dataset first."}
    if {![llength [info commands ::GX::datasetViewerOpen]]} {
        error "CORE Dataset Viewer API is unavailable."
    }
    ::GX::datasetViewerOpen $state(dataset)
    _setStatus "Opened published numerical Dataset in the CORE Dataset Viewer."
}
proc ::GX::ElectromagneticsStudio::_writeResult {message} {
    variable state
    if {![info exists state(result_widget)] || ![winfo exists $state(result_widget)]} {return}
    set w $state(result_widget)
    $w configure -state normal
    $w delete 1.0 end
    $w insert end $message
    $w configure -state disabled
}
proc ::GX::ElectromagneticsStudio::_teaching {} {
    variable state
    if {![info exists state(teaching_widget)] || ![winfo exists $state(teaching_widget)]} {return}
    set w $state(teaching_widget)
    $w configure -state normal
    $w delete 1.0 end
    if {$state(kind) eq "magnetostatic_2d"} {
        set txt {MAGNETOSTATIC LAB — CURRENT-CARRYING ROUND CONDUCTOR

Objective: solve the static field caused by uniform axial current density.

Model: an infinitely long, straight conductor with Jz = constant inside a circular disk. The surroundings are air and the material inside has explicit linear mu_r. The simulated domain is a finite rectangle. All lengths are in meters.

Equation: curl[(1/mu) curl(A)] = J. For planar geometry A = Az ez; B = curl(A), H = B/mu. Outer Dirichlet A_z=0 is a numerical truncation boundary.

Ideal reference (mu_r=1, infinite surrounding space):
B_theta(r >= a) = mu0 I / (2*pi*r), I = Jz*pi*a^2.
B_theta(r < a) = mu0 Jz*r/2.

Limitations: the outer rectangular boundary changes the solution, particularly near the boundary. A 2D A_z result does not determine a complete three-dimensional inductor or its inductance. Refine the mesh and compare the same physical observable across multiple real solves.}
    } else {
        set txt {ELECTROSTATIC LAB — PARALLEL ELECTRODES

Objective: solve a linear electrostatic potential field with explicit boundary potentials.

Model: homogeneous rectangular dielectric domain. Left electrode: 0 V. Right electrode: imposed voltage. Top/bottom: natural zero-normal-electric-displacement (insulating) boundaries. Length units are meters.

Equation: div(epsilon grad(V)) = 0; E = -grad(V). epsilon = epsilon0*eps_r.

Ideal reference for this geometry:
V(x) = V_applied*(x+L/2)/L, Ex = -V_applied/L, Ey = 0; L = 2*half_width_m.

Limitations: this boundary-value problem is not a finite physical plate capacitor with fringing. Capacitance of a 3D component requires port, geometry depth, and scientifically justified extraction. Repeated mesh studies must use actual separate solver runs.}
    }
    $w insert end $txt
    $w configure -state disabled
}
proc ::GX::ElectromagneticsStudio::_showHelp {} {variable window;::GX::documentationBrowserOpenModuleWindow viewer.electromagnetics $window}
proc ::GX::ElectromagneticsStudio::_settings {} {
    return [::GX::configurationOpenPage runtime]
}
proc ::GX::ElectromagneticsStudio::_controls {} {
    variable state;variable window
    if {![winfo exists $window]||![info exists state(busy)]} return
    set busy $state(busy);set completed [expr {!$busy&&$state(job) ne {}&&$state(last_result) ne {}}];set field [expr {$state(dataset) ne {}}]
    foreach w [list $window.toolbar.run $window.tabs.solve.run $window.tabs.mesh.v $window.toolbar.validate] {if {[winfo exists $w]} {$w state [expr {$busy?{disabled}:{!disabled}}]}}
    foreach w [list $window.toolbar.cancel $window.tabs.solve.cancel] {if {[winfo exists $w]} {$w state [expr {$busy?{!disabled}:{disabled}}]}}
    foreach w [list $window.tabs.results.controls.pub] {if {[winfo exists $w]} {$w state [expr {$completed?{!disabled}:{disabled}}]}}
    foreach w [list $window.toolbar.field $window.tabs.results.controls.plot $window.tabs.results.actions.field $window.tabs.results.actions.profile $window.tabs.results.actions.publish $window.tabs.results.actions.export] {if {[winfo exists $w]} {$w state [expr {$field?{!disabled}:{disabled}}]}}
    if {![info exists state(kind)]} return
    set magnetic [expr {$state(kind) eq {magnetostatic_2d}}]
    foreach page {model materials excitation mesh} {foreach w [winfo children $window.tabs.$page] {if {[winfo class $w] eq {TEntry}} {$w state [expr {$busy?{disabled}:{!disabled}}]}}}
    foreach w [list $window.tabs.materials.e0 $window.tabs.excitation.e0 $window.tabs.excitation.e1] {$w state [expr {!$busy&&$magnetic?{!disabled}:{disabled}}]}
    foreach w [list $window.tabs.materials.e1 $window.tabs.excitation.e2] {$w state [expr {!$busy&&!$magnetic?{!disabled}:{disabled}}]}
}
proc ::GX::ElectromagneticsStudio::_fieldSpec {} {
    variable state
    if {$state(dataset) eq {}} {error {Publish an actual completed cell field first.}}
    set info [::GX::ElectromagneticSimulation::fieldDescribe $state(dataset)];set roles [dict get $info roles]
    set binding [dict create schema GXTXT_CELL_FIELD_BINDING_v1 nodes_dataset_id [dict get $info nodes_dataset_id] node_id_variable_id [dict get $roles node_id_variable_id] x_variable_id [dict get $roles node_x_variable_id] y_variable_id [dict get $roles node_y_variable_id] cell_id_variable_id [dict get $roles cell_id_variable_id] node_variable_ids [dict get $roles node_variable_ids] scalar_variable_id [dict get $roles scalar_variable_id]]
    set spec [::GX::PlotDatasetAPIv4::cellFieldSpec $state(dataset) [dict get $roles cell_x_variable_id] [dict get $roles cell_y_variable_id] $binding {Actual FEM cell field — no interpolation}]
    set panels [dict get $spec panels];set panel [lindex $panels 0];dict set panel axes x label {X (m)};dict set panel axes y_left label {Y (m)};dict set spec panels [list $panel]
    dict set spec native_presentation {schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1 legend {placement none} graphics {font_size 11 axis_label_font_size 12 title_font_size 14}}
    return $spec
}
proc ::GX::ElectromagneticsStudio::_showField {} {
    variable state;variable window
    set spec [_fieldSpec];set path $window.tabs.results.field.plot
    if {[winfo exists $window.tabs.results.field.empty]} {destroy $window.tabs.results.field.empty}
    if {[winfo exists $path]} {::GX::PlotDatasetAPIv4::widgetConfigure $path $spec} else {::GX::PlotDatasetAPIv4::widgetCreate $path $spec;pack $path -fill both -expand 1;bind $path <ButtonPress-1> [list ::GX::ElectromagneticsStudio::_pick %W %x %y]}
    $window.tabs select $window.tabs.results;_setStatus {Exact triangle cells, source coordinates and constant field values. Wheel: zoom; middle drag: pan; double-click: fit.}
}
proc ::GX::ElectromagneticsStudio::_pick {path x y} {
    set hit [::GX::PlotDatasetAPIv4::widgetHit $path $x $y]
    if {[dict exists $hit object_kind]&&[dict get $hit object_kind] eq {cell}} {_setStatus "Cell [dict get $hit cell_id], source row [dict get $hit source_row_ordinal]: [dict get $hit value] [dict get $hit scalar_unit]."}
}
proc ::GX::ElectromagneticsStudio::_profileSpec {} {
    return [::GX::PlotDatasetAPIv4::cellFieldProfileSpec [_fieldSpec]]
}
proc ::GX::ElectromagneticsStudio::_showProfile {} {
    variable window
    set w ${window}.profile;set spec [_profileSpec]
    if {![winfo exists $w]} {toplevel $w;wm title $w {Actual cell-centroid sample profile};::GX::uiFieldWindowFit $w 900 600;::GX::PlotDatasetAPIv4::widgetCreate $w.plot $spec;pack $w.plot -fill both -expand 1} else {::GX::PlotDatasetAPIv4::widgetConfigure $w.plot $spec;raise $w}
}
proc ::GX::ElectromagneticsStudio::_publishCharts {} {
    variable state
    foreach suffix {field profile} spec [list [_fieldSpec] [_profileSpec]] {set ref [::GX::PlotDatasetAPIv4::upsertPlotFromSpec viewer.electromagnetics viewer.electromagnetics:$state(dataset):$suffix $spec];::GX::PlotDatasetAPIv4::render $ref;dict set state(graphs) $suffix $ref}
    ::GX::sessionPersistenceCommit;_setStatus {Published independently retained native field and sample charts to Plots.}
}
proc ::GX::ElectromagneticsStudio::_exportField {} {
    variable window
    set path [::GX::workspaceSaveFile export_dir -parent $window -title {Export native field figure} -defaultextension .png -filetypes {{{PNG} {.png}} {{SVG} {.svg}} {{PDF} {.pdf}}}]
    if {$path eq {}} return
    _showField;::GX::PlotDatasetAPIv4::widgetExport $window.tabs.results.field.plot $path
}
proc ::GX::ElectromagneticsStudio::_entryRow {parent row key name {unit ""}} {
    variable state
    ttk::label $parent.l$row -text $name
    ttk::entry $parent.e$row -textvariable ::GX::ElectromagneticsStudio::state($key) -width 24
    ttk::label $parent.u$row -text $unit
    grid $parent.l$row -row $row -column 0 -sticky w -padx 8 -pady 7
    grid $parent.e$row -row $row -column 1 -sticky ew -padx 8 -pady 7
    grid $parent.u$row -row $row -column 2 -sticky w -padx 4
}
proc ::GX::ElectromagneticsStudio::_make {} {
    variable state
    variable window
    if {[winfo exists $window]} {raise $window; focus $window; return [dict create state opened window $window]}
    _core
    package require Tk
    toplevel $window
    wm title $window "Electromagnetics Studio — GX-TXT"
    ::GX::uiFieldWindowFit $window 1080 780
    wm minsize $window 790 580
    wm protocol $window WM_DELETE_WINDOW ::GX::ElectromagneticsStudio::_close
    set state(window) $window
    set state(token) [::GX::interactiveDocumentSessionToken];set state(saved_model) {};set state(workspace_name) {}
    set state(busy) 0
    set state(document) ""
    set state(job) ""
    set state(dataset) ""
    set state(last_result) ""
    set state(output_id) em_field_result
    set state(status) "Ready; a real FEM solver is required for numerical results."
    set menu $window.menu
    menu $menu -tearoff 0
    $window configure -menu $menu
    foreach title {Model Simulation Results Configuration Help} {
        set key [string tolower $title]
        menu $menu.$key -tearoff 0
        $menu add cascade -label $title -menu $menu.$key
    }
    $menu.model add command -label "Use Magnetic Physics" -command [list ::GX::ElectromagneticsStudio::_invoke {set ::GX::ElectromagneticsStudio::state(kind) magnetostatic_2d;::GX::ElectromagneticsStudio::_kindChanged}]
    $menu.model add command -label "Use Electric Physics" -command [list ::GX::ElectromagneticsStudio::_invoke {set ::GX::ElectromagneticsStudio::state(kind) electrostatic_2d;::GX::ElectromagneticsStudio::_kindChanged}]
    $menu.model add separator
    ::GX::sessionWorkspaceViewerMenu $menu.model em_models [_callbacks] $window
    $menu.simulation add command -label "Validate Model" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_validate]
    $menu.simulation add command -label "Run FEM Solver" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_run]
    $menu.simulation add command -label "Cancel Solver" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_cancel]
    $menu.results add command -label "Publish Dataset" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_publish]
    $menu.results add command -label "Open Dataset in CORE Viewer" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_openDataset]
    $menu.configuration add command -label "Backend Settings..." -command ::GX::ElectromagneticsStudio::_settings
    $menu.help add command -label "User Manual…" -accelerator F1 -command ::GX::ElectromagneticsStudio::_showHelp

    bind $window <F1> ::GX::ElectromagneticsStudio::_showHelp
    ttk::frame $window.toolbar -padding 5;pack $window.toolbar -side top -fill x
    foreach {key label action} {open {Open…} _openModel save Save _saveModel validate Validate _validate run {Run FEM} _run cancel Cancel _cancel field {Show field} _showField help Help _showHelp} {ttk::button $window.toolbar.$key -text $label -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::$action];pack $window.toolbar.$key -side left -padx 2}
    bind $window.toolbar <Configure> [list ::GX::native2DToolbarLayout $window.toolbar %w]
    ttk::frame $window.top -padding {10 10 10 4}
    pack $window.top -fill x
    ttk::label $window.top.brand -text "Electromagnetics Studio" -font {TkDefaultFont 15 bold}
    ttk::label $window.top.sub -text "Planar linear FEM • verified solver results only"
    pack $window.top.brand $window.top.sub -side left -padx {0 18}
    ttk::label $window.status -textvariable ::GX::ElectromagneticsStudio::state(status) -relief sunken -anchor w -padding 9
    pack $window.status -side bottom -fill x
    ttk::notebook $window.tabs
    pack $window.tabs -side top -fill both -expand 1 -padx 8 -pady 8
    foreach {key title} {model Model materials Materials excitation Excitation mesh Mesh solve Solve results Results learning Learning} {
        ttk::frame $window.tabs.$key -padding 16
        $window.tabs add $window.tabs.$key -text $title
    }
    set m $window.tabs.model
    _entryRow $m 0 model_id "Stable model ID"
    ttk::label $m.kindlabel -text "Analysis"
    ttk::combobox $m.kind -state readonly -values {magnetostatic_2d electrostatic_2d} \
        -textvariable ::GX::ElectromagneticsStudio::state(kind) -width 26
    grid $m.kindlabel -row 1 -column 0 -sticky w -padx 8 -pady 6
    grid $m.kind -row 1 -column 1 -sticky w -padx 8 -pady 6
    bind $m.kind <<ComboboxSelected>> [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_kindChanged]
    _entryRow $m 2 formulation "Spatial formulation" "planar_2d only"
    $m.e2 configure -state readonly
    _entryRow $m 3 half_width_m "Half domain width" m
    _entryRow $m 4 height_m "Domain height" m
    ttk::label $m.note -text "Magnetic: disk in finite rectangular air domain. Electric: homogeneous rectangular dielectric between electrode boundaries." -wraplength 700
    grid $m.note -row 5 -column 0 -columnspan 3 -sticky w -padx 8 -pady 18
    set ma $window.tabs.materials
    _entryRow $ma 0 mu_r "Conductor relative permeability" "dimensionless; magnetic only"
    _entryRow $ma 1 eps_r "Dielectric relative permittivity" "dimensionless; electric only"
    ttk::label $ma.note -text "Material names never imply properties. Values are explicit, linear, isotropic and frequency independent. Air has mu_r = 1 in the surrounding magnetic region." -wraplength 700
    grid $ma.note -row 2 -columnspan 3 -sticky w -padx 8 -pady 18
    set ex $window.tabs.excitation
    _entryRow $ex 0 radius_m "Conductor radius" "m; magnetic only"
    _entryRow $ex 1 current_density_A_m2 "Uniform axial current density Jz" "A/m²; magnetic only"
    _entryRow $ex 2 voltage_V "Right electrode potential" "V; left electrode = 0 V"
    ttk::label $ex.note -text "Magnetic outer boundary: Az = 0. Electric: insulated upper/lower sides. No terminal-based inductance or capacitance extraction is claimed." -wraplength 700
    grid $ex.note -row 3 -columnspan 3 -sticky w -padx 8 -pady 18
    set me $window.tabs.mesh
    _entryRow $me 0 mesh_size_m "Nominal maximum mesh size" m
    ttk::label $me.t -text "The Gmsh mesher reports actual node and triangle counts only after execution. Refine by reducing the size, solving again and comparing the actual field values." -wraplength 700
    grid $me.t -row 1 -columnspan 3 -sticky w -padx 8 -pady 18
    ttk::button $me.v -text "Validate Physical Model" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_validate]
    grid $me.v -row 2 -column 0 -padx 8 -pady 10
    set so $window.tabs.solve
    ttk::label $so.notice -text "Solver backend: Gmsh 2D mesh + GetDP static linear FEM. The GUI does not substitute analytical reference calculations for the solver." -wraplength 700
    grid $so.notice -row 0 -columnspan 3 -sticky w -pady 12
    ttk::button $so.run -text "Run Actual FEM" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_run]
    ttk::button $so.cancel -text "Cancel Running Job" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_cancel]
    grid $so.run -row 1 -column 0 -padx 8 -pady 8
    grid $so.cancel -row 1 -column 1 -padx 8 -pady 8
    ttk::button $so.settings -text "Backend Settings..." -command ::GX::ElectromagneticsStudio::_settings
    grid $so.settings -row 2 -column 0 -padx 8 -pady 8
    set r $window.tabs.results
    ttk::frame $r.controls
    pack $r.controls -side top -fill x -pady {0 10}
    ttk::label $r.controls.name -text "New output Dataset ID"
    ttk::entry $r.controls.id -textvariable ::GX::ElectromagneticsStudio::state(output_id) -width 26
    ttk::button $r.controls.pub -text "Publish Verified Field" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_publish]
    ttk::button $r.controls.plot -text "Open CORE Dataset View" -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::_openDataset]
    pack $r.controls.name $r.controls.id $r.controls.pub $r.controls.plot -side left -padx 5
    ttk::frame $r.actions;pack $r.actions -fill x
    foreach {key label action} {field {Show exact cell field} _showField profile {Show sample profile} _showProfile publish {Publish charts to Plots} _publishCharts export {Export field…} _exportField} {ttk::button $r.actions.$key -text $label -command [list ::GX::ElectromagneticsStudio::_invoke ::GX::ElectromagneticsStudio::$action];pack $r.actions.$key -side left -padx 2 -pady 4}
    ttk::frame $r.field -height 280;pack $r.field -fill both -expand 1;pack propagate $r.field 0
    ttk::label $r.field.empty -text {Publish a completed field, then show its exact element topology and constant cell values.};pack $r.field.empty -padx 8 -pady 8
    ttk::scrollbar $r.s -orient vertical
    text $r.t -height 6 -wrap none -font TkFixedFont -yscrollcommand [list $r.s set] -state disabled
    $r.s configure -command [list $r.t yview]
    pack $r.s -side right -fill y
    pack $r.t -side left -fill both -expand 1
    set state(result_widget) $r.t
    set l $window.tabs.learning
    ttk::scrollbar $l.s -orient vertical
    text $l.t -wrap word -yscrollcommand [list $l.s set] -state disabled
    $l.s configure -command [list $l.t yview]
    pack $l.s -side right -fill y
    pack $l.t -side left -fill both -expand 1
    set state(teaching_widget) $l.t
    _new magnetostatic_2d
    _controls
    ::GX::sessionWorkspaceViewerTitle $window {Electromagnetics Studio} [list set ::GX::ElectromagneticsStudio::state(document)] [list set ::GX::ElectromagneticsStudio::state(workspace_name)]
    _writeResult "No numerical simulation has been executed. Select a model and run the FEM solver."
    return [dict create state opened window $window]
}
proc ::GX::ElectromagneticsStudio::viewerDispatch {action scene} {
    switch -- $action {
        open {return [open [dict get $scene open_context]]}
        rerender {return [open]}
        default {error "Unsupported Viewer Provider action '$action'"}
    }
}
::GX::viewerBackendRegister electromagnetics_studio_tk ::GX::ElectromagneticsStudio::viewerDispatch
