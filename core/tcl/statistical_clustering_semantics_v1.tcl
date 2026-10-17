# Captured native clustering facts and assignment meaning, no clustering here.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label kind unit definition} {
        cluster_centers {Returned cluster centers} matrix coordinate_columns {Selected native solution coordinates in cluster-row and feature-column order; no additional final-assignment refit is claimed}
        cluster_populations {Assigned observations per cluster} vector count {Counts of the actual returned nearest-center assignments in cluster-label order}
        cluster_within_ss {Within-cluster squared distances} vector covariance_eigen_unit {Native sums of squared Euclidean coordinate distances to the returned centers under the actual returned assignments}
        cluster_total_within_ss {Total squared coordinate distance} scalar covariance_eigen_unit {Sum of native within-cluster squared distances for the selected returned solution; not a variance estimate or inferential test}
        cluster_count {Returned cluster count} scalar count {Requested and returned number of cluster labels}
        cluster_feature_count {Clustering coordinate count} scalar count {Number of actual feature columns used in the native distance}
        cluster_replicates {Requested native starts} scalar count {Requested repeated starts under the recorded native provider; convergence of every start is not established}
    } {dict set quantities $id [dict create label $label kind $kind unit $unit policy clustering definition $definition]}
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_clusteringFields {} {return {n n centroids cluster_centers cluster_counts cluster_populations within_ss cluster_within_ss total_within_ss cluster_total_within_ss cluster_count cluster_count feature_count cluster_feature_count replicates cluster_replicates}}
proc ::GX::StatisticsV1::_clusteringAssumptions {} {
    return {{Assignments are nearest returned centers under squared Euclidean coordinate distance; no automatic feature standardization is performed} {Center and label ordering are identities of this seeded calculation, not physical class identities across unrelated fits} {Mixed physical coordinate units do not define one physical squared-distance unit; preprocessing and scaling are part of the scientific model} {Requested native starts and the selected objective do not establish a global optimum or convergence of every start} {The native provider does not return selected-solution iteration counts or convergence status; these are not invented} {Cluster counts and centers are descriptive; no sampling uncertainty or significance is inferred}}
}
proc ::GX::StatisticsV1::_clusteringAdapt {raw context} {
    foreach {key expected} {method native_kmeans_sqeuclidean start_method plus empty_action singleton convergence not_reported random_generator twister} {
        if {[_get $raw $key {}] ne $expected} {_error {Clustering must retain its actual native settings}}
    }
    if {![_finite [_get $raw max_iterations {}]]||[dict get $raw max_iterations]!=100} {_error {Clustering must retain its actual iteration limit}}
    set k [_get $raw cluster_count {}];set p [_get $raw feature_count {}]
    foreach count [list $k $p] {if {![_finite $count]||$count<1||$count>128||$count!=floor($count)} {_error {Bounded clustering interpretation requires one to 128 clusters and features}}}
    set k [expr {int($k)}];set p [expr {int($p)}]
    set ids {};for {set i 1} {$i<=$k} {incr i} {lappend ids cluster_$i};dict set context cluster_ids $ids
    if {![dict exists $context output_ids]} {set ids {};for {set i 1} {$i<=$p} {incr i} {lappend ids feature_$i};dict set context output_ids $ids}
    if {![dict exists $context output_units]} {dict set context output_units [lrepeat $p [_get $context y_unit unspecified]]}
    dict set context method native_kmeans_sqeuclidean;dict set context initialization plus
    dict set context empty_cluster_policy singleton;dict set context iteration_limit 100;dict set context convergence_evidence not_reported
    dict set context assumptions [_clusteringAssumptions]
    set numerical {};dict for {field quantity} [_clusteringFields] {if {![dict exists $raw $field]} {_error {Clustering is missing a captured numerical fact}};dict set numerical $quantity [dict get $raw $field]}
    set centers [dict get $numerical cluster_centers]
    if {$k==1&&($p>1&&[llength $centers]==$p)} {set centers [list $centers]}
    dict set numerical cluster_centers $centers
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateClustering {numerical context} {
    foreach {key expected} {method native_kmeans_sqeuclidean initialization plus empty_cluster_policy singleton convergence_evidence not_reported} {if {[_get $context $key {}] ne $expected} {_error {Clustering context differs from its actual native policy}}}
    if {![_finite [_get $context iteration_limit {}]]||[dict get $context iteration_limit]!=100} {_error {Clustering context differs from its actual iteration limit}}
    if {[_get $context assumptions {}] ne [_clusteringAssumptions]} {_error {Clustering requires the shared CORE interpretation limits}}
    foreach key {n cluster_count cluster_feature_count cluster_replicates} {set v [_get $numerical $key {}];if {![_finite $v]||$v<1||$v!=floor($v)} {_error {Clustering counts must be positive integers}}}
    set k [dict get $numerical cluster_count];set p [dict get $numerical cluster_feature_count]
    set rows [_get $context cluster_ids {}];set columns [_get $context output_ids {}]
    set canonical {};for {set i 1} {$i<=$k} {incr i} {lappend canonical cluster_$i}
    if {$k>128||$p>128||$k>[dict get $numerical n]||$rows ne $canonical||[llength $columns]!=$p||[llength [lsort -unique $columns]]!=$p||{} in $columns||[llength [_get $context output_units {}]]!=$p} {_error {Clustering dimensions, feature units or label identities are inconsistent}}
    set centers [_get $numerical cluster_centers {}]
    if {[llength $centers]!=$k} {_error {Center rows differ from cluster identities}}
    foreach row $centers {if {[llength $row]!=$p} {_error {Center columns differ from feature identities}};foreach v $row {if {![_finite $v]} {_error {Cluster center is nonfinite}}}}
    set counts [_get $numerical cluster_populations {}];set distances [_get $numerical cluster_within_ss {}]
    if {[llength $counts]!=$k||[llength $distances]!=$k} {_error {Cluster counts or objectives differ from label identities}}
    set total 0;foreach v $counts {if {![_finite $v]||$v<0||$v!=floor($v)} {_error {Cluster populations must be nonnegative integers}};set total [expr {$total+$v}]}
    if {$total!=[dict get $numerical n]} {_error {Cluster populations do not cover the actual observations}}
    foreach v [concat $distances [list [_get $numerical cluster_total_within_ss {}]]] {if {![_finite $v]||$v<0} {_error {Clustering objectives must be finite and nonnegative}}}
}
proc ::GX::StatisticsV1::_clusteringPolicy {quantity profile numerical context} {
    if {$profile ne "clustering"} {return {not_applicable {Quantity requires a registered native clustering result}}}
    return {value {}}
}
proc ::GX::StatisticsV1::numericDataFields {result} {
    validate $result
    set fields {}
    if {[_get $result schema {}] eq "gxtxt.fit_profile_interpretation.v1"} {set fields [_profileDataFields $result]}
    if {[_get $result schema {}] eq "gxtxt.regression_bootstrap_interpretation.v1"} {set fields [_bootstrapDataFields $result]}
    if {[_get $result schema {}] eq "gxtxt.regression_influence_interpretation.v1"} {set fields [_influenceDataFields $result]}
    if {[_get $result schema {}] eq "gxtxt.log_response_interpretation.v1"} {
        dict for {name column} [dict get $result columns] {
            if {[dict get $column status] eq "value"} {dict set fields $name [dict merge $column [dict create kind vector value_kind real shape [list [expr {int([dict get $result row_count])}] 1] nonfinite_status unavailable nonfinite_reason {Captured log interval has an unavailable row}]]}
        }
    }
    if {[_get $result schema {}] eq "gxtxt.statistical_result.v1"&&[dict get $result model profile] eq "clustering"} {
        set n [dict get $result quantities n value];set k [dict get $result quantities cluster_count value]
        dict set fields labels [dict create kind vector value_kind integer unit 1 shape [list [expr {int($n)}] 1] minimum 1 maximum [expr {int($k)}] \
            label {Cluster assignment label} definition {One-based row of the returned cluster-center matrix, in original observation order; label numbers are identifiers, not continuous measurements} \
            identity_ids [dict get $result context cluster_ids]]
    }
    if {[_get $result schema {}] eq "gxtxt.statistical_result.v1"&&[dict get $result model profile] eq "foundation_regression"} {set fields [_foundationRegressionDataFields $result]}
    if {[_get $result schema {}] eq "gxtxt.statistical_result.v1"&&[dict get $result model profile] eq "prediction_uncertainty"} {set fields [_predictionDataFields $result]}
    if {[_get $result schema {}] eq "gxtxt.statistical_result.v1"&&[_get [dict get $result context] fit_geometry vertical_response] eq "orthogonal_xy"} {set fields [_orthogonalXYDataFields $result]}
    return [dict create api_id STATISTICAL_RESULT_SEMANTICS_API_v1 api_version 1 schema gxtxt.statistical_data_fields.v1 fields $fields]
}
