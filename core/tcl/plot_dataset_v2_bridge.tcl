#!/usr/bin/env tclsh
# GX-TXT public standard_octave -> PLOT_DATASET_API_v2 bridge v1
# SPDX-License-Identifier: GPL-3.0-or-later

fconfigure stdout -buffering none -translation lf -encoding utf-8

proc bridgeError {message} {
    puts "ERROR\t[binary encode base64 -maxlen 0 [encoding convertto utf-8 $message]]"
    flush stdout
}
proc bridgeEncode {value} {
    return [binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]]
}
proc bridgeReadNode {fd} {
    if {[gets $fd line] < 0} {error "unexpected end of PlotSpec transport"}
    set parts [split $line \t]
    set type [lindex $parts 0]
    switch -- $type {
        S {
            set raw [lindex $parts 1]
            if {$raw eq ""} {return ""}
            return [encoding convertfrom utf-8 [binary decode base64 $raw]]
        }
        D {
            set count [lindex $parts 1]
            if {![string is integer -strict $count] || $count < 0} {error "invalid PlotSpec dict count"}
            set out [dict create]
            for {set i 0} {$i < $count} {incr i} {
                set key [bridgeReadNode $fd]
                dict set out $key [bridgeReadNode $fd]
            }
            return $out
        }
        L {
            set count [lindex $parts 1]
            if {![string is integer -strict $count] || $count < 0} {error "invalid PlotSpec list count"}
            set out {}
            for {set i 0} {$i < $count} {incr i} {lappend out [bridgeReadNode $fd]}
            return $out
        }
        default {error "invalid PlotSpec transport node '$type'"}
    }
}
proc bridgePersistSession {session} {
    set metadata [file join $session metadata]
    file mkdir $metadata
    ::GX::writeManifest [file join $metadata manifest.ini]
}

if {[catch {
    if {[llength $argv] ni {8 9}} {
        error "plot.dataset bridge requires SESSION ACTION KIND SOURCE_VARIANT GRAPH_ID VARIANT_ID RENDER REQUEST_FILE ?PROVIDER_KEY?"
    }
    lassign $argv session action kind sourceVariant graphId variantId doRender requestPath providerKey
    set session [file normalize $session]
    if {![file isdirectory $session]} {error "GX-TXT session does not exist: $session"}
    if {$action ni {create ensure render rerender}} {error "action must be create, ensure, render or rerender"}
    if {$kind ni {base variant}} {error "kind must be base or variant"}
    if {$doRender ni {0 1}} {error "render option must be boolean"}

    # Framework bootstrap is owned by this CORE executable bridge.  Octave
    # consumers only use this public command and never source desktop/private
    # Tcl entrypoints themselves.
    set root [file normalize [file join [file dirname [info script]] .. ..]]
    set argv0 __gxtxt_plot_dataset_bridge__
    source [file join $root gxtxt_pipeline.tcl]
    ::GX::defaults
    ::GX::loadModuleCatalog
    set ::GX::currentSession $session
    set manifest [file join $session metadata manifest.ini]
    if {[file isfile $manifest]} {::GX::loadManifest $manifest}
    ::GX::loadDatasetRegistry $session

    set descriptor [::GX::moduleField plot.dataset descriptor ""]
    if {$descriptor eq ""} {error "plot.dataset is not installed"}
    set desc [::GX::parseIni $descriptor]
    set entry [::GX::descriptorValue $desc public_api.PLOT_DATASET_API_v2 entrypoint ""]
    if {$entry eq ""} {error "plot.dataset does not publish PLOT_DATASET_API_v2"}
    source [file join [file dirname $descriptor] api plot_dataset_api_v1.tcl]
    source [file join [file dirname $descriptor] $entry]

    set spec ""
    if {$requestPath ne ""} {
        set fd [open $requestPath r]
        fconfigure $fd -encoding utf-8 -translation lf
        try {set spec [bridgeReadNode $fd]} finally {close $fd}
    }

    if {$action eq "ensure"} {
        if {$spec eq "" || $kind ne "variant" || $providerKey eq ""} {
            error "ensure requires a PlotSpec, kind=variant, and a stable provider_key"
        }
        ::GX::PlotDatasetAPIv2::validateSpec $spec
        set requestedGraph [dict get $spec graph_id]
        if {$graphId ne "" && $graphId ne $requestedGraph} {error "ensure graph_id disagrees with PlotSpec"}
        set found [::GX::plotVariantFindProviderKey plot.dataset $requestedGraph $providerKey]
        if {$found eq "" && $variantId ne "" && [::GX::plotVariantExists plot.dataset $requestedGraph $variantId]} {
            set priorKey [::GX::plotVariantField plot.dataset $requestedGraph $variantId provider_key ""]
            if {$priorKey eq ""} {set found $variantId}
        }
        if {$found eq ""} {
            set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec variant $sourceVariant]
        } else {
            set ref [dict create module_id plot.dataset graph_id $requestedGraph variant_id $found]
        }
        ::GX::plotVariantSet plot.dataset $requestedGraph [dict get $ref variant_id] [dict create provider_key $providerKey]
        bridgePersistSession $session
        if {$doRender} {set operationResult [::GX::PlotDatasetAPIv2::render $ref]}
    } elseif {$action eq "create"} {
        if {$spec eq ""} {error "create requires a PlotSpec"}
        set ref [::GX::PlotDatasetAPIv2::createPlotFromSpec $spec $kind $sourceVariant]
        bridgePersistSession $session
        if {$doRender} {set operationResult [::GX::PlotDatasetAPIv2::render $ref]}
    } else {
        if {$graphId eq ""} {error "$action requires graph_id"}
        set ref [dict create module_id plot.dataset graph_id $graphId variant_id $variantId]
        if {$spec ne ""} {
            ::GX::PlotDatasetAPIv2::applySpec $ref $spec
            bridgePersistSession $session
        }
        if {$action eq "render"} {
            set operationResult [::GX::PlotDatasetAPIv2::render $ref]
        } else {
            set operationResult [::GX::PlotDatasetAPIv2::rerender $ref]
        }
    }
    set artifacts [::GX::PlotDatasetAPIv2::artifacts $ref]
    set artifact [dict get $artifacts graph_artifact]
    puts [join [list RESULT [bridgeEncode [dict get $ref graph_id]] [bridgeEncode [dict get $ref variant_id]] \
        [bridgeEncode $artifact] [bridgeEncode [dict get $artifacts output_dir]] \
        [bridgeEncode [dict get $artifacts render_cache]] [bridgeEncode [dict get $artifacts summary]]] \t]
    flush stdout
} message options]} {
    bridgeError $message
    exit 2
}
