// SPDX-License-Identifier: GPL-3.0-or-later
// Persistent declaration cache. Public scientific/Bridge/SDK owners retain authority.
#include <tcl.h>
#include <sqlite3.h>
#include <openssl/evp.h>
#include <array>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>

namespace {
constexpr int schemaVersion = 3;
constexpr const char* packageVersion = "1.1";
constexpr int applicationId = 0x47584143; // GXAC
constexpr std::size_t maxInput = 64U * 1024U * 1024U;
constexpr std::size_t maxOutput = 16U * 1024U * 1024U;
constexpr int maxRecords = 50000;
constexpr std::array<const char*, 10> fields = {{"id", "api_id", "provider_id", "surface", "language", "version", "title", "summary", "payload", nullptr}};
struct Failure : std::runtime_error {
    std::string code;
    Failure(std::string c, std::string message) : std::runtime_error(std::move(message)), code(std::move(c)) {}
};
[[noreturn]] void invalid(const std::string& message) { throw Failure("INVALID", message); }
std::string stringOf(Tcl_Obj* object) {
    int length = 0;
    const char* data = Tcl_GetStringFromObj(object, &length);
    return std::string(data, static_cast<std::size_t>(length));
}
class Digest {
    std::unique_ptr<EVP_MD_CTX, decltype(&EVP_MD_CTX_free)> context_{EVP_MD_CTX_new(), EVP_MD_CTX_free};
public:
    Digest() { if (!context_ || EVP_DigestInit_ex(context_.get(), EVP_sha256(), nullptr) != 1) throw Failure("DIGEST", "SHA256 initialization failed"); }
    void update(const char* data, std::size_t length) { if (EVP_DigestUpdate(context_.get(), data, length) != 1) throw Failure("DIGEST", "SHA256 update failed"); }
    void field(const std::string& value) {
        const auto length = std::to_string(value.size()) + ":";
        update(length.data(), length.size()); update(value.data(), value.size());
    }
    std::string finish() {
        std::array<unsigned char, EVP_MAX_MD_SIZE> output{};
        unsigned int length = 0;
        if (EVP_DigestFinal_ex(context_.get(), output.data(), &length) != 1) throw Failure("DIGEST", "SHA256 finalization failed");
        constexpr char hex[] = "0123456789abcdef";
        std::string result;
        for (unsigned int index = 0; index < length; ++index) { result.push_back(hex[output[index] >> 4]); result.push_back(hex[output[index] & 15]); }
        return result;
    }
};
void bound(const std::string& value, std::size_t maximum, const char* label, bool nonempty = false, bool allowNul = false) {
    // Tcl's internal UTF-8 represents U+0000 as C0 80 rather than a zero byte.
    if (value.size() > maximum || (nonempty && value.empty()) || (!allowNul && (value.find('\0') != std::string::npos || value.find("\xc0\x80") != std::string::npos))) invalid(std::string(label) + " exceeds its bound or contains NUL");
}
std::string fingerprint(Tcl_Interp* interp, Tcl_Obj* paths, const std::string& root = {}) {
    int count = 0;
    Tcl_Obj** values = nullptr;
    if (Tcl_ListObjGetElements(interp, paths, &count, &values) != TCL_OK || count > 10000) invalid("Fingerprint requires at most 10000 file paths");
    Digest digest;
    digest.field("gxtxt.api_catalog.fingerprint.v1");
    std::size_t total = 0;
    std::array<char, 65536> buffer{};
    for (int index = 0; index < count; ++index) {
        Tcl_Obj* normalized = Tcl_FSGetNormalizedPath(interp, values[index]);
        if (!normalized) invalid("Fingerprint requires ordinary file paths");
        const auto path = stringOf(normalized);
        bound(path, 32768, "Fingerprint path", true);
        digest.field(root.empty() ? path : std::filesystem::path(path).lexically_relative(root).generic_string());
        std::error_code error;
        const auto state = std::filesystem::status(path, error);
        if (error == std::errc::no_such_file_or_directory || (!error && !std::filesystem::exists(state))) { digest.field("missing"); continue; }
        if (error || !std::filesystem::is_regular_file(state)) throw Failure("FINGERPRINT", "Fingerprint source is inaccessible or not a regular file");
        const auto size = std::filesystem::file_size(path, error);
        if (error || size > 16U * 1024U * 1024U) throw Failure("FINGERPRINT", "Fingerprint source exceeds 16 MiB or is inaccessible");
        digest.field("file"); digest.field(std::to_string(size));
        std::ifstream input(path, std::ios::binary);
        if (!input) throw Failure("FINGERPRINT", "Fingerprint source cannot be opened");
        std::size_t fileBytes = 0;
        while (input) {
            input.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
            const auto bytes = static_cast<std::size_t>(input.gcount());
            fileBytes += bytes; total += bytes;
            if (fileBytes > 16U * 1024U * 1024U || total > 256U * 1024U * 1024U) throw Failure("FINGERPRINT", "Fingerprint source bytes exceed their bound");
            digest.update(buffer.data(), bytes);
        }
        if (!input.eof() || fileBytes != size) throw Failure("FINGERPRINT", "Fingerprint source changed or could not be completely read");
    }
    return digest.finish();
}
void sqliteCheck(sqlite3* database, int result) {
    if (result == SQLITE_OK || result == SQLITE_DONE || result == SQLITE_ROW) return;
    const int base = result & 255;
    const char* code = base == SQLITE_BUSY || base == SQLITE_LOCKED ? "BUSY" :
                       base == SQLITE_CORRUPT || base == SQLITE_NOTADB ? "CORRUPT" :
                       base == SQLITE_CONSTRAINT ? "CONSTRAINT" : "SQLITE";
    throw Failure(code, std::string("API Catalog database: ") + sqlite3_errmsg(database));
}
void execute(sqlite3* database, const char* sql) { sqliteCheck(database, sqlite3_exec(database, sql, nullptr, nullptr, nullptr)); }
class Statement {
    sqlite3* database_;
    sqlite3_stmt* statement_ = nullptr;
public:
    Statement(sqlite3* database, const char* sql) : database_(database) { sqliteCheck(database, sqlite3_prepare_v2(database, sql, -1, &statement_, nullptr)); }
    ~Statement() { sqlite3_finalize(statement_); }
    Statement(const Statement&) = delete;
    void bind(int index, const std::string& value) { sqliteCheck(database_, sqlite3_bind_text(statement_, index, value.data(), static_cast<int>(value.size()), SQLITE_TRANSIENT)); }
    void bind(int index, sqlite3_int64 value) { sqliteCheck(database_, sqlite3_bind_int64(statement_, index, value)); }
    int step() { const int result = sqlite3_step(statement_); sqliteCheck(database_, result); return result; }
    std::string text(int index) const {
        const auto* data = reinterpret_cast<const char*>(sqlite3_column_text(statement_, index));
        return data ? std::string(data, static_cast<std::size_t>(sqlite3_column_bytes(statement_, index))) : std::string();
    }
    sqlite3_int64 number(int index) const { return sqlite3_column_int64(statement_, index); }
    void reset() { sqliteCheck(database_, sqlite3_reset(statement_)); sqliteCheck(database_, sqlite3_clear_bindings(statement_)); }
};
struct Transaction {
    sqlite3* database;
    bool committed = false;
    explicit Transaction(sqlite3* db, bool write = true) : database(db) { execute(database, write ? "BEGIN IMMEDIATE" : "BEGIN"); }
    ~Transaction() { if (!committed) sqlite3_exec(database, "ROLLBACK", nullptr, nullptr, nullptr); }
    void commit() { execute(database, "COMMIT"); committed = true; }
};
struct Connection {
    sqlite3* database = nullptr;
    std::string framework;
    ~Connection() { if (database) sqlite3_close_v2(database); }
};
struct State {
    std::uint64_t next = 0;
    std::unordered_map<std::string, std::unique_ptr<Connection>> connections;
};
void destroyState(ClientData client, Tcl_Interp*) { delete static_cast<State*>(client); }
Tcl_Obj* textObject(const std::string& value) { return Tcl_NewStringObj(value.data(), static_cast<int>(value.size())); }
void put(Tcl_Interp* interp, Tcl_Obj* dictionary, const char* key, const std::string& value) { Tcl_DictObjPut(interp, dictionary, Tcl_NewStringObj(key, -1), textObject(value)); }
void putNumber(Tcl_Interp* interp, Tcl_Obj* dictionary, const char* key, sqlite3_int64 value) { Tcl_DictObjPut(interp, dictionary, Tcl_NewStringObj(key, -1), Tcl_NewWideIntObj(static_cast<Tcl_WideInt>(value))); }
using Properties = std::unordered_map<std::string, Tcl_Obj*>;
Properties dictionary(Tcl_Interp* interp, Tcl_Obj* value, const std::set<std::string>& allowed) {
    Properties properties;
    Tcl_DictSearch search;
    Tcl_Obj* key = nullptr;
    Tcl_Obj* item = nullptr;
    int done = 0;
    if (Tcl_DictObjFirst(interp, value, &search, &key, &item, &done) != TCL_OK) invalid("Expected a dictionary");
    try {
        while (!done) {
            const auto name = stringOf(key);
            if (!allowed.count(name)) invalid("Unknown dictionary field: " + name.substr(0, 80));
            properties.emplace(name, item);
            Tcl_DictObjNext(&search, &key, &item, &done);
        }
    } catch (...) { Tcl_DictObjDone(&search); throw; }
    Tcl_DictObjDone(&search);
    return properties;
}
Connection& connection(State& state, Tcl_Obj* handle) {
    const auto found = state.connections.find(stringOf(handle));
    if (found == state.connections.end()) throw Failure("HANDLE", "Unknown API Catalog handle in this interpreter");
    return *found->second;
}
sqlite3_int64 scalar(sqlite3* database, const char* sql) { Statement statement(database, sql); if (statement.step() != SQLITE_ROW) throw Failure("SCHEMA", "API Catalog metadata is absent"); return statement.number(0); }
struct Metadata { std::string fingerprint; sqlite3_int64 generation = 0; sqlite3_int64 count = 0; };
Metadata metadata(Connection& connection) {
    Statement statement(connection.database, "SELECT fingerprint,generation,(SELECT count(*) FROM records) FROM catalog_meta WHERE singleton=1");
    if (statement.step() != SQLITE_ROW) throw Failure("SCHEMA", "API Catalog metadata is absent");
    return {statement.text(0), statement.number(1), statement.number(2)};
}
Tcl_Obj* status(Tcl_Interp* interp, Connection& connection, const Metadata& meta) {
    Tcl_Obj* result = Tcl_NewDictObj();
    put(interp, result, "schema", "gxtxt.api_catalog.native.v1");
    put(interp, result, "native_package_version", packageVersion);
    putNumber(interp, result, "schema_version", schemaVersion);
    put(interp, result, "framework_id", connection.framework);
    put(interp, result, "root", connection.framework);
    put(interp, result, "fingerprint", meta.fingerprint);
    putNumber(interp, result, "generation", meta.generation);
    putNumber(interp, result, "count", meta.count);
    return result;
}
std::unique_ptr<Connection> open(Tcl_Interp* interp, Tcl_Obj* pathObject, Tcl_Obj* rootObject, bool readonly = false) {
    auto result = std::make_unique<Connection>();
    result->framework = stringOf(rootObject);
    bound(result->framework, 8192, "Framework identity", true);
    Tcl_Obj* normal = Tcl_FSGetNormalizedPath(interp, pathObject);
    if (!normal) invalid("Catalog database requires an ordinary filesystem path");
    const auto path = stringOf(normal);
    bound(path, 32768, "Database path", true);
    int flags = readonly ? SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX;
#ifdef SQLITE_OPEN_NOFOLLOW
    flags |= SQLITE_OPEN_NOFOLLOW;
#endif
    const int code = sqlite3_open_v2(path.c_str(), &result->database, flags, nullptr);
    sqliteCheck(result->database, code);
    sqlite3_extended_result_codes(result->database, 1);
    sqliteCheck(result->database, sqlite3_busy_timeout(result->database, 100));
    sqlite3_limit(result->database, SQLITE_LIMIT_LENGTH, static_cast<int>(maxOutput));
    sqlite3_limit(result->database, SQLITE_LIMIT_SQL_LENGTH, 16384);
    execute(result->database, "PRAGMA trusted_schema=OFF");
    Transaction transaction(result->database,!readonly);
    const auto version = scalar(result->database, "PRAGMA user_version");
    const auto application = scalar(result->database, "PRAGMA application_id");
    if (!readonly && version == 0 && application == 0 && scalar(result->database, "SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0) {
        execute(result->database,
            "CREATE TABLE catalog_meta(singleton INTEGER PRIMARY KEY CHECK(singleton=1),framework_id TEXT NOT NULL,fingerprint TEXT NOT NULL,generation INTEGER NOT NULL CHECK(generation>=0));"
            "CREATE TABLE records(id TEXT PRIMARY KEY NOT NULL,api_id TEXT NOT NULL,provider_id TEXT NOT NULL,surface TEXT NOT NULL CHECK(surface IN ('family','host','script_bridge','cpp_sdk')),language TEXT NOT NULL CHECK(language IN ('all','Python','Octave','Cpp')),version TEXT NOT NULL,title TEXT NOT NULL,summary TEXT NOT NULL,payload TEXT NOT NULL) WITHOUT ROWID;"
            "CREATE INDEX records_family ON records(api_id,provider_id,surface,id);"
            "CREATE INDEX records_surface ON records(surface,language,api_id);"
            "CREATE TABLE declaration_sources(record_id TEXT PRIMARY KEY,provider_version TEXT NOT NULL,declaration_ref TEXT NOT NULL,declaration_sha256 TEXT NOT NULL,documentation TEXT NOT NULL,deprecated INTEGER NOT NULL,superseded_by TEXT NOT NULL,documentation_status TEXT NOT NULL,source_kind TEXT NOT NULL);"
            "CREATE INDEX declaration_source_lookup ON declaration_sources(declaration_ref,declaration_sha256);"
            "CREATE TABLE catalog_source_members(record_id TEXT NOT NULL,provider_id TEXT NOT NULL,provider_version TEXT NOT NULL,declaration_ref TEXT NOT NULL,declaration_sha256 TEXT NOT NULL,source_role TEXT NOT NULL,PRIMARY KEY(record_id,provider_id,declaration_ref,source_role));"
            "CREATE INDEX catalog_source_member_lookup ON catalog_source_members(provider_id,declaration_ref,record_id);"
            "CREATE INDEX catalog_source_exact_lookup ON catalog_source_members(declaration_ref,declaration_sha256,record_id);"
            "CREATE TABLE operation_visibility(record_id TEXT PRIMARY KEY,operation TEXT NOT NULL,public_documented INTEGER NOT NULL,python INTEGER NOT NULL,octave INTEGER NOT NULL,cpp_sdk INTEGER NOT NULL,result_contract TEXT NOT NULL);"
            "CREATE INDEX operation_visibility_language ON operation_visibility(python,octave,cpp_sdk,operation);"
            "CREATE TABLE operation_arguments(record_id TEXT NOT NULL,position INTEGER NOT NULL,name TEXT NOT NULL,kind TEXT NOT NULL,required INTEGER NOT NULL,default_known INTEGER NOT NULL,default_value TEXT NOT NULL,description TEXT NOT NULL,PRIMARY KEY(record_id,position));"
            "PRAGMA application_id=1196966211;PRAGMA user_version=3;");
        Statement insert(result->database, "INSERT INTO catalog_meta VALUES(1,?1,'',0)");
        insert.bind(1, result->framework); insert.step();
    } else if (version != schemaVersion || application != applicationId) {
        throw Failure("SCHEMA", "Unsupported API Catalog schema or foreign database; cache was preserved");
    }
    {
        Statement identity(result->database, "SELECT framework_id FROM catalog_meta WHERE singleton=1");
        if (identity.step() != SQLITE_ROW || identity.text(0) != result->framework) throw Failure("IDENTITY", "API Catalog framework identity differs; cache was preserved");
    }
    transaction.commit();
    if (!readonly) {
    execute(result->database, "PRAGMA journal_mode=WAL");
    execute(result->database, "PRAGMA synchronous=NORMAL");
    execute(result->database, "PRAGMA wal_autocheckpoint=256");
    }
    return result;
}
using Record = std::array<std::string, 9>;
std::vector<Record> records(Tcl_Interp* interp, Tcl_Obj* list) {
    int count = 0;
    Tcl_Obj** values = nullptr;
    if (Tcl_ListObjGetElements(interp, list, &count, &values) != TCL_OK) invalid("Records must be a list");
    if (count > maxRecords) invalid("API Catalog record count exceeds 50000");
    const std::set<std::string> allowed = {"id", "api_id", "provider_id", "surface", "language", "version", "title", "summary", "payload"};
    std::vector<Record> result;
    result.reserve(static_cast<std::size_t>(count));
    std::set<std::string> ids;
    std::size_t bytes = 0;
    for (int index = 0; index < count; ++index) {
        const auto properties = dictionary(interp, values[index], allowed);
        if (properties.size() != 9) invalid("API Catalog record requires all nine fields");
        Record record;
        for (std::size_t field = 0; field < record.size(); ++field) {
            record[field] = stringOf(properties.at(fields[field]));
            bound(record[field], field == 8 ? 1048576U : field == 7 ? 65536U : field == 6 ? 4096U : 1024U, fields[field], field < 5, field == 8);
            bytes += record[field].size();
            if (bytes > maxInput) invalid("API Catalog records exceed 64 MiB");
        }
        if (!ids.insert(record[0]).second) invalid("Duplicate API Catalog record identity");
        if (record[3] != "family" && record[3] != "host" && record[3] != "script_bridge" && record[3] != "cpp_sdk") invalid("Unknown API Catalog surface");
        if (record[4] != "all" && record[4] != "Python" && record[4] != "Octave" && record[4] != "Cpp") invalid("Unknown API Catalog language");
        int payloadFields = 0;
        if (Tcl_DictObjSize(interp, properties.at("payload"), &payloadFields) != TCL_OK) invalid("API Catalog payload must be a dictionary");
        result.emplace_back(std::move(record));
    }
    return result;
}
// Relational contract fields are indexed independently of presentation payloads.
Tcl_Obj* valueAt(Tcl_Interp* interp, Tcl_Obj* object, const char* key) {
    Tcl_Obj* value = nullptr;
    Tcl_Obj* name=Tcl_NewStringObj(key,-1);Tcl_IncrRefCount(name);
    const int code=Tcl_DictObjGet(interp,object,name,&value);Tcl_DecrRefCount(name);
    if(code!=TCL_OK) invalid("Malformed catalog contract dictionary");
    return value;
}
std::string textAt(Tcl_Interp* interp, Tcl_Obj* object, const char* key) {
    auto* value = valueAt(interp, object, key); return value ? stringOf(value) : std::string();
}
void normalize(Tcl_Interp* interp, sqlite3* database, const Record& row) {
    Tcl_Obj* payload = textObject(row[8]); Tcl_IncrRefCount(payload);
    try {
        Tcl_Obj* meta = valueAt(interp, payload, "catalog_meta");
        if (!meta) { Tcl_DecrRefCount(payload); return; }
        Statement source(database, "INSERT INTO declaration_sources VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)");
        source.bind(1,row[0]);
        int column=2;
        for (const char* key : {"provider_version","declaration_ref","declaration_sha256","documentation"}) source.bind(column++,textAt(interp,meta,key));
        source.bind(6,static_cast<sqlite3_int64>(textAt(interp,meta,"deprecated")=="1"));source.bind(7,textAt(interp,meta,"superseded_by"));source.bind(8,textAt(interp,meta,"documentation_status"));source.bind(9,textAt(interp,meta,"source_kind"));source.step();
        Tcl_Obj* sources=valueAt(interp,meta,"source_members");
        if(sources) {
            int count=0;Tcl_Obj** values=nullptr;
            if(Tcl_ListObjGetElements(interp,sources,&count,&values)!=TCL_OK || count>1024) invalid("Catalog source membership exceeds bound");
            Statement member(database,"INSERT INTO catalog_source_members VALUES(?1,?2,?3,?4,?5,?6)");
            for(int index=0;index<count;++index) {
                member.bind(1,row[0]);int column=2;
                for(const char* key : {"provider_id","provider_version","declaration_ref","declaration_sha256","source_role"}) member.bind(column++,textAt(interp,values[index],key));
                member.step();member.reset();
            }
        }
        Statement visibility(database,"INSERT INTO operation_visibility VALUES(?1,?2,?3,?4,?5,?6,?7)");
        visibility.bind(1,row[0]);visibility.bind(2,textAt(interp,meta,"operation"));
        column=3;for(const char* key : {"public_documented","python","octave","cpp_sdk"}) visibility.bind(column++,static_cast<sqlite3_int64>(textAt(interp,meta,key)=="1"));
        visibility.bind(7,textAt(interp,meta,"result_contract"));visibility.step();
        Tcl_Obj* arguments=valueAt(interp,meta,"arguments");
        if(arguments) {
            int count=0;Tcl_Obj** values=nullptr;
            if(Tcl_ListObjGetElements(interp,arguments,&count,&values)!=TCL_OK || count>256) invalid("Catalog argument list exceeds bound");
            Statement argument(database,"INSERT INTO operation_arguments VALUES(?1,?2,?3,?4,?5,?6,?7,?8)");
            for(int index=0;index<count;++index) {
                const auto name=textAt(interp,values[index],"name");if(name.empty()) invalid("Catalog argument requires a name");
                argument.bind(1,row[0]);argument.bind(2,static_cast<sqlite3_int64>(index));argument.bind(3,name);argument.bind(4,textAt(interp,values[index],"kind"));const auto required=textAt(interp,values[index],"required");argument.bind(5,static_cast<sqlite3_int64>(required.empty() || required=="-1" || required=="unknown" ? -1 : required=="0" ? 0 : 1));argument.bind(6,static_cast<sqlite3_int64>(valueAt(interp,values[index],"default")!=nullptr));argument.bind(7,textAt(interp,values[index],"default"));argument.bind(8,textAt(interp,values[index],"description"));argument.step();argument.reset();
            }
        }
    } catch(...) {Tcl_DecrRefCount(payload);throw;}
    Tcl_DecrRefCount(payload);
}
Tcl_Obj* rowObject(Tcl_Interp* interp, Statement& statement, std::size_t& bytes) {
    std::array<std::string, 9> values;
    for (int index = 0; index < 9; ++index) {
        values[static_cast<std::size_t>(index)] = statement.text(index);
        bytes += values[static_cast<std::size_t>(index)].size();
    }
    if (bytes > maxOutput) throw Failure("RESPONSE_LIMIT", "API Catalog response exceeds 16 MiB; use a smaller page");
    Tcl_Obj* row = Tcl_NewDictObj();
    for (std::size_t index = 0; index < values.size(); ++index) put(interp, row, fields[index], values[index]);
    return row;
}
struct Filters {
    std::string surface, language, query, api, provider, source, sourceHash;
    sqlite3_int64 offset = 0, limit = 100;
};
Filters filters(Tcl_Interp* interp, Tcl_Obj* object) {
    const auto values = dictionary(interp, object, {"surface", "language", "query", "api_id", "provider_id", "source_ref", "source_sha256", "offset", "limit"});
    Filters result;
    const auto get = [&](const char* key) { const auto found = values.find(key); return found == values.end() ? std::string() : stringOf(found->second); };
    result.language = get("language"); result.query = get("query"); result.api = get("api_id"); result.provider = get("provider_id");result.source=get("source_ref");result.sourceHash=get("source_sha256");
    bound(result.source,1024,"source_ref");bound(result.sourceHash,64,"source_sha256");
    const auto surface = values.find("surface");
    if (surface != values.end()) {
        int count = 0;
        Tcl_Obj** members = nullptr;
        if (Tcl_ListObjGetElements(interp, surface->second, &count, &members) != TCL_OK || count > 4) invalid("Surface filter requires up to four declared surfaces");
        for (int index = 0; index < count; ++index) {
            const auto member = stringOf(members[index]);
            if (member != "family" && member != "host" && member != "script_bridge" && member != "cpp_sdk") invalid("Unknown API Catalog surface filter");
            if (!result.surface.empty()) result.surface += ' ';
            result.surface += member;
        }
    }
    for (const auto& pair : std::array<std::pair<const char*, std::string*>, 5>{{{"surface", &result.surface}, {"language", &result.language}, {"query", &result.query}, {"api_id", &result.api}, {"provider_id", &result.provider}}}) bound(*pair.second, std::string(pair.first) == "query" ? 2048U : 1024U, pair.first);
    if (Tcl_NumUtfChars(result.query.data(), static_cast<int>(result.query.size())) > 256) invalid("API Catalog query exceeds 256 characters");
    if (!result.language.empty() && result.language != "all" && result.language != "Python" && result.language != "Octave" && result.language != "Cpp") invalid("Unknown API Catalog language filter");
    for (const char* key : {"offset", "limit"}) {
        const auto found = values.find(key);
        if (found == values.end()) continue;
        Tcl_WideInt number = 0;
        if (Tcl_GetWideIntFromObj(interp, found->second, &number) != TCL_OK) invalid("Catalog pagination requires integers");
        if (std::string(key) == "offset") result.offset = number; else result.limit = number;
    }
    if (result.offset < 0 || result.limit < 1 || result.limit > 1000) invalid("Catalog offset must be nonnegative and limit must be 1..1000");
    return result;
}
void bindFilters(Statement& statement, const Filters& filters) {
    statement.bind(1, filters.surface); statement.bind(2, filters.language); statement.bind(3, filters.api); statement.bind(4, filters.provider); statement.bind(5, filters.query);statement.bind(8,filters.source);statement.bind(9,filters.sourceHash);
}
Tcl_Obj* query(Tcl_Interp* interp, Connection& connection, const Filters& filters) {
    // Both count and rows see one snapshot even while another process reconciles.
    Transaction transaction(connection.database, false);
    const auto meta = metadata(connection);
    constexpr const char* where = " WHERE (?1='' OR instr(' '||?1||' ',' '||surface||' ')>0) AND (?2='' OR ?2='all' OR language='all' OR language=?2) AND (?3='' OR api_id=?3) AND (?4='' OR provider_id=?4) AND (?5='' OR instr(lower(api_id||' '||provider_id||' '||title||' '||summary||' '||payload),lower(?5))>0) AND ((?8='' AND ?9='') OR EXISTS(SELECT 1 FROM catalog_source_members m WHERE m.record_id=records.id AND (?8='' OR m.declaration_ref=?8) AND (?9='' OR m.declaration_sha256=?9)))";
    const auto countSql = std::string("SELECT count(*) FROM records") + where;
    Statement count(connection.database, countSql.c_str()); bindFilters(count, filters); count.step();
    const auto total = count.number(0);
    const auto rowsSql = std::string("SELECT id,api_id,provider_id,surface,language,version,title,summary,payload FROM records") + where + " ORDER BY api_id,provider_id,surface,id LIMIT ?6 OFFSET ?7";
    Statement statement(connection.database, rowsSql.c_str()); bindFilters(statement, filters); statement.bind(6, filters.limit); statement.bind(7, filters.offset);
    Tcl_Obj* result = Tcl_NewDictObj();
    Tcl_IncrRefCount(result);
    try {
        Tcl_Obj* rows = Tcl_NewListObj(0, nullptr); Tcl_DictObjPut(interp, result, Tcl_NewStringObj("rows", -1), rows);
        std::size_t bytes = 0;
        while (statement.step() == SQLITE_ROW) Tcl_ListObjAppendElement(interp, rows, rowObject(interp, statement, bytes));
        putNumber(interp, result, "total", total); putNumber(interp, result, "offset", filters.offset); putNumber(interp, result, "limit", filters.limit);
        putNumber(interp, result, "generation", meta.generation); put(interp, result, "fingerprint", meta.fingerprint);
        transaction.commit();
    } catch (...) { Tcl_DecrRefCount(result); throw; }
    // Transfer the sole reference to the command result without leaking it.
    Tcl_SetObjResult(interp, result); Tcl_DecrRefCount(result);
    return Tcl_GetObjResult(interp);
}
void summary(Tcl_Interp* interp, Connection& connection) {
    // Aggregate in the native owner without fetching or parsing declaration
    // payloads. Both groupings belong to the same immutable read snapshot.
    Transaction transaction(connection.database, false);
    const auto meta = metadata(connection);
    if (meta.count < 0 || meta.count > maxRecords) invalid("API Catalog summary exceeds the record bound");
    Tcl_Obj* result = Tcl_NewDictObj();
    Tcl_IncrRefCount(result);
    try {
        Tcl_Obj* surfaces = Tcl_NewDictObj();
        Tcl_Obj* providers = Tcl_NewDictObj();
        Tcl_DictObjPut(interp, result, Tcl_NewStringObj("surfaces", -1), surfaces);
        Tcl_DictObjPut(interp, result, Tcl_NewStringObj("providers", -1), providers);
        sqlite3_int64 surfaceTotal = 0;
        Statement surfaceRows(connection.database, "SELECT surface,count(*) FROM records GROUP BY surface ORDER BY surface");
        while (surfaceRows.step() == SQLITE_ROW) {
            const auto name = surfaceRows.text(0);
            if (name != "family" && name != "host" && name != "script_bridge" && name != "cpp_sdk") invalid("Unknown API Catalog summary surface");
            const auto total = surfaceRows.number(1);
            putNumber(interp, surfaces, name.c_str(), total); surfaceTotal += total;
        }
        sqlite3_int64 providerTotal = 0;
        std::size_t bytes = 0;
        Statement providerRows(connection.database, "SELECT provider_id,count(*) FROM records GROUP BY provider_id ORDER BY provider_id");
        while (providerRows.step() == SQLITE_ROW) {
            const auto name = providerRows.text(0); bound(name, 1024, "Provider identity", true);
            bytes += name.size() + 32U;
            if (bytes > maxOutput) invalid("API Catalog summary exceeds 16 MiB");
            const auto total = providerRows.number(1);
            putNumber(interp, providers, name.c_str(), total); providerTotal += total;
        }
        if (surfaceTotal != meta.count || providerTotal != meta.count) throw Failure("SCHEMA", "API Catalog summary totals differ");
        put(interp, result, "schema", "gxtxt.api_catalog.summary.v1");
        putNumber(interp, result, "count", meta.count);
        putNumber(interp, result, "generation", meta.generation);
        put(interp, result, "fingerprint", meta.fingerprint);
        transaction.commit();
    } catch (...) { Tcl_DecrRefCount(result); throw; }
    Tcl_SetObjResult(interp, result); Tcl_DecrRefCount(result);
}
int command(ClientData client, Tcl_Interp* interp, int count, Tcl_Obj* const arguments[]) {
    auto& state = *static_cast<State*>(client);
    try {
        if (count < 2) invalid("Usage: apiCatalogNative open|close|status|summary|reconcile|query|get ...");
        const auto operation = stringOf(arguments[1]);
        if (operation == "digest") {
            if (count != 3) invalid("Usage: apiCatalogNative digest text");
            const auto input = stringOf(arguments[2]);
            if (input.size() > maxInput) invalid("Digest input exceeds 64 MiB");
            Digest digest; digest.update(input.data(), input.size()); Tcl_SetObjResult(interp, textObject(digest.finish()));
        } else if (operation == "file_digest") {
            if(count!=3) invalid("Usage: apiCatalogNative file_digest path");
            std::ifstream file(stringOf(arguments[2]),std::ios::binary);if(!file) throw Failure("DIGEST","Catalog source cannot be opened");
            Digest digest;std::array<char,65536> buffer{};std::size_t total=0;
            while(file){file.read(buffer.data(),static_cast<std::streamsize>(buffer.size()));const auto bytes=static_cast<std::size_t>(file.gcount());total+=bytes;if(total>maxInput)invalid("File digest exceeds64MiB");digest.update(buffer.data(),bytes);}
            if(!file.eof()) {throw Failure("DIGEST","Catalog source could not be completely read");}
            Tcl_SetObjResult(interp,textObject(digest.finish()));
        } else if (operation == "fingerprint") {
            if (count != 3 && count != 4) invalid("Usage: apiCatalogNative fingerprint paths ?root?");
            Tcl_SetObjResult(interp, textObject(fingerprint(interp, arguments[2],count==4?stringOf(arguments[3]):std::string())));
        } else if (operation == "open" || operation == "open_readonly") {
            if (count != 4) invalid("Usage: apiCatalogNative open database framework_id");
            auto database = open(interp, arguments[2], arguments[3],operation=="open_readonly");
            const auto handle = "api_catalog_" + std::to_string(++state.next);
            state.connections.emplace(handle, std::move(database));
            Tcl_SetObjResult(interp, textObject(handle));
        } else {
            if (count < 3) invalid("API Catalog operation requires a handle");
            auto& database = connection(state, arguments[2]);
            if (operation == "close") {
                if (count != 3) invalid("Usage: apiCatalogNative close handle");
                state.connections.erase(stringOf(arguments[2])); Tcl_ResetResult(interp);
            } else if (operation == "validate") {
                if(count!=3) invalid("Usage: apiCatalogNative validate handle");
                Statement integrity(database.database,"PRAGMA quick_check");
                if(integrity.step()!=SQLITE_ROW || integrity.text(0)!="ok") throw Failure("CORRUPT","API Catalog integrity check failed; snapshot preserved");
                if(scalar(database.database,"SELECT count(*) FROM records r LEFT JOIN declaration_sources s ON r.id=s.record_id LEFT JOIN operation_visibility v ON r.id=v.record_id WHERE s.record_id IS NULL OR v.record_id IS NULL OR NOT EXISTS(SELECT 1 FROM catalog_source_members m WHERE m.record_id=r.id)")!=0 || scalar(database.database,"SELECT count(*) FROM operation_arguments a LEFT JOIN records r ON a.record_id=r.id WHERE r.id IS NULL")!=0) throw Failure("SCHEMA","API Catalog normalized contract relations are incomplete");
                Tcl_Obj* result=status(interp,database,metadata(database));put(interp,result,"integrity","ok");Tcl_SetObjResult(interp,result);
            } else if (operation == "status") {
                if (count != 3) invalid("Usage: apiCatalogNative status handle");
                Tcl_SetObjResult(interp, status(interp, database, metadata(database)));
            } else if (operation == "summary") {
                if (count != 3) invalid("Usage: apiCatalogNative summary handle");
                summary(interp, database);
            } else if (operation == "reconcile") {
                if (count != 5) invalid("Usage: apiCatalogNative reconcile handle fingerprint records");
                const auto fingerprint = stringOf(arguments[3]); bound(fingerprint, 1024, "Fingerprint", true);
                const auto rows = records(interp, arguments[4]);
                Transaction transaction(database.database);
                const auto prior = metadata(database);
                const bool changed = prior.fingerprint != fingerprint;
                if (changed) {
                    execute(database.database, "DELETE FROM operation_arguments;DELETE FROM operation_visibility;DELETE FROM catalog_source_members;DELETE FROM declaration_sources;DELETE FROM records");
                    Statement insert(database.database, "INSERT INTO records VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9)");
                    for (const auto& row : rows) { for (std::size_t index = 0; index < row.size(); ++index) insert.bind(static_cast<int>(index + 1), row[index]); insert.step(); insert.reset(); normalize(interp,database.database,row); }
                    Statement update(database.database, "UPDATE catalog_meta SET fingerprint=?1,generation=generation+1 WHERE singleton=1"); update.bind(1, fingerprint); update.step();
                }
                const auto current = metadata(database); transaction.commit();
                Tcl_Obj* result = status(interp, database, current); putNumber(interp, result, "changed", changed ? 1 : 0); Tcl_SetObjResult(interp, result);
            } else if (operation == "query") {
                if (count != 4) invalid("Usage: apiCatalogNative query handle filters");
                query(interp, database, filters(interp, arguments[3]));
            } else if (operation == "get") {
                if (count != 4) invalid("Usage: apiCatalogNative get handle record_id");
                const auto identity = stringOf(arguments[3]); bound(identity, 1024, "Record identity", true);
                Statement statement(database.database, "SELECT id,api_id,provider_id,surface,language,version,title,summary,payload FROM records WHERE id=?1"); statement.bind(1, identity);
                if (statement.step() != SQLITE_ROW) throw Failure("MISSING", "API Catalog record no longer exists");
                std::size_t bytes = 0; Tcl_SetObjResult(interp, rowObject(interp, statement, bytes));
            } else invalid("Unknown API Catalog operation");
        }
        return TCL_OK;
    } catch (const Failure& failure) {
        Tcl_SetObjResult(interp, Tcl_NewStringObj(failure.what(), -1)); Tcl_SetErrorCode(interp, "GX", "API_CATALOG", failure.code.c_str(), nullptr);
    } catch (const std::bad_alloc&) {
        Tcl_SetObjResult(interp, Tcl_NewStringObj("API Catalog memory allocation failed", -1)); Tcl_SetErrorCode(interp, "GX", "API_CATALOG", "MEMORY", nullptr);
    } catch (const std::exception& failure) {
        Tcl_SetObjResult(interp, Tcl_NewStringObj(failure.what(), -1)); Tcl_SetErrorCode(interp, "GX", "API_CATALOG", "INTERNAL", nullptr);
    }
    return TCL_ERROR;
}
} // namespace

extern "C" {
#ifdef _WIN32
__declspec(dllexport)
#endif
int Gxtxt_api_catalog_Init(Tcl_Interp* interp) {
    if (!Tcl_InitStubs(interp, "8.6", 0)) return TCL_ERROR;
    if (!Tcl_FindNamespace(interp, "::GX", nullptr, TCL_GLOBAL_ONLY) && !Tcl_CreateNamespace(interp, "::GX", nullptr, nullptr)) return TCL_ERROR;
    auto* state = new State();
    Tcl_SetAssocData(interp, "gxtxt.api_catalog.v1", destroyState, state);
    Tcl_CreateObjCommand(interp, "::GX::apiCatalogNative", command, state, nullptr);
    return Tcl_PkgProvide(interp, "gxtxt_api_catalog", packageVersion);
}
}
