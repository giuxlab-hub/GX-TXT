// SPDX-License-Identifier: GPL-3.0-or-later
// PEPE SP source adapter; PRF/CFB is a different, separately declared format.
#include "include/measurement.hpp"
#include "include/sp_decoder.hpp"
#include <algorithm>
#include <cstdio>
#include <limits>

namespace scientific_measurement {
namespace {
gxtxt_sp::Bytes bytes(gx::AcquisitionHost& host,std::uint64_t at,std::uint64_t count){gxtxt_sp::Bytes out;out.reserve(count);while(out.size()<count){if(host.cancelled())throw std::runtime_error("SP import cancelled");auto got=host.source_read(0,at+out.size(),static_cast<unsigned>(std::min<std::uint64_t>(65536,count-out.size())));if(got.offset!=at+out.size()||got.bytes.empty()||got.bytes.size()>count-out.size())throw std::runtime_error("SP source range ended early");out.insert(out.end(),got.bytes.begin(),got.bytes.end());}return out;}
std::string decimal(double value){char output[64];auto n=std::snprintf(output,sizeof output,"%.17g",value);if(n<=0||n>=static_cast<int>(sizeof output))throw std::runtime_error("SP finite header number cannot be represented");return {output,static_cast<std::size_t>(n)};}
class GrantedReader final:public gxtxt_sp::Reader {gx::AcquisitionHost& host;public:explicit GrantedReader(gx::AcquisitionHost& value):host(value){}gxtxt_sp::Bytes read(std::uint64_t at,unsigned count)override{return bytes(host,at,count);}};
}
gx::AcquisitionResult sp_parse(gx::AcquisitionHost& host,const gx::AcquisitionRequest& request){
    static_assert(sizeof(double)==8&&std::numeric_limits<double>::is_iec559,"SP preserves IEEE binary64");
    const std::uint16_t endian=1;if(*reinterpret_cast<const unsigned char*>(&endian)!=1)throw std::runtime_error("SP requires little-endian native transport");
    if(profile(request)!="perkinelmer_sp"||request.sources.size()!=1)throw std::runtime_error("SP requires its saved profile and one source per request");
    const auto source=host.source_info(0);
    GrantedReader reader(host);gxtxt_sp::Decoder decoder(reader,source.size);
    const auto parsed=decoder.parse();
    std::string xquantity,xunit;
    if((parsed.x_label=="cm-1"||parsed.x_label=="CM-1")&&parsed.x_unit_type==10){xquantity="wavenumber";xunit="cm^-1";}
    else if((parsed.x_label=="nm"||parsed.x_label=="NM")&&parsed.x_unit_type==11){xquantity="wavelength";xunit="nm";}
    else throw std::runtime_error("UnsupportedUnit: SP coordinate label/enum is not a qualified source-unit combination; no unit guessed");
    if((parsed.y_label!="A"&&parsed.y_label!="a")||parsed.y_unit_type!=1)throw std::runtime_error("UnsupportedUnit: this SP profile qualifies explicit absorbance label A/enum1 only; other ordinates require source evidence");
    const std::string yquantity="absorbance",yrepresentation="absorbance",yunit="1";
    const std::vector<Field> original={{"spectral_x",xquantity,xunit,"independent","float64",{"spectral_point"}},{"spectral_y",yquantity,yunit,"measured","float64",{"spectral_point"}}};
    const auto mapped=mapping(request,original);
    auto metadata=gx::acquisition_object({{"format",gx::acquisition_text("PerkinElmer PEPE constant-interval float64")},{"source_sha256",gx::acquisition_text(source.source_sha256)},
        {"description",gx::acquisition_text(parsed.description)},{"alias",gx::acquisition_text(parsed.alias)},{"file_type",gx::acquisition_text(parsed.file_type)},
        {"source_data_type",gx::acquisition_integer(parsed.data_type)},{"source_x_unit_type",gx::acquisition_integer(parsed.x_unit_type)},{"source_y_unit_type",gx::acquisition_integer(parsed.y_unit_type)},
        {"source_x_label",gx::acquisition_text(parsed.x_label)},{"source_y_label",gx::acquisition_text(parsed.y_label)},
        {"first_x",gx::acquisition_number(parsed.first)},{"last_x",gx::acquisition_number(parsed.last)},{"source_step",gx::acquisition_number(parsed.step)},
        {"sample_count",gx::acquisition_integer(parsed.count)},{"payload_offset",gx::acquisition_integer(parsed.payload_offset)},{"payload_bytes",gx::acquisition_integer(parsed.payload_bytes)},
        {"history_bytes_uninterpreted",gx::acquisition_integer(parsed.history_bytes)},{"annotation_bytes_uninterpreted",gx::acquisition_integer(parsed.annotation_bytes)},
        {"x_policy",gx::acquisition_text("source first + index * source interval; checked against end/count; original order, no sorting/resampling")}});
    if(request.phase=="recognize"||request.phase=="inspect"){
        auto raw=bytes(host,parsed.payload_offset,std::min<std::uint64_t>(parsed.count,12)*8);auto preview=gx::acquisition_array();
        for(std::size_t i=0;i<raw.size()/8;++i){double y;std::memcpy(&y,raw.data()+i*8,8);preview.elements.push_back(gx::acquisition_array({gx::acquisition_number(parsed.first+static_cast<double>(i)*parsed.step),gxtxt_sp::finite(y)?gx::acquisition_number(y):V{}}));}
        auto fields=gx::acquisition_array({inspection_field(original[0],1,{parsed.count},{},true),inspection_field(original[1],2,{parsed.count},{original[0].id})});
        return gx::acquisition_object({{"recognized",gx::acquisition_flag(true)},{"format",gx::acquisition_text("perkinelmer_sp")},{"metadata",metadata},{"variables",fields},{"preview_rows",preview}});
    }
    auto annotations=spectrum_fields("spectral_signal",xquantity,xunit,yquantity,yrepresentation,yunit,mapped[0].id,mapped[1].id);
    annotations.fields["measurement.source_format"]=gx::acquisition_text("PerkinElmer PEPE SP constant-interval float64");
    annotations.fields["measurement.source_x_label"]=gx::acquisition_text(parsed.x_label);annotations.fields["measurement.source_y_label"]=gx::acquisition_text(parsed.y_label);
    annotations.fields["measurement.source_first_x"]=gx::acquisition_text(decimal(parsed.first));annotations.fields["measurement.source_last_x"]=gx::acquisition_text(decimal(parsed.last));annotations.fields["measurement.source_interval"]=gx::acquisition_text(decimal(parsed.step));
    annotations.fields["measurement.alias"]=gx::acquisition_text(parsed.alias);
    annotations.fields["measurement.x_policy"]=gx::acquisition_text("first + index * source interval; original order preserved; no sorting or resampling");
    annotations.fields["measurement.uninterpreted_history_bytes"]=gx::acquisition_text(std::to_string(parsed.history_bytes));annotations.fields["measurement.uninterpreted_annotation_bytes"]=gx::acquisition_text(std::to_string(parsed.annotation_bytes));
    annotations.fields["measurement.processing_policy"]=gx::acquisition_text("Stored signal already embodies source processing; opaque source history retained in original RAW, no correction applied or invented instrument/model");
    auto definition=gx::acquisition_object({{"dataset_id",gx::acquisition_text(dataset_id(request))},{"contract",gx::acquisition_text("spectrum.scientific")},{"structured_metadata",annotations},
        {"notes",gx::acquisition_text("Qualified single-dataset PEPE SP subset. Original float64 signal and coordinate direction preserved; exact source units, not a fluorescence-only interpretation. PRF is not parsed as SP.")}});
    auto dimensions=gx::acquisition_object({{"spectral_point",gx::acquisition_integer(parsed.count)}});
    const auto output=host.prepare_output(definition,dimensions,gx::acquisition_array({field_schema(mapped[0],{},true),field_schema(mapped[1],{mapped[0].id})}));
    for(std::uint64_t offset=0;offset<parsed.count;){auto n=std::min<std::uint64_t>(8192,parsed.count-offset);std::vector<double> x(n);for(std::uint64_t i=0;i<n;++i)x[i]=parsed.first+static_cast<double>(offset+i)*parsed.step;
        auto y=bytes(host,parsed.payload_offset+offset*8,n*8);host.output_write(output,mapped[0].id.c_str(),offset*8,x.data(),n*8);host.output_write(output,mapped[1].id.c_str(),offset*8,y.data(),y.size());offset+=n;host.progress("prepare","Preserving original SP float64 signal/order",offset,parsed.count);}
    const auto finished=host.output_finish(output);
    return gx::acquisition_object({{"metadata",metadata},{"prepared_outputs",gx::acquisition_array({gx::acquisition_object({{"output_id",gx::acquisition_text(finished.output_id)}})})}});
}
}
