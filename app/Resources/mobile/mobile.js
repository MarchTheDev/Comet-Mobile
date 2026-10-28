/*
 * Comet for iOS — the mobile shell
 * --------------------------------------------------------------------------
 * Comet's interface is React and its state lives in that React tree, so this
 * layer does not reimplement anything. It adds the chrome a phone needs and
 * makes all of it *press the app's own controls*: the same buttons that live in
 * Comet's sidebar and top bar.
 *
 * There is no sidebar here. A 330pt drawer over a 390pt screen is one app
 * covering another, and hiding it makes the phone layout a tab bar and a sheet
 * — which is the shape every notes app on the phone has. Comet's sidebar stays
 * in the DOM, keeps its state, and is simply never drawn; the sheet presses its
 * rows, which is why they still work while `display: none`.
 *
 * What it adds:
 *   - a bar that is glass once content scrolls under it, with back and search
 *   - a floating glass dock: Files, Search, Calendar, Library
 *   - a floating create button
 *   - a Library sheet with the destinations the sidebar used to hold
 *   - long press on a file or folder, for the app's own menu
 *   - edge swipe to go back, and haptics through the native bridge
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
  /* Destinations — every place the sheet or the dock can send you.          */
  /* ---------------------------------------------------------------------- */

  var SEARCH_BUTTON = '[aria-label="Search notes"]';
  var CREATE_BUTTON = '[aria-label="Add file or upload"]';
  var HISTORY_BACK = '[aria-label="Go back"]';
  var WORKSPACE_PICKER = ".workspace-picker";

  /*
   * `nav` matches the label Comet gives the row. The counts live in the row's
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
    search: '<circle cx="10.8" cy="10.8" r="6.3"/><path d="M15.5 15.5 20 20"/>',
    plus: '<path d="M12 5.5v13M5.5 12h13"/>',
    files: '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3.2l1.8 2h8A2.5 2.5 0 0 1 21 9.5v7A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5z"/>',
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
    chevron: '<path d="M9 5l7 7-7 7"/>'
  };

  function icon(name) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICONS[name] + "</svg>";
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
   * button that works and a button that silently does nothing.
   */
  function press(element, coords) {
    if (!element) return false;
    var container = element.closest("[inert]");
    if (container) {
      container.removeAttribute("inert");
      container.removeAttribute("aria-hidden");
    }
    try {
      // A real click event rather than element.click(), so that the app's
      // handlers see the pointer position it uses to place its menus.
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

  /*
   * Where the app shows a document, its own heading carries the display title
   * (Comet strips ".md" for reading), and the hidden path bar carries the path.
   */
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
      var row = destinationRow(DESTINATIONS[index].key);
      if (row && row === active) return DESTINATIONS[index].key;
    }
    return "";
  }

  /*
   * The app's own history button is the real "back": it walks the same list a
   * desktop user walks. It is disabled at the start of a session, though, and a
   * session restored straight into a note has nowhere to go back to — so the
   * file list stands in. Back is hidden when neither would do anything, which
   * is better than a button that looks live and does nothing.
   */
  function backAction() {
    var history = one(HISTORY_BACK);
    if (history && !history.disabled) return function () { press(history); };
    if (readLocation().document) {
      var files = destinationRow("files");
      if (files) return function () { press(files); };
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
  /* The dock                                                               */
  /* ---------------------------------------------------------------------- */

  var DOCK = [
    { key: "files", label: "Files", icon: "files" },
    { key: "search", label: "Search", icon: "search" },
    { key: "calendar", label: "Calendar", icon: "calendar" },
    { key: "library", label: "Library", icon: "library" }
  ];

  /*
   * The lens under a dock item should move under the finger, not one React
   * render later, so the state is set optimistically and then corrected by
   * paint() when the app has actually navigated.
   */
  function markTab(key) {
    var items = document.querySelectorAll(".m-dock-item");
    for (var index = 0; index < items.length; index++) {
      if (items[index].dataset.tab === key) items[index].setAttribute("aria-current", "page");
      else items[index].removeAttribute("aria-current");
    }
  }

  function buildDock() {
    var dock = document.createElement("nav");
    dock.className = "m-dock";
    dock.setAttribute("role", "navigation");
    dock.setAttribute("aria-label", "Comet");

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
    return dock;
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
  /* The Library sheet                                                      */
  /* ---------------------------------------------------------------------- */

  var library = null;

  function rowText(key) {
    var row = destinationRow(key);
    var small = row ? row.querySelector("small") : null;
    var text = small ? (small.textContent || "").trim() : "";
    return text || "";
  }

  function buildLibrary() {
    var backdrop = document.createElement("div");
    backdrop.className = "m-library-backdrop";
    backdrop.addEventListener("click", closeLibrary);

    var sheet = document.createElement("div");
    sheet.className = "m-library";
    sheet.setAttribute("role", "dialog");
    sheet.setAttribute("aria-modal", "true");
    sheet.setAttribute("aria-label", "Library");

    var head = document.createElement("div");
    head.className = "m-library-head";
    var heading = document.createElement("strong");
    heading.textContent = "Library";
    var done = document.createElement("button");
    done.type = "button";
    done.className = "m-library-done";
    done.textContent = "Done";
    done.addEventListener("click", closeLibrary);
    head.appendChild(heading);
    head.appendChild(done);

    var scroll = document.createElement("div");
    scroll.className = "m-library-scroll";

    // The workspace switcher first: which workspace you are in is the single
    // most important thing on this screen, and the app's own picker answers it.
    var workspaceGroup = document.createElement("div");
    workspaceGroup.className = "m-library-group";
    var workspaceCard = document.createElement("div");
    workspaceCard.className = "m-library-card";
    var workspaceRow = document.createElement("button");
    workspaceRow.type = "button";
    workspaceRow.className = "m-library-row m-library-workspace";
    workspaceRow.appendChild(iconSpan("workspace", true));
    var workspaceCopy = document.createElement("span");
    workspaceCopy.className = "m-library-copy";
    var workspaceName = document.createElement("strong");
    workspaceName.dataset.role = "workspace-name";
    var workspaceDetail = document.createElement("small");
    workspaceDetail.dataset.role = "workspace-detail";
    workspaceCopy.appendChild(workspaceName);
    workspaceCopy.appendChild(workspaceDetail);
    workspaceRow.appendChild(workspaceCopy);
    var workspaceChevron = document.createElement("span");
    workspaceChevron.className = "m-library-chevron";
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
      var group = document.createElement("div");
      group.className = "m-library-group";
      var label = document.createElement("div");
      label.className = "m-library-label";
      label.textContent = section.label;
      var card = document.createElement("div");
      card.className = "m-library-card";

      DESTINATIONS.filter(function (item) { return item.group === section.group; }).forEach(function (item) {
        var row = document.createElement("button");
        row.type = "button";
        row.className = "m-library-row";
        row.dataset.destination = item.key;
        row.appendChild(iconSpan(item.icon, true));
        var copy = document.createElement("span");
        copy.className = "m-library-copy";
        var strong = document.createElement("strong");
        strong.textContent = item.label;
        copy.appendChild(strong);
        row.appendChild(copy);
        var count = document.createElement("span");
        count.className = "m-library-count";
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

      group.appendChild(label);
      group.appendChild(card);
      scroll.appendChild(group);
    });

    var foot = document.createElement("div");
    foot.className = "m-library-label m-library-build";
    foot.dataset.role = "build";
    foot.textContent = buildLabel ? "Comet for iOS · build " + buildLabel : "Comet for iOS";

    sheet.appendChild(head);
    sheet.appendChild(scroll);
    sheet.appendChild(foot);
    backdrop.appendChild(sheet);
    return backdrop;
  }

  function iconSpan(name, boxed) {
    var holder = document.createElement(boxed ? "span" : "span");
    if (boxed) holder.className = "m-library-icon";
    holder.innerHTML = icon(name);
    return holder;
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
  var longPress = { timer: 0, x: 0, y: 0, row: null };

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
    longPress.row = null;
  }

  /* ---------------------------------------------------------------------- */
  /* Edge swipe back                                                        */
  /* ---------------------------------------------------------------------- */

  /*
   * Every iOS app can be left by dragging in from the left edge, and a page in
   * a web view cannot. This is the same gesture over the app's own back.
   */
  var EDGE = 26;
  var swipe = { active: false, x: 0, y: 0 };

  function onSwipeStart(event) {
    swipe.active = false;
    if (event.touches.length !== 1) return;
    var target = event.target;
    if (!target || !target.closest) return;
    if (target.closest("input, textarea, select, [contenteditable=true], .todo-board, .m-library")) return;
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

    var row = target.closest(".workspace-entry, .tree-item");
    if (!row) return;

    var touch = event.touches[0];
    longPress.x = touch.clientX;
    longPress.y = touch.clientY;
    longPress.row = row;
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
      area ? area.scrollTop : 0
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
    var tabFor = "";
    if (current === "calendar") tabFor = "calendar";
    else if (current === "files" || current === "pinned" || current === "favorites" ||
             current === "tree" || current === "brain") tabFor = "files";
    var items = document.querySelectorAll(".m-dock-item");
    for (var index = 0; index < items.length; index++) {
      var key = items[index].dataset.tab;
      if (key === "search" || key === "library") continue;
      if (key === tabFor) items[index].setAttribute("aria-current", "page");
      else items[index].removeAttribute("aria-current");
    }
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
