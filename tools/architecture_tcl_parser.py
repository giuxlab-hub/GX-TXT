"""Read-only Tcl 8.6 command parser using its public C parser API.

No inspected command is evaluated. Quoted/regexp/list data stays data; known
script bodies and command substitutions are parsed recursively. Dynamic bodies
remain visible as tokens for the architecture check's unresolved-call rules.
"""
# SPDX-License-Identifier: GPL-3.0-or-later
import ctypes as C
import ctypes.util
import re
import sys


class NativeToken(C.Structure):
    _fields_ = [('type', C.c_int), ('start', C.c_void_p), ('size', C.c_int), ('components', C.c_int)]


class Parse(C.Structure):
    # Only documented public fields are read. Extra aligned storage gives the
    # interpreter its private parser workspace without inspecting private state.
    _fields_ = [('commentStart',C.c_void_p),('commentSize',C.c_int),
                ('commandStart',C.c_void_p),('commandSize',C.c_int),('numWords',C.c_int),
                ('tokenPtr',C.POINTER(NativeToken)),('numTokens',C.c_int),
                ('tokensAvailable',C.c_int),('errorType',C.c_int),('workspace',C.c_byte*2048)]


_library = None


def library():
    global _library
    if _library is None:
        name = ctypes.util.find_library('tcl8.6') or ctypes.util.find_library('tcl86')
        if not name:
            raise ValueError('Tcl 8.6 public parser unavailable; install the supported runtime')
        lib = C.CDLL(name)
        lib.Tcl_GetVersion.argtypes = [C.POINTER(C.c_int)]*4
        version = [C.c_int() for _ in range(4)];lib.Tcl_GetVersion(*(C.byref(v) for v in version))
        if [v.value for v in version[:2]] != [8,6]:raise ValueError('Unsupported Tcl parser ABI')
        lib.Tcl_FindExecutable.argtypes = [C.c_char_p];lib.Tcl_FindExecutable(sys.executable.encode())
        lib.Tcl_CreateInterp.restype = C.c_void_p
        lib.Tcl_DeleteInterp.argtypes = [C.c_void_p]
        lib.Tcl_GetStringResult.argtypes = [C.c_void_p];lib.Tcl_GetStringResult.restype = C.c_char_p
        lib.Tcl_ParseCommand.argtypes = [C.c_void_p,C.c_void_p,C.c_int,C.c_int,C.POINTER(Parse)]
        lib.Tcl_FreeParse.argtypes = [C.POINTER(Parse)]
        _library = lib
    return _library


def parse(source, token_class):
    lib = library();interpreter = lib.Tcl_CreateInterp()
    raw = source.encode('utf-8');buffer = C.create_string_buffer(raw);base = C.addressof(buffer)
    statements = [];all_tokens = [];visited = set();report_spans=[]
    def location(offset):
        return raw.count(b'\n',0,offset)+1, offset-raw.rfind(b'\n',0,offset)
    def text(offset,size):return raw[offset:offset+size].decode('utf-8')
    def tokenize(offset,size):
        # Tcl itself established the syntactic extent and quoting. This extraction
        # identifies semantic names/operators inside data, never parses data as code.
        result = []
        chunk = text(offset,size)
        for match in re.finditer(r'(?:::)?[A-Za-z_][A-Za-z_0-9:.-]*|[=+*/-]',chunk):
            position = offset+len(chunk[:match.start()].encode('utf-8'))
            line,col = location(position)
            result.append(token_class('identifier' if len(match.group())>1 or match.group().isalpha() else 'punctuation',match.group(),line,col))
        return result
    def visit(start,size,depth=0):
        if (start,size) in visited:return
        visited.add((start,size))
        if depth>128:raise ValueError('Tcl parser nesting exceeds audited limit')
        cursor = start;end = start+size
        while cursor<end:
            parsed = Parse()
            try:
                rc = lib.Tcl_ParseCommand(interpreter,base+cursor,end-cursor,0,C.byref(parsed))
                if rc:
                    line,col = location(cursor)
                    raise ValueError(f'{line}:{col}: '+lib.Tcl_GetStringResult(interpreter).decode('utf-8'))
                next_cursor = (parsed.commandStart-base)+parsed.commandSize
                if next_cursor<=cursor:break
                native = [(t.type,t.start-base,t.size,t.components) for t in parsed.tokenPtr[:parsed.numTokens]]
            finally:lib.Tcl_FreeParse(C.byref(parsed))
            cursor = next_cursor
            words = [];index = 0;nested = []
            while index<len(native):
                kind,offset,length,components = native[index]
                if kind not in (1,2,256):raise ValueError('Unexpected Tcl word token')
                children = native[index+1:index+1+components]
                literal = children[0] if len(children)==1 and children[0][0]==4 else None
                if raw[offset:offset+1]==b'{' and raw[offset+length-1:offset+length]==b'}':
                    # Braced words can have several TEXT/BS components because of
                    # line continuation; they remain literal script bodies.
                    literal=(4,offset+1,length-2,0)
                words.append({'raw':text(offset,length),'offset':offset,'size':length,'literal':literal})
                for child_type,child_offset,child_size,_ in children:
                    if child_type==16:nested.append((child_offset+1,child_size-2))
                index += 1+components
            if not words:continue
            command = words[0]['raw'];statement = []
            # The exact public reporting command validates its result at runtime.
            # Keep its source extent; sibling substitutions/raw fields are outside.
            if command in ('::GX::StatisticsV1::numericFieldElements','::GX::StatisticsV1::numericFields','::GX::StatisticsV1::report','::GX::StatisticsV1::iniReport','::GX::StatisticsV1::parameterReport','::GX::StatisticsV1::parameterCorrelationReport','::GX::StatisticsV1::scalarValue','::GX::StatisticsV1::tableReport','::GX::StatisticsV1::parameterIniReport','::GX::StatisticsV1::scalarRows','::GX::StatisticsV1::parameterRows'):
                report_spans.append((words[0]['offset'],next_cursor))
            # Recognized body words are represented by their own parsed commands,
            # avoiding statistical taint from unrelated branches into a whole proc.
            bodies = set()
            if command in ('proc',):bodies.add(3)
            elif command in ('foreach','lmap','while'):bodies.add(len(words)-1)
            elif command == 'for':bodies.update((1,3,4))
            elif command in ('catch','time'):bodies.add(1)
            elif command == 'namespace' and len(words)>1 and words[1]['raw']=='eval':bodies.add(len(words)-1)
            elif command == 'if':
                i=1
                while i<len(words):
                    if words[i]['raw'] in ('elseif',):i+=1;continue
                    if words[i]['raw']=='else':bodies.add(i+1);break
                    i+=1
                    if i<len(words) and words[i]['raw']=='then':i+=1
                    bodies.add(i);i+=1
            elif command == 'try':
                bodies.add(1);i=2
                while i<len(words):
                    if words[i]['raw']=='finally':bodies.add(i+1);break
                    if words[i]['raw'] in ('on','trap'):bodies.add(i+3);i+=4
                    else:break
            # Switch bodies are Tcl lists. A synthetic list command permits the
            # same official parser to identify exact literal pattern/body tokens.
            if command=='switch' and words[-1]['literal']:
                _,offset,length,_=words[-1]['literal']
                # Braced switch lists are command-like pairs separated by newlines.
                # Parse each pair as syntax, then visit literal body words.
                switch_pairs(offset,length,depth+1)
                bodies.add(len(words)-1)
            for i,word in enumerate(words):
                if i in bodies:
                    if word['literal'] and command!='switch':
                        _,offset,length,_=word['literal'];visit(offset,length,depth+1)
                    elif not word['literal']:statement.extend(tokenize(word['offset'],word['size']))
                else:statement.extend(tokenize(word['offset'],word['size']))
            statements.append(statement);all_tokens.extend(statement)
            for offset,length in nested:visit(offset,length,depth+1)
    def switch_pairs(start,size,depth):
        cursor=start;end=start+size
        while cursor<end:
            parsed=Parse()
            try:
                if lib.Tcl_ParseCommand(interpreter,base+cursor,end-cursor,0,C.byref(parsed)):
                    raise ValueError('Unresolved switch list syntax')
                next_cursor=parsed.commandStart-base+parsed.commandSize
                native=[(t.type,t.start-base,t.size,t.components) for t in parsed.tokenPtr[:parsed.numTokens]]
            finally:lib.Tcl_FreeParse(C.byref(parsed))
            if next_cursor<=cursor:break
            cursor=next_cursor;index=0;word_index=0
            while index<len(native):
                _,offset,length,components=native[index];children=native[index+1:index+components+1]
                if word_index%2 and len(children)==1 and children[0][0]==4:
                    _,offset,length,_=children[0]
                    if text(offset,length)!='-':visit(offset,length,depth+1)
                index+=components+1;word_index+=1
    try:
        visit(0,len(raw))
        # Token locations refer to UTF-8 byte columns, matching Tcl's parser.
        line_starts=[0]+[i+1 for i,b in enumerate(raw) if b==10]
        for token in all_tokens:
            position=line_starts[token.line-1]+token.column-1
            if any(start<=position<end for start,end in report_spans):
                token.kind='validated_report'
    finally:lib.Tcl_DeleteInterp(interpreter)
    return all_tokens,statements
