// SPDX-License-Identifier: GPL-3.0-or-later
// Authored SourceGrant decoder: observed SIF65567 primary float32 payload only.
#include "include/measurement.hpp"
#include "include/sif_decoder.hpp"
#include <algorithm>
#include <cstring>
#include <limits>

namespace scientific_measurement {
namespace {
bool finite_control(double value){const auto maximum=std::numeric_limits<double>::max();return value<=maximum&&value>=-maximum;}
std::vector<std::uint8_t> source_bytes(gx::AcquisitionHost& host,std::uint64_t offset,std::uint64_t count) {
    std::vector<std::uint8_t> out;out.reserve(static_cast<std::size_t>(count));
    while(out.size()<count){
        if(host.cancelled())throw std::runtime_error("SIF import cancelled");
        auto chunk=host.source_read(0,offset+out.size(),static_cast<unsigned>(std::min<std::uint64_t>(65536,count-out.size())));
        if(chunk.offset!=offset+out.size()||chunk.bytes.empty()||chunk.bytes.size()>count-out.size())throw std::runtime_error("SIF source chunk does not close the reviewed byte range");
        out.insert(out.end(),chunk.bytes.begin(),chunk.bytes.end());
    }
    return out;
}
V texts(const std::vector<std::string>& input){auto result=gx::acquisition_array();for(const auto& text:input)result.elements.push_back(gx::acquisition_text(text));return result;}
V integers(const std::vector<std::int64_t>& input){auto result=gx::acquisition_array();for(auto value:input)result.elements.push_back(gx::acquisition_integer(value));return result;}
struct SignalSemantics {std::string unit,quantity,representation;};
SignalSemantics signal_semantics(const gx::AcquisitionRequest& request,const gxtxt_sif::Image& image) {
    SignalSemantics result;
    if(image.data_type=="Counts")result={"count","detector counts","detector_counts"};
    else if(image.data_type=="Counts (Bg corrected per second)")result={"count/s","background-corrected detector count rate","background_corrected_count_rate"};
    const auto declaredUnit=setting(request,"sif_unknown_y_unit");
    const auto declaredQuantity=setting(request,"sif_unknown_y_quantity");
    const auto declaredRepresentation=setting(request,"sif_unknown_y_representation");
    if(!result.unit.empty()){
        if((!declaredUnit.empty()&&declaredUnit!=result.unit)||(!declaredQuantity.empty()&&declaredQuantity!=result.quantity)||(!declaredRepresentation.empty()&&declaredRepresentation!=result.representation))throw std::runtime_error("UnsupportedUnit: observed SIF signal semantics cannot be relabelled by an unknown-unit declaration");
    }else result={declaredUnit,declaredQuantity,declaredRepresentation};
    return result;
}
void write_vector(gx::AcquisitionHost& host,const gx::PreparedOutput& output,const std::string& id,const void* values,std::uint64_t bytes){
    auto p=static_cast<const std::uint8_t*>(values);
    for(std::uint64_t offset=0;offset<bytes;){if(host.cancelled())throw std::runtime_error("SIF import cancelled");auto count=static_cast<unsigned>(std::min<std::uint64_t>(65536,bytes-offset));host.output_write(output,id.c_str(),offset,p+offset,count);offset+=count;}
}
}

gx::AcquisitionResult sif_parse(gx::AcquisitionHost& host,const gx::AcquisitionRequest& request) {
    static_assert(sizeof(float)==4&&std::numeric_limits<float>::is_iec559,"SIF preserves IEEE binary32");
    static_assert(sizeof(double)==8&&std::numeric_limits<double>::is_iec559,"SIF coordinates use IEEE binary64");
    const std::uint16_t endian=1;if(*reinterpret_cast<const unsigned char*>(&endian)!=1)throw std::runtime_error("SIF requires little-endian native transport");
    if(profile(request)!="andor_sif"||request.sources.size()!=1)throw std::runtime_error("SIF requires its saved profile and one source per request");
    const auto source=host.source_info(0);
    auto prefix=source_bytes(host,0,std::min<std::uint64_t>(source.size,gxtxt_sif::header_prefix_bytes));
    const auto image=gxtxt_sif::parse(prefix,source.size);
    // Multiple ROI containers are diagnosed, never flattened into a false image.
    if(image.regions.size()!=1)throw std::runtime_error("UnsupportedVariant: this qualified primary-image SIF adapter requires one ROI; multiple-ROI source is preserved without publication");
    const auto& roi=image.regions[0];const bool spectrum=roi.height==1&&image.frames==1&&roi.width>=2;
    const auto axisMode=setting(request,"sif_axis_mode","pixel");
    if(axisMode!="pixel"&&axisMode!="calibrated")throw std::runtime_error("UnsupportedVariant: select pixel or explicitly unit-qualified calibrated SIF coordinates");
    const bool calibrated=axisMode=="calibrated";
    const auto xunit=calibrated?setting(request,"sif_calibration_unit"):"px";
    const auto xquantity=calibrated?setting(request,"sif_calibration_quantity"):"detector pixel";
    if(calibrated&&(xunit.empty()||xquantity.empty()||image.coefficients.size()!=4))throw std::runtime_error("UnsupportedUnit: calibrated SIF coordinates require four finite source coefficients and an explicitly reviewed physical quantity/unit");
    if(calibrated&&(roi.left!=1||roi.xbin!=1))throw std::runtime_error("UnsupportedVariant: physical calibration of offset/binned detector X is not qualified; source pixel coordinates remain available");
    const auto semantics=signal_semantics(request,image);
    if(spectrum&&(semantics.unit.empty()||semantics.quantity.empty()||semantics.representation.empty()))throw std::runtime_error("UnsupportedUnit: unknown SIF signal semantics require explicit source unit, quantity and representation before spectral publication");
    std::vector<double> x(roi.width),y(roi.height);
    for(std::uint64_t i=0;i<roi.width;++i){auto pixel=static_cast<double>(roi.left+i*roi.xbin);x[i]=calibrated?gxtxt_sif::calibrated_x(image,pixel):pixel;if(!finite_control(x[i]))throw std::runtime_error("SIF calibration overflows a finite coordinate");}
    for(std::uint64_t i=0;i<roi.height;++i)y[i]=static_cast<double>(roi.top+i*roi.ybin);
    auto dimensions=gx::acquisition_object({{"detector_x",gx::acquisition_integer(roi.width)}});
    std::vector<std::string> signalDims={"detector_x"};std::vector<std::uint64_t> signalShape={roi.width};
    if(!spectrum){dimensions.fields["detector_y"]=gx::acquisition_integer(roi.height);signalDims.push_back("detector_y");signalShape.push_back(roi.height);}
    if(image.frames>1){dimensions.fields["frame"]=gx::acquisition_integer(image.frames);signalDims.push_back("frame");signalShape.push_back(image.frames);}
    std::vector<Field> original={{"detector_x",xquantity,xunit,"independent","float64",{"detector_x"}},
        {"signal",image.data_type,semantics.unit,"measured","float32",signalDims}};
    if(!spectrum)original.push_back({"detector_y","detector row","px","independent","float64",{"detector_y"}});
    if(image.frames>1){original.push_back({"frame_index","frame index","1","independent","int64",{"frame"}});original.push_back({"frame_timestamp_raw","vendor timestamp (unit not declared)","","auxiliary","int64",{"frame"}});if(!image.frame_ticks_raw.empty())original.push_back({"frame_tick_raw","vendor frame tick (unit not declared)","","auxiliary","int64",{"frame"}});}
    const auto mapped=mapping(request,original);
    std::vector<std::string> coords={mapped[0].id};if(!spectrum)coords.push_back(mapped[2].id);if(image.frames>1)coords.push_back(mapped[3].id);
    auto metadata=gx::acquisition_object({{"format",gx::acquisition_text("andor_sif65567_primary_float32")},{"source_sha256",gx::acquisition_text(source.source_sha256)},
        {"signal_representation",gx::acquisition_text(semantics.representation)},{"signal_source_label",gx::acquisition_text(image.data_type)},
        {"calibration_coefficients",texts(image.coefficient_text)},{"calibration_raw",gx::acquisition_text(image.calibration_raw)},
        {"axis_mode",gx::acquisition_text(axisMode)},{"calibration_unit_source",gx::acquisition_text(calibrated?"explicit reviewed source-unit declaration":"pixel coordinates; no physical calibration unit inferred")},
        {"width",gx::acquisition_integer(roi.width)},{"height",gx::acquisition_integer(roi.height)},{"frames",gx::acquisition_integer(image.frames)},
        {"detector_width",gx::acquisition_integer(image.detector_width)},{"detector_height",gx::acquisition_integer(image.detector_height)},
        {"x_bin",gx::acquisition_integer(roi.xbin)},{"y_bin",gx::acquisition_integer(roi.ybin)},
        {"payload_offset",gx::acquisition_integer(image.payload_offset)},{"trailing_vendor_bytes",gx::acquisition_integer(image.trailing_vendor_bytes)},
        {"opaque_user_text_bytes",gx::acquisition_integer(image.opaque_user_text_bytes)},{"timestamps_raw",integers(image.timestamps_raw)},{"frame_ticks_raw",integers(image.frame_ticks_raw)}});
    auto variables=gx::acquisition_array();
    for(std::size_t i=0;i<mapped.size();++i)variables.elements.push_back(field_schema(mapped[i],i==1?coords:std::vector<std::string>{},i==0||i==2||i==3));
    if(request.phase=="recognize"||request.phase=="inspect"){
        auto fields=gx::acquisition_array();
        for(std::size_t i=0;i<original.size();++i){std::vector<std::uint64_t> shape=i==1?signalShape:std::vector<std::uint64_t>{i==0?roi.width:i==2?roi.height:image.frames};fields.elements.push_back(inspection_field(original[i],i+1,shape,i==1?coords:std::vector<std::string>{},i==0||i==2||i==3));}
        // Metadata exposes real shape; a bounded scalar preview is not a table
        // contract or a flattened delivery of an image/stack.
        auto raw=source_bytes(host,image.payload_offset,std::min<std::uint64_t>(image.total_pixels,12)*4);auto preview=gx::acquisition_array();
        for(std::size_t i=0;i<raw.size();i+=4){float value;std::memcpy(&value,raw.data()+i,4);preview.elements.push_back(finite_control(value)?gx::acquisition_number(value):V{});}
        return gx::acquisition_object({{"recognized",gx::acquisition_flag(true)},{"format",gx::acquisition_text("andor_sif")},{"metadata",metadata},{"variables",fields},{"preview_values",preview}});
    }
    auto annotations=spectrum?spectrum_fields("detector_signal",xquantity,xunit,semantics.quantity,semantics.representation,semantics.unit,mapped[0].id,mapped[1].id):gx::acquisition_object();
    annotations.fields["measurement.source_format"]=gx::acquisition_text("Andor SIF65567 primary float32");
    annotations.fields["measurement.signal_source_label"]=gx::acquisition_text(image.data_type);
    annotations.fields["measurement.signal_representation"]=gx::acquisition_text(semantics.representation);
    annotations.fields["measurement.calibration_raw"]=gx::acquisition_text(image.calibration_raw);
    annotations.fields["measurement.detector_type"]=gx::acquisition_text(image.detector_type);
    annotations.fields["measurement.detector_temperature_raw"]=gx::acquisition_text(image.detector_temperature_raw);
    annotations.fields["measurement.exposure_seconds_raw"]=gx::acquisition_text(image.exposure_seconds_raw);
    std::string timestampText,tickText;
    for(auto value:image.timestamps_raw){if(!timestampText.empty())timestampText+=' ';timestampText+=std::to_string(value);}
    for(auto value:image.frame_ticks_raw){if(!tickText.empty())tickText+=' ';tickText+=std::to_string(value);}
    annotations.fields["measurement.timestamps_raw_unit_unknown"]=gx::acquisition_text(timestampText);
    annotations.fields["measurement.frame_ticks_raw_unit_unknown"]=gx::acquisition_text(tickText);
    annotations.fields["measurement.axis_mode"]=gx::acquisition_text(axisMode);
    annotations.fields["measurement.pixel_coordinate_policy"]=gx::acquisition_text("One-based source ROI bin starts; no inferred bin-center or physical coordinate");
    annotations.fields["measurement.detector_shape"]=gx::acquisition_text(std::to_string(image.detector_width)+" "+std::to_string(image.detector_height));
    annotations.fields["measurement.primary_shape"]=gx::acquisition_text(std::to_string(roi.width)+" "+std::to_string(roi.height)+" "+std::to_string(image.frames));
    annotations.fields["measurement.frame_axis_label_raw"]=gx::acquisition_text(image.frame_axis);
    annotations.fields["measurement.image_axis_label_raw"]=gx::acquisition_text(image.image_axis);
    annotations.fields["measurement.roi_bounds_binning"]=gx::acquisition_text(std::to_string(roi.left)+" "+std::to_string(roi.top)+" "+std::to_string(roi.right)+" "+std::to_string(roi.bottom)+" "+std::to_string(roi.xbin)+" "+std::to_string(roi.ybin));
    annotations.fields["measurement.trailing_vendor_bytes"]=gx::acquisition_text(std::to_string(image.trailing_vendor_bytes));
    annotations.fields["measurement.opaque_user_text"]=gx::acquisition_text("Not decoded or published; full original RAW retained by acquisition owner");
    auto definition=gx::acquisition_object({{"dataset_id",gx::acquisition_text(dataset_id(request))},{"contract",gx::acquisition_text(spectrum?"spectrum.scientific":"measurement.numeric_array")},{"structured_metadata",annotations},
        {"notes",gx::acquisition_text("Original primary signal float32 bytes, explicit dimensions and source pixel order preserved; no inferred physical calibration, timestamp units, background correction or auxiliary-stream decoding.")}});
    const auto output=host.prepare_output(definition,dimensions,variables);
    write_vector(host,output,mapped[0].id,x.data(),x.size()*8);
    for(std::uint64_t offset=0,total=image.total_pixels*4;offset<total;){auto raw=source_bytes(host,image.payload_offset+offset,std::min<std::uint64_t>(65536,total-offset));host.output_write(output,mapped[1].id.c_str(),offset,raw.data(),raw.size());offset+=raw.size();host.progress("prepare","Preserving original SIF float32 primary pixels",offset,total);}
    if(!spectrum)write_vector(host,output,mapped[2].id,y.data(),y.size()*8);
    if(image.frames>1){std::vector<std::int64_t> frames(image.frames);for(std::uint64_t i=0;i<image.frames;++i)frames[i]=i;write_vector(host,output,mapped[3].id,frames.data(),frames.size()*8);write_vector(host,output,mapped[4].id,image.timestamps_raw.data(),image.frames*8);if(!image.frame_ticks_raw.empty())write_vector(host,output,mapped[5].id,image.frame_ticks_raw.data(),image.frames*8);}
    const auto finished=host.output_finish(output);
    return gx::acquisition_object({{"metadata",metadata},{"prepared_outputs",gx::acquisition_array({gx::acquisition_object({{"output_id",gx::acquisition_text(finished.output_id)}})})}});
}
}
