// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once
#include <cstdint>
#include <stdexcept>
#include <string>
#include <set>
#include <vector>
namespace scientific_measurement {
using V = gx::AcquisitionValue;
using K = gx::AcquisitionValue::Kind;
const V& member(const V&,const std::string&);
std::string text(const V&);
std::string setting(const gx::AcquisitionRequest&,const std::string&,const std::string& = "");
std::uint64_t integer(const V&);
std::string profile(const gx::AcquisitionRequest&);
V variable(const std::string&,const std::string&,const std::string&,bool);

struct Field {
    std::string id, label, unit, role, dtype;
    std::vector<std::string> dimensions;
};
inline std::string row_text(const V& row,const std::string& key,const std::string& fallback="") {
    auto found=row.fields.find(key);return found==row.fields.end()?fallback:text(found->second);
}
// Source mappings are reviewed input, not a conversion authority. Publish IDs
// and labels may change consistently; physical/type/role changes must not be
// silently applied to unchanged numeric bytes.
inline std::vector<Field> mapping(const gx::AcquisitionRequest& request,const std::vector<Field>& expected) {
    if(request.mapping.kind!=K::object)throw std::runtime_error("Expected reviewed source mapping object");
    auto rows=request.mapping.fields.find("variables");
    if(rows==request.mapping.fields.end()||(rows->second.kind==K::array&&rows->second.elements.empty()))return expected;
    if(rows->second.kind!=K::array||rows->second.elements.size()!=expected.size())throw std::runtime_error("This profile preserves every declared coordinate/signal field; reinspect and retain all fields");
    auto out=expected;std::vector<bool> seen(expected.size(),false);
    for(const auto& row:rows->second.elements){
        if(row.kind!=K::object)throw std::runtime_error("Source mapping row must be a typed object");
        const auto column=row_text(row,"source_column");std::size_t end=0;
        auto n=std::stoul(column,&end,10);
        if(end!=column.size()||n<1||n>expected.size()||seen[n-1])throw std::runtime_error("Source mapping column identity changed; reinspect this source");
        const auto& source=expected[n-1];seen[n-1]=true;
        const auto original=row_text(row,"original_header");
        if(!original.empty()&&original!=source.label)throw std::runtime_error("Source mapping header changed; reinspect instead of retargeting a prior row");
        const auto unit=row_text(row,"unit",source.unit);
        if(unit!=source.unit)throw std::runtime_error("Unit conversion is not performed by this source profile; keep the observed source unit or use the shared conversion owner");
        const auto role=row_text(row,"semantic_role",source.role);
        if(role!=source.role)throw std::runtime_error("Changing a coordinate/signal role without a transformation is not admitted");
        const auto dtype=row_text(row,"dtype",source.dtype);
        if(!dtype.empty()&&dtype!=source.dtype)throw std::runtime_error("This profile preserves the original numeric dtype; reviewed dtype conversion is not implemented here");
        for(const auto& key:{"time_origin","value_format","to_canonical","from_canonical","canonical_unit"})if(!row_text(row,key).empty())throw std::runtime_error("This source profile does not apply time or physical-value transforms");
        // Rank/shape are source facts, not an alternative reshape instruction.
        // The current mapping UI serializes these as text when present.
        const auto rank=row_text(row,"rank");
        if(!rank.empty()&&rank!=std::to_string(source.dimensions.size()))throw std::runtime_error("Reshaping the source through a mapping row is not supported");
        for(const auto& key:{"shape","dimension_ids","coordinate_variable_ids","coordinate_role"})if(!row_text(row,key).empty())throw std::runtime_error("Array/coordinate remapping is not performed here; retain the source-defined dimensions and associations");
        const auto scale=row_text(row,"scale","1");const auto offset=row_text(row,"offset","0");
        if(scale!="1"||offset!="0")throw std::runtime_error("This source profile does not apply scalar scale/offset transforms");
        const auto canonical=row_text(row,"canonical",row_text(row,"variable_id",source.id));
        if(canonical.empty())throw std::runtime_error("A published variable alias cannot be empty");
        out[n-1].id=canonical;
        out[n-1].label=row_text(row,"display_label",row_text(row,"name",source.label));
    }
    std::set<std::string> aliases;for(const auto& field:out)if(!aliases.insert(field.id).second)throw std::runtime_error("Duplicate published variable alias");
    return out;
}
inline V spectrum_fields(const std::string& kind,const std::string& xq,const std::string& xu,const std::string& yq,const std::string& yr,const std::string& yu,const std::string& xid,const std::string& yid) {
    return gx::acquisition_object({{"spectrum_kind",gx::acquisition_text(kind)},{"x_quantity",gx::acquisition_text(xq)},{"x_unit",gx::acquisition_text(xu)},{"y_quantity",gx::acquisition_text(yq)},{"y_representation",gx::acquisition_text(yr)},{"y_unit",gx::acquisition_text(yu)},{"spectral_x_variable_id",gx::acquisition_text(xid)},{"spectral_y_variable_id",gx::acquisition_text(yid)}});
}
inline std::string dataset_id(const gx::AcquisitionRequest& request) {
    auto id=setting(request,"spectrum_id","measurement");
    if(request.mapping.kind==K::object){auto value=request.mapping.fields.find("dataset_id");if(value!=request.mapping.fields.end()&&value->second.kind==K::text&&!value->second.text.empty())id=value->second.text;}
    return id;
}
inline V field_schema(const Field& field,const std::vector<std::string>& coordinates={},bool coordinate=false) {
    auto ids=gx::acquisition_array();for(const auto& id:field.dimensions)ids.elements.push_back(gx::acquisition_text(id));
    auto schema=gx::acquisition_object({{"name",gx::acquisition_text(field.label)},{"dtype",gx::acquisition_text(field.dtype)},{"dimension_ids",ids},{"semantic_role",gx::acquisition_text(field.role)}});
    if(!field.unit.empty())schema.fields["unit"]=gx::acquisition_text(field.unit);
    if(coordinate)schema.fields["coordinate_role"]=gx::acquisition_text("coordinate");
    if(!coordinates.empty()){auto refs=gx::acquisition_array();for(const auto& id:coordinates)refs.elements.push_back(gx::acquisition_text(id));schema.fields["coordinate_variable_ids"]=refs;}
    return gx::acquisition_object({{"variable_id",gx::acquisition_text(field.id)},{"schema",schema}});
}
inline V inspection_field(const Field& field,unsigned column,const std::vector<std::uint64_t>& shape,const std::vector<std::string>& coordinates={},bool coordinate=false) {
    auto variable=field_schema(field,coordinates,coordinate);auto result=member(variable,"schema");
    result.fields["source_column"]=gx::acquisition_integer(column);
    result.fields["original_header"]=gx::acquisition_text(field.label);
    result.fields["canonical"]=gx::acquisition_text(field.id);
    result.fields["rank"]=gx::acquisition_integer(field.dimensions.size());
    auto sizes=gx::acquisition_array();for(auto n:shape)sizes.elements.push_back(gx::acquisition_integer(n));result.fields["shape"]=sizes;
    return result;
}
}
