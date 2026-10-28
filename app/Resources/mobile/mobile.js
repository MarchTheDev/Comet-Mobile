/*
 * Comet for iOS — the mobile shell
 * --------------------------------------------------------------------------
 * Comet's interface is React and its state lives in that React tree, so this
 * layer does not reimplement anything. It adds the two pieces a phone needs
 * (a header and a thumb bar), and makes them *press the app's own controls* —
 * the same buttons in the sidebar and top bar that a desktop user clicks.
 *
 * That decision has a cost worth stating: the anchors below are Comet's
 * accessible names and class names, so a future Comet that renames them breaks
 * this shell. tools/test-mobile.mjs exists to notice that, and every anchor is
 * in one place (PRESS_TARGETS) so it is a one-line fix.
 *
 * What it adds:
 *   - a compact header showing where you are, with the drawer and back
 *   - a five-slot thumb bar: Files, Search, New, Calendar, Library
 *   - long-press on a file or folder opens the app's own menu
 *
 * The desktop chrome it replaces is hidden by mobile.css, never removed: the
 * buttons stay in the DOM so that pressing them still works.
 */
(function () {
  "use strict";

  if (window.__cometMobileInstalled) return;
  window.__cometMobileInstalled = true;

  /* ---------------------------------------------------------------------- */
  /* Anchors — the only place Comet's own markup is named.                   */
  /* ---------------------------------------------------------------------- */

  var PRESS_TARGETS = {
    // Sidebar navigation, matched by their visible label.
    files: { nav: "All files" },
    calendar: { nav: "Calendar" },
    passwords: { nav: "Passwords" },
    settings: { nav: "Settings" },
    search: ".sidebar-search",
    // The app's own "New" menu, anchored on the sidebar's add button.
    create: '[aria-label="Add file or upload"]',
    drawer: ".sidebar-toggle",
    back: '[aria-label="Go back"]',
    forward: '[aria-label="Go forward"]'
  };

  var ICONS = {
    menu: '<path d="M3 6h18M3 12h18M3 18h18"/>',
    back: '<path d="M15 18l-6-6 6-6"/>',
    files: '<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20"/><path d="M6.5 2H20v20H6.5A2.5 2.5 0 0 1 4 19.5v-15A2.5 2.5 0 0 1 6.5 2z"/>',
    search: '<circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    calendar: '<rect x="3" y="4" width="18" height="18" rx="2"/><path d="M16 2v4M8 2v4M3 10h18"/>',
    library: '<path d="M4 6h16M4 12h16M4 18h10"/>'
  };

  function icon(name) {
    return '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" ' +
      'stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + ICONS[name] + "</svg>";
  }

  /* ---------------------------------------------------------------------- */
  /* Driving the app's own controls                                          */
  /* ---------------------------------------------------------------------- */

  function one(selector) {
    return selector ? document.querySelector(selector) : null;
  }

  /*
   * Nav rows read `<span>All files</span><small>3</small>`, so the whole
   * element's text is "All files3". The label span is what to match, or the
   * counts make every row unmatchable.
   */
  function navItem(label) {
    var items = document.querySelectorAll(".sidebar .nav-item");
    for (var index = 0; index < items.length; index++) {
      var caption = items[index].querySelector("span");
      var text = (caption || items[index]).textContent || "";
      if (text.trim() === label) return items[index];
    }
    return null;
  }

  function targetFor(key) {
    var config = PRESS_TARGETS[key];
    if (!config) return null;
    if (typeof config === "string") return one(config);
    if (config.nav) return navItem(config.nav);
    return null;
  }

  /*
   * The sidebar is marked `inert` whenever it is closed, which is exactly the
   * state its buttons are in while this bar is on screen. Lifting it for the
   * duration of a programmatic press is the difference between a button that
   * works and a button that silently does nothing.
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

  function drawerIsOpen() {
    var sidebar = one(".sidebar");
    return Boolean(sidebar) && !sidebar.classList.contains("is-closed");
  }

  function closeDrawer() {
    if (!drawerIsOpen()) return;
    var toggle = one(PRESS_TARGETS.drawer);
    if (toggle) press(toggle);
    else {
      // The app also closes it from its own close button inside the drawer.
      var close = one(".sidebar-close-mobile");
      if (close) press(close);
    }
  }

  function goTo(key) {
    var element = targetFor(key);
    if (!element) return;
    press(element);
    closeDrawer();
  }

  /* ---------------------------------------------------------------------- */
  /* The header                                                             */
  /* ---------------------------------------------------------------------- */

  /*
   * Where the app shows a document, its own heading carries the display title
   * (Comet strips ".md" for reading), and the hidden path bar carries the path.
   * Those two make a better header than anything this file could invent.
   */
  function readLocation() {
    var workspace = one(".workspace-picker-copy strong");
    var workspaceName = workspace ? (workspace.textContent || "").trim() : "Comet";

    var heading = one(".document-heading h2");
    var file = heading ? (heading.textContent || "").trim() : "";
    var pathField = one('input[aria-label="Workspace path"]');
    var path = pathField && pathField.value ? pathField.value.trim() : "";

    if (file) return { title: file, detail: path || workspaceName };

    var active = one(".primary-nav .nav-item.active");
    var caption = active ? active.querySelector("span") : null;
    var view = caption ? (caption.textContent || "").trim() : "";
    return { title: workspaceName, detail: view || "Workspace" };
  }

  function canGoBack() {
    var back = one(PRESS_TARGETS.back);
    return Boolean(back) && !back.disabled;
  }

  function buildHeader() {
    var header = document.createElement("header");
    header.className = "m-header";
    header.setAttribute("role", "banner");

    var menu = document.createElement("button");
    menu.type = "button";
    menu.className = "m-header-button m-header-menu";
    menu.setAttribute("aria-label", "Open library");
    menu.innerHTML = icon("menu");
    menu.addEventListener("click", function () {
      var toggle = one(PRESS_TARGETS.drawer);
      if (toggle) press(toggle);
    });

    var title = document.createElement("div");
    title.className = "m-header-title";
    var strong = document.createElement("strong");
    var small = document.createElement("small");
    title.appendChild(strong);
    title.appendChild(small);

    var back = document.createElement("button");
    back.type = "button";
    back.className = "m-header-button m-header-back";
    back.setAttribute("aria-label", "Go back");
    back.innerHTML = icon("back");
    back.hidden = true;
    back.addEventListener("click", function () {
      press(one(PRESS_TARGETS.back));
      closeDrawer();
    });

    header.appendChild(menu);
    header.appendChild(title);
    header.appendChild(back);
    return header;
  }

  /* ---------------------------------------------------------------------- */
  /* The thumb bar                                                          */
  /* ---------------------------------------------------------------------- */

  var TABS = [
    { key: "files", label: "Files", icon: "files" },
    { key: "search", label: "Search", icon: "search" },
    { key: "create", label: "New", icon: "plus", raised: true },
    { key: "calendar", label: "Calendar", icon: "calendar" },
    { key: "library", label: "Library", icon: "library" }
  ];

  function buildTabs() {
    var bar = document.createElement("nav");
    bar.className = "m-tabs";
    bar.setAttribute("role", "navigation");
    bar.setAttribute("aria-label", "Comet");

    TABS.forEach(function (tab) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = "m-tab" + (tab.raised ? " m-tab-new" : "");
      button.setAttribute("aria-label", tab.label);
      button.dataset.tab = tab.key;
      button.innerHTML = (tab.raised
        ? '<span class="m-tab-fab">' + icon(tab.icon) + "</span>"
        : icon(tab.icon)) + "<span>" + tab.label + "</span>";

      button.addEventListener("click", function () {
        if (tab.key === "library") {
          var toggle = one(PRESS_TARGETS.drawer);
          if (toggle) press(toggle);
          return;
        }
        if (tab.key === "create") {
          openCreateMenu();
          return;
        }
        if (tab.key === "search") {
          press(one(PRESS_TARGETS.search));
          closeDrawer();
          return;
        }
        goTo(tab.key);
      });

      bar.appendChild(button);
    });
    return bar;
  }

  /*
   * The app positions its New menu at the pointer. There is no pointer here, so
   * it is given a point near the bottom of the screen and mobile.css turns the
   * menu into a sheet regardless of where it lands.
   */
  function openCreateMenu() {
    var create = one(PRESS_TARGETS.create);
    if (!create) return;
    press(create, {
      x: Math.round(window.innerWidth - 28),
      y: Math.round(window.innerHeight - 120)
    });
  }

  /* ---------------------------------------------------------------------- */
  /* Long press = right click                                               */
  /* ---------------------------------------------------------------------- */

  var LONG_PRESS_MS = 480;
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

  function onTouchStart(event) {
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
      // Open the menu first, and only then start swallowing: the swallow is
      // for the click the finger produces when it lifts, and installing it
      // early would eat this press too.
      press(button, { x: touch.clientX, y: touch.clientY });
      swallowNextClick();
    }, LONG_PRESS_MS);
  }

  function onTouchMove(event) {
    if (!longPress.timer) return;
    var touch = event.touches && event.touches[0];
    if (!touch) return cancelLongPress();
    if (Math.abs(touch.clientX - longPress.x) > MOVE_TOLERANCE ||
        Math.abs(touch.clientY - longPress.y) > MOVE_TOLERANCE) {
      cancelLongPress();
    }
  }

  /* ---------------------------------------------------------------------- */
  /* Keeping the chrome truthful                                            */
  /* ---------------------------------------------------------------------- */

  function paint() {
    var header = one(".m-header");
    if (!header) return;
    var location = readLocation();
    var strong = header.querySelector("strong");
    var small = header.querySelector("small");
    if (strong && strong.textContent !== location.title) strong.textContent = location.title;
    if (small && small.textContent !== location.detail) small.textContent = location.detail;

    var back = header.querySelector(".m-header-back");
    if (back) back.hidden = !canGoBack();

    var active = one(".primary-nav .nav-item.active");
    var view = active ? (active.textContent || "").trim() : "";
    var current = view === "Calendar" ? "calendar" : "files";
    var tabs = document.querySelectorAll(".m-tab");
    for (var index = 0; index < tabs.length; index++) {
      var key = tabs[index].dataset.tab;
      if (key === "create" || key === "search" || key === "library") continue;
      if (key === current) tabs[index].setAttribute("aria-current", "page");
      else tabs[index].removeAttribute("aria-current");
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
    if (one(".m-header")) {
      schedulePaint();
      return true;
    }
    // Wait for the app to render: the first frame is an empty #root.
    if (!one(".app-shell")) return false;

    document.documentElement.classList.add("comet-mobile");
    document.body.appendChild(buildHeader());
    document.body.appendChild(buildTabs());

    document.addEventListener("touchstart", onTouchStart, { passive: true });
    document.addEventListener("touchmove", onTouchMove, { passive: true });
    document.addEventListener("touchend", cancelLongPress, { passive: true });
    document.addEventListener("touchcancel", cancelLongPress, { passive: true });

    var observer = new MutationObserver(function () {
      // React may replace whole subtrees on navigation; rebuild if the chrome
      // was swept away with them and refresh the labels either way.
      if (!one(".m-header")) install();
      else schedulePaint();
    });
    observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["class", "disabled"] });

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
