/*
 * Comet for iOS — Tauri bridge shim.
 *
 * Comet is written against Tauri v2's JavaScript API. Every one of those calls
 * funnels through `window.__TAURI_INTERNALS__`, so instead of patching Comet we
 * implement that one object and let the unmodified, unpatched Comet bundle run.
 *
 * The native side injects this file as a WKUserScript at document start and
 * replaces the __COMET_BASE__ placeholder with the address of an in-process
 * HTTP server on 127.0.0.1. Commands travel as JSON over that server rather
 * than through postMessage, which keeps large payloads (Comet streams imports
 * in 512 KB chunks of raw bytes) out of the message-size limits and gives us
 * plain HTTP request logs.
 *
 * Nothing here is Comet-specific: it is the shape of Tauri's own IPC, so any
 * Tauri app would run on top of it.
 */
(function () {
  "use strict";

  var BASE = "__COMET_BASE__";
  // If the placeholder was never substituted the page came from somewhere other
  // than the iOS shell; stay out of the way rather than break the page.
  if (!/^https?:\/\//.test(BASE)) {
    return;
  }

  var nextId = 1;
  var callbacks = Object.create(null);
  var listeners = Object.create(null);

  function invoke(cmd, args) {
    var body;
    try {
      body = JSON.stringify({ cmd: cmd, args: args == null ? {} : args });
    } catch (error) {
      return Promise.reject("Comet bridge: the arguments could not be encoded (" + String(error) + ").");
    }
    return fetch(BASE + "/__invoke", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: body,
      // The bridge is same-origin and must never be served from a cache.
      cache: "no-store",
      credentials: "omit"
    }).then(function (response) {
      if (!response.ok) {
        throw "Comet bridge: the app returned HTTP " + response.status + ".";
      }
      return response.json();
    }).then(function (payload) {
      if (payload && payload.ok) {
        return payload.value === undefined ? null : payload.value;
      }
      // Tauri rejects with a string, and Comet renders errors with String().
      throw payload && typeof payload.error === "string" ? payload.error : "Comet bridge: the request failed.";
    }, function (error) {
      throw "Comet bridge: " + (error && error.message ? error.message : String(error));
    });
  }

  function transformCallback(callback, once) {
    var id = nextId++;
    callbacks[id] = { fn: callback, once: !!once };
    // Tauri's runtime calls back into window["_" + id]; keep that convention so
    // anything else that expects it continues to work.
    window["_" + id] = function (payload) {
      var entry = callbacks[id];
      if (!entry) return;
      if (entry.once) delete callbacks[id];
      if (typeof entry.fn === "function") {
        try { entry.fn(payload); } catch (error) { console.error(error); }
      }
    };
    return id;
  }

  function unregisterCallback(id) {
    delete callbacks[id];
    try { delete window["_" + id]; } catch (error) { /* ignore */ }
  }

  /*
   * Comet loads workspace media through convertFileSrc and then reads it with
   * fetch(), so this has to be a real, fetchable URL rather than a tidier
   * custom scheme that WKWebView would refuse to load.
   */
  function convertFileSrc(filePath) {
    return BASE + "/__file?path=" + encodeURIComponent(String(filePath));
  }

  // @tauri-apps/api/event calls this when a listener is removed. The real
  // runtime installs it; without it, unlisten() would throw.
  window.__TAURI_EVENT_PLUGIN_INTERNALS__ = {
    unregisterListener: function (event, eventId) {
      delete listeners[event + ":" + eventId];
    },
    emit: function () { /* no native emitters in this build */ }
  };

  window.__TAURI_INTERNALS__ = {
    metadata: {
      currentWindow: { label: "main" },
      currentWebview: { windowLabel: "main", label: "main" },
      windows: [{ label: "main" }],
      webviews: [{ windowLabel: "main", label: "main" }]
    },
    plugins: {},
    invoke: invoke,
    transformCallback: transformCallback,
    unregisterCallback: unregisterCallback,
    convertFileSrc: convertFileSrc,
    // Tauri resolves IPC resources through this; Comet does not use channels.
    resolveResource: function (path) { return Promise.resolve(String(path)); }
  };

  // @tauri-apps/api/core isTauri(): Comet decides "desktop" from this and turns
  // on the whole local-files feature set, which is what this shell provides.
  window.isTauri = true;
})();
