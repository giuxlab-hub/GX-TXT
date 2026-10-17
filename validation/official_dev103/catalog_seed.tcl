# Public Acquisition/Publication owners; no invented user measurements.
proc catalogSeed {directory} {
    ::GX::datasetPreviewCacheInit;::GX::configurationSet preview.cache_enabled 0
    ::GX::acquisitionHandlerImportSourceToSession acq.image_binary $::GX::currentSession [file join $directory synthetic_image.png] catalog_image image.raster {}
    ::GX::acquisitionHandlerImportSourceToSession acq.nmr_multidimensional $::GX::currentSession [file join $directory synthetic_catalog_spectrum.ft2] catalog_nmr spectrum.nmr_multidimensional {}
    ::GX::datasetMetadataUpdate $::GX::currentSession catalog_nmr {fixture.synthetic 1 fixture.purpose {Viewer opening only; no acquired measurement}}
    set plan [::GX::datasetPublicationV2Prepare $::GX::currentSession math.numeric {dataset_id catalog_xyz contract table.generic storage hdf5 structured_metadata {fixture.synthetic 1}}]
    set writer [::GX::datasetPublicationV2OpenWriter $plan]
    ::GX::datasetPublicationV2DeclareDimension $writer row 9
    foreach {variable unit} {x m y m z V} {::GX::datasetPublicationV2DeclareVariable $writer $variable [dict create dtype float64 unit $unit dimension_ids row]}
    ::GX::datasetPublicationV2WriteRange $writer x 0 {0 1 2 0 1 2 0 1 2}
    ::GX::datasetPublicationV2WriteRange $writer y 0 {0 0 0 1 1 1 2 2 2}
    ::GX::datasetPublicationV2WriteRange $writer z 0 {1 3 5 4 6 8 7 9 11}
    ::GX::datasetPublicationV2Finalize $writer
}
