# SPDX-License-Identifier: GPL-3.0-or-later
lassign $argv root output
set root [file normalize $root]
if {[file exists $output]} {error {Fresh private fixture output required}}
file mkdir $output;set output [file normalize $output]
foreach {key dir} {HOME home XDG_CONFIG_HOME config XDG_DATA_HOME data XDG_CACHE_HOME cache XDG_STATE_HOME state GXTXT_INSTALLATION_ROOT installation GXTXT_RESOURCE_ROOT resources GXTXT_RESOURCE_STORAGE buffers GXTXT_JOB_ROOT jobs TMPDIR tmp} {set ::env($key) [file join $output $dir];file mkdir $::env($key);file attributes $::env($key) -permissions 0700}
set argv0 __EXP01_FIXTURE_PREPARATION__
source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
::GX::configurationSet storage.session_root [file join $output Sessions]
::GX::configurationSet storage.temp_dir [file join $output tmp]
::GX::configurationSet storage.cache_dir [file join $output cache]
# Copy only the reported graphics preferences; no source/user Session locations.
set pref /home/giu/.config/gxtxt_pipeline/configuration.ini
set f [open $pref r]
foreach line [split [read $f] \n] {
 if {[regexp {^(viewers\.native3d\.[^=]+)=(.*)$} $line -> key value]} {::GX::configurationSet $key $value}
}
close $f
::GX::configurationSave
set project [::GX::projectCreate {EXP01 isolated local validation} {Synthetic fixture only}]
set session [::GX::createNewSession EXP01_regression {} 0]
set molecule [file join $root plugins modules viewer.molecule_3d library ATP_ideal.sdf]
set mol [::GX::datasetFilePublicationPublish $session viewer.molecule_3d [dict create dataset_id p022_atp contract molecular.structure format sdf storage_kind binary media_type chemical/x-mdl-sdfile source_file $molecule source {Repository ATP reference fixture} provenance {Isolated EXP01 rendering validation fixture; not a user or GUI publication}]]
::GX::native2DEnsure
::GX::modulePublicApiActivate viewer.3d_workbench WORKBENCH_3D_API_v1
set documents {};set shapes {};set workspaces {}
foreach count {1 10 50} {
 set scene [::GX::Native2D::core scene]
 set model [dict create format gxtxt.native_cad_sketch.v1 working_unit mm plane {origin {0 0 0} normal {0 0 1} u_axis {1 0 0}}]
 for {set i 0} {$i<$count} {incr i} {
  set x [expr {($i%10)*3.0}];set y [expr {int($i/10)*3.0}];set controls {}
  for {set j 0} {$j<11} {incr j} {lappend controls [list [expr {$x+$j*.2}] [expr {$y+.2*sin($j*.65+$i*.2)}]]}
  set family [expr {$i%5==1 ? {spline} : {polyline}}]
  set id [::GX::Native2D::core sketch_create $scene [dict create family $family controls $controls] 257]
  ::GX::Native2D::core object_style $scene $id {color {0.1 0.45 0.75 1} line_width 2}
  set entry [dict create definition [::GX::Native2D::core sketch_definition $scene $id] style [::GX::Native2D::core object_style $scene $id] direction [::GX::Native2D::core direction_marker $scene $id] role [::GX::Native2D::core identity_geometry_role $scene $id] name [::GX::Native2D::core identity_name $scene $id] attributes [::GX::Native2D::core identity_attributes $scene $id]]
  dict set entry style selected 0
  dict set model object/s[expr {$i+1}] $entry
 }
 ::GX::NativeCadSketch::validate $model
 set doc [::GX::interactiveDocumentCreate core.native2d sketch gxtxt.native_cad_sketch.v1 1 [dict create model $model allocation_counter $count]]
 dict set documents $count [dict get $doc id];dict set shapes $count $model
 # Existing owner supplies its empty canonical fixture schema; this is data
 # preparation, never a replacement CAD workflow or a GUI acceptance assertion.
 set wb [::GX::Workbench3D::defaultModel]
 dict set wb sketch_documents [dict get $doc id] [dict create document_id [dict get $doc id] working_unit mm plane [dict get $model plane]]
 set workspace [::GX::interactiveDocumentCreate viewer.3d_workbench workbench_3d workbench3d.document.v1 1 [dict create model $wb undo {} redo {} allocation_counters {}]]
 # Canonical Document IDs are sufficient; no unrelated Workspace promotion.
 dict set workspaces $count [dict get $workspace id]
 ::GX::Native2D::core destroy $scene
}
::GX::writeManifest [file join $session metadata manifest.ini]
set f [open [file join $output FIXTURE.tcldict] w];puts $f [dict create session $session project $project sketch_documents $documents workspaces $workspaces molecule_id p022_atp source_sha256 [::GX::sha256File $molecule] payload_sha256 [dict get [::GX::sessionInspectionDatasetPayload p022_atp] sha256]];close $f
set f [open [file join $output EXACT_MODELS.tcldict] w];puts $f $shapes;close $f
puts [dict create status PREPARED session $session documents $documents molecule_payload_sha256 [dict get [::GX::sessionInspectionDatasetPayload p022_atp] sha256]]
