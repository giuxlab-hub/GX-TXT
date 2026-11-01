// SPDX-License-Identifier: GPL-3.0-or-later
// Additive Acquisition target SDK. Existing Viewer SDK/ABI is unchanged.
#pragma once
#include <cstdint>
#include <map>
#include <string>
#include <vector>
namespace gx {
// Bounded inert metadata, not paths, commands or a source/publication grant.
struct AcquisitionValue {
    enum class Kind { null, text, boolean, integer, real, object, array };
    Kind kind=Kind::null;
    std::string text;
    std::int64_t integer=0;
    double real=0;
    std::map<std::string,AcquisitionValue> fields;
    std::vector<AcquisitionValue> elements;
};
AcquisitionValue acquisition_text(std::string);
AcquisitionValue acquisition_integer(std::int64_t);
AcquisitionValue acquisition_number(double);
AcquisitionValue acquisition_flag(bool);
AcquisitionValue acquisition_object(std::map<std::string,AcquisitionValue> = {});
AcquisitionValue acquisition_array(std::vector<AcquisitionValue> = {});
using AcquisitionResult=AcquisitionValue;
struct SourceDescriptor {
    unsigned source_index=0;
    std::string logical_name,source_sha256;
    std::uint64_t size=0;
    bool full_sha_reviewed=false;
};
struct SourceChunk {
    std::uint64_t offset=0,total_size=0;
    bool eof=false;
    std::vector<std::uint8_t> bytes;
};
struct PreparedVariable {std::string variable_id;std::uint64_t byte_count=0;};
struct PreparedOutput {std::string output_id;std::vector<PreparedVariable> variables;};
struct PreparedReference {std::string output_id;};
struct AcquisitionRequest {
    std::string phase,qualified_profile;
    std::vector<SourceDescriptor> sources;
    AcquisitionValue config,mapping,limits;
};
class AcquisitionHost {
public:
    SourceDescriptor source_info(unsigned source_index) const;
    SourceChunk source_read(unsigned source_index,std::uint64_t offset,unsigned count) const;
    bool cancelled() const;
    void progress(const char* phase,const char* message) const;
    void progress(const char* phase,const char* message,std::uint64_t current,std::uint64_t total) const;
    PreparedOutput prepare_output(const AcquisitionValue& definition,std::uint64_t row_count,const AcquisitionValue& variables) const;
    // Additive nD form: dimensions is {stable_dimension_id: positive size};
    // each Variable declares dimension_ids, with optional consistent rank/shape.
    // Bytes retain canonical little-endian column-major order; never flatten.
    PreparedOutput prepare_output(const AcquisitionValue& definition,const AcquisitionValue& dimensions,const AcquisitionValue& variables) const;
    // Raw typed bytes stay local to the trusted worker's CORE-issued buffer.
    // CORE authorizes each bounded sequential chunk before the local write.
    void output_write(const PreparedOutput& output,const char* variable_id,std::uint64_t offset,const void* bytes,unsigned byte_count) const;
    PreparedReference output_finish(const PreparedOutput& output) const;
    AcquisitionValue helper_call(const char* declared_helper_id,const AcquisitionValue& args) const;
    // Fixed common CORE parser on an already granted source; no path authority.
    // Returns request-local parse_token, row_count and exact source metadata.
    AcquisitionValue scientific_spectrum_parse(unsigned source_index,const char* format,const AcquisitionValue& options) const;
    // Bounded source-data page (x/y arrays), never a publication or Library grant.
    AcquisitionValue scientific_spectrum_read(const char* parse_token,std::uint64_t offset,unsigned count) const;
private:
    void* context_=nullptr;
    int (*dispatch_)(void*,unsigned,const char*,const void*,unsigned,char*,unsigned,unsigned*)=nullptr;
    AcquisitionValue call(unsigned,const AcquisitionValue&,const void* =nullptr,unsigned=0) const;
    friend struct AcquisitionHostAccess;
};
// Authored free callbacks have exactly this signature; manifest binds finite names:
// gx::AcquisitionResult recognize/inspect/import(gx::AcquisitionHost&,const gx::AcquisitionRequest&).
}
