# GX-TXT public IR Library Type Provider API v1.
# SPDX-License-Identifier: GPL-3.0-or-later
namespace eval ::GX::IRLibraryTypeProviderAPIv1 {}
proc ::GX::IRLibraryTypeProviderAPIv1::apiInfo {} {
    return [dict create api_name IR_LIBRARY_TYPE_PROVIDER_API_v1 api_version 1 \
        provider_id library.spectroscopy.ir.reference library_type spectroscopy.ir.reference]
}
proc ::GX::IRLibraryTypeProviderAPIv1::listLibraries {} {
    return [::GX::ScientificLibraryManagerAPIv1::queryCompatibleLibraries spectroscopy.ir.reference]
}
proc ::GX::IRLibraryTypeProviderAPIv1::listEntries {libraryId} {
    return [::GX::ScientificLibraryManagerAPIv1::listLibraryEntries $libraryId]
}
proc ::GX::IRLibraryTypeProviderAPIv1::readSpectrum {libraryId spectrumId} {
    return [::GX::ScientificLibraryManagerAPIv1::readLibrarySpectrum $libraryId $spectrumId]
}
