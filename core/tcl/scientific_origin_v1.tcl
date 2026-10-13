# SPDX-License-Identifier: GPL-3.0-or-later
# Scientific extension of the existing Object Origin representation/authority.
proc ::GX::documentOriginRead {document} {
    return [datasetPublicationV2DictDefault [interactiveDocumentRead $document] origin [_originUnknown]]
}
proc ::GX::datasetOriginRead {dataset {session {}}} {
    set session [_sessionInspectionRequire $session]
    return [datasetPublicationV2DictDefault [datasetMetadataRead $session $dataset] origin.definition [_originUnknown]]
}
proc ::GX::resourceOriginRead {resource} {
    interactiveDocumentResourceInfo $resource
    return [datasetPublicationV2DictDefault [dict get $resource metadata] origin [_originUnknown]]
}
proc ::GX::_scientificResourceOrigin {document kind} {
    set owner [interactiveDocumentRead $document]
    return [_originCreate $kind [dict create document_id $document revision [dict get $owner revision] origin_snapshot [documentOriginRead $document]]]
}
proc ::GX::_scientificImportedOrigin {} {
    set origin [_originUnknown]
    dict lappend origin events [dict create kind receive_resource installation_id [installationIdentityCurrent] at [projectTimestamp]]
    return $origin
}
proc ::GX::_scientificPublicationMetadata {session dataset metadata sources {preserveExisting 1}} {
    # Replacement does not rewrite an existing Dataset's original creator.
    if {$preserveExisting && [datasetField $dataset id {}] ne {}} {
        dict set metadata origin.definition [datasetOriginRead $dataset $session]
    } elseif {![dict exists $metadata origin.definition]} {
        set parents {};foreach id $sources {dict set parents $id [datasetOriginRead $id $session]}
        dict set metadata origin.definition [_originCreate dataset_publication [dict create source_dataset_origins $parents source_origin [_originUnknown] session_origin [sessionOriginRead $session]]]
    }
    return $metadata
}
