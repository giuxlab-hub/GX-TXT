# SPDX-License-Identifier: GPL-3.0-or-later
# Read-only GX-TXT Catalog/Namespace contract fixture for Curve Digitizer.
proc assert {condition message} {if {!$condition} {error $message}}
namespace eval ::GX {
    variable revision 3
    variable sourceState unchanged
}
proc ::GX::sessionInspectionCurrentSession {} {return /example/session}
proc ::GX::interactiveDocumentSessionToken {} {return session-token}
proc ::GX::datasetCatalogSnapshot {{session ""}} {
    return [dict create session_token catalog-token revision $::GX::revision current_namespace base datasets [list \
        [dict create dataset_id image_one kind image.raster namespace {group/sem} canonical_sha256 abc] \
        [dict create dataset_id csv_one kind table.generic namespace base canonical_sha256 def]]]
}
proc ::GX::datasetNamespaceList {{session ""}} {return {base group group/sem}}
proc ::GX::sessionInspectionDataset {id {session ""}} {
    switch -- $id {
        image_one {return [dict create contract image.raster media_type image/png format png]}
        csv_one {return [dict create contract table.generic media_type text/csv format csv]}
    }
    error {Unexpected Dataset}
}
proc ::GX::viewerBackendRegister {args} {return}
source [file join [file dirname [info script]] .. api curve_digitizer_viewer_api_v1.tcl]
set payload [::GX::CurveDigitizer::_catalogPayload]
set records [split $payload "\n"]
set imageCount 0
set stateCount 0
set namespaces {}
foreach line $records {
    set cols [split $line "\t"]
    set kind [lindex $cols 0]
    set values [lmap encoded [lrange $cols 1 end] {::GX::CurveDigitizer::_b64d $encoded}]
    switch -- $kind {
        STATE {
            incr stateCount
            assert [expr {[lindex $values 0] eq "session-token" && [lindex $values 2] == 3}] "Unexpected state"
        }
        IMAGE {
            incr imageCount
            assert [expr {[lindex $values 0] eq "image_one" && [lindex $values 1] eq "group/sem"}] "Wrong image namespace"
        }
        NAMESPACE {lappend namespaces [lindex $values 0]}
        default {error "Unexpected record: $kind"}
    }
}
assert [expr {$imageCount == 1 && $stateCount == 1}] "Unexpected record counts"
assert [expr {$namespaces eq {base group group/sem}}] "Namespaces unavailable"
set rev [::GX::CurveDigitizer::_catalogState]
assert [expr {[string first "STATE\t" $rev] == 0}] "Revision record invalid"
lassign [::GX::CurveDigitizer::_handleRequest "" "REQ\t42\tSESSION_TOKEN"] rid tokenPayload
assert [expr {$rid eq "42"}] "Incorrect asynchronous Session request identity"
set encoded [lindex [split $tokenPayload "\t"] 1]
assert [expr {[::GX::CurveDigitizer::_b64d $encoded] eq "session-token"}] "CORE Session token was not obtained from the read-only API"
puts "PASS catalog state, image filtering and hierarchical namespace records"
