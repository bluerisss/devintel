// DevIntel knowledge map.
//
// Plain DOM, no framework and no build step: the page is a search box, two
// lists and a diagram served from a RubyGem, and a toolchain would outweigh
// all of it. The JSON API is the contract, so this file can be replaced by a
// framework later without touching the server.
"use strict";

const el = (id) => document.getElementById(id);
const SEARCH_DEBOUNCE_MS = 120;

let selected = null;

/* ---------- API ---------- */

async function fetchJson(path) {
  const response = await fetch(path, { headers: { Accept: "application/json" } });
  const body = await response.json();

  if (!response.ok) throw new Error(body.error || `Request failed (${response.status})`);
  return body;
}

/* ---------- rendering helpers ---------- */

// Everything from the index is inserted as text, never as markup: symbol names
// come from the user's source code and must not be able to act as HTML.
function text(tag, className, value) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (value !== undefined) node.textContent = value;
  return node;
}

function badge(evidence) {
  return text("span", `badge ${evidence}`, evidence);
}

/* ---------- search ---------- */

async function runSearch(query) {
  const list = el("results");
  const empty = el("results-empty");

  if (!query.trim()) {
    list.replaceChildren();
    empty.textContent = "Type to search classes, modules, methods and constants.";
    empty.hidden = false;
    return;
  }

  const { results } = await fetchJson(`/api/search?q=${encodeURIComponent(query)}`);
  list.replaceChildren(...results.map(resultRow));
  empty.textContent = results.length ? "" : `Nothing in the index matches “${query}”.`;
  empty.hidden = results.length > 0;
}

function resultRow(result) {
  const button = text("button");
  button.append(
    text("div", "name", result.qualified_name),
    text("div", "kind", result.type.replace(/_/g, " ")),
    text("div", "path", `${result.path}:${result.line_start}`)
  );
  button.addEventListener("click", () => select(result.qualified_name));

  const item = document.createElement("li");
  item.append(button);
  return item;
}

/* ---------- symbol detail ---------- */

async function select(name) {
  selected = name;
  let data;

  try {
    data = await fetchJson(`/api/symbol?name=${encodeURIComponent(name)}`);
  } catch (error) {
    el("detail").hidden = true;
    el("detail-empty").textContent = error.message;
    el("detail-empty").hidden = false;
    return;
  }

  el("detail-empty").hidden = true;
  el("detail").hidden = false;
  render(data);
  markSelected(data.query);
}

function markSelected(name) {
  for (const button of el("results").querySelectorAll("button")) {
    const match = button.querySelector(".name").textContent === name;
    button.setAttribute("aria-current", match ? "true" : "false");
  }
}

function render(data) {
  el("symbol-name").textContent = data.query;

  el("definitions").replaceChildren(
    ...(data.definitions.length
      ? data.definitions.map((definition) => {
          const item = document.createElement("li");
          item.append(
            text("span", "kind", `${definition.type.replace(/_/g, " ")} `),
            text("span", "path", `${definition.path}:${definition.line_start}-${definition.line_end}`)
          );
          return item;
        })
      : [text("li", "meta", "not defined in this repository")])
  );

  renderEdges("callers", data.callers);
  renderEdges("callees", data.callees);
  renderUntraced(data.untraced);
  renderTests(data.tests);
  drawGraph(data);
}

function renderEdges(section, relations) {
  el(`${section}-count`).textContent = relations.length ? `(${relations.length})` : "(none)";
  el(section).replaceChildren(...relations.map(edgeRow));
}

function edgeRow(relation) {
  const item = document.createElement("li");
  const link = text("button", null, relation.qualified_name);
  link.addEventListener("click", () => select(relation.qualified_name));

  const meta = text("div", "meta");
  meta.append(
    badge(relation.evidence),
    text("span", null, ` ${relation.type} `),
    text("span", null, relation.reaches ? `${relation.reaches} ` : ""),
    text("span", null, relation.location),
    text("span", null, relation.occurrences > 1 ? `  (${relation.occurrences} sites)` : "")
  );

  item.append(link, meta);
  return item;
}

// Relationships that exist but lead where DevIntel cannot follow are stated,
// not omitted: an empty callees list would otherwise read as "depends on
// nothing".
function renderUntraced(untraced) {
  const entries = Object.entries(untraced || {});
  const total = entries.reduce((sum, [, count]) => sum + count, 0);
  const detail = entries.map(([resolution, count]) => `${resolution.replace(/_/g, " ")} ${count}`).join(", ");

  el("untraced").textContent = total
    ? `+ ${total} relationship${total === 1 ? "" : "s"} DevIntel could not follow (${detail})`
    : "";
}

function renderTests(tests) {
  el("tests-count").textContent = tests.length ? `(${tests.length})` : "(none)";
  el("tests").replaceChildren(
    ...tests.map((test) => {
      const item = document.createElement("li");
      item.append(text("span", "path", `${test.path}:${test.line}`));
      return item;
    })
  );
}

/* ---------- graph ---------- */

const GRAPH = {
  nodeWidth: 230,
  nodeHeight: 30,
  gapY: 10,
  columnGap: 90,
  padding: 16,
  maxPerSide: 8
};

// A deliberate three-column layout rather than a force-directed cloud: the
// view answers one question — what reaches this symbol and what it reaches —
// and direction is the whole point. A physics simulation would scramble it.
function drawGraph(data) {
  const callers = unique(data.callers).slice(0, GRAPH.maxPerSide);
  const callees = unique(data.callees).slice(0, GRAPH.maxPerSide);
  const rows = Math.max(callers.length, callees.length, 1);
  const height = rows * (GRAPH.nodeHeight + GRAPH.gapY) + GRAPH.padding * 2;
  const width = GRAPH.nodeWidth * 3 + GRAPH.columnGap * 2 + GRAPH.padding * 2;

  const svg = svgEl("svg", { viewBox: `0 0 ${width} ${height}`, role: "img" });
  const centerX = GRAPH.padding + GRAPH.nodeWidth + GRAPH.columnGap;
  const rightX = centerX + GRAPH.nodeWidth + GRAPH.columnGap;
  const centerY = height / 2 - GRAPH.nodeHeight / 2;

  callers.forEach((relation, i) => {
    const y = columnY(i, callers.length, height);
    svg.append(
      link(GRAPH.padding + GRAPH.nodeWidth, y, centerX, centerY, relation.evidence),
      node(GRAPH.padding, y, relation.qualified_name, relation.evidence)
    );
  });

  callees.forEach((relation, i) => {
    const y = columnY(i, callees.length, height);
    svg.append(
      link(centerX + GRAPH.nodeWidth, centerY, rightX, y, relation.evidence),
      node(rightX, y, relation.qualified_name, relation.evidence)
    );
  });

  svg.append(node(centerX, centerY, data.query, null, true));
  el("graph").replaceChildren(svg);
}

// One node per related symbol: the same caller reaching two members is one box
// with the strongest evidence it has, not two overlapping ones.
function unique(relations) {
  const byName = new Map();

  for (const relation of relations) {
    const existing = byName.get(relation.qualified_name);
    if (!existing || rank(relation.evidence) < rank(existing.evidence)) {
      byName.set(relation.qualified_name, relation);
    }
  }
  return [...byName.values()];
}

const rank = (evidence) => ({ FACT: 0, INFERENCE: 1, UNKNOWN: 2 })[evidence] ?? 3;

function columnY(index, count, height) {
  const block = count * (GRAPH.nodeHeight + GRAPH.gapY) - GRAPH.gapY;
  return (height - block) / 2 + index * (GRAPH.nodeHeight + GRAPH.gapY);
}

function svgEl(name, attributes) {
  const node = document.createElementNS("http://www.w3.org/2000/svg", name);
  for (const [key, value] of Object.entries(attributes)) node.setAttribute(key, value);
  return node;
}

function node(x, y, label, evidence, focus = false) {
  const group = svgEl("g", { class: `node${focus ? " focus" : ""}`, tabindex: "0", role: "button" });
  group.append(
    svgEl("rect", { x, y, width: GRAPH.nodeWidth, height: GRAPH.nodeHeight, rx: 5 }),
    svgTitle(label)
  );

  const caption = svgEl("text", { x: x + 9, y: y + GRAPH.nodeHeight / 2 + 4 });
  caption.textContent = truncate(label, 30);
  group.append(caption);

  if (!focus) {
    group.addEventListener("click", () => select(label));
    group.addEventListener("keydown", (event) => {
      if (event.key === "Enter" || event.key === " ") select(label);
    });
  }
  if (evidence) group.classList.add(evidence);
  return group;
}

function svgTitle(label) {
  const title = svgEl("title", {});
  title.textContent = label;
  return title;
}

function link(x1, y1, x2, y2, evidence) {
  const midX = (x1 + x2) / 2;

  return svgEl("path", {
    class: `edge ${evidence || "UNKNOWN"}`,
    d: `M ${x1} ${y1 + GRAPH.nodeHeight / 2} C ${midX} ${y1 + GRAPH.nodeHeight / 2}, ` +
       `${midX} ${y2 + GRAPH.nodeHeight / 2}, ${x2} ${y2 + GRAPH.nodeHeight / 2}`
  });
}

// The full name is always available through the node's <title>.
const truncate = (value, max) => (value.length <= max ? value : `…${value.slice(-(max - 1))}`);

/* ---------- boot ---------- */

function debounce(fn, delay) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), delay);
  };
}

async function boot() {
  try {
    const stats = await fetchJson("/api/stats");
    el("stats").textContent =
      `${stats.files} files · ${stats.symbols} symbols · ${stats.relationships} relationships`;
  } catch (error) {
    el("stats").textContent = error.message;
  }

  const search = el("search");
  search.addEventListener("input", debounce((event) => runSearch(event.target.value), SEARCH_DEBOUNCE_MS));
  search.focus();
}

boot();
