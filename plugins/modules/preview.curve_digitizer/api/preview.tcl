# SPDX-License-Identifier: GPL-3.0-or-later
# Installed trusted Preview component. No separate Viewer or scientific I/O.
namespace eval ::GX::DigitizerFamilyPreview {
    variable root [file dirname [file dirname [info script]]]
    variable state {}
    variable pending {}
    variable pendingSerial 0
}
proc ::GX::DigitizerFamilyPreview::design {} {
    variable root
    return [::GX::viewerGuiDesignRead [file join $root gui design.tcldict]]
}
proc ::GX::DigitizerFamilyPreview::_schema {context} {
    set id [dict get $context dataset_id]
    ::GX::modulePublicApiActivate viewer.curve_digitizer CURVE_DIGITIZER_DATASET_SCHEMA_API_v1
    set schema [::GX::CurveDigitizerDataset::read $id]
    set cols [dict get $schema columns]
    foreach role {curve_key curve_name point_order x y} {
        if {![dict exists $cols $role]} {error "Curve source is missing required public role $role"}
    }
    if {[dict get $schema publication_calibration_mode] eq {combined}} {
        foreach role {calibration_key calibration_name} {
            if {![dict exists $cols $role]} {error "Combined Dataset has no $role role"}
        }
    }
    return $schema
}
proc ::GX::DigitizerFamilyPreview::_optional {metadata key fallback} {
    expr {[dict exists $metadata $key] && [dict get $metadata $key] ne {} ?
          [dict get $metadata $key] : $fallback}
}
proc ::GX::DigitizerFamilyPreview::preview {context} {
    set id [dict get $context dataset_id]
    set m [_schema $context]
    set cols [dict get $m columns]
    set md [dict get $context metadata]
    set multiY [expr {[dict exists $m multi_y_available] && [dict get $m multi_y_available]}]
    set axes [expr {$multiY ? [::GX::CurveDigitizerDataset::axes $id] : {}}]
    set summary [dict create \
        Dataset $id Contract [dict get $context contract] \
        {Source Dataset} [_optional $md curve_digitizer.source_dataset_id {Not declared}] \
        {Source SHA-256} [_optional $md curve_digitizer.source_sha256 {Not declared}] \
        {Calibration class} [_optional $md curve_digitizer.calibration_type {Not declared}] \
        {Calibration mode} [dict get $m publication_calibration_mode] \
        {Calibration realizations} [_optional $md curve_digitizer.measurement_count {Not declared}] \
        {Family quantity} [_optional $md curve_digitizer.family_label {Not declared}] \
        {Family unit} [_optional $md curve_digitizer.family_unit {Not declared}] \
        {Scientific X Variable} [dict get $cols x] \
        {Scientific Y Variable} [dict get $cols y] \
        {Grouping identity} [join [dict get $m grouping_roles] { + }] \
        {Raster positions} [expr {[dict get $m raster_points_available] ?
                        {Declared canonical raster columns} : {Not published}}]]
    if {$multiY} {
        dict set summary {Scientific Y axes} [dict get $axes mode]
        dict set summary {Y2 schema version} [dict get $m curve_schema_version]
        dict set summary {Y-axis binding column} [dict get $cols y_axis_id]
        dict set summary {Calibration axis mappings} [llength [dict get $axes measurements]]
        dict set summary {Y1 unit} [dict get $axes unit_y1]
        dict set summary {Y2 unit} [dict get $axes unit_y2]
    }
    foreach {key label} {
        curve_digitizer.x_label {X label}
        curve_digitizer.x_unit {X unit}
        curve_digitizer.y_label {Y label}
        curve_digitizer.y_unit {Y unit}
        curve_digitizer.quality_status {Quality status}
        curve_digitizer.quality_issue_count {Quality issues}
        curve_digitizer.quality_curve_count {Curve count}
        curve_digitizer.quality_source_point_count {Original raster points}
        curve_digitizer.quality_published_row_count {Published rows}
        curve_digitizer.quality_calibration_realizations {Quality: calibration realizations}
        curve_digitizer.uncertainty_schema_version {Uncertainty schema}
    } {
        if {[dict exists $md $key]} {dict set summary $label [dict get $md $key]}
    }
    # Present the per-measurement published configuration, not only the count.
    set count [_optional $md curve_digitizer.measurement_count 0]
    if {[string is integer -strict $count] && $count>=0} {
        for {set i 0} {$i<min(16,$count)} {incr i} {
            set pfx "curve_digitizer.measurement.$i."
            set label [_optional $md [format {%slabel} $pfx] {Unnamed}]
            set state [_optional $md [format {%sstate} $pfx] {Not declared}]
            set class [_optional $md [format {%scalibration_type} $pfx] {Not declared}]
            set uid [_optional $md [format {%smeasurement_id} $pfx] {Not declared}]
            dict set summary "Calibration [expr {$i+1}] status" "$label / $state / $class / $uid"
            set xa [_optional $md [format {%stransform.x_minimum} $pfx] {?}]
            set xb [_optional $md [format {%stransform.x_maximum} $pfx] {?}]
            set xu [_optional $md [format {%stransform.x_unit} $pfx] {?}]
            set ya [_optional $md [format {%stransform.y_minimum} $pfx] {?}]
            set yb [_optional $md [format {%stransform.y_maximum} $pfx] {?}]
            set yu [_optional $md [format {%stransform.y_unit} $pfx] {?}]
            dict set summary "Calibration [expr {$i+1}] axes" "X $xa to $xb $xu; Y $ya to $yb $yu"
        }
        if {$count>16} {
            dict set summary {Additional calibration records}                 "[expr {$count-16}] more in canonical publication metadata"
        }
    }
    # CORE's precomputed Quality presentation supplies method, residual,
    # evidence and spacing details. Keep its reported semantics unchanged.
    if {[dict exists $context representation digitizer quality_rows]} {
        set i 0
        foreach row [dict get $context representation digitizer quality_rows] {
            if {$i>=50} break
            if {![dict exists $row label] || ![dict exists $row value]} continue
            set caption [dict get $row label]
            set value [dict get $row value]
            if {[dict exists $row unit] && [dict get $row unit] ne {}} {
                append value " " [dict get $row unit]
            }
            if {[dict exists $row meaning]} {
                append value " — " [dict get $row meaning]
            }
            dict set summary "Quality detail [incr i]: $caption" [string range $value 0 750]
        }
        if {[llength [dict get $context representation digitizer quality_rows]]>50} {
            dict set summary {Further Quality diagnostics}                 {See the published Quality API v2 report for remaining detail}
        }
    }
    if {[dict exists $context representation digitizer host_source_verification status]} {
        dict set summary {Source verification} [dict get $context representation digitizer host_source_verification status]
    }
    if {[dict exists $context representation digitizer quality]} {
        set report [dict get $context representation digitizer quality]
        foreach {key title} {accuracy_status {Accuracy status} uncertainty_status {Uncertainty status}
                              source_integrity {Source integrity}} {
            if {[dict exists $report $key]} {dict set summary $title [dict get $report $key]}
        }
    }
    if {![dict exists $summary {Accuracy status}]} {dict set summary {Accuracy status} {Not assessed}}
    if {![dict exists $summary {Uncertainty status}]} {
        dict set summary {Uncertainty status} {No published uncertainty status available}
    }
    set roleOrder {curve_key calibration_key curve_name calibration_name point_order
                   x y y_axis_id family_parameter raster_x raster_y point_id}
    set columns {}
    foreach role $roleOrder {if {[dict exists $cols $role]} {lappend columns [dict get $cols $role]}}
    return [dict create tabs [list \
        [dict create id curves label Curves kind gui role complementary] \
        [dict create id quality label {Calibration & Quality} kind metadata metadata $summary role complementary] \
        [dict create id canonical label {Canonical Data} kind gui role complementary]]]
}
proc ::GX::DigitizerFamilyPreview::guiMount {host context} {
    if {(![llength [info commands ::GX::datasetPreviewGuiCachedCurvesRequest]] ||
         ![llength [info commands ::GX::datasetPreviewGuiCachedPageRequest]]) &&
        ![info exists ::env(GXTXT_PREVIEW_TEST_LEGACY)]} {
        error {This Preview requires the CORE Preview Cache Bridge 022; it cannot silently fall back to recalculating canonical data}
    }
    if {[dict exists $context tab_id] && [dict get $context tab_id] eq {canonical}} {
        return [_tableMount $host $context]
    }
    if {[dict get $context dataset_id] eq {}} {error {No current canonical Dataset}}
    ::GX::viewerGuiDesignPreviewMount [design] $host [list ::GX::DigitizerFamilyPreview::dispatch]
    # Preview GUI admission permits bounded metadata and choices, but NOT
    # a scientific Dataset read from guiMount. Display a non-data placeholder
    # instead of a featureless empty list. Selecting the placeholder is an
    # explicit user event and triggers the same cooperative Load action.
    ::GX::datasetPreviewGuiControlSet $host groups [list {Select here or press Load curves to display the available curves}]
    ::GX::datasetPreviewGuiControlSet $host notice {Load curves reads the canonical Dataset in bounded pages; plotting is owned by Plot v4.}
}
proc ::GX::DigitizerFamilyPreview::dispatch {host event} {
    if {[dict exists $event control_id] &&
        [dict get $event control_id] in {first previous next precision}} {
        return [_tableDispatch $host $event]
    }
    set id [dict get $event control_id]
    # Passive list selection and labels have no action side effect.
    switch -- $id {
        load {return [load $host]}
        show {return [visibility $host 1]}
        hide {return [visibility $host 0]}
        show_all {return [showAll $host]}
        fit {return [navigate $host fit]}
        zoom_in {return [navigate $host zoom_in]}
        zoom_out {return [navigate $host zoom_out]}
        groups {
            variable state
            variable pending
            # A selection in the metadata-only placeholder is a deliberate
            # user action. No scientific work takes place in guiMount.
            if {![dict exists $state $host] && ![dict exists $pending $host] &&
                [dict exists $event type] && [dict get $event type] eq {list} &&
                [dict exists $event value selection] &&
                [llength [dict get $event value selection]]} {
                return [load $host]
            }
            return
        }
        default {return}
    }
}
proc ::GX::DigitizerFamilyPreview::_groups {context schema {yieldPages 0}} {
    # Prepare ONLY disposable presentation points from the public canonical
    # Dataset Preview Page authority. Never parse CSV, build another Dataset,
    # or submit a Dataset Transform. All (curve, calibration) identities come
    # from published schema role bindings, not physical CSV column positions.
    set cols [dict get $schema columns]
    set combined [expr {[dict get $schema publication_calibration_mode] eq {combined}}]
    set ids [list [dict get $cols curve_key] [dict get $cols curve_name] \
                  [dict get $cols point_order] [dict get $cols x] [dict get $cols y]]
    if {$combined} {
        lappend ids [dict get $cols calibration_key] [dict get $cols calibration_name]
    }
    set hasY2 [dict exists $cols y_axis_id]
    if {$hasY2} {lappend ids [dict get $cols y_axis_id]}
    set total 0
    set ordered {}
    set groups {}
    set source [dict get $context dataset_id]
    set session [dict get $context session]
    while {1} {
        if {$total>=20000} {
            error {Source exceeds 20000 rows: bounded Preview refuses partial curve reconstruction}
        }
        set page [::GX::datasetPreviewPage $session $source \
            [dict create start $total count [expr {min(1000,20000-$total)}] variable_ids $ids]]
        if {![dict get $page available]} {error {Canonical table is unavailable}}
        set n [dict get $page count]
        if {$n==0 && [dict get $page has_next]} {
            error {Canonical table paging made no progress}
        }
        if {[llength [dict get $page rows]]!=$n ||
            [llength [dict get $page source_rows]]!=$n} {
            error {Canonical table rows and source identities disagree}
        }
        foreach row [dict get $page rows] sourceRow [dict get $page source_rows] {
            if {[llength $row] != [llength $ids]} {
                error {Canonical table variable count changed during Preview}
            }
            lassign [lrange $row 0 4] curve name order x y
            set calibration [expr {$combined ? [lindex $row 5] : {}}]
            set calibrationName [expr {$combined ? [lindex $row 6] : {}}]
            set yAxis [expr {$hasY2 ? [lindex $row end] : {y1}}]
            if {$yAxis ni {y1 y2}} {
                error {Source row references an invalid logical Y axis.}
            }
            if {![string is entier -strict $order] || $order<0 ||
                ![string is entier -strict $sourceRow] || $sourceRow<=0 ||
                ![string is double -strict $x] ||
                ![string is double -strict $y] ||
                ![expr {abs(double($x))<Inf && abs(double($y))<Inf}]} {
                error {Canonical point has invalid order, source row or finite coordinate}
            }
            set key [list $curve $calibration $yAxis]
            if {![dict exists $groups $key]} {
                if {[dict size $groups]>=256} {
                    error {More than 256 curve/calibration groups; no partial view}
                }
                set label [expr {$name eq {} ? $curve : $name}]
                if {$combined} {
                    append label " / " [expr {$calibrationName eq {} ? $calibration : $calibrationName}]
                }
                if {$hasY2} {append label " (" [string toupper $yAxis] ")"}
                dict set groups $key [dict create label $label y_axis_id $yAxis samples {}]
                lappend ordered $key
            }
            set record [dict get $groups $key]
            if {[llength [dict get $record samples]]>=4096} {
                error {Plot v4 display is limited to 4096 points per curve/calibration group}
            }
            dict lappend record samples [list $order [list $x $y] [expr {$sourceRow-1}]]
            dict set groups $key $record
        }
        incr total $n
        if {![dict get $page has_next]} break
        if {$total>=20000} {
            error {Source exceeds 20000 rows: bounded Preview refuses partial curve reconstruction}
        }
        # In Preview GUI mode each bounded canonical page is followed by an
        # event-loop yield. Pure headless tests can use the synchronous default.
        if {$yieldPages} {yield [dict create stage reading rows $total]}
    }
    if {![llength $ordered]} {error {No digitized curve groups in this Dataset}}
    # Recheck host ownership before exposing a page-derived presentation.
    set updated [::GX::datasetPreviewGuiContext [dict get $context preview_host]]
    if {[dict get $updated dataset_id] ne $source ||
        [dict get $updated token] ne [dict get $context token] ||
        [dict get $updated canonical_identity] ne [dict get $context canonical_identity]} {
        error {Source or Session changed during canonical Preview paging}
    }
    return [dict create ordered $ordered records $groups combined $combined total_rows $total         multi_y $hasY2]
}
# CORE-retained native model consumer. No canonical source rows are scanned
# by the plugin on this path, including after Session/Preview reopen.
proc ::GX::DigitizerFamilyPreview::_cachedCurvesReady {host response} {
    if {[dict get $response status] ne {ready}} {
        catch {::GX::datasetPreviewGuiControlSet $host notice \
            "Curve loading failed: [dict get $response message]"}
        return
    }
    if {[catch {_displayCachedCurves $host $response} reason]} {
        catch {::GX::datasetPreviewGuiControlSet $host notice \
            "Cached scientific display failed: $reason"}
    }
}
proc ::GX::DigitizerFamilyPreview::_displayCachedCurves {host receipt} {
    variable state
    set context [::GX::datasetPreviewGuiContext $host]
    if {[dict get $receipt dataset_id] ne [dict get $context dataset_id]} {
        error {CORE retained model Dataset identity mismatch}
    }
    set model [dict get $receipt model]
    if {![dict exists $model panels]} {error {CORE retained model lacks panels}}
    set dataset [dict get $context dataset_id]
    set schema [_schema $context]
    set hasY2 [expr {[dict exists $schema multi_y_available] && [dict get $schema multi_y_available]}]
    set axes [expr {$hasY2 ? [::GX::CurveDigitizerDataset::axes $dataset] : {}}]
    set curveLookup {}
    if {$hasY2} {
        set registry [::GX::CurveDigitizerDataset::curves $dataset]
        foreach c [dict get $registry curves] {
            dict set curveLookup [dict get $c curve_id] $c
        }
    }
    set mode [expr {[dict exists $axes mode] ? [dict get $axes mode] : {y1}}]
    set limits [dict create x {Inf -Inf} y1 {Inf -Inf} y2 {Inf -Inf}]
    set labels {};set ids {};set plots {};set index 0
    foreach panel [dict get $model panels] {
        set seriesList {}
        foreach series [dict get $panel series] {
            set originalId {}
            foreach filter [expr {[dict exists $series row_filters] ? [dict get $series row_filters] : {}}] {
                if {[dict get $filter filter_variable_id] eq {curve_id} &&
                    [dict get $filter predicate] eq {exact_equal}} {
                    set originalId [dict get $filter value]
                }
            }
            if {$hasY2} {
                if {$originalId ne {} && [dict exists $curveLookup $originalId]} {
                    set curve [dict get $curveLookup $originalId]
                } elseif {[dict size $curveLookup]==1} {
                    set curve [lindex [dict values $curveLookup] 0]
                } else {
                    error {CORE retained series has ambiguous Y1/Y2 curve binding}
                }
                set yaxis [dict get $curve axis_id]
                set label [dict get $curve curve_name]
                if {$yaxis ni {y1 y2}} {error {Retained series has invalid Y-axis binding}}
                append label " (" [string toupper $yaxis] ")"
            } else {
                set yaxis y1
                set label [dict get $series label]
            }
            set minmax [expr {[dict exists $series canonical_full_bounds] ?
                [dict get $series canonical_full_bounds] :
                [dict get $series full_bounds]}]
            if {[llength $minmax]!=4} {error {Retained series has no complete scientific bounds}}
            lassign $minmax xMin yMin xMax yMax
            foreach key [list x $yaxis] lower [list $xMin $yMin] upper [list $xMax $yMax] {
                lassign [dict get $limits $key] lo hi
                dict set limits $key [list [expr {min(double($lower),$lo)}] [expr {max(double($upper),$hi)}]]
            }
            set newId trace[incr index]
            dict set series id $newId
            dict set series label $label
            dict set series axis [expr {$yaxis eq {y2} ? {right} : {left}}]
            lappend ids $newId
            lappend labels "[format %02d $index]. $label"
            lappend seriesList $series
        }
        dict set panel series $seriesList
        set properties {}
        foreach axis {x y1 y2} target {x left right} {
            lassign [dict get $limits $axis] lo hi
            if {$hasY2} {
                set p [_axisPresentation $axes $axis]
            } else {
                set initialAxis [dict get $panel axes [expr {$axis eq {x} ? {x} : {left}}]]
                set p [dict create label [dict get $initialAxis label] scale linear]
            }
            lassign [_axisRange $lo $hi [dict get $p scale]] a b scale
            dict set properties $target [dict create label [dict get $p label] min $a max $b scale $scale]
        }
        dict set panel axes $properties
        lappend plots $panel
    }
    if {![llength $ids]} {error {No current CORE retained curves}}
    dict set model panels $plots
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set area [::GX::datasetPreviewGuiControlConfigure $host plotarea {}]
    set container [winfo parent $area]
    grid rowconfigure $container 0 -weight 1
    grid columnconfigure $container 0 -weight 1
    set path $area.nativeplot
    set options [dict create prepared_model 1 retain_presentation 1]
    ::GX::PlotDatasetAPIv4::widgetValidateSources $model $options
    if {[dict exists $state $host plot] &&
        [winfo exists [dict get $state $host plot]]} {
        set path [dict get $state $host plot]
        ::GX::PlotDatasetAPIv4::widgetConfigure $path $model $options
    } else {
        ::GX::PlotDatasetAPIv4::widgetCreate $path $model $options
        pack $path -fill both -expand 1
    }
    dict set state $host [dict create dataset $dataset token [dict get $context token] plot $path ids $ids labels $labels]
    ::GX::datasetPreviewGuiControlSet $host groups $labels
    ::GX::datasetPreviewGuiControlSet $host notice \
        "[llength $ids] CORE-cached scientific traces, [dict get $receipt total_rows] rows; Plot v4 ([expr {[dict get $receipt cache_hit] ? {cache hit} : {new preparation}}])."
    return [dict create status ready cached 1 series [llength $ids]]
}
proc ::GX::DigitizerFamilyPreview::load {host} {
    # A user action only schedules bounded, source-checked work. There is no
    # nested 'update', blocking event loop, private Dataset worker or
    # asynchronous Tcl call into unadmitted native code.
    variable pending
    variable pendingSerial
    _stopPending $host
    set context [::GX::datasetPreviewGuiContext $host]
    if {[llength [info commands ::GX::datasetPreviewGuiCachedCurvesRequest]]} {
        ::GX::datasetPreviewGuiControlSet $host notice {Requesting current CORE cached curves asynchronously...}
        return [::GX::datasetPreviewGuiCachedCurvesRequest $host [list ::GX::DigitizerFamilyPreview::_cachedCurvesReady $host]]
    }
    if {![info exists ::env(GXTXT_PREVIEW_TEST_LEGACY)]} {
        error {CORE Preview Cache Bridge 022 is missing. No fallback canonical re-read is permitted}
    }
    set schema [_schema $context]
    dict set context preview_host $host
    set reader ::GX::DigitizerFamilyPreview::pageReader[incr pendingSerial]
    set generation $pendingSerial
    set record [dict create reader $reader generation $generation         token [dict get $context token]         dataset [dict get $context dataset_id]         canonical_identity [dict get $context canonical_identity]]
    dict set pending $host $record
    ::GX::datasetPreviewGuiControlSet $host notice {Reading canonical curve rows…}
    if {[catch {
        set progress [coroutine $reader ::GX::DigitizerFamilyPreview::_groups $context $schema 1]
    } message]} {
        _stopPending $host
        ::GX::datasetPreviewGuiControlSet $host notice "Curve loading failed: $message"
        return [dict create status failed reason $message]
    }
    set task [dict get $pending $host]
    dict set task after_id [after 1 [list ::GX::DigitizerFamilyPreview::_advance $host $generation $progress]]
    dict set pending $host $task
    return [dict create status preparing plot_api PLOT_DATASET_API_v4]
}
proc ::GX::DigitizerFamilyPreview::_stopPending {host} {
    variable pending
    if {![dict exists $pending $host]} return
    set task [dict get $pending $host]
    dict unset pending $host
    if {[dict exists $task after_id]} {after cancel [dict get $task after_id]}
    set reader [dict get $task reader]
    if {[llength [info commands $reader]]} {rename $reader {}}
}
proc ::GX::DigitizerFamilyPreview::_advance {host generation progress} {
    variable pending
    if {![dict exists $pending $host] ||
        [dict get $pending $host generation]!=$generation} return
    set task [dict get $pending $host]
    dict unset task after_id
    dict set pending $host $task
    if {[catch {
        set current [::GX::datasetPreviewGuiContext $host]
        foreach {contextField taskField} {
            token token dataset_id dataset canonical_identity canonical_identity
        } {
            if {[dict get $current $contextField] ne [dict get $task $taskField]} {
                error {Preview source or Session changed during curve loading}
            }
        }
        if {[dict exists $progress stage]} {
            ::GX::datasetPreviewGuiControlSet $host notice                 "Reading canonical rows: [dict get $progress rows]…"
            set reader [dict get $task reader]
            set progress [$reader]
            set task [dict get $pending $host]
            dict set task after_id [after 1 [list ::GX::DigitizerFamilyPreview::_advance $host $generation $progress]]
            dict set pending $host $task
        } else {
            _stopPending $host
            _display $host $progress
        }
    } message]} {
        _stopPending $host
        catch {::GX::datasetPreviewGuiControlSet $host notice "Curve loading failed: $message"}
    }
}
proc ::GX::DigitizerFamilyPreview::_display {host groups} {
    if {[dict exists $groups multi_y] && [dict get $groups multi_y]} {
        return [_displayY2 $host $groups]
    }
    variable state
    set context [::GX::datasetPreviewGuiContext $host]
    set m [_schema $context]
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set lines {}
    set labels {}
    set ids {}
    set index 0
    set minX Inf
    set maxX -Inf
    set minY Inf
    set maxY -Inf
    foreach key [dict get $groups ordered] {
        set item [dict get $groups records $key]
        set samples [lsort -integer -index 0 [dict get $item samples]]
        set points {}
        set rows {}
        set prior {}
        foreach sample $samples {
            lassign $sample ordinal coords sourceRow
            if {$prior ne {} && $ordinal != $prior+1} {
                error {Curve has missing or repeated point_order: cannot connect a false segment}
            }
            set prior $ordinal
            lassign $coords x y
            set minX [expr {min($minX,double($x))}]
            set maxX [expr {max($maxX,double($x))}]
            set minY [expr {min($minY,double($y))}]
            set maxY [expr {max($maxY,double($y))}]
            lappend points $coords
            lappend rows $sourceRow
        }
        set id "trace[incr index]"
        set label [dict get $item label]
        lappend lines [dict create id $id label $label \
            kind [expr {[llength $points]==1 ? {scatter} : {line}}] \
            axis left points $points source_rows $rows \
            style [dict create color auto line_style solid line_width 2 marker none]]
        lappend ids $id
        lappend labels "[format %02d $index]. $label"
    }
    if {$minX>=Inf || $minY>=Inf} {error {No finite canonical points}}
    set xPad [expr {$maxX==$minX ? max(abs($minX)*0.03,1e-9) : ($maxX-$minX)*0.03}]
    set yPad [expr {$maxY==$minY ? max(abs($minY)*0.03,1e-9) : ($maxY-$minY)*0.03}]
    set roles [dict get $m columns]
    set xLabel [dict get $roles x]
    set yLabel [dict get $roles y]
    foreach v [dict get $context variables] {
        set vid [dict get $v variable_id]
        if {$vid ni [list [dict get $roles x] [dict get $roles y]]} continue
        set caption [dict get $v display_label]
        if {$caption eq {}} {set caption $vid}
        if {[dict get $v unit] ne {}} {append caption " ([dict get $v unit])"}
        if {$vid eq [dict get $roles x]} {set xLabel $caption} else {set yLabel $caption}
    }
    # Native C++ Plot v4 gets a disposable, explicitly page-derived model.
    # The source remains the registered Dataset and the current Preview host
    # supplies strict Session/identity invalidation. No canonical analysis,
    # transform, publication or independent numeric renderer is introduced.
    set model [dict create title {Published digitized curves} \
        panels [list [dict create id main \
            axes [dict create \
                x [dict create label $xLabel min [expr {$minX-$xPad}] max [expr {$maxX+$xPad}]] \
                left [dict create label $yLabel min [expr {$minY-$yPad}] max [expr {$maxY+$yPad}]]] \
            series $lines]] \
        native_presentation [dict create legend [dict create placement top]]]
    set area [::GX::datasetPreviewGuiControlConfigure $host plotarea {}]
    set container [winfo parent $area]
    grid rowconfigure $container 0 -weight 1
    grid columnconfigure $container 0 -weight 1
    set path $area.nativeplot
    set options [dict create prepared_model 1 retain_presentation 1]
    # Validate native admission BEFORE replacing any accepted previous frame.
    ::GX::PlotDatasetAPIv4::widgetValidateSources $model $options
    if {[dict exists $state $host plot] && [winfo exists [dict get $state $host plot]]} {
        set path [dict get $state $host plot]
        ::GX::PlotDatasetAPIv4::widgetConfigure $path $model $options
    } else {
        ::GX::PlotDatasetAPIv4::widgetCreate $path $model $options
        pack $path -fill both -expand 1
    }
    dict set state $host [dict create dataset [dict get $context dataset_id] \
        token [dict get $context token] plot $path ids $ids labels $labels]
    ::GX::datasetPreviewGuiControlSet $host groups $labels
    ::GX::datasetPreviewGuiControlSet $host notice \
        "[llength $ids] curve/calibration groups, [dict get $groups total_rows] exact canonical rows; Plot v4 presentation only."
    return [dict create status ready groups [llength $ids] plot_api PLOT_DATASET_API_v4]
}
proc ::GX::DigitizerFamilyPreview::_selected {host} {
    variable state
    if {![dict exists $state $host]} {error {Click Load curves first}}
    set row [::GX::datasetPreviewGuiControlGet $host groups]
    set selected [dict get $row selection]
    if {[llength $selected]!=1} {error {Select exactly one curve/calibration group}}
    set index [lindex $selected 0]
    set ids [dict get $state $host ids]
    if {$index<0 || $index>=[llength $ids]} {error {Invalid selected group}}
    return [list [dict get $state $host plot] [lindex $ids $index] [lindex [dict get $state $host labels] $index]]
}
proc ::GX::DigitizerFamilyPreview::visibility {host visible} {
    lassign [_selected $host] plot series label
    ::GX::PlotDatasetAPIv4::widgetVisibility $plot main $series $visible
    ::GX::datasetPreviewGuiControlSet $host notice \
        "[expr {$visible ? {Shown} : {Hidden}}]: $label. Only presentation changed."
}
proc ::GX::DigitizerFamilyPreview::showAll {host} {
    variable state
    if {![dict exists $state $host]} {error {Click Load curves first}}
    set path [dict get $state $host plot]
    foreach id [dict get $state $host ids] {
        ::GX::PlotDatasetAPIv4::widgetVisibility $path main $id 1
    }
    ::GX::datasetPreviewGuiControlSet $host notice {All published curve/calibration groups shown.}
}
proc ::GX::DigitizerFamilyPreview::navigate {host operation} {
    variable state
    if {![dict exists $state $host]} {error {Click Load curves first}}
    set path [dict get $state $host plot]
    switch -- $operation {
        fit {::GX::PlotDatasetAPIv4::widgetView $path fit}
        zoom_in {::GX::PlotDatasetAPIv4::widgetPointer $path zoom [expr {[winfo width $path]/2}] [expr {[winfo height $path]/2}] 1.25}
        zoom_out {::GX::PlotDatasetAPIv4::widgetPointer $path zoom [expr {[winfo width $path]/2}] [expr {[winfo height $path]/2}] 0.8}
        default {error {Unknown Plot API v4 navigation}}
    }
}
proc ::GX::DigitizerFamilyPreview::guiDispose {host context reason} {
    variable tableState
    if {[dict exists $tableState $host]} {dict unset tableState $host}
    variable state
    _stopPending $host
    if {![dict exists $state $host]} return
    set path [dict get $state $host plot]
    catch {::GX::PlotDatasetAPIv4::widgetDestroy $path}
    dict unset state $host
}

# The Y2 variant retains the old Plot v4 native renderer and reads only the
# trusted, bounded canonical pages established in _groups. It never opens a CSV,
# decodes producer-private metadata or modifies scientific values.
proc ::GX::DigitizerFamilyPreview::_axisRange {low high scale} {
    if {$low>=Inf || $high<=-Inf} {return [list 0 1 linear]}
    if {$scale eq "log" && $low>0 && $high>0} {
        set delta [expr {max(log10($high)-log10($low),0.0001)}]
        set padding [expr {pow(10.0,0.03*$delta)}]
        return [list [expr {$low/$padding}] [expr {$high*$padding}] log]
    }
    set p [expr {$low==$high ? max(abs($low)*0.03,1e-9) : ($high-$low)*0.03}]
    return [list [expr {$low-$p}] [expr {$high+$p}] linear]
}

proc ::GX::DigitizerFamilyPreview::_axisPresentation {axes axisId} {
    set label [string toupper $axisId]
    set unit {}
    set scale linear
    set formats {}
    foreach m [dict get $axes measurements] {
        set spec [dict get $m $axisId]
        set name [expr {[dict exists $spec name] ? [dict get $spec name] : $label}]
        set u [dict get $spec unit]
        set s [dict get $spec scale]
        lappend formats [list $s $name $u]
    }
    if {[llength $formats]} {
        lassign [lindex $formats 0] scale label unit
        if {[llength [lsort -unique $formats]]>1} {
            # Publication may contain differently calibrated realizations;
            # show the physical rows without asserting a single axis log scale.
            set scale linear
            append label " (multiple calibrations)"
        }
    }
    if {$unit ne {}} {append label " ($unit)"}
    return [dict create label $label scale $scale]
}

proc ::GX::DigitizerFamilyPreview::_displayY2 {host groups} {
    variable state
    set context [::GX::datasetPreviewGuiContext $host]
    set m [_schema $context]
    set axes [::GX::CurveDigitizerDataset::axes [dict get $context dataset_id]]
    ::GX::modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set lines {}
    set labels {}
    set ids {}
    set index 0
    set limits [dict create x [list Inf -Inf] y1 [list Inf -Inf] y2 [list Inf -Inf]]
    set seenAxes {}
    foreach key [dict get $groups ordered] {
        set item [dict get $groups records $key]
        set logical [dict get $item y_axis_id]
        if {$logical ni {y1 y2}} {error {Unknown logical Preview axis binding}}
        lappend seenAxes $logical
        set samples [lsort -integer -index 0 [dict get $item samples]]
        set points {}
        set rows {}
        set prior {}
        foreach sample $samples {
            lassign $sample ordinal coords sourceRow
            if {$prior ne {} && $ordinal != $prior+1} {
                error {Curve has missing or repeated point_order; no invented segment}
            }
            set prior $ordinal
            lassign $coords x y
            foreach axis [list x $logical] value [list $x $y] {
                lassign [dict get $limits $axis] low high
                dict set limits $axis [list [expr {min($low,double($value))}] [expr {max($high,double($value))}]]
            }
            lappend points $coords
            lappend rows $sourceRow
        }
        if {![llength $points]} continue
        set id "trace[incr index]"
        set label [dict get $item label]
        lappend lines [dict create id $id label $label \
            kind [expr {[llength $points]==1 ? {scatter} : {line}}] \
            axis [expr {$logical eq "y2" ? "right" : "left"}] \
            points $points source_rows $rows \
            style [dict create color auto line_style solid line_width 2 marker none]]
        lappend ids $id
        lappend labels "[format %02d $index]. $label"
    }
    if {![llength $lines]} {error {No valid scientific Y2 groups to display}}
    set xInfo [_axisPresentation $axes x]
    set y1Info [_axisPresentation $axes y1]
    set y2Info [_axisPresentation $axes y2]
    set axisDescriptors [dict create]
    foreach axis {x y1 y2} target {x left right} info [list $xInfo $y1Info $y2Info] {
        lassign [dict get $limits $axis] lo hi
        lassign [_axisRange $lo $hi [dict get $info scale]] min max scale
        dict set axisDescriptors $target [dict create \
            label [dict get $info label] scale $scale min $min max $max]
    }
    set model [dict create title {Published digitized curves} \
        panels [list [dict create id main axes $axisDescriptors series $lines]] \
        native_presentation [dict create legend [dict create placement top]]]
    set area [::GX::datasetPreviewGuiControlConfigure $host plotarea {}]
    set container [winfo parent $area]
    grid rowconfigure $container 0 -weight 1
    grid columnconfigure $container 0 -weight 1
    set path $area.nativeplot
    set options [dict create prepared_model 1 retain_presentation 1]
    ::GX::PlotDatasetAPIv4::widgetValidateSources $model $options
    if {[dict exists $state $host plot] && [winfo exists [dict get $state $host plot]]} {
        set path [dict get $state $host plot]
        ::GX::PlotDatasetAPIv4::widgetConfigure $path $model $options
    } else {
        ::GX::PlotDatasetAPIv4::widgetCreate $path $model $options
        pack $path -fill both -expand 1
    }
    dict set state $host [dict create dataset [dict get $context dataset_id] \
        token [dict get $context token] plot $path ids $ids labels $labels]
    ::GX::datasetPreviewGuiControlSet $host groups $labels
    ::GX::datasetPreviewGuiControlSet $host notice \
        "[llength $ids] curves, [dict get $groups total_rows] canonical rows; logical Y1/Y2 shown using Plot v4."
    return [dict create status ready groups [llength $ids] plot_api PLOT_DATASET_API_v4]
}

# Canonical table GUI reuses only public CORE preview APIs.
source [file join [file dirname [info script]] table_preview.tcl]
