// SPDX-License-Identifier: GPL-3.0-or-later
// Reversible projection of CORE-admitted parser text maps to the existing
// one-field-per-line Dataset Metadata owner. No source parser/store/serializer.
#pragma once
#include <map>
#include <stdexcept>
#include <string>

namespace scientific_measurement {
inline std::string metadata_utf8_hex(const std::string& bytes){
    if(bytes.size()>49152)throw std::runtime_error("Original source metadata exceeds48KiB");
    static const char digits[]="0123456789abcdef";std::string out;out.reserve(bytes.size()*2);
    for(unsigned char byte:bytes){out+=digits[byte>>4];out+=digits[byte&15];}return out;
}
inline std::map<std::string,std::string> source_metadata_projection(const std::map<std::string,std::string>& original){
    std::map<std::string,std::string> out;std::size_t budget=2;
    // Count the SDK's quoted text size only; SDK remains the actual JSON owner.
    const auto quoted_size=[](const std::string& text){std::size_t n=2;for(unsigned char c:text)n+=c<32?6:(c=='"'||c=='\\'?2:1);return n;};
    const auto put=[&](const std::string& key,const std::string& value){
        const auto size=quoted_size(key)+quoted_size(value)+2;
        if(size>49152-budget)throw std::runtime_error("Reversible source metadata projection exceeds48KiB; no fields truncated");
        budget+=size;if(!out.emplace(key,value).second)throw std::runtime_error("Source metadata projection collision");
    };
    put("measurement.source_metadata_key_encoding","utf8_hex_v1");
    put("measurement.source_metadata_value_encoding","utf8_hex_v1");
    for(const auto& item:original){
        if(item.first.find_first_of("\r\n")!=std::string::npos||item.first.find('\0')!=std::string::npos)throw std::runtime_error("Original source metadata label contains an invalid line break or NUL");
        const auto token="k_"+metadata_utf8_hex(item.first);
        put("measurement.source_metadata."+token,metadata_utf8_hex(item.second));
        put("measurement.source_metadata_key."+token,item.first);
    }
    return out;
}
}
