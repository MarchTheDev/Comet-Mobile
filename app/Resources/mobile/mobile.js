/*
 * Comet for iOS — the mobile shell
 * --------------------------------------------------------------------------
 * Comet's interface is React and its state lives in that React tree, so this
 * layer does not reimplement any of it. What it does is give the phone its own
 * surfaces and drive them by *pressing the app's own controls*:
 *
 *   - a bar that is glass once content scrolls under it, back and search
 *   - a floating dock: Files, Search, Calendar, Library — with a lens that
 *     slides to the selected tab
 *   - a create button
 *   - a Library sheet for everything the sidebar used to hold
 *   - the Files surface: its own hero, search field, filter chips, folder
 *     tiles and file rows, drawn from the app's rows and pressing them
 *   - long press for the app's own menu, edge swipe to go back, haptics
 *
 * There is no sidebar: a 330pt drawer over a 390pt screen is one app covering
 * another. Comet's sidebar is still in the DOM and still holds its state, and
 * every row in it is still what the shell presses.
 *
 * The anchors below are Comet's accessible names and class names, so a future
 * Comet that renames them breaks this shell. tools/test-mobile.mjs exists to
 * notice that, and every anchor is in one place (DESTINATIONS) so it is a
 * one-line fix.
 */
(function () {
  "use strict";

  if (window.__cometMobileInstalled) return;
  window.__cometMobileInstalled = true;

  /* ---------------------------------------------------------------------- */
  /* Anchors                                                                */
  /* ---------------------------------------------------------------------- */

  var SEARCH_BUTTON = '[aria-label="Search notes"]';
  var CREATE_BUTTON = '[aria-label="Add file or upload"]';
  var HISTORY_BACK = '[aria-label="Go back"]';
  var WORKSPACE_PICKER = ".workspace-picker";

  /*
   * `label` matches the label Comet gives the row. The counts live in the row's
   * <small>, so matching the whole element's text would make every row with a
   * count unmatchable.
   */
  var DESTINATIONS = [
    { key: "files", label: "All files", icon: "files", group: "browse" },
    { key: "pinned", label: "Pinned", icon: "pin", group: "browse" },
    { key: "favorites", label: "Favorites", icon: "star", group: "browse" },
    { key: "tree", label: "Tree view", icon: "tree", group: "browse" },
    { key: "brain", label: "Brain view", icon: "brain", group: "browse" },
    { key: "calendar", label: "Calendar", icon: "calendar", group: "tools" },
    { key: "passwords", label: "Passwords", icon: "lock", group: "tools" },
    { key: "tags", label: "Manage tags", icon: "tag", group: "tools" },
    { key: "settings", label: "Settings", icon: "gear", group: "tools" }
  ];

  var ICONS = {
    back: '<path d="M15 5l-7 7 7 7"/>',
    up: '<path d="M6 15l6-6 6 6"/>',
    search: '<circle cx="10.8" cy="10.8" r="6.3"/><path d="M15.5 15.5 20 20"/>',
    plus: '<path d="M12 5.5v13M5.5 12h13"/>',
    more: '<circle cx="5.5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="18.5" cy="12" r="1.4"/>',
    files: '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3.2l1.8 2h8A2.5 2.5 0 0 1 21 9.5v7A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5z"/>',
    folder: '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3.2l1.8 2h8A2.5 2.5 0 0 1 21 9.5v7A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5z"/>',
    pin: '<path d="M9 4h6l-1 5 3.5 3.5H5.5L9 9z"/><path d="M12 12.5V20"/>',
    star: '<path d="M12 4.5l2.4 4.9 5.4.8-3.9 3.8.9 5.4-4.8-2.6-4.8 2.6.9-5.4L4.2 10.2l5.4-.8z"/>',
    tree: '<path d="M5 5v14M5 8h5M5 13h7M5 18h9"/><circle cx="12.5" cy="8" r="1.4"/><circle cx="14.5" cy="13" r="1.4"/><circle cx="16.5" cy="18" r="1.4"/>',
    brain: '<path d="M9.5 4.8A2.8 2.8 0 0 0 6.7 7.6 2.6 2.6 0 0 0 5 10a2.6 2.6 0 0 0 1 2 2.6 2.6 0 0 0-.6 1.7 2.8 2.8 0 0 0 2.8 2.8c.4 1 1.4 1.7 2.5 1.7V5.6a1.6 1.6 0 0 0-1.2-.8z"/><path d="M14.5 4.8a2.8 2.8 0 0 1 2.8 2.8A2.6 2.6 0 0 1 19 10a2.6 2.6 0 0 1-1 2 2.6 2.6 0 0 1 .6 1.7 2.8 2.8 0 0 1-2.8 2.8c-.4 1-1.4 1.7-2.5 1.7V5.6a1.6 1.6 0 0 1 1.2-.8z"/>',
    calendar: '<rect x="3.5" y="5.5" width="17" height="15" rx="3.4"/><path d="M8 3.5v3.6M16 3.5v3.6M3.5 10.4h17"/>',
    lock: '<rect x="4.5" y="10" width="15" height="10" rx="3"/><path d="M8 10V7.5a4 4 0 0 1 8 0V10"/>',
    tag: '<path d="M4 11.5V5.5A1.5 1.5 0 0 1 5.5 4h6l8.5 8.5-7.5 7.5z"/><circle cx="8.4" cy="8.4" r="1.3"/>',
    gear: '<circle cx="12" cy="12" r="3.1"/><path d="M12 3.6v2M12 18.4v2M4.8 7.9l1.7 1M17.5 15.1l1.7 1M4.8 16.1l1.7-1M17.5 8.9l1.7-1"/>',
    library: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M3.5 9.2h17"/>',
    workspace: '<rect x="3.5" y="6" width="17" height="13" rx="3"/><path d="M3.5 10.5h17"/>',
    chevron: '<path d="M9 5l7 7-7 7"/>',
    note: '<path d="M6 3.5h7.5L19 9v11.5H6z"/><path d="M13.5 3.5V9H19"/><path d="M9 13h6M9 16.5h4"/>',
    text: '<path d="M6 3.5h12v17H6z"/><path d="M9 8h6M9 11.5h6M9 15h4"/>',
    image: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><circle cx="9" cy="10" r="1.6"/><path d="M4.5 17l4.6-4.4 3.4 3.2 2.6-2.4 4.4 4.1"/>',
    pdf: '<path d="M6 3.5h7.5L19 9v11.5H6z"/><path d="M13.5 3.5V9H19"/>',
    book: '<path d="M4 5.5A2 2 0 0 1 6 3.5h5v17H6a2 2 0 0 1-2-2z"/><path d="M20 5.5a2 2 0 0 0-2-2h-5v17h5a2 2 0 0 0 2-2z"/>',
    audio: '<path d="M9 17V6l9-2v11"/><circle cx="7" cy="17.5" r="2.2"/><circle cx="16" cy="15.5" r="2.2"/>',
    video: '<rect x="3.5" y="6" width="17" height="12" rx="3"/><path d="M10 9.5l5 2.5-5 2.5z"/>',
    todo: '<path d="M4.5 7l1.8 1.8L9.5 5.6"/><path d="M4.5 15l1.8 1.8 3.2-3.2"/><path d="M13 7h7M13 15h7"/>',
    board: '<rect x="3.5" y="4.5" width="7" height="15" rx="2"/><rect x="13.5" y="4.5" width="7" height="9" rx="2"/>',
    link: '<path d="M10 14a3.5 3.5 0 0 0 5 0l3-3a3.5 3.5 0 0 0-5-5l-1 1"/><path d="M14 10a3.5 3.5 0 0 0-5 0l-3 3a3.5 3.5 0 0 0 5 5l1-1"/>'
  };

  function icon(name) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + (ICONS[name] || ICONS.files) + "</svg>";
  }

  var KIND_ICON = {
    folder: "folder", markdown: "note", text: "text", image: "image", pdf: "pdf",
    ebook: "book", audio: "audio", video: "video", todo: "todo", whiteboard: "board",
    link: "link", other: "text"
  };

  function groupOf(kind) {
    if (kind === "folder") return "folders";
    if (kind === "markdown" || kind === "text" || kind === "todo" || kind === "whiteboard") return "notes";
    if (kind === "image" || kind === "audio" || kind === "video" || kind === "pdf" || kind === "ebook") return "media";
    return "other";
  }

  /* ---------------------------------------------------------------------- */
  /* The native side                                                         */
  /* ---------------------------------------------------------------------- */

  /*
   * Haptics are most of what makes a tap feel like an app rather than a web
   * page. The bridge answers this command with a real generator; if it is ever
   * missing the promise rejects and nothing else notices.
   */
  function haptic(kind) {
    try {
      var internals = window.__TAURI_INTERNALS__;
      if (!internals || typeof internals.invoke !== "function") return;
      var result = internals.invoke("plugin:haptics|impact", { style: kind || "light" });
      if (result && typeof result.catch === "function") result.catch(function () {});
    } catch (error) { /* a phone without haptics is still a phone */ }
  }

  /* The status bar has to change colour with the theme, or one of the two
     themes has an invisible clock in the corner. */
  var lastStatusBarTheme = null;
  function syncStatusBar() {
    var theme = document.documentElement.getAttribute("data-theme") === "dark" ? "dark" : "light";
    if (theme === lastStatusBarTheme) return;
    lastStatusBarTheme = theme;
    try {
      var internals = window.__TAURI_INTERNALS__;
      if (!internals || typeof internals.invoke !== "function") return;
      var result = internals.invoke("plugin:comet|status_bar", { dark: theme === "dark" });
      if (result && typeof result.catch === "function") result.catch(function () {});
    } catch (error) { /* the default style stands */ }
  }

  /*
   * Which build is installed. A sideloaded app has no App Store to say, and
   * "is this the build with the new chrome?" is the first question anyone asks
   * of a screenshot — so the answer lives in the Library sheet.
   */
  var buildLabel = "";
  function fetchBuild() {
    try {
      var internals = window.__TAURI_INTERNALS__;
      if (!internals || typeof internals.invoke !== "function") return;
      var result = internals.invoke("plugin:app|build", {});
      if (result && typeof result.then === "function") {
        result.then(function (value) {
          if (!value) return;
          buildLabel = String(value);
          if (library) syncLibrary();
        }).catch(function () {});
      }
    } catch (error) { /* the sheet simply omits it */ }
  }

  /* ---------------------------------------------------------------------- */
  /* Driving the app's own controls                                          */
  /* ---------------------------------------------------------------------- */

  function one(selector) {
    return selector ? document.querySelector(selector) : null;
  }

  function navRow(label) {
    var rows = document.querySelectorAll(".sidebar .nav-item");
    for (var index = 0; index < rows.length; index++) {
      var caption = rows[index].querySelector("span");
      var text = (caption || rows[index]).textContent || "";
      if (text.trim() === label) return rows[index];
    }
    return null;
  }

  function destinationRow(key) {
    for (var index = 0; index < DESTINATIONS.length; index++) {
      if (DESTINATIONS[index].key === key) return navRow(DESTINATIONS[index].label);
    }
    return null;
  }

  /*
   * Target `inert` containers: the sidebar is `inert` whenever Comet thinks it
   * is closed, and it is always closed here because it is never drawn. Lifting
   * it for the duration of a programmatic press is the difference between a
   * button that works and a button that silently does nothing. The same holds
   * for a row inside a panel that has been moved off-screen.
   */
  function press(element, coords) {
    if (!element) return false;
    var container = element.closest("[inert]");
    if (container) {
      container.removeAttribute("inert");
      container.removeAttribute("aria-hidden");
    }
    try {
      element.dispatchEvent(new MouseEvent("click", {
        bubbles: true,
        cancelable: true,
        view: window,
        clientX: coords && coords.x ? coords.x : 0,
        clientY: coords && coords.y ? coords.y : 0
      }));
    } finally {
      if (container) {
        container.setAttribute("inert", "");
        container.setAttribute("aria-hidden", "true");
      }
    }
    return true;
  }

  function openSearch() {
    haptic("light");
    press(one(SEARCH_BUTTON));
  }

  function openCreateMenu() {
    var create = one(CREATE_BUTTON);
    if (!create) return;
    // The app places its menu at the pointer; there is no pointer here, so it
    // is given the bottom of the screen and mobile.css turns it into a sheet.
    press(create, { x: Math.round(window.innerWidth - 28), y: Math.round(window.innerHeight - 120) });
  }

  /* ---------------------------------------------------------------------- */
  /* Where we are                                                           */
  /* ---------------------------------------------------------------------- */

  function readLocation() {
    var workspace = one(".workspace-picker-copy strong");
    var workspaceName = workspace ? (workspace.textContent || "").trim() : "Comet";

    var heading = one(".document-heading h2");
    var file = heading ? (heading.textContent || "").trim() : "";
    var pathField = one('input[aria-label="Workspace path"]');
    var path = pathField && pathField.value ? pathField.value.trim() : "";

    if (file) return { title: file, detail: path || workspaceName, document: true };

    var active = one(".primary-nav .nav-item.active, .sidebar-bottom .nav-item.active");
    var caption = active ? active.querySelector("span") : null;
    var view = caption ? (caption.textContent || "").trim() : "";
    return { title: workspaceName, detail: view || "Workspace", document: false };
  }

  function activeDestination() {
    var active = one(".primary-nav .nav-item.active, .sidebar-bottom .nav-item.active");
    if (!active) return "";
    for (var index = 0; index < DESTINATIONS.length; index++) {
      if (destinationRow(DESTINATIONS[index].key) === active) return DESTINATIONS[index].key;
    }
    return "";
  }

  function backAction() {
    var history = one(HISTORY_BACK);
    if (history && !history.disabled) return function () { press(history); };
    if (readLocation().document) {
      var filesRow = destinationRow("files");
      if (filesRow) return function () { press(filesRow); };
    }
    return null;
  }

  /* ---------------------------------------------------------------------- */
  /* The bar                                                                */
  /* ---------------------------------------------------------------------- */

  function buildBar() {
    var bar = document.createElement("header");
    bar.className = "m-bar";
    bar.setAttribute("role", "banner");

    var back = document.createElement("button");
    back.type = "button";
    back.className = "m-bar-button m-bar-back";
    back.setAttribute("aria-label", "Go back");
    back.innerHTML = icon("back");
    back.hidden = true;
    back.addEventListener("click", function () {
      var action = backAction();
      if (!action) return;
      haptic("light");
      action();
    });

    var title = document.createElement("div");
    title.className = "m-bar-title";
    title.appendChild(document.createElement("strong"));
    title.appendChild(document.createElement("small"));

    var search = document.createElement("button");
    search.type = "button";
    search.className = "m-bar-button m-bar-search";
    search.setAttribute("aria-label", "Search");
    search.innerHTML = icon("search");
    search.addEventListener("click", openSearch);

    bar.appendChild(back);
    bar.appendChild(title);
    bar.appendChild(search);
    return bar;
  }

  /* ---------------------------------------------------------------------- */
  /* The dock, with a lens that travels                                     */
  /* ---------------------------------------------------------------------- */

  var DOCK = [
    { key: "files", label: "Files", icon: "files" },
    { key: "search", label: "Search", icon: "search" },
    { key: "calendar", label: "Calendar", icon: "calendar" },
    { key: "library", label: "Library", icon: "library" }
  ];

  function buildDock() {
    var dock = document.createElement("nav");
    dock.className = "m-dock";
    dock.setAttribute("role", "navigation");
    dock.setAttribute("aria-label", "Comet");

    // One lens for the whole bar, moved between tabs, so the highlight slides
    // instead of blinking from one item to the next.
    var lens = document.createElement("span");
    lens.className = "m-dock-lens";
    lens.setAttribute("aria-hidden", "true");

    DOCK.forEach(function (tab) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = "m-dock-item";
      button.setAttribute("aria-label", tab.label);
      button.dataset.tab = tab.key;
      button.innerHTML = icon(tab.icon) + "<span>" + tab.label + "</span>";

      button.addEventListener("click", function () {
        if (tab.key === "search") return openSearch();
        if (tab.key === "library") return toggleLibrary();
        haptic("light");
        markTab(tab.key);
        var row = destinationRow(tab.key);
        if (row) press(row);
        closeLibrary();
      });

      dock.appendChild(button);
    });

    dock.insertBefore(lens, dock.firstChild);
    return dock;
  }

  /*
   * The lens moves under the finger, not one React render later: the state is
   * set optimistically here and corrected by paint() once the app has actually
   * navigated.
   */
  function markTab(key) {
    var items = document.querySelectorAll(".m-dock-item");
    var index = -1;
    for (var cursor = 0; cursor < items.length; cursor++) {
      if (items[cursor].dataset.tab === key) index = cursor;
    }
    for (var item = 0; item < items.length; item++) {
      if (items[item].dataset.tab === key) items[item].setAttribute("aria-current", "page");
      else items[item].removeAttribute("aria-current");
    }
    moveLens(index);
  }

  function moveLens(index) {
    var lens = one(".m-dock-lens");
    if (!lens) return;
    if (index < 0) {
      lens.dataset.active = "false";
      return;
    }
    lens.dataset.active = "true";
    lens.style.transform = "translate3d(" + (index * 100) + "%, 0, 0)";
  }

  function buildCreate() {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "m-create";
    button.setAttribute("aria-label", "New");
    button.innerHTML = icon("plus");
    button.addEventListener("click", function () {
      haptic("medium");
      openCreateMenu();
    });
    return button;
  }

  /* ---------------------------------------------------------------------- */
  /* The Files surface                                                      */
  /* ---------------------------------------------------------------------- */

  var FILTERS = [
    { key: "all", label: "All" },
    { key: "folders", label: "Folders" },
    { key: "notes", label: "Notes" },
    { key: "media", label: "Media" }
  ];

  var files = { root: null, view: null, body: null, head: null, hero: null, signature: "", filter: "all", animTimer: 0, everShown: false };

  function element(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = text;
    return node;
  }

  /*
   * The app re-renders its rows on every navigation, so a reference captured
   * while drawing a tile is detached by the time the tile is pressed. Tiles
   * therefore remember a path and look the row up again when they are used.
   */
  function appRowByPath(path) {
    var rows = document.querySelectorAll(".workspace-entry");
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].dataset.path === path) return rows[index];
    }
    return null;
  }

  function openEntry(path) {
    var row = appRowByPath(path);
    return row ? press(row.querySelector(".workspace-entry-open")) : false;
  }

  function menuEntry(path, coords) {
    var row = appRowByPath(path);
    if (!row) return false;
    return press(row.querySelector(".workspace-entry-more") ||
      row.querySelector('[aria-label^="More options for"]'), coords);
  }

  function readEntries() {
    var rows = document.querySelectorAll(".workspace-panel .workspace-entry");
    var list = [];
    for (var index = 0; index < rows.length; index++) {
      var row = rows[index];
      var iconEl = row.querySelector(".workspace-entry-icon");
      var classes = iconEl ? String(iconEl.className).split(/\s+/) : [];
      var kind = "other";
      for (var cursor = 0; cursor < classes.length; cursor++) {
        if (classes[cursor] && classes[cursor] !== "workspace-entry-icon") kind = classes[cursor];
      }
      var labelEl = row.querySelector(".workspace-entry-copy strong");
      var metaEl = row.querySelector(".workspace-entry-copy small");
      list.push({
        path: row.dataset.path || "",
        kind: kind,
        group: groupOf(kind),
        label: (labelEl && (labelEl.getAttribute("title") || labelEl.textContent) || "").trim(),
        meta: (metaEl && metaEl.textContent || "").replace(/\s*·\s*Workspace$/, "").trim(),
        pinned: Boolean(row.querySelector('.entry-badges [aria-label="Pinned"]')),
        favorite: Boolean(row.querySelector('.entry-badges [aria-label="Favorite"]'))
      });
    }
    return list;
  }

  function buildFiles() {
    var root = element("div", "m-files");
    root.dataset.away = "true";

    var view = element("div", "m-files-view");
    view.dataset.role = "view";

    var hero = element("header", "m-files-hero");
    var art = element("div", "m-files-hero-art");
    var heroBody = element("div", "m-files-hero-body");
    var up = element("button", "m-files-up");
    up.type = "button";
    up.innerHTML = icon("up") + "<span>Workspace</span>";
    up.addEventListener("click", function () {
      haptic("light");
      var row = destinationRow("files");
      if (row) press(row);
    });
    heroBody.appendChild(up);
    heroBody.appendChild(element("span", "m-files-eyebrow", "WORKSPACE"));
    heroBody.appendChild(element("h1", "m-files-title", "Files"));
    heroBody.appendChild(element("p", "m-files-sub", ""));
    hero.appendChild(art);
    hero.appendChild(heroBody);

    var body = element("div", "m-files-body");
    var tools = element("div", "m-files-tools");
    var search = element("button", "m-files-search");
    search.type = "button";
    search.innerHTML = icon("search") + "<span>Search notes, files and tags</span>";
    search.addEventListener("click", openSearch);

    var chips = element("div", "m-files-chips");
    chips.setAttribute("role", "tablist");
    chips.setAttribute("aria-label", "Show");
    FILTERS.forEach(function (filter) {
      var chip = element("button", "m-chip", filter.label);
      chip.type = "button";
      chip.setAttribute("role", "tab");
      chip.dataset.filter = filter.key;
      chip.addEventListener("click", function () {
        if (files.filter === filter.key) return;
        files.filter = filter.key;
        haptic("light");
        renderFiles(files.lastEntries || [], true);
      });
      chips.appendChild(chip);
    });

    tools.appendChild(search);
    tools.appendChild(chips);
    body.appendChild(tools);

    var content = element("div");
    content.dataset.role = "content";
    body.appendChild(content);

    view.appendChild(hero);
    view.appendChild(body);

    var top = element("button", "m-files-top");
    top.type = "button";
    top.setAttribute("aria-label", "Back to top");
    top.innerHTML = icon("up");
    top.dataset.show = "false";
    top.addEventListener("click", function () {
      haptic("light");
      view.scrollTo({ top: 0, behavior: "smooth" });
      if (typeof view.scrollTo !== "function") view.scrollTop = 0;
    });

    root.appendChild(view);
    root.appendChild(top);

    files.root = root;
    files.view = view;
    files.body = body;
    files.head = content;
    files.hero = hero;

    view.addEventListener("scroll", onFilesScroll, { passive: true });
    return root;
  }

  function sectionFor(title, count, kind, index) {
    var section = element("section", "m-files-section m-files-section-" + kind);
    section.style.setProperty("--s", index);
    var head = element("div", "m-files-section-head");
    head.appendChild(element("h2", null, title));
    head.appendChild(element("span", null, String(count)));
    section.appendChild(head);
    var body = element("div", kind === "folders" ? "m-files-grid" : "m-files-list");
    section.appendChild(body);
    return { section: section, body: body };
  }

  function renderFiles(entries, animate) {
    files.lastEntries = entries;
    var content = files.head;
    if (!content) return;
    content.textContent = "";

    var filter = files.filter;
    var visible = entries.filter(function (entry) {
      return filter === "all" || entry.group === filter || (filter === "media" && entry.group === "other");
    });
    var folders = visible.filter(function (entry) { return entry.group === "folders"; });
    var notes = visible.filter(function (entry) { return entry.group === "notes"; });
    var media = visible.filter(function (entry) { return entry.group === "media" || entry.group === "other"; });

    var sectionIndex = 0;
    var order = 0;

    if (folders.length) {
      var folderSection = sectionFor("Folders", folders.length, "folders", sectionIndex++);
      folders.forEach(function (entry, index) {
        folderSection.body.appendChild(tileFor(entry, index));
      });
      content.appendChild(folderSection.section);
    }

    if (notes.length) {
      var noteSection = sectionFor(filter === "notes" ? "Notes" : "Notes", notes.length, "notes", sectionIndex++);
      notes.forEach(function (entry, index) {
        noteSection.body.appendChild(fileFor(entry, index));
      });
      content.appendChild(noteSection.section);
    }

    if (media.length) {
      var mediaSection = sectionFor("Media", media.length, "media", sectionIndex++);
      media.forEach(function (entry, index) {
        mediaSection.body.appendChild(fileFor(entry, index));
      });
      content.appendChild(mediaSection.section);
    }

    if (!visible.length) {
      var empty = element("div", "m-files-empty");
      empty.appendChild(element("strong", null, entries.length ? "Nothing matches that filter" : "Nothing here yet"));
      empty.appendChild(element("p", null, entries.length
        ? "Try another filter, or search the whole workspace."
        : "Create a note or a folder, and it lands here."));
      content.appendChild(empty);
    }
    void order;

    // Chips say which filter is on, in the app's own accent.
    var chips = files.root.querySelectorAll(".m-chip");
    for (var chipIndex = 0; chipIndex < chips.length; chipIndex++) {
      if (chips[chipIndex].dataset.filter === files.filter) chips[chipIndex].setAttribute("aria-selected", "true");
      else chips[chipIndex].setAttribute("aria-selected", "false");
    }

    if (animate) playEntrance();
  }

  function tileFor(entry, index) {
    var tile = element("div", "m-tile");
    tile.dataset.path = entry.path;
    tile.style.setProperty("--i", index);

    var open = element("button", "m-tile-open");
    open.type = "button";
    open.dataset.role = "open";
    open.setAttribute("aria-label", entry.label);
    var glyph = element("span", "m-tile-icon");
    glyph.innerHTML = icon(KIND_ICON[entry.kind] || "folder");
    open.appendChild(glyph);
    open.appendChild(element("span", "m-tile-name", entry.label));
    var meta = element("span", "m-tile-meta", entry.meta || "Folder");
    open.appendChild(meta);
    open.addEventListener("click", function () {
      haptic("light");
      openEntry(entry.path);
    });
    tile.appendChild(open);

    tile.appendChild(moreButton("m-tile-more", entry, "More options"));
    return tile;
  }

  function fileFor(entry, index) {
    var row = element("div", "m-file");
    row.dataset.path = entry.path;
    row.style.setProperty("--i", index);

    var open = element("button", "m-file-open");
    open.type = "button";
    open.setAttribute("aria-label", entry.label);
    var glyph = element("span", "m-file-glyph");
    glyph.innerHTML = icon(KIND_ICON[entry.kind] || "text");
    glyph.style.color = "var(--accent)";
    open.appendChild(glyph);

    var copy = element("span", "m-file-copy");
    var name = element("span", "m-file-name", entry.label);
    if (entry.pinned) name.insertAdjacentHTML("beforeend", '<span class="m-file-badge">' + icon("pin") + "</span>");
    if (entry.favorite) name.insertAdjacentHTML("beforeend", '<span class="m-file-badge">' + icon("star") + "</span>");
    copy.appendChild(name);
    copy.appendChild(element("span", "m-file-meta", entry.meta || "File"));
    open.appendChild(copy);
    open.addEventListener("click", function () {
      haptic("light");
      openEntry(entry.path);
    });
    row.appendChild(open);
    row.appendChild(moreButton("m-file-more", entry, "More options"));
    return row;
  }

  function moreButton(className, entry, label) {
    var button = element("button", className);
    button.type = "button";
    button.setAttribute("aria-label", label);
    button.innerHTML = icon("more");
    button.addEventListener("click", function (event) {
      event.stopPropagation();
      haptic("light");
      menuEntry(entry.path, { x: event.clientX, y: event.clientY });
    });
    return button;
  }

  function playEntrance() {
    var root = files.root;
    if (!root) return;
    root.removeAttribute("data-anim");
    // Reading a layout property forces the animation to restart when the same
    // attribute is set again, which is what a rebuild needs.
    void root.offsetWidth;
    root.setAttribute("data-anim", "in");
    if (files.animTimer) window.clearTimeout(files.animTimer);
    files.animTimer = window.setTimeout(function () { root.removeAttribute("data-anim"); }, 900);
  }

  /*
   * Comet labels the top of a workspace "Comet" and everything under it
   * "Comet\Sub\Folder", in its own hidden path bar. That label is the depth
   * signal: at the top there is nothing to go up to.
   */
  function atWorkspaceRoot() {
    var field = one('input[aria-label="Workspace path"]');
    var displayed = field && field.value ? field.value.trim() : "";
    return !displayed || displayed === "Comet";
  }

  function syncFiles() {
    var panel = one(".workspace-panel");
    if (!files.root) return;
    if (!panel) {
      // A note, a board, the tree, the calendar: the app's own view has it.
      if (files.root.dataset.away !== "true") {
        files.root.dataset.away = "true";
        files.root.setAttribute("aria-hidden", "true");
        document.documentElement.classList.remove("m-files-active");
      }
      return;
    }

    var wasHidden = files.root.dataset.away === "true";
    if (wasHidden) {
      files.root.dataset.away = "false";
      files.root.removeAttribute("aria-hidden");
      document.documentElement.classList.add("m-files-active");
    }

    var entries = readEntries();
    var title = (one(".workspace-heading h2") || one(".overview-heading h2") || {}).textContent || "Files";
    var folder = (one(".workspace-scroll") || {}).dataset;
    var folderPath = (folder && folder.dropFolder) || "";
    var signature = title.trim() + "|" + folderPath + "|" + entries.map(function (entry) {
      return entry.path + ":" + entry.label + ":" + entry.meta;
    }).join(",");

    if (signature !== files.signature) {
      files.signature = signature;
      updateHero(title, entries);
      // The first paint of a session just appears; every navigation after it
      // is staged, so moving around the workspace reads as movement.
      renderFiles(entries, files.everShown);
      files.everShown = true;
    } else if (wasHidden && files.everShown) {
      // Same list as before, so there is nothing to rebuild — but coming back
      // from a note is still a change of place and should look like one.
      playEntrance();
    }
  }

  function updateHero(title, entries) {
    if (!files.hero) return;
    var workspace = one(".workspace-picker-copy strong");
    var workspaceName = workspace ? (workspace.textContent || "").trim() : "Comet";
    var titleEl = files.hero.querySelector(".m-files-title");
    var subEl = files.hero.querySelector(".m-files-sub");
    var upEl = files.hero.querySelector(".m-files-up");
    if (titleEl && titleEl.textContent !== title.trim()) titleEl.textContent = title.trim();

    var folders = entries.filter(function (entry) { return entry.group === "folders"; }).length;
    var pieces = [entries.length + (entries.length === 1 ? " item" : " items")];
    if (folders) pieces.push(folders + (folders === 1 ? " folder" : " folders"));
    if (workspaceName) pieces.push(workspaceName);
    if (subEl) subEl.textContent = pieces.join(" · ");

    // "Workspace" is a way home from a folder, so it only exists inside one.
    if (upEl) upEl.hidden = atWorkspaceRoot();
  }

  var filesScrollFrame = 0;
  function onFilesScroll() {
    if (filesScrollFrame) return;
    filesScrollFrame = window.requestAnimationFrame(function () {
      filesScrollFrame = 0;
      updateFilesScroll();
      measureScroll();
    });
  }

  function updateFilesScroll() {
    var view = files.view;
    if (!view || files.root.dataset.away === "true") return;
    var top = view.scrollTop || 0;
    files.root.style.setProperty("--m-hero-shift", Math.min(top, 320) + "px");
    files.root.style.setProperty("--m-hero-fade", Math.min(top / 260, 1));
    var topButton = files.root.querySelector(".m-files-top");
    if (topButton) topButton.dataset.show = top > 360 ? "true" : "false";
  }

  /* ---------------------------------------------------------------------- */
  /* The Library sheet                                                      */
  /* ---------------------------------------------------------------------- */

  var library = null;

  function rowText(key) {
    var row = destinationRow(key);
    var small = row ? row.querySelector("small") : null;
    var text = small ? (small.textContent || "").trim() : "";
    return text || "";
  }

  function iconSpan(name, boxed) {
    var holder = element("span", boxed ? "m-library-icon" : null);
    holder.innerHTML = icon(name);
    return holder;
  }

  function buildLibrary() {
    var backdrop = element("div", "m-library-backdrop");
    backdrop.addEventListener("click", closeLibrary);

    var sheet = element("div", "m-library");
    sheet.setAttribute("role", "dialog");
    sheet.setAttribute("aria-modal", "true");
    sheet.setAttribute("aria-label", "Library");

    var head = element("div", "m-library-head");
    head.appendChild(element("strong", null, "Library"));
    var done = element("button", "m-library-done", "Done");
    done.type = "button";
    done.addEventListener("click", closeLibrary);
    head.appendChild(done);

    var scroll = element("div", "m-library-scroll");

    var workspaceGroup = element("div", "m-library-group");
    var workspaceCard = element("div", "m-library-card");
    var workspaceRow = element("button", "m-library-row m-library-workspace");
    workspaceRow.type = "button";
    workspaceRow.appendChild(iconSpan("workspace", true));
    var workspaceCopy = element("span", "m-library-copy");
    var workspaceName = element("strong");
    workspaceName.dataset.role = "workspace-name";
    var workspaceDetail = element("small");
    workspaceDetail.dataset.role = "workspace-detail";
    workspaceCopy.appendChild(workspaceName);
    workspaceCopy.appendChild(workspaceDetail);
    workspaceRow.appendChild(workspaceCopy);
    var workspaceChevron = element("span", "m-library-chevron");
    workspaceChevron.innerHTML = icon("chevron");
    workspaceRow.appendChild(workspaceChevron);
    workspaceRow.addEventListener("click", function () {
      haptic("light");
      closeLibrary();
      // The app's own workspace menu, which mobile.css presents as a sheet.
      press(one(WORKSPACE_PICKER));
    });
    workspaceCard.appendChild(workspaceRow);
    workspaceGroup.appendChild(workspaceCard);
    scroll.appendChild(workspaceGroup);

    [
      { group: "browse", label: "Browse" },
      { group: "tools", label: "Tools" }
    ].forEach(function (section) {
      var group = element("div", "m-library-group");
      group.appendChild(element("div", "m-library-label", section.label));
      var card = element("div", "m-library-card");

      DESTINATIONS.filter(function (item) { return item.group === section.group; }).forEach(function (item) {
        var row = element("button", "m-library-row");
        row.type = "button";
        row.dataset.destination = item.key;
        row.appendChild(iconSpan(item.icon, true));
        var copy = element("span", "m-library-copy");
        copy.appendChild(element("strong", null, item.label));
        row.appendChild(copy);
        var count = element("span", "m-library-count");
        count.dataset.role = "count";
        row.appendChild(count);
        row.addEventListener("click", function () {
          haptic("light");
          var target = destinationRow(item.key);
          closeLibrary();
          if (target) press(target);
        });
        card.appendChild(row);
      });

      group.appendChild(card);
      scroll.appendChild(group);
    });

    var foot = element("div", "m-library-label m-library-build");
    foot.dataset.role = "build";
    foot.textContent = buildLabel ? "Comet for iOS · build " + buildLabel : "Comet for iOS";

    sheet.appendChild(head);
    sheet.appendChild(scroll);
    sheet.appendChild(foot);
    backdrop.appendChild(sheet);
    return backdrop;
  }

  function syncLibrary() {
    if (!library) return;
    var workspace = one(".workspace-picker-copy strong");
    var workspaceSmall = one(".workspace-picker-copy small");
    var name = library.querySelector('[data-role="workspace-name"]');
    var detail = library.querySelector('[data-role="workspace-detail"]');
    if (name) name.textContent = workspace ? (workspace.textContent || "").trim() : "Comet";
    if (detail) detail.textContent = workspaceSmall ? (workspaceSmall.textContent || "").trim() : "Local workspace";

    var build = library.querySelector('[data-role="build"]');
    if (build) build.textContent = buildLabel ? "Comet for iOS · build " + buildLabel : "Comet for iOS";

    var current = activeDestination();
    var rows = library.querySelectorAll(".m-library-row[data-destination]");
    for (var index = 0; index < rows.length; index++) {
      var key = rows[index].dataset.destination;
      var count = rows[index].querySelector('[data-role="count"]');
      if (count) count.textContent = rowText(key);
      if (key === current) rows[index].setAttribute("aria-current", "page");
      else rows[index].removeAttribute("aria-current");
    }
  }

  function openLibrary() {
    if (library) return;
    haptic("light");
    library = buildLibrary();
    document.body.appendChild(library);
    syncLibrary();
    var items = document.querySelectorAll(".m-dock-item");
    for (var index = 0; index < items.length; index++) {
      if (items[index].dataset.tab === "library") items[index].setAttribute("aria-expanded", "true");
    }
  }

  function closeLibrary() {
    if (!library) return;
    library.remove();
    library = null;
    var items = document.querySelectorAll(".m-dock-item");
    for (var index = 0; index < items.length; index++) {
      if (items[index].dataset.tab === "library") items[index].removeAttribute("aria-expanded");
    }
  }

  function toggleLibrary() {
    if (library) closeLibrary();
    else openLibrary();
  }

  /* ---------------------------------------------------------------------- */
  /* Long press = right click                                               */
  /* ---------------------------------------------------------------------- */

  var LONG_PRESS_MS = 420;
  var MOVE_TOLERANCE = 12;
  var longPress = { timer: 0, x: 0, y: 0, node: null };

  /*
   * The surface draws its own rows, so a long press on one has to find the app
   * row it stands for before it can press that row's menu button.
   */
  function appRowFor(node) {
    if (!node || !node.closest) return null;
    var own = node.closest(".workspace-entry, .tree-item");
    if (own) return own;
    var drawn = node.closest(".m-tile, .m-file");
    if (!drawn || !drawn.dataset.path) return null;
    var rows = document.querySelectorAll(".workspace-entry");
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].dataset.path === drawn.dataset.path) return rows[index];
    }
    return null;
  }

  function rowMenuButton(row) {
    return row.querySelector(".workspace-entry-more") ||
      row.querySelector('[aria-label^="More options for"]') ||
      row.querySelector(".tree-action");
  }

  /*
   * A long press must not also open the file, so the click that follows is
   * swallowed once, at capture time, before React sees it.
   */
  function swallowNextClick() {
    var handler = function (event) {
      event.stopPropagation();
      event.preventDefault();
      document.removeEventListener("click", handler, true);
    };
    document.addEventListener("click", handler, true);
    window.setTimeout(function () {
      document.removeEventListener("click", handler, true);
    }, 900);
  }

  function cancelLongPress() {
    if (longPress.timer) window.clearTimeout(longPress.timer);
    longPress.timer = 0;
    longPress.node = null;
  }

  /* ---------------------------------------------------------------------- */
  /* Edge swipe back                                                        */
  /* ---------------------------------------------------------------------- */

  var EDGE = 26;
  var swipe = { active: false, x: 0, y: 0 };

  function onSwipeStart(event) {
    swipe.active = false;
    if (event.touches.length !== 1) return;
    var target = event.target;
    if (!target || !target.closest) return;
    if (target.closest("input, textarea, select, [contenteditable=true], .todo-board, .m-library, .m-files")) return;
    var touch = event.touches[0];
    if (touch.clientX > EDGE) return;
    swipe.active = true;
    swipe.x = touch.clientX;
    swipe.y = touch.clientY;
  }

  function onSwipeMove(event) {
    if (!swipe.active) return;
    var touch = event.touches && event.touches[0];
    if (!touch) return;
    var dx = touch.clientX - swipe.x;
    var dy = Math.abs(touch.clientY - swipe.y);
    if (dx < -8 || dy > 52) { swipe.active = false; return; }
    if (dx < 64) return;
    swipe.active = false;
    var action = backAction();
    if (!action) return;
    haptic("light");
    action();
  }

  function onTouchStart(event) {
    onSwipeStart(event);

    if (event.touches.length !== 1) return cancelLongPress();
    var target = event.target;
    if (!target || !target.closest) return;
    // Never interfere with typing, or with a board that owns the gesture.
    if (target.closest("input, textarea, select, [contenteditable=true], .todo-board")) return;
    if (target.closest(".m-tile-more, .m-file-more")) return;

    var row = appRowFor(target);
    if (!row) return;

    var touch = event.touches[0];
    longPress.x = touch.clientX;
    longPress.y = touch.clientY;
    longPress.node = row;
    longPress.timer = window.setTimeout(function () {
      var button = rowMenuButton(row);
      longPress.timer = 0;
      if (!button) return;
      haptic("medium");
      // Open the menu first, and only then start swallowing: the swallow is
      // for the click the finger produces when it lifts, and installing it
      // early would eat this press too.
      press(button, { x: touch.clientX, y: touch.clientY });
      swallowNextClick();
    }, LONG_PRESS_MS);
  }

  function onTouchMove(event) {
    onSwipeMove(event);
    if (!longPress.timer) return;
    var touch = event.touches && event.touches[0];
    if (!touch) return cancelLongPress();
    if (Math.abs(touch.clientX - longPress.x) > MOVE_TOLERANCE ||
        Math.abs(touch.clientY - longPress.y) > MOVE_TOLERANCE) {
      cancelLongPress();
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Scrolled state, for the glass bar                                      */
  /* ---------------------------------------------------------------------- */

  var scrolled = false;
  var scrollScheduled = false;
  function measureScroll() {
    if (scrollScheduled) return;
    scrollScheduled = true;
    window.requestAnimationFrame(function () {
      scrollScheduled = false;
      readScroll();
    });
  }

  function readScroll() {
    var area = one(".workspace-scroll");
    var top = Math.max(
      window.scrollY || 0,
      document.documentElement.scrollTop || 0,
      area ? area.scrollTop : 0,
      files.view ? files.view.scrollTop : 0
    );
    var next = top > 6;
    if (next === scrolled) return;
    scrolled = next;
    document.documentElement.classList.toggle("m-scrolled", next);
  }

  /* ---------------------------------------------------------------------- */
  /* Keeping the chrome truthful                                            */
  /* ---------------------------------------------------------------------- */

  function paint() {
    syncStatusBar();
    measureScroll();
    syncFiles();
    updateFilesScroll();
    if (library) syncLibrary();

    var bar = one(".m-bar");
    if (!bar) return;
    var location = readLocation();
    var strong = bar.querySelector("strong");
    var small = bar.querySelector("small");
    if (strong && strong.textContent !== location.title) strong.textContent = location.title;
    if (small && small.textContent !== location.detail) small.textContent = location.detail;

    var back = bar.querySelector(".m-bar-back");
    if (back) back.hidden = !backAction();

    var current = activeDestination();
    // Files is current while you are browsing the workspace, Calendar while you
    // are in it, and neither for the tools, which live in the sheet.
    var tab = "";
    if (current === "calendar") tab = "calendar";
    else if (current === "files" || current === "pinned" || current === "favorites" ||
             current === "tree" || current === "brain") tab = "files";
    var lensIndex = -1;
    for (var index = 0; index < DOCK.length; index++) {
      if (DOCK[index].key === tab) lensIndex = index;
    }
    var items = document.querySelectorAll(".m-dock-item");
    for (var item = 0; item < items.length; item++) {
      if (items[item].dataset.tab === tab && tab) items[item].setAttribute("aria-current", "page");
      else items[item].removeAttribute("aria-current");
    }
    moveLens(lensIndex);
  }

  var scheduled = false;
  function schedulePaint() {
    if (scheduled) return;
    scheduled = true;
    window.requestAnimationFrame(function () {
      scheduled = false;
      paint();
    });
  }

  /* ---------------------------------------------------------------------- */
  /* Install                                                                */
  /* ---------------------------------------------------------------------- */

  function install() {
    if (one(".m-bar")) {
      schedulePaint();
      return true;
    }
    // Wait for the app to render: the first frame is an empty #root.
    if (!one(".app-shell")) return false;

    document.documentElement.classList.add("comet-mobile");
    fetchBuild();
    document.body.appendChild(buildFiles());
    document.body.appendChild(buildBar());
    document.body.appendChild(buildDock());
    document.body.appendChild(buildCreate());

    document.addEventListener("touchstart", onTouchStart, { passive: true });
    document.addEventListener("touchmove", onTouchMove, { passive: true });
    document.addEventListener("touchend", cancelLongPress, { passive: true });
    document.addEventListener("touchcancel", cancelLongPress, { passive: true });
    // Capture, because the scrolling element is not the document.
    document.addEventListener("scroll", measureScroll, { capture: true, passive: true });
    window.addEventListener("resize", schedulePaint, { passive: true });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") closeLibrary();
    });

    /*
     * The workspace sheet is Comet's own menu inside the sidebar, so tapping
     * its dim has to press the app's own toggle to close it again: the click
     * lands on the sheet's own box, not on a row.
     */
    document.addEventListener("click", function (event) {
      var target = event.target;
      if (!target || !target.classList || !target.classList.contains("sidebar")) return;
      if (!one(".vault-dropdown")) return;
      press(one(WORKSPACE_PICKER));
    }, true);

    /*
     * Coming back from a native sheet (the workspace picker, the share sheet)
     * WKWebView can keep a stale surface. Toggling a compositing hint forces it
     * to re-render the layer instead of leaving whatever was there, which is
     * what turns a stale frame into a black one.
     */
    document.addEventListener("visibilitychange", function () {
      if (document.visibilityState !== "visible") return;
      var root = document.documentElement;
      root.style.webkitTransform = "translateZ(0)";
      window.requestAnimationFrame(function () {
        window.requestAnimationFrame(function () { root.style.webkitTransform = ""; });
      });
      schedulePaint();
    });

    var observer = new MutationObserver(function () {
      // React may replace whole subtrees on navigation; rebuild if the chrome
      // was swept away with them and refresh the labels either way.
      if (!one(".m-bar")) install();
      else schedulePaint();
    });
    observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "disabled", "data-theme"] });
    new MutationObserver(schedulePaint).observe(document.documentElement, { attributes: true, attributeFilter: ["data-theme", "data-palette"] });

    schedulePaint();
    return true;
  }

  function start() {
    if (install()) return;
    var tries = 0;
    (function retry() {
      if (install()) return;
      if (++tries > 120) return;
      window.requestAnimationFrame(retry);
    })();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start, { once: true });
  else start();
})();
