// engine.js
// Custom Marp engine with line highlighting support
// Usage: marp --engine engine.js --theme theme.css file.md

const { readFileSync } = require("node:fs");
const { join } = require("node:path");

const fonts = new Map(
  ["JetBrainsMono-Regular.woff2", "JetBrainsMono-Bold.woff2"].map((name) => [
    name,
    readFileSync(join(__dirname, "fonts", name)).toString("base64"),
  ]),
);

// Top-level await keeps the PDF export waiting until the diagrams are rendered
// Alternative to mermaid, use https://pele.run/
const mermaidScript = `<script type="module">
import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs';
mermaid.initialize({
  startOnLoad: false,
  theme: 'neutral',
  fontFamily: 'Montserrat, sans-serif',
  flowchart: { htmlLabels: false },
  htmlLabels: false
});
await document.fonts.load('16px Montserrat');
const bodyChildren = new Set(document.body.children);
await mermaid.run({ querySelector: 'div.mermaid' });
// Mermaid leaves helper elements in <body>; in a PDF they become an empty last page
[...document.body.children]
  .filter(element => !bodyChildren.has(element))
  .forEach(element => element.remove());
</script>`;

const escapeHtml = (text) =>
  text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

module.exports = ({ marp }) =>
  marp
    .use(({ marpit }) => {
      const { renderStyle } = marpit;

      // Inlined theme URLs otherwise resolve relative to the deck, not the CSS.
      marpit.renderStyle = function (...args) {
        return renderStyle
          .apply(this, args)
          .replace(
            /url\((["']?)fonts\/(JetBrainsMono-(?:Regular|Bold)\.woff2)\1\)/g,
            (_match, _quote, name) =>
              `url("data:font/woff2;base64,${fonts.get(name)}")`,
          );
      };
    })
    .use(({ marpit }) => {
      // Render ```mermaid fences as diagrams instead of code
      const { fence } = marpit.markdown.renderer.rules;

      marpit.markdown.renderer.rules.fence = (
        tokens,
        idx,
        options,
        env,
        self,
      ) => {
        const token = tokens[idx];

        if (token.info.trim().split(/\s+/)[0] !== "mermaid") {
          return fence(tokens, idx, options, env, self);
        }

        const script = env.mermaidScriptAdded ? "" : mermaidScript;
        env.mermaidScriptAdded = true;

        const diagram = escapeHtml(token.content);

        return `<div class="mermaid">${diagram}</div>${script}`;
      };
    })
    .use(({ marpit }) => {
      const { highlighter } = marpit;

      marpit.highlighter = function (code, lang, attrs) {
        const original = highlighter.call(this, code, lang, attrs);
        const rendered = original || escapeHtml(code);

        // Parse code highlight from {line-numbers} syntax
        // Examples: {4}, {4-8}, {1,3,5}, {1-3,5,7-9}
        const matched = attrs.toString().match(/{([\d,-]+)}/);
        const lineNumbers = matched?.[1]
          .split(",")
          .map((v) => v.split("-").map((v) => parseInt(v, 10)));

        // Apply line numbers and highlighting
        const listItems = rendered
          .split(/\n(?!$)/) // Don't split at the trailing newline
          .map((line, index) => {
            const lineNum = index + 1;

            const highlighted = lineNumbers?.find(([start, end]) => {
              if (end != null && start <= lineNum && lineNum <= end)
                return true;
              return start === lineNum;
            });

            return `<li${
              highlighted ? ' class="highlighted-line"' : ""
            }><span data-marp-line-number></span><span>${line}</span></li>`;
          });

        return `<ol>${listItems.join("")}</ol>`;
      };
    });
