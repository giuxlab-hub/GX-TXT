# Handwritten scientific hooks; preserved on regeneration.
namespace eval ::GX::Generated_viewer_dev104_demo_b::Handlers {}
proc ::GX::Generated_viewer_dev104_demo_b::Handlers::fit {window action} {
    return {status not_connected}
}
proc ::GX::Generated_viewer_dev104_demo_b::Handlers::load {window action} {
    return {status not_connected}
}
proc ::GX::Generated_viewer_dev104_demo_b::Handlers::zoom_in {window action} {
    return {status not_connected}
}
proc ::GX::Generated_viewer_dev104_demo_b::Handlers::zoom_out {window action} {
    return {status not_connected}
}

# Independent handwritten scientific source; must survive regeneration.
proc ::GX::Generated_viewer_dev104_demo_b::Handlers::load {window action} {
    set values [::GX::viewerGuiDesignValues $window]
    set request [dict create dataset_id [dict get $values dataset] x_variable_id [dict get $values x_variable] y_variable_id [dict get $values y_variable] display_budget 4096]
    ::GX::viewerGuiDesignSourceSet $window xy $request
    return {status completed}
}
