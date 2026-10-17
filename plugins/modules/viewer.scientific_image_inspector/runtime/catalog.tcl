# ImageMagick operation registry: no strings from the user become option names.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::SII { variable catalog [dict create] }

# Params: (key type default min max enum-list), type number/int/percent/enum/geometry.
# support: executable, recognized, disabled; all entries have independent availability.
proc ::GX::SII::catalogAdd {id family class label about option params {support executable} {roi 1} {reason ""}} {
    variable catalog
    set safety [dict get [dict create executable validated_local recognized requires_review disabled blocked] $support]
    set input {One authorized canonical image.raster Dataset; first frame.}
    set output [expr {$class eq "output" ? "Explicit canonical derived image Dataset only" : "Derived raster or local display preview; no implicit Dataset publication"}]
    dict set catalog $id [dict create id $id family $family class $class label $label about $about option $option params $params support $support roi $roi reason $reason safety_class $safety input_requirements $input output_requirements $output]
}
proc ::GX::SII::param {name type default {low ""} {high ""} {choices {}}} {
    return [list $name $type $default $low $high $choices]
}
# Geometry / spatial changes. ROI compositing only for same-size operators.
namespace eval ::GX::SII {
catalogAdd resize Geometry operator Resize {Resize image pixels (geometry WxH).} -resize [list [param geometry geometry 1024x768]] executable 0
catalogAdd sample Geometry operator Sample {Nearest-neighbor resize.} -sample [list [param geometry geometry 640x480]] executable 0
catalogAdd crop Geometry operator Crop {Crop to geometry WxH+X+Y.} -crop [list [param rect geometry 256x256+0+0]] executable 0
catalogAdd rotate Geometry operator Rotate {Angle in degrees.} -rotate [list [param degrees number 90 -360 360]] executable 0
catalogAdd flip Geometry operator Flip {Flip vertically.} -flip {} executable 0
catalogAdd flop Geometry operator Flop {Flip horizontally.} -flop {} executable 0
catalogAdd auto_orient Geometry operator {Auto orient} {Respect EXIF orientation where supported.} -auto-orient {} executable 0
catalogAdd trim Geometry operator Trim {Remove edge background; may alter coordinates.} -trim {} executable 0
catalogAdd transpose Geometry operator Transpose {Transpose image axes.} -transpose {} executable 0
catalogAdd transverse Geometry operator Transverse {Transverse image axes.} -transverse {} executable 0
catalogAdd extent Geometry operator Extent {Resize canvas to geometry (top-left aligned).} -extent [list [param geometry geometry 800x600]] executable 0
catalogAdd deskew Geometry operator Deskew {Auto straighten using threshold percentage.} -deskew [list [param threshold percent 40 0 100]] executable 0
catalogAdd distort Geometry operator Distort {Affine, perspective and barrel distortion need structured control points.} -distort {} recognized 0 {Validated control-point and virtual pixel schemas not implemented}
catalogAdd affine Geometry operator Affine {Affine matrix transform requires geometry-safe matrices.} -affine {} recognized 0 {Coordinate schema and transform tracking not implemented}
catalogAdd resample Geometry setting Resample {Resolution dependent resampling.} -resample {} recognized 0 {Requires unit and density policy}
# Tones / contrast
catalogAdd gamma Tones operator Gamma {Power-law gamma modification.} -gamma [list [param gamma number 1.2 0.01 10]]
catalogAdd level Tones operator Levels {Black and white input points in percent.} -level [list [param black percent 1 0 99] [param white percent 99 1 100]]
catalogAdd brightness_contrast Tones operator {Brightness / contrast} {Brightness and contrast percentages.} -brightness-contrast [list [param brightness number 5 -100 100] [param contrast number 5 -100 100]]
catalogAdd auto_level Tones operator {Auto level} {Stretch per-channel image intensity dynamically.} -auto-level {}
catalogAdd auto_gamma Tones operator {Auto gamma} {Automatic gamma adjustment.} -auto-gamma {}
catalogAdd normalize Tones operator Normalize {Normalize histogram range.} -normalize {}
catalogAdd equalize Tones operator Equalize {Histogram equalization.} -equalize {}
catalogAdd contrast_stretch Tones operator {Contrast stretch} {Clip lower and upper distribution tails (%).} -contrast-stretch [list [param black percent 1 0 99] [param white percent 1 0 99]]
catalogAdd sigmoidal Tones operator {Sigmoidal contrast} {Sigmoidal contrast midpoint in percent and strength.} -sigmoidal-contrast [list [param contrast number 5 0 50] [param midpoint percent 50 0 100]]
catalogAdd threshold Tones operator Threshold {Threshold relative to quantum maximum.} -threshold [list [param threshold percent 50 0 100]]
catalogAdd white_threshold Tones operator {White threshold} {Set pixels above threshold to white.} -white-threshold [list [param threshold percent 80 0 100]]
catalogAdd black_threshold Tones operator {Black threshold} {Set pixels below threshold to black.} -black-threshold [list [param threshold percent 20 0 100]]
catalogAdd negate Tones operator Invert {Negate color channels.} -negate {}
catalogAdd solarize Tones operator Solarize {Invert pixel intensities above a threshold.} -solarize [list [param threshold percent 50 0 100]]
catalogAdd modulate Color operator Modulate {Brightness, saturation and hue factors.} -modulate [list [param brightness number 100 0 300] [param saturation number 100 0 300] [param hue number 100 0 300]]
catalogAdd colorspace Color setting Colorspace {Mathematical color-space conversion, not ICC profile management.} -colorspace [list [param space enum sRGB "" "" {sRGB RGB Gray Lab LCH HSV HSL CMYK XYZ YCbCr}]]
catalogAdd posterize Color operator Posterize {Discrete output color levels.} -posterize [list [param levels int 8 2 256]]
catalogAdd quantize Color operator {Palette quantization} {Reduce to at most N colors.} -colors [list [param count int 64 2 65536]]
catalogAdd alpha_extract Color channel {Extract alpha} {Convert output to an alpha coverage plane.} -alpha [list [param mode enum Extract "" "" {Extract}]] executable 0
catalogAdd alpha_deactivate Color channel {Deactivate alpha} {Deactivate alpha channel without applying transparency.} -alpha [list [param mode enum Off "" "" {Off}]] executable 0
catalogAdd separate_channel Color channel {Channel extraction} {Extract a channel; renders as grayscale.} -channel [list [param channel enum R "" "" {R G B A}]] recognized 0 {Requires channel sequence and availability validation}
catalogAdd color_matrix Color operator {Color matrix} {Arbitrary pixel matrix is not yet validated.} -color-matrix {} recognized 1 {Validated matrix schema not implemented}
catalogAdd profile Color setting {ICC profile} {External ICC file requires managed resource authorization.} -profile {} recognized 0 {External resources are not accepted as direct arguments}
catalogAdd clut Color operator CLUT {Requires an authorized second image.} -clut {} recognized 0 {Secondary Dataset selection is not implemented}
# Filters
catalogAdd blur Filters operator Blur {Radius and sigma (pixels).} -blur [list [param radius number 0 0 80] [param sigma number 1 0.1 80]]
catalogAdd gaussian_blur Filters operator {Gaussian blur} {Gaussian filtering in pixels.} -gaussian-blur [list [param radius number 0 0 80] [param sigma number 2 0.1 80]]
catalogAdd sharpen Filters operator Sharpen {Sharpen radius and sigma.} -sharpen [list [param radius number 0 0 80] [param sigma number 1 0.1 80]]
catalogAdd unsharp Filters operator Unsharp {Unsharp radius, sigma, gain and threshold.} -unsharp [list [param radius number 0 0 80] [param sigma number 1 0.1 80] [param gain number 1 0 10] [param threshold number 0.05 0 1]]
catalogAdd median Filters operator Median {Median neighborhood filter (NxN).} -statistic [list [param size int 3 1 31]]
catalogAdd despeckle Filters operator Despeckle {Reduce small speckles.} -despeckle {}
catalogAdd enhance Filters operator Enhance {ImageMagick noise enhancement.} -enhance {}
catalogAdd edge Filters operator Edge {Edge detection with a fixed radius.} -edge [list [param radius number 1 0.1 30]]
catalogAdd emboss Filters operator Emboss {Emboss radius and sigma.} -emboss [list [param radius number 0 0 50] [param sigma number 1 0.1 50]]
catalogAdd add_noise Filters operator {Add noise} {Synthetic noise; stochastic result depends on seed.} -noise [list [param distribution enum Gaussian "" "" {Uniform Gaussian Multiplicative Poisson Laplacian Impulse}]] recognized 1 {Seed and reproducibility policy not yet defined}
catalogAdd convolve Filters operator Convolution {Custom convolution coefficients not yet validated.} -convolve {} recognized 1 {Kernel matrix validation not implemented}
# Morphology and segmentation
catalogAdd erode Morphology operator Erode {Disk-shaped erosion; radius in pixels.} -morphology [list [param radius int 1 1 15]]
catalogAdd dilate Morphology operator Dilate {Disk-shaped dilation; radius in pixels.} -morphology [list [param radius int 1 1 15]]
catalogAdd open Morphology operator Open {Morphological opening using Disk.} -morphology [list [param radius int 1 1 15]]
catalogAdd close Morphology operator Close {Morphological closing using Disk.} -morphology [list [param radius int 1 1 15]]
catalogAdd gradient Morphology operator {Morphological gradient} {Gradient using Disk.} -morphology [list [param radius int 1 1 15]]
catalogAdd distance Morphology operator Distance {Euclidean distance transform; verify quantitative meaning.} -morphology {} recognized 1 {Requires calibrated output semantics and morphology scaling}
catalogAdd canny Morphology operator Canny {Requires structured sigma and thresholds.} -canny {} recognized 1 {Threshold pipeline not implemented}
catalogAdd connected_components Morphology operator {Connected components} {Segmentation labels with artifact metadata.} -connected-components {} recognized 1 {Label output and stats publication need dedicated schema}
# Multi-image, conversion, and intentionally disabled commands
catalogAdd compose Composition sequence Composite {Requires second canonical Dataset.} -compose {} recognized 0 {Second image and alpha alignment not implemented}
catalogAdd compare Composition sequence Compare {Quantified image differences require registered second input.} -compare {} recognized 0 {Second image Dataset selection not implemented}
catalogAdd append Composition sequence Append {Multi-frame stack generation.} -append {} recognized 0 {Sequence policy and frame count not implemented}
catalogAdd flatten Composition sequence Flatten {Flatten image layers.} -flatten {} recognized 0 {Requires explicit multi-frame handling}
catalogAdd convert_file Output output {Format conversion} {PNG and TIFF publication choices are available in Publish dialog.} {} {} recognized 0 {Handled by controlled publication only}
catalogAdd set_define Unsafe setting {Arbitrary defines} {Unrestricted -define is unsafe.} -define {} disabled 0 {Unrestricted coder/delegate settings prohibited}
catalogAdd fx Unsafe operator FX {Arbitrary expression evaluator is not permitted.} -fx {} disabled 0 {Unrestricted expressions are prohibited}
catalogAdd draw Unsafe operator Draw {External MVG/URL/path payload not accepted.} -draw {} disabled 0 {Unrestricted primitive strings are prohibited}
catalogAdd write Unsafe output Write {Arbitrary filenames and side effects prohibited.} -write {} disabled 0 {Only canonical explicit publication/export is permitted}
catalogAdd script Unsafe input Script {Arbitrary ImageMagick scripts not permitted.} -script {} disabled 0 {Can execute unrestricted command sequences}
catalogAdd delegate Unsafe input Delegate {External delegates not executable through this catalog.} -delegate {} disabled 0 {No direct delegate invocation}

}
proc ::GX::SII::catalogList {{query ""}} {
    variable catalog
    set out {}
    dict for {id spec} $catalog {
        if {$query ne "" && [string first [string tolower $query] [string tolower "$id [dict get $spec family] [dict get $spec label] [dict get $spec about]"]] < 0} continue
        lappend out $spec
    }
    return [lsort -command ::GX::SII::catalogCompare $out]
}
proc ::GX::SII::catalogCompare {a b} {
    return [string compare "[dict get $a family] [dict get $a label]" "[dict get $b family] [dict get $b label]"]
}
proc ::GX::SII::catalogGet {id} {
    variable catalog
    if {![dict exists $catalog $id]} {error "Unknown operation: $id"}
    return [dict get $catalog $id]
}
