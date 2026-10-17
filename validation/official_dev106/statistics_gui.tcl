# SPDX-License-Identifier: GPL-3.0-or-later
proc statsAudit {} {
    set p [::GX::datasetPublicationV2Prepare $::GX::currentSession math.numeric {dataset_id stats_input contract table.generic storage hdf5}]
    set writer [::GX::datasetPublicationV2OpenWriter $p];::GX::datasetPublicationV2DeclareDimension $writer row 32
    foreach {id unit} {x V y V group 1 weight 1} {::GX::datasetPublicationV2DeclareVariable $writer $id [dict create dtype float64 unit $unit dimension_ids row]}
    set x {};set y {};set g {};set weights {}
    for {set n 0} {$n<32} {incr n} {lappend x [expr {1.0+$n*.3+sin($n)}];lappend y [expr {2.0+$n*.6+.4*cos($n)}];lappend g [expr {$n%3}];lappend weights [expr {1.0+$n%4}]}
    foreach id {x y group weight} values [list $x $y $g $weights] {::GX::datasetPublicationV2WriteRange $writer $id 0 $values}
    ::GX::datasetPublicationV2Finalize $writer
    set revision [::GX::datasetRevisionToken stats_input]
    set modules {};foreach provider [::GX::StatisticalAnalysisViewer::providers] {lappend modules [dict get $provider module_id]}
    gcheck {[llength $modules]==10} ten_providers
    foreach m $modules {::GX::moduleSetEnabled $m 0;::GX::moduleSetRunSelected $m 0}
    set ordinary [::GX::buildStandardAnalysisQueue_before_plot_variant]
    gcheck {$ordinary eq {}} disabled_analysis_excluded_from_ordinary_run
    set w .gxtxt_statistical_analysis
    set receipts {}
    foreach m $modules {
        ::GX::viewerGuiDesignValueSet $w method $m
        ::GX::viewerGuiDesignValueSet $w dataset stats_input
        ::GX::StatisticalAnalysisViewer::action $w method_changed
        foreach key [::GX::moduleConfigKeys $m] {
            set type [::GX::moduleConfigField $m $key type {}]
            if {$type eq {variable}} {
                switch -- $key {weight_variable {set v weight} group_variable {set v group} second_variable {set v y} default {set v x}}
                ::GX::viewerGuiDesignValueSet $w param_$key $v
            } elseif {$type eq {table}} {
                switch -- $key {grouping {set v group} default {set v {x;y}}}
                ::GX::viewerGuiDesignValueSet $w param_$key $v
            } elseif {$key eq {render_graphs}} {::GX::viewerGuiDesignValueSet $w param_$key 0}
        }
        set snapshot [array get ::GX::moduleCfg "$m,*"]
        ::GX::StatisticalAnalysisViewer::action $w run
        set run [dict get $::GX::StatisticalAnalysisViewer::state($w,receipt) run_id]
        set deadline [expr {[clock seconds]+100}]
        while 1 {
            set result [::GX::StatisticalAnalysisViewer::status $m $run]
            if {[dict get $result state] ne {RUNNING}} break
            if {[clock seconds]>$deadline} {::GX::StatisticalAnalysisViewer::cancel $m $run;error "Timeout: $m"}
            after 100 {set ::statsTick 1};vwait ::statsTick
        }
        record stats_[string map {. _} $m] $result
        if {[dict get $result state] ne {COMPLETED}} {error "Statistics $m failed: $result"}
        gcheck {![::GX::moduleIsEnabled $m] && ![::GX::moduleRunIsSelected $m]} [string map {. _} $m]_disabled_and_unselected
        gcheck {[dict size $snapshot]==[dict size [array get ::GX::moduleCfg "$m,*"]]} [string map {. _} $m]_config_shape
        dict for {k v} $snapshot {if {$::GX::moduleCfg($k) ne $v} {error "Persistent configuration changed: $k"}}
        gcheck {[::GX::datasetRevisionToken stats_input] eq $revision} [string map {. _} $m]_source_unchanged
        dict set receipts $m $result
        puts "PASS genuine statistical Viewer $m";flush stdout
    }
    record statistics_gui [dict create status PASS providers $receipts]
    raise $w;after 800 {capture .gxtxt_statistical_analysis statistics_raised}
}
if {[catch {statsAudit} failure options]} {record statistics_gui_failure [dict get $options -errorinfo]}
