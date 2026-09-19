"""Open, admit and read the converter's EPUB archives."""
from contextlib import contextmanager
from pathlib import PurePosixPath
import re
import sys
from typing import NamedTuple
import xml.etree.ElementTree as ET
import zipfile

OPF_NS = 'http://www.idpf.org/2007/opf'
XHTML_NS = 'http://www.w3.org/1999/xhtml'
OPS_NS = 'http://www.idpf.org/2007/ops'
OPF = '{' + OPF_NS + '}'
XHTML = '{' + XHTML_NS + '}'
OPS = '{' + OPS_NS + '}'
NS = {'opf': OPF_NS, 'html': XHTML_NS}
PACKAGE = 'EPUB/package.opf'
MIMETYPE = b'application/epub+zip'
# Admission ceilings for inspection: not process-memory budgets. Images are not expanded;
# chapter XML and accumulated page text still consume memory after admission.
DEFAULT_MAX_ENTRIES = 10_000
DEFAULT_MAX_UNCOMPRESSED_BYTES = 512 * 1024 * 1024
_PAGE_ANCHOR = re.compile(r'page-[1-9]\d*')


def inspection_limit(value, name):
    """An admission ceiling: an int from 1 to sys.maxsize; there is no unlimited value."""
    if type(value) is not int or not 1 <= value <= sys.maxsize:
        raise ValueError(f'{name} must be an integer from 1 to {sys.maxsize}')
    return value


def admit(archive, max_entries, max_uncompressed_bytes):
    """Reject an archive over either ceiling, or with duplicate entry names, before any entry is read."""
    entries = archive.infolist()
    if len(entries) > max_entries or sum(entry.file_size for entry in entries) > max_uncompressed_bytes:
        raise ValueError('EPUB exceeds inspection bounds')
    if len(set(archive.namelist())) != len(entries):
        raise ValueError('Duplicate archive entries')


@contextmanager
def open_archive(path, *, max_entries=DEFAULT_MAX_ENTRIES,
                 max_uncompressed_bytes=DEFAULT_MAX_UNCOMPRESSED_BYTES):
    """Open an EPUB for inspection, admitting it by entry count and total expanded bytes.

    Both limits are validated before the archive is opened, and the archive is admitted from
    its central directory before any entry is read.
    """
    inspection_limit(max_entries, 'max_entries')
    inspection_limit(max_uncompressed_bytes, 'max_uncompressed_bytes')
    with zipfile.ZipFile(path) as archive:
        admit(archive, max_entries, max_uncompressed_bytes)
        yield archive


class Package(NamedTuple):
    version: str | None
    items: dict     # manifest item id -> the item's attributes
    spine: list     # archive names of the spine documents, in reading order


def parse_package(tree, name=PACKAGE):
    """The manifest and spine of a parsed package document stored at `name` in the archive."""
    base = PurePosixPath(name).parent
    items = {item.get('id'): dict(item.attrib) for item in tree.iterfind(OPF + 'manifest/' + OPF + 'item')}
    spine = [str(base / items[reference.get('idref')]['href'])
             for reference in tree.iterfind(OPF + 'spine/' + OPF + 'itemref')]
    return Package(tree.get('version'), items, spine)


def read_package(archive, name=PACKAGE):
    return parse_package(ET.fromstring(archive.read(name)), name)


def is_page_boundary(element):
    return 'pagebreak' in element.get(OPS + 'type', '').split()


def page_boundary(element):
    """The source page number a pagebreak marker names, or None for any other element."""
    if not is_page_boundary(element):
        return None
    anchor = element.get('id', '')
    if not _PAGE_ANCHOR.fullmatch(anchor):
        raise ValueError('Invalid page boundary')
    return int(anchor[len('page-'):])
