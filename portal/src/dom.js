/** DOM creation always assigns textContent; no HTML from the API is interpreted.
 * @param {string} tag @param {string} [className] @param {string} [text]
 * @returns {HTMLElement}
 */
export function element(tag, className = '', text = '') {
  const node = document.createElement(tag);
  node.className = className;
  node.textContent = text;
  return node;
}

/** SVG creation with explicit attributes, shared by the chart renderers.
 * @template {keyof SVGElementTagNameMap} T
 * @param {T} tag @param {Record<string, string|number>} [attributes]
 * @returns {SVGElementTagNameMap[T]}
 */
export function svgElement(tag, attributes = {}) {
  const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (const [key, value] of Object.entries(attributes))
    node.setAttribute(key, String(value));
  return node;
}
