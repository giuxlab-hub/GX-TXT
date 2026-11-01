// SPDX-License-Identifier: GPL-3.0-or-later
// Bounded parser for the SAME documented Rigol/sequence CSV input as the
// retained Octave worker. Outputs are staging float64 transport arrays, never
// canonical GX-TXT files. CORE Publication v2 owns HDF5 and Dataset identity.
#include <algorithm>
#include <charconv>
#include <cctype>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <regex>
#include <stdexcept>
#include <string>
#include <vector>

namespace fs = std::filesystem;
using Clock = std::chrono::steady_clock;
static double elapsed(Clock::time_point start) { return std::chrono::duration<double>(Clock::now()-start).count(); }
static std::string trim(std::string s) {
    auto first=s.find_first_not_of(" \t\r\n");
    if(first==std::string::npos) return {};
    return s.substr(first,s.find_last_not_of(" \t\r\n")-first+1);
}
static std::vector<std::string> split(const std::string& text,char delimiter) {
    std::vector<std::string> result; std::string cell; bool quoted=false;
    for(std::size_t i=0;i<text.size();++i) {
        char c=text[i];
        if(c=='"') {
            if(quoted && i+1<text.size() && text[i+1]=='"') {cell+='"';++i;}
            else quoted=!quoted;
        } else if(c==delimiter && !quoted) { result.push_back(trim(cell));cell.clear(); }
        else cell+=c;
    }
    if(quoted) throw std::runtime_error("Unterminated CSV quoted field");
    result.push_back(trim(cell));return result;
}
static double number(std::string value,bool empty=true) {
    value=trim(value);
    if(value.empty() && empty) return std::numeric_limits<double>::quiet_NaN();
    if(!value.empty() && value[0]=='+') value.erase(0,1);
    double result=0;
    auto parsed=std::from_chars(value.data(),value.data()+value.size(),result,std::chars_format::general);
    if(parsed.ec!=std::errc{} || parsed.ptr!=value.data()+value.size()) throw std::runtime_error("Invalid numeric CSV field");
    return result;
}
static std::size_t integer(const std::string& value,std::size_t maximum) {
    auto n=number(value,false);
    if(!std::isfinite(n) || n<0 || n>double(maximum) || std::floor(n)!=n) throw std::runtime_error("Invalid bounded integer option");
    return std::size_t(n);
}
struct Output {
    std::string name; fs::path temporary,final; std::ofstream stream;
    std::vector<double> values;
    Output(const fs::path& root,const std::string& stem,std::size_t reserve):name(stem),temporary(root/(stem+".f64le.part")),final(root/(stem+".f64le")) {
        if(fs::exists(temporary)||fs::exists(final)) throw std::runtime_error("Output already exists");
        stream.open(temporary,std::ios::binary|std::ios::out);
        if(!stream) throw std::runtime_error("Cannot open private numeric output");
        values.reserve(reserve);
    }
    Output(Output&&)=default;
    void flush() {
        static_assert(sizeof(double)==8 && std::numeric_limits<double>::is_iec559,"IEEE binary64 required");
        const std::uint16_t endian=1;
        if(*reinterpret_cast<const unsigned char*>(&endian)!=1) {
            for(double& value:values) {
                unsigned char raw[8];std::memcpy(raw,&value,8);std::reverse(raw,raw+8);std::memcpy(&value,raw,8);
            }
        }
        stream.write(reinterpret_cast<const char*>(values.data()),std::streamsize(values.size()*8));
        if(!stream) throw std::runtime_error("Numeric output write failed");
        values.clear();
    }
    void close() {flush();stream.flush();stream.close();if(!stream) throw std::runtime_error("Numeric output close failed");}
};
struct Channel {std::size_t column;std::string name;std::size_t finite=0;double minimum=INFINITY,maximum=-INFINITY,sum=0,first=NAN,last=NAN;};

int main(int argc,char** argv) {
    try {
        std::map<std::string,std::string> options;
        for(int i=1;i<argc;i+=2) {
            if(i+1>=argc || std::string(argv[i]).rfind("--",0)!=0 || options.count(argv[i])) throw std::runtime_error("Invalid or duplicate worker argument");
            options[argv[i]]=argv[i+1];
        }
        auto get=[&](const std::string& key,const std::string& fallback=std::string{}) {auto it=options.find(key);return it==options.end()?fallback:it->second;};
        const std::vector<std::string> admitted={"--input","--out","--parser","--delimiter","--header-lines","--sequence-col","--time-col","--tstart","--dt","--channels","--chunk-rows","--raw-fields","--drop-trailing-fields","--strict-sequence","--workers","--make-rigol","--make-canonical"};
        for(const auto& pair:options) if(std::find(admitted.begin(),admitted.end(),pair.first)==admitted.end()) throw std::runtime_error("Unknown worker option");
        const auto parser=get("--parser","rigol_ds1000z");
        if(parser!="rigol_ds1000z" && parser!="generic_sequence" && parser!="generic_time") throw std::runtime_error("Unsupported sequence parser");
        const auto separator=get("--delimiter",",");
        const char delimiter=separator=="tab"?'\t':separator.size()==1?separator[0]:'\0';
        if(delimiter!=',' && delimiter!=';' && delimiter!='\t') throw std::runtime_error("Invalid CSV delimiter");
        const auto headerRows=integer(get("--header-lines","2"),10000);
        const auto chunkRows=std::max<std::size_t>(1000,integer(get("--chunk-rows","250000"),1000000));
        const auto sequenceCol=integer(get("--sequence-col","1"),4096);
        const auto timeCol=integer(get("--time-col","1"),4096);
        const auto drop=integer(get("--drop-trailing-fields","0"),4096);
        const bool strict=integer(get("--strict-sequence","1"),1)!=0;
        fs::path source=get("--input"),root=get("--out");
        if(source.empty()||root.empty()||get("--channels").empty()) throw std::runtime_error("Input, private output and channel mapping required");
        std::ifstream input(source);if(!input) throw std::runtime_error("Cannot open CSV input");
        fs::create_directories(root);
        std::string line;std::vector<std::string> headers;
        for(std::size_t i=0;i<headerRows;++i) {if(!std::getline(input,line)||line.size()>2097152) throw std::runtime_error("Invalid or truncated CSV header");headers.push_back(line);}
        double start=number(get("--tstart","NaN")),dt=number(get("--dt","NaN"));
        if(parser=="rigol_ds1000z") {
            if(headers.size()<2) throw std::runtime_error("Rigol CSV requires two header rows");
            auto keys=split(headers[0],delimiter),values=split(headers[1],delimiter);
            for(std::size_t i=0;i<std::min(keys.size(),values.size());++i) {
                auto key=keys[i];std::transform(key.begin(),key.end(),key.begin(),[](unsigned char c){return char(std::tolower(c));});
                if(key=="start") start=number(values[i],false);
                if(key=="increment") dt=number(values[i],false);
            }
        }
        if(parser!="generic_time" && (!std::isfinite(start)||!std::isfinite(dt)||dt<=0)) throw std::runtime_error("Invalid source time start/increment");
        std::vector<Channel> channels;
        for(const auto& spec:split(get("--channels"),';')) {
            auto parts=split(spec,'|');
            if(parts.size()!=3 || !std::regex_match(parts[2],std::regex("[A-Za-z_][A-Za-z0-9_.-]*"))) throw std::runtime_error("Invalid admitted channel mapping");
            channels.push_back({integer(parts[0],4096),parts[2]});
        }
        if(channels.empty()||channels.size()>128) throw std::runtime_error("Invalid channel count");
        std::vector<Output> outputs;outputs.reserve(channels.size()+1);outputs.emplace_back(root,"time_s",chunkRows);
        for(const auto& channel:channels) outputs.emplace_back(root,channel.name,chunkRows);
        std::size_t rows=0,rawFields=integer(get("--raw-fields","0"),4096),sequenceErrors=0;
        double firstTime=NAN,lastTime=NAN,firstSequence=NAN,lastSequence=NAN,previousSequence=NAN,writeSeconds=0;
        const auto streamStart=Clock::now();const auto size=fs::file_size(source);
        auto flush=[&]() {auto began=Clock::now();for(auto& output:outputs)output.flush();writeSeconds+=elapsed(began);};
        while(std::getline(input,line)) {
            if(line.size()>2097152) throw std::runtime_error("CSV record exceeds line bound");
            if(trim(line).empty())continue;
            auto cells=split(line,delimiter);
            if(!rawFields)rawFields=cells.size();
            if(cells.size()!=rawFields||rawFields<2||drop>=rawFields) throw std::runtime_error("CSV field count changed");
            const auto effective=rawFields-drop;
            std::vector<double> numeric;numeric.reserve(cells.size());
            for(const auto& cell:cells)numeric.push_back(number(cell));
            const auto selected=parser=="generic_time"?timeCol:sequenceCol;
            if(selected<1||selected>effective)throw std::runtime_error("Invalid time/sequence column");
            const double ordinal=numeric[selected-1];
            double time=ordinal;
            if(parser!="generic_time") {
                if(!std::isfinite(ordinal)||std::floor(ordinal)!=ordinal) {
                    ++sequenceErrors;
                    if(strict)throw std::runtime_error("Sequence must contain finite exact integers");
                }
                if(std::isfinite(ordinal)) {
                    if(std::isfinite(previousSequence) && std::abs(ordinal-previousSequence-1)>1e-9)++sequenceErrors;
                    if(!std::isfinite(firstSequence))firstSequence=ordinal;
                    previousSequence=lastSequence=ordinal;
                }
                time=start+ordinal*dt;
            }
            if(std::isfinite(time)) {if(!std::isfinite(firstTime))firstTime=time;lastTime=time;}
            outputs[0].values.push_back(time);
            for(std::size_t i=0;i<channels.size();++i) {
                auto& channel=channels[i];
                if(channel.column<1||channel.column>effective)throw std::runtime_error("Channel is outside effective source columns");
                const double value=numeric[channel.column-1];
                if(!rows)channel.first=value;
                channel.last=value;
                if(std::isfinite(value)) {++channel.finite;channel.minimum=std::min(channel.minimum,value);channel.maximum=std::max(channel.maximum,value);channel.sum+=value;}
                outputs[i+1].values.push_back(value);
            }
            if(++rows>268435456)throw std::runtime_error("Numeric staging exceeds per-variable size bound");
            if(rows%chunkRows==0) {
                flush();auto position=input.tellg();
                std::cout<<"[IMPORT] rows="<<rows<<" progress="<<(position<0?100.0:100.0*double(position)/double(std::max<std::uintmax_t>(1,size)))<<"%\n"<<std::flush;
            }
        }
        if(!input.eof()||!rows)throw std::runtime_error("CSV read failed or source contains no samples");
        if(strict&&sequenceErrors)throw std::runtime_error("Sequence validation failed; numeric outputs remain private .part files");
        auto closing=Clock::now();for(auto& output:outputs)output.close();writeSeconds+=elapsed(closing);
        const double streamSeconds=elapsed(streamStart);
        for(auto& output:outputs) {
            if(fs::file_size(output.temporary)!=rows*8)throw std::runtime_error("Numeric staging shape mismatch");
            fs::rename(output.temporary,output.final);
        }
        std::ofstream receipt(root/"import_result.ini.part");receipt<<std::setprecision(17);
        receipt<<"[dataset]\nbackend=native\nparser="<<parser<<"\nrows="<<rows<<"\nraw_fields="<<rawFields<<"\nchannels="<<channels.size()<<"\ntStart_s="<<(parser=="generic_time"?firstTime:start)<<"\nfirst_time_s="<<firstTime<<"\nlast_time_s="<<lastTime<<"\nduration_s="<<lastTime-firstTime<<"\ndt_s="<<dt<<"\nsample_rate_Sa_s="<<1/dt<<"\nsequence_first="<<firstSequence<<"\nsequence_last="<<lastSequence<<"\nsequence_errors="<<sequenceErrors<<"\nworkers=1\n";
        receipt<<"\n[performance]\nparse_validation_statistics_seconds="<<streamSeconds-writeSeconds<<"\noutput_seconds="<<writeSeconds<<"\nstream_seconds="<<streamSeconds<<"\n\n[integrity]\nstatus=OK\nexpected_rows="<<rows<<"\n";
        for(std::size_t i=0;i<channels.size();++i)receipt<<"channel"<<i+1<<".name="<<channels[i].name<<"\nchannel"<<i+1<<".rows_written="<<rows<<"\n";
        receipt.flush();receipt.close();if(!receipt)throw std::runtime_error("Worker receipt write failed");
        fs::rename(root/"import_result.ini.part",root/"import_result.ini");
        std::cout<<"[PROFILE] stream="<<streamSeconds<<" output="<<writeSeconds<<" seconds; worker_parallelism=1\nOK\n";
        return 0;
    } catch(const std::exception& error) {
        std::cerr<<"Rigol CSV native worker: "<<error.what()<<'\n';return 1;
    }
}
