// SPDX-License-Identifier: GPL-3.0-or-later
// Original bounded MS-CFBv3 reader of public Microsoft structures; no COM/FS.
// Authentic PRF compatibility UNVERIFIED. Implementation is a separate normal
// source translation unit to keep consumer ASTs bounded; no policy/limit change.
#pragma once
#include <cstdint>
#include <string>
#include <vector>
namespace gxtxt_prf {
using Bytes=std::vector<std::uint8_t>;
using Sector=std::uint32_t;
class Reader {public:virtual ~Reader()=default;virtual Bytes read(std::uint64_t,unsigned)=0;};
struct Stream {std::uint64_t size=0;bool mini=false;std::vector<Sector> sectors;};
struct Profile {std::uint64_t count=0;Stream x,y;std::string storage_name;};
class DecoderImpl;
class Decoder {
public:
    Decoder(Reader&,std::uint64_t);
    ~Decoder();
    Decoder(const Decoder&)=delete;
    Decoder& operator=(const Decoder&)=delete;
    Profile parse();
    Bytes read_stream(const Stream&,std::uint64_t,unsigned);
private:
    DecoderImpl* impl_;
};
}
