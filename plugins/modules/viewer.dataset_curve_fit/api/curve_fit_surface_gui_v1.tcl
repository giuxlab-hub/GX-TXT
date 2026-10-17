# Surface controls consume the public physical model and shared Workspace owners.
# SPDX-License-Identifier: GPL-3.0-or-later
set ::GX::DatasetCurveFit::surfaceCommands {}
foreach {id label key} {save {Save Workspace} Ctrl+s close Close {} preview {Preview fit} F5 accept {Accept fit} F6 cancel {Cancel operation} {} undo Undo Ctrl+z redo Redo Ctrl+Shift+z add_parameter {Add parameter} {} query {Evaluate exact XY pair} {} export {Export model…} {} recipe {Export rerun recipe…} {} publish {Publish sampled grid} {} plot {Open published grid in3D} {}} {
    dict set ::GX::DatasetCurveFit::surfaceCommands $id [dict create label $label default $key]
}
::GX::viewerCommandCatalogRegister viewer.dataset_curve_fit.surface $::GX::DatasetCurveFit::surfaceCommands modules.dataset_surface_fit.shortcuts
proc ::GX::DatasetCurveFit::surfaceViewerDispatch {action scene} {
    if {$action ni {open rerender}} {error {Unsupported surface Viewer action}}
    return [openSurface [::GX::datasetPublicationV2DictDefault $scene open_context {}]]
}
::GX::viewerBackendRegister dataset_surface_fit_tk ::GX::DatasetCurveFit::surfaceViewerDispatch
proc ::GX::DatasetCurveFit::_surfaceUiEnabled {w id} {
    variable state
    if {![info exists state($w,busy)]||$state($w,sessionToken) ne [::GX::interactiveDocumentSessionToken]} {return 0}
    if {$id eq "cancel"} {return $state($w,busy)}
    if {$state($w,busy)} {return 0}
    if {$id eq "accept"} {
        if {[dict get $state($w,payload) preview] eq {}||![info exists state($w,previewEditor)]||[catch {_surfaceUiEditor $w} editor]} {return 0}
        return [expr {$editor eq $state($w,previewEditor)}]
    }
    if {$id in {query export recipe publish plot}} {return [expr {$state($w,selected) ne {}}]}
    set history [dict get $state($w,payload) scientific_history]
    if {$id eq "undo"} {return [expr {[dict get $history cursor]>0}]}
    if {$id eq "redo"} {return [expr {[dict get $history cursor]<[llength [dict get $history steps]]}]}
    return 1
}
proc ::GX::DatasetCurveFit::_surfaceUiReference {w} {
    variable state
    return [surfaceResultReference $state($w,workspace) $state($w,selected)]
}
proc ::GX::DatasetCurveFit::_surfaceUiEditor {w} {return [list [_surfaceUiSource $w] [_surfaceUiRecipe $w] [_surfaceUiOptions $w]]}
proc ::GX::DatasetCurveFit::_surfaceAddParameter {w parameter} {
    variable state
    _formulaAdd $w $parameter
    set row [lindex $state($w,rows) end]
    foreach field {id unit initial lower upper} {$state($w,body).parameters.$field$row configure -width 9}
}
proc ::GX::DatasetCurveFit::_surfaceUiLayout {w width} {
    variable state
    set body $state($w,body)
    foreach widget [list $body.units $body.help $body.grid.note] {$widget configure -wraplength [expr {max(220,$width-25)}]}
}
proc ::GX::DatasetCurveFit::_surfaceUiSource {w} {
    variable state
    set source [dict create dataset_id $state($w,dataset) layout $state($w,layout)]
    foreach role {x y z sigma} {dict set source ${role}_variable_id $state($w,$role)}
    return $source
}
proc ::GX::DatasetCurveFit::_surfaceUiRecipe {w} {
    variable state
    set units {};foreach role {x y z} {
        if {![dict exists $state($w,variables) $state($w,$role)]} {error {Choose canonical X, Y and Z Variables}}
        lappend units [dict get $state($w,variables) $state($w,$role) unit]
    }
    set parameters {}
    foreach row $state($w,rows) {
        set parameter [dict create id [string trim $state($w,$row,id)] unit [string trim $state($w,$row,unit)] initial [_finite $state($w,$row,initial) {Parameter initial value}] fixed $state($w,$row,fixed)]
        foreach field {lower upper} {set value [string trim $state($w,$row,$field)];if {$value ne {}} {dict set parameter $field $value}}
        lappend parameters $parameter
    }
    return [dict create expression [string trim $state($w,expression)] predictor_ids {x y} predictor_units [lrange $units 0 1] response_unit [lindex $units 2] parameters $parameters]
}
proc ::GX::DatasetCurveFit::_surfaceUiOptions {w} {
    variable state
    return [dict create nonfinite $state($w,nonfinite) noise_model $state($w,noise) max_iterations $state($w,max_iterations) max_seconds $state($w,max_seconds)]
}
proc ::GX::DatasetCurveFit::_surfaceUiDataset {w} {
    variable state
    set state($w,variables) {};set vectors {};set matrices {};set numeric {}
    if {$state($w,dataset) ne {}} {
        set handle [::GX::datasetAccessOpen $::GX::currentSession $state($w,dataset)]
        try {
            foreach variable [dict get [::GX::datasetAccessMetadata $handle] variables] {
                if {![dict get $variable enabled]||[dict get $variable value_kind] ne "number"||[dict get $variable rank] ni {1 2}} continue
                set id [dict get $variable variable_id];dict set state($w,variables) $id $variable;lappend numeric $id
                if {[dict get $variable rank]==1} {lappend vectors $id} else {lappend matrices $id}
            }
        } finally {::GX::datasetAccessClose $handle}
    }
    set body $state($w,body)
    foreach role {x y z sigma} values [list $vectors $vectors $numeric [linsert $numeric 0 {}]] {
        $body.source.$role configure -values $values
        if {$state($w,$role) ni $values} {set state($w,$role) {}}
    }
    _surfaceUiUnits $w
}
proc ::GX::DatasetCurveFit::_surfaceUiUnits {w} {
    variable state
    set labels {}
    foreach role {x y z sigma} {
        set id $state($w,$role)
        if {[dict exists $state($w,variables) $id]} {set v [dict get $state($w,variables) $id];lappend labels "[string toupper $role]: $id ([dict get $v unit]), shape [dict get $v shape]"}
    }
    set state($w,units) [join $labels {   }]
}
proc ::GX::DatasetCurveFit::_surfaceUiApply {w payload} {
    variable state
    set state($w,payload) $payload
    set source [dict get $payload source];set recipe [dict get $payload recipe];set settings [dict get $payload settings]
    if {$source ne {}} {
        set state($w,dataset) [dict get $source dataset_id];set state($w,layout) [dict get $source layout]
        foreach role {x y z sigma} {set state($w,$role) [::GX::datasetPublicationV2DictDefault $source ${role}_variable_id {}]}
    }
    if {$recipe ne {}} {
        set state($w,expression) [dict get $recipe expression]
        foreach row $state($w,rows) {_formulaRemove $w $row}
        foreach parameter [dict get $recipe parameters] {_surfaceAddParameter $w $parameter}
    }
    foreach field {nonfinite max_iterations max_seconds} {if {[dict exists $settings $field]} {set state($w,$field) [dict get $settings $field]}}
    if {[dict exists $settings noise_model]} {set state($w,noise) [dict get $settings noise_model]}
    foreach field {name selected qx qy dataset_out nx ny xmin xmax ymin ymax style} {
        if {[dict exists $payload controls $field]} {set state($w,$field) [dict get $payload controls $field]}
    }
    _surfaceUiDataset $w
    set state($w,showPreview) [expr {[dict get $payload preview] ne {}}]
    if {$state($w,showPreview)&&![catch {_surfaceUiEditor $w} editor]} {set state($w,previewEditor) $editor}
    _surfaceUiRefresh $w
}
proc ::GX::DatasetCurveFit::_surfaceUiRefresh {w} {
    variable state
    if {![winfo exists $w]} return
    set state($w,payload) [dict get [_surfaceRead $state($w,workspace)] payload]
    set ids {};set names {}
    foreach record [dict get $state($w,payload) records] {lappend ids [dict get $record id];lappend names [dict get $record name]}
    set state($w,acceptedIds) $ids;$w.results.accepted configure -values $names
    if {$state($w,selected) ni $ids} {set state($w,selected) [lindex $ids end]}
    set index [lsearch -exact $ids $state($w,selected)];set state($w,acceptedName) [lindex $names $index]
    set result {};if {$state($w,showPreview)} {set result [dict get $state($w,payload) preview]}
    if {$result eq {}&&$index>=0} {set result [lindex [dict get $state($w,payload) records] $index]}
    set report {Choose an explicit source layout and physical formula. Preview does not publish a Dataset.}
    $w.results.rows delete [$w.results.rows children {}]
    if {$result ne {}} {
        _surfaceValidateResult $state($w,workspace) $result
        set meaning [dict get $result statistics]
        set report "[::GX::StatisticsV1::report $meaning {n sse r_squared dof rmse}]\n[::GX::StatisticsV1::parameterReport $meaning]"
        set page [_surfaceResidualPage $result 0 64];binary scan [dict get $page residuals bytes] q* values;binary scan [dict get $page source_rows bytes] wu* indices
        set i 0;foreach id $indices {set row [lmap value [lrange $values [expr {$i*5}] [expr {$i*5+4}]] {format %.9g $value}];$w.results.rows insert {} end -values [linsert $row 0 $id];incr i}
        if {$state($w,xmin) eq {}} {lassign [lindex [dict get $result domain] 0] state($w,xmin) state($w,xmax);lassign [lindex [dict get $result domain] 1] state($w,ymin) state($w,ymax)}
    }
    $w.results.report configure -state normal;$w.results.report delete 1.0 end;$w.results.report insert end $report;$w.results.report configure -state disabled
    set history [dict get $state($w,payload) scientific_history]
    set state($w,history) "History [dict get $history cursor] / [llength [dict get $history steps]]"
    dict for {id descriptor} $::GX::DatasetCurveFit::surfaceCommands {
        if {[winfo exists $w.actions.$id]} {$w.actions.$id configure -state [expr {[_surfaceUiEnabled $w $id]?"normal":"disabled"}]}
    }
    ::GX::viewerCommandMenusRefresh $w
}
proc ::GX::DatasetCurveFit::_surfaceUiSave {w} {
    variable state
    set original [_surfaceRead $state($w,workspace)];set payload [dict get $original payload]
    if {$state($w,x) ne {}&&$state($w,y) ne {}&&$state($w,z) ne {}} {
        dict set payload source [_surfaceUiSource $w];dict set payload recipe [_surfaceUiRecipe $w];dict set payload settings [_surfaceUiOptions $w]
    }
    foreach field {name selected qx qy dataset_out nx ny xmin xmax ymin ymax style} {dict set payload controls $field $state($w,$field)}
    if {$payload ne [dict get $original payload]} {_surfaceCommit $original $payload {Save physical surface controls}}
    set state($w,status) {Workspace saved.};_surfaceUiRefresh $w
}
proc ::GX::DatasetCurveFit::_surfaceUiSelected {w} {
    variable state
    set state($w,selected) [lindex $state($w,acceptedIds) [$w.results.accepted current]]
    set state($w,showPreview) 0
    _surfaceUiRefresh $w
}
proc ::GX::DatasetCurveFit::_surfaceUiAxis {w axis} {
    variable state
    set count $state($w,n$axis)
    if {![string is entier -strict $count]||$count<2||$count>256} {error {Grid axes require2..256 explicit samples}}
    set lo [_surfaceCoordinate $state($w,${axis}min) {Grid lower bound}];set hi [_surfaceCoordinate $state($w,${axis}max) {Grid upper bound}]
    if {$hi<=$lo} {error {Grid upper bound must exceed lower bound}}
    set values {};for {set i 0} {$i<$count} {incr i} {lappend values [expr {$lo+($hi-$lo)*$i/($count-1.0)}]}
    return $values
}
proc ::GX::DatasetCurveFit::_surfaceUiAction {w id} {
    variable state
    switch $id {
        cancel {if {$state($w,numericRun) ne {}} {::GX::parallelExecutionCancel $state($w,numericRun)};set state($w,sourceCancelled) 1;return}
        save {_surfaceUiSave $w}
        close {_surfaceUiSave $w;destroy $w;return}
        add_parameter {if {[llength $state($w,rows)]>=32} {error {Surface formulas support at most32 parameters}};_surfaceAddParameter $w [dict create id {} unit {} initial 1]}
        preview {
            set state($w,busy) 1;set state($w,status) {Fitting the declared physical surface…};_surfaceUiRefresh $w;update idletasks
            try {
                surfacePreview $state($w,workspace) [_surfaceUiSource $w] [_surfaceUiRecipe $w] [_surfaceUiOptions $w] $w
                set state($w,previewEditor) [_surfaceUiEditor $w];set state($w,showPreview) 1
            } finally {set state($w,busy) 0;_surfaceUiRefresh $w}
            set state($w,status) {Preview captured. Review the common report before accepting.}
        }
        accept {set reference [surfaceAccept $state($w,workspace) $state($w,name)];set state($w,selected) [dict get $reference fit_id];set state($w,showPreview) 0;_surfaceUiRefresh $w;set state($w,status) {Accepted physical surface saved.}}
        undo - redo {
            set original [_surfaceRead $state($w,workspace)];set history [dict get $original payload scientific_history]
            set delta [expr {$id eq "undo"?-1:1}]
            set history [::GX::scientificHistoryNavigate viewer.dataset_curve_fit.surface $history [expr {[dict get $history cursor]+$delta}]]
            set payload [::GX::scientificHistoryState $history];dict set payload scientific_history $history
            ::GX::sessionWorkspaceUpdate $state($w,workspace) $payload;_surfaceUiApply $w $payload
        }
        query {
            set q [surfaceQuery [_surfaceUiReference $w] [list [list $state($w,qx) $state($w,qy)]]]
            set state($w,status) "Z = [format %.12g [lindex [dict get $q predicted] 0]] [lindex [dict get $q coordinate_units] 2] at exact X/Y; no refit."
        }
        export {
            set directory [tk_chooseDirectory -parent $w -title {Export retained surface model}];if {$directory eq {}} return
            set artifact [surfaceExport [_surfaceUiReference $w] fit_surface]
            foreach field {python octave latex metadata_json} extension {py m tex json} {set path [file join $directory fit_surface.$extension];if {[file exists $path]} {error "Export exists: $path"}}
            foreach field {python octave latex metadata_json} extension {py m tex json} {set f [::open [file join $directory fit_surface.$extension] {WRONLY CREAT EXCL}];try {fconfigure $f -encoding utf-8;puts -nonewline $f [dict get $artifact $field]} finally {::close $f}}
            set state($w,status) {Python, Octave, LaTeX and physical model metadata exported.}
        }
        recipe {
            set path [tk_getSaveFile -parent $w -defaultextension .gxtxtrecipe -title {Export surface rerun recipe}];if {$path eq {}} return
            if {[file exists $path]} {error {Recipe destination already exists}}
            set f [::open $path {WRONLY CREAT EXCL}];try {puts $f [surfaceRecipeCapture [_surfaceUiReference $w]]} finally {::close $f}
        }
        publish {
            set reference [_surfaceUiReference $w];set published [surfacePublish $reference $state($w,dataset_out) [_surfaceUiAxis $w x] [_surfaceUiAxis $w y]]
            set state($w,dataset_out) [dict get $published dataset_id];_surfaceUiSave $w
            set state($w,status) {Published an explicit sampled model grid. Original missing cells remain unchanged.}
        }
        plot {
            set plot [surfacePlot [_surfaceUiReference $w] $state($w,dataset_out) $state($w,style)]
            set state($w,plot) $plot;set state($w,viewer3d) [::GX::PlotDatasetAPIv3::openInteractive $plot]
            set state($w,status) {Opened the published sampled model through Plot Dataset / Native3D.}
        }
        default {error {Unknown surface command}}
    }
}
proc ::GX::DatasetCurveFit::_surfaceUiInvoke {w id} {
    variable state
    if {[catch {_surfaceUiAction $w $id} message options]} {set state($w,status) $message;set state($w,lastError) $message;return 0}
    if {[winfo exists $w]} {set state($w,lastError) {}};return 1
}
proc ::GX::DatasetCurveFit::openSurface {{context {}}} {
    variable state
    package require Tk
    set w .dataset_surface_fit;set requested [::GX::datasetPublicationV2DictDefault $context workspace_id {}]
    if {[winfo exists $w]} {
        if {$requested eq {}||$requested eq $state($w,workspace)} {raise $w;return $w}
        if {$state($w,busy)} {error {Finish or cancel the active surface operation}}
        _surfaceUiSave $w;destroy $w
    }
    if {$requested in {{} new}} {
        set names [lmap item [::GX::sessionWorkspaceList] {dict get $item name}];set name {Physical surface fit};set suffix 1
        while {$name in $names} {set name "Physical surface fit [incr suffix]"}
        set requested [dict get [surfaceCreate $name] workspace_id]
    }
    set workspace [_surfaceRead $requested]
    foreach {field value} {dataset {} x {} y {} z {} sigma {} layout points nonfinite error noise unspecified max_iterations 400 max_seconds 30 expression {offset+x_slope*x+y_slope*y} rows {} serial 0 selected {} name {Accepted surface} qx 0 qy 0 dataset_out surface_model nx 17 ny 17 xmin {} xmax {} ymin {} ymax {} style surface busy 0 numericRun {} sourceCancelled 0 status {Choose canonical Variables and an explicit input layout.} lastError {}} {set state($w,$field) $value}
    set state($w,workspace) $requested;set state($w,sessionToken) [::GX::interactiveDocumentSessionToken]
    toplevel $w;wm title $w "Physical Surface Fit — [dict get $workspace name]";::GX::uiFieldWindowFit $w 1220 900
    wm protocol $w WM_DELETE_WINDOW [list ::GX::viewerCommandInvoke $w close]
    bind $w <Escape> [list ::GX::viewerCommandInvoke $w cancel]
    ttk::frame $w.footer -padding 6;pack $w.footer -side bottom -fill x
    ttk::label $w.footer.status -textvariable ::GX::DatasetCurveFit::state($w,status) -wraplength 1060 -justify left;pack $w.footer.status -fill x
    ttk::label $w.footer.history -textvariable ::GX::DatasetCurveFit::state($w,history);pack $w.footer.history -anchor e
    ttk::frame $w.actions -padding 5;pack $w.actions -side top -fill x
    foreach id {preview accept save cancel undo redo publish plot} {ttk::button $w.actions.$id -text [dict get $::GX::DatasetCurveFit::surfaceCommands $id label] -command [list ::GX::viewerCommandInvoke $w $id];pack $w.actions.$id -side left -padx 3}
    ttk::panedwindow $w.panes -orient horizontal;pack $w.panes -fill both -expand 1
    ttk::frame $w.setup;ttk::frame $w.results -padding 8;$w.panes add $w.setup -weight 1;$w.panes add $w.results -weight 1
    set body [::GX::scrollableDialogBody $w.setup];set state($w,body) $body
    ttk::labelframe $body.source -text {Canonical source and exact coordinate binding} -padding 5;pack $body.source -fill x
    set row 0
    foreach {field label} {dataset Dataset x {X coordinate} y {Y coordinate} z {Z response} sigma {Response sigma (optional)} layout {Input layout} nonfinite {Nonfinite observations} noise {Response-noise assumption}} {
        ttk::label $body.source.l$field -text $label;ttk::combobox $body.source.$field -state readonly -textvariable ::GX::DatasetCurveFit::state($w,$field) -width 32
        grid $body.source.l$field -row $row -column 0 -sticky w -padx 3 -pady 3;grid $body.source.$field -row $row -column 1 -sticky ew -padx 3;incr row
    }
    grid columnconfigure $body.source 1 -weight 1
    $body.source.dataset configure -values [::GX::datasetRegistryIds]
    $body.source.layout configure -values {points grid_yx};$body.source.nonfinite configure -values {error omit}
    $body.source.noise configure -values {unspecified independent_gaussian_known_sigma independent_gaussian_estimated_variance}
    bind $body.source.dataset <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_surfaceUiDataset $w]
    foreach role {x y z sigma} {bind $body.source.$role <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_surfaceUiUnits $w]}
    ttk::label $body.units -textvariable ::GX::DatasetCurveFit::state($w,units) -wraplength 540 -justify left;pack $body.units -fill x -pady 6
    ttk::label $body.help -text {z=f(x,y): physical X/Y are exact predictors. grid_yx requires a canonical Z matrix with Y/X dimensions; points uses matched rows. Missing cells are never filled. Parameter units may be inferred only when unambiguous.} -wraplength 540 -justify left;pack $body.help -fill x -pady 4
    ttk::entry $body.expression -textvariable ::GX::DatasetCurveFit::state($w,expression);pack $body.expression -fill x -pady 5
    ttk::frame $body.parameters;pack $body.parameters -fill x
    set col 0;foreach label {Parameter Unit Initial Lower Upper Fixed {}} {ttk::label $body.parameters.h$col -text $label;grid $body.parameters.h$col -row 0 -column $col -sticky w;incr col}
    foreach id {offset x_slope y_slope} {_surfaceAddParameter $w [dict create id $id unit {} initial 1]}
    ttk::button $body.add -text {Add parameter} -command [list ::GX::viewerCommandInvoke $w add_parameter];pack $body.add -anchor w -pady 4
    ttk::frame $body.limits;pack $body.limits -fill x
    set row 0;foreach {field label} {max_iterations Iterations max_seconds Seconds name {Accepted name}} {ttk::label $body.limits.l$field -text $label;ttk::entry $body.limits.$field -width 15 -textvariable ::GX::DatasetCurveFit::state($w,$field);grid $body.limits.l$field -row $row -column 0 -sticky w -padx 2;grid $body.limits.$field -row $row -column 1 -sticky ew -padx 2;incr row};grid columnconfigure $body.limits 1 -weight 1
    ttk::labelframe $body.grid -text {Sample the retained formula on an explicit grid} -padding 5;pack $body.grid -fill x -pady 8
    set row 0;foreach {field label} {xmin {X minimum} xmax {X maximum} nx {X samples} ymin {Y minimum} ymax {Y maximum} ny {Y samples} dataset_out {Published Dataset ID} style {3D style}} {
        ttk::label $body.grid.l$field -text $label
        if {$field eq "style"} {ttk::combobox $body.grid.$field -state readonly -values {surface mesh} -textvariable ::GX::DatasetCurveFit::state($w,$field)} else {ttk::entry $body.grid.$field -textvariable ::GX::DatasetCurveFit::state($w,$field)}
        grid $body.grid.l$field -row $row -column 0 -sticky w;grid $body.grid.$field -row $row -column 1 -sticky ew;incr row
    }
    grid columnconfigure $body.grid 1 -weight 1
    ttk::label $body.grid.note -text {Bounds describe axis extrema, not observation coverage. Publication samples the model and preserves the original source.} -wraplength 520 -justify left;grid $body.grid.note -row $row -columnspan 2 -sticky ew
    ttk::label $w.results.title -text {Accepted surface};ttk::combobox $w.results.accepted -state readonly -textvariable ::GX::DatasetCurveFit::state($w,acceptedName);pack $w.results.title $w.results.accepted -fill x
    bind $w.results.accepted <<ComboboxSelected>> [list ::GX::DatasetCurveFit::_surfaceUiSelected $w]
    ttk::frame $w.results.reporting;pack $w.results.reporting -fill both -expand 1 -pady 6
    text $w.results.report -wrap word -height 19 -width 60 -state disabled -yscrollcommand [list $w.results.reporting.scroll set]
    ttk::scrollbar $w.results.reporting.scroll -orient vertical -command [list $w.results.report yview]
    pack $w.results.report -in $w.results.reporting -side left -fill both -expand 1;pack $w.results.reporting.scroll -side right -fill y
    ttk::label $w.results.residualLabel -text {Retained observations (first64): original index, X, Y, observed Z, predicted Z, residual Z};pack $w.results.residualLabel -fill x
    ttk::treeview $w.results.rows -columns {index x y z predicted residual} -show headings -height 7
    foreach id {index x y z predicted residual} {$w.results.rows heading $id -text $id;$w.results.rows column $id -width 85 -stretch 1};pack $w.results.rows -fill both -expand 1
    ttk::frame $w.results.query;pack $w.results.query -fill x -pady 5
    foreach {field label} {qx X qy Y} {ttk::label $w.results.query.l$field -text $label;ttk::entry $w.results.query.$field -width 12 -textvariable ::GX::DatasetCurveFit::state($w,$field);pack $w.results.query.l$field $w.results.query.$field -side left}
    ttk::button $w.results.query.run -text Evaluate -command [list ::GX::viewerCommandInvoke $w query];pack $w.results.query.run -side left -padx 5
    set handlers {};dict for {id descriptor} $::GX::DatasetCurveFit::surfaceCommands {dict set handlers $id [dict create command [list ::GX::DatasetCurveFit::_surfaceUiInvoke $w $id] enabled [list ::GX::DatasetCurveFit::_surfaceUiEnabled $w $id]]}
    ::GX::viewerCommandsAttach $w viewer.dataset_curve_fit.surface $handlers
    menu $w.menu -tearoff 0;$w configure -menu $w.menu
    foreach {group label ids} {file File {save export recipe close} fit Fit {preview accept cancel add_parameter query} history History {undo redo} output Publish {publish plot}} {menu $w.menu.$group -tearoff 0;$w.menu add cascade -label $label -menu $w.menu.$group;foreach id $ids {::GX::viewerCommandMenuAdd $w $w.menu.$group $id}}
    if {[dict exists $context dataset_id]} {set state($w,dataset) [dict get $context dataset_id]}
    _surfaceUiApply $w [dict get $workspace payload]
    bind $w.setup.viewport.canvas <Configure> +[list ::GX::DatasetCurveFit::_surfaceUiLayout $w %w]
    update idletasks;$w.panes sashpos 0 [expr {min(640,int([winfo width $w]*0.53))}]
    return $w
}
