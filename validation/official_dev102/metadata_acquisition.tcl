set png [file normalize [lindex $argv 2]]
source [file join [file dirname [info script]] .. official_dev099 project_common.tcl]
try {
    set session [::GX::createNewSession acquisition_metadata102]
    set before [::GX::sha256File $png]
    set ids [::GX::acquisitionHandlerImportSourcesToSession acq.image_binary $session [list $png] acquired_image image.raster {}]
    set actors [::GX::datasetMetadataContributors $session acquired_image]
    check {[dict get $actors source.original_filename original_contributor] eq {module:acq.image_binary} && [dict get $actors image.format last_contributor] eq {module:acq.image_binary}} {Actual Acquisition Handler attributes supplied fields to its authenticated module}
    ::GX::datasetFilePublicationPublish $session viewer.curve_digitizer [dict create dataset_id file_image contract image.raster format png storage_kind binary media_type image/png source_file $png structured_metadata {ordinary_annotation {File module contribution}}]
    check {[dict get [::GX::datasetMetadataContributors $session file_image] ordinary_annotation original_contributor] eq {module:viewer.curve_digitizer}} {Actual File Publication attributes ordinary supplied metadata independently of key prefixes}
    ::GX::datasetMetadataUpdate $session acquired_image {user_annotation {Reviewed by user}}
    check {[::GX::datasetField acquired_image producer_module [::GX::datasetField acquired_image source_module {}]] eq {acq.image_binary} && [dict get [::GX::datasetMetadataContributors $session acquired_image] user_annotation last_contributor] eq {User}} {Later user metadata preserves the acquired Dataset producer}
    set definition {dataset_id descendant_table contract table.generic storage csv dataset_namespace module/math.numeric/studies/example x_values {0 1} y_values {3 4} x_variable {variable_id x unit s} y_variable {variable_id y unit V}}
    ::GX::datasetPublicationV2PublishSeries $session math.numeric $definition
    set definition [dict remove $definition dataset_namespace];dict set definition replace_owned 1;dict set definition storage {};dict set definition y_values {7 8}
    ::GX::datasetPublicationV2PublishSeries $session math.numeric $definition
    check {[::GX::datasetNamespaceGet $session descendant_table] eq {module/math.numeric/studies/example} && [::GX::datasetField descendant_table storage_provider {}] eq {csv}} {Automatic owned replacement preserves descendant scientific namespace and CSV provider}
    dict set definition dataset_id foreign_namespace;dict set definition replace_owned 0;dict set definition dataset_namespace module/plot.dataset/studies/example
    check {[catch {::GX::datasetPublicationV2PublishSeries $session math.numeric $definition}]} {A module cannot publish into another producer's descendant namespace}
    check {[::GX::sha256File $png] eq $before} {Acquisition/File publication preserve the exact input image}
    save result [dict create status PASS checks $checks session $session]
} on error {message options} {save result [dict create status FAIL checks $checks details [dict get $options -errorinfo]];puts stderr [dict get $options -errorinfo];exit 1}
exit
