# SPDX-License-Identifier: GPL-3.0-or-later
# Derived profile stored only in existing reserved Dataset Metadata API v1.
namespace eval ::GX {variable datasetScientificProfileCache {};variable datasetScientificProfileBuilding 0}
proc ::GX::datasetScientificProfileApiInfo {} {
    return {api_id DATASET_SCIENTIFIC_PROFILE_API_v1 api_version 1 profile_revision 2 operations {read discover build} row_budget 100000 value_budget 1024 value_bytes_max 1024 profile_value_bytes_max 2097152 scanned_variables_max 32 persistence dataset_metadata scientific_mutation 0}
}
proc ::GX::_datasetScientificProfileIdentity {id} {
    # Normalize the existing v3 projection before reading its version fingerprint.
    datasetVariableSchemaV3 $id
    return [dict create content_identity [dict create dataset_id $id canonical_sha256 [datasetField $id canonical_sha256 {}] sha256 [datasetField $id sha256 {}]] scientific_schema_identity [graphSeriesPreparationIdentity $id]]
}
proc ::GX::_datasetScientificProfileReadRegistered {session id} {
    set identity [_datasetScientificProfileIdentity $id]
    set result [dict merge [datasetScientificProfileApiInfo] $identity [dict create dataset_id $id status absent variables {} persistent 0]]
    set metadata [_datasetMetadataReadRegistered $session $id]
    if {![dict exists $metadata _gxtxt.framework.scientific_profile]} {return $result}
    if {[catch {
        set encoded [dict get $metadata _gxtxt.framework.scientific_profile]
        if {[string length $encoded]>12582912} {error {Profile exceeds bounded storage}}
        set profile [encoding convertfrom utf-8 [binary decode base64 $encoded]]
        if {[dict get $profile api_id] ne "DATASET_SCIENTIFIC_PROFILE_API_v1" || [dict get $profile api_version]!=1} {error {Unsupported profile}}
        if {![dict exists $profile profile_revision] || [dict get $profile profile_revision]!=2} {error {Older categorical inventory revision; rebuild through CORE.}}
        foreach key {content_identity scientific_schema_identity} {if {[dict get $profile $key] ne [dict get $identity $key]} {error {Stale profile}}}
        if {[dict exists $profile summaries]} {
            if {[dict get $profile summary_revision]!=1 || [dict size [dict get $profile summaries]]>32 || [zlib crc32 [encoding convertto utf-8 [dict get $profile summaries]]] ne [dict get $profile summary_crc32]} {error {Invalid descriptive summary integrity/version}}
            dict for {vid s} [dict get $profile summaries] {
                datasetVariableV3ById $id $vid
                if {[dict get $s variable_id] ne $vid || [dict get $s status] ni {exact_coverage partial unsupported} || ![string is entier -strict [dict get $s observed]] || [dict get $s observed]<0 || [llength [dict get $s values]]>1024 || [string bytelength $s]>262144 || [dict get $s distinct_complete] ni {0 1}} {error {Invalid descriptive summary bounds}}
            }
        }
        # Invalid profiles are never used as an inventory.
        foreach d [dict get $profile variables] {
            datasetVariableV3ById $id [dict get $d variable_id]
            if {[llength [dict get $d values]]>1024 || [dict get $d complete] ni {0 1}} {error {Invalid profile bounds}}
        }
    } reason]} {return [dict merge $result [dict create status stale reason $reason]]}
    return [dict merge $profile [dict create status current persistent 1]]
}
proc ::GX::datasetScientificProfileRead {session id} {
    lassign [_datasetMetadataRequireDataset $session $id] session id
    return [_datasetScientificProfileReadRegistered $session $id]
}
proc ::GX::datasetScientificProfileDiscover {session id {rowBudget 100000} {valueBudget 1024}} {
    variable datasetScientificProfileCache
    lassign [_datasetMetadataRequireDataset $session $id] session id
    if {$session ne [sessionInspectionCurrentSession]} {error {Open the profile's Session first.}}
    if {![string is integer -strict $rowBudget] || $rowBudget<1 || $rowBudget>100000 || ![string is integer -strict $valueBudget] || $valueBudget<1 || $valueBudget>1024} {error {Profile budgets must be 1..100000 rows and 1..1024 values.}}
    set identity [_datasetScientificProfileIdentity $id]
    set key [list [interactiveDocumentSessionToken] $session $id $identity $rowBudget $valueBudget]
    if {[dict exists $datasetScientificProfileCache $key]} {return [dict get $datasetScientificProfileCache $key]}
    # Keep only this Session's bounded latest per-Dataset identities, at most 32.
    dict for {old value} $datasetScientificProfileCache {
        if {[lindex $old 0] ne [lindex $key 0] || [lindex $old 2] eq $id} {dict unset datasetScientificProfileCache $old}
    }
    set profile [dict merge [datasetScientificProfileApiInfo] $identity [dict create dataset_id $id status discovered persistent 0 row_budget $rowBudget value_budget $valueBudget variables [_datasetScientificProfileScan $id $rowBudget $valueBudget]]]
    if {[_datasetScientificProfileIdentity $id] ne $identity} {error {Dataset changed while discovering its profile.}}
    if {[dict size $datasetScientificProfileCache]>=32} {dict unset datasetScientificProfileCache [lindex [dict keys $datasetScientificProfileCache] 0]}
    dict set datasetScientificProfileCache $key $profile
    return $profile
}
proc ::GX::_datasetScientificProfileRefresh {session id} {
    variable datasetScientificProfileBuilding
    if {$datasetScientificProfileBuilding} return
    set datasetScientificProfileBuilding 1
    try {
        set profile [datasetScientificProfileDiscover $session $id]
        set encoded [binary encode base64 -maxlen 0 [encoding convertto utf-8 [dict remove $profile status persistent]]]
        _datasetFrameworkMetadataUpdate $session $id [dict create scientific_profile $encoded]
    } finally {set datasetScientificProfileBuilding 0}
    return [datasetScientificProfileRead $session $id]
}
proc ::GX::datasetScientificProfileBuild {session id} {
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Profile persistence belongs to CORE publication or an explicit user operation.}}
    lassign [_datasetMetadataRequireDataset $session $id] session id
    if {$session ne [sessionInspectionCurrentSession]} {error {Open the profile's Session first.}}
    set profile [datasetScientificProfileRead $session $id]
    if {[dict get $profile status] eq "current"} {return $profile}
    return [_datasetScientificProfileRefresh $session $id]
}
proc ::GX::_datasetScientificProfileCommitCandidates {session registered ids} {
    variable datasetScientificProfileBuilding
    if {$datasetScientificProfileBuilding} {return {}}
    set result {}
    foreach id $ids {
        set changed [expr {![dict exists $registered dataset.$id.id]}]
        foreach name [array names ::GX::datasetRegistry "$id,*"] {
            set field [string range $name [expr {[string length $id]+1}] end]
            if {$field ni {canonical_sha256 sha256 variable_schema_api_version row_count storage_provider format path} && ![string match var* $field]} continue
            if {![dict exists $registered dataset.$id.$field] || [dict get $registered dataset.$id.$field] ne $::GX::datasetRegistry($name)} {set changed 1;break}
        }
        # A profile with no dimensions is unnecessary, but stale formerly
        # categorical schemas get an empty replacement to invalidate old choices.
        if {$changed && ([_datasetScientificProfileDimensions $id] ne {} || [dict exists [_datasetMetadataReadRegistered $session $id] _gxtxt.framework.scientific_profile])} {lappend result $id}
    }
    return $result
}

# Additive descriptive extension. Existing categorical consumers and revision-2
# inventories retain their public shape and semantics. One persistence authority.
namespace eval ::GX::ScientificProfile {variable jobs {}; variable serial 0}
proc ::GX::datasetProfileApiInfo {} {
    return [dict merge [datasetScientificProfileApiInfo] {extension_revision 1 operations {read discover build describe variable distinct request progress cancel release} measured_rank 1 chunk_elements 2048 max_variables 32 max_rows 100000000 max_jobs 4 moments_method welford_population_float64}]
}
proc ::GX::datasetProfileDescribe {session id} {
    set p [datasetScientificProfileRead $session $id]
    dict set p structure [datasetVariableSchemaV3 $id]
    dict set p measured_status [expr {[dict exists $p summaries] ? "available" : "absent"}]
    return $p
}
proc ::GX::datasetProfileVariable {session id vid} {
    set p [datasetProfileDescribe $session $id]
    set v [datasetVariableV3ById $id $vid]
    set r [dict create variable_id $vid structure $v status absent]
    if {[dict exists $p summaries $vid]} {set r [dict merge $r [dict get $p summaries $vid]]}
    if {[dict get $v axis_kind] eq "uniform"} {
        set n [dict get $v axis_count];set origin [dict get $v axis_origin];set step [dict get $v axis_step]
        if {[string is entier -strict $n] && $n>=0 && [string is double -strict $origin] && [string is double -strict $step] && ![catch {
            set last [expr {$n ? double($origin)+($n-1)*double($step) : $origin}]
            if {abs($last)==Inf || abs($origin)==Inf || abs($step)==Inf} {error {Nonfinite uniform axis}}
            set range [expr {$n?[list [expr {min($origin,$last)}] [expr {max($origin,$last)}]]:{}}]
        }]} {dict set r declared_axis [dict create status declared method schema_uniform_endpoint_arithmetic count $n range $range order [expr {$step==0?"constant":$step>0?"increasing":"decreasing"}] numeric_rounding float64]}
    }
    return $r
}
proc ::GX::datasetProfileDistinct {session id vid {options {}}} {
    foreach k [dict keys $options] {if {$k ni {start limit require_complete}} {error "Unknown distinct option $k"}}
    set start [datasetPublicationV2DictDefault $options start 0]
    set limit [datasetPublicationV2DictDefault $options limit 100]
    if {![string is integer -strict $start] || $start<0 || ![string is integer -strict $limit] || $limit<1 || $limit>1024} {error {Invalid distinct page bounds}}
    set p [datasetScientificProfileRead $session $id];set v [datasetVariableV3ById $id $vid]
    set values {};set complete 0;set coverage 0
    if {[dict exists $p summaries $vid]} {
        set s [dict get $p summaries $vid];set values [dict get $s values];set complete [dict get $s distinct_complete];set coverage [dict get $s observed]
    } else {
        foreach d [dict get $p variables] {if {[dict get $d variable_id] eq $vid} {set values [dict get $d values];set complete [dict get $d complete];set coverage [dict get $d scanned_rows];break}}
    }
    # Descriptive coverage and categorical inventory are independent properties.
    # A bounded numeric request must not hide a current complete inventory.
    if {!$complete} {
        foreach d [dict get $p variables] {
            if {[dict get $d variable_id] eq $vid && [dict get $d complete]} {
                set values [dict get $d values];set complete 1;set coverage [dict get $d scanned_rows];break
            }
        }
    }
    if {[datasetPublicationV2DictDefault $options require_complete 0] && !$complete} {error {Complete distinct inventory unavailable; request explicit profiling}}
    set page [lrange $values $start [expr {$start+$limit-1}]]
    return [dict create variable_id $vid dtype [dict get $v dtype] values $page returned [llength $page] next [expr {$start+[llength $page]<[llength $values]?$start+[llength $page]:-1}] complete $complete cardinality [expr {$complete?[llength $values]:"unknown"}] retained_count [llength $values] observed $coverage status [dict get $p status] equality_policy original_typed_lexical_values]
}
proc ::GX::_profileAccumulator {v} {
    return [dict create variable_id [dict get $v variable_id] dtype [dict get $v dtype] observed 0 finite 0 missing 0 nan 0 positive_infinity 0 negative_infinity 0 invalid 0 min {} max {} mean 0.0 m2 0.0 moments_available 1 previous {} ascending 1 descending 1 strict 1 unique {} distinct_complete 1 retained_bytes 0]
}
proc ::GX::_profileAccumulate {s values valueBudget} {
    set numeric [expr {[dict get $s dtype] ni {string bool}}]
    foreach value $values {
        dict incr s observed
        # Original values are filter payloads, including empty text and int64.
        if {![dict exists $s unique $value]} {
            if {[dict size [dict get $s unique]] >= $valueBudget || [string bytelength $value]>1024 || [dict get $s retained_bytes]+[string bytelength $value]>65536} {dict set s distinct_complete 0} else {dict set s unique $value 1;dict incr s retained_bytes [string bytelength $value]}
        }
        if {!$numeric} continue
        if {$value eq {}} {dict incr s missing;continue}
        if {[regexp -nocase {^[+-]?nan$} $value]} {dict incr s nan;continue}
        if {[regexp -nocase {^\+?inf(?:inity)?$} $value]} {dict incr s positive_infinity;continue}
        if {[regexp -nocase {^-inf(?:inity)?$} $value]} {dict incr s negative_infinity;continue}
        set integer [string match *int* [dict get $s dtype]]
        if {!$integer && [string is double -strict $value] && ![catch {expr {double($value)}} parsed] && abs($parsed)==Inf} {
            dict incr s [expr {$parsed>0?"positive_infinity":"negative_infinity"}];continue
        }
        if {($integer && ![string is entier -strict $value]) || (!$integer && ![string is double -strict $value])} {dict incr s invalid;continue}
        # Tcl bignum comparison preserves integer extrema beyond 2^53.
        if {[dict get $s finite]==0} {dict set s min $value;dict set s max $value} else {
            if {$value<[dict get $s min]} {dict set s min $value}
            if {$value>[dict get $s max]} {dict set s max $value}
            set prev [dict get $s previous]
            if {$value<$prev} {dict set s ascending 0}
            if {$value>$prev} {dict set s descending 0}
            if {$value==$prev} {dict set s strict 0}
        }
        dict set s previous $value;dict incr s finite
        if {[dict get $s moments_available]} {
            if {[catch {
                set delta [expr {double($value)-[dict get $s mean]}]
                set mean [expr {[dict get $s mean]+$delta/[dict get $s finite]}]
                set m2 [expr {[dict get $s m2]+$delta*(double($value)-$mean)}]
                if {abs($mean)==Inf || abs($m2)==Inf} {error {Floating moments overflow}}
                dict set s mean $mean;dict set s m2 $m2
            }]} {dict set s moments_available 0}
        }
    }
    return $s
}
proc ::GX::_profileFinish {s total} {
    set full [expr {[dict get $s observed]==$total}]
    dict set s values [dict keys [dict get $s unique]];dict unset s unique
    dict set s distinct_complete [expr {$full&&[dict get $s distinct_complete]}]
    dict set s complete $full;dict set s status [expr {$full?"exact_coverage":"partial"}]
    dict set s total $total
    dict set s extrema_status [expr {$full?"exact":"sample"}]
    set n [dict get $s finite]
    set gaps [expr {[dict get $s missing]+[dict get $s nan]+[dict get $s positive_infinity]+[dict get $s negative_infinity]+[dict get $s invalid]}]
    set order unknown
    if {$full&&$n>0&&!$gaps} {
        set a [dict get $s ascending];set d [dict get $s descending]
        set order [expr {$a&&$d?"constant":$a?"increasing":$d?"decreasing":"nonmonotone"}]
    }
    dict set s monotonicity $order
    dict set s variance_population [expr {$n&&[dict get $s moments_available]?[dict get $s m2]/$n:"unavailable"}]
    dict set s moments_exact 0
    dict set s missing_policy {empty numeric is missing; empty string is an exact text value; NaN and infinities are separate; provider null masks unavailable}
    return [dict remove $s previous ascending descending m2]
}
proc ::GX::datasetProfileRequest {session id {options {}}} {
    variable ::GX::ScientificProfile::jobs;variable ::GX::ScientificProfile::serial
    if {$::GX::DatasetPrivate::activeContext ne {}} {error {Explicit profile persistence requires a user/CORE operation}}
    lassign [_datasetMetadataRequireDataset $session $id] session id
    if {$session ne [sessionInspectionCurrentSession]} {error {Open the profile Session first}}
    foreach k [dict keys $options] {if {$k ni {variable_ids row_budget value_budget}} {error "Unknown profile request option $k"}}
    set rows [datasetPublicationV2DictDefault $options row_budget 1000000];set values [datasetPublicationV2DictDefault $options value_budget 1024]
    if {![string is integer -strict $rows] || $rows<1 || $rows>100000000 || ![string is integer -strict $values] || $values<1 || $values>1024} {error {Invalid profile budgets}}
    set ids [datasetPublicationV2DictDefault $options variable_ids [lmap v [datasetVariableSchemaV3 $id] {dict get $v variable_id}]]
    if {[llength $ids]>32 || ![llength $ids] || [llength [lsort -unique $ids]]!=[llength $ids]} {error {Choose 1..32 unique variables}}
    set active 0
    dict for {t j} $jobs {if {[dict get $j status] eq "building"} {incr active;if {[dict get $j session] eq $session&&[dict get $j dataset_id] eq $id} {error {A profile build for this Dataset is already running}}}}
    if {$active>=4 || [dict size $jobs]>=32} {error {Profile job budget reached; release completed jobs}}
    set queue {};set summaries {}
    foreach vid $ids {
        set v [datasetVariableV3ById $id $vid]
        set shape [datasetSchemaV3SplitIds [dict get $v shape]]
        if {([dict get $v axis_kind] eq "uniform" && [datasetStorageVariableLocator $id $vid] eq {}) || [dict get $v rank]!=1 || [llength $shape]!=1 || ![string is entier -strict [lindex $shape 0]]} {
            dict set summaries $vid [dict create variable_id $vid status unsupported reason implicit_axis_or_rank_or_shape values {} distinct_complete 0 observed 0]
        } else {lappend queue [list $vid [lindex $shape 0] [_profileAccumulator $v]]}
    }
    set token "scientific-profile#[pid]-[incr serial]"
    dict set jobs $token [dict create status building session $session dataset_id $id identity [_datasetScientificProfileIdentity $id] session_token [interactiveDocumentSessionToken] queue $queue summaries $summaries row_budget $rows remaining $rows value_budget $values observed 0 access {} started_ms [clock milliseconds]]
    dict set jobs $token timer [after 0 [list ::GX::_profileStep $token]]
    return $token
}
proc ::GX::_profileStep {token} {
    variable ::GX::ScientificProfile::jobs
    if {![dict exists $jobs $token] || [dict get $jobs $token status] ne "building"} return
    set j [dict get $jobs $token]
    try {
        if {[dict get $j session_token] ne [interactiveDocumentSessionToken] || [_datasetScientificProfileIdentity [dict get $j dataset_id]] ne [dict get $j identity]} {error {Profile source identity or Session lifetime changed}}
        loadDatasetRegistry [dict get $j session]
        if {[_datasetScientificProfileIdentity [dict get $j dataset_id]] ne [dict get $j identity]} {error {Profile source registry changed}}
        set q [dict get $j queue]
        if {[llength $q]} {
            lassign [lindex $q 0] vid total s
            set start [dict get $s observed]
            set count [expr {min(2048,$total-$start,[dict get $j remaining])}]
            if {$count>0} {
                if {[dict get $j access] eq {}} {dict set j access [datasetAccessOpen [dict get $j session] [dict get $j dataset_id]]}
                # Existing CSV provider retains its sequential file position;
                # HDF5 uses direct bounded ranges, including independent axes.
                set data [datasetAccessReadRange [dict get $j access] [list $vid] $start $count]
                set chunk [dict get $data $vid values]
                if {[llength $chunk]!=$count} {error {Provider returned incomplete variable range}}
                set s [_profileAccumulate $s $chunk [dict get $j value_budget]]
                dict incr j observed $count;dict incr j remaining -$count
            }
            if {[dict get $s observed]>=$total || [dict get $j remaining]<=0} {
                dict set j summaries $vid [_profileFinish $s $total];set q [lrange $q 1 end]
            } else {set q [lreplace $q 0 0 [list $vid $total $s]]}
            dict set j queue $q
        }
        if {$q eq {}} {
            set p [datasetScientificProfileRead [dict get $j session] [dict get $j dataset_id]]
            if {[dict get $p status] ne "current"} {set p [dict merge [datasetScientificProfileApiInfo] [dict get $j identity] [dict create dataset_id [dict get $j dataset_id] variables {}]]}
            dict set p summary_revision 1
            dict for {vid s} [dict get $j summaries] {dict set p summaries $vid $s}
            set dims [_datasetScientificProfileDimensions [dict get $j dataset_id]]
            set old {};foreach d [dict get $p variables] {dict set old [dict get $d variable_id] $d}
            set ds {}
            foreach d $dims {
                set vid [dict get $d variable_id]
                if {[dict exists $old $vid] && [dict get $old $vid complete]} {
                    # p was identity-validated above; never retain a stale source's
                    # inventory, and never downgrade this source's complete one.
                    set d [dict get $old $vid]
                } elseif {[dict exists $p summaries $vid]} {
                    set s [dict get $p summaries $vid];dict set d values [dict get $s values];dict set d complete [dict get $s distinct_complete];dict set d scanned_rows [dict get $s observed];dict set d truncated [expr {![dict get $d complete]}]
                } elseif {[dict exists $old $vid]} {set d [dict get $old $vid]} else {dict set d complete 0;dict set d scanned_rows 0;dict set d truncated 1}
                lappend ds $d
            }
            dict set p variables $ds
            dict set p summary_crc32 [zlib crc32 [encoding convertto utf-8 [dict get $p summaries]]]
            _datasetFrameworkMetadataUpdate [dict get $j session] [dict get $j dataset_id] [dict create scientific_profile [binary encode base64 -maxlen 0 [encoding convertto utf-8 [dict remove $p status persistent structure measured_status]]]]
            dict set j status complete
        }
    } on error {message options} {dict set j status failed;dict set j reason $message}
    if {[dict get $j status] ne "building"} {
        if {[dict get $j access] ne {}} {catch {datasetAccessClose [dict get $j access]};dict set j access {}}
        dict set j elapsed_ms [expr {[clock milliseconds]-[dict get $j started_ms]}]
        dict unset j queue
    } else {dict set j timer [after 1 [list ::GX::_profileStep $token]]}
    dict set jobs $token $j
}
proc ::GX::datasetProfileProgress {token} {
    if {![dict exists $::GX::ScientificProfile::jobs $token]} {error {Unknown profile request}}
    return [dict remove [dict get $::GX::ScientificProfile::jobs $token] access queue timer identity]
}
proc ::GX::datasetProfileCancel {token} {
    variable ::GX::ScientificProfile::jobs
    if {![dict exists $jobs $token]} {error {Unknown profile request}}
    set j [dict get $jobs $token]
    if {[dict get $j status] eq "building"} {
        after cancel [dict get $j timer]
        if {[dict get $j access] ne {}} {catch {datasetAccessClose [dict get $j access]}}
        dict set j access {};dict set j status cancelled;dict unset j queue
        dict set jobs $token $j
    }
    return [datasetProfileProgress $token]
}
proc ::GX::datasetProfileRelease {token} {
    variable ::GX::ScientificProfile::jobs
    if {[dict exists $jobs $token]} {datasetProfileCancel $token;dict unset jobs $token}
}
