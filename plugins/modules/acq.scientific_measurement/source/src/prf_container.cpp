// SPDX-License-Identifier: GPL-3.0-or-later
// Original bounded MS-CFBv3 implementation. No COM, filesystem or third-party reader.
#include "include/prf_decoder.hpp"
#include <algorithm>
#include <stdexcept>
namespace gxtxt_prf {
constexpr Sector free_sector=0xffffffffU,end_chain=0xfffffffeU,fat_sector=0xfffffffdU,difat_sector=0xfffffffcU;
constexpr std::uint64_t max_source=32ULL*1024*1024;
inline std::uint16_t u16(const Bytes& b,std::size_t at){if(at>b.size()||b.size()-at<2)throw std::runtime_error("PRF truncated uint16");return b[at]|(std::uint16_t(b[at+1])<<8);}
inline Sector u32(const Bytes& b,std::size_t at){if(at>b.size()||b.size()-at<4)throw std::runtime_error("PRF truncated uint32");return Sector(b[at])|(Sector(b[at+1])<<8)|(Sector(b[at+2])<<16)|(Sector(b[at+3])<<24);}
inline std::uint64_t u64(const Bytes& b,std::size_t at){return u32(b,at)|(std::uint64_t(u32(b,at+4))<<32);}
inline std::string name(const Bytes& b,std::size_t at){
    auto n=u16(b,at+64);if(n<2||n>64||(n&1)||u16(b,at+n-2)!=0)throw std::runtime_error("PRF malformed UTF-16 directory name");
    std::string result;
    for(std::size_t p=0;p+2<n;p+=2){
        std::uint32_t c=u16(b,at+p);
        if(c>=0xd800&&c<=0xdbff){if(p+4>=n)throw std::runtime_error("PRF unpaired UTF-16 high surrogate");auto low=u16(b,at+p+2);if(low<0xdc00||low>0xdfff)throw std::runtime_error("PRF malformed UTF-16 pair");c=0x10000+((c-0xd800)<<10)+(low-0xdc00);p+=2;}
        else if(c>=0xdc00&&c<=0xdfff)throw std::runtime_error("PRF unpaired UTF-16 low surrogate");
        if(!c||c=='/'||c=='\\'||c==':'||c=='!')throw std::runtime_error("PRF invalid compound directory name");
        if(c<0x80)result+=static_cast<char>(c);
        else if(c<0x800){result+=static_cast<char>(0xc0|(c>>6));result+=static_cast<char>(0x80|(c&63));}
        else if(c<0x10000){result+=static_cast<char>(0xe0|(c>>12));result+=static_cast<char>(0x80|((c>>6)&63));result+=static_cast<char>(0x80|(c&63));}
        else{result+=static_cast<char>(0xf0|(c>>18));result+=static_cast<char>(0x80|((c>>12)&63));result+=static_cast<char>(0x80|((c>>6)&63));result+=static_cast<char>(0x80|(c&63));}
    }
    return result;
}
struct Entry {std::string name;unsigned type=0;Sector left=free_sector,right=free_sector,child=free_sector,start=end_chain;Bytes clsid;std::uint64_t size=0;};
class DecoderImpl {
public:
    DecoderImpl(Reader& reader,std::uint64_t size):reader_(reader),size_(size){}
    Profile parse(){
        if(size_<1536||size_>max_source||(size_%512))throw std::runtime_error("PRF CFB source must be sector-aligned within32MiB");
        count_=static_cast<Sector>(size_/512-1);owners_.assign(count_,0);
        auto h=get(0,512);
        const Bytes signature={0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1};
        if(!std::equal(signature.begin(),signature.end(),h.begin()))throw std::runtime_error("UnsupportedVariant: selected PRF has no compound-file signature; SP is a distinct format");
        if(u16(h,26)!=3||u16(h,30)!=9)throw std::runtime_error("UnsupportedVariant: only CFBv3/512-byte sectors are qualified");
        if(u16(h,28)!=0xfffe||u16(h,32)!=6||u32(h,40)!=0||u32(h,56)!=4096)throw std::runtime_error("PRF inconsistent CFB header fields");
        for(unsigned p=8;p<24;++p)if(h[p])throw std::runtime_error("PRF reserved header CLSID is nonzero");
        for(unsigned p=34;p<40;++p)if(h[p])throw std::runtime_error("PRF reserved header bytes are nonzero");
        const auto fat_count=u32(h,44),dif_count=u32(h,72);
        if(!fat_count||fat_count>512||fat_count>count_||dif_count>count_)throw std::runtime_error("PRF excessive FAT/DIFAT count");
        std::vector<Sector> fats,difs;
        auto add_fat=[&](Sector value){if(value==free_sector)return;if(fats.size()>=fat_count)throw std::runtime_error("PRF DIFAT contains surplus FAT sectors");claim(value,1);fats.push_back(value);};
        for(unsigned p=76;p<512;p+=4)add_fat(u32(h,p));
        auto next=u32(h,68);
        for(Sector n=0;n<dif_count;++n){claim(next,2);difs.push_back(next);auto block=sector(next);for(unsigned p=0;p<508;p+=4)add_fat(u32(block,p));next=u32(block,508);}
        if((dif_count&&next!=end_chain)||(!dif_count&&next!=end_chain&&next!=free_sector)||fats.size()!=fat_count)throw std::runtime_error("PRF DIFAT count/closure disagrees");
        for(auto id:fats){auto block=sector(id);for(unsigned p=0;p<512;p+=4)fat_.push_back(u32(block,p));}
        if(fat_.size()<count_)throw std::runtime_error("PRF FAT does not cover source sectors");
        // MS-CFB2.3: allocated FAT entries cannot describe sectors past EOF.
        for(std::size_t id=count_;id<fat_.size();++id)if(fat_[id]!=free_sector)throw std::runtime_error("PRF FAT entry past source EOF is not FREESECT");
        for(auto id:fats)if(fat_[id]!=fat_sector)throw std::runtime_error("PRF FAT sector marker disagrees");
        for(auto id:difs)if(fat_[id]!=difat_sector)throw std::runtime_error("PRF DIFAT sector marker disagrees");
        const auto directory=chain(u32(h,48),0,3,256);
        for(auto id:directory){auto b=sector(id);for(unsigned at=0;at<512;at+=128){
            Entry entry;entry.type=b[at+66];
            if(entry.type){
                if(entry.type!=1&&entry.type!=2&&entry.type!=5)throw std::runtime_error("PRF invalid directory object type");
                if(b[at+67]>1)throw std::runtime_error("PRF invalid directory color flag");
                entry.name=name(b,at);entry.left=u32(b,at+68);entry.right=u32(b,at+72);entry.child=u32(b,at+76);
                entry.clsid=Bytes(b.begin()+at+80,b.begin()+at+96);entry.start=u32(b,at+116);entry.size=u64(b,at+120);
                if(entry.size>max_source||(entry.size>>32))throw std::runtime_error("PRF CFBv3 stream size exceeds source bound");
                if(entry.type==2&&entry.child!=free_sector)throw std::runtime_error("PRF stream has directory children");
                if(entry.type==1&&entry.size)throw std::runtime_error("PRF storage object has a stream size");
            }
            entries_.push_back(entry);
        }}
        if(entries_.empty()||entries_[0].type!=5||entries_[0].left!=free_sector||entries_[0].right!=free_sector)throw std::runtime_error("PRF missing or malformed root storage");
        parents_.assign(entries_.size(),free_sector);parents_[0]=0;
        std::vector<std::pair<Sector,Sector>> pending={{entries_[0].child,0}};
        while(!pending.empty()){
            auto item=pending.back();pending.pop_back();auto id=item.first;
            if(id==free_sector)continue;
            if(!id||id>=entries_.size()||parents_[id]!=free_sector||!entries_[id].type||entries_[id].type==5)throw std::runtime_error("PRF directory graph is cyclic, aliased or invalid");
            parents_[id]=item.second;const auto& entry=entries_[id];
            pending.push_back({entry.left,item.second});pending.push_back({entry.right,item.second});
            if(entry.type==1)pending.push_back({entry.child,id});
        }
        for(Sector id=1;id<entries_.size();++id)if(entries_[id].type&&parents_[id]==free_sector)throw std::runtime_error("PRF active directory entry is unreachable");
        const auto mini_count=u32(h,64);
        if(mini_count>count_)throw std::runtime_error("PRF excessive MiniFAT count");
        const auto minis=chain(u32(h,60),mini_count,4,count_);
        for(auto id:minis){auto block=sector(id);for(unsigned p=0;p<512;p+=4)mini_fat_.push_back(u32(block,p));}
        root_.size=entries_[0].size;
        root_.sectors=chain(entries_[0].start,(root_.size+511)/512,5,count_);
        mini_owners_.assign(static_cast<std::size_t>((root_.size+63)/64),false);
        // Qualified subset: no allocation may describe bytes outside the root
        // mini-stream. MS-CFB2.4/3.4 define this allocator and show free tail slots.
        for(std::size_t id=mini_owners_.size();id<mini_fat_.size();++id)if(mini_fat_[id]!=free_sector)throw std::runtime_error("UnsupportedVariant: PRF MiniFAT entry past root mini-stream extent is not FREESECT");
        streams_.resize(entries_.size());
        for(Sector id=1;id<entries_.size();++id)if(entries_[id].type==2)streams_[id]=make_stream(entries_[id]);
        // Enumerate the actual graph, never assume the first compound storage is
        // the instrument profile and never activate this inert CLSID.
        const Bytes profile_guid={0x6a,0x25,0x5d,0xac,0x4e,0x80,0xd0,0x11,0x88,0xf2,0x00,0x20,0xaf,0xc9,0xa5,0xcc};
        Sector selected=free_sector;
        for(Sector id=1;id<entries_.size();++id)if(parents_[id]==0&&entries_[id].type==1&&entries_[id].clsid==profile_guid){if(selected!=free_sector)throw std::runtime_error("PRF ambiguous intensity-profile storages");selected=id;}
        if(selected==free_sector)throw std::runtime_error("UnsupportedVariant: no direct PRF intensity-profile storage");
        std::vector<std::string> names;std::vector<Sector> ids;
        for(Sector id=1;id<entries_.size();++id)if(parents_[id]==selected){
            auto key=entries_[id].name;for(auto& c:key)if(c>='a'&&c<='z')c=static_cast<char>(c-'a'+'A');
            if(std::find(names.begin(),names.end(),key)!=names.end())throw std::runtime_error("PRF ambiguous profile member names");
            names.push_back(key);ids.push_back(id);
        }
        auto required=[&](const std::string& key)->const Stream&{auto at=std::find(names.begin(),names.end(),key);if(at==names.end())throw std::runtime_error("PRF required stream missing: "+key);auto id=ids[static_cast<std::size_t>(at-names.begin())];if(entries_[id].type!=2)throw std::runtime_error("PRF required stream is not a stream: "+key);return streams_[id];};
        const auto& contents=required("CONTENTS");
        if(contents.size<232)throw std::runtime_error("PRF CONTENTS lacks the declared point count");
        auto prefix=read_stream(contents,0,232);auto n=u32(prefix,228);
        if(n<2||n>1000000)throw std::runtime_error("PRF declared point count exceeds2..1000000");
        Profile result;result.count=n;result.storage_name=entries_[selected].name;result.x=required("PROP36");result.y=required("PROP37");
        if(result.x.size!=std::uint64_t(n)*8||result.y.size!=std::uint64_t(n)*8)throw std::runtime_error("PRF explicit X/Y byte counts disagree with CONTENTS; no truncation performed");
        return result;
    }
    Bytes read_stream(const Stream& stream,std::uint64_t offset,unsigned count){
        if(offset>stream.size||count>stream.size-offset||count>1048576)throw std::runtime_error("PRF stream read is outside admitted bounds");
        Bytes result;result.reserve(count);std::uint64_t physical=0;unsigned run=0;
        auto flush=[&](){if(run){auto bytes=raw(physical,run);result.insert(result.end(),bytes.begin(),bytes.end());run=0;}};
        while(count){
            auto width=stream.mini?64U:512U;auto index=static_cast<std::size_t>(offset/width);auto within=static_cast<unsigned>(offset%width);
            if(index>=stream.sectors.size())throw std::runtime_error("PRF stream sector plan is incomplete");
            auto chunk=std::min(count,width-within);std::uint64_t at;
            if(stream.mini){auto logical=std::uint64_t(stream.sectors[index])*64+within;if(logical+chunk>root_.size)throw std::runtime_error("PRF mini stream exceeds root stream");auto ri=static_cast<std::size_t>(logical/512);if(ri>=root_.sectors.size())throw std::runtime_error("PRF root sector plan is incomplete");at=(std::uint64_t(root_.sectors[ri])+1)*512+logical%512;}
            else at=(std::uint64_t(stream.sectors[index])+1)*512+within;
            if(run&&at!=physical+run)flush();if(!run)physical=at;run+=chunk;count-=chunk;offset+=chunk;
        }
        flush();return result;
    }
private:
    Reader& reader_;std::uint64_t size_=0,control_bytes_=0;Sector count_=0;
    std::vector<unsigned> owners_;std::vector<bool> mini_owners_;
    std::vector<Sector> fat_,mini_fat_,parents_;std::vector<Entry> entries_;std::vector<Stream> streams_;Stream root_;
    Bytes raw(std::uint64_t at,unsigned n){if(at>size_||n>size_-at)throw std::runtime_error("PRF source read outside bounds");auto bytes=reader_.read(at,n);if(bytes.size()!=n)throw std::runtime_error("PRF truncated source read");return bytes;}
    Bytes get(std::uint64_t at,unsigned n){if(n>786432-control_bytes_)throw std::runtime_error("PRF bounded container metadata exceeds inspect budget");control_bytes_+=n;return raw(at,n);}
    Bytes sector(Sector id){if(id>=count_)throw std::runtime_error("PRF sector is outside source");return get((std::uint64_t(id)+1)*512,512);}
    void claim(Sector id,unsigned owner){if(id>=count_||owners_[id])throw std::runtime_error("PRF sector chain is cyclic, aliased or out of range");owners_[id]=owner;}
    std::vector<Sector> chain(Sector start,std::uint64_t expected,unsigned owner,std::uint64_t maximum){
        std::vector<Sector> result;
        // Directory has no v3 count; all other chains must close exactly.
        const bool directory=owner==3;
        if(!directory&&!expected){if(start!=end_chain&&start!=free_sector)throw std::runtime_error("PRF empty chain has a start sector");return result;}
        auto next=start;
        while(next!=end_chain){
            if(result.size()>=maximum||(!directory&&result.size()>=expected))throw std::runtime_error("PRF sector chain exceeds declared size/bound");
            claim(next,owner);result.push_back(next);if(next>=fat_.size())throw std::runtime_error("PRF FAT index outside coverage");next=fat_[next];
        }
        if((directory&&result.empty())||(!directory&&result.size()!=expected))throw std::runtime_error("PRF sector chain ended before declared size");return result;
    }
    Stream make_stream(const Entry& entry){
        Stream stream;stream.size=entry.size;stream.mini=entry.size<4096;
        if(!stream.mini){stream.sectors=chain(entry.start,(entry.size+511)/512,6,count_);return stream;}
        if(!stream.size){if(entry.start!=end_chain&&entry.start!=free_sector)throw std::runtime_error("PRF empty stream has allocated sectors");return stream;}
        auto next=entry.start;const auto expected=(entry.size+63)/64;
        while(next!=end_chain){
            if(stream.sectors.size()>=expected||next>=mini_fat_.size()||next>=mini_owners_.size()||mini_owners_[next]||(std::uint64_t(next)*64+64)>root_.size)throw std::runtime_error("PRF MiniFAT chain cyclic, aliased, out of bounds or too long");
            mini_owners_[next]=true;stream.sectors.push_back(next);next=mini_fat_[next];
        }
        if(stream.sectors.size()!=expected)throw std::runtime_error("PRF MiniFAT chain shorter than declared stream");return stream;
    }
};
Decoder::Decoder(Reader& reader,std::uint64_t size):impl_(new DecoderImpl(reader,size)){}
Decoder::~Decoder(){delete impl_;}
Profile Decoder::parse(){return impl_->parse();}
Bytes Decoder::read_stream(const Stream& stream,std::uint64_t offset,unsigned count){return impl_->read_stream(stream,offset,count);}
}
