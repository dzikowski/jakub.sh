# html-review

`html-review` is a standalone browser script that adds lightweight review markup to any HTML page.

Use it when a coding agent gives you an HTML response, design mockup, or generated page and you want to mark changes directly in the browser, then export those edits back to the agent as structured JSON.

## Quick start

Embed the script in any HTML page:

```html
<script src="https://jakub.sh/html-review/html-review.js"></script>
```

Or, for local testing inside this repository:

```html
<script src="./html-review.js"></script>
```

Then open the page in a browser:

1. Select text.
2. Choose `Comment` or `Suggest edit`.
3. Write the comment or replacement in the in-place popover.
4. Click an existing highlight to edit it; existing edits save immediately as you type.
5. Use `Export review JSON` to copy or download all annotations for the page.

Annotations are stored in `localStorage` per origin and path, so each page gets its own review state.

## Demo

Open:

```text
https://jakub.sh/html-review/demo.html
```

## Export format

Exports are one page object plus an `entries` array. Comments use `content`; suggested edits use `contentBefore` and `contentAfter`.

```json
{
  "page": {
    "url": "https://example.com/design.html",
    "title": "Landing page"
  },
  "entries": [
    {
      "id": "hr_lf9k2n_abc123",
      "type": "change",
      "cssPath": "body > main > section:nth-of-type(1) > p",
      "occurrence": 0,
      "quote": {
        "exact": "selected original text",
        "prefix": "text before the selection",
        "suffix": "text after the selection"
      }
      },
      "contentBefore": "selected original text",
      "contentAfter": "replacement text",
      "createdAt": "2026-05-11T16:00:00.000Z",
      "updatedAt": "2026-05-11T16:00:00.000Z"
    }
  ]
}
```

The primary locator is the `quote` selector plus `occurrence`; `cssPath` narrows the search area. This is more useful for agent handoff than XPath because generated HTML often changes structure between revisions.

## Agent prompt

You can ask an agent to include the script while it produces HTML:

```text
Produce a standalone HTML file and include:
<script src="https://jakub.sh/html-review/html-review.js"></script>

The page should remain usable without build tools. I will export review JSON from html-review and send it back for revisions.
```

When sending exported review back:

```text
Apply these HTML review annotations. Treat `comment` as requested feedback and `change` as a concrete text replacement. Use `quote` plus `occurrence` first; use `cssPath` only to narrow the search area.

[paste JSON here]
```

## Browser extension usage

For extension or bookmarklet workflows, inject the same file into the current page:

```js
const script = document.createElement("script");
script.src = "https://jakub.sh/html-review/html-review.js";
document.documentElement.appendChild(script);
```

## API

Auto-initialization is enabled by default. To control initialization yourself:

```html
<script src="https://jakub.sh/html-review/html-review.js" data-auto-init="false"></script>
<script>
  HTMLReview.init({
    storageKey: "custom-review-key"
  });
</script>
```

Available methods:

- `HTMLReview.init(options)` starts the UI.
- `HTMLReview.export()` returns `{ page, entries }`.
- `HTMLReview.annotations()` returns a copy of saved annotations.
- `HTMLReview.clear()` clears storage for the active page key.

## Limits

This is a lightweight static-page review tool, not a full collaborative editor.

- It works best on stable, rendered HTML, not heavily mutating apps.
- It stores data only in the browser where the review was made.
- Overlapping annotations and complex selections across many nested elements can be fragile.
- Exported review JSON is designed for agent handoff, not as a permanent document format.
