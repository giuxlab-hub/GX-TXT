# Public Preview/cache/publication lifecycle in a fresh private Session.
lassign $argv root out
set root [file normalize $root];set out [file normalize $out]
if {[file exists $out]} {error {Fresh output required}}
file mkdir $out
foreach name {XDG_CONFIG_HOME XDG_DATA_HOME XDG_CACHE_HOME XDG_STATE_HOME GXTXT_INSTALLATION_ROOT GXTXT_RESOURCE_ROOT GXTXT_RESOURCE_STORAGE GXTXT_JOB_ROOT} {set ::env($name) [file join $out $name]}
set argv0 __dev103_cache_contracts__;source [file join $root gxtxt_pipeline.tcl]
::GX::defaults;::GX::loadModuleCatalog
set ::GX::cfg(output_root) [file join $out sessions]
set checks {}
proc check {condition label} {if {![uplevel 1 [list expr $condition]]} {error "FAIL $label"};lappend ::checks $label;puts "PASS $label";flush stdout}
proc save {name value} {set f [open [file join $::out $name.tcldict] w];puts $f $value;close $f}
proc waitCache {key} {
    set deadline [expr {[clock milliseconds]+180000}]
    while {[clock milliseconds]<$deadline} {
        set status [::GX::datasetPreviewCacheStatus $key]
        if {[dict get $status status] ne "preparing"} {return $status}
        after 50 [list set ::cacheTick 1];vwait ::cacheTick
    }
    error {Cache preparation timed out}
}
try {
    set session [::GX::createNewSession media_cache]
    set image [file join [pwd] _private_dev103 catalog_inputs synthetic_image.png]
    set mesh [file join $out triangle.stl];set f [open $mesh w];puts $f {solid triangle
facet normal 0 0 1
outer loop
vertex 0 0 0
vertex 1 0 0
vertex 0 1 0
endloop
endfacet
endsolid triangle};close $f
    exec [::GX::runtimeToolResolve python] -c {import wave,struct,math,sys
with wave.open(sys.argv[1],'wb') as w:
 w.setparams((1,2,8000,8000,'NONE','not compressed'));w.writeframes(b''.join(struct.pack('<h',int(20000*math.sin(2*math.pi*440*i/8000))) for i in range(8000)))} [file join $out tone.wav]
    foreach {id contract format media path} [list cache_image image.raster png image/png $image cache_pdf document.pdf pdf application/pdf /usr/share/doc/shared-mime-info/shared-mime-info-spec.pdf cache_audio audio.waveform wav audio/wav [file join $out tone.wav] cache_mesh geometry.mesh stl model/stl $mesh] {
        ::GX::datasetFilePublicationPublish $session viewer.curve_digitizer [dict create dataset_id $id contract $contract format $format media_type $media storage_kind binary source_file $path]
    }
    set plan [::GX::datasetPublicationV2Prepare $session math.numeric {dataset_id cache_array contract table.generic storage hdf5}]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    ::GX::datasetPublicationV2DeclareDimension $writer row 2
    ::GX::datasetPublicationV2DeclareDimension $writer col 3
    ::GX::datasetPublicationV2DeclareVariable $writer matrix {dtype float64 dimension_ids {row;col} unit V}
    ::GX::datasetPublicationV2WriteVariable $writer matrix {0 1 2 3 4 5} {2 3}
    ::GX::datasetPublicationV2Finalize $writer
    foreach {id kind} {cache_image media cache_pdf media cache_audio media cache_mesh native3d cache_array array} {
        set key [::GX::datasetPreviewCacheRequest $id]
        set response [waitCache $key];save $id $response
        check {[dict get $response status] eq "ready"} "$id completes a managed standard preparation"
        set representation [::GX::datasetPreviewCacheRead $id $key];save ${id}_representation $representation
        check {[dict get $representation kind] eq $kind && [dict exists $representation media_artifact]} "$id has a verified applicable $kind graphical artifact"
        set artifact [dict get $representation media_artifact path]
        exec identify $artifact
        if {$id eq "cache_array"} {
            exec [::GX::runtimeToolResolve python] -c {from PIL import Image
import sys
im=Image.open(sys.argv[1]).convert('RGB')
assert im.size==(24,16)
actual=[im.getpixel((c*8+4,r*8+4)) for r in range(2) for c in range(3)]
for value,pixel in enumerate(actual):
 t=value/5
 expected=(int(255*t),int(180*(1-abs(2*t-1))),int(255*(1-t)))
 assert max(abs(a-b) for a,b in zip(pixel,expected))<=1,(value,pixel,expected)
} $artifact
            check {1} {Rank-2 standard frame retains all six distinct finite source palette values}
        }
        set jobs [llength [::GX::scriptJobList]]
        ::GX::datasetPreviewCacheRequest $id
        check {[llength [::GX::scriptJobList]]==$jobs} "$id reuses its exact source/render cache without a new Job"
    }
    save result [dict create status PASS checks $checks session $session]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
