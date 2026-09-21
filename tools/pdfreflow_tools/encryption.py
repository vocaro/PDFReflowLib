"""A minimal encrypted PDF, for the one fixture that has to be locked (#252).

No corpus document is encrypted and none should be: a locked book cannot be redistributed as a
test input in a useful form. So the fixture is built here, from nothing, with the standard
library alone — the generator's ReportLab writes no encryption this old, and pulling in a crypto
dependency to produce one 1 KiB file would be a poor trade.

The scheme is the standard security handler at revision 2 (40-bit RC4), which is what PDF 1.4
specified and what PDFKit still opens. It is long obsolete as security and is not chosen as a
recommendation: it is chosen because it is the one handler whose whole key schedule is MD5 and a
twenty-line stream cipher, so the fixture can be built with `hashlib` and read back by any PDF
reader. What the library is being tested on here is that a password reaches every place that
opens the document, which does not depend on the cipher.

Every byte is fixed, including the file identifier, so the fixture has one identity.
"""
import hashlib
import struct

# The 32-byte padding string from the PDF specification's Algorithm 2.
PAD = bytes([0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41, 0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA,
             0x01, 0x08, 0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80, 0x2F, 0x0C, 0xA9, 0xFE,
             0x64, 0x53, 0x69, 0x7A])
# A fixed file identifier keeps the fixture byte-identical from one generation to the next.
FILE_ID = bytes.fromhex('5044465245464c4f57454e435259505445444649585455524521')
# Every permission granted: this fixture tests a password, not a permissions policy.
PERMISSIONS = -1


def rc4(key, data):
    """RC4 of data under key, both bytes."""
    box = list(range(256))
    j = 0
    for i in range(256):
        j = (j + box[i] + key[i % len(key)]) & 0xFF
        box[i], box[j] = box[j], box[i]
    out = bytearray()
    i = j = 0
    for byte in data:
        i = (i + 1) & 0xFF
        j = (j + box[i]) & 0xFF
        box[i], box[j] = box[j], box[i]
        out.append(byte ^ box[(box[i] + box[j]) & 0xFF])
    return bytes(out)


def padded(password):
    """A password padded or truncated to the 32 bytes the key schedule takes."""
    return (password.encode('latin-1') + PAD)[:32]


def owner_entry(owner, user):
    """The /O entry: the user password encrypted under a key made from the owner password."""
    return rc4(hashlib.md5(padded(owner)).digest()[:5], padded(user))


def file_key(user, owner_value, permissions=PERMISSIONS, file_id=FILE_ID):
    """The 40-bit file encryption key (Algorithm 2)."""
    digest = hashlib.md5(padded(user) + owner_value + struct.pack('<i', permissions) + file_id)
    return digest.digest()[:5]


def object_key(key, number, generation=0):
    """The key for one indirect object (Algorithm 1)."""
    extended = key + struct.pack('<i', number)[:3] + struct.pack('<i', generation)[:2]
    return hashlib.md5(extended).digest()[:min(len(key) + 5, 16)]


def encrypted_pdf(user='reflow', owner='reflow-owner', text=None):
    """A one-page PDF locked with `user`, whose page draws `text`."""
    text = 'A locked page reflows once its password unlocks it.' if text is None else text
    owner_value = owner_entry(owner, user)
    key = file_key(user, owner_value)
    content = b'BT /F1 14 Tf 40 120 Td (' + text.encode('ascii') + b') Tj ET'
    # Streams and strings are encrypted; the encryption dictionary's own entries are not.
    stream = rc4(object_key(key, 4), content)
    objects = [
        b'<< /Type /Catalog /Pages 2 0 R >>',
        b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
        b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 200] '
        b'/Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
        b'<< /Length %d >>\nstream\n' % len(stream) + stream + b'\nendstream',
        b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
        b'<< /Filter /Standard /V 1 /R 2 /O <%s> /U <%s> /P %d >>'
        % (owner_value.hex().encode('ascii'), rc4(key, PAD).hex().encode('ascii'), PERMISSIONS),
    ]
    data = bytearray(b'%PDF-1.4\n')
    offsets = []
    for number, obj in enumerate(objects, start=1):
        offsets.append(len(data))
        data += b'%d 0 obj\n' % number + obj + b'\nendobj\n'
    start = len(data)
    data += b'xref\n0 %d\n0000000000 65535 f \n' % (len(objects) + 1)
    for offset in offsets:
        data += b'%010d 00000 n \n' % offset
    identifier = FILE_ID.hex().encode('ascii')
    data += (b'trailer\n<< /Size %d /Root 1 0 R /Encrypt %d 0 R /ID [<%s> <%s>] >>\n'
             b'startxref\n%d\n%%%%EOF\n'
             % (len(objects) + 1, len(objects), identifier, identifier, start))
    return bytes(data)
