# SPDX-License-Identifier: GPL-3.0-or-later
# Actual shared cache/Supervisor semantics in a new synthetic private Session.
source [file join [file dirname [info script]] print_recipe_contract.tcl]
set ::deliveredA {};set ::deliveredB {};set ::deliveredLegacy {}
proc responseA {r} {lappend ::deliveredA $r}
proc responseB {r} {lappend ::deliveredB $r}
proc responseLegacy {r} {lappend ::deliveredLegacy $r}
proc waitPreview {key} {
    set until [expr {[clock milliseconds]+120000}]
    while {[dict get [::GX::datasetPreviewCacheStatus $key] status] eq {preparing}} {
        if {[clock milliseconds]>$until} {error {Finite cache wait timed out}}
        after 40 {set ::previewTick 1};vwait ::previewTick
    }
    return [::GX::datasetPreviewCacheStatus $key]
}
set scientific [::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession print_table]]
set a [::GX::datasetPreviewCacheSubscribe print_table {} responseA]
set b [::GX::datasetPreviewCacheSubscribe print_table {} responseB]
check {[dict get $a key] eq [dict get $b key] && [dict size $::GX::PreviewCache::tasks]==1} concurrent_subscribers_share_one_actual_job
::GX::datasetPreviewCacheUnsubscribe [dict get $a ticket]
set ready [waitPreview [dict get $b key]]
check {[dict get $ready status] eq {ready} && [dict get [lindex $::deliveredB end] status] eq {ready} && $::deliveredA eq {}} unsubscribe_does_not_cancel_other_consumer
set count [llength [::GX::scriptJobList]]
set hit [::GX::datasetPreviewCacheSubscribe print_table {} responseA]
after 100 {set ::previewTick 1};vwait ::previewTick
check {[llength [::GX::scriptJobList]]==$count && [dict get [lindex $::deliveredA end] cache_hit]} cache_hit_no_job
# Independent options yield a cold key, then a legacy consumer joins that job.
set c [::GX::datasetPreviewCacheSubscribe print_table {print_subscription_case legacy_join} responseA]
set legacy [::GX::datasetPreviewCacheRequest print_table {print_subscription_case legacy_join} responseLegacy]
::GX::datasetPreviewCacheUnsubscribe [dict get $c ticket]
set ready [waitPreview $legacy]
check {[dict get $ready status] eq {ready} && [dict get [lindex $::deliveredLegacy end] status] eq {ready}} unsubscribe_preserves_legacy_join
set key [dict get $b key]
::GX::datasetMetadataUpdate $::GX::currentSession print_table {print_fixture_metadata changed}
check {[::GX::datasetPreviewCacheKey print_table] ne $key && [::GX::datasetPreviewCacheRead print_table $key] eq {}} scientific_metadata_invalidates_cache
check {[::GX::sha256File [::GX::datasetResolvePath $::GX::currentSession print_table]] eq $scientific} consultation_preserves_scientific_payload
set f [open [file join $out subscription_result.tcldict] w];puts $f [dict create status PASS checks $checks scientific_sha256 $scientific];close $f
puts {PASS actual cache subscriptions}
