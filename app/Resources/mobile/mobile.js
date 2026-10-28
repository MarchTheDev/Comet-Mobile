/*
 * Comet for iOS — the mobile shell
 * --------------------------------------------------------------------------
 * Comet's interface is React and its state lives in that React tree, so this
 * layer does not reimplement anything. It adds the chrome a phone needs — a
 * translucent bar, a large title, a floating dock, a create button — and makes
 * all of it *press the app's own controls*: the same buttons in the sidebar and
 * top bar that a desktop user clicks.
 *
 * That decision has a cost worth stating: the anchors below are Comet's
 * accessible names and class names, so a future Comet that renames them breaks
 * this shell. tools/test-mobile.mjs exists to notice that, and every anchor is
 * in one place (PRESS_TARGETS) so it is a one-line fix.
 *
 * What it adds:
 *   - a bar showing where you are, glass once content scrolls under it
 *   - a floating dock: Files, Search, Calendar, Library
 *   - a floating create button, because making something is what a phone is for
 *   - long press on a file or folder opens the app's own menu
 *   - edge swipe to go back, and haptics through the native bridge
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

  /* SF-Symbol-shaped glyphs, stroked thin: the weight is most of the "native". */
  var ICONS = {
    menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
    back: '<path d="M15 5l-7 7 7 7"/>',
    files: '<path d="M3 7.5A2.5 2.5 0 0 1 5.5 5h3.2l1.8 2h8A2.5 2.5 0 0 1 21 9.5v7A2.5 2.5 0 0 1 18.5 19h-13A2.5 2.5 0 0 1 3 16.5z"/>',
    search: '<circle cx="10.8" cy="10.8" r="6.3"/><path d="M15.5 15.5 20 20"/>',
    plus: '<path d="M12 5.5v13M5.5 12h13"/>',
    calendar: '<rect x="3.5" y="5.5" width="17" height="15" rx="3.4"/><path d="M8 3.5v3.6M16 3.5v3.6M3.5 10.4h17"/>',
    library: '<rect x="3.5" y="4.5" width="17" height="15" rx="3"/><path d="M3.5 9.2h17"/>'
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

  function toggleDrawer() {
    var toggle = one(PRESS_TARGETS.drawer);
    if (!toggle) return;
    haptic("light");
    press(toggle);
  }

  function goTo(key) {
    var element = targetFor(key);
    if (!element) return;
    press(element);
    closeDrawer();
  }

  /* ---------------------------------------------------------------------- */
  /* Where we are                                                           */
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

    if (file) return { title: file, detail: path || workspaceName, document: true };

    var active = one(".primary-nav .nav-item.active");
    var caption = active ? active.querySelector("span") : null;
    var view = caption ? (caption.textContent || "").trim() : "";
    return { title: workspaceName, detail: view || "Workspace", document: false };
  }

  /*
   * The app's own history button is the real "back": it walks the same list a
   * desktop user walks. It is disabled at the start of a session, though, and a
   * session restored straight into a note has nowhere to go back to — so the
   * file list stands in. Back is hidden when neither would do anything, which
   * is better than a button that looks live and does nothing.
   */
  function backAction() {
    var history = one(PRESS_TARGETS.back);
    if (history && !history.disabled) return function () { press(history); };
    var location = readLocation();
    if (location.document) {
      var files = targetFor("files");
      if (files) return function () { press(files); };
    }
    return null;
  }

  /* ---------------------------------------------------------------------- */
  /* The bar and the large title                                            */
  /* ---------------------------------------------------------------------- */

  function buildBar() {
    var bar = document.createElement("header");
    bar.className = "m-bar";
    bar.setAttribute("role", "banner");

    var menu = document.createElement("button");
    menu.type = "button";
    menu.className = "m-bar-button m-bar-menu";
    menu.setAttribute("aria-label", "Open library");
    menu.innerHTML = icon("menu");
    menu.addEventListener("click", toggleDrawer);

    var title = document.createElement("div");
    title.className = "m-bar-title";
    var strong = document.createElement("strong");
    var small = document.createElement("small");
    title.appendChild(strong);
    title.appendChild(small);

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
      closeDrawer();
    });

    bar.appendChild(menu);
    bar.appendChild(title);
    bar.appendChild(back);
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
        if (tab.key === "library") {
          toggleDrawer();
          return;
        }
        if (tab.key === "search") {
          haptic("light");
          // The field lives in the drawer, so show the drawer and put the
          // caret in it: a Search tab that only opens a drawer is a dead end.
          if (!drawerIsOpen()) toggleDrawer();
          window.setTimeout(function () {
            var input = one(".sidebar-search input");
            if (input) input.focus();
          }, 320);
          return;
        }
        haptic("light");
        goTo(tab.key);
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
    if (target.closest("input, textarea, select, [contenteditable=true], .todo-board, .sidebar")) return;
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
    if (drawerIsOpen()) { closeDrawer(); haptic("light"); return; }
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
  /* Scrolled state, for the glass bar and the large title                  */
  /* ---------------------------------------------------------------------- */

  var scrolled = false;
  function measureScroll() {
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

    var bar = one(".m-bar");
    if (!bar) return;
    var location = readLocation();
    var strong = bar.querySelector("strong");
    var small = bar.querySelector("small");
    if (strong && strong.textContent !== location.title) strong.textContent = location.title;
    if (small && small.textContent !== location.detail) small.textContent = location.detail;

    var back = bar.querySelector(".m-bar-back");
    if (back) back.hidden = !backAction();

    var active = one(".primary-nav .nav-item.active");
    var view = active ? (active.textContent || "").trim() : "";
    var current = view.indexOf("Calendar") === 0 ? "calendar" : "files";
    var items = document.querySelectorAll(".m-dock-item");
    for (var index = 0; index < items.length; index++) {
      var key = items[index].dataset.tab;
      if (key === "search") continue;
      if (key === "library") {
        // A toggle, so it reports open rather than current.
        if (drawerIsOpen()) items[index].setAttribute("aria-expanded", "true");
        else items[index].removeAttribute("aria-expanded");
        continue;
      }
      if (key === current) items[index].setAttribute("aria-current", "page");
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
