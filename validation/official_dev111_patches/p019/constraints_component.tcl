lassign $argv framework output
if {[file exists $output]} {error {Fresh output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key)}
set argv0 __p019_constraints_component__
source [file join $framework gxtxt_pipeline.tcl];::GX::defaults
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSave {storage.session_root storage.temp_dir}
::GX::createNewSession p019_constraints {} 0
package require Tk;wm geometry . 1000x700+10+10;wm title . {P019 shared constraints component}
if {[lsearch -exact [info class methods ::GX::Native2DCadCanvas::Advanced -all] dimension]<0} {source [file join $framework core tcl native2d_cad_tools_constraints_v1.tcl]}
set errors {};set checks {};set trace {}
proc write {name value} {set f [open [file join $::output $name] w];puts $f $value;close $f}
proc bgerror {message} {lappend ::errors $message;write errors.tcllist $::errors;puts stderr $message}
proc pause {{ms 100}} {set ::waiting 1;after $ms {set ::waiting 0};vwait ::waiting}
proc check {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $label"};lappend ::checks $label;write checks.tcllist $::checks;puts "PASS $label";flush stdout}
proc xt {args} {lappend ::trace [list [clock microseconds] {*}$args];write input.tcllist $::trace;exec xdotool {*}$args}
proc click {widget} {xt mousemove [expr {[winfo rootx $widget]+[winfo width $widget]/2}] [expr {[winfo rooty $widget]+[winfo height $widget]/2}] click 1;pause}
proc type {widget text} {click $widget;xt key Home shift+End BackSpace;xt type --clearmodifiers -- $text;pause 60}
proc at {canvas device} {xt mousemove [expr {[winfo rootx $canvas]+int([lindex $device 0])}] [expr {[winfo rooty $canvas]+int([lindex $device 1])}]}
::GX::native2DEnsure
set scene [::GX::Native2D::core scene]
set id [::GX::Native2D::core sketch_create $scene {family line controls {{0 0} {3 0}}} 128]
::GX::Native2D::core object_style $scene $id {color {0.1 0.3 0.7 1} line_width 2}
frame .domain;pack .domain -fill both -expand 1
set host [::GX::native2DCadCanvasCreate .domain $scene];set canvas [$host canvas];pack $canvas -fill both -expand 1
set a [$host advanced];set cad [$host context]
set code 0
try {
 $host fit;pause 200
 check {![llength [info commands ::GX::CurveWorkbench::open]]} {standalone consumer imports no Workbench}
 set ref [$cad selection reference $id object 0]
 set available [$a constraint options [list $ref]]
 check {[dict exists $available horizontal] && [dict exists $available fixed]} {shared compatible native constraints discovered}
 set horizontal [$a constraint apply 0 [dict get $available horizontal]]
 set rid [dict get $horizontal id]
 $a constraint manage $rid disable
 check {[dict get [$a constraint inspect $rid] disabled]} {shared native disable}
 $a constraint manage $rid enable
 check {![dict get [$a constraint inspect $rid] disabled]} {shared native enable}
 $a dimension start distance [list $ref]
 set proposal [$a dimension preview [::GX::Native2D::core device $scene {1.5 -1}]]
 check {[dict get $proposal specification kind] eq {distance} && [dict get $proposal geometry value]==3} {native dimension preview exact length}
 set spec [dict get $proposal specification];set point [dict get $proposal annotation]
 $a dimension editor_create .editor [dict create specification $spec annotation $point value 3 native_unit mm display_unit mm canvas $canvas anchor_device [list 600 [expr {[winfo height $canvas]-80}]] title {Length (mm)}]
 pause 200;type .editor.value 4;xt key Return;pause 250
 check {![winfo exists .editor]} {actual Enter commits and closes shared editor}
 check {[$canvas find withtag cad_relation_preview] eq {} && [dict get [$a dimension state] geometry] eq {}} {accepted editor commit removes staged dimension preview}
 set dimension {};foreach receipt [$cad relationship list] {if {[dict get $receipt kind] eq {distance}} {set dimension $receipt}}
 write editor-accepted.tcldict [dict create relations [$cad relationship list] definition [$cad object definition $id]]
 check {$dimension ne {} && abs([dict get $dimension measured_value]-4)<1e-8} {actual editor changed authoritative native geometry}
 set before [$cad object definition $id]
 set fixed [$a constraint apply 0 [dict get [$a constraint options [list [$cad selection reference $id object 0]]] fixed]]
 set spec [$cad relationship get [dict get $dimension id]]
 $a dimension editor_create .editor [dict create specification $spec existing [dict get $spec id] annotation $point value 4 native_unit mm display_unit mm canvas $canvas anchor_device [list 600 [expr {[winfo height $canvas]-60}]] title {Length (mm)}]
 pause 150;type .editor.value 9;xt key Return;pause 250
 check {[winfo exists .editor] && [winfo ismapped .editor.reference]} {actual rejected driving edit offers supported reference fallback}
 check {[$cad object definition $id] eq $before} {rejected edit preserves exact native definition}
 set editorBottom [expr {[winfo rooty .editor]+[winfo height .editor]}]
 set buttonBottom [expr {[winfo rooty .editor.reference]+[winfo height .editor.reference]}]
 check {$buttonBottom<=$editorBottom && $editorBottom<=[winfo rooty $canvas]+[winfo height $canvas]} {shared editor grows and bounds reference button within Canvas}
 exec import -silent -window root [file join $output reference-layout.png]
 click .editor.reference;pause 150
 check {![winfo exists .editor] && [dict get [$a constraint inspect [dict get $spec id]] driven]} {actual reference action retains read-only native measurement}
 $a constraint manage [dict get $fixed id] remove
 check {[$cad object definition $id] eq $before} {reference fallback leaves scientific geometry unchanged}
 # Same public embedded Host, with actual unpressed pointer hover and Escape.
 $host cancel preview_test;$host tool select;$host fit;pause 80
 at $canvas [::GX::Native2D::core device $scene {1 -0.4}];xt click 1;pause 60
 set stableRelations [$cad relationship list]
 $a dimension start distance [list [$cad selection reference $id object 0]]
 at $canvas [::GX::Native2D::core device $scene {1.5 -0.5}];pause 200
 set staged [$a dimension state]
 check {[dict get $staged geometry] ne {} && [llength [$canvas find withtag cad_relation_preview]]>=3} {actual pointer hover draws native dimension preview before commit}
 set previewCount [llength [$canvas find withtag cad_relation_preview]]
 $host refresh final;pause 80
 check {[llength [$canvas find withtag cad_relation_preview]]==$previewCount} {repeated redraw replaces owned dimension preview items}
 exec import -silent -window root [file join $output dimension-preview.png]
 xt key Escape;pause 120
 write dimension-preview-cancel.tcldict [dict create focus [focus] state [$a dimension state] items [$canvas find withtag cad_relation_preview] definition [$cad object definition $id] relationships [$cad relationship list] expected_relationships $stableRelations]
 check {[$canvas find withtag cad_relation_preview] eq {} && [$cad object definition $id] eq $before && [$cad relationship list] eq $stableRelations} {actual Escape removes dimension preview without scientific mutation}
 # Annotation placement is staged, not a live scientific state update.
 set dimensionId [dict get $spec id]
 set label [dict get [$cad relationship dimension_geometry $dimensionId] label]
 set originalAnnotation [dict get [$cad relationship get $dimensionId] annotation]
 at $canvas $label;xt mousedown 1;pause 60
 set target [list [expr {[lindex $label 0]+55}] [expr {[lindex $label 1]-40}]]
 at $canvas $target;pause 180
 set drag [dict get [$a dimension state] annotation_drag]
 check {$drag ne {} && [dict get $drag changed] && [dict get [$cad relationship get $dimensionId] annotation] eq $originalAnnotation} {actual annotation pointer drag stages target without committed mutation}
 set previewLabel [dict get [$cad relationship dimension_preview [dict get $drag specification] [dict get $drag target]] label]
 set textItems {};foreach item [$canvas find withtag native_constraint_$dimensionId] {if {[$canvas type $item] eq {text}} {lappend textItems $item}}
 set actualLabel [$canvas coords [lindex $textItems end]]
 check {abs([lindex $actualLabel 0]-[lindex $previewLabel 0])<1e-8 && abs([lindex $actualLabel 1]-[lindex $previewLabel 1])<1e-8} {annotation label visibly follows authoritative native preview before release}
 check {[$canvas itemcget [lindex $textItems end] -text] eq {(4)}} {annotation preview preserves reference measurement presentation}
 exec import -silent -window root [file join $output annotation-preview.png]
 xt key Escape;xt mouseup 1;pause 150
 check {[dict get [$a dimension state] annotation_drag] eq {} && [dict get [$cad relationship get $dimensionId] annotation] eq $originalAnnotation && [$cad object definition $id] eq $before} {actual Escape restores committed annotation and preserves geometry}
 set ::componentLive 0
 $host configure [dict create callbacks [dict create guard {apply {event {return $::componentLive}}}]]
 set readonlyTools [$host advanced]
 set badges [$readonlyTools constraint present $canvas [list [dict get $spec id]]]
 check {[dict exists $badges [dict get $spec id]]} {readonly relationship presentation remains available while edits are gated}
 check {[catch {$a constraint manage $rid disable}]} {scientific mutation still rejects gated owner}
 set ::componentLive 1
 $a dimension start distance [list [$cad selection reference $id object 0]]
 set spec [dict get [$a dimension preview [::GX::Native2D::core device $scene {1 -1}]] specification]
 $a dimension editor_create .editor [dict create specification $spec annotation {1 -1} value 4 native_unit mm display_unit mm]
 pack .editor -side bottom -fill x;pause 150
 type .editor.value 7;xt key Escape;pause 150
 check {![winfo exists .editor] && [$cad object definition $id] eq $before} {Escape disposes editor with unchanged scientific state}
 check {$errors eq {}} {no background exceptions}
 $host dispose
 check {[::GX::Native2D::core kind $scene $id] eq {curve}} {Canvas controller disposal preserves consumer scene}
} on error {message options} {puts stderr "$message\n[dict get $options -errorinfo]";write failure.tcldict $options;set code 1} finally {
 write errors.tcllist $errors
 write RESULT.txt [expr {$code?{FAIL}:{PASS}}]
 catch {destroy .}
}
exit $code
