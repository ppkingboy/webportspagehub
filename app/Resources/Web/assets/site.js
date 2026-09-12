const state = {
  pages: [],
  query: "",
  group: "全部",
};

const grid = document.querySelector("#grid");
const empty = document.querySelector("#empty");
const count = document.querySelector("#page-count");
const search = document.querySelector("#search");
const groups = document.querySelector("#groups");

function pageURL(relativePath) {
  return relativePath
    .split("/")
    .map((component) => encodeURIComponent(component))
    .join("/");
}

function visiblePages() {
  const query = state.query.trim().toLocaleLowerCase("zh-CN");

  return state.pages.filter((page) => page.enabled !== false).filter((page) => {
    const matchesGroup = state.group === "全部" || page.group === state.group;
    const searchable = `${page.title} ${page.relativePath} ${page.group}`.toLocaleLowerCase("zh-CN");
    return matchesGroup && (!query || searchable.includes(query));
  });
}

function renderFilters() {
  const enabledPages = state.pages.filter((page) => page.enabled !== false);
  const allGroups = [...new Set(enabledPages.map((page) => page.group))].sort(
    (left, right) => left.localeCompare(right, "zh-CN")
  );
  const filters = ["全部", ...allGroups];

  groups.replaceChildren(
    ...filters.map((group) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `filter-button${state.group === group ? " is-active" : ""}`;
      button.textContent = group;
      button.addEventListener("click", () => {
        state.group = group;
        render();
      });
      return button;
    })
  );
}

function renderPages() {
  const pages = visiblePages();
  const enabledPages = state.pages.filter((page) => page.enabled !== false);
  grid.replaceChildren(
    ...pages.map((page) => {
      const card = document.createElement("a");
      card.className = "page-card";
      card.href = pageURL(page.relativePath);
      if (page.openInNewWindow) {
        card.target = "_blank";
        card.rel = "noopener";
      }

      const topLine = document.createElement("div");
      topLine.className = "card-topline";

      const group = document.createElement("span");
      group.className = "group-label";
      group.textContent = page.group;

      const open = document.createElement("span");
      open.className = "open-label";
      open.textContent = "打开";

      const title = document.createElement("h2");
      title.textContent = page.title;

      const description = document.createElement("p");
      description.className = "page-description";
      description.textContent = page.description || "";
      description.hidden = !page.description;

      const path = document.createElement("div");
      path.className = "page-path";
      path.textContent = page.relativePath;

      topLine.append(group, open);
      card.append(topLine, title, description, path);
      return card;
    })
  );

  empty.hidden = pages.length !== 0;
  grid.hidden = pages.length === 0;
  count.textContent =
    enabledPages.length === pages.length
      ? `共 ${enabledPages.length} 个页面`
      : `${pages.length} / ${enabledPages.length} 个页面`;
}

function render() {
  renderFilters();
  renderPages();
}

async function loadPages({ preserveState = false } = {}) {
  if (!preserveState) {
    count.textContent = "正在读取页面...";
  }

  try {
    const response = await fetch("./__pages.json", { cache: "no-store" });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`);
    }

    state.pages = await response.json();
    if (!preserveState) {
      state.group = "全部";
    }

    const groups = new Set(state.pages.map((page) => page.group));
    if (state.group !== "全部" && !groups.has(state.group)) {
      state.group = "全部";
    }
    render();
  } catch (error) {
    state.pages = [];
    render();
    count.textContent = "页面读取失败";
    console.error(error);
  }
}

search.addEventListener("input", (event) => {
  state.query = event.target.value;
  renderPages();
});

document.querySelector("#reload").addEventListener("click", loadPages);
loadPages();
setInterval(() => loadPages({ preserveState: true }), 10000);
