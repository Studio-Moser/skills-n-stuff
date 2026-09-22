const machinesRoot = document.querySelector("#machines");
const message = document.querySelector("#message");
const search = document.querySelector("#search");
const sync = document.querySelector(".sync");
const syncLabel = document.querySelector("#sync-label");
const filters = [...document.querySelectorAll(".filter")];

let inventory = null;
let activeFilter = "all";

function textNode(tag, className, value) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  element.textContent = value;
  return element;
}

function stateLabel(state) {
  if (state === "live") return "Live";
  if (state === "saved") return "Saved";
  return "Unavailable";
}

function previewMatches(preview, machineName, query) {
  const matchesQuery = `${preview.project} ${preview.service} ${machineName}`
    .toLocaleLowerCase()
    .includes(query);
  const matchesFilter =
    activeFilter === "all" ||
    (activeFilter === "live" && preview.state === "live") ||
    (activeFilter === "saved" && preview.state !== "live");
  return matchesQuery && matchesFilter;
}

function render() {
  if (!inventory) return;
  const query = search.value.trim().toLocaleLowerCase();
  machinesRoot.replaceChildren();
  let shown = 0;

  for (const machine of inventory.machines) {
    const previews = machine.previews.filter((preview) =>
      previewMatches(preview, machine.name, query),
    );
    if (!previews.length) continue;
    shown += previews.length;

    const section = document.createElement("section");
    section.className = `machine${machine.connected ? "" : " is-offline"}`;
    const heading = document.createElement("div");
    heading.className = "machine-heading";
    heading.append(
      textNode("h2", "", machine.name),
      textNode("span", "machine-state", machine.connected ? "Connected" : "Offline"),
    );
    section.append(heading);

    const list = document.createElement("div");
    list.className = "preview-list";
    for (const preview of previews) {
      const row = document.createElement("article");
      row.className = "preview";

      const project = document.createElement("div");
      project.className = "project";
      project.append(
        textNode("strong", "", preview.project),
        textNode(
          "small",
          "",
          preview.sharedHosts > 1
            ? `${preview.service} · ${preview.sharedHosts} hosts`
            : preview.service,
        ),
      );
      row.append(project, textNode("span", "kind", preview.kind));

      const state = textNode("span", `state${preview.state === "live" ? " is-live" : ""}`, stateLabel(preview.state));
      row.append(state);

      const open = document.createElement("a");
      open.className = "open-preview";
      open.textContent = preview.state === "live" ? "Open" : "Not available";
      if (preview.state === "live" && preview.url.startsWith("https://preview-")) {
        open.href = preview.url;
      } else {
        open.setAttribute("aria-disabled", "true");
      }
      row.append(open);
      list.append(row);
    }
    section.append(list);
    machinesRoot.append(section);
  }

  message.textContent = shown ? "" : "No previews match this view.";
}

function updateSummary(data) {
  document.querySelector("#live-count").textContent = data.counts.live;
  document.querySelector("#service-count").textContent = data.counts.services;
  document.querySelector("#machine-count").textContent = data.counts.machines;
  const updated = new Date(data.updatedAt);
  syncLabel.textContent = `Updated ${updated.toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })}`;
  sync.classList.remove("is-error");
}

async function refresh() {
  const controller = new AbortController();
  const timeout = window.setTimeout(() => controller.abort(), 20000);
  try {
    const response = await fetch("/api/previews", {
      cache: "no-store",
      signal: controller.signal,
    });
    if (!response.ok) throw new Error("inventory request failed");
    inventory = await response.json();
    updateSummary(inventory);
    render();
  } catch {
    sync.classList.add("is-error");
    syncLabel.textContent = "Inventory unavailable";
    if (!inventory) message.textContent = "The preview inventory could not be loaded. It will retry automatically.";
  } finally {
    window.clearTimeout(timeout);
  }
}

search.addEventListener("input", render);
for (const filter of filters) {
  filter.addEventListener("click", () => {
    activeFilter = filter.dataset.filter;
    for (const candidate of filters) {
      const selected = candidate === filter;
      candidate.classList.toggle("is-active", selected);
      candidate.setAttribute("aria-pressed", String(selected));
    }
    render();
  });
}

refresh();
window.setInterval(refresh, 30000);
