# Complete canonical scientific capture. Files are data, never sourced Tcl.
proc ::GX::PlotDatasetAPIv4::_writeData {path value} {file mkdir [file dirname $path];set f [open "$path.tmp.[pid]" w];try {fconfigure $f -encoding utf-8 -translation lf;puts $f [list $value]} finally {close $f};file rename -force -- "$path.tmp.[pid]" $path}
proc ::GX::PlotDatasetAPIv4::_readData {path} {if {![file isfile $path]||[file size $path]>16777216} {error {Native snapshot manifest is missing or exceeds its bounded metadata size}};set f [open $path];try {fconfigure $f -encoding utf-8;set raw [read $f]} finally {close $f};if {[llength $raw]!=1||[catch {dict size [lindex $raw 0]}]} {error {Invalid native snapshot data}};return [lindex $raw 0]}
proc ::GX::PlotDatasetAPIv4::snapshotValidate {directory {graph {}}} {
    set root [file normalize $directory];set manifest [_readData [file join $root native_v4_snapshot.tcldict]]
    if {[dict get $manifest schema] ne {GXTXT_NATIVE_PLOT_SNAPSHOT_v1}||[dict get $manifest renderer_owner] ne {PLOT_DATASET_API_v4}} {error {Unsupported native scientific snapshot}}
    if {$graph ne {}&&[dict get $manifest graph_id] ne $graph} {error {Snapshot graph identity mismatch}}
    if {![file isdirectory [file join $root resources]]||[file type [file join $root resources]] ne {directory}} {error {Snapshot resource directory must be a real contained directory}}
    dict for {id resource} [dict get $manifest datasets] {
        ::GX::datasetPublicationV2ValidateId dataset $id
        set relative [dict get $resource archive]
        if {![regexp {^resources/[A-Za-z_][A-Za-z0-9_.-]*\.zip$} $relative]} {error {Unsafe snapshot resource path}}
        set path [file join $root $relative]
        if {![file isfile $path]||[file type $path] ne {file}||[::GX::sha256File $path] ne [dict get $resource sha256]} {error "Snapshot Dataset '$id' failed canonical archive integrity verification"}
        set package [::GX::portableResourceValidate $path]
        if {[dict get $package resource_type] ne {dataset}||[dict get $package dataset_id] ne $id} {error {Snapshot Dataset archive identity mismatch}}
    }
    set datasets {};set qualified {}
    set spec [dict get $manifest spec]
    if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {set all [list $spec]} else {set all {};foreach p [dict get $spec panels] {lappend all {*}[dict get $p series]}}
    foreach series $all {set ds [dict get $series dataset_id];lappend datasets $ds;foreach id [_snapshotVariableIds [expr {[dict get $spec graph_id] eq {plot.dataset.xyz}?$spec:[dict create graph_id plot.dataset.xy panels [list [dict create series [list $series]]]]}]] {dict set qualified "$ds:$id" [dict create dataset_id $ds variable_id $id]}}
    if {[lsort -unique $datasets] ne [lsort [dict keys [dict get $manifest datasets]]]} {error {Snapshot scientific dependency set does not match its canonical PlotSpec}}
    dict set manifest source_dataset_ids [lsort -unique $datasets];dict set manifest source_variable_ids [lsort [dict keys $qualified]];dict set manifest source_variables [dict values $qualified]
    return $manifest
}
proc ::GX::PlotDatasetAPIv4::captureForArtifact {artifact destination} {
    set ref [plotRefForArtifact $artifact];if {$ref eq {}||[_get $ref module_id {}] ne {plot.dataset}} {error {Artifact has no genuine canonical Plot Dataset reference}}
    set spec [loadSpec $ref];set datasets {}
    if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {lappend datasets [dict get $spec dataset_id]} else {foreach panel [dict get $spec panels] {foreach series [dict get $panel series] {lappend datasets [dict get $series dataset_id]}}}
    file mkdir [file join $destination resources];set resources {}
    foreach id [lsort -unique $datasets] {
        set relative resources/$id.zip;set path [file join $destination $relative]
        if {[file exists $path]} {error {Snapshot resource destination already exists}}
        ::GX::portableResourceExportDataset $id $path
        dict set resources $id [dict create archive $relative sha256 [::GX::sha256File $path] source_identity [::GX::curveSourceDatasetIdentity $::GX::currentSession $id]]
    }
    set manifest [dict create schema GXTXT_NATIVE_PLOT_SNAPSHOT_v1 renderer_owner PLOT_DATASET_API_v4 graph_id [dict get $ref graph_id] source_variant [_get $ref variant_id {}] source_renderer_owner [_get [::GX::graphMetadataRead [_graphRef $ref]] renderer_owner legacy] spec $spec datasets $resources]
    _writeData [file join $destination native_v4_snapshot.tcldict] [dict remove $manifest source_dataset_ids source_variable_ids source_variables]
    snapshotValidate $destination [dict get $ref graph_id]
    renderSnapshot $destination [dict get $ref graph_id]
    return [dict create graph_id [dict get $ref graph_id] source_variant [_get $ref variant_id {}] snapshot native_v4_snapshot.tcldict renderer_owner PLOT_DATASET_API_v4 source_dataset_ids [lsort -unique $datasets] source_variable_ids [dict get [snapshotValidate $destination] source_variable_ids]]
}
proc ::GX::PlotDatasetAPIv4::renderSnapshot {directory graph} {
    variable apiDir
    snapshotValidate $directory $graph
    set tcl [auto_execok tclsh];if {$tcl eq {}} {error {Native scientific snapshot rendering requires Tcl}}
    set script [file join [file dirname $apiDir] runtime native_v4_snapshot.tcl]
    exec -- $tcl $script $::GX::scriptDir [file normalize $directory] $graph 2>@1
    set artifact [file join $directory graph.png]
    if {![file isfile $artifact]||[file size $artifact]<100} {error {Native scientific snapshot produced no graph}}
    return $artifact
}
proc ::GX::PlotDatasetAPIv4::snapshotPresentationFields {directory graph} {
    set m [snapshotValidate $directory $graph];set spec [dict get $m spec]
    set np [_get $spec native_presentation {}];set graphics [_get $np graphics {}];set layout [_get $np layout {}];set legend [_get $np legend {}]
    set result [dict create title [_get $spec title auto] spec $spec renderer_owner PLOT_DATASET_API_v4]
    if {$graph eq {plot.dataset.xyz}} {set axes [_get $spec axes {}]} else {set axes [_get [lindex [dict get $spec panels] 0] axes {}]}
    foreach {key axis field default} {x_label x label {} y_label y_left label {} y2_label y_right label {} x_min x min auto x_max x max auto y_min y_left min auto y_max y_left max auto} {dict set result $key [_get [_get $axes $axis {}] $field $default]}
    foreach key {line_width marker_size} {dict set result $key [_get [_get [_get $spec defaults {}] style {}] $key [_get $graphics $key [expr {$key eq {line_width}?1.5:4}]]]}
    dict set result legend_placement [_get $legend placement inside]
    foreach key {xgrid ygrid} {dict set result $key [_get [_get $np axes {}] $key on]}
    foreach key {layout_auto layout_margin_left layout_margin_right layout_margin_top layout_margin_bottom layout_gap layout_ylabel_dist} {dict set result $key [_get $layout $key [expr {$key eq {layout_auto}?1:6}]]}
    foreach key {width_px height_px} {dict set result $key [_get $graphics $key [expr {$key eq {width_px}?1000:720}]]}
    return $result
}
proc ::GX::PlotDatasetAPIv4::snapshotPresentationSet {directory graph fields} {
    set m [snapshotValidate $directory $graph];set prior $m;set spec [dict get $m spec]
    set allowed {title spec x_label y_label y2_label line_width marker_size legend_placement x_min x_max y_min y_max xgrid ygrid layout_auto layout_margin_left layout_margin_right layout_margin_top layout_margin_bottom layout_gap layout_ylabel_dist width_px height_px}
    foreach key [dict keys $fields] {if {$key ni $allowed} {error "Unknown native snapshot presentation field '$key'"};set value [dict get $fields $key];if {$key ni {spec}&&[regexp {[\r\n]} $value]} {error {Presentation fields must be single-line values}}}
    if {[dict exists $fields spec]} {set spec [dict get $fields spec];if {[dict get $spec graph_id] ne $graph} {error {Snapshot graph identity cannot change}}}
    dict for {key value} [dict remove $fields spec] {
        if {$key eq {title}} {dict set spec title $value;continue}
        if {$key in {line_width marker_size}} {if {![string is double -strict $value]||$value<=0||![expr {abs($value)<Inf}]} {error {Style sizes must be positive finite numbers}};dict set spec defaults style $key $value;dict set spec native_presentation graphics $key $value;continue}
        if {$key eq {legend_placement}} {if {$value ni {none inside below above right left manual}} {error {Invalid legend placement}};dict set spec native_presentation legend placement $value;continue}
        if {$key in {xgrid ygrid}} {if {$value ni {on off major minor both 0 1}} {error {Invalid grid visibility}};dict set spec native_presentation axes $key $value;continue}
        if {$key in {width_px height_px}} {if {![string is integer -strict $value]||$value<240||$value>16384} {error {Export dimension outside 240–16384 pixels}};dict set spec native_presentation graphics $key $value;continue}
        if {[string match layout_* $key]} {if {![string is double -strict $value]||![expr {abs($value)<Inf}]} {error {Layout must be finite}};dict set spec native_presentation layout $key $value;continue}
        lassign [split $key _] axis field
        if {$axis eq {y}} {set axis y_left} elseif {$axis eq {y2}} {set axis y_right}
        if {$field in {min max}&&$value ni {auto {}}&&(![string is double -strict $value]||![expr {abs($value)<Inf}])} {error {Axis limits must be finite or auto}}
        if {$graph eq {plot.dataset.xyz}} {if {$axis eq {y_left}} {set axis y};dict set spec axes $axis $field $value} else {set panels {};foreach panel [dict get $spec panels] {dict set panel axes $axis $field $value;lappend panels $panel};dict set spec panels $panels}
    }
    dict set m spec $spec;set m [dict remove $m source_dataset_ids source_variable_ids source_variables]
    set path [file join $directory native_v4_snapshot.tcldict];_writeData $path $m
    if {[catch {renderSnapshot $directory $graph} message options]} {_writeData $path [dict remove $prior source_dataset_ids source_variable_ids source_variables];return -options $options $message}
    return [snapshotPresentationFields $directory $graph]
}
proc ::GX::PlotDatasetAPIv4::writePointIndex {artifact destination} {
    set ref [plotRefForArtifact $artifact];if {$ref eq {}} {error {Native graph identity is unavailable}}
    if {[file exists $destination]} {error {Point index destination already exists}}
    set model [modelFromSpec [loadSpec $ref]];set f [open $destination w]
    try {fconfigure $f -encoding utf-8 -translation lf;puts $f "series_id\tdataset_id\tsource_row\tx\ty\taxis\tpanel_id"
        foreach panel [dict get $model panels] {foreach series [dict get $panel series] {if {[_get $series point_identity_kind {}] eq {derived_statistic}} continue;foreach row [dict get $series source_rows] point [_get $series source_points [dict get $series points]] {puts $f [join [concat [list [_get $series source_series_id [dict get $series id]] [dict get $series dataset_id] $row] $point [list [dict get $series axis] [dict get $panel id]]] \t]}}}
    } finally {close $f};return $destination
}
proc ::GX::PlotDatasetAPIv4::renderTransientIndependentCurves2D {series label destination} {
    if {[llength $series]<1||[llength $series]>64||[regexp {[\r\n\t]} $label]} {error {Invalid transient independent curve request}}
    set output {};set index 0;set total 0
    foreach s $series {
        set xs [dict get $s x_values];set ys [dict get $s y_values];set n [llength $xs];incr total $n
        if {$n<1||$n!=[llength $ys]||$total>200000} {error {Transient curves require matching vectors, 1–200000 total points}}
        foreach text [list [dict get $s label] [_get $s x_unit {}] [_get $s y_unit {}]] {if {[regexp {[\r\n\t]} $text]} {error {Series labels and units must be one line without tabs}}}
        set points {};foreach x $xs y $ys {if {![string is double -strict $x]||![string is double -strict $y]||![expr {abs($x)<Inf&&abs($y)<Inf}]} {error {Transient coordinates must be finite}};lappend points [list $x $y]}
        lappend output [dict create id transient_[incr index] label [_get $s label "Curve $index"] points $points kind line axis left]
    }
    file mkdir $destination;set model [dict create title $label panels [list [dict create id main axes {} series $output annotations {}]]]
    set artifact [file join $destination graph.png];renderModel $model $artifact
    return [dict create artifact $artifact graph_id plot.dataset.xy transient 1 series_count [llength $series] renderer_owner PLOT_DATASET_API_v4]
}
proc ::GX::PlotDatasetAPIv4::renderTransientCurves2D {xs series label destination {xUnit {}}} {
    if {[llength $xs]<2||[llength $xs]>200000||[llength $series]<1||[llength $series]>16} {error {Transient shared-X curves require 2..200000 X points and 1..16 series}}
    if {[regexp {[\r\n\t]} $xUnit]} {error {Transient X unit must be one line without tabs}}
    set independent {};foreach s $series {lappend independent [dict merge $s [dict create label [_get $s label Y] x_values $xs y_values [dict get $s values] x_unit $xUnit y_unit [_get $s unit {}]]]}
    renderTransientIndependentCurves2D $independent $label $destination
}
proc ::GX::PlotDatasetAPIv4::renderTransientOverlay {artifact xs ys label destination} {
    if {[llength $xs]<2||[llength $xs]!=[llength $ys]||[regexp {[\r\n]} $label]} {error {Transient overlay requires matching X/Y vectors with at least two points and a single-line label}}
    foreach value [concat $xs $ys] {if {![string is double -strict $value]||![expr {abs($value)<Inf}]} {error {Transient overlay coordinates must be finite}}}
    captureForArtifact $artifact $destination
    set m [snapshotValidate $destination];if {[dict get $m graph_id] eq {plot.dataset.xyz}} {error {XY overlay requires a 2D source}}
    # The complete canonical capture remains immutable; the overlay is a
    # caller-owned transient presentation, never a new Dataset or registry.
    set model [modelFromSpec [loadSpec [plotRefForArtifact $artifact]]]
    set points {};foreach x $xs y $ys {lappend points [list $x $y]}
    set panels [dict get $model panels];set panel [lindex $panels 0];dict lappend panel series [dict create id transient_overlay label $label kind line axis left points $points style {color #d62728}];lset panels 0 $panel;dict set model panels $panels
    renderModel $model [file join $destination graph.png]
    return [dict create artifact [file join $destination graph.png] graph_id [dict get $m graph_id] transient 1]
}

proc ::GX::PlotDatasetAPIv4::snapshotCopy {source destination} {
    set manifest [snapshotValidate $source]
    if {[file exists [file join $destination native_v4_snapshot.tcldict]]} {error {Native snapshot copy destination already contains a scientific snapshot}}
    file mkdir [file join $destination resources]
    dict for {id resource} [dict get $manifest datasets] {set relative [dict get $resource archive];if {[file exists [file join $destination $relative]]} {error {Snapshot resource copy would overwrite an existing file}};file copy -- [file join $source $relative] [file join $destination $relative]}
    _writeData [file join $destination native_v4_snapshot.tcldict] [dict remove $manifest source_dataset_ids source_variable_ids source_variables]
    return [snapshotValidate $destination]
}

proc ::GX::PlotDatasetAPIv4::_snapshotVariableIds {spec} {
 set ids {};if {[dict get $spec graph_id] eq {plot.dataset.xyz}} {set series [list $spec]} else {set series {};foreach p [dict get $spec panels] {lappend series {*}[dict get $p series]}}
 foreach s $series {dict for {key value} $s {if {[string match *_variable_id $key]&&$value ne {}} {lappend ids $value}};foreach field {x_error y_error band bar_bounds} {if {[dict exists $s $field]} {dict for {key value} [dict get $s $field] {if {[string match *_variable_id $key]||$key eq {variable_id}} {lappend ids $value}}}}};return [lsort -unique $ids]
}
