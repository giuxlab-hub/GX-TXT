# Public canonical fixture construction; private dev103 paths only.
lassign $argv root out
foreach key {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($key) [file join $out seed $key]}
set argv0 __dev103_remote_seed__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out node_sessions]
set session [::GX::createNewSession node_authority]
set plan [::GX::datasetPublicationV2Prepare $session math.numeric {dataset_id remote_big contract table.generic storage hdf5}]
set writer [::GX::datasetPublicationV2OpenWriter $plan]
::GX::datasetPublicationV2DeclareDimension $writer row 1000000
::GX::datasetPublicationV2DeclareVariable $writer exact {dtype uint64 unit 1 dimension_ids row}
for {set start 0} {$start<1000000} {incr start 10000} {
    set values {};for {set i 0} {$i<10000} {incr i} {lappend values [expr {9007199254740993+$start+$i}]}
    ::GX::datasetPublicationV2WriteRange $writer exact $start $values
}
::GX::datasetPublicationV2Finalize $writer
set plan [::GX::datasetPublicationV2Prepare $session math.numeric {dataset_id remote_matrix contract tensor.generic storage hdf5}]
set writer [::GX::datasetPublicationV2OpenWriter $plan]
::GX::datasetPublicationV2DeclareDimension $writer row 3;::GX::datasetPublicationV2DeclareDimension $writer col 4
::GX::datasetPublicationV2DeclareVariable $writer matrix {dtype int64 unit V dimension_ids row;col}
::GX::datasetPublicationV2WriteHyperslab $writer matrix {0 0} {3 4} {9007199254740993 9007199254740994 9007199254740995 9007199254740996 -9007199254740993 -9007199254740994 -9007199254740995 -9007199254740996 0 1 2 3}
::GX::datasetPublicationV2Finalize $writer
# A registered CSV import retains nullable floating cells; typed Publication
# intentionally refuses creating an empty cell in its nonnullable write API.
file mkdir [file join $session datasets]
set path [file join $session datasets remote_typed.csv]
set f [open $path w];fconfigure $f -encoding utf-8
puts $f {label,flag,reading}
puts $f {µV,1,1.25}
puts $f {"commas,a",0,}
puts $f {,1,NaN}
puts $f {two words,0,Inf};close $f
set fields [dict create kind table.generic contract table.generic format csv storage_provider csv path datasets/remote_typed.csv canonical_delimiter comma var_count 3 row_count 4 variable_schema_api_version 3 variables {label;flag;reading} units {} canonical_sha256 [::GX::sha256File $path]]
set index 0
foreach id {label flag reading} dtype {string bool float64} {
    incr index
    foreach {field value} [list variable_id $id enabled 1 canonical $id dtype $dtype value_kind [expr {$dtype eq "string"?"text":"number"}] rank 1 shape 4 dimension_ids row axis_kind explicit coordinate_role data unit [expr {$id eq "reading"?"V":"1"}]] {dict set fields var${index}_$field $value}
}
::GX::datasetRegister remote_typed $fields
::GX::saveDatasetRegistry $session
set f [open [file join $out node_session.txt] w];puts $f $session;close $f
puts "SEEDED $session"
