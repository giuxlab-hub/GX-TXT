// SPDX-License-Identifier: GPL-3.0-or-later
// Qualified CFBv3 structural subset. Authentic PRF compatibility UNVERIFIED;
// reviewed source-unit declarations do not establish authentic instrument data.
#include "include/measurement.hpp"
#include "include/prf_decoder.hpp"
#include <cstring>
#include <limits>

namespace scientific_measurement {
namespace {
class PrfGrantedReader final:public gxtxt_prf::Reader {
    gx::AcquisitionHost& host_;
public:
    explicit PrfGrantedReader(gx::AcquisitionHost& host):host_(host){}
    gxtxt_prf::Bytes read(std::uint64_t at,unsigned count)override{
        gxtxt_prf::Bytes out;out.reserve(count);
        while(out.size()<count){
            if(host_.cancelled())throw std::runtime_error("PRF import cancelled");
            auto part=host_.source_read(0,at+out.size(),static_cast<unsigned>(std::min<std::size_t>(65536,count-out.size())));
            if(part.offset!=at+out.size()||part.bytes.empty()||part.bytes.size()>count-out.size())throw std::runtime_error("PRF source range ended early");
            out.insert(out.end(),part.bytes.begin(),part.bytes.end());
        }
        return out;
    }
};
bool finite_prf(double value){auto limit=std::numeric_limits<double>::max();return value>=-limit&&value<=limit;}
void finite_page(const gxtxt_prf::Bytes& bytes){
    if(bytes.size()%8)throw std::runtime_error("PRF partial float64 sample");
    for(std::size_t at=0;at<bytes.size();at+=8){double value;std::memcpy(&value,bytes.data()+at,8);if(!finite_prf(value))throw std::runtime_error("UnsupportedVariant: PRF nonfinite numeric sample; no fill, truncation or normalization performed");}
}
}
gx::AcquisitionResult prf_parse(gx::AcquisitionHost& host,const gx::AcquisitionRequest& request){
    static_assert(sizeof(double)==8&&std::numeric_limits<double>::is_iec559,"PRF preserves IEEE binary64");
    const std::uint16_t endian=1;if(*reinterpret_cast<const unsigned char*>(&endian)!=1)throw std::runtime_error("PRF requires little-endian native transport");
    if(profile(request)!="perkinelmer_prf"||request.sources.size()!=1)throw std::runtime_error("PRF requires its saved profile and one source per request");
    auto source=host.source_info(0);PrfGrantedReader reader(host);gxtxt_prf::Decoder decoder(reader,source.size);auto parsed=decoder.parse();
    const auto time_unit=setting(request,"prf_time_unit"),signal_unit=setting(request,"prf_signal_unit"),signal_quantity=setting(request,"prf_signal_quantity");
    if(!time_unit.empty()&&time_unit!="s"&&time_unit!="min"&&time_unit!="h")throw std::runtime_error("UnsupportedUnit: PRF time unit requires an explicit reviewed s/min/h declaration; no conversion performed");
    const bool unit_reviewed=!time_unit.empty()&&!signal_unit.empty()&&!signal_quantity.empty();
    const std::vector<Field> original={{"time","Time",time_unit,"time","float64",{"sample"}},{"signal",signal_quantity.empty()?"Signal (source quantity unverified)":signal_quantity,signal_unit,"signal","float64",{"sample"}}};
    const auto mapped=mapping(request,original);
    auto metadata=gx::acquisition_object({{"format",gx::acquisition_text("PRF CFBv3 intensity-profile explicit float64 arrays")},
        {"source_sha256",gx::acquisition_text(source.source_sha256)},{"sample_count",gx::acquisition_integer(parsed.count)},
        {"compatibility",gx::acquisition_text("SYNTHETIC_CONTAINER_QUALIFIED; REAL_PRF_UNVERIFIED")},
        {"source_unit_evidence",gx::acquisition_text(unit_reviewed?"explicit reviewed configuration declarations, not inferred from storage/extension/reference converter":"unknown; review actual source time unit, signal unit and quantity before conversion")},
        {"time_unit",gx::acquisition_text(time_unit)},{"signal_unit",gx::acquisition_text(signal_unit)},{"signal_quantity",gx::acquisition_text(signal_quantity)},
        {"x_policy",gx::acquisition_text("exact explicit source float64 coordinates; original order; no interpolation, sorting, resampling or timestamp-origin inference")}});
    if(request.phase=="recognize"||request.phase=="inspect"){
        auto n=std::min<std::uint64_t>(12,parsed.count);auto x=decoder.read_stream(parsed.x,0,static_cast<unsigned>(n*8));auto y=decoder.read_stream(parsed.y,0,static_cast<unsigned>(n*8));finite_page(x);finite_page(y);
        auto preview=gx::acquisition_array();
        for(std::uint64_t i=0;i<n;++i){double xv,yv;std::memcpy(&xv,x.data()+8*i,8);std::memcpy(&yv,y.data()+8*i,8);preview.elements.push_back(gx::acquisition_array({gx::acquisition_number(xv),gx::acquisition_number(yv)}));}
        auto fields=gx::acquisition_array({inspection_field(original[0],1,{parsed.count},{},true),inspection_field(original[1],2,{parsed.count},{original[0].id})});
        return gx::acquisition_object({{"recognized",gx::acquisition_flag(true)},{"format",gx::acquisition_text("perkinelmer_prf")},{"metadata",metadata},{"variables",fields},{"preview_rows",preview}});
    }
    if(!unit_reviewed)throw std::runtime_error("UnsupportedUnit: authentic PRF source units are not established; explicitly review prf_time_unit, prf_signal_unit and prf_signal_quantity. No seconds/RMS/absolute origin guessed");
    auto annotations=gx::acquisition_object({
        {"measurement.source_format",gx::acquisition_text("PRF CFBv3 intensity-profile explicit float64")},
        {"measurement.profile_qualification",gx::acquisition_text("synthetic structural subset qualified; authentic PRF compatibility UNVERIFIED")},
        {"measurement.source_time_unit",gx::acquisition_text(time_unit)},{"measurement.source_signal_unit",gx::acquisition_text(signal_unit)},
        {"measurement.source_signal_quantity",gx::acquisition_text(signal_quantity)},
        {"measurement.source_unit_evidence",gx::acquisition_text("explicit reviewed declarations; values unchanged; no inferred origin or hidden conversion")},
        {"measurement.x_policy",gx::acquisition_text("original explicit X float64/order preserved; no resampling")}});
    annotations.fields["measurement.source_storage_name"]=gx::acquisition_text(parsed.storage_name);
    auto definition=gx::acquisition_object({{"dataset_id",gx::acquisition_text(dataset_id(request))},{"contract",gx::acquisition_text("timeseries.table")},{"structured_metadata",annotations},
        {"notes",gx::acquisition_text("CFBv3 structural subset tested with synthetic containers only. Numeric time coordinate retains the reviewed source unit; it is not HMS elapsed_time or an absolute timestamp. Authentic PRF/reference and shared scientific temporal validation remain separate acceptance gates.")}});
    auto dimensions=gx::acquisition_object({{"sample",gx::acquisition_integer(parsed.count)}});
    auto output=host.prepare_output(definition,dimensions,gx::acquisition_array({field_schema(mapped[0],{},true),field_schema(mapped[1],{mapped[0].id})}));
    for(std::uint64_t offset=0;offset<parsed.count;){
        auto n=static_cast<unsigned>(std::min<std::uint64_t>(4096,parsed.count-offset));
        auto x=decoder.read_stream(parsed.x,offset*8,n*8),y=decoder.read_stream(parsed.y,offset*8,n*8);finite_page(x);finite_page(y);
        host.output_write(output,mapped[0].id.c_str(),offset*8,x.data(),x.size());host.output_write(output,mapped[1].id.c_str(),offset*8,y.data(),y.size());
        offset+=n;host.progress("prepare","Preserving explicit PRF coordinates and signal; authentic compatibility unverified",offset,parsed.count);
    }
    auto finished=host.output_finish(output);
    return gx::acquisition_object({{"metadata",metadata},{"prepared_outputs",gx::acquisition_array({gx::acquisition_object({{"output_id",gx::acquisition_text(finished.output_id)}})})}});
}
}
