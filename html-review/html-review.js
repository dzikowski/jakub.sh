/*
 * html-review.js
 * Standalone, dependency-free review annotations for static HTML.
 */
(function () {
  "use strict";

  var STORAGE_PREFIX = "html-review:";
  var MARK_ATTR = "data-html-review-id";
  var ROOT_SKIP_SELECTOR = "script, style, textarea, input, select, option, button, [contenteditable], .hr-note, .hr-notes-rail, .hr-notes-rail-footer, .hr-popover, .hr-mobile-review, .hr-fixedbar, .hr-export-dialog";
  var NOTES_RAIL_ID = "html-review-notes-rail";
  var NARROW_VIEWPORT_BREAKPOINT_PX = 640;

  var state = {
    annotations: [],
    activeRange: null,
    activeId: null,
    activeType: null,
    notesFrame: null,
    selectionFrame: null,
    options: {
      storageKey: null,
      autoRestore: true
    }
  };

  function nowId() {
    return "hr_" + Date.now().toString(36) + "_" + Math.random().toString(36).slice(2, 8);
  }

  function pageKey() {
    return STORAGE_PREFIX + location.origin + location.pathname;
  }

  function storageKey() {
    return state.options.storageKey || pageKey();
  }

  function isNarrowReviewViewport() {
    try {
      if (window.matchMedia && window.matchMedia("(pointer: coarse)").matches) return true;
    } catch (e) {
      /**/
    }
    return window.innerWidth <= NARROW_VIEWPORT_BREAKPOINT_PX;
  }

  /** Click/touch may target a Text node, which has no `.closest()` in some browsers. */
  function eventTargetElement(ev) {
    var n = ev && ev.target;
    if (!n) return null;
    return n.nodeType === 3 ? n.parentElement : n;
  }

  function syncNotesRailVisibilityClass() {
    var rail = document.getElementById(NOTES_RAIL_ID);
    if (!rail) return;
    rail.classList.toggle("hr-notes-visible", Boolean(rail.querySelector(".hr-note")));
    syncNarrowRailChromeClass();
  }

  function syncNarrowRailChromeClass() {
    try {
      document.body.classList.toggle(
        "hr-narrow-rail-open",
        isNarrowReviewViewport() &&
          Boolean(
            document.getElementById(NOTES_RAIL_ID) &&
              document.getElementById(NOTES_RAIL_ID).classList.contains("hr-notes-visible")
          )
      );
    } catch (e) {
      /**/
    }
  }

  function loadAnnotations() {
    try {
      var raw = localStorage.getItem(storageKey());
      return raw ? JSON.parse(raw) : [];
    } catch (error) {
      console.warn("html-review: could not load annotations", error);
      return [];
    }
  }

  function saveAnnotations() {
    localStorage.setItem(storageKey(), JSON.stringify(state.annotations));
  }

  function injectStyles() {
    if (document.getElementById("html-review-styles")) return;

    var bp = String(NARROW_VIEWPORT_BREAKPOINT_PX);
    var mobRailSheet =
      "top:auto;bottom:0;left:0;right:0;width:100%;max-width:none;height:auto;max-height:33vh;min-height:0;transform:none;" +
      "padding:0;border-radius:14px 14px 0 0;overflow:hidden;" +
      "box-shadow:0 -8px 28px rgba(15,23,42,.12);border:1px solid rgba(246,209,133,.72);border-bottom:0;" +
      "background:rgba(254,252,246,.96);display:flex;flex-direction:column;box-sizing:border-box;";

    var mobRailFooter =
      "display:flex;flex-wrap:wrap;gap:8px;justify-content:center;align-items:center;flex-shrink:0;" +
      "padding:10px max(12px,env(safe-area-inset-left,0px)) calc(10px + env(safe-area-inset-bottom,0px)) max(12px,env(safe-area-inset-right,0px));" +
      "border-top:1px solid rgba(246,209,133,.72);background:rgba(255,255,255,.94);font:13px/1.3 system-ui,-apple-system,Segoe UI,sans-serif;pointer-events:auto;box-sizing:border-box;";

    var style = document.createElement("style");
    style.id = "html-review-styles";
    style.textContent = [
      ".hr-mark{cursor:pointer;touch-action:manipulation;-webkit-touch-callout:none;border-radius:2px;padding:0 1px;}",
      ".hr-comment{position:relative;background:#fff7cc;border-bottom:2px solid #d69e2e;box-decoration-break:clone;-webkit-box-decoration-break:clone;}",
      ".hr-notes-rail{display:none;}",
      ".hr-notes-rail.hr-notes-visible{display:block;position:fixed;z-index:2147483643;top:0;right:0;bottom:96px;width:min(280px,calc(100vw - 32px));overflow-x:hidden;overflow-y:auto;pointer-events:auto;-webkit-overflow-scrolling:touch;padding:0 0 0 14px;box-sizing:border-box;}",
      ".hr-notes-rail:has(.hr-note){display:block;position:fixed;z-index:2147483643;top:0;right:0;bottom:96px;width:min(280px,calc(100vw - 32px));overflow-x:hidden;overflow-y:auto;pointer-events:auto;-webkit-overflow-scrolling:touch;padding:0 0 0 14px;box-sizing:border-box;}",
      ".hr-notes-rail-sizer{position:relative;width:100%;min-height:100%;pointer-events:none;box-sizing:border-box;}",
      "@media(max-width:" + bp + "px){.hr-notes-rail.hr-notes-visible{" + mobRailSheet + "}}",
      "@media(max-width:" + bp + "px){.hr-notes-rail:has(.hr-note){" + mobRailSheet + "}}",
      "@media(max-width:" +
        bp +
        "px){.hr-notes-rail-sizer{min-height:0;flex:1 1 auto;display:flex;flex-direction:column;gap:8px;pointer-events:auto;padding:10px max(12px,env(safe-area-inset-left,0px)) 8px max(12px,env(safe-area-inset-right,0px));overflow-x:hidden;overflow-y:auto;-webkit-overflow-scrolling:touch;box-sizing:border-box;}}",
      "@media(max-width:" +
        bp +
        "px){.hr-notes-rail-sizer .hr-note{position:relative;top:auto;" +
        "left:auto;right:auto;width:100%;max-width:none;flex-shrink:0;" +
        "touch-action:manipulation;-webkit-touch-callout:none}}",
      ".hr-notes-rail-footer{display:none;}",
      "@media(max-width:" + bp + "px){.hr-notes-rail.hr-notes-visible .hr-notes-rail-footer{" + mobRailFooter + "}}",
      "@media(max-width:" + bp + "px){.hr-notes-rail:has(.hr-note) .hr-notes-rail-footer{" + mobRailFooter + "}}",
      "@media(max-width:" +
        bp +
        "px){.hr-notes-rail-footer button{font:inherit;border:0;border-radius:8px;padding:7px 10px;cursor:pointer;background:#111827;color:white;}}",
      "@media(max-width:" +
        bp +
        "px){.hr-notes-rail-footer button.hr-secondary{background:#f3f4f6;color:#111827;}}",
      "@media(max-width:" +
        bp +
        "px){.hr-fixedbar{left:0;right:0;width:100%;max-width:none;border-radius:0;" +
        "justify-content:center;padding:10px max(16px,env(safe-area-inset-left,0px)) calc(10px + env(safe-area-inset-bottom,0px)) max(16px,env(safe-area-inset-right,0px));" +
        "bottom:0;box-shadow:0 -8px 26px rgba(15,23,42,.1);border-top:1px solid #d1d5db;border-bottom:0;" +
        "background:rgba(255,255,255,.98);}}",
      "@media(max-width:" + bp + "px){body.hr-narrow-rail-open .hr-fixedbar{display:none!important}}",
      ".hr-note{position:absolute;left:0;right:16px;width:auto;max-width:none;box-sizing:border-box;min-height:18px;white-space:normal;background:#fffbeb;color:#713f12;border:1px solid #f2c94c;border-left:4px solid #d69e2e;border-radius:10px;padding:8px 10px;box-shadow:6px 12px 26px rgba(120,53,15,.14), -3px 0 14px rgba(120,53,15,.085);font:12px/1.35 system-ui,-apple-system,Segoe UI,sans-serif;cursor:pointer;outline:none;pointer-events:auto;}",
      ".hr-note:hover{filter:brightness(.985);}",
      ".hr-note:empty::before{content:'Comment';color:#92400e;font-style:italic;}",
      ".hr-connector{position:fixed;height:0;border-top:2px dotted #d69e2e;transform-origin:left center;pointer-events:none;z-index:2147483644;}",
      ".hr-change del{color:#b42318;background:#fee4e2;text-decoration:line-through;text-decoration-thickness:2px;}",
      ".hr-change ins{color:#067647;background:#dcfae6;text-decoration:none;margin-left:.2em;}",
      ".hr-mark.hr-active{outline:2px solid #2563eb;outline-offset:2px;}",
      ".hr-popover button,.hr-export-dialog button{font:inherit;border:0;border-radius:7px;padding:6px 9px;cursor:pointer;background:#e5e7eb;color:#111827;}",
      ".hr-popover button:hover,.hr-export-dialog button:hover{filter:brightness(.95);}",
      ".hr-fixedbar{position:fixed;right:16px;bottom:calc(16px + env(safe-area-inset-bottom,0px));z-index:2147483646;display:flex;gap:8px;padding:8px;background:white;border:1px solid #d1d5db;border-radius:12px;box-shadow:0 12px 32px rgba(15,23,42,.18);font:13px/1.3 system-ui,-apple-system,Segoe UI,sans-serif;}",
      ".hr-fixedbar button{font:inherit;border:0;border-radius:8px;padding:7px 10px;cursor:pointer;background:#111827;color:white;}",
      ".hr-fixedbar button.hr-secondary{background:#f3f4f6;color:#111827;}",
      ".hr-popover{position:fixed;z-index:2147483647;width:min(360px,calc(100vw - 24px));display:none;background:white;color:#111827;border:1px solid #d1d5db;border-radius:12px;box-shadow:0 18px 42px rgba(15,23,42,.24);padding:12px;font:13px/1.45 system-ui,-apple-system,Segoe UI,sans-serif;}",
      ".hr-popover textarea{width:100%;box-sizing:border-box;min-height:86px;margin:8px 0;border:1px solid #d1d5db;border-radius:8px;padding:8px;font:inherit;}",
      ".hr-popover .hr-title{font-weight:700;margin-bottom:4px;}",
      ".hr-popover .hr-meta{color:#6b7280;font-size:12px;margin-bottom:8px;}",
      ".hr-popover .hr-status{color:#6b7280;font-size:12px;min-height:16px;margin-top:-2px;margin-bottom:8px;}",
      ".hr-popover .hr-actions{display:flex;flex-wrap:wrap;gap:8px;align-items:center;}",
      ".hr-popover [data-hr-popover='cancel']{margin-right:auto;}",
      ".hr-popover .hr-convert-action{background:#f3f4f6;color:#111827;border:1px solid #d1d5db;}",
      ".hr-popover .hr-comment-action{background:#fef3c7;color:#92400e;border:1px solid #f2c94c;}",
      ".hr-popover .hr-suggestion-action{background:#111827;color:white;border:1px solid #111827;}",
      ".hr-popover .hr-primary{background:#111827;color:white;}",
      ".hr-popover .hr-danger{background:#fee2e2;color:#991b1b;}",
      ".hr-mobile-review{position:fixed;z-index:2147483647;display:none;border:0;border-radius:999px;padding:9px 13px;background:#111827;color:white;box-shadow:0 12px 28px rgba(15,23,42,.28);font:600 13px/1.2 system-ui,-apple-system,Segoe UI,sans-serif;}",
      ".hr-export-dialog{position:fixed;z-index:2147483647;inset:5vh 5vw;display:none;background:white;color:#111827;border:1px solid #d1d5db;border-radius:14px;box-shadow:0 24px 70px rgba(15,23,42,.35);padding:16px;font:13px/1.45 system-ui,-apple-system,Segoe UI,sans-serif;}",
      ".hr-export-dialog textarea{width:100%;height:calc(100% - 90px);box-sizing:border-box;border:1px solid #d1d5db;border-radius:10px;padding:10px;font:12px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace;}",
      ".hr-export-dialog .hr-actions{display:flex;gap:8px;justify-content:flex-end;margin-top:10px;}",
      ".hr-backdrop{position:fixed;z-index:2147483646;inset:0;background:rgba(15,23,42,.32);display:none;}"
    ].join("");
    document.head.appendChild(style);
  }

  function textNodesUnder(root) {
    var nodes = [];
    var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
      acceptNode: function (node) {
        if (!node.nodeValue || !node.nodeValue.trim()) return NodeFilter.FILTER_REJECT;
        if (node.parentElement && node.parentElement.closest(ROOT_SKIP_SELECTOR)) return NodeFilter.FILTER_REJECT;
        return NodeFilter.FILTER_ACCEPT;
      }
    });
    var node;
    while ((node = walker.nextNode())) nodes.push(node);
    return nodes;
  }

  function textOffsetWithin(root, targetNode, targetOffset) {
    var nodes = textNodesUnder(root);
    var offset = 0;
    for (var i = 0; i < nodes.length; i += 1) {
      if (nodes[i] === targetNode) return offset + targetOffset;
      offset += nodes[i].nodeValue.length;
    }
    return -1;
  }

  function reviewableText(root) {
    return textNodesUnder(root).map(function (node) {
      return node.nodeValue;
    }).join("");
  }

  function pointFromTextOffset(root, offset) {
    var nodes = textNodesUnder(root);
    var remaining = offset;
    for (var i = 0; i < nodes.length; i += 1) {
      var length = nodes[i].nodeValue.length;
      if (remaining <= length) return { node: nodes[i], offset: remaining };
      remaining -= length;
    }
    if (!nodes.length) return null;
    var last = nodes[nodes.length - 1];
    return { node: last, offset: last.nodeValue.length };
  }

  function elementForRange(range) {
    var node = range.commonAncestorContainer;
    return node.nodeType === Node.ELEMENT_NODE ? node : node.parentElement;
  }

  function cssEscape(value) {
    if (window.CSS && CSS.escape) return CSS.escape(value);
    return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\$&");
  }

  function cssPath(element) {
    if (!element || element === document.body) return "body";
    if (element.id) return "#" + cssEscape(element.id);

    var parts = [];
    var current = element;
    while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.body) {
      var name = current.nodeName.toLowerCase();
      var parent = current.parentElement;
      if (!parent) break;

      var siblings = Array.prototype.filter.call(parent.children, function (child) {
        return child.nodeName === current.nodeName;
      });
      if (siblings.length > 1) {
        name += ":nth-of-type(" + (siblings.indexOf(current) + 1) + ")";
      }
      parts.unshift(name);
      current = parent;
    }
    parts.unshift("body");
    return parts.join(" > ");
  }

  function quoteFor(root, start, end) {
    var text = reviewableText(root);
    return {
      exact: text.slice(start, end),
      prefix: text.slice(Math.max(0, start - 40), start),
      suffix: text.slice(end, end + 40)
    };
  }

  function occurrenceFor(text, exact, beforeIndex) {
    var occurrence = 0;
    var index = text.indexOf(exact);
    while (index !== -1 && index < beforeIndex) {
      occurrence += 1;
      index = text.indexOf(exact, index + exact.length);
    }
    return occurrence;
  }

  function anchorForRange(range) {
    var root = elementForRange(range);
    if (!root || root.closest(ROOT_SKIP_SELECTOR)) return null;

    var start = textOffsetWithin(root, range.startContainer, range.startOffset);
    var end = textOffsetWithin(root, range.endContainer, range.endOffset);
    if (start < 0 || end <= start) return null;

    var quote = quoteFor(root, start, end);
    return {
      cssPath: cssPath(root),
      textStart: start,
      textEnd: end,
      occurrence: occurrenceFor(reviewableText(root), quote.exact, start),
      quote: quote
    };
  }

  function rangeFromAnchor(anchor) {
    var root = document.querySelector(anchor.cssPath);
    if (!root) return null;

    var text = reviewableText(root);
    var exact = anchor.quote && anchor.quote.exact;
    if (!exact) return null;

    var index = -1;
    var from = 0;
    for (var i = 0; i <= (anchor.occurrence || 0); i += 1) {
      index = text.indexOf(exact, from);
      if (index === -1) break;
      from = index + exact.length;
    }

    if (index === -1 && typeof anchor.textStart === "number") {
      if (text.slice(anchor.textStart, anchor.textStart + exact.length) === exact) {
        index = anchor.textStart;
      }
    }
    if (index === -1) return null;

    var start = pointFromTextOffset(root, index);
    var end = pointFromTextOffset(root, index + exact.length);
    if (!start || !end) return null;

    var range = document.createRange();
    range.setStart(start.node, start.offset);
    range.setEnd(end.node, end.offset);
    return range;
  }

  function selectedRange() {
    var selection = window.getSelection();
    if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
    var range = selection.getRangeAt(0);
    if (!range.toString().trim()) return null;
    return range.cloneRange();
  }

  function clearSelection() {
    var selection = window.getSelection();
    if (selection) selection.removeAllRanges();
  }

  function notesRail() {
    var rail = document.getElementById(NOTES_RAIL_ID);
    if (rail) return rail;

    rail = document.createElement("div");
    rail.id = NOTES_RAIL_ID;
    rail.className = "hr-notes-rail";
    rail.setAttribute("aria-label", "Review comments");
    rail.addEventListener("scroll", scheduleReviewNotePositioning, { passive: true });
    document.body.appendChild(rail);
    ensureNotesRailFooter(rail);
    return rail;
  }

  function onReviewFixedToolbarClick(event) {
    var action = event.target && event.target.getAttribute("data-hr-fixed");
    if (action === "export") showExportDialog();
    if (action === "clear" && window.confirm("Remove all saved review annotations for this page?")) {
      localStorage.removeItem(storageKey());
      location.reload();
    }
  }

  function ensureNotesRailFooter(rail) {
    var footer = rail.querySelector(".hr-notes-rail-footer");
    if (!footer) {
      footer = document.createElement("div");
      footer.className = "hr-notes-rail-footer";
      footer.setAttribute("aria-label", "Review actions");
      footer.innerHTML = [
        "<button type=\"button\" data-hr-fixed=\"export\">Export review</button>",
        "<button type=\"button\" class=\"hr-secondary\" data-hr-fixed=\"clear\">Clear page</button>"
      ].join("");
      footer.addEventListener("click", onReviewFixedToolbarClick);
      rail.appendChild(footer);
    }
    return footer;
  }

  function ensureNotesRailSizer(rail) {
    ensureNotesRailFooter(rail);
    var footer = rail.querySelector(".hr-notes-rail-footer");
    var sizer = rail.querySelector(".hr-notes-rail-sizer");
    if (!sizer) {
      sizer = document.createElement("div");
      sizer.className = "hr-notes-rail-sizer";
      if (footer) rail.insertBefore(sizer, footer);
      else rail.appendChild(sizer);
      if (!sizer.dataset.hrReviewScrollBound) {
        sizer.dataset.hrReviewScrollBound = "1";
        sizer.addEventListener("scroll", scheduleReviewNotePositioning, { passive: true });
      }
    }
    return sizer;
  }

  function createCommentUi(annotation) {
    var connector = document.createElement("span");
    connector.className = "hr-connector";

    var note = document.createElement("div");
    note.className = "hr-note";
    note.setAttribute("data-hr-note-for", annotation.id);
    note.setAttribute("aria-label", "Review comment");
    note.textContent = annotation.content || "";

    ensureNotesRailSizer(notesRail()).appendChild(note);
    syncNotesRailVisibilityClass();
    return { connector: connector, note: note };
  }

  function layoutAnchoredNoteTops(layouts, marginTop, marginBottom, stackGap) {
    if (!layouts.length) return [];
    var maxB = window.innerHeight - marginBottom;
    var n = layouts.length;
    var desired = layouts.map(function (it) {
      return it.anchorMidY - it.h / 2;
    });
    var hList = layouts.map(function (it) {
      return it.h;
    });
    var tops = [];
    var i;
    tops[0] = desired[0];
    for (i = 1; i < n; i += 1) {
      tops[i] = Math.max(desired[i], tops[i - 1] + hList[i - 1] + stackGap);
    }

    var spanTop = tops[0];
    var spanBot = tops[n - 1] + hList[n - 1];
    var low = marginTop - spanTop;
    var high = maxB - spanBot;
    var shift = 0;
    if (low <= high) {
      if (0 < low) shift = low;
      else if (0 > high) shift = high;
    } else {
      shift = low;
    }
    for (i = 0; i < n; i += 1) {
      tops[i] += shift;
    }
    return tops;
  }

  function positionReviewNotes() {
    var rail = document.getElementById(NOTES_RAIL_ID);
    if (!rail) return;

    var marks = Array.prototype.filter.call(
      document.querySelectorAll(".hr-comment[" + MARK_ATTR + "]"),
      function (m) {
        return Boolean(m.querySelector(".hr-connector"));
      }
    );

    marks.sort(function (a, b) {
      return a.getBoundingClientRect().top - b.getBoundingClientRect().top;
    });

    var sizer = ensureNotesRailSizer(rail);

    marks.forEach(function (mark) {
      var id = mark.getAttribute(MARK_ATTR);
      var note = rail.querySelector(".hr-note[data-hr-note-for='" + id + "']");
      if (note) sizer.appendChild(note);
    });

    var marginTopNotes = 12;
    var marginBottomNotes = 96;
    var stackGapPx = 8;
    var markConnectorPadPx = 6;
    var noteConnectorPadPx = 4;

    var narrow = isNarrowReviewViewport();

    var layouts = [];

    marks.forEach(function (mark) {
      var connector = mark.querySelector(".hr-connector");
      var id = mark.getAttribute(MARK_ATTR);
      var note = document.querySelector(".hr-note[data-hr-note-for='" + id + "']");
      if (!connector || !note) return;

      var rect = mark.getBoundingClientRect();

      if (rect.bottom < -8 || rect.top > window.innerHeight + 8) {
        connector.style.display = "none";
        note.style.display = "none";
        note.setAttribute("aria-hidden", "true");
        return;
      }

      var noteWasHidden = note.style.display === "none";
      if (noteWasHidden) note.style.display = "";

      if (!narrow) {
        var railPadLeft = parseFloat(window.getComputedStyle(rail).paddingLeft) || 0;
        var approxNoteLeft = rail.getBoundingClientRect().left + railPadLeft;
        var roughStart = Math.min(window.innerWidth - 20, Math.max(12, rect.right + markConnectorPadPx));
        if (approxNoteLeft - noteConnectorPadPx - roughStart <= 8) {
          connector.style.display = "none";
          note.style.display = "none";
          note.setAttribute("aria-hidden", "true");
          return;
        }
      }

      layouts.push({
        connector: connector,
        note: note,
        rect: rect,
        anchorMidY: rect.top + rect.height / 2,
        h: note.offsetHeight
      });
    });

    if (narrow) {
      marks.forEach(function (mark) {
        var c = mark.querySelector(".hr-connector");
        if (c) c.style.display = "none";
      });

      layouts.forEach(function (item) {
        var note = item.note;
        note.style.position = "";
        note.style.left = "";
        note.style.right = "";
        note.style.top = "";
        note.style.width = "";
        note.style.maxWidth = "";
        note.style.display = "";
        note.removeAttribute("aria-hidden");
      });

      sizer.style.minHeight = "";
    } else {
      var tops = layoutAnchoredNoteTops(layouts, marginTopNotes, marginBottomNotes, stackGapPx);

      if (layouts.length) {
        var lastIx = layouts.length - 1;
        var layoutBottomPx = tops[lastIx] + layouts[lastIx].h;
        var railViewportH = rail.clientHeight;
        sizer.style.minHeight = Math.max(railViewportH, layoutBottomPx + 12) + "px";
      } else {
        sizer.style.minHeight = "";
      }

      layouts.forEach(function (item, i) {
        var note = item.note;
        var connector = item.connector;
        var rect = item.rect;

        note.style.position = "absolute";
        note.style.left = "0";
        note.style.right = "16px";
        note.style.width = "";
        note.style.maxWidth = "";
        note.style.top = tops[i] + "px";

        note.style.display = "";
        note.removeAttribute("aria-hidden");

        var noteRect = note.getBoundingClientRect();
        var startX = Math.min(window.innerWidth - 20, Math.max(12, rect.right + markConnectorPadPx));
        var startY = rect.top + rect.height / 2;
        var endX = noteRect.left - noteConnectorPadPx;
        var endY = noteRect.top + noteRect.height / 2;
        var dx = endX - startX;
        var dy = endY - startY;

        if (dx <= 8) {
          connector.style.display = "none";
          note.style.display = "none";
          note.setAttribute("aria-hidden", "true");
          return;
        }

        connector.style.display = "block";
        note.style.display = "";
        note.removeAttribute("aria-hidden");
        connector.style.left = startX + "px";
        connector.style.top = startY + "px";
        connector.style.width = Math.sqrt(dx * dx + dy * dy) + "px";
        connector.style.transform = "rotate(" + Math.atan2(dy, dx) + "rad)";
      });
    }

    syncNotesRailVisibilityClass();
  }

  function scheduleReviewNotePositioning() {
    if (state.notesFrame) return;
    state.notesFrame = window.requestAnimationFrame(function () {
      state.notesFrame = null;
      positionReviewNotes();
    });
  }

  function textSegmentsInRange(range) {
    var root = elementForRange(range);
    return textNodesUnder(root).filter(function (node) {
      return range.intersectsNode(node);
    }).map(function (node) {
      return {
        node: node,
        start: node === range.startContainer ? range.startOffset : 0,
        end: node === range.endContainer ? range.endOffset : node.nodeValue.length
      };
    }).filter(function (segment) {
      return segment.end > segment.start;
    });
  }

  function wrapTextSegment(segment, annotation, includeReviewNote, includeReplacement) {
    var textNode = segment.node;
    var start = segment.start;
    var end = segment.end;

    if (end < textNode.nodeValue.length) textNode.splitText(end);
    if (start > 0) textNode = textNode.splitText(start);

    var span = document.createElement("span");
    span.className = "hr-mark " + (annotation.type === "change" ? "hr-change" : "hr-comment");
    span.setAttribute(MARK_ATTR, annotation.id);
    span.title = annotation.type === "comment" ? annotation.content : "Suggested change";

    var parent = textNode.parentNode;
    parent.insertBefore(span, textNode);

    if (annotation.type === "change") {
      var del = document.createElement("del");
      del.appendChild(textNode);
      span.appendChild(del);

      if (includeReplacement && annotation.contentAfter) {
        var ins = document.createElement("ins");
        ins.textContent = annotation.contentAfter;
        span.appendChild(ins);
      }
      return span;
    }

    span.appendChild(textNode);
    if (includeReviewNote) {
      var commentUi = createCommentUi(annotation);
      span.appendChild(commentUi.connector);
    }
    return span;
  }

  function wrapRange(range, annotation) {
    var segments = textSegmentsInRange(range);
    var firstMark = null;

    for (var i = segments.length - 1; i >= 0; i -= 1) {
      var mark = wrapTextSegment(segments[i], annotation, i === 0, i === 0);
      if (i === 0) firstMark = mark;
    }

    scheduleReviewNotePositioning();
    return firstMark;
  }

  function applyAnnotation(annotation) {
    if (document.querySelector("[" + MARK_ATTR + "='" + annotation.id + "']")) return;
    var range = rangeFromAnchor(annotation.anchor);
    if (!range) return;
    wrapRange(range, annotation);
  }

  function restoreAnnotations() {
    state.annotations.forEach(applyAnnotation);
    scheduleReviewNotePositioning();
  }

  function annotationById(id) {
    return state.annotations.filter(function (item) {
      return item.id === id;
    })[0];
  }

  function removeMarkElement(mark) {
    if (!mark) return;
    var parent = mark.parentNode;

    if (mark.classList.contains("hr-change")) {
      var original = mark.querySelector("del");
      while (original && original.firstChild) parent.insertBefore(original.firstChild, mark);
      parent.removeChild(mark);
      parent.normalize();
      return;
    }

    var rid = mark.getAttribute(MARK_ATTR);
    mark.querySelectorAll(".hr-connector").forEach(function (reviewUi) {
      reviewUi.remove();
    });
    var railNote = rid && document.querySelector(".hr-note[data-hr-note-for='" + rid + "']");
    if (railNote) railNote.remove();
    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parent.normalize();
    syncNotesRailVisibilityClass();
  }

  function removeAnnotation(id) {
    document.querySelectorAll("[" + MARK_ATTR + "='" + id + "']").forEach(removeMarkElement);
    state.annotations = state.annotations.filter(function (item) {
      return item.id !== id;
    });
    saveAnnotations();
    hidePopover();
  }

  function removeAnnotationDomOnly(id) {
    document.querySelectorAll("[" + MARK_ATTR + "='" + id + "']").forEach(removeMarkElement);
  }

  function convertCommentToSuggestion(annotation) {
    var text = popover().querySelector("textarea").value;
    removeAnnotationDomOnly(annotation.id);
    annotation.type = "change";
    annotation.updatedAt = new Date().toISOString();
    delete annotation.content;
    annotation.contentBefore = annotation.anchor && annotation.anchor.quote ? annotation.anchor.quote.exact : "";
    annotation.contentAfter = text;
    updateAnnotation(annotation);
    applyAnnotation(annotation);
    var mark = document.querySelector("[" + MARK_ATTR + "='" + annotation.id + "']");
    if (mark) showPopover(mark);
  }

  function convertSuggestionToComment(annotation) {
    var text = popover().querySelector("textarea").value;
    removeAnnotationDomOnly(annotation.id);
    annotation.type = "comment";
    annotation.updatedAt = new Date().toISOString();
    delete annotation.contentBefore;
    delete annotation.contentAfter;
    annotation.content = text;
    updateAnnotation(annotation);
    applyAnnotation(annotation);
    var mark = document.querySelector("[" + MARK_ATTR + "='" + annotation.id + "']");
    if (mark) showPopover(mark);
  }

  function updateAnnotation(annotation) {
    var index = state.annotations.findIndex(function (item) {
      return item.id === annotation.id;
    });
    if (index >= 0) state.annotations[index] = annotation;
    saveAnnotations();
  }

  function createAnnotation(type, contentAfterOrComment) {
    var range = state.activeRange || selectedRange();
    if (!range) return null;

    var anchor = anchorForRange(range);
    if (!anchor) return null;

    var selected = range.toString();
    var annotation = {
      id: nowId(),
      type: type,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      anchor: anchor
    };

    if (type === "comment") {
      annotation.content = contentAfterOrComment || "";
    } else {
      annotation.contentBefore = selected;
      annotation.contentAfter = contentAfterOrComment || "";
    }

    if (!wrapRange(range, annotation)) return null;
    state.annotations.push(annotation);
    saveAnnotations();
    state.activeRange = null;
    clearSelection();
    hideMobileReviewButton();
    return annotation;
  }

  function updateAnnotationContent(annotation, value) {
    annotation.updatedAt = new Date().toISOString();

    if (annotation.type === "comment") {
      annotation.content = value;
      var mark = document.querySelector("[" + MARK_ATTR + "='" + annotation.id + "']");
      if (mark) {
        mark.title = value;
        var note = document.querySelector(".hr-note[data-hr-note-for='" + annotation.id + "']");
        if (note && note.textContent !== value) note.textContent = value;
        scheduleReviewNotePositioning();
      }
    } else {
      annotation.contentAfter = value;
      var changeMark = document.querySelector("[" + MARK_ATTR + "='" + annotation.id + "']");
      var ins = changeMark && changeMark.querySelector("ins");
      if (!ins && value && changeMark) {
        ins = document.createElement("ins");
        changeMark.appendChild(ins);
      }
      if (ins) ins.textContent = value;
    }

    updateAnnotation(annotation);
  }

  function exportAnnotations() {
    return {
      page: {
        url: location.href,
        title: document.title
      },
      entries: state.annotations.map(function (annotation) {
        var base = {
          id: annotation.id,
          type: annotation.type,
          cssPath: annotation.anchor.cssPath,
          occurrence: annotation.anchor.occurrence,
          quote: annotation.anchor.quote,
          createdAt: annotation.createdAt,
          updatedAt: annotation.updatedAt
        };

        if (annotation.type === "comment") {
          base.content = annotation.content;
        } else {
          base.contentBefore = annotation.contentBefore;
          base.contentAfter = annotation.contentAfter;
        }
        return base;
      })
    };
  }

  function positionPopoverForRange(range, el) {
    var rect = range.getBoundingClientRect();
    el.style.left = Math.max(8, Math.min(window.innerWidth - el.offsetWidth - 8, rect.left)) + "px";
    el.style.top = Math.max(8, Math.min(window.innerHeight - el.offsetHeight - 8, rect.bottom + 8)) + "px";
  }

  function isCoarsePointer() {
    return Boolean(window.matchMedia && window.matchMedia("(pointer: coarse)").matches);
  }

  function createMobileReviewButton() {
    var button = document.createElement("button");
    button.type = "button";
    button.className = "hr-mobile-review";
    button.textContent = "Review";
    document.body.appendChild(button);

    button.addEventListener("click", function (event) {
      event.preventDefault();
      event.stopPropagation();
      showComposer("");
    });

    return button;
  }

  function mobileReviewButton() {
    return document.querySelector(".hr-mobile-review") || createMobileReviewButton();
  }

  function hideMobileReviewButton() {
    var button = document.querySelector(".hr-mobile-review");
    if (button) button.style.display = "none";
  }

  function showMobileReviewButton(range) {
    if (!isCoarsePointer() || !range) return;

    state.activeRange = range;
    var rect = range.getBoundingClientRect();
    var button = mobileReviewButton();
    button.style.display = "block";

    var left = rect.left + rect.width / 2 - button.offsetWidth / 2;
    var top = rect.bottom + 10;
    if (top + button.offsetHeight + 8 > window.innerHeight) top = rect.top - button.offsetHeight - 10;

    button.style.left = Math.max(8, Math.min(window.innerWidth - button.offsetWidth - 8, left)) + "px";
    button.style.top = Math.max(8, Math.min(window.innerHeight - button.offsetHeight - 8, top)) + "px";
  }

  function updateMobileSelectionButton() {
    if (!isCoarsePointer()) return;

    var range = selectedRange();
    if (range) {
      showMobileReviewButton(range);
    } else {
      hideMobileReviewButton();
    }
  }

  function scheduleMobileSelectionButton() {
    if (!isCoarsePointer() || state.selectionFrame) return;
    state.selectionFrame = window.requestAnimationFrame(function () {
      state.selectionFrame = null;
      updateMobileSelectionButton();
    });
  }

  function createFixedBar() {
    var bar = document.createElement("div");
    bar.className = "hr-fixedbar";
    bar.innerHTML = [
      "<button type=\"button\" data-hr-fixed=\"export\">Export review</button>",
      "<button type=\"button\" class=\"hr-secondary\" data-hr-fixed=\"clear\">Clear page</button>"
    ].join("");
    document.body.appendChild(bar);

    bar.addEventListener("click", onReviewFixedToolbarClick);
  }

  function createPopover() {
    var popover = document.createElement("div");
    popover.className = "hr-popover";
    popover.innerHTML = [
      "<div class=\"hr-title\"></div>",
      "<div class=\"hr-meta\"></div>",
      "<textarea></textarea>",
      "<div class=\"hr-status\"></div>",
      "<div class=\"hr-actions\">",
      "<button type=\"button\" data-hr-popover=\"cancel\">Cancel</button>",
      "<button type=\"button\" class=\"hr-danger\" data-hr-popover=\"remove\">Remove</button>",
      "<button type=\"button\" class=\"hr-convert-action\" data-hr-popover=\"to-suggestion\">Convert to suggestion</button>",
      "<button type=\"button\" class=\"hr-convert-action\" data-hr-popover=\"to-comment\">Convert to comment</button>",
      "<button type=\"button\" class=\"hr-comment-action\" data-hr-popover=\"comment\">Comment</button>",
      "<button type=\"button\" class=\"hr-suggestion-action\" data-hr-popover=\"replace\">Submit suggestion</button>",
      "</div>"
    ].join("");
    document.body.appendChild(popover);

    popover.querySelector("textarea").addEventListener("input", function () {
      if (popover.dataset.mode !== "edit") return;

      var annotation = annotationById(state.activeId);
      if (!annotation) return;
      updateAnnotationContent(annotation, popover.querySelector("textarea").value);
      popover.querySelector(".hr-status").textContent = "Saved";
    });

    popover.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        event.preventDefault();
        event.stopPropagation();
        hidePopover();
        return;
      }

      if (event.key !== "Enter" || (!event.metaKey && !event.ctrlKey) || popover.dataset.mode !== "create") return;
      event.preventDefault();
      event.stopPropagation();

      if (event.shiftKey) {
        popover.querySelector("[data-hr-popover='comment']").click();
      } else {
        popover.querySelector("[data-hr-popover='replace']").click();
      }
    });

    popover.addEventListener("click", function (event) {
      var action = event.target && event.target.getAttribute("data-hr-popover");
      if (!action) return;

      if (action === "cancel") {
        hidePopover();
        return;
      }

      if (action === "comment") {
        createAnnotation("comment", popover.querySelector("textarea").value);
        hidePopover();
        return;
      }

      if (action === "replace") {
        createAnnotation("change", popover.querySelector("textarea").value);
        hidePopover();
        return;
      }

      if (action === "remove") {
        var annotation = annotationById(state.activeId);
        if (annotation) removeAnnotation(annotation.id);
        return;
      }

      if (action === "to-suggestion") {
        var toChange = annotationById(state.activeId);
        if (toChange && toChange.type === "comment") convertCommentToSuggestion(toChange);
        return;
      }

      if (action === "to-comment") {
        var toComment = annotationById(state.activeId);
        if (toComment && toComment.type === "change") convertSuggestionToComment(toComment);
        return;
      }
    });

    return popover;
  }

  function popover() {
    return document.querySelector(".hr-popover") || createPopover();
  }

  function configurePopoverActions(el, mode, type) {
    var removeButton = el.querySelector("[data-hr-popover='remove']");
    var commentButton = el.querySelector("[data-hr-popover='comment']");
    var replaceButton = el.querySelector("[data-hr-popover='replace']");
    var cancelButton = el.querySelector("[data-hr-popover='cancel']");
    var toSuggestionButton = el.querySelector("[data-hr-popover='to-suggestion']");
    var toCommentButton = el.querySelector("[data-hr-popover='to-comment']");

    removeButton.style.display = mode === "edit" ? "" : "none";
    commentButton.style.display = mode === "create" ? "" : "none";
    replaceButton.style.display = mode === "create" ? "" : "none";
    if (toSuggestionButton) {
      toSuggestionButton.style.display = mode === "edit" && type === "comment" ? "" : "none";
    }
    if (toCommentButton) {
      toCommentButton.style.display = mode === "edit" && type === "change" ? "" : "none";
    }
    removeButton.textContent = type === "comment" ? "Remove comment" : "Remove suggestion";
    cancelButton.textContent = "Cancel";
  }

  function showComposer(initialValue) {
    var range = state.activeRange || selectedRange();
    if (!range) return;

    state.activeId = null;
    state.activeType = "change";

    var el = popover();
    el.dataset.mode = "create";
    el.querySelector(".hr-title").textContent = "Review selection";
    el.querySelector(".hr-meta").textContent = range.toString();
    el.querySelector("textarea").value = initialValue || "";
    el.querySelector("textarea").placeholder = "Type a comment or replacement...";
    el.querySelector(".hr-status").textContent = "";
    configurePopoverActions(el, "create", "change");

    el.style.display = "block";
    hideMobileReviewButton();
    positionPopoverForRange(range, el);
    el.querySelector("textarea").focus();
    el.querySelector("textarea").setSelectionRange(el.querySelector("textarea").value.length, el.querySelector("textarea").value.length);
  }

  function showPopover(mark) {
    var annotation = annotationById(mark.getAttribute(MARK_ATTR));
    if (!annotation) return;

    state.activeId = annotation.id;
    state.activeType = annotation.type;
    document.querySelectorAll(".hr-active").forEach(function (item) {
      item.classList.remove("hr-active");
    });
    mark.classList.add("hr-active");

    var el = popover();
    el.dataset.mode = "edit";
    el.querySelector(".hr-title").textContent = annotation.type === "comment" ? "Comment" : "Suggested edit";
    el.querySelector(".hr-meta").textContent = annotation.type === "comment"
      ? annotation.anchor.quote.exact
      : annotation.contentBefore + " -> " + annotation.contentAfter;
    el.querySelector("textarea").value = annotation.type === "comment" ? annotation.content : annotation.contentAfter;
    el.querySelector("textarea").placeholder = annotation.type === "comment" ? "Write a comment..." : "Replacement text...";
    el.querySelector(".hr-status").textContent = "Saved";
    configurePopoverActions(el, "edit", annotation.type);

    var rect = mark.getBoundingClientRect();
    el.style.display = "block";
    el.style.left = Math.max(8, Math.min(window.innerWidth - el.offsetWidth - 8, rect.left)) + "px";
    el.style.top = Math.max(8, Math.min(window.innerHeight - el.offsetHeight - 8, rect.bottom + 8)) + "px";
  }

  function hidePopover() {
    state.activeId = null;
    state.activeType = null;
    hideMobileReviewButton();
    document.querySelectorAll(".hr-active").forEach(function (item) {
      item.classList.remove("hr-active");
    });
    var el = document.querySelector(".hr-popover");
    if (el) el.style.display = "none";
  }

  function createExportDialog() {
    var backdrop = document.createElement("div");
    backdrop.className = "hr-backdrop";
    document.body.appendChild(backdrop);

    var dialog = document.createElement("div");
    dialog.className = "hr-export-dialog";
    dialog.innerHTML = [
      "<h2 style=\"margin:0 0 8px;font:700 18px/1.3 system-ui,-apple-system,Segoe UI,sans-serif;\">Review export</h2>",
      "<textarea readonly></textarea>",
      "<div class=\"hr-actions\">",
      "<button type=\"button\" data-hr-export=\"copy\">Copy</button>",
      "<button type=\"button\" data-hr-export=\"download\">Download</button>",
      "<button type=\"button\" data-hr-export=\"close\">Close</button>",
      "</div>"
    ].join("");
    document.body.appendChild(dialog);

    dialog.addEventListener("click", function (event) {
      var action = event.target && event.target.getAttribute("data-hr-export");
      if (!action) return;

      var text = dialog.querySelector("textarea").value;
      if (action === "close") hideExportDialog();
      if (action === "copy") navigator.clipboard.writeText(text);
      if (action === "download") {
        var blob = new Blob([text], { type: "application/json" });
        var link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = "html-review-" + new Date().toISOString().slice(0, 10) + ".json";
        link.click();
        URL.revokeObjectURL(link.href);
      }
    });

    backdrop.addEventListener("click", hideExportDialog);
  }

  function showExportDialog() {
    if (!document.querySelector(".hr-export-dialog")) createExportDialog();
    var text = JSON.stringify(exportAnnotations(), null, 2);
    document.querySelector(".hr-export-dialog textarea").value = text;
    document.querySelector(".hr-backdrop").style.display = "block";
    document.querySelector(".hr-export-dialog").style.display = "block";
  }

  function hideExportDialog() {
    var dialog = document.querySelector(".hr-export-dialog");
    var backdrop = document.querySelector(".hr-backdrop");
    if (dialog) dialog.style.display = "none";
    if (backdrop) backdrop.style.display = "none";
  }

  function isReviewUiTarget(target) {
    if (!target) return false;
    if (target.nodeType === 3) target = target.parentElement;
    if (!target || !target.closest) return false;
    return Boolean(
      target.closest(
        ".hr-popover,.hr-mobile-review,.hr-fixedbar,.hr-export-dialog,.hr-notes-rail,.hr-note"
      )
    );
  }

  function isEditableTarget(target) {
    if (!target) return false;
    if (target.nodeType === 3) target = target.parentElement;
    return Boolean(target && target.closest && target.closest("input, textarea, select, button, [contenteditable]"));
  }

  function isPrintableKey(event) {
    return event.key.length === 1 && !event.metaKey && !event.ctrlKey && !event.altKey;
  }

  function isPopoverVisible() {
    var el = document.querySelector(".hr-popover");
    return Boolean(el && el.style.display !== "none");
  }

  function bindEvents() {
    document.addEventListener("mouseup", function (event) {
      var t = eventTargetElement(event);
      if (isReviewUiTarget(t)) return;
      window.setTimeout(function () {
        var range = selectedRange();
        if (range) {
          state.activeRange = range;
          showMobileReviewButton(range);
        }
      }, 0);
    });

    document.addEventListener("touchend", function (event) {
      var t = eventTargetElement(event);
      if (isReviewUiTarget(t)) return;
      window.setTimeout(scheduleMobileSelectionButton, 0);
    });

    document.addEventListener("selectionchange", scheduleMobileSelectionButton);

    document.addEventListener("mousedown", function (event) {
      var t = eventTargetElement(event);
      if (isReviewUiTarget(t)) return;
      if (t && t.closest && t.closest("[" + MARK_ATTR + "]")) return;
      hidePopover();
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && isPopoverVisible()) {
        event.preventDefault();
        event.stopPropagation();
        hidePopover();
        return;
      }

      var keyT = eventTargetElement(event);
      if (isEditableTarget(keyT) || isReviewUiTarget(keyT)) return;

      var range = selectedRange();
      if (!range) return;
      state.activeRange = range;

      if (event.key === "Backspace" || event.key === "Delete") {
        event.preventDefault();
        createAnnotation("change", "");
        return;
      }

      if (isPrintableKey(event)) {
        event.preventDefault();
        showComposer(event.key);
      }
    });

    document.addEventListener("click", function (event) {
      var elt = eventTargetElement(event);

      var noteEl = elt && elt.closest(".hr-note[data-hr-note-for]");
      if (noteEl) {
        var nid = noteEl.getAttribute("data-hr-note-for");
        var marked = nid && document.querySelector(".hr-comment[" + MARK_ATTR + "='" + nid + "']");
        if (marked) {
          event.preventDefault();
          event.stopPropagation();
          showPopover(marked);
        }
        return;
      }

      var mark = elt && elt.closest("[" + MARK_ATTR + "]");
      if (mark) {
        event.preventDefault();
        event.stopPropagation();
        showPopover(mark);
      }
    });

    window.addEventListener("resize", function () {
      hidePopover();
      hideMobileReviewButton();
      scheduleReviewNotePositioning();
      syncNarrowRailChromeClass();
    });

    window.addEventListener("scroll", function () {
      hideMobileReviewButton();
      scheduleReviewNotePositioning();
    });
  }

  function init(options) {
    state.options = Object.assign({}, state.options, options || {});
    injectStyles();
    notesRail();
    state.annotations = loadAnnotations();
    if (state.options.autoRestore) restoreAnnotations();
    createFixedBar();
    bindEvents();
    return window.HTMLReview;
  }

  window.HTMLReview = {
    init: init,
    export: exportAnnotations,
    clear: function () {
      localStorage.removeItem(storageKey());
      document.querySelectorAll("[" + MARK_ATTR + "]").forEach(removeMarkElement);
      state.annotations = [];
      hideMobileReviewButton();
      hidePopover();
      var rail = document.getElementById(NOTES_RAIL_ID);
      if (rail) rail.innerHTML = "";
      syncNotesRailVisibilityClass();
    },
    annotations: function () {
      return state.annotations.slice();
    }
  };

  if (document.currentScript && document.currentScript.dataset.autoInit === "false") return;
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      init();
    });
  } else {
    init();
  }
})();
