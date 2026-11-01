#include "gxtxt_acquisition_sdk_v1.hpp"
#include <stdexcept>
namespace scientific_measurement {gx::AcquisitionResult parse(gx::AcquisitionHost&,const gx::AcquisitionRequest&);}
namespace scientific_measurement {gx::AcquisitionResult sif_parse(gx::AcquisitionHost&,const gx::AcquisitionRequest&);}
namespace scientific_measurement {gx::AcquisitionResult sp_parse(gx::AcquisitionHost&,const gx::AcquisitionRequest&);}
namespace scientific_measurement {gx::AcquisitionResult prf_parse(gx::AcquisitionHost&,const gx::AcquisitionRequest&);}
namespace gx {AcquisitionResult acquisition_dispatch_v1(const std::string& profile,const std::string& phase,AcquisitionHost& host,const AcquisitionRequest& request){
if(profile=="acq.scientific_measurement/spectral_csv"){
if(phase=="recognize")return ::scientific_measurement::parse(host,request);
if(phase=="inspect")return ::scientific_measurement::parse(host,request);
if(phase=="import"||phase=="test")return ::scientific_measurement::parse(host,request);
}
if(profile=="acq.scientific_measurement/jcamp_dx"){
if(phase=="recognize")return ::scientific_measurement::parse(host,request);
if(phase=="inspect")return ::scientific_measurement::parse(host,request);
if(phase=="import"||phase=="test")return ::scientific_measurement::parse(host,request);
}
if(profile=="acq.scientific_measurement/andor_sif"){
if(phase=="recognize")return ::scientific_measurement::sif_parse(host,request);
if(phase=="inspect")return ::scientific_measurement::sif_parse(host,request);
if(phase=="import"||phase=="test")return ::scientific_measurement::sif_parse(host,request);
}
if(profile=="acq.scientific_measurement/perkinelmer_sp"){
if(phase=="recognize")return ::scientific_measurement::sp_parse(host,request);
if(phase=="inspect")return ::scientific_measurement::sp_parse(host,request);
if(phase=="import"||phase=="test")return ::scientific_measurement::sp_parse(host,request);
}
if(profile=="acq.scientific_measurement/perkinelmer_prf"){
if(phase=="recognize")return ::scientific_measurement::prf_parse(host,request);
if(phase=="inspect")return ::scientific_measurement::prf_parse(host,request);
if(phase=="import"||phase=="test")return ::scientific_measurement::prf_parse(host,request);
}
throw std::runtime_error("Compiled profile/phase is not admitted");}}
