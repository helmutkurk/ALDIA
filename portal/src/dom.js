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
