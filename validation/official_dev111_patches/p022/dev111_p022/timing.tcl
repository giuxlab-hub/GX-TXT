# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::P022Timing {variable rows {};variable stack {};variable targets {};variable dropped 0;variable receipts {}}
proc ::P022Timing::record {command args} {
    variable rows;variable stack;variable dropped;variable receipts
    set op [lindex $args end];set key [lindex $command 0]
    if {[string match ::oo::* $key] && [lindex $command 1] ni {render capture notify committed begin restore}} return
    if {$op eq {enter}} {dict lappend stack $key [clock microseconds];return}
    if {![dict exists $stack $key] || ![llength [dict get $stack $key]]} return
    set times [dict get $stack $key];set begin [lindex $times end];dict set stack $key [lrange $times 0 end-1]
    set arguments [lrange $command 1 2]
    if {$key in {::GX::meshDatasetNavigate ::GX::meshDatasetDrag}} {set arguments [lrange $command 1 5]}
    if {[llength $rows]<30000} {lappend rows [list $begin [expr {[clock microseconds]-$begin}] $key [string range $arguments 0 180] [lindex $args 0]]} else {incr dropped}
    if {$key eq {::GX::meshDatasetReadable} && [llength $receipts]<200} {
        set w [lindex $command 1]
        if {[info exists ::GX::DatasetViewer::state($w,lastReceipt)]} {
            lappend receipts [list [clock microseconds] $::GX::DatasetViewer::state($w,lastRequest) $::GX::DatasetViewer::state($w,lastReceipt) $::GX::DatasetViewer::state($w,lastResponseMs)]
        }
    }
}
proc ::P022Timing::start {{nativeDetail 1}} {
    variable targets;variable rows;variable stack;variable dropped;variable receipts
    if {[llength $targets]} {error {Timing already enabled}}
    set rows {};set stack {};set dropped 0;set receipts {}
    foreach target {
        ::GX::meshDatasetDrag ::GX::meshDatasetNavigate ::GX::meshDatasetRequest
        ::GX::meshDatasetReadable ::GX::datasetViewerCheck ::GX::datasetPreviewStamp
        ::GX::native3DPreviewDisplay ::GX::native3DPreviewLiveRefreshStatus
        ::GX::_native3DViewportPresentFrame ::GX::_native3DViewportReadable
        ::GX::Engine3D::cameraMotion ::GX::Engine3D::rpc ::GX::Engine3D::rerender
        ::GX::native3DGeometryCall ::GX::Native2D::core ::image
    } {
        if {!$nativeDetail && $target eq {::GX::Native2D::core}} continue
        if {[llength [info commands $target]]} {trace add execution $target {enter leave} ::P022Timing::record;lappend targets $target}
    }
    foreach class {::GX::Native2DCadCanvas::Host ::GX::Native2DCadProjection::Adapter ::GX::NativeCadSketch::Component} {
        if {![llength [info commands $class]]} continue
        foreach object [info class instances $class] {trace add execution $object {enter leave} ::P022Timing::record;lappend targets $object}
    }
    return $targets
}
proc ::P022Timing::stop {path} {
    variable targets;variable rows;variable dropped;variable receipts
    foreach target $targets {catch {trace remove execution $target {enter leave} ::P022Timing::record}}
    set targets {}
    set f [open $path {WRONLY CREAT EXCL}]
    try {puts $f "start_us\tduration_us\tcommand\targuments\tcode";foreach row $rows {puts $f [join [lmap v $row {string map [list \t { } \n { }] $v}] \t]}} finally {close $f}
    set f [open ${path}.receipts {WRONLY CREAT EXCL}];try {puts $f $receipts} finally {close $f}
    return [dict create spans [llength $rows] dropped $dropped path $path]
}
