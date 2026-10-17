# Shared CORE signal interpretation; all arithmetic stays with public Numeric.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label unit definition} {
        signal_rms {Signal magnitude RMS} response {Square root of the arithmetic mean of squared complex magnitudes; not a standard error}
        signal_peak_magnitude {Peak signal magnitude} response {Largest absolute complex magnitude among the supplied samples}
        signal_real_peak_to_peak {Real-part peak-to-peak range} response {Maximum minus minimum of the real component; not the complex magnitude range}
        signal_crest_factor {Signal crest factor} dimensionless {Peak magnitude divided by magnitude RMS; undefined for an all-zero signal}
        signal_dc_real {Real DC component} response {Arithmetic mean of the real components of the supplied samples}
        signal_dc_imaginary {Imaginary DC component} response {Arithmetic mean of the imaginary components of the supplied samples}
    } {
        dict set quantities $id [dict create label $label unit $unit kind scalar policy signal_summary definition $definition]
    }
    unset id label unit definition
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_signalSummaryAssumptions {} {
    return {{Descriptive moments of the supplied real or complex samples; no sampling uncertainty or interval is inferred} {Sample count does not establish independent observations, bandwidth or effective degrees of freedom} {Magnitude RMS includes DC; the peak-to-peak field refers only to the real component}}
}

apply {{} {
    variable quantities
    foreach {id label unit definition} {
        event_mean_period {Mean intercrossing period} s {Arithmetic mean of consecutive supplied reference-crossing intervals, including zero intervals from repeated detections}
        event_frequency {Reciprocal mean intercrossing period} Hz {Reciprocal of the arithmetic mean period; not the mean of instantaneous reciprocal intervals}
        event_crossing_count {Reference crossing count} count {Number of supplied reference events, including repeated detections; not independent observations}
        event_period_count {Intercrossing interval count} count {Number of adjacent reference-event intervals, including zero intervals}
        pulse_width_count {Complete pulse width count} count {Reference intervals containing a first strictly later falling event before the next reference event}
        pulse_mean_width {Mean complete pulse width} s {Arithmetic mean of accepted complete pulse widths; incomplete intervals are excluded only from this mean}
        pulse_duty_ratio {Ratio of mean width to mean period} dimensionless {Mean complete width divided by mean of all reference intervals; not the mean of per-pulse duty ratios}
        period_jitter_std {Sample intercrossing period spread} s {Sample standard deviation of all reference intervals with denominator count minus one; not timing accuracy or standard error}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy event_timing definition $definition]}
    unset id label unit definition
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_eventTimingAssumptions {} {
    return {{Crossing extraction and direction remain source-owned; repeated detections are retained, not deduplicated} {Time inputs must be seconds; frequency is reciprocal mean period rather than mean instantaneous frequency} {Pulse width uses the first strictly later falling event before the next reference event; incomplete intervals still contribute to period statistics} {Descriptive event timing does not establish independent periods, measurement uncertainty or a confidence interval}}
}
proc ::GX::StatisticsV1::_eventTimingAdapt {operation raw context} {
    set numerical {}
    dict for {source quantity} [numericFieldMap $operation] {
        if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Event timing requires bounded scalar Numeric facts}}
        dict set numerical $quantity [dict get $raw $source]
    }
    dict set context method [_get $raw method {}];dict set context timing_operation $operation
    dict set context assumptions [_eventTimingAssumptions]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateEventTiming {numerical context} {
    set op [_get $context timing_operation {}]
    if {$op ni {event_period pulse_timing}||[_get $context x_unit {}] ne "s"||[_get $context assumptions {}] ne [_eventTimingAssumptions]} {_error {Event timing requires actual seconds and the CORE descriptive contract}}
    set method [expr {$op eq "event_period" ? "arithmetic_intercrossing_intervals" : "complete_pulse_intervals"}]
    if {[_get $context method {}] ne $method} {_error {Unknown event timing estimator}}
    set n [_get $numerical n {}]
    if {![_finite $n]||$n<1||$n!=floor($n)||![_finite [_get $numerical event_period_count {}]]||[dict get $numerical event_period_count]!=$n} {_error {Event timing requires its actual positive interval count}}
    set nc [_get $numerical event_crossing_count {}]
    if {![_finite $nc]||$nc!=$n+1} {_error {Crossing and interval counts disagree}}
    set nonnegative {event_mean_period event_frequency}
    if {$op eq "pulse_timing"} {
        set widths [_get $numerical pulse_width_count {}]
        if {![_finite $widths]||$widths<1||$widths>=$nc||$widths!=floor($widths)} {_error {Complete width count is inconsistent with the reference intervals}}
        set nonnegative [concat $nonnegative {pulse_mean_width pulse_duty_ratio period_jitter_std}]
    }
    foreach key $nonnegative {
        if {![dict exists $numerical $key]} {_error "Event timing is missing $key"}
        if {[_finite [dict get $numerical $key]]&&[dict get $numerical $key]<0} {_error {Timing spread, interval and frequency facts must be nonnegative}}
    }
}
proc ::GX::StatisticsV1::_eventTimingPolicy {quantity profile numerical context} {
    if {$profile ne "event_timing"} {return {not_applicable {Quantity requires a registered event-timing result}}}
    if {$quantity in {pulse_width_count pulse_mean_width pulse_duty_ratio period_jitter_std}&&[dict get $context timing_operation] ne "pulse_timing"} {return {not_applicable {Quantity requires complete pulse timing facts}}}
    if {$quantity eq "period_jitter_std"&&[dict get $numerical n]<2} {return {undefined {At least two reference intervals are required for sample period spread}}}
    if {$quantity eq "event_frequency"&&[dict get $numerical event_mean_period]==0} {return {undefined {Zero mean period has no finite reciprocal frequency}}}
    return {value {}}
}
proc ::GX::StatisticsV1::_validateSignalSummary {numerical context} {
    if {![dict exists $context y_unit]||[_get $context input_kind {}] ni {real complex}||[_get $context method {}] ne "descriptive_complex_magnitude"||[_get $context assumptions {}] ne [_signalSummaryAssumptions]} {_error {Signal summary requires actual units, input kind and the CORE descriptive contract}}
    set n [_get $numerical n {}]
    if {![_finite $n]||$n<1||$n!=floor($n)} {_error {Signal summary requires a positive integer sample count}}
    foreach key {signal_rms signal_peak_magnitude signal_real_peak_to_peak signal_crest_factor} {
        if {![dict exists $numerical $key]} {_error "Signal summary is missing $key"}
        set value [dict get $numerical $key]
        if {[_finite $value]&&$value<0} {_error {Signal magnitude, range and crest facts must be nonnegative}}
    }
}
proc ::GX::StatisticsV1::_signalSummaryPolicy {quantity profile numerical context} {
    if {$profile ne "signal_summary"} {return {not_applicable {Quantity requires a registered descriptive signal summary}}}
    if {$quantity eq "signal_crest_factor"&&[_finite [dict get $numerical signal_rms]]&&[dict get $numerical signal_rms]==0} {return {undefined {An all-zero signal has zero RMS and no defined crest ratio}}}
    return {value {}}
}

apply {{} {
    variable quantities
    foreach {id label unit definition} {
        signal_energy_sum {Supplied signal squared-magnitude sum} squared_response {Sum of squared magnitudes of the supplied signal samples; not time-integrated physical energy}
        supplied_noise_energy_sum {Supplied noise squared-magnitude sum} squared_response {Sum of squared magnitudes of the separately supplied noise samples; no noise model is inferred}
        signal_fundamental_bin_power {Fundamental raw FFT-bin magnitude squared} squared_response {Squared magnitude of the unnormalized positive FFT fundamental bin; not mean-square signal power}
        signal_dc_bin_power {DC raw FFT-bin magnitude squared} squared_response {Squared magnitude of the unnormalized DC FFT bin}
        signal_harmonic_bin_powers {Harmonic raw FFT-bin magnitudes squared} squared_response {Squared magnitudes of unnormalized positive FFT harmonic bins in the recorded harmonic order; Nyquist is not doubled}
        signal_noise_bin_power {Nonharmonic raw FFT-bin sum} squared_response {Nonnegative difference between non-DC nonfundamental positive-bin sum and harmonic-bin sum}
        signal_noise_floor_bin_power {Median positive nonharmonic FFT-bin magnitude squared} squared_response {Median of strictly positive nonharmonic non-DC positive-bin squared magnitudes; zero bins are excluded}
        signal_noise_floor_db_relative {Noise floor relative to fundamental} dB {Ten log10 of the positive-bin median divided by the raw fundamental-bin squared magnitude}
        signal_distortion_bin_power {Harmonic raw FFT-bin sum} squared_response {Sum of positive harmonic-bin squared magnitudes, including the undoubled Nyquist bin when harmonic}
        signal_thd {Coherent-bin total harmonic distortion} dimensionless {Square root of the harmonic-bin sum divided by fundamental-bin squared magnitude; raw-bin Nyquist weighting is retained}
        signal_thd_db {Coherent-bin harmonic distortion level} dB {Twenty log10 of the coherent-bin THD amplitude ratio; zero distortion has no finite logarithmic level}
        signal_thd_plus_noise {Coherent-bin distortion plus noise ratio} dimensionless {Square root of the non-DC nonfundamental positive-bin sum divided by fundamental-bin squared magnitude}
        signal_snr_db {Signal-to-noise ratio} dB {Ten log10 of the signal-to-noise squared-magnitude ratio under the recorded method}
        signal_sinad_db {Coherent-bin SINAD} dB {Ten log10 of fundamental-bin squared magnitude divided by the non-DC nonfundamental positive-bin sum}
        signal_sfdr_db {Coherent-bin SFDR} dB {Ten log10 of fundamental-bin squared magnitude divided by the largest non-DC nonfundamental positive bin}
        signal_enob_bits {SINAD-derived nominal effective bits} bit {SINAD minus 1.76 dB divided by 6.02 dB; an ideal full-scale sinusoidal quantizer convention, not a measured ADC resolution claim}
    } {
        dict set quantities $id [dict create label $label unit $unit kind [expr {$id eq "signal_harmonic_bin_powers" ? "vector" : "scalar"}] policy signal_quality definition $definition]
    }
    unset id label unit definition
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_signalQualityAssumptions {profile} {
    if {$profile eq "signal_snr"} {return {{Ratio of separately supplied complex-magnitude energies with equal sample counts; no noise independence or sampling uncertainty is inferred} {Zero numerator or denominator has no finite logarithmic ratio; energy sums carry squared response units, not joules}}}
    return {{Coherent real-signal rectangular-window FFT; positive bins only, without one-sided doubling or division by sample count squared} {DC and the declared fundamental are excluded from spurs; non-aliased harmonics through Nyquist are removed from the noise sum} {Noise floor is the median of strictly positive remaining bin magnitudes squared; zero bins are excluded} {Ratios retain raw-bin Nyquist weighting and are descriptive; no uncertainty, confidence interval or device-resolution guarantee is inferred} {ENOB uses the ideal full-scale sinusoidal quantizer relation; the API does not establish its physical assumptions}}
}
proc ::GX::StatisticsV1::_signalQualityAdapt {profile operation raw context} {
    set numerical {}
    dict for {source quantity} [numericFieldMap $operation] {
        if {![dict exists $raw $source]} {_error "Signal quality requires the Numeric fact $source"}
        if {$source ne "harmonic_powers"&&[llength [dict get $raw $source]]!=1} {_error {Signal quality scalar facts must be bounded scalars}}
        dict set numerical $quantity [dict get $raw $source]
    }
    dict set context method [_get $raw method {}];dict set context assumptions [_signalQualityAssumptions $profile]
    if {$profile eq "signal_snr"} {
        foreach key {signal_zero noise_zero} {dict set context $key [_get $raw $key {}]}
    } else {
        foreach key {normalization sample_rate fundamental_hz fundamental_bin} {dict set context $key [_get $raw $key {}]}
        dict set numerical harmonic_orders [_get $raw harmonic_orders {}]
    }
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateSignalQuality {profile numerical context} {
    if {![dict exists $context y_unit]||[_get $context assumptions {}] ne [_signalQualityAssumptions $profile]} {_error {Signal quality requires actual units and CORE conditional assumptions}}
    set n [_get $numerical n {}]
    if {![_finite $n]||$n<1||$n!=floor($n)} {_error {Signal quality requires a positive integer sample count}}
    if {$profile eq "signal_snr"} {
        if {[_get $context method {}] ne "ratio_of_supplied_complex_magnitude_energies"} {_error {Unknown supplied signal/noise ratio method}}
        foreach key {signal_zero noise_zero} {if {![string is boolean -strict [_get $context $key {}]]} {_error {Signal/noise ratio requires explicit zero-input facts}}}
        set nonnegative {signal_energy_sum supplied_noise_energy_sum}
    } else {
        if {[_get $context method {}] ne "coherent_positive_fft_bins"||[_get $context normalization {}] ne "raw_positive_fft_squared"} {_error {Unknown coherent FFT-bin convention}}
        foreach key {sample_rate fundamental_hz fundamental_bin} {if {![_finite [_get $context $key {}]]||[dict get $context $key]<=0} {_error {Coherent quality requires finite positive rate, frequency and bin identity}}}
        set fs [dict get $context sample_rate];set f0 [dict get $context fundamental_hz];set bin [dict get $context fundamental_bin]
        if {$f0>=$fs/2||$bin!=floor($bin)||abs($f0*$n/$fs-$bin)>1e-6} {_error {Fundamental identity is not a coherent below-Nyquist FFT bin}}
        set orders [_get $numerical harmonic_orders {}]
        if {[llength $orders]>65536||[llength $orders]!=int(floor(($fs/2)/$f0))-1} {_error {Harmonic identities differ from the bounded non-aliased order range}}
        set expected 2;foreach order $orders {if {![_finite $order]||$order!=$expected} {_error {Harmonic orders must preserve their complete increasing identity}};incr expected}
        set nonnegative {signal_fundamental_bin_power signal_dc_bin_power signal_harmonic_bin_powers signal_noise_bin_power signal_noise_floor_bin_power signal_distortion_bin_power signal_thd signal_thd_plus_noise}
    }
    foreach key $nonnegative {
        if {![dict exists $numerical $key]} {_error "Signal quality is missing $key"}
        foreach value [dict get $numerical $key] {if {[_finite $value]&&$value<0} {_error {Signal squared-magnitude and amplitude ratios must be nonnegative}}}
    }
}
proc ::GX::StatisticsV1::_signalQualityPolicy {quantity profile numerical context} {
    if {$profile ni {signal_snr signal_spectrum_quality}} {return {not_applicable {Quantity requires a registered signal quality analysis}}}
    if {$profile eq "signal_snr"} {
        if {$quantity ni {signal_snr_db signal_energy_sum supplied_noise_energy_sum}} {return {not_applicable {Quantity requires coherent FFT-bin quality facts}}}
        if {$quantity eq "signal_snr_db"&&([dict get $context signal_zero]||[dict get $context noise_zero])} {return {undefined {A zero supplied signal or noise energy has no finite logarithmic ratio}}}
    } elseif {$quantity in {signal_energy_sum supplied_noise_energy_sum}} {return {not_applicable {Supplied time-sample energy is distinct from raw FFT-bin magnitudes}}}
    return {value {}}
}

apply {{} {
    variable quantities
    foreach {id label unit definition} {
        sequence_first_count {First sequence sample count} count {Number of supplied first-sequence samples; not independent observations or overlap at the selected lag}
        sequence_second_count {Second sequence sample count} count {Number of supplied second-sequence samples}
        sequence_lag_count {Full correlation lag count} count {First length plus second length minus one, ordered from minus second length plus one through first length minus one}
        sequence_peak_magnitude {Peak sequence correlation magnitude} sequence_product {Largest magnitude of the uncentered conjugate correlation under the recorded normalization; not a Pearson coefficient}
        sequence_peak_real {Selected correlation real part} sequence_product {Real part at the first largest-magnitude correlation in ascending lag order}
        sequence_peak_imaginary {Selected correlation imaginary part} sequence_product {Imaginary part at the first largest-magnitude correlation in ascending lag order}
        sequence_delay_samples {Selected correlation lag} sample {Lag k of the first largest-magnitude sum x(j+k) times conjugate(y(j)); positive lag means the first sequence is delayed relative to the second}
        sequence_delay_seconds {Selected correlation delay} s {Selected lag divided by the explicitly supplied sample rate; not a sub-sample time estimate}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy signal_correlation definition $definition]}
    unset id label unit definition
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_signalCorrelationAssumptions {mode} {
    set result {{Finite-sequence uncentered conjugate correlation; no mean subtraction, Pearson association, independence or inferential significance is implied} {Lag k sums x(j+k) times conjugate(y(j)) over overlapping indices; lags are ascending} {The first largest absolute value selects the lag; ties are not a uniqueness claim and zero correlation has no resolved delay} {Full lag vectors remain scientific payload; this bounded receipt describes their normalization and selected peak without recomputing them}}
    switch -- $mode {
        none {lappend result {Raw overlapping product sums carry the product of the supplied signal units}}
        biased {lappend result {Every lag is divided by the larger input length; the biased name specifies normalization and is not a model-based bias guarantee}}
        unbiased {lappend result {Each lag is divided by its actual overlapping pair count; the unbiased name specifies normalization and is not a model-based bias guarantee}}
        coefficient {lappend result {Each input is normalized by its full-sequence Euclidean norm; the result is dimensionless and remains uncentered}}
        default {_error {Unknown sequence correlation normalization}}
    }
    return $result
}
proc ::GX::StatisticsV1::_signalCorrelationAdapt {raw context} {
    set numerical {}
    dict for {source quantity} [numericFieldMap signal_correlation] {
        # Legacy Signal omits seconds when no rate was supplied.
        if {$source eq "delay_seconds"&&![dict exists $raw $source]} {dict set numerical $quantity NaN;continue}
        if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Sequence correlation requires bounded scalar Numeric facts}}
        dict set numerical $quantity [dict get $raw $source]
    }
    foreach key {normalization method peak_policy input_kind peak_resolved} {dict set context $key [_get $raw $key {}]}
    set rate [_get $raw sample_rate NaN]
    if {[_finite $rate]} {dict set context sample_rate $rate} elseif {[string tolower $rate] eq "nan"} {if {[dict exists $context sample_rate]} {dict unset context sample_rate}} else {_error {Numeric sample rate must be positive finite or the explicit absent NaN}}
    dict set context assumptions [_signalCorrelationAssumptions [dict get $context normalization]]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateSignalCorrelation {numerical context} {
    if {![dict exists $context x_unit]||![dict exists $context y_unit]||[_get $context input_kind {}] ni {real complex}||[_get $context method {}] ne "uncentered_conjugate_sequence_correlation"||[_get $context peak_policy {}] ne "first_maximum_absolute_in_ascending_lag"} {_error {Sequence correlation requires actual input units, kind and lag/peak conventions}}
    if {[_get $context assumptions {}] ne [_signalCorrelationAssumptions [_get $context normalization {}]]} {_error {Sequence correlation requires CORE conditional assumptions}}
    foreach key {n sequence_first_count sequence_second_count sequence_lag_count} {
        set v [_get $numerical $key {}];if {![_finite $v]||$v<1||$v!=floor($v)} {_error {Sequence counts must be positive integers}}
    }
    set nx [dict get $numerical sequence_first_count];set ny [dict get $numerical sequence_second_count]
    if {[dict get $numerical n]!=$nx||[dict get $numerical sequence_lag_count]!=$nx+$ny-1} {_error {Sequence and lag counts disagree}}
    set lag [_get $numerical sequence_delay_samples {}]
    if {![_finite $lag]||$lag!=floor($lag)||$lag<1-$ny||$lag>$nx-1} {_error {Selected lag is outside the actual full-sequence range}}
    if {![string is boolean -strict [_get $context peak_resolved {}]]} {_error {Sequence correlation requires explicit delay availability}}
    set peak [_get $numerical sequence_peak_magnitude {}]
    if {[_finite $peak]&&$peak<0} {_error {Correlation peak magnitude cannot be negative}}
    if {[dict get $context peak_resolved]&&(![_finite $peak]||$peak<=0)} {_error {A resolved delay requires finite positive correlation magnitude}}
    if {[dict exists $context sample_rate]&&(![_finite [dict get $context sample_rate]]||[dict get $context sample_rate]<=0)} {_error {Sample rate must be finite and positive}}
}
proc ::GX::StatisticsV1::_signalCorrelationPolicy {quantity profile numerical context} {
    if {$profile ne "signal_correlation"} {return {not_applicable {Quantity requires a registered uncentered sequence-correlation result}}}
    if {$quantity in {sequence_delay_samples sequence_delay_seconds}&&![dict get $context peak_resolved]} {return {undefined {Zero or nonfinite correlation does not resolve a finite delay}}}
    if {$quantity eq "sequence_delay_seconds"&&![dict exists $context sample_rate]} {return {unavailable {Delay in seconds requires an explicit finite positive sample rate}}}
    return {value {}}
}

apply {{} {
    variable quantities
    foreach {id label unit definition} {
        window_sample_rate {Window reference sample rate} Hz {Explicit supplied sampling rate used to express discrete-window equivalent noise bandwidth in hertz}
        window_coherent_gain {Window coherent gain} dimensionless {Arithmetic mean of the supplied dimensionless window coefficients; its sign is retained}
        window_power_gain {Window power gain} dimensionless {Arithmetic mean of squared real window coefficients; not a sample variance or noise-power estimate}
        window_equivalent_noise_bandwidth {Window equivalent noise bandwidth} Hz {Sample rate times sum of squared coefficients divided by squared sum of coefficients; not FFT bin spacing or an uncertainty bandwidth}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy window_metrics definition $definition]}
    unset id label unit definition
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_windowMetricsAssumptions {} {
    return {{Deterministic finite real dimensionless window coefficients with nonzero sum; coefficient count does not establish independent samples} {Coherent gain retains the coefficient-sum sign; power gain is the uncentered second moment with denominator N} {Equivalent noise bandwidth uses the declared sample rate and is invariant to nonzero overall window scaling} {These window moments do not estimate signal noise, sampling uncertainty or confidence intervals}}
}
proc ::GX::StatisticsV1::_windowMetricsAdapt {raw context} {
    set numerical {}
    dict for {source quantity} [numericFieldMap window_metrics] {
        if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Window metrics require bounded scalar Numeric facts}}
        dict set numerical $quantity [dict get $raw $source]
    }
    dict set context method [_get $raw method {}];dict set context assumptions [_windowMetricsAssumptions]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateWindowMetrics {numerical context} {
    if {[_get $context x_unit {}] ne "1"||[_get $context method {}] ne "discrete_window_moments"||[_get $context assumptions {}] ne [_windowMetricsAssumptions]} {_error {Window metrics require actual dimensionless coefficients and the CORE deterministic contract}}
    set n [_get $numerical n {}]
    if {![_finite $n]||$n<1||$n!=floor($n)} {_error {Window coefficient count must be a positive integer}}
    set rate [_get $numerical window_sample_rate {}]
    if {![_finite $rate]||$rate<=0} {_error {Window sample rate must be finite and positive}}
    foreach key {window_power_gain window_equivalent_noise_bandwidth} {
        if {![dict exists $numerical $key]} {_error "Missing window fact $key"}
        set value [dict get $numerical $key]
        if {[_finite $value]&&$value<=0} {_error {A nonzero-sum window has positive power gain and equivalent noise bandwidth}}
    }
    if {![dict exists $numerical window_coherent_gain]} {_error {Missing window coherent gain}}
}
proc ::GX::StatisticsV1::_windowMetricsPolicy {quantity profile numerical context} {
    if {$profile ne "window_metrics"} {return {not_applicable {Quantity requires registered deterministic window metrics}}}
    return {value {}}
}
