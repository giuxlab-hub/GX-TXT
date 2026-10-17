source [file join [file dirname [info script]] .. api configuration_schema.tcl]
set validator ::GX::CurveDigitizerSettings::validateNameTemplate
foreach good {{[name].[calibration].curves} {[name].[index].[calibration_id]} {[name]}} {
    if {[$validator $good] ne $good} {error "Rejected valid template $good"}
}
foreach invalid {{[calibration].curves} {[name].[unknown]} {[name][unclosed} {../[name]} {[name]/test}} {
    if {![catch {$validator $invalid}]} {error "Accepted invalid naming template $invalid"}
}
puts {PASS CORE Configuration naming template validator}
