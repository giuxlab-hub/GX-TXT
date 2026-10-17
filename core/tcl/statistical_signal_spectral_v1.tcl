# Shared per-bin spectral interpretation, without FFT or estimator arithmetic.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label unit definition} {
        spectral_estimate_frequency {Spectral bin frequency} Hz {Frequency coordinate of this numerical estimate on the recorded FFT grid}
        spectral_estimate_real {Spectral estimate real component} spectral_estimate {Real component under the recorded spectral estimator}
        spectral_estimate_imaginary {Spectral estimate imaginary component} spectral_estimate {Imaginary component under the recorded spectral estimator}
        spectral_estimate_sample_rate {Spectral sample rate} Hz {Explicit supplied samples-per-second rate used in the spectral grid and density normalization}
        spectral_estimate_fft_length {Spectral FFT length} count {Actual numerical FFT length after the backend segment-length rule}
        spectral_estimate_bin_count {Spectral bin count} count {Actual full returned grid length under the recorded one-sided or two-sided policy}
        spectral_estimate_window_length {Spectral window length} count {Number of coefficients in the actual resolved analysis window}
        spectral_estimate_overlap {Overlapping segment samples} count {Integer segment overlap after truncating the supplied native overlap fraction times window length}
        spectral_estimate_window_count {Averaged segment count} count {Actual complete periodograms included in the arithmetic spectral average; not effective independent observations}
        spectral_estimate_used_samples {Used segment span} count {Span covered by complete segments, including backend zero padding when shorter than one window; unused trailing samples are excluded}
    } {dict set quantities $id [dict create label $label unit $unit kind scalar policy signal_spectral definition $definition]}
    unset id label unit definition
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_signalSpectralFieldMap {operation} {
    set common {n n sample_rate spectral_estimate_sample_rate fft_length spectral_estimate_fft_length bin_count spectral_estimate_bin_count window_length spectral_estimate_window_length overlap_samples spectral_estimate_overlap window_count spectral_estimate_window_count used_sample_count spectral_estimate_used_samples frequency_hz spectral_estimate_frequency}
    switch -- $operation {
        signal_periodogram - signal_welch {return [concat $common {psd_real spectral_estimate_real psd_imaginary spectral_estimate_imaginary}]}
        signal_asd {return [concat $common {asd spectral_estimate_real}]}
        signal_cross_psd - signal_coherence - signal_frf_h1 - signal_frf_h2 {return [concat $common {value_real spectral_estimate_real value_imaginary spectral_estimate_imaginary}]}
        default {_error {Unknown registered spectral estimator}}
    }
}
proc ::GX::StatisticsV1::_signalSpectralUnit {context} {
    set x [_get $context x_unit unspecified];set y [_get $context y_unit unspecified]
    switch -- [_get $context spectral_operation {}] {
        periodogram - welch {return "($x)^2/Hz"}
        asd {return "($x)/sqrt(Hz)"}
        cross_psd {return "($x)*($y)/Hz"}
        coherence {return 1}
        frf_h1 - frf_h2 {return "($y)/($x)"}
        default {return unspecified}
    }
}
proc ::GX::StatisticsV1::_signalSpectralDefinition {action quantity} {
    set component [expr {$quantity eq "spectral_estimate_real" ? "Real" : "Imaginary"}]
    switch -- $action {
        periodogram {return "$component component of the windowed periodogram, normalized by sample rate and squared window norm; no mean removal"}
        welch {return "$component component of the arithmetic mean of complete windowed periodograms, normalized by sample rate and squared window norm"}
        asd {return {Nonnegative square root of the real Welch power spectral density; not an FFT peak amplitude}}
        cross_psd {return "$component component of the Welch cross density Y times conjugate(X), normalized by sample rate and squared window norm"}
        coherence {return "$component component of magnitude-squared coherence abs(Pxy)^2/(Pxx*Pyy); undefined for a zero denominator and not Pearson correlation"}
        frf_h1 {return "$component component of the H1 transfer estimate Pxy/Pxx, with Pxy=Y times conjugate(X); undefined for a zero denominator"}
        frf_h2 {return "$component component of the H2 transfer estimate Pyy/conjugate(Pxy), with Pxy=Y times conjugate(X); undefined for a zero denominator"}
        default {_error {Unknown spectral estimator definition}}
    }
}
proc ::GX::StatisticsV1::_signalSpectralAssumptions {context} {
    set result {{Per-frequency numerical estimates; full spectral vectors remain scientific payload and must use bounded rows or Dataset-local column bindings} {Sample/segment counts do not establish independent averages, effective degrees of freedom, confidence intervals or causal transfer behavior}}
    if {[dict get $context spectral_operation] eq "periodogram"} {
        lappend result {Periodogram removes no mean; an explicitly shorter FFT folds the complete windowed sequence before transforming}
    } else {
        lappend result {Native Octave Welch convention is explicit and caller compatibility state is restored; one global mean over the complete used segment span is removed before windowing}
        lappend result {Complete segments are averaged arithmetically; trailing samples outside their span are unused and a short signal is zero padded to one window}
    }
    if {[dict get $context sidedness] eq "onesided"} {
        lappend result {Real effective inputs use positive frequencies including DC and even-length Nyquist; negative-frequency power is added without doubling DC or Nyquist}
    } else {lappend result {Complex effective inputs use the full unshifted grid from zero toward the sample rate; negative frequencies are represented by their wrapped coordinates}}
    if {[dict get $context spectral_operation] in {cross_psd coherence frf_h1 frf_h2}} {lappend result {Paired estimates share one window, mean-removal span and sidedness; cross-spectrum conjugation is Y times conjugate(X)}}
    return $result
}
proc ::GX::StatisticsV1::_signalSpectralAdapt {operation raw context} {
    set numerical {};set action [string range $operation 7 end]
    dict for {source quantity} [_signalSpectralFieldMap $operation] {
        if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Spectral interpretation requires scalar per-bin facts; use from_numeric_columns or a Dataset-local column binding for vectors}}
        dict set numerical $quantity [dict get $raw $source]
    }
    foreach key {method spectral_operation sidedness detrend input_kind normalization} {dict set context $key [_get $raw $key {}]}
    if {[dict get $context spectral_operation] ne $action} {_error {Spectral operation identity differs from its public Numeric operation}}
    dict set context assumptions [_signalSpectralAssumptions $context]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateSignalSpectral {numerical context} {
    set action [_get $context spectral_operation {}]
    if {$action ni {periodogram welch asd cross_psd coherence frf_h1 frf_h2}||![dict exists $context x_unit]||[_get $context sidedness {}] ni {onesided twosided}||[_get $context input_kind {}] ni {real complex}||[_get $context normalization {}] ne "window_energy_and_sample_rate"} {_error {Spectral estimates require their actual operation, first-signal unit and normalization}}
    if {$action in {cross_psd coherence frf_h1 frf_h2}&&![dict exists $context y_unit]} {_error {Paired spectral estimates require the actual second-signal unit}}
    set method [expr {$action eq "periodogram" ? "octave_periodogram_window_energy" : "octave_native_welch_window_energy"}]
    set detrend [expr {$action eq "periodogram" ? "none" : "global_mean_over_used_segment_span"}]
    if {[_get $context method {}] ne $method||[_get $context detrend {}] ne $detrend||[_get $context assumptions {}] ne [_signalSpectralAssumptions $context]} {_error {Spectral method and mean-removal convention must retain CORE interpretation}}
    if {[dict get $context sidedness] ne [expr {[dict get $context input_kind] eq "real" ? "onesided" : "twosided"}]} {_error {Spectral sidedness differs from the effective input kind}}
    foreach key {n spectral_estimate_fft_length spectral_estimate_bin_count spectral_estimate_window_length spectral_estimate_window_count spectral_estimate_used_samples} {
        set v [_get $numerical $key {}];if {![_finite $v]||$v<1||$v!=floor($v)} {_error {Spectral counts must be positive integers}}
    }
    set n [dict get $numerical n];set fft [dict get $numerical spectral_estimate_fft_length];set length [dict get $numerical spectral_estimate_window_length];set count [dict get $numerical spectral_estimate_window_count];set used [dict get $numerical spectral_estimate_used_samples];set overlap [_get $numerical spectral_estimate_overlap {}]
    if {![_finite $overlap]||$overlap<0||$overlap!=floor($overlap)||$overlap>=$length} {_error {Invalid actual segment overlap}}
    if {$action eq "periodogram"} {
        if {$length!=$n||$used!=$n||$count!=1||$overlap!=0} {_error {Periodogram facts must describe the complete single window}}
    } elseif {$fft<$length||$used!=$length+($count-1)*($length-$overlap)||$count!=int(floor((max($n,$length)-$length)/($length-$overlap)))+1} {_error {Welch complete-segment facts are inconsistent}}
    set bins [expr {[dict get $context sidedness] eq "onesided" ? int(floor($fft/2))+1 : $fft}]
    if {[dict get $numerical spectral_estimate_bin_count]!=$bins} {_error {Spectral bin count differs from FFT length and sidedness}}
    set rate [_get $numerical spectral_estimate_sample_rate {}];set frequency [_get $numerical spectral_estimate_frequency {}]
    if {![_finite $rate]||$rate<=0||![_finite $frequency]||$frequency<0||$frequency>=$rate} {_error {Invalid spectral rate or unshifted frequency coordinate}}
    set index [expr {$frequency/$rate*$fft}]
    if {abs($index-round($index))>1e-8||round($index)>=$bins} {_error {Spectral coordinate is outside the recorded FFT grid}}
    if {$action in {periodogram welch asd coherence}} {
        set value [_get $numerical spectral_estimate_real {}]
        if {[_finite $value]&&($value<0||($action eq "coherence"&&$value>1+1e-10))} {_error {Power, amplitude density or coherence is outside its numerical range}}
    }
}
proc ::GX::StatisticsV1::_signalSpectralPolicy {quantity profile numerical context} {
    if {$profile ne "signal_spectral"} {return {not_applicable {Quantity requires a registered per-frequency spectral estimator}}}
    if {$quantity eq "spectral_estimate_imaginary"&&[dict get $context spectral_operation] eq "asd"} {return {not_applicable {Amplitude spectral density is a nonnegative real quantity}}}
    return {value {}}
}
