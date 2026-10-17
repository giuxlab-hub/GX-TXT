# Published realization enumeration and explicit-selection transform; CORE mock.
namespace eval ::GX { variable md {};variable session /session }
proc ::GX::sessionInspectionCurrentSession {} {return $::GX::session}
proc ::GX::sessionInspectionDataset {id s} {return [dict create id $id kind table.generic]}
proc ::GX::datasetMetadataRead {s id} {return $::GX::md}
source [file join [file dirname [info script]] .. api curve_digitizer_calibration_api_v1.tcl]
set hash [string repeat a 64]
set hash2 [string repeat b 64]
set md [dict create curve_digitizer.plugin_id viewer.curve_digitizer curve_digitizer.manifest_version 1 \
  curve_digitizer.source_dataset_id src curve_digitizer.source_sha256 [string repeat c 64] \
  curve_digitizer.configuration_id cfg curve_digitizer.calibration_type affine \
  curve_digitizer.image_width 200 curve_digitizer.image_height 100 \
  curve_digitizer.coordinate_origin bottom_left curve_digitizer.y_direction up curve_digitizer.physical_unit um \
  curve_digitizer.transform.convention column_vector_homogeneous_xy1 \
  curve_digitizer.transform.raster_origin top_left curve_digitizer.transform.pixel_reference pixel_center \
  curve_digitizer.calibration_id cal_[string range $hash 0 23] curve_digitizer.calibration_sha256 $hash \
  curve_digitizer.measurement_count 3]
foreach axis {x y} {
    dict set md curve_digitizer.transform.${axis}_minimum 0
    dict set md curve_digitizer.transform.${axis}_maximum 100
    dict set md curve_digitizer.transform.${axis}_scale linear
    dict set md curve_digitizer.transform.${axis}_unit um
}
foreach n {0 1 2} {
    set pref curve_digitizer.measurement.${n}.
    dict set md ${pref}measurement_id "m$n"
    dict set md ${pref}label "Trial $n"
    dict set md ${pref}state [lindex {accepted accepted rejected} $n]
    dict set md ${pref}active [expr {$n==0}]
    dict set md ${pref}valid [expr {$n!=2}]
    if {$n==2} continue
    set digest [expr {$n==0?$hash:$hash2}]
    dict set md ${pref}calibration_id cal_[string range $digest 0 23]
    dict set md ${pref}calibration_sha256 $digest
    dict set md ${pref}calibration_type affine
    foreach axis {x y} {
      dict set md ${pref}transform.${axis}_minimum 0
      dict set md ${pref}transform.${axis}_maximum [expr {$n==0?100:200}]
      dict set md ${pref}transform.${axis}_scale linear
      dict set md ${pref}transform.${axis}_unit um
    }
}
for {set a 0} {$a<3} {incr a} {for {set b 0} {$b<3} {incr b} {
  set v [expr {$a==$b?1.0:0.0}]
  dict set md curve_digitizer.transform.h${a}${b} $v
  foreach n {0 1} {dict set md curve_digitizer.measurement.${n}.transform.h${a}${b} $v}
}}
set ::GX::md $md
set trials [::GX::CurveDigitizerCalibration::replicates xyz]
if {[llength $trials]!=3} {error "Incorrect measurement count"}
set a [::GX::CurveDigitizerCalibration::transformPoints xyz {{0.25 0.25}} pixel_to_scientific m0]
set b [::GX::CurveDigitizerCalibration::transformPoints xyz {{0.25 0.25}} pixel_to_scientific m1]
if {abs([lindex $a 0 0]-25)>1e-6 || abs([lindex $b 0 0]-50)>1e-6} {error "Explicit mapping not applied"}
if {![catch {::GX::CurveDigitizerCalibration::transformPoints xyz {{0.25 0.25}} pixel_to_scientific m2}]} {error "Invalid draft mapping accepted"}
if {![catch {::GX::CurveDigitizerCalibration::identity xyz unknown}]} {error "Unknown mapping accepted"}
puts {PASS Tcl replication API, independent mappings, invalid/unknown ID}
