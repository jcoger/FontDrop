/**
 * Parse, sanitize, and normalize an SVG string for safe inline rendering.
 *
 * - Removes <script> elements and on* event attributes
 * - Synthesizes a viewBox from width/height if absent so the SVG scales correctly
 * - Removes fixed width/height and sets CSS height:100%; width:auto so the
 *   consumer can control size via the container element's height
 */
export function parseSvg(raw: string): string | null {
  const parser = new DOMParser();
  const doc = parser.parseFromString(raw, "image/svg+xml");

  // DOMParser signals a parse error via a <parsererror> element
  if (doc.querySelector("parsererror")) return null;

  const svg = doc.querySelector("svg");
  if (!svg) return null;

  // Remove scripts
  svg.querySelectorAll("script").forEach((el) => el.remove());

  // Strip event handler attributes from every element
  svg.querySelectorAll("*").forEach((el) => {
    for (const attr of Array.from(el.attributes)) {
      if (attr.name.startsWith("on")) el.removeAttribute(attr.name);
    }
  });

  // Normalize fills/strokes to currentColor so the container's CSS `color`
  // property drives the SVG color (single-color logo support).
  const normalizeFillStroke = (el: Element) => {
    const fill = el.getAttribute("fill");
    if (fill && fill !== "none" && fill !== "currentColor") {
      el.setAttribute("fill", "currentColor");
    }
    const stroke = el.getAttribute("stroke");
    if (stroke && stroke !== "none" && stroke !== "currentColor") {
      el.setAttribute("stroke", "currentColor");
    }
  };
  normalizeFillStroke(svg);
  svg.querySelectorAll("*").forEach(normalizeFillStroke);
  // If root has no fill attribute, default to currentColor so all children inherit it
  if (!svg.hasAttribute("fill")) {
    svg.setAttribute("fill", "currentColor");
  }

  // Synthesize viewBox before stripping dimensions so the SVG remains scalable
  if (!svg.hasAttribute("viewBox")) {
    const w = parseFloat(svg.getAttribute("width") ?? "");
    const h = parseFloat(svg.getAttribute("height") ?? "");
    if (w > 0 && h > 0) svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
  }

  svg.removeAttribute("width");
  svg.removeAttribute("height");

  // These inline styles let the container's height drive the rendered size
  svg.style.height = "100%";
  svg.style.width = "auto";
  svg.style.display = "block";

  return svg.outerHTML;
}
