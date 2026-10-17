# CORE interpretation of retained amplitude-spectrum quality estimators.
# SPDX-License-Identifier: GPL-3.0-or-later
apply {{} {
    variable quantities
    foreach {id label unit definition} {
        amplitude_bin_spacing {Frequency-bin spacing} frequency {Recorded spectral coordinate spacing under the numerical estimator}
        fft_window_coherent_gain {Window coherent gain} dimensionless {Arithmetic mean of the applied symmetric FFT window used for amplitude correction}
        spectrum_reference_amplitude {Reference fundamental amplitude} response {Selected fundamental amplitude under the recorded peak or lobe estimator}
        spectrum_reference_frequency {Resolved fundamental frequency} frequency {Frequency coordinate of the selected fundamental bin}
        amplitude_thd_ratio {Tracked harmonic amplitude ratio} dimensionless {Root sum of squared tracked harmonic amplitudes divided by the reference fundamental amplitude}
        amplitude_thd_percent {Tracked harmonic distortion percent} % {One hundred times the tracked harmonic amplitude ratio}
        amplitude_thd_level {Tracked harmonic distortion level} dB {Twenty log10 of the tracked harmonic amplitude ratio; zero has no finite logarithmic level}
        amplitude_sfdr_level {Amplitude-spectrum SFDR} dB {Twenty log10 of the reference lobe amplitude divided by the largest eligible single-bin spur amplitude}
        amplitude_spur_relative_level {Selected spur relative level} dB {Twenty log10 of the eligible single-bin spur amplitude divided by the reference lobe amplitude}
        amplitude_spur {Selected single-bin spur amplitude} response {Largest amplitude bin outside the recorded DC and lobe exclusions; not an integrated spur lobe}
        amplitude_spur_frequency {Selected spur frequency} frequency {Frequency coordinate of the first largest eligible spur bin}
        amplitude_sinad_level {Amplitude-spectrum SINAD} dB {Ten log10 of reference lobe amplitude squared divided by the sum of squared amplitude bins outside the DC and fundamental lobe exclusions}
        amplitude_nominal_bits {SINAD-derived nominal effective bits} bit {SINAD minus 1.76 dB divided by 6.02 dB under the ideal full-scale sinusoidal quantizer convention; not a device-resolution guarantee}
        amplitude_noise_median {Median nonfundamental bin amplitude} response {Median amplitude outside the DC and fundamental lobe exclusions; includes harmonics and zero bins}
        amplitude_noise_median_level {Reported median amplitude level} dB {Twenty log10 of max(median amplitude, binary64 realmin) divided by reference amplitude; the finite floor is a reporting convention}
        harmonic_count {Resolved harmonic orders} count {Number of retained component orders including the fundamental for local single-bin analysis}
        harmonic_order {Harmonic order identity} count {Positive integer component order retained from the numerical estimator}
        harmonic_expected_frequency {Expected harmonic frequency} frequency {Declared integer harmonic target coordinate}
        harmonic_frequency {Detected harmonic frequency} frequency {Coordinate of the selected component peak bin}
        harmonic_frequency_error {Harmonic frequency error} frequency {Detected frequency minus the expected integer-harmonic coordinate}
        harmonic_amplitude {Component amplitude} response {Supplied component amplitude under the recorded single-bin, lobe RSS or caller-supplied method}
        harmonic_level_db {Reported component relative level} dB {Twenty log10 of component amplitude divided by the reference, using only the explicitly recorded level floor}
        harmonic_amplitude_percent {Component amplitude percent} % {One hundred times component amplitude divided by the reference fundamental amplitude}
    } {
        dict set quantities $id [dict create label $label unit $unit kind scalar policy spectral_quality definition $definition]
    }
    unset id label unit definition
} ::GX::StatisticsV1}
proc ::GX::StatisticsV1::_spectralQualityAssumptions {profile context} {
    if {$profile eq "fft_spectrum_quality"} {return {{Single-sided peak amplitudes use N times coherent gain; DC and even-length Nyquist amplitudes are halved} {Fundamental and harmonic amplitudes are root sums of squared amplitude bins in their recorded lobes; overlapping lobes are not deduplicated} {SFDR compares a reference lobe to a single-bin spur under the recorded exclusion policy} {SINAD and median include nonfundamental harmonics; they are not an independently estimated noise model} {Magnitude and median display levels use binary64 realmin flooring; THD and spur ratios have no invented finite zero level} {ENOB uses an ideal full-scale sinusoidal quantizer convention; no uncertainty or device guarantee is inferred}}}
    if {$profile eq "harmonic_peak_quality"} {return {{Local single-bin peaks are selected near integer multiples of the resolved fundamental; overlapping search ranges may select the same source bin} {THD includes only resolved orders through the configured maximum and available frequency range} {The existing source amplitude spectrum is not recomputed; its normalization remains source-owned} {No sampling uncertainty, confidence interval or noise-independence claim is inferred}}}
    set assumptions {{Component identities and frequency errors are retained from the numerical provider; the CORE does not search or recompute peaks} {Amplitude percent and relative level use the supplied reference amplitude; no uncertainty is inferred}}
    if {[_get $context component_level_floor {}] eq "realmin"} {lappend assumptions {Reported component levels floor amplitudes below binary64 realmin; a finite floored level is not a positive physical amplitude claim}} else {lappend assumptions {No component level floor is applied; a zero component has no finite logarithmic level}}
    return $assumptions
}
proc ::GX::StatisticsV1::_spectralQualityAdapt {operation raw context} {
    set numerical {}
    dict for {source quantity} [numericFieldMap $operation] {
        if {![dict exists $raw $source]||[llength [dict get $raw $source]]!=1} {_error {Spectral quality requires scalar facts; adapt component columns with bounded statistical tables}}
        dict set numerical $quantity [dict get $raw $source]
    }
    if {$operation eq "harmonic_components"} {set keys {component_method component_level_floor}} else {set keys {method fundamental_mode guard_bins track_harmonics}}
    if {$operation eq "fft_spectrum_quality"} {lappend keys normalization window detrend spur_search level_floor}
    if {$operation eq "harmonic_peak_quality"} {lappend keys exclude_dc_bins}
    foreach key $keys {dict set context $key [_get $raw $key {}]}
    dict set context assumptions [_spectralQualityAssumptions $operation $context]
    return [list $numerical $context]
}
proc ::GX::StatisticsV1::_validateSpectralQuality {profile numerical context} {
    foreach key {x_unit y_unit} {if {![dict exists $context $key]} {_error {Spectral quality requires actual frequency and amplitude units}}}
    if {[_get $context assumptions {}] ne [_spectralQualityAssumptions $profile $context]} {_error {Spectral quality must retain CORE estimator assumptions}}
    set reference [_get $numerical spectrum_reference_amplitude {}]
    if {![_finite $reference]||$reference<0} {_error {Spectral quality requires a finite nonnegative reference amplitude}}
    if {$profile eq "harmonic_components"} {
        if {[_get $context component_method {}] ni {supplied_component_amplitude fft_lobe_rss single_bin_peak}||[_get $context component_level_floor {}] ni {none realmin}} {_error {Unknown component amplitude or level-floor convention}}
        set order [_get $numerical harmonic_order {}]
        if {![_finite $order]||$order<1||$order!=floor($order)} {_error {Component order must be a positive integer identity}}
        set nonnegative {harmonic_amplitude harmonic_amplitude_percent}
    } else {
        if {[_get $context fundamental_mode {}] ni {auto_peak explicit}} {_error {Unknown fundamental selection method}}
        foreach key {guard_bins track_harmonics} {set value [_get $context $key {}];if {![_finite $value]||$value<0||$value!=floor($value)} {_error {Spectral search limits must be nonnegative integers}}}
        set n [_get $numerical n {}]
        if {![_finite $n]||$n<3||$n!=floor($n)} {_error {Spectral quality requires an actual source count}}
        if {$profile eq "fft_spectrum_quality"} {
            if {[_get $context method {}] ne "coherent_gain_corrected_fft_lobe_rss"||[_get $context normalization {}] ne "single_sided_peak_amplitude_with_dc_nyquist_halved"||[_get $context level_floor {}] ne "realmin"||[_get $context spur_search {}] ni {all_nonfundamental nonharmonic_only}||[_get $context window {}] eq {}||[_get $context detrend {}] eq {}} {_error {FFT lobe quality must preserve its numerical normalization and policies}}
            if {$n<8||[dict get $context track_harmonics]<2||[dict get $context track_harmonics]>65536||[dict get $context guard_bins]>=floor($n/2)} {_error {FFT search limits exceed their declared range}}
            set nonnegative {amplitude_thd_ratio amplitude_thd_percent amplitude_spur amplitude_noise_median}
        } else {
            if {[_get $context method {}] ne "local_single_bin_harmonic_peaks"} {_error {Unknown local harmonic estimator}}
            set count [_get $numerical harmonic_count {}];set dc [_get $context exclude_dc_bins {}]
            if {![_finite $count]||$count<1||$count!=floor($count)||$count>[dict get $context track_harmonics]||[dict get $context track_harmonics]>10000||[dict get $context track_harmonics]<2||[dict get $context guard_bins]>1000||![_finite $dc]||$dc<0||$dc>1000||$dc!=floor($dc)} {_error {Local harmonic search limits or resolved count are invalid}}
            set nonnegative {amplitude_thd_ratio amplitude_thd_percent}
        }
    }
    foreach key $nonnegative {set value [_get $numerical $key {}];if {[_finite $value]&&$value<0} {_error {Amplitude and distortion magnitudes cannot be negative}}}
}
proc ::GX::StatisticsV1::_spectralQualityPolicy {quantity profile numerical context} {
    if {$profile ni {fft_spectrum_quality harmonic_peak_quality harmonic_components}} {return {not_applicable {Quantity requires a registered amplitude-spectrum quality analysis}}}
    if {$quantity ni [dict values [numericFieldMap $profile]]} {return {not_applicable {Quantity is outside the recorded amplitude-spectrum estimator}}}
    if {[dict get $numerical spectrum_reference_amplitude]==0&&$quantity in {amplitude_thd_ratio amplitude_thd_percent amplitude_thd_level amplitude_sfdr_level amplitude_spur_relative_level amplitude_sinad_level amplitude_nominal_bits amplitude_noise_median_level harmonic_level_db harmonic_amplitude_percent}} {return {undefined {A zero reference amplitude does not define an amplitude ratio or logarithmic level}}}
    return {value {}}
}
