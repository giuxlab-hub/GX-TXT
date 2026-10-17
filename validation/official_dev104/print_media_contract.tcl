# SPDX-License-Identifier: GPL-3.0-or-later
source [file join [file dirname [info script]] print_recipe_contract.tcl]
exec python3 -B -c {
from PIL import Image
from pathlib import Path
import sys
p=Path(sys.argv[1])
Image.new('RGB',(120,80),(20,90,180)).save(p/'rgb.png')
Image.new('I;16',(120,80),65535).save(p/'highbit.tiff')
Image.new('F',(120,80),123.456).save(p/'float.tiff')
Image.new('RGB',(120,80),'red').save(p/'frames.gif',save_all=True,append_images=[Image.new('RGB',(120,80),'blue')],duration=50,loop=0)
} $out
set receipts {}
foreach {id name format media printable} {rgb rgb.png png image/png 1 highbit highbit.tiff tiff image/tiff 0 float float.tiff tiff image/tiff 0 frames frames.gif gif image/gif 0} {
    set original [file join $out $name];set before [::GX::sha256File $original]
    ::GX::datasetFilePublicationPublish $::GX::currentSession math.numeric [dict create dataset_id $id contract image.raster format $format media_type $media storage_kind binary source_file $original]
    unset -nocomplain ::response
    ::GX::printDocumentMediaInfo $id {apply {{value} {set ::response $value}}}
    set timer [after 15000 {set ::response {ok 0 error timeout}}];vwait ::response;after cancel $timer
    if {![dict get $response ok]} {error [dict get $response error]}
    set receipt [dict get $response result]
    check {[dict get $receipt printable]==$printable} capability_$id
    check {$printable || [dict get $receipt reason] ne {}} explicit_reason_$id
    check {[::GX::sha256File $original] eq $before && [::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession $id]] eq $before} immutable_$id
    dict set receipts $id $receipt
    ::GX::printDocumentRelease [dict get $receipt resource_id]
}
set f [open [file join $out media_result.tcldict] w];puts $f [dict create status PASS cases $checks media $receipts];close $f
puts {PASS original-image capabilities; no high-bit/float/frame clipping}
after 1200 {set ::cleanupWait 1};vwait ::cleanupWait
