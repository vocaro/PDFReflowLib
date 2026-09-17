import re, sys, os, collections

def tokens(data):
    i, n = 0, len(data)
    while i < n:
        c = data[i:i+1]
        if c in b' \t\r\n\f\x00':
            i += 1; continue
        if c == b'%':
            j = data.find(b'\n', i); i = n if j < 0 else j+1; continue
        if c == b'(':
            depth, j, esc = 1, i+1, False
            while j < n and depth:
                ch = data[j:j+1]
                if esc: esc = False
                elif ch == b'\\': esc = True
                elif ch == b'(': depth += 1
                elif ch == b')': depth -= 1
                j += 1
            yield ('str', data[i:j]); i = j; continue
        if data[i:i+2] == b'<<':
            yield ('op2', '<<'); i += 2; continue
        if data[i:i+2] == b'>>':
            yield ('op2', '>>'); i += 2; continue
        if c == b'<':
            j = data.find(b'>', i); j = n if j < 0 else j+1
            yield ('str', data[i:j]); i = j; continue
        if c == b'/':
            j = i+1
            while j < n and data[j:j+1] not in b' \t\r\n\f\x00/[]<>(){}%': j += 1
            yield ('name', data[i+1:j].decode('latin-1')); i = j; continue
        if c in b'[]{}':
            yield ('op2', c.decode()); i += 1; continue
        j = i
        while j < n and data[j:j+1] not in b' \t\r\n\f\x00/[]<>(){}%': j += 1
        tok = data[i:j].decode('latin-1'); i = j
        if re.fullmatch(r'[-+.0-9]+', tok):
            try: yield ('num', float(tok)); continue
            except ValueError: pass
        yield ('kw', tok)

