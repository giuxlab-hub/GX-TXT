source [file join [file dirname [info script]] project_common.tcl]
proc workspaceSeed {} {
 set ::GX::cfg(output_root) [file join $::out sessions]
 set ::session [::GX::createNewSession {Workspace fixture}]
 ::GX::modulePublicApiActivate viewer.curve_viewer CURVE_VIEWER_API_v1
 ::GX::modulePublicApiActivate viewer.dataset_curve_fit DATASET_CURVE_FIT_API_v1
 set ::publication [::GX::datasetPublicationV2PublishSeries $::session math.numeric [dict create dataset_id immutable_source099 contract table.generic storage csv x_values {-1 0 2} y_values {3 2 8} x_variable {variable_id original_time unit s} y_variable {variable_id original_response unit V}]]
 set ::source [dict get [::GX::sessionInspectionDatasetPayload immutable_source099 $::session] path]
 set ::sourceSha [sha $::source]
}
