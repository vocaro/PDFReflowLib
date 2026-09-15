import { EPUB } from './lib/epub.js';

const $ = id => document.getElementById(id);
const frame = $('reader');
let book, manifest, chapter = 0, anchor = '';
const fail = error => { $('error').textContent = String(error.message || error); $('error').hidden = false; };

function flatten(items, depth = 0) {
  return items.flatMap(item => [{...item, depth}, ...flatten(item.subitems || [], depth + 1)]);
}

function typography() {
  const doc = frame.contentDocument;
  if (!doc?.body) return;
  doc.body.style.fontSize = `${$('size').value}px`;
}

function align() {
  const doc = frame.contentDocument;
  const target = anchor && doc?.getElementById(anchor);
  frame.contentWindow.scrollTo(0, target ? target.getBoundingClientRect().top + doc.documentElement.scrollTop : 0);
}

function navigate(href) {
  const [path, fragment = ''] = href.split('#');
  const index = book.sections.findIndex(section => section.id === path);
  if (index < 0) throw new Error(`Navigation does not resolve to the EPUB spine: ${href}`);
  chapter = index; anchor = decodeURIComponent(fragment);
  const preview = new URL('epub/' + path.replace(/\.xhtml$/, '.html'), location.href).href;
  if (frame.src === preview) align(); else frame.src = preview;
  $('previous').disabled = index === 0;
  $('next').disabled = index === book.sections.length - 1;
  $('position').textContent = `EPUB chapter ${index + 1} of ${book.sections.length} · Scroll to read`;
}

async function start() {
  manifest = await (await fetch('book.json')).json();
  // Foliate independently parses the actual container, OPF, spine and EPUB navigation.
  // The chapter surface uses equivalent HTML serialization for browser compatibility.
  const load = async name => {
    if (!Object.hasOwn(manifest.resources, name)) return null;
    const response = await fetch('epub/' + name.split('/').map(encodeURIComponent).join('/'));
    if (!response.ok) throw new Error(`Cannot read EPUB resource: ${name}`);
    return response;
  };
  book = await new EPUB({
    loadText: async name => (await load(name))?.text() ?? null,
    loadBlob: async name => (await load(name))?.blob() ?? null,
    getSize: name => manifest.resources[name] ?? 0,
  }).init();
  if (!book.sections.length) throw new Error('The EPUB has no readable spine');
  $('title').textContent = book.metadata.title || manifest.filename;
  $('title').title = `EPUB SHA-256: ${manifest.identity.sha256}`;
  document.title = `${manifest.filename} · PDFReflowLib test reader`;
  const toc = flatten(book.toc || []);
  const navigation = toc.length ? toc : book.sections.map((section, index) => ({label: `Chapter ${index + 1}`, href: section.id, depth: 0}));
  $('contents').add(new Option('Choose a heading…', ''));
  navigation.forEach((item, index) => $('contents').add(new Option('  '.repeat(item.depth) + item.label, index)));
  for (const page of Object.keys(manifest.pages).sort((a, b) => a - b)) $('page').add(new Option(page, page));
  frame.addEventListener('load', () => {
    typography(); align();
    const doc = frame.contentDocument;
    doc.addEventListener('click', event => {
      if (event.target.closest('a')) event.preventDefault();
    });
    const markers = [...doc.querySelectorAll('[role="doc-pagebreak"]')];
    const updatePage = () => {
      const current = markers.findLast(marker => marker.getBoundingClientRect().top <= 30) || markers[0];
      if (current) $('page').value = current.id.replace('page-', '');
    };
    doc.addEventListener('scroll', updatePage, {passive: true});
    updatePage();
  });
  const safeNavigate = href => { try { navigate(href); } catch (error) { fail(error); } };
  $('previous').onclick = () => safeNavigate(book.sections[chapter - 1].id);
  $('next').onclick = () => safeNavigate(book.sections[chapter + 1].id);
  $('contents').onchange = () => { if ($('contents').value !== '') safeNavigate(navigation[Number($('contents').value)].href); };
  $('page').onchange = () => safeNavigate(manifest.pages[$('page').value]);
  $('size').onchange = typography;
  $('width').onchange = () => { frame.style.width = $('width').value; };
  navigate(book.sections[0].id);
}
start().catch(fail);
