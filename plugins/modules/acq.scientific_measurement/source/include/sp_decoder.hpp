// SPDX-License-Identifier: GPL-3.0-or-later AND MIT
// Bounded PEPE block decoder. Format references: cheminfo/spc-parser
// src/perkinElmer/{parseBinary,parseBlocks,decodeMembers,constants}.ts at
// Git tree89040729ebdfae52bb279e505f6574a7decc2ea1. No JS dependency.
/*
MIT License

Copyright (c) 2021 cheminfo

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/
#pragma once
#include <cstdint>
#include <cstring>
#include <limits>
#include <map>
#include <stdexcept>
#include <string>
#include <vector>

namespace gxtxt_sp {
using Bytes=std::vector<std::uint8_t>;
class Reader {public:virtual ~Reader()=default;virtual Bytes read(std::uint64_t,unsigned)=0;};
constexpr std::uint64_t max_source=32ULL*1024*1024;
inline bool finite(double value){const auto max=std::numeric_limits<double>::max();return value<=max&&value>=-max;}
inline std::uint16_t u16(const Bytes& b,std::size_t at=0){if(at>b.size()||b.size()-at<2)throw std::runtime_error("SP truncated uint16");return b[at]|(static_cast<std::uint16_t>(b[at+1])<<8);}
inline std::uint32_t u32(const Bytes& b,std::size_t at=0){if(at>b.size()||b.size()-at<4)throw std::runtime_error("SP truncated uint32");return static_cast<std::uint32_t>(b[at])|(static_cast<std::uint32_t>(b[at+1])<<8)|(static_cast<std::uint32_t>(b[at+2])<<16)|(static_cast<std::uint32_t>(b[at+3])<<24);}
inline double f64(const Bytes& b,std::size_t at){if(at>b.size()||b.size()-at<8)throw std::runtime_error("SP truncated float64");double out;std::memcpy(&out,b.data()+at,8);if(!finite(out))throw std::runtime_error("SP nonfinite header coordinate");return out;}
inline std::string literal(const Bytes& raw,std::size_t at,std::size_t n){if(at>raw.size()||n>raw.size()-at||n>4096)throw std::runtime_error("SP string exceeds bounded member");while(n&&raw[at+n-1]==0)--n;std::string out;for(std::size_t i=0;i<n;++i){auto c=raw[at+i];if(c<32||c>=127)throw std::runtime_error("UnsupportedVariant: SP metadata encoding is not qualified ASCII");out+=static_cast<char>(c);}return out;}
struct Block {unsigned id=0;std::uint64_t offset=0,size=0;};
struct Spectrum {
    std::string description,alias,file_type,x_label,y_label;
    std::uint64_t count=0,payload_offset=0,payload_bytes=0,history_bytes=0,annotation_bytes=0;
    std::uint32_t data_type=0,x_unit_type=0,y_unit_type=0;
    double first=0,last=0,step=0;
};
class Decoder {
public:
    Decoder(Reader& reader,std::uint64_t size):read(reader),source_size(size){}
    Spectrum parse(){
        if(source_size<44||source_size>max_source)throw std::runtime_error("SP source is outside the32MiB bound");
        auto header=get(0,44);if(literal(header,0,4)!="PEPE")throw std::runtime_error("UnsupportedVariant: selected SP source has no PEPE binary signature; PRF is a distinct format");
        Spectrum result;result.description=literal(header,4,40);std::map<unsigned,Block> members;unsigned datasets=0;
        for(const auto& block:blocks(44,source_size)){
            if(block.id==120){
                if(++datasets!=1)throw std::runtime_error("UnsupportedVariant: this qualified SP profile requires one constant-interval dataset; multiple datasets are not silently dropped");
                for(const auto& member:blocks(block.offset,block.offset+block.size))if(!members.emplace(member.id,member).second)throw std::runtime_error("SP duplicate dataset member");
            }else if(block.id<121||block.id>126)throw std::runtime_error("UnsupportedVariant: unknown SP top-level block");
        }
        if(datasets!=1)throw std::runtime_error("SP has no spectral dataset block120");
        for(const auto& member:members){
            auto id=member.first;
            if(id<35697||id>35714||id==35712)throw std::runtime_error("UnsupportedVariant: unknown or invalid-region SP dataset member");
        }
        result.data_type=integer(required(members,35697));
        if(result.data_type!=1&&result.data_type!=16)throw std::runtime_error("UnsupportedVariant: SP data type is outside the qualified UV/IR constant-interval layouts");
        auto range=value(required(members,35698),18);if(u16(range)!=29981||range.size()!=18)throw std::runtime_error("SP coordinate range type/length disagrees");
        result.first=f64(range,2);result.last=f64(range,10);
        auto step=value(required(members,35700),10);if(step.size()!=10||(u16(step)!=29979&&u16(step)!=29980))throw std::runtime_error("SP coordinate interval type/length disagrees");result.step=f64(step,2);
        result.count=integer(required(members,35701));if(result.count<2||result.count>1000000)throw std::runtime_error("SP point count exceeds supported2..1000000 bounds");
        if(result.step==0)throw std::runtime_error("SP zero coordinate step is not a constant-interval spectrum");
        const auto endpoint=result.first+static_cast<double>(result.count-1)*result.step;
        const auto abs=[](double v){return v<0?-v:v;};
        auto scale=abs(result.first);if(abs(result.last)>scale)scale=abs(result.last);if(abs(result.step)>scale)scale=abs(result.step);
        // Relative source-roundoff allowance: an absolute +1 floor would admit
        // inconsistent tiny-unit grids. Multiply epsilon first to avoid overflow.
        const auto tolerance=(scale*std::numeric_limits<double>::epsilon())*64*result.count;
        if(!finite(endpoint)||abs(endpoint-result.last)>tolerance)throw std::runtime_error("SP start/interval/count disagree with actual end; no resampling or axis sorting performed");
        result.x_label=string(required(members,35703));result.y_label=string(required(members,35704));
        result.file_type=string(required(members,35707));if(result.file_type!="Spectrum"&&result.file_type!="SPECTRUM")throw std::runtime_error("UnsupportedVariant: SP file type is not the qualified spectrum layout");
        auto alias=members.find(35713);if(alias!=members.end())result.alias=string(alias->second);
        result.x_unit_type=integer(required(members,35705));result.y_unit_type=integer(required(members,35706));
        const auto& data=required(members,35708);if(data.size<6)throw std::runtime_error("SP signal typed header is truncated");auto prefix=get(data.offset,6);
        if(u16(prefix)!=29974)throw std::runtime_error("SP signal is not a typed float64 coordinate array");
        result.payload_bytes=u32(prefix,2);result.payload_offset=data.offset+6;
        if(result.payload_bytes!=result.count*8||data.size!=result.payload_bytes+6)throw std::runtime_error("SP signal byte length/point count do not close");
        auto history=members.find(35711);if(history!=members.end())result.history_bytes=history->second.size;
        auto annotations=members.find(35714);if(annotations!=members.end()){
            auto tag=get(annotations->second.offset,2);if(u16(tag)!=29971||annotations->second.size>65536)throw std::runtime_error("UnsupportedVariant: SP annotation type/length is not qualified");
            result.annotation_bytes=annotations->second.size;
        }
        return result;
    }
private:
    Reader& read;std::uint64_t source_size=0,header_bytes=0;
    Bytes get(std::uint64_t at,unsigned count){if(at>source_size||count>source_size-at||header_bytes+count>786432)throw std::runtime_error("SP bounded header read exceeds source/control budget");auto bytes=read.read(at,count);if(bytes.size()!=count)throw std::runtime_error("SP source header ended early");header_bytes+=count;return bytes;}
    std::vector<Block> blocks(std::uint64_t at,std::uint64_t end){std::vector<Block> out;while(at<end){if(end-at<6||out.size()>=256)throw std::runtime_error("SP trailing/truncated/excessive block headers");auto b=get(at,6);auto n=u32(b,2);if(n>2147483647||n>end-at-6)throw std::runtime_error("SP negative or truncated block length");out.push_back({u16(b),at+6,n});at+=6+n;}return out;}
    const Block& required(const std::map<unsigned,Block>& blocks,unsigned id){auto at=blocks.find(id);if(at==blocks.end())throw std::runtime_error("SP required typed member missing");return at->second;}
    Bytes value(const Block& b,unsigned max){if(b.size>max||b.size<2)throw std::runtime_error("SP bounded typed member length disagrees");return get(b.offset,static_cast<unsigned>(b.size));}
    // The authentic IR dataset stores its datatype as UINT29996 with a two-byte
    // payload. Retain this observed legacy short form without reading into the
    // next block; other tagged integer widths remain explicit.
    std::uint32_t integer(const Block& b){auto raw=value(b,6);auto tag=u16(raw);if((tag==29973||tag==29998||tag==29996)&&raw.size()==4)return u16(raw,2);if((tag==29978||tag==29995||tag==29996||tag==29997)&&raw.size()==6){auto out=u32(raw,2);if((tag==29995||tag==29997)&&out>2147483647)throw std::runtime_error("SP negative typed count");return out;}throw std::runtime_error("SP integer type/length is not qualified");}
    std::string string(const Block& b){auto raw=value(b,4100);if(raw.size()<4||u16(raw)!=29987||u16(raw,2)+4!=raw.size())throw std::runtime_error("SP literal string type/length disagrees");return literal(raw,4,u16(raw,2));}
};
}
