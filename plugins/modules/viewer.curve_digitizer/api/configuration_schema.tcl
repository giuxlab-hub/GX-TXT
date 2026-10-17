# SPDX-License-Identifier: GPL-3.0-or-later
# Lightweight configuration-only contribution; safe at descriptor discovery.
namespace eval ::GX::CurveDigitizerSettings {}
proc ::GX::CurveDigitizerSettings::validateNameTemplate {template} {
    set template [string trim $template]
    if {$template eq {} || [string length $template] > 220} {
        error {Dataset naming template must contain 1..220 characters.}
    }
    if {[string first {[name]} $template] < 0} {
        error {Dataset naming template must include [name].}
    }
    set residue $template
    foreach token [regexp -all -inline {\[[A-Za-z_]+\]} $template] {
        set key [string range $token 1 end-1]
        if {$key ni {name calibration calibration_id configuration index mode}} {
            error "Unknown Dataset naming token $token."
        }
        set residue [string map [list $token {}] $residue]
    }
    if {[string first {[} $residue] >= 0 || [string first {]} $residue] >= 0 ||
        ![regexp {^[A-Za-z0-9_.-]*$} $residue]} {
        error {Invalid characters or malformed token in Dataset naming template.}
    }
    return $template
}

# Central Configuration API: reject malformed CSS colors before persistence.
proc ::GX::CurveDigitizerSettings::validateCanvasColor {value} {
    if {![regexp {^#[[:xdigit:]]{6}$} $value]} {
        error {Canvas background must be a #RRGGBB color.}
    }
    return [string tolower $value]
}
