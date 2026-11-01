# SPDX-License-Identifier: GPL-3.0-or-later
# Generic transient comparison controller. Canonical access, Numeric, Plot and
# Workspace remain the scientific, mathematical, presentation and store owners.
namespace eval ::GX::ComparisonPlot {variable maximumSamples 65536}
proc ::GX::comparisonPlotApiInfo {} {
    return [dict create api_id COMPARISON_PLOT_API_v1 api_version 1 owner CORE \
        operations {comparisonPlotSourceDataset comparisonPlotSourceLibrary comparisonPlotValidate comparisonPlotPrepare comparisonPlotSpec} \
        native_client_operations {comparison_command} presentation_operations {plot_fit plot_zoom_in plot_zoom_out plot_cursor plot_clear_cursor plot_reverse_x plot_properties plot_legend plot_style plot_copy plot_export plot_save_variant plot_load_variant} modes {overlay top_bottom stacked difference ratio} \
        source_samples_max 65536 sources_max 8 library_page_samples_max 32768 \
        library_access bounded_read_only library_pin_context session_optional plot_context library_only_session_optional \
        scientific_math_owner NUMERIC_API_v1 \
        renderer PLOT_DATASET_API_v4 persistence existing_PlotSpec_Workspace_History \
        implicit_publication 0]
}
proc ::GX::_comparisonPlotGet {d key default} {expr {[dict exists $d $key]?[dict get $d $key]:$default}}
proc ::GX::_comparisonPlotHash {value} {
    if {$::GX::currentSession eq {}} {
        # Library identities are valid without a Session. Reuse the existing
        # pure byte hash; an empty Session must never become a cwd cache path.
        return [scriptRegistryHashBytes [encoding convertto utf-8 $value]]
    }
    set session [_sessionInspectionRequire $::GX::currentSession]
    return [datasetStorageSha256Text $session $value]
}
proc ::GX::_comparisonPlotMeaning {quantity representation role kind unit reference origin} {
    set temporal [expr {$kind eq {elapsed_time} || $reference eq {absolute} || $origin ne {}}]
    if {!$temporal && ![catch {unitTclCompatible $unit s} compatible] && $compatible} {set temporal 1}
    # V3's elapsed default exists even on voltage/absorbance/wavenumber. It is
    # a clock identity only for an actual temporal quantity; absolute/origin
    # declarations always remain significant and cannot be discarded.
    if {!$temporal} {set reference {};set origin {}}
    return [dict create quantity $quantity representation $representation semantic_role $role value_kind $kind time_reference $reference time_origin $origin]
}
proc ::GX::_comparisonPlotDatasetPin {dataset x y} {
    datasetPublicationV2ValidateId dataset $dataset
    foreach id [list $x $y] {datasetPublicationV2ValidateId variable $id}
    if {$x eq $y} {error {Comparison requires distinct X and Y Variables}}
    set provenance [datasetField $dataset provenance {}]
    if {[catch {dict size $provenance}]} {set provenance {}}
    set units {};set meanings {}
    foreach id [list $x $y] coordinate {x y} {
        set v [datasetVariableV3ById $dataset $id]
        if {[dict get $v dtype] ni {float64 float32 int64 int32 uint64 uint32 int16 uint16 int8 uint8} || [dict get $v rank]!=1} {error {Comparison needs real rank-one numeric Variables}}
        lappend units [_comparisonPlotGet $v unit {}]
        # Physical role, representation and quantity survive independent
        # Dataset identities. A matching display label is never authority.
        set quantity [_comparisonPlotGet $v quantity {}]
        set representation [_comparisonPlotGet $v representation {}]
        # The Spectrum producer publishes its admitted scientific quantities
        # in provenance and the exact Variable name. Bind only that declared
        # Variable; do not guess from a GUI label or apply it to another column.
        set canonical [_comparisonPlotGet $v canonical [_comparisonPlotGet $v original_header {}]]
        if {[dict exists $provenance ${coordinate}_quantity] && $canonical eq [dict get $provenance ${coordinate}_quantity]} {
            if {$quantity ne {} && $quantity ne [dict get $provenance ${coordinate}_quantity]} {error {Explicit Variable quantity conflicts with source provenance}}
            set quantity [dict get $provenance ${coordinate}_quantity]
            if {$coordinate eq {y}} {
                set declared [_comparisonPlotGet $provenance y_representation {}]
                if {$representation ne {} && $declared ne {} && $representation ne $declared} {error {Explicit Variable representation conflicts with source provenance}}
                if {$declared ne {}} {set representation $declared}
            }
        }
        set meaning [_comparisonPlotMeaning $quantity $representation [_comparisonPlotGet $v semantic_role {}] \
            [_comparisonPlotGet $v value_kind number] [_comparisonPlotGet $v unit {}] [_comparisonPlotGet $v time_reference {}] [_comparisonPlotGet $v time_origin {}]]
        lappend meanings $meaning
    }
    set count [datasetField $dataset row_count 0]
    if {![string is entier -strict $count] || $count<2 || $count>65536} {error {Comparison source requires 2..65536 actual rows; no implicit truncation}}
    set identity [curveSourceDatasetIdentity $::GX::currentSession $dataset]
    set metadata [datasetMetadataRead $::GX::currentSession $dataset]
    # Include exact protected scientific metadata, schema and coordinate frame;
    # the persisted pin contains no absolute paths or process lifetime tokens.
    set coordinate [datasetCoordinateRead $::GX::currentSession $dataset]
    set semantic [list $meanings $metadata $coordinate]
    return [dict create kind dataset dataset_id $dataset x_variable_id $x y_variable_id $y \
        sha256 [dict get $identity sha256] schema_sha256 [dict get $identity schema_identity] \
        revision [_comparisonPlotHash [datasetRevisionPortableToken $dataset]] semantic_sha256 [_comparisonPlotHash $semantic] \
        session_origin [sessionOriginRead $::GX::currentSession] sample_count $count \
        x_unit [lindex $units 0] y_unit [lindex $units 1] x_meaning [lindex $meanings 0] y_meaning [lindex $meanings 1] \
        label "$dataset / $y"]
}
proc ::GX::comparisonPlotSourceDataset {dataset x y} {return [_comparisonPlotDatasetPin $dataset $x $y]}
proc ::GX::_comparisonPlotLibraryPin {library entry} {
    set info [::GX::ScientificLibraryManagerAPIv1::getLibraryInfo $library]
    if {[_comparisonPlotGet $info mode managed] ne {managed} || [_comparisonPlotGet $info state installed] ne {installed}} {error {Comparison Library consultation requires an installed managed read-only source}}
    set entryInfo [::GX::ScientificLibraryManagerAPIv1::getLibraryEntryInfo $library $entry]
    if {![dict exists $entryInfo metadata spectrum sample_count]} {error {Library provider has no admitted bounded scientific curve representation}}
    set s [dict get $entryInfo metadata spectrum];set count [dict get $s sample_count]
    if {![string is entier -strict $count] || $count<2 || $count>65536} {error {Library comparison source requires 2..65536 samples, without truncation}}
    foreach key {x_unit y_unit x_quantity y_quantity y_representation} {if {![dict exists $s $key]} {error "Library curve lacks actual $key semantics"}}
    set identity {}
    foreach key {library_id library_type version provider_id provider_version payload_sha256 package_sha256} {dict set identity $key [_comparisonPlotGet $info $key {}]}
    if {[dict get $identity payload_sha256] eq {}} {error {Managed Library source lacks a pinned payload SHA-256}}
    return [dict create kind library_entry library_id $library entry_id $entry \
        revision [dict get $identity version] sha256 [dict get $identity payload_sha256] \
        semantic_sha256 [_comparisonPlotHash [list $identity [dict remove $entryInfo result_json retrieved_at]]] \
        sample_count $count x_unit [dict get $s x_unit] y_unit [dict get $s y_unit] \
        x_meaning [_comparisonPlotMeaning [dict get $s x_quantity] {} independent number [dict get $s x_unit] elapsed {}] \
        y_meaning [_comparisonPlotMeaning [dict get $s y_quantity] [dict get $s y_representation] measured number [dict get $s y_unit] elapsed {}] \
        label [_comparisonPlotGet $s display_name "$library / $entry"]]
}
proc ::GX::comparisonPlotSourceLibrary {library entry} {return [_comparisonPlotLibraryPin $library $entry]}
proc ::GX::_comparisonPlotCurrent {source} {
    switch [_comparisonPlotGet $source kind {}] {
        dataset {set now [_comparisonPlotDatasetPin [dict get $source dataset_id] [dict get $source x_variable_id] [dict get $source y_variable_id]]}
        library_entry {set now [_comparisonPlotLibraryPin [dict get $source library_id] [dict get $source entry_id]]}
        default {error {Unknown comparison source kind}}
    }
    if {[lsort [dict keys $now]] ne [lsort [dict keys $source]]} {error {Malformed comparison source pin}}
    dict for {key value} $now {
        set expected [dict get $source $key]
        if {$key in {x_meaning y_meaning}} {
            if {[lsort [dict keys $expected]] ne [lsort [dict keys $value]]} {error {Malformed comparison meaning}}
            dict for {field literal} $value {if {![dict exists $expected $field] || [dict get $expected $field] ne $literal} {error {Comparison scientific meaning changed; select the exact source again}}}
        } elseif {$key eq {session_origin}} {
            if {![_sessionOriginAuditExtensionMatches $expected $value]} {error {Comparison Session namespace or retained import audit changed; explicitly select the exact source again}}
        } elseif {$value ne $expected} {error {Comparison source identity, revision, SHA, provenance, namespace or scientific metadata changed; explicitly select it again}}
    }
    return $now
}
proc ::GX::comparisonPlotValidate {configuration} {
    if {[string length [encoding convertto utf-8 $configuration]]>65536} {error {Comparison configuration exceeds its 64 KiB bound}}
    foreach key [dict keys $configuration] {if {$key ni {schema sources mode normalization offset denominator_floor interpolation domain single_source_consultation}} {error "Unknown comparison field $key"}}
    if {[_comparisonPlotGet $configuration schema {}] ne {GXTXT_COMPARISON_PLOT_v1}} {error {Unsupported comparison configuration schema}}
    set mode [dict get $configuration mode]
    if {$mode ni {overlay top_bottom stacked difference ratio}} {error {Unknown comparison mode}}
    set sources [dict get $configuration sources];set n [llength $sources]
    set consultation [_comparisonPlotGet $configuration single_source_consultation 0]
    if {![string is boolean -strict $consultation]} {error {Single-source consultation requires an explicit boolean}}
    if {$n<($consultation?1:2) || $n>8 || ($mode in {difference ratio} && $n!=2)} {error {Comparison needs two to eight distinct sources, or one explicitly enabled consultation source; difference and ratio need exactly two ordered sources}}
    set seen {}
    foreach source $sources {
        _comparisonPlotCurrent $source
        set key [expr {[dict get $source kind] eq {dataset}?[list dataset [dict get $source dataset_id] [dict get $source x_variable_id] [dict get $source y_variable_id]]:[list library_entry [dict get $source library_id] [dict get $source entry_id]]}]
        if {$key in $seen} {error {Duplicate comparison source identity}}
        lappend seen $key
    }
    set normalization [_comparisonPlotGet $configuration normalization none]
    if {$normalization ni {none minmax} || ($mode in {difference ratio top_bottom} && $normalization ne {none})} {error {Select raw comparison or an explicit supported display-only normalization}}
    foreach key {offset denominator_floor} {
        set value [_comparisonPlotGet $configuration $key 0]
        if {![string is double -strict $value] || [catch {expr {abs($value)<Inf}} finite] || !$finite || ($key eq {denominator_floor} && $value<0)} {error "Invalid finite comparison $key"}
        if {$key eq {offset} && $mode ne {stacked} && $value!=0} {error {A display offset applies only in Stacked mode}}
    }
    if {[_comparisonPlotGet $configuration interpolation linear] ne {linear} || [_comparisonPlotGet $configuration domain intersection_first_source_grid] ne {intersection_first_source_grid}} {error {Comparison requires explicit linear interpolation on the intersection of the first source grid, without extrapolation}}
    set first [lindex $sources 0]
    foreach source $sources {
        if {![_comparisonPlotMeaningEqual [dict get $source x_meaning] [dict get $first x_meaning]]} {error {Comparison X quantities/roles/time origins differ}}
        foreach axis {x y} {if {[dict get $source ${axis}_unit] eq {}} {error {Comparison needs declared units, including 1 for dimensionless quantities}}}
        unitRegistryConversionPlan [dict get $source x_unit] [dict get $first x_unit]
        if {$mode ne {top_bottom} && $normalization eq {none}} {
            if {![_comparisonPlotMeaningEqual [dict get $source y_meaning] [dict get $first y_meaning]]} {error {Comparison ordinate meaning or representation differs}}
            unitRegistryConversionPlan [dict get $source y_unit] [dict get $first y_unit]
        }
        if {$mode in {difference ratio}} {unitRegistryArithmeticPlan [expr {$mode eq {difference}?{-}:{/}}] [dict get $first y_unit] [dict get $source y_unit]}
    }
    return [dict create valid 1 source_count $n mode $mode canonical_values_modified 0]
}
proc ::GX::_comparisonPlotRead {source} {
    _comparisonPlotCurrent $source
    set xs {};set ys {}
    if {[dict get $source kind] eq {dataset}} {
        set x [dict get $source x_variable_id];set y [dict get $source y_variable_id]
        set token [curveSourceOpen $::GX::currentSession [dict create dataset_id [dict get $source dataset_id] x_variable_id $x y_variable_id $y]]
        try {
            set stream [curveSourceOpenStream $token [list $x $y] 4096 {numeric_transport values}]
            try {
                while {1} {
                    set chunk [tableStreamNext $stream]
                    # Numeric/coordinate preparation uses binary64. Do not
                    # silently coerce authoritative wide integer observations
                    # before subtraction/division or grid admission.
                    foreach id [list $x $y] {
                        if {[dict get [datasetVariableV3ById [dict get $source dataset_id] $id] dtype] in {int64 uint64}} {
                            foreach value [dict get $chunk values $id] {
                                if {![string is entier -strict $value] || $value< -9007199254740991 || $value>9007199254740991} {error {Comparison refuses 64-bit integer samples outside the exact binary64 integer range; use an explicit scientifically reviewed conversion}}
                            }
                        }
                    }
                    lappend xs {*}[dict get $chunk values $x];lappend ys {*}[dict get $chunk values $y]
                    if {[llength $xs]>65536} {error {Comparison source exceeded its admitted bound}}
                    if {[dict get $chunk eof]} break
                }
            } finally {curveSourceCloseStream $token $stream}
        } finally {curveSourceClose $token}
    } else {
        set count [dict get $source sample_count]
        for {set start 0} {$start<$count} {incr start 32768} {
            set take [expr {min(32768,$count-$start)}]
            set options [dict create provider_json [format {{"start":%d,"count":%d}} $start $take]]
            set result [::GX::ScientificLibraryManagerAPIv1::readLibraryEntry [dict get $source library_id] [dict get $source entry_id] $options]
            set payload [dict get $result payload]
            if {[llength [dict get $payload x]]!=$take || [llength [dict get $payload y]]!=$take} {error {Library provider did not honor its exact admitted sample window}}
            lappend xs {*}[dict get $payload x];lappend ys {*}[dict get $payload y]
        }
    }
    _comparisonPlotCurrent $source
    if {[llength $xs]!=[dict get $source sample_count] || [llength $ys]!=[llength $xs]} {error {Source sample count changed during comparison read}}
    return [dict create x $xs y $ys]
}
proc ::GX::_comparisonPlotConvert {values from to} {
    if {$from eq {} || $to eq {}} {error {Missing physical units cannot imply a unit conversion; declare dimensionless quantities explicitly as 1}}
    if {$from eq $to} {return $values}
    unitRegistryConversionPlan $from $to
    set output {}
    # Respect the existing conversion owner's 4096-value bound. Nonfinite Y
    # samples remain explicit gaps, without being passed to its finite grammar.
    for {set start 0} {$start<[llength $values]} {incr start 4096} {
        set page [lrange $values $start [expr {$start+4095}]];set finite {};set positions {};set index 0
        foreach value $page {
            if {[string is double -strict $value] && ![catch {expr {abs($value)<Inf}} yes] && $yes} {lappend finite $value;lappend positions $index}
            incr index
        }
        set converted [unitRegistryConvertValues $from $to $finite]
        foreach index $positions value $converted {lset page $index $value}
        lappend output {*}$page
    }
    return $output
}
proc ::GX::_comparisonPlotMeaningEqual {a b} {
    if {[lsort [dict keys $a]] ne [lsort [dict keys $b]]} {return 0}
    dict for {key value} $a {if {$value ne [dict get $b $key]} {return 0}}
    return 1
}
proc ::GX::_comparisonPlotCoordinate {source coordinate values target} {
    if {[dict get $source kind] ne {dataset}} {return [_comparisonPlotConvert $values [dict get $source ${coordinate}_unit] $target]}
    if {$target eq {}} {error {Comparison needs explicit coordinate units, including 1 for dimensionless quantities}}
    set id [dict get $source ${coordinate}_variable_id]
    set context [datasetCoordinateRead $::GX::currentSession [dict get $source dataset_id]]
    set declaration [dict get $context variables $id source]
    set output {}
    for {set start 0} {$start<[llength $values]} {incr start 4096} {
        set page [lrange $values $start [expr {$start+4095}]];set finite {};set positions {};set index 0
        foreach value $page {
            if {[string is double -strict $value] && ![catch {expr {abs($value)<Inf}} yes] && $yes} {lappend finite $value;lappend positions $index}
            incr index
        }
        if {[_comparisonPlotGet $declaration value_kind {}] eq {elapsed_time} && [_comparisonPlotGet $declaration value_format {}] eq {hms}} {set finite [elapsedTimeConvert $finite [dict get $declaration unit]]}
        set converted [dict get [datasetCoordinateSnapshotValues $context $id $finite [dict create mode canonical unit $target]] values]
        foreach index $positions value $converted {lset page $index $value}
        lappend output {*}$page
    }
    return $output
}
proc ::GX::_comparisonPlotContextToken {configuration} {
    if {$::GX::currentSession ne {}} {return [interactiveDocumentSessionToken]}
    foreach source [dict get $configuration sources] {
        if {[dict get $source kind] ne {library_entry}} {error {Canonical Dataset comparison requires an open Session}}
    }
    # Reuse the existing process-local context epoch, including no-Session
    # lifetimes. No fake Session/store or filesystem allocation is involved.
    _interactiveDocumentSessionChanged
    return "library-consultation#[pid]-$::GX::DocumentSessionScope::epoch"
}
proc ::GX::comparisonPlotPrepare {configuration} {
    comparisonPlotValidate $configuration
    set lifetime [_comparisonPlotContextToken $configuration]
    set sources [dict get $configuration sources];set first [lindex $sources 0]
    set mode [dict get $configuration mode];set norm [_comparisonPlotGet $configuration normalization none]
    set xu [dict get $first x_unit];set yu [dict get $first y_unit]
    set values {};set index 0
    foreach source $sources {
        if {![_comparisonPlotMeaningEqual [dict get $source x_meaning] [dict get $first x_meaning]]} {error {Comparison X quantities/roles/time origins differ; materialize an authorized alignment first}}
        if {$mode ne {top_bottom} && $norm eq {none} && ![_comparisonPlotMeaningEqual [dict get $source y_meaning] [dict get $first y_meaning]]} {error {Comparison ordinate meaning or representation differs; no implicit scientific equivalence}}
        if {$mode in {difference ratio}} {
            if {$yu eq {} || [dict get $source y_unit] eq {}} {error {Derived comparison needs explicit physical ordinate units}}
            unitRegistryArithmeticPlan [expr {$mode eq {difference}?{-}:{/}}] $yu [dict get $source y_unit]
        }
        set data [_comparisonPlotRead $source]
        dict set data x [_comparisonPlotCoordinate $source x [dict get $data x] $xu]
        set yTarget [expr {$mode ne {top_bottom} && $norm eq {none}?$yu:[dict get $source y_unit]}]
        dict set data y [_comparisonPlotCoordinate $source y [dict get $data y] $yTarget]
        lappend values $data
    }
    modulePublicApiActivate math.numeric NUMERIC_API_v1
    set results {}
    if {$mode in {difference ratio}} {
        lassign $values a b
        lappend results [::GX::NumericAPIv1::comparisonCurves $mode [dict get $a x] [dict get $a y] [dict get $b x] [dict get $b y] [dict create denominator_floor [_comparisonPlotGet $configuration denominator_floor 0]]]
    } else {
        foreach data $values {
            set offset [expr {$mode eq {stacked}?$index*[_comparisonPlotGet $configuration offset 0]:0}]
            lappend results [::GX::NumericAPIv1::comparisonCurves $mode [dict get $data x] [dict get $data y] {} {} [dict create normalization $norm offset $offset]]
            incr index
        }
    }
    # Recheck every pin after numerical work and before exposing a replacement.
    comparisonPlotValidate $configuration
    if {[_comparisonPlotContextToken $configuration] ne $lifetime} {error {Comparison Session changed during preparation}}
    set panels {};set series {};set index 0;set invalid 0
    foreach result $results {
        set source [lindex $sources $index];set label [dict get $source label]
        set unit [expr {$mode eq {ratio}?{1}:($norm eq {minmax}?{1}:($mode eq {top_bottom}?[dict get $source y_unit]:$yu))}]
        # Keep the complete source labels in the ordered source/receipt model.
        # A derived legend names the same zero-based rows as the Sources page;
        # repeating two full names and method prose can overflow the viewport.
        if {$mode in {difference ratio}} {set label "Source 0 [expr {$mode eq {difference}?{−}:{÷}}] Source 1 (display)"}
        set points {};foreach x [dict get $result x] y [dict get $result values] {lappend points [list $x $y]}
        set trace [dict create id comparison_$index label $label kind line axis left points $points point_identity_kind derived_statistic row_count 0 \
            style [dict create color auto line_width 1.5 marker none line_style solid]]
        incr invalid [dict get $result invalid_count]
        set axes [dict create x [dict create label "X ($xu)" display_unit $xu] left [dict create label "[expr {$norm eq {minmax}?{Display shape}:($mode eq {ratio}?{Raw ratio}:{Y})}] ($unit)" display_unit $unit]]
        if {$mode eq {top_bottom}} {lappend panels [dict create id source_$index title $label axes $axes series [list $trace]]} else {lappend series $trace}
        incr index
    }
    if {$mode ne {top_bottom}} {
        set title "[string totitle $mode] — source order is explicit"
        if {$norm eq {minmax}} {set title "[string totitle $mode] — min-max display; canonical unchanged"}
        if {$mode eq {stacked}} {
            set title "Stacked — [expr {$norm eq {minmax}?{min-max, }:{}}]display step [format %.12g [_comparisonPlotGet $configuration offset 0]]; first offset 0"
        }
        lappend panels [dict create id comparison title $title axes $axes series $series]
    }
    set derived [expr {$mode in {difference ratio}}]
    set receipt [dict create schema GXTXT_COMPARISON_RECEIPT_v1 configuration $configuration mode $mode sources $sources \
        normalization $norm display_offset_step [_comparisonPlotGet $configuration offset 0] invalid_samples $invalid \
        interpolation [expr {$derived?{linear}:{none}}] common_domain [expr {$derived?{intersection_first_source_grid}:{independent_full_source_domains}}] extrapolation 0 \
        numeric_authority NUMERIC_API_v1 renderer PLOT_DATASET_API_v4 scientific_identification 0 canonical_values_modified 0]
    set model [dict create title "Comparison: $mode" panels $panels generic_comparison $configuration \
        shared_x_interaction [expr {$mode eq {top_bottom}}] comparison_receipt $receipt]
    return [dict create model $model receipt $receipt]
}
proc ::GX::_comparisonPlotPresentation {spec} {
    set styles {};set config [_comparisonPlotGet [_comparisonPlotGet $spec native_presentation {}] plot_config {}]
    set n [expr {[dict get $spec comparison mode] in {difference ratio}?1:[llength [dict get $spec comparison sources]]}]
    dict for {key value} $config {
        if {![string match comparison_* $key]} continue
        if {$key in {comparison_cursor_version comparison_cursor_panel comparison_cursor_x comparison_cursor_y}} continue
        if {$key eq {comparison_style_version}} {if {$value ne {1}} {error {Unsupported Comparison presentation version}};continue}
        if {![regexp {^comparison_style:comparison_([0-7]):(color|line_width|line_style|marker|marker_size|opacity)$} $key -> index field] || $index>=$n} {error {Unknown or unavailable Comparison display style}}
        if {[_comparisonPlotGet $config comparison_style_version {}] ne {1}} {error {Comparison styles require their explicit version}}
        if {$field in {line_width marker_size opacity}} {
            if {![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite} {error {Comparison style numbers must be finite}}
            if {$field eq {opacity}} {if {$value<0 || $value>1} {error {Opacity must be in 0..1}}} elseif {$value<=0 || $value>50} {error {Comparison line/marker size must be in 0..50}}
        }
        dict set styles comparison_$index $field $value
    }
    dict for {id style} $styles {::GX::PlotDatasetAPIv2::_validateStyle $style "Comparison $id"}
    set cursorKeys {comparison_cursor_version comparison_cursor_panel comparison_cursor_x comparison_cursor_y}
    set count 0;foreach key $cursorKeys {if {[dict exists $config $key]} {incr count}}
    if {$count} {
        if {$count!=4 || [dict get $config comparison_cursor_version] ne {1}} {error {Comparison display cursor requires its complete version1 declaration}}
        set panelIds {};foreach panel [dict get $spec panels] {lappend panelIds [dict get $panel id]}
        if {[dict get $config comparison_cursor_panel] ni $panelIds} {error {Comparison cursor panel is unavailable}}
        foreach key {comparison_cursor_x comparison_cursor_y} {
            set value [dict get $config $key]
            if {![string is double -strict $value] || [catch {expr {abs(double($value))<Inf}} finite] || !$finite} {error {Comparison cursor coordinates must be finite}}
        }
    }
    return $styles
}
proc ::GX::comparisonPlotSpec {configuration} {
    comparisonPlotValidate $configuration
    modulePublicApiActivate plot.dataset PLOT_DATASET_API_v4
    set spec [::GX::PlotDatasetAPIv4::newSpec -title {Scientific comparison}]
    set panels {};set sources [dict get $configuration sources]
    if {[dict get $configuration mode] eq {top_bottom}} {
        set index 0
        foreach source $sources {
            lappend panels [dict create id source_$index title [dict get $source label] axes {} series {} annotations {}]
            incr index
        }
    } else {set panels [list [dict create id comparison axes {} series {} annotations {}]]}
    dict set spec panels $panels
    dict set spec multi_panel [expr {[dict get $configuration mode] eq {top_bottom}}]
    dict set spec comparison $configuration
    # Use the existing shared Graph presentation owner. New comparisons should
    # Keep full source captions outside the scientific panel. A single column
    # avoids the fixed-width right strip and competing long columns. Reserve
    # footer space per displayed series using the existing Graph layout owner;
    # saved specs and explicit user legend choices retain their own settings.
    dict set spec native_presentation schema GXTXT_NATIVE_GRAPH_PRESENTATION_v1
    dict set spec native_presentation legend [dict create placement below layout stacked columns 1]
    set legendRows [expr {[dict get $configuration mode] in {top_bottom difference ratio}?1:[llength $sources]}]
    dict set spec native_presentation layout layout_margin_bottom [expr {8+6*($legendRows-1)}]
    return $spec
}
