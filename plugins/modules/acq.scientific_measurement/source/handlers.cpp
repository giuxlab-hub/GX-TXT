// SPDX-License-Identifier: GPL-3.0-or-later
// Authored Acquisition callbacks; all CSV/JCAMP parsing belongs to CORE.
#include "include/measurement.hpp"
#include "include/source_metadata.hpp"
#include <algorithm>
#include <stdexcept>
#include <limits>
#include <string>
#include <vector>

namespace scientific_measurement {
static_assert(sizeof(double) == 8 && std::numeric_limits<double>::is_iec559, "Scientific float64 transport requires IEEE binary64");
using V = gx::AcquisitionValue;
using K = gx::AcquisitionValue::Kind;

const V& member(const V& value, const std::string& name) {
    if (value.kind != K::object) throw std::runtime_error("Expected typed object: " + name);
    auto found = value.fields.find(name);
    if (found == value.fields.end()) throw std::runtime_error("Missing typed field: " + name);
    return found->second;
}
std::string text(const V& value) {
    if (value.kind != K::text) throw std::runtime_error("Expected literal text field");
    return value.text;
}
std::string setting(const gx::AcquisitionRequest& request, const std::string& key, const std::string& fallback) {
    if (request.config.kind != K::object) throw std::runtime_error("Expected saved typed Module configuration");
    auto item = request.config.fields.find(key);
    return item == request.config.fields.end() ? fallback : text(item->second);
}
std::uint64_t integer(const V& value) {
    if (value.kind != K::integer || value.integer < 0) throw std::runtime_error("Expected nonnegative bounded count");
    return static_cast<std::uint64_t>(value.integer);
}
std::string profile(const gx::AcquisitionRequest& request) {
    auto separator = request.qualified_profile.rfind('/');
    if (separator == std::string::npos) throw std::runtime_error("Expected qualified saved format profile");
    return request.qualified_profile.substr(separator + 1);
}
V spectrum_options(const gx::AcquisitionRequest& request, const std::string& format) {
    auto options = gx::acquisition_object({
        {"spectrum_id", gx::acquisition_text(setting(request, "spectrum_id", "measurement"))},
        {"display_name", gx::acquisition_text(setting(request, "display_name", "Scientific measurement"))}
    });
    for (const std::string& key : {"spectrum_kind", "x_quantity", "x_unit", "y_quantity", "y_representation", "y_unit"}) {
        auto value = setting(request, key);
        // CSV has no authoritative physical metadata, so declarations are
        // required there. JCAMP source headers must be decoded by CORE first;
        // saved declarations are consistency checks, never relabelling options.
        if (format == "csv" && !value.empty()) options.fields[key] = gx::acquisition_text(value);
    }
    if (format == "csv") {
        for (const std::string& key : {"x_column", "y_column", "delimiter"}) options.fields[key] = gx::acquisition_text(setting(request, key));
        const auto& header = member(request.config, "header");
        if (header.kind != K::boolean) throw std::runtime_error("Header must be a typed boolean");
        options.fields["header"] = gx::acquisition_text(header.integer ? "1" : "0");
    }
    return options;
}
V variable(const std::string& id, const std::string& label, const std::string& unit, bool coordinate) {
    auto schema = gx::acquisition_object({
        {"name", gx::acquisition_text(label)}, {"dtype", gx::acquisition_text("float64")},
        {"dimension_ids", gx::acquisition_array({gx::acquisition_text("spectral_point")})},
        {"unit", gx::acquisition_text(unit)},
        {"semantic_role", gx::acquisition_text(coordinate ? "independent" : "measured")}
    });
    if (coordinate) schema.fields["coordinate_role"] = gx::acquisition_text("coordinate");
    else schema.fields["coordinate_variable_ids"] = gx::acquisition_array({gx::acquisition_text("spectral_x")});
    return gx::acquisition_object({{"variable_id", gx::acquisition_text(id)}, {"schema", schema}});
}
std::vector<double> numeric_page(const V& page, const std::string& name, std::uint64_t count) {
    const auto& values = member(page, name);
    if (values.kind != K::array || values.elements.size() != count) throw std::runtime_error("CORE scientific page count mismatch");
    std::vector<double> out;
    out.reserve(values.elements.size());
    for (const auto& value : values.elements) {
        if (value.kind == K::real) out.push_back(value.real);
        else if (value.kind == K::integer) out.push_back(static_cast<double>(value.integer));
        else throw std::runtime_error("CORE scientific page contains a nonnumeric value");
    }
    return out;
}

// Real Builder-bound callback shared by the two independently declared formats.
// Vendor formats are added as separate source adapters, never guessed here.
gx::AcquisitionResult parse(gx::AcquisitionHost& host, const gx::AcquisitionRequest& request) {
    const std::uint16_t endianProbe = 1;
    if (*reinterpret_cast<const unsigned char*>(&endianProbe) != 1) throw std::runtime_error("This native build requires little-endian typed output");
    if (request.sources.size() != 1) throw std::runtime_error("This spectrum profile requires one source per request; use the ordinary file batch queue");
    const auto selected = profile(request);
    const std::string format = selected == "spectral_csv" ? "csv" : selected == "jcamp_dx" ? "jcamp" : "";
    if (format.empty()) throw std::runtime_error("No implemented source decoder for selected profile");
    host.progress("decode", "Using the shared CORE scientific source parser");
    const auto parsed = host.scientific_spectrum_parse(0, format.c_str(), spectrum_options(request, format));
    const auto token = text(member(parsed, "parse_token"));
    const auto count = integer(member(parsed, "row_count"));
    const auto& fields = member(parsed, "fields");
    if (format == "jcamp") {
        for (const std::string& key : {"spectrum_kind", "x_quantity", "x_unit", "y_quantity", "y_representation", "y_unit"}) {
            const auto declared = setting(request, key);
            const auto observed = text(member(fields, key));
            if (!declared.empty() && declared != observed) {
                throw std::runtime_error("ConflictingSourceDeclaration: " + key + " is declared as '" + declared + "' but JCAMP source metadata is '" + observed + "'. Clear the stale CSV declaration or enter the exact observed value; no numeric conversion or relabelling is performed");
            }
        }
    }
    const auto xname = text(member(fields, "x_quantity"));
    const auto yname = text(member(fields, "y_quantity"));
    const auto xunit = text(member(fields, "x_unit"));
    const auto yunit = text(member(fields, "y_unit"));
    const std::vector<Field> expected={
        {"spectral_x",xname,xunit,"independent","float64",{"spectral_point"}},
        {"spectral_y",yname,yunit,"measured","float64",{"spectral_point"}}
    };
    auto mapped=mapping(request,expected);
    auto metadata = gx::acquisition_object({
        {"profile", gx::acquisition_text(selected)},
        {"source_sha256", member(parsed, "source_sha256")},
        {"parser_sha256", member(parsed, "parser_sha256")},
        {"sample_count", gx::acquisition_integer(static_cast<std::int64_t>(count))},
        {"fields", fields}, {"source_metadata", member(parsed, "metadata")},
        {"source_provenance", member(parsed, "provenance")}
    });
    if (request.phase == "recognize" || request.phase == "inspect") {
        const auto page = host.scientific_spectrum_read(token.c_str(), 0, static_cast<unsigned>(std::min<std::uint64_t>(count, 12)));
        auto x = numeric_page(page, "x", integer(member(page, "row_count")));
        auto y = numeric_page(page, "y", integer(member(page, "row_count")));
        auto preview = gx::acquisition_array();
        for (std::size_t i = 0; i < x.size(); ++i) preview.elements.push_back(gx::acquisition_array({gx::acquisition_number(x[i]), gx::acquisition_number(y[i])}));
        auto variables = gx::acquisition_array({
            gx::acquisition_object({{"source_column", gx::acquisition_integer(1)}, {"original_header", gx::acquisition_text(xname)}, {"canonical", gx::acquisition_text("spectral_x")}, {"unit", gx::acquisition_text(xunit)}, {"semantic_role", gx::acquisition_text("independent")}}),
            gx::acquisition_object({{"source_column", gx::acquisition_integer(2)}, {"original_header", gx::acquisition_text(yname)}, {"canonical", gx::acquisition_text("spectral_y")}, {"unit", gx::acquisition_text(yunit)}, {"semantic_role", gx::acquisition_text("measured")}})
        });
        // Even an empty prepared_outputs key is forbidden during inspection.
        return gx::acquisition_object({{"recognized", gx::acquisition_flag(true)}, {"format", gx::acquisition_text(format)}, {"metadata", metadata}, {"variables", variables}, {"preview_rows", preview}});
    }
    std::string dataset = setting(request, "spectrum_id", "measurement");
    if (request.mapping.kind == K::object) {
        auto proposed = request.mapping.fields.find("dataset_id");
        if (proposed != request.mapping.fields.end() && proposed->second.kind == K::text && !proposed->second.text.empty()) dataset = proposed->second.text;
    }
    auto annotations = spectrum_fields(text(member(fields,"spectrum_kind")),xname,xunit,yname,text(member(fields,"y_representation")),yunit,mapped[0].id,mapped[1].id);
    annotations.fields["measurement.decoder_sha256"]=member(parsed,"parser_sha256");
    annotations.fields["measurement.source_sha256"]=member(parsed,"source_sha256");
    annotations.fields["measurement.profile"]=gx::acquisition_text(selected);
    for (const auto& item : fields.fields) if (item.second.kind == K::text) annotations.fields["measurement." + item.first] = item.second;
    const auto& original = member(parsed, "metadata");
    if(original.kind!=K::object)throw std::runtime_error("Original source metadata must remain a complete text map");
    std::map<std::string,std::string> originalText;
    for(const auto& item:original.fields){if(item.second.kind!=K::text)throw std::runtime_error("Original source metadata must remain a complete text map");originalText.emplace(item.first,item.second.text);}
    for(const auto& item:source_metadata_projection(originalText))annotations.fields[item.first]=gx::acquisition_text(item.second);
    auto definition = gx::acquisition_object({
        {"dataset_id", gx::acquisition_text(dataset)}, {"contract", gx::acquisition_text("spectrum.scientific")},
        {"structured_metadata", annotations},
        {"notes", gx::acquisition_text("Decoded by the shared CORE CSV/JCAMP parser; original RAW and scientific semantics retained.")}
    });
    auto variables = gx::acquisition_array({field_schema(mapped[0],{},true),field_schema(mapped[1],{mapped[0].id})});
    auto dimensions = gx::acquisition_object({{"spectral_point", gx::acquisition_integer(static_cast<std::int64_t>(count))}});
    auto output = host.prepare_output(definition, dimensions, variables);
    for (std::uint64_t offset = 0; offset < count;) {
        if (host.cancelled()) throw std::runtime_error("Measurement import cancelled");
        auto page = host.scientific_spectrum_read(token.c_str(), offset, static_cast<unsigned>(std::min<std::uint64_t>(count - offset, 2048)));
        auto got = integer(member(page, "row_count"));
        if (!got || got > count - offset) throw std::runtime_error("CORE scientific page ended before declared sample count");
        auto x = numeric_page(page, "x", got);auto y = numeric_page(page, "y", got);
        host.output_write(output, mapped[0].id.c_str(), offset * sizeof(double), x.data(), static_cast<unsigned>(x.size() * sizeof(double)));
        host.output_write(output, mapped[1].id.c_str(), offset * sizeof(double), y.data(), static_cast<unsigned>(y.size() * sizeof(double)));
        offset += got;
        host.progress("prepare", "Staging exact decoded X/Y under existing CORE typed buffers", offset, count);
    }
    const auto finished = host.output_finish(output);
    return gx::acquisition_object({{"prepared_outputs", gx::acquisition_array({gx::acquisition_object({{"output_id", gx::acquisition_text(finished.output_id)}})})}, {"metadata", metadata}});
}
}
