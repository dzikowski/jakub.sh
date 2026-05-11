/*
 * html-review.js
 * Standalone, dependency-free review annotations for static HTML.
 */
(function () {
  "use strict";

  var STORAGE_PREFIX = "html-review:";
  var MARK_ATTR = "data-html-review-id";
  var ROOT_SKIP_SELECTOR = "script, style, textarea, input, select, option, button, [contenteditable], .hr-toolbar, .hr-popover, .hr-fixedbar, .hr-export-dialog";

  var state = {
    annotations: [],
    activeRange: null,
    activeId: null,
    activeType: null,
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

    var style = document.createElement("style");
    style.id = "html-review-styles";
    style.textContent = [
      ".hr-mark{cursor:pointer;border-radius:2px;padding:0 1px;}",
      ".hr-comment{position:relative;background:#fff7cc;border-bottom:2px solid #d69e2e;box-decoration-break:clone;-webkit-box-decoration-break:clone;}",
      ".hr-comment::after{content:attr(data-hr-note);position:absolute;left:calc(100% + 10px);top:-6px;width:220px;white-space:normal;background:#fffbeb;color:#713f12;border:1px solid #f2c94c;border-left:4px solid #d69e2e;border-radius:10px;padding:8px 10px;box-shadow:0 10px 24px rgba(120,53,15,.14);font:12px/1.35 system-ui,-apple-system,Segoe UI,sans-serif;z-index:2147483645;}",
      ".hr-comment[data-hr-note='']::after{content:'Comment';color:#92400e;font-style:italic;}",
      ".hr-change del{color:#b42318;background:#fee4e2;text-decoration:line-through;text-decoration-thickness:2px;}",
      ".hr-change ins{color:#067647;background:#dcfae6;text-decoration:none;margin-left:.2em;}",
      ".hr-mark.hr-active{outline:2px solid #2563eb;outline-offset:2px;}",
      ".hr-toolbar{position:fixed;z-index:2147483647;display:none;gap:6px;padding:8px;background:white;color:#111827;border:1px solid #d1d5db;border-radius:12px;box-shadow:0 18px 42px rgba(15,23,42,.18);font:13px/1.3 system-ui,-apple-system,Segoe UI,sans-serif;}",
      ".hr-toolbar button,.hr-popover button,.hr-export-dialog button{font:inherit;border:0;border-radius:7px;padding:6px 9px;cursor:pointer;background:#e5e7eb;color:#111827;}",
      ".hr-toolbar button{background:#f3f4f6;}",
      ".hr-toolbar button:hover,.hr-popover button:hover,.hr-export-dialog button:hover{filter:brightness(.95);}",
      ".hr-fixedbar{position:fixed;right:16px;bottom:16px;z-index:2147483646;display:flex;gap:8px;padding:8px;background:white;border:1px solid #d1d5db;border-radius:12px;box-shadow:0 12px 32px rgba(15,23,42,.18);font:13px/1.3 system-ui,-apple-system,Segoe UI,sans-serif;}",
      ".hr-fixedbar button{font:inherit;border:0;border-radius:8px;padding:7px 10px;cursor:pointer;background:#111827;color:white;}",
      ".hr-fixedbar button.hr-secondary{background:#f3f4f6;color:#111827;}",
      ".hr-popover{position:fixed;z-index:2147483647;width:min(360px,calc(100vw - 24px));display:none;background:white;color:#111827;border:1px solid #d1d5db;border-radius:12px;box-shadow:0 18px 42px rgba(15,23,42,.24);padding:12px;font:13px/1.45 system-ui,-apple-system,Segoe UI,sans-serif;}",
      ".hr-popover textarea{width:100%;box-sizing:border-box;min-height:86px;margin:8px 0;border:1px solid #d1d5db;border-radius:8px;padding:8px;font:inherit;}",
      ".hr-popover .hr-title{font-weight:700;margin-bottom:4px;}",
      ".hr-popover .hr-meta{color:#6b7280;font-size:12px;margin-bottom:8px;}",
      ".hr-popover .hr-status{color:#6b7280;font-size:12px;min-height:16px;margin-top:-2px;margin-bottom:8px;}",
      ".hr-popover .hr-actions{display:flex;gap:8px;justify-content:flex-end;}",
      ".hr-popover .hr-primary{background:#111827;color:white;}",
      ".hr-popover .hr-danger{background:#fee2e2;color:#991b1b;}",
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
    var text = root.textContent || "";
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
      occurrence: occurrenceFor(root.textContent || "", quote.exact, start),
      quote: quote
    };
  }

  function rangeFromAnchor(anchor) {
    var root = document.querySelector(anchor.cssPath);
    if (!root) return null;

    var text = root.textContent || "";
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

  function wrapRange(range, annotation) {
    var span = document.createElement("span");
    span.className = "hr-mark " + (annotation.type === "change" ? "hr-change" : "hr-comment");
    span.setAttribute(MARK_ATTR, annotation.id);
    span.title = annotation.type === "comment" ? annotation.content : "Suggested change";
    if (annotation.type === "comment") span.setAttribute("data-hr-note", annotation.content || "");

    if (annotation.type === "change") {
      var del = document.createElement("del");
      del.appendChild(range.extractContents());
      span.appendChild(del);

      if (annotation.contentAfter) {
        var ins = document.createElement("ins");
        ins.textContent = annotation.contentAfter;
        span.appendChild(ins);
      }
      range.insertNode(span);
      return span;
    }

    span.appendChild(range.extractContents());
    range.insertNode(span);
    return span;
  }

  function applyAnnotation(annotation) {
    if (document.querySelector("[" + MARK_ATTR + "='" + annotation.id + "']")) return;
    var range = rangeFromAnchor(annotation.anchor);
    if (!range) return;
    wrapRange(range, annotation);
  }

  function restoreAnnotations() {
    state.annotations.forEach(applyAnnotation);
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

    while (mark.firstChild) parent.insertBefore(mark.firstChild, mark);
    parent.removeChild(mark);
    parent.normalize();
  }

  function removeAnnotation(id) {
    var mark = document.querySelector("[" + MARK_ATTR + "='" + id + "']");
    removeMarkElement(mark);
    state.annotations = state.annotations.filter(function (item) {
      return item.id !== id;
    });
    saveAnnotations();
    hidePopover();
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

    wrapRange(range, annotation);
    state.annotations.push(annotation);
    saveAnnotations();
    state.activeRange = null;
    clearSelection();
    hideToolbar();
    return annotation;
  }

  function updateAnnotationContent(annotation, value) {
    annotation.updatedAt = new Date().toISOString();

    if (annotation.type === "comment") {
      annotation.content = value;
      var mark = document.querySelector("[" + MARK_ATTR + "='" + annotation.id + "']");
      if (mark) {
        mark.title = value;
        mark.setAttribute("data-hr-note", value || "");
      }
    } else {
      annotation.contentAfter = value;
      var ins = document.querySelector("[" + MARK_ATTR + "='" + annotation.id + "'] ins");
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

  function createToolbar() {
    var toolbar = document.createElement("div");
    toolbar.className = "hr-toolbar";
    toolbar.innerHTML = [
      "<button type=\"button\" data-hr-action=\"comment\">Comment</button>",
      "<button type=\"button\" data-hr-action=\"change\">Suggest edit</button>"
    ].join("");
    document.body.appendChild(toolbar);

    toolbar.addEventListener("click", function (event) {
      var action = event.target && event.target.getAttribute("data-hr-action");
      if (!action) return;

      if (action === "comment" || action === "change") showComposer(action);
    });

    return toolbar;
  }

  function toolbar() {
    return document.querySelector(".hr-toolbar") || createToolbar();
  }

  function showToolbar(range) {
    state.activeRange = range;
    var rect = range.getBoundingClientRect();
    var el = toolbar();
    el.style.display = "flex";
    el.style.left = Math.max(8, Math.min(window.innerWidth - el.offsetWidth - 8, rect.left + rect.width / 2 - el.offsetWidth / 2)) + "px";
    el.style.top = Math.max(8, rect.top - el.offsetHeight - 10) + "px";
  }

  function hideToolbar() {
    var el = document.querySelector(".hr-toolbar");
    if (el) el.style.display = "none";
  }

  function positionPopoverForRange(range, el) {
    var rect = range.getBoundingClientRect();
    el.style.left = Math.max(8, Math.min(window.innerWidth - el.offsetWidth - 8, rect.left)) + "px";
    el.style.top = Math.max(8, Math.min(window.innerHeight - el.offsetHeight - 8, rect.bottom + 8)) + "px";
  }

  function createFixedBar() {
    var bar = document.createElement("div");
    bar.className = "hr-fixedbar";
    bar.innerHTML = [
      "<button type=\"button\" data-hr-fixed=\"export\">Export review JSON</button>",
      "<button type=\"button\" class=\"hr-secondary\" data-hr-fixed=\"clear\">Clear page</button>"
    ].join("");
    document.body.appendChild(bar);

    bar.addEventListener("click", function (event) {
      var action = event.target && event.target.getAttribute("data-hr-fixed");
      if (action === "export") showExportDialog();
      if (action === "clear" && window.confirm("Remove all saved review annotations for this page?")) {
        localStorage.removeItem(storageKey());
        location.reload();
      }
    });
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
      "<button type=\"button\" class=\"hr-danger\" data-hr-popover=\"remove\">Delete</button>",
      "<button type=\"button\" class=\"hr-primary\" data-hr-popover=\"add\">Add</button>",
      "<button type=\"button\" data-hr-popover=\"cancel\">Cancel</button>",
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

    popover.addEventListener("click", function (event) {
      var action = event.target && event.target.getAttribute("data-hr-popover");
      if (!action) return;

      if (action === "cancel") {
        hidePopover();
        return;
      }

      if (action === "add") {
        createAnnotation(state.activeType, popover.querySelector("textarea").value);
        hidePopover();
        return;
      }

      if (action === "remove") {
        var annotation = annotationById(state.activeId);
        if (annotation) removeAnnotation(annotation.id);
      }
    });

    return popover;
  }

  function popover() {
    return document.querySelector(".hr-popover") || createPopover();
  }

  function configurePopoverActions(el, mode, type) {
    var removeButton = el.querySelector("[data-hr-popover='remove']");
    var addButton = el.querySelector("[data-hr-popover='add']");
    var cancelButton = el.querySelector("[data-hr-popover='cancel']");

    removeButton.style.display = mode === "edit" ? "" : "none";
    addButton.style.display = mode === "create" ? "" : "none";
    addButton.textContent = type === "comment" ? "Add comment" : "Add edit";
    removeButton.textContent = type === "change" ? "Undo" : "Delete";
    cancelButton.textContent = "Cancel";
  }

  function showComposer(type) {
    var range = state.activeRange || selectedRange();
    if (!range) return;

    state.activeId = null;
    state.activeType = type;
    hideToolbar();

    var el = popover();
    el.dataset.mode = "create";
    el.querySelector(".hr-title").textContent = type === "comment" ? "Add comment" : "Suggest edit";
    el.querySelector(".hr-meta").textContent = range.toString();
    el.querySelector("textarea").value = "";
    el.querySelector("textarea").placeholder = type === "comment" ? "Write a comment..." : "Replacement text...";
    el.querySelector(".hr-status").textContent = "";
    configurePopoverActions(el, "create", type);

    el.style.display = "block";
    positionPopoverForRange(range, el);
    el.querySelector("textarea").focus();
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

  function bindEvents() {
    document.addEventListener("mouseup", function (event) {
      if (event.target && event.target.closest(".hr-toolbar,.hr-popover,.hr-fixedbar,.hr-export-dialog")) return;
      window.setTimeout(function () {
        var range = selectedRange();
        if (range) showToolbar(range);
      }, 0);
    });

    document.addEventListener("mousedown", function (event) {
      if (event.target && event.target.closest(".hr-toolbar,.hr-popover,.hr-fixedbar,.hr-export-dialog")) return;
      hideToolbar();
      hidePopover();
    });

    document.addEventListener("click", function (event) {
      var mark = event.target && event.target.closest("[" + MARK_ATTR + "]");
      if (mark) {
        event.preventDefault();
        event.stopPropagation();
        showPopover(mark);
      }
    });

    window.addEventListener("resize", function () {
      hideToolbar();
      hidePopover();
    });
  }

  function init(options) {
    state.options = Object.assign({}, state.options, options || {});
    injectStyles();
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
      hideToolbar();
      hidePopover();
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
