"use strict";
const element = id => document.getElementById(id);
let manifest;
let selected;
const notes = new Map();

function currentPage() { return manifest.pages.find(page => page.number === Number(element("page").value)); }

function saveNote() {
  if (selected !== undefined) notes.set(selected, element("notes").value);
}

function resizeViews() {
  const width = element("width").value;
  for (const id of ["epub", "poppler"]) {
    element(id).style.width = width === "full" ? "100%" : `${width}px`;
  }
  const frame = element("poppler");
  const doc = frame.contentDocument;
  if (doc?.body) {
    doc.documentElement.style.zoom = 1;
    if (element("mode").value === "positioned") {
      const page = doc.getElementById(`page${currentPage().number}-div`);
      if (page) doc.documentElement.style.zoom = Math.min(1, (frame.clientWidth - 20) / page.offsetWidth);
    }
  }
}

function alignEPUB() {
  const frame = element("epub");
  const marker = frame.contentDocument?.getElementById(`page-${currentPage().number}`);
  if (marker) {
    // An inline marker may sit inside a word. Scroll without adding visible text or splitting it.
    const doc = frame.contentDocument;
    const top = marker.getBoundingClientRect().top + doc.documentElement.scrollTop;
    frame.contentWindow.scrollTo(0, top);
  }
}

function showPage() {
  saveNote();
  const page = currentPage();
  selected = page.number;
  element("notes").value = notes.get(selected) || "";
  element("notes-status").textContent = "";
  const index = manifest.pages.indexOf(page);
  element("previous").disabled = index === 0;
  element("next").disabled = index === manifest.pages.length - 1;
  const epub = element("epub");
  const desired = new URL(page.epub, location.href);
  if (epub.src.split("#")[0] === desired.href.split("#")[0]) {
    alignEPUB();
  } else {
    // Native fragment navigation can scroll the outer review page as well as the iframe.
    // Navigate to the chapter alone and align its source marker when its images finish loading.
    desired.hash = "";
    epub.src = desired.href;
  }
  const mode = element("mode").value;
  element("poppler").src = page[mode];
  element("source").src = page.source;
  element("source").parentElement.scrollTop = 0;
  element("source").alt = `Original PDF, physical page ${page.number}`;
  element("mode-label").textContent = mode === "simple" ? "Simple HTML" : "Positioned HTML";
  element("poppler-note").textContent = mode === "simple"
    ? "Original pdftohtml output for this page; hard line breaks are retained."
    : "Fixed page geometry, scaled to fit. Placement can conceal a poor text reading order.";
  const warnings = manifest.report.warnings.filter(warning => warning.page === page.number);
  element("warning-count").textContent = `Page ${page.number} · ${warnings.length} PDFReflowLib warning${warnings.length === 1 ? "" : "s"}`;
  element("warning-list").replaceChildren(...warnings.map(warning => {
    const item = document.createElement("li");
    item.textContent = `${warning.code}: ${warning.message}`;
    return item;
  }));
  history.replaceState(null, "", `#page=${page.number}`);
  resizeViews();
}

async function start() {
  const response = await fetch("comparison.json");
  if (!response.ok) throw new Error("Cannot load the comparison manifest");
  manifest = await response.json();
  if (manifest.status !== "ready" || !manifest.pages.length) throw new Error("Comparison is incomplete");
  document.title = `${manifest.sourceName} · PDF comparison`;
  element("title").textContent = manifest.sourceName;
  element("summary").textContent = `${manifest.pageCount} source pages · ${manifest.pages.length} prepared for review · ${manifest.report.reflowedPageCount} pages with reflowed text · ${manifest.report.imageCount} images`;
  element("page-count").textContent = `of ${manifest.pageCount}`;
  element("page").replaceChildren(...manifest.pages.map(page => {
    const option = document.createElement("option");
    option.value = page.number;
    option.textContent = page.number;
    return option;
  }));
  const requested = Number(new URLSearchParams(location.hash.slice(1)).get("page"));
  if (manifest.pages.some(page => page.number === requested)) element("page").value = requested;
  element("run-details").textContent = [
    manifest.platform,
    `Input SHA-256: ${manifest.source.sha256}`,
    `Converter SHA-256: ${manifest.converter.sha256}`,
    manifest.popplerVersion,
    "PDFReflowLib converts the complete book; Poppler converts selected pages independently.",
    "Timings in the manifest describe commands with different scopes, not a speed comparison."
  ].join("\n");
  for (const id of ["epub", "poppler"]) {
    element(id).addEventListener("load", () => {
      // Source links are review content, not navigation controls or network authorization.
      element(id).contentDocument?.addEventListener("click", event => {
        if (event.target.closest("a")) event.preventDefault();
      });
      if (id === "epub") alignEPUB(); else resizeViews();
    });
  }
  element("page").addEventListener("change", showPage);
  element("mode").addEventListener("change", showPage);
  element("width").addEventListener("change", () => { resizeViews(); alignEPUB(); });
  element("reset").addEventListener("click", showPage);
  for (const [id, step] of [["previous", -1], ["next", 1]]) {
    element(id).addEventListener("click", () => {
      element("page").selectedIndex += step;
      showPage();
    });
  }
  element("show-source").addEventListener("change", () => {
    const show = element("show-source").checked;
    element("source-pane").hidden = !show;
    element("panes").classList.toggle("with-source", show);
    resizeViews(); alignEPUB();
  });
  element("export-notes").addEventListener("click", () => {
    saveNote();
    const review = {schemaVersion: 1, source: manifest.source, converter: manifest.converter,
      epub: manifest.epub, popplerVersion: manifest.popplerVersion,
      pages: [...notes].filter(([, note]) => note.trim()).map(([page, note]) => ({page, note}))};
    const url = URL.createObjectURL(new Blob([JSON.stringify(review, null, 2) + "\n"], {type: "application/json"}));
    const link = document.createElement("a");
    link.href = url; link.download = "review-notes.json"; link.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
    element("notes-status").textContent = `Exported notes for ${review.pages.length} pages.`;
  });
  addEventListener("beforeunload", event => {
    saveNote();
    if ([...notes.values()].some(note => note.trim())) { event.preventDefault(); event.returnValue = ""; }
  });
  addEventListener("resize", resizeViews);
  showPage();
}
start().catch(error => { element("summary").textContent = error.message + ". Start the supplied local server; file:// is unsupported."; });
