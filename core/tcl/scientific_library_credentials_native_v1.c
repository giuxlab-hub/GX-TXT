/* SPDX-License-Identifier: GPL-3.0-or-later
 * Private Library submit boundary. MAIN003 SOURCE IMPLEMENTATION ONLY.
 * Init is trusted/nonsecret. Submit never evaluates Tcl, waits, cancels,
 * schedules, invokes a script callback or resets diagnostic globals.
 * Ordinary untraced owner maps and admitted native Tcl values/pipes only.
 */
#define _POSIX_C_SOURCE 200809L
#include <tcl.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#if TCL_MAJOR_VERSION != 8 || TCL_MINOR_VERSION != 6 || TCL_UTF_MAX != 3
#error "Private Library submit requires the reviewed Tcl8.6 Unicode ABI"
#endif
#if !defined(__linux__)
#error "Private Library submit requires the reviewed Linux monotonic host"
#endif

#define SUBMIT "::GX::ScientificLibraryManagerAPIv1::credentialSubmit"
#define INFO "::GX::ScientificLibraryCredentialsNative::info"
#define SEND "::GX::ScriptJob::_protectedSend"
#define SEND_INFO "::GX::ScriptJob::_protectedSendInfo"
#define CONTEXTS "::GX::ScientificLibraryManagerAPIv1::credentialContexts"
#define OP_SCHEMA "gxtxt.library_credential_operation.v1"
#define NATIVE_SCHEMA "gxtxt.library_credentials_native.v1"
#define PREFIX "GXTXT_LIBRARY_RUNTIME_V1\t"
#define FRAME_LIMIT 65536
#define PAYLOAD_LIMIT 49131
#define RAW_LIMIT 32768
#define PROTECTED_LIMIT 16384

typedef struct NativeState NativeState;
typedef struct {
    NativeState *owner;
    Tcl_Command token;
    Tcl_ObjCmdProc *proc;
    ClientData data;
    int traced;
} Delegate;
struct NativeState {
    Tcl_Interp *interp;
    Tcl_ThreadId thread;
    Tcl_Encoding utf8;
    Delegate send, info;
    int admitted;
    int references;
};
static int submit(ClientData, Tcl_Interp *, int, Tcl_Obj *const []);
static int native_info(ClientData, Tcl_Interp *, int, Tcl_Obj *const []);

static Tcl_Obj *field(Tcl_Obj *dict, const char *name)
{
    Tcl_Obj *key = Tcl_NewStringObj(name, -1), *value = NULL;
    Tcl_IncrRefCount(key);
    if (Tcl_DictObjGet(NULL, dict, key, &value) != TCL_OK) value = NULL;
    Tcl_DecrRefCount(key);
    return value;
}

static int put(Tcl_Obj *dict, const char *name, Tcl_Obj *value)
{
    Tcl_Obj *key = Tcl_NewStringObj(name, -1);
    int code;
    Tcl_IncrRefCount(key);
    Tcl_IncrRefCount(value);
    code = Tcl_DictObjPut(NULL, dict, key, value);
    Tcl_DecrRefCount(value);
    Tcl_DecrRefCount(key);
    return code == TCL_OK;
}

static int text_is(Tcl_Obj *value, const char *literal)
{
    int length;
    const char *text;
    if (value == NULL) return 0;
    text = Tcl_GetStringFromObj(value, &length);
    return length == (int)strlen(literal) && memcmp(text, literal, (size_t)length) == 0;
}

static int object_equal(Tcl_Obj *a, Tcl_Obj *b)
{
    int na, nb;
    const char *sa, *sb;
    if (a == NULL || b == NULL) return 0;
    sa = Tcl_GetStringFromObj(a, &na);
    sb = Tcl_GetStringFromObj(b, &nb);
    return na == nb && memcmp(sa, sb, (size_t)na) == 0;
}

static int hex_text(Tcl_Obj *value, int required)
{
    int length, i;
    const char *text;
    if (value == NULL || Tcl_GetCharLength(value) != required) return 0;
    text = Tcl_GetStringFromObj(value, &length);
    if (length != required) return 0;
    for (i = 0; i < length; ++i)
        if (!((text[i] >= '0' && text[i] <= '9') || (text[i] >= 'a' && text[i] <= 'f'))) return 0;
    return 1;
}

static int serial_text(Tcl_Obj *value, const char *prefix)
{
    int length, i, start = (int)strlen(prefix);
    const char *text;
    if (value == NULL || Tcl_GetCharLength(value) > 64) return 0;
    text = Tcl_GetStringFromObj(value, &length);
    if (length <= start || length > 64 || memcmp(text, prefix, (size_t)start) != 0
            || text[start] < '1' || text[start] > '9') return 0;
    for (i = start + 1; i < length; ++i) if (text[i] < '0' || text[i] > '9') return 0;
    return 1;
}

static int safe_id(Tcl_Obj *value, int maximum)
{
    int n, i;
    const char *s;
    if (value == NULL || Tcl_GetCharLength(value) > maximum) return 0;
    s = Tcl_GetStringFromObj(value, &n);
    if (n < 1 || n > maximum) return 0;
    for (i = 0; i < n; ++i) {
        int alnum = (s[i] >= 'a' && s[i] <= 'z') || (s[i] >= 'A' && s[i] <= 'Z')
                || (s[i] >= '0' && s[i] <= '9');
        if (!alnum && (i == 0 || (s[i] != '.' && s[i] != '_' && s[i] != '-'))) return 0;
    }
    return 1;
}

static int flag_is(Tcl_Obj *value, int expected)
{
    int result;
    return value != NULL && Tcl_GetBooleanFromObj(NULL, value, &result) == TCL_OK
            && result == expected;
}

static int monotonic_ms(Tcl_WideInt *result)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0 || now.tv_sec < 0
            || now.tv_nsec < 0 || now.tv_nsec >= 1000000000L
            || (uint64_t)now.tv_sec > ((uint64_t)INT64_MAX - 999) / 1000) return 0;
    *result = (Tcl_WideInt)now.tv_sec * 1000 + now.tv_nsec / 1000000;
    return 1;
}

static void delegate_changed(ClientData data, Tcl_Interp *interp,
        const char *old_name, const char *new_name, int flags)
{
    Delegate *delegate = (Delegate *)data;
    (void)interp; (void)old_name; (void)new_name;
    delegate->owner->admitted = 0;
    if (flags & TCL_TRACE_DELETE) {
        delegate->token = NULL;
        delegate->traced = 0;
    }
}

static int delegate_live(NativeState *state, Delegate *delegate, const char *name)
{
    Tcl_CmdInfo info;
    Tcl_Obj *full;
    int same;
    if (delegate->token == NULL || !delegate->traced
            || !Tcl_GetCommandInfoFromToken(delegate->token, &info)
            || !info.isNativeObjectProc || info.objProc != delegate->proc
            || info.objClientData != delegate->data) return 0;
    full = Tcl_NewObj(); Tcl_IncrRefCount(full);
    Tcl_GetCommandFullName(state->interp, delegate->token, full);
    same = text_is(full, name);
    Tcl_DecrRefCount(full);
    return same;
}

static int ready(NativeState *state, Tcl_Interp *interp)
{
    Tcl_CmdInfo command;
    return state->admitted && state->interp == interp
            && state->thread == Tcl_GetCurrentThread()
            && Tcl_GetCommandInfo(interp, SUBMIT, &command) && command.isNativeObjectProc
            && command.objProc == submit && command.objClientData == (ClientData)state
            && Tcl_GetCommandInfo(interp, INFO, &command) && command.isNativeObjectProc
            && command.objProc == native_info && command.objClientData == (ClientData)state
            && delegate_live(state, &state->send, SEND)
            && delegate_live(state, &state->info, SEND_INFO);
}

static void untrace_delegate(NativeState *state, Delegate *delegate)
{
    if (delegate->traced && delegate->token != NULL) {
        Tcl_Obj *full = Tcl_NewObj(); Tcl_IncrRefCount(full);
        Tcl_GetCommandFullName(state->interp, delegate->token, full);
        Tcl_UntraceCommand(state->interp, Tcl_GetString(full), TCL_TRACE_RENAME | TCL_TRACE_DELETE,
                          delegate_changed, (ClientData)delegate);
        Tcl_DecrRefCount(full);
        delegate->traced = 0;
    }
}

static void release_state(ClientData data)
{
    NativeState *state = (NativeState *)data;
    if (--state->references != 0) return;
    untrace_delegate(state, &state->send);
    untrace_delegate(state, &state->info);
    Tcl_FreeEncoding(state->utf8);
    Tcl_Free((char *)state);
}

static int capture_delegate(NativeState *state, Delegate *delegate, const char *name)
{
    Tcl_CmdInfo info;
    delegate->owner = state;
    delegate->token = Tcl_FindCommand(state->interp, name, NULL, TCL_GLOBAL_ONLY);
    if (delegate->token == NULL || !Tcl_GetCommandInfoFromToken(delegate->token, &info)
            || !info.isNativeObjectProc || info.objProc == NULL) return 0;
    delegate->proc = info.objProc;
    delegate->data = info.objClientData;
    if (Tcl_TraceCommand(state->interp, name, TCL_TRACE_RENAME | TCL_TRACE_DELETE,
                        delegate_changed, (ClientData)delegate) != TCL_OK) return 0;
    delegate->traced = 1;
    return 1;
}

/* Scalar validation plus actual Tcl utf-8 owner conversion, not a UTF8 encoder.
 * Explicit fixed bounds avoid DString growth on untrusted input. NUL is legal
 * inside the credential; the inner B64 makes the submitted frame ASCII.
 */
static unsigned char *utf8_text(NativeState *state, Tcl_Obj *input, int maximum, int *length)
{
    int count, i, internal_length, read_count, written, chars, code;
    const Tcl_UniChar *unicode;
    const char *internal;
    Tcl_Obj *canonical = NULL, *roundtrip = NULL;
    unsigned char *output = NULL;
    char *inverse = NULL;
    int inverse_count, inverse_written, inverse_chars, roundtrip_count;
    const Tcl_UniChar *roundtrip_unicode;
    if (input == NULL || Tcl_GetCharLength(input) > maximum) return NULL;
    unicode = Tcl_GetUnicodeFromObj(input, &count);
    for (i = 0; i < count; ++i) {
        if (unicode[i] >= 0xd800 && unicode[i] <= 0xdbff) {
            if (++i >= count || unicode[i] < 0xdc00 || unicode[i] > 0xdfff) return NULL;
        } else if (unicode[i] >= 0xdc00 && unicode[i] <= 0xdfff) return NULL;
    }
    canonical = Tcl_NewUnicodeObj(unicode, count); Tcl_IncrRefCount(canonical);
    internal = Tcl_GetStringFromObj(canonical, &internal_length);
    if (internal_length < 0 || internal_length > maximum * 3) goto done;
    /* Tcl8.6's utf-8 owner reserves per-character destination headroom even
     * for final ASCII. Capacity is not the admitted written-byte limit. */
    output = (unsigned char *)malloc((size_t)maximum + 4);
    inverse = (char *)malloc((size_t)maximum * 3 + 4);
    if (output == NULL || inverse == NULL) goto done;
    code = Tcl_UtfToExternal(NULL, state->utf8, internal, internal_length,
            TCL_ENCODING_START | TCL_ENCODING_END | TCL_ENCODING_STOPONERROR | TCL_ENCODING_NO_TERMINATE,
            NULL, (char *)output, maximum + 4, &read_count, &written, &chars);
    if (code != TCL_OK || read_count != internal_length || written < 0 || written > maximum) goto done;
    code = Tcl_ExternalToUtf(NULL, state->utf8, (const char *)output, written,
            TCL_ENCODING_START | TCL_ENCODING_END | TCL_ENCODING_STOPONERROR | TCL_ENCODING_NO_TERMINATE,
            NULL, inverse, maximum * 3 + 4, &inverse_count, &inverse_written, &inverse_chars);
    if (code != TCL_OK || inverse_count != written || inverse_written < 0
            || inverse_written > maximum * 3) goto done;
    roundtrip = Tcl_NewStringObj(inverse, inverse_written); Tcl_IncrRefCount(roundtrip);
    roundtrip_unicode = Tcl_GetUnicodeFromObj(roundtrip, &roundtrip_count);
    if (roundtrip_count != count || memcmp(unicode, roundtrip_unicode,
                                         (size_t)count * sizeof(Tcl_UniChar)) != 0) goto done;
    *length = written;
    if (roundtrip != NULL) Tcl_DecrRefCount(roundtrip);
    Tcl_DecrRefCount(canonical);
    free(inverse);
    return output;
done:
    if (roundtrip != NULL) Tcl_DecrRefCount(roundtrip);
    if (canonical != NULL) Tcl_DecrRefCount(canonical);
    free(inverse); free(output);
    return NULL;
}

static Tcl_Obj *base64_object(const unsigned char *input, int length)
{
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    int i, j = 0, size;
    char *output;
    Tcl_Obj *result;
    if (length < 0 || length > PAYLOAD_LIMIT) return NULL;
    size = ((length + 2) / 3) * 4;
    output = (char *)malloc((size_t)size + 1);
    if (output == NULL) return NULL;
    for (i = 0; i < length; i += 3) {
        unsigned a = input[i], b = i + 1 < length ? input[i + 1] : 0;
        unsigned c = i + 2 < length ? input[i + 2] : 0;
        output[j++] = alphabet[a >> 2];
        output[j++] = alphabet[((a & 3) << 4) | (b >> 4)];
        output[j++] = i + 1 < length ? alphabet[((b & 15) << 2) | (c >> 6)] : '=';
        output[j++] = i + 2 < length ? alphabet[c & 63] : '=';
    }
    result = Tcl_NewStringObj(output, size); Tcl_IncrRefCount(result);
    free(output);
    return result;
}

static int append(Tcl_Obj *list, Tcl_Obj *value)
{
    int code;
    Tcl_IncrRefCount(value);
    code = Tcl_ListObjAppendElement(NULL, list, value);
    Tcl_DecrRefCount(value);
    return code == TCL_OK;
}

static Tcl_Obj *canonical_ref(Tcl_Obj *input)
{
    int size;
    Tcl_Obj *id, *generation, *operation, *result;
    if (Tcl_GetCharLength(input) > 512
            || Tcl_DictObjSize(NULL, input, &size) != TCL_OK || size != 3
            || !serial_text(id = field(input, "context_id"), "credential-context-")
            || !hex_text(generation = field(input, "generation"), 32)
            || !serial_text(operation = field(input, "operation_id"), "credential-operation-")) return NULL;
    result = Tcl_NewDictObj(); Tcl_IncrRefCount(result);
    if (!put(result, "context_id", id) || !put(result, "generation", generation)
            || !put(result, "operation_id", operation)) {Tcl_DecrRefCount(result); return NULL;}
    return result;
}

static Tcl_Obj *find_record(Tcl_Obj *map, Tcl_Obj *ref)
{
    int size;
    Tcl_Obj *record = NULL, *operation;
    if (map == NULL || Tcl_DictObjSize(NULL, map, &size) != TCL_OK || size > 4
            || Tcl_DictObjGet(NULL, map, field(ref, "context_id"), &record) != TCL_OK
            || record == NULL || !object_equal(field(record, "generation"), field(ref, "generation"))
            || (operation = field(record, "protected")) == NULL
            || !object_equal(field(operation, "operation_id"), field(ref, "operation_id"))) return NULL;
    return record;
}

/* Only fixed nonsecret fields enter the existing <=4 context map. Owner maps
 * are qualified trace-free before getters/Submit; hostile traces are excluded.
 */
static int set_phase(NativeState *state, Tcl_Obj *ref, const char *expected,
                     const char *phase, int dispatched, const char *code)
{
    Tcl_Obj *map, *record, *operation, *new_map = NULL, *new_record = NULL, *new_operation = NULL;
    int ok = 0;
    map = Tcl_GetVar2Ex(state->interp, CONTEXTS, NULL, TCL_GLOBAL_ONLY);
    if (map == NULL) return 0;
    Tcl_IncrRefCount(map);
    record = find_record(map, ref);
    if (record == NULL || (operation = field(record, "protected")) == NULL
            || !text_is(field(operation, "phase"), expected)) goto done;
    new_map = Tcl_DuplicateObj(map); Tcl_IncrRefCount(new_map);
    new_record = Tcl_DuplicateObj(record); Tcl_IncrRefCount(new_record);
    new_operation = Tcl_DuplicateObj(operation); Tcl_IncrRefCount(new_operation);
    if (!put(new_operation, "phase", Tcl_NewStringObj(phase, -1))
            || !put(new_operation, "dispatched", Tcl_NewBooleanObj(dispatched))
            || !put(new_operation, "submit_code", Tcl_NewStringObj(code, -1))
            || !put(new_record, "protected", new_operation)
            || Tcl_DictObjPut(NULL, new_map, field(ref, "context_id"), new_record) != TCL_OK) goto done;
    ok = Tcl_SetVar2Ex(state->interp, CONTEXTS, NULL, new_map, TCL_GLOBAL_ONLY) != NULL;
done:
    if (new_operation != NULL) Tcl_DecrRefCount(new_operation);
    if (new_record != NULL) Tcl_DecrRefCount(new_record);
    if (new_map != NULL) Tcl_DecrRefCount(new_map);
    Tcl_DecrRefCount(map);
    return ok;
}

static int response(Tcl_Interp *interp, Tcl_Obj *ref, const char *code, int unknown)
{
    Tcl_Obj *result = Tcl_NewDictObj();
    (void)put(result, "schema", Tcl_NewStringObj(OP_SCHEMA, -1));
    (void)put(result, "ok", Tcl_NewBooleanObj(code == NULL));
    (void)put(result, "state", Tcl_NewStringObj(code == NULL ? "submitted" : "failed", -1));
    if (ref != NULL) (void)put(result, "operation_ref", ref);
    if (code != NULL) (void)put(result, "code", Tcl_NewStringObj(code, -1));
    if (unknown) (void)put(result, "mutation_outcome", Tcl_NewStringObj("unknown", -1));
    Tcl_SetObjResult(interp, result);
    return TCL_OK;
}

static int metadata_operation(Tcl_Obj *record, Tcl_Obj *protected, int *operation)
{
    Tcl_Obj *kind = field(protected, "operation"), *meta = field(protected, "metadata");
    Tcl_Obj *revision, *lifetime;
    int size, unused;
    Tcl_WideInt seconds;
    if (meta == NULL || Tcl_DictObjSize(NULL, meta, &size) != TCL_OK
            || field(record, "descriptors") == NULL
            || Tcl_ListObjLength(NULL, field(record, "descriptors"), &unused) != TCL_OK) return 0;
    if (text_is(kind, "unlock")) {
        if (size != 2 || !text_is(field(record, "role"), "runtime")
                || !safe_id(field(meta, "library_id"), RAW_LIMIT)
                || !object_equal(field(meta, "library_id"), field(record, "library"))
                || (lifetime = field(meta, "lifetime_seconds")) == NULL
                || Tcl_GetWideIntFromObj(NULL, lifetime, &seconds) != TCL_OK || seconds < 1 || seconds > 900
                || !flag_is(field(protected, "mutation"), 0)) return 0;
        *operation = 0;
    } else {
        if (!text_is(field(record, "role"), "admin") || !text_is(field(record, "library"), "")
                || size != 3 || !safe_id(field(meta, "profile_id"), 64)
                || !safe_id(field(meta, "provider_id"), 64)
                || !flag_is(field(protected, "mutation"), 1)) return 0;
        revision = field(meta, "expected_revision");
        if (text_is(kind, "profile_create") && text_is(revision, "absent")) *operation = 1;
        else if (text_is(kind, "profile_replace") && hex_text(revision, 64)) *operation = 2;
        else return 0;
    }
    return 1;
}

static Tcl_Obj *make_frame(NativeState *state, Tcl_Obj *record, Tcl_Obj *protected,
                           int operation, Tcl_Obj *password, Tcl_Obj *secret)
{
    unsigned char *plain = NULL, *application = NULL, *payload = NULL;
    int size, raw_size, payload_size, encoded_size, fields_size;
    Tcl_Obj *password64 = NULL, *secret64 = NULL, *arguments = NULL, *dict = NULL, *outer = NULL, *frame = NULL;
    Tcl_Obj *meta = field(protected, "metadata");
    Tcl_WideInt seconds;
    plain = utf8_text(state, password, 1024, &size);
    if (plain == NULL || size < 12) goto done;
    password64 = base64_object(plain, size); free(plain); plain = NULL;
    if (password64 == NULL) goto done;
    if (operation != 0) {
        plain = utf8_text(state, secret, 4096, &size);
        if (plain == NULL || size < 1) goto done;
        secret64 = base64_object(plain, size); free(plain); plain = NULL;
        if (secret64 == NULL) goto done;
    }
    arguments = Tcl_NewListObj(0, NULL); Tcl_IncrRefCount(arguments);
    if (operation == 0) {
        if (Tcl_GetWideIntFromObj(NULL, field(meta, "lifetime_seconds"), &seconds) != TCL_OK
                || !append(arguments, field(meta, "library_id")) || !append(arguments, password64)
                || !append(arguments, Tcl_NewWideIntObj(seconds))) goto done;
    } else {
        if (!append(arguments, Tcl_NewStringObj(operation == 1 ? "create" : "replace", -1))
                || !append(arguments, field(meta, "profile_id"))
                || !append(arguments, field(meta, "expected_revision"))
                || !append(arguments, field(meta, "provider_id"))
                || !append(arguments, password64) || !append(arguments, secret64)) goto done;
    }
    application = utf8_text(state, arguments, PROTECTED_LIMIT, &raw_size);
    if (application == NULL || raw_size > RAW_LIMIT || raw_size > PROTECTED_LIMIT) goto done;
    dict = Tcl_NewDictObj(); Tcl_IncrRefCount(dict);
    if (!put(dict, "operation", Tcl_NewStringObj(operation == 0 ? "credential_unlock" : "profile_admin", -1))
            || !put(dict, "arguments", arguments) || !put(dict, "provider_descriptors", field(record, "descriptors"))) goto done;
    payload = utf8_text(state, dict, PAYLOAD_LIMIT, &payload_size);
    if (payload == NULL) goto done;
    outer = base64_object(payload, payload_size);
    if (outer == NULL) goto done;
    (void)Tcl_GetStringFromObj(outer, &encoded_size);
    fields_size = (int)(sizeof(PREFIX) - 1);
    if (encoded_size > FRAME_LIMIT - 1 - fields_size) goto done;
    frame = Tcl_NewStringObj(PREFIX, fields_size); Tcl_IncrRefCount(frame);
    Tcl_AppendObjToObj(frame, outer);
done:
    free(plain); free(application); free(payload);
    if (password64 != NULL) Tcl_DecrRefCount(password64);
    if (secret64 != NULL) Tcl_DecrRefCount(secret64);
    if (arguments != NULL) Tcl_DecrRefCount(arguments);
    if (dict != NULL) Tcl_DecrRefCount(dict);
    if (outer != NULL) Tcl_DecrRefCount(outer);
    return frame;
}

static int submit(ClientData data, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[])
{
    NativeState *state = (NativeState *)data;
    Tcl_Obj *ref = NULL, *map = NULL, *record, *protected, *frame = NULL;
    Tcl_Obj *send_name = NULL, *reply = NULL, *request, *sendv[3], *receipt;
    Tcl_WideInt now, deadline;
    int operation = 0, code, unknown = 0, attempted = 0, captured = 0;
    const char *failure = "invalid_request", *leaf_code;
    if (state->interp != interp || state->thread != Tcl_GetCurrentThread())
        return response(interp, NULL, "unavailable", 0);
    if (objc != 3 && objc != 4) return response(interp, NULL, failure, 0);
    ref = canonical_ref(objv[1]);
    if (ref == NULL) return response(interp, NULL, failure, 0);
    map = Tcl_GetVar2Ex(interp, CONTEXTS, NULL, TCL_GLOBAL_ONLY);
    if (map == NULL) goto done;
    Tcl_IncrRefCount(map);
    record = find_record(map, ref);
    if (record == NULL) {failure = "stale_context"; goto done;}
    captured = 1;
    protected = field(record, "protected");
    if (!text_is(field(protected, "phase"), "prepared")) {failure = "busy"; goto done;}
    if (!flag_is(field(record, "revoked"), 0) || !flag_is(field(record, "busy"), 1)
            || !flag_is(field(protected, "dispatched"), 0)) {failure = "stale_context"; goto refused;}
    if (!ready(state, interp) || !monotonic_ms(&now)) {failure = "unavailable"; goto refused;}
    if (field(protected, "deadline_ms") == NULL
            || Tcl_GetWideIntFromObj(NULL, field(protected, "deadline_ms"), &deadline) != TCL_OK
            || deadline <= now) {failure = "stale_context"; goto refused;}
    if (!metadata_operation(record, protected, &operation) || objc != (operation == 0 ? 3 : 4)) goto refused;
    request = field(record, "request");
    if (!serial_text(request, "job-request-")) goto refused;
    frame = make_frame(state, record, protected, operation, objv[2], operation == 0 ? NULL : objv[3]);
    if (frame == NULL) goto refused;
    if (!monotonic_ms(&now) || deadline <= now || !ready(state, interp)) {failure = "stale_context"; goto refused;}
    /* If this fixed state cannot be retained, no write is attempted. */
    if (!set_phase(state, ref, "prepared", "attempting", 1, "")) {failure = "stale_context"; goto done;}
    attempted = 1;
    send_name = Tcl_NewStringObj(SEND, -1); Tcl_IncrRefCount(send_name);
    sendv[0] = send_name; sendv[1] = request; sendv[2] = frame;
    code = state->send.proc(state->send.data, interp, 3, sendv);
    reply = Tcl_GetObjResult(interp); Tcl_IncrRefCount(reply);
    if (code != TCL_OK) {state->admitted = 0; failure = "transport_failure"; goto uncertain;}
    if (flag_is(field(reply, "ok"), 1)) {
        receipt = field(reply, "result");
        if (receipt == NULL || !object_equal(field(receipt, "request_id"), request)
                || !flag_is(field(receipt, "accepted"), 1)) {failure = "transport_failure"; goto uncertain;}
        if (!set_phase(state, ref, "attempting", "submitted", 1, "")) {failure = "transport_failure"; goto uncertain;}
        failure = NULL; goto done;
    }
    if (!flag_is(field(reply, "ok"), 0)) {failure = "transport_failure"; goto uncertain;}
    leaf_code = field(reply, "code") == NULL ? "" : Tcl_GetString(field(reply, "code"));
    if (strcmp(leaf_code, "ARITY") == 0 || strcmp(leaf_code, "INACTIVE") == 0
            || strcmp(leaf_code, "FRAME") == 0 || strcmp(leaf_code, "CHANNEL") == 0
            || strcmp(leaf_code, "BUSY") == 0) {
        failure = strcmp(leaf_code, "BUSY") == 0 ? "busy" : "transport_failure";
        if (!set_phase(state, ref, "attempting", "refused", 0, failure)) goto uncertain;
        attempted = 0; goto done;
    }
    failure = "transport_failure";
uncertain:
    unknown = operation != 0;
    (void)set_phase(state, ref, "attempting", "quarantined", 1, "transport_failure");
    goto done;
refused:
    (void)set_phase(state, ref, "prepared", "refused", 0, failure);
done:
    /* Retain the earlier attempting state on post-write bookkeeping failure.
     * No cleanup/callback/eval occurs underneath protected objv. */
    if (attempted && failure != NULL && operation != 0) unknown = 1;
    code = response(interp, captured ? ref : NULL, failure, unknown);
    if (reply != NULL) Tcl_DecrRefCount(reply);
    if (send_name != NULL) Tcl_DecrRefCount(send_name);
    if (frame != NULL) Tcl_DecrRefCount(frame);
    if (map != NULL) Tcl_DecrRefCount(map);
    Tcl_DecrRefCount(ref);
    return code;
}

static int native_info(ClientData data, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[])
{
    NativeState *state = (NativeState *)data;
    Tcl_WideInt now = 0;
    Tcl_Obj *result = Tcl_NewDictObj();
    int clock_ok = monotonic_ms(&now);
    (void)objv;
    (void)put(result, "schema", Tcl_NewStringObj(NATIVE_SCHEMA, -1));
    (void)put(result, "ready", Tcl_NewBooleanObj(objc == 1 && clock_ok && ready(state, interp)));
    (void)put(result, "monotonic_ms", Tcl_NewWideIntObj(clock_ok ? now : 0));
    Tcl_SetObjResult(interp, result);
    return TCL_OK;
}

/* Trusted NONSECRET initialization only, after MAIN admits the exact2179
 * package/artifact. Captured command identity is not an artifact certificate.
 * No SafeInit, auto-load, Tcl script resolver or public Script alias supplied.
 */
int Gxtxtlibrarycredentialsnative_Init(Tcl_Interp *interp)
{
    NativeState *state;
    Tcl_CmdInfo existing;
    Tcl_WideInt now;
    int major, minor, patch, release;
    if (Tcl_InitStubs(interp, "8.6", 0) == NULL) return TCL_ERROR;
    Tcl_GetVersion(&major, &minor, &patch, &release);
    if (major != 8 || minor != 6 || !monotonic_ms(&now)
            || Tcl_GetCommandInfo(interp, SUBMIT, &existing) || Tcl_GetCommandInfo(interp, INFO, &existing)
            || Tcl_PkgPresent(interp, "gxtxt_script_job_channel", "1.0", 1) == NULL) {
        Tcl_SetObjResult(interp, Tcl_NewStringObj("Native Library prerequisites are unavailable.", -1));
        return TCL_ERROR;
    }
    state = (NativeState *)Tcl_Alloc(sizeof(NativeState)); memset(state, 0, sizeof(*state));
    state->interp = interp; state->thread = Tcl_GetCurrentThread(); state->references = 1;
    state->utf8 = Tcl_GetEncoding(interp, "utf-8");
    if (state->utf8 == NULL) {Tcl_Free((char *)state); return TCL_ERROR;}
    if (!capture_delegate(state, &state->send, SEND) || !capture_delegate(state, &state->info, SEND_INFO)) {
        release_state((ClientData)state);
        Tcl_SetObjResult(interp, Tcl_NewStringObj("Native ScriptJob admission is unavailable.", -1));
        return TCL_ERROR;
    }
    if (Tcl_FindNamespace(interp, "::GX::ScientificLibraryManagerAPIv1", NULL, TCL_GLOBAL_ONLY) == NULL
            || (Tcl_FindNamespace(interp, "::GX::ScientificLibraryCredentialsNative", NULL, TCL_GLOBAL_ONLY) == NULL
                && Tcl_CreateNamespace(interp, "::GX::ScientificLibraryCredentialsNative", NULL, NULL) == NULL)) {
        release_state((ClientData)state); return TCL_ERROR;
    }
    state->admitted = 1;
    ++state->references;
    if (Tcl_CreateObjCommand(interp, SUBMIT, submit, (ClientData)state, release_state) == NULL) {
        release_state((ClientData)state); release_state((ClientData)state); return TCL_ERROR;
    }
    ++state->references;
    if (Tcl_CreateObjCommand(interp, INFO, native_info, (ClientData)state, release_state) == NULL) {
        release_state((ClientData)state); Tcl_DeleteCommand(interp, SUBMIT);
        release_state((ClientData)state); return TCL_ERROR;
    }
    if (Tcl_PkgProvide(interp, "gxtxt_library_credentials_native", "1.0") != TCL_OK) {
        Tcl_DeleteCommand(interp, INFO); Tcl_DeleteCommand(interp, SUBMIT);
        release_state((ClientData)state); return TCL_ERROR;
    }
    release_state((ClientData)state);
    return TCL_OK;
}
