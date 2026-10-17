# SPDX-License-Identifier: GPL-3.0-or-later
proc ::GX::SignalAPIv1::datasetMethods {} {return {quality.basic correlation.auto correlation.cross spectral.periodogram spectral.welch spectral.asd spectral.coherence spectral.frf_h1 spectral.frf_h2 analytic.envelope analytic.phase analytic.instantaneous_frequency filter.causal filter.zero_phase multirate.decimate}}
proc ::GX::SignalAPIv1::datasetServiceRegister {} {
    set parameters [dict create dataset_id {type string required 1} primary {type string required 1} secondary {type string default {}} time {type string default {}} operation [dict create type choice values [datasetMethods] required 1] sample_rate {type number default 0 min 0} window {type integer default 256 min 8} overlap {type number default .5 min 0 max .95} normalization {type choice default coefficient values {none biased unbiased coefficient}} cutoff {type number default 10 min 0} order {type integer default 3 min 1 max 6} decimation {type integer default 2 min 2 max 64}]
    ::GX::scientificExecutionRegister math.signal.dataset [dict create module_id math.signal version 1.0.0 worker plugins/modules/math.signal/api/dataset_provider.py tools {} parameters $parameters runtime_files {plugins/modules/math.signal/api/operation_fields_v1.tsv plugins/modules/math.signal/api/operation_constraints_v1.tsv}]
    return $parameters
}
proc ::GX::SignalAPIv1::datasetSubmit {parameters} {
    datasetServiceRegister
    set source [dict get $parameters dataset_id]
    set prepared [::GX::scientificExecutionPrepare math.signal.dataset $parameters {} [dict create node_id local dataset_sources [list $source]]]
    return [::GX::scientificExecutionSubmit $prepared]
}
proc ::GX::SignalAPIv1::datasetStatus {job} {return [::GX::scientificExecutionStatus $job]}
proc ::GX::SignalAPIv1::datasetCancel {job} {return [::GX::scientificExecutionCancel $job]}
