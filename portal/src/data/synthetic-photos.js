// Synthetic "photos" for the demo: small SVG drawings, clearly labelled. No real photos of
// streets or people are used until the backend blurs faces and plates before storage.

const LABEL = "Foto sintética";

function frame(body, caption) {
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 220">
<rect width="320" height="220" fill="#8d959c"/>
<rect y="120" width="320" height="100" fill="#6b7277"/>
${body}
<rect x="8" y="190" width="304" height="22" rx="4" fill="rgba(0,0,0,.55)"/>
<text x="16" y="205" font-family="Arial, sans-serif" font-size="12" fill="#fff">${LABEL} · ${caption}</text>
</svg>`;
  return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(svg)}`;
}

const BROKEN = {
  pothole: '<ellipse cx="160" cy="160" rx="70" ry="22" fill="#2b2f31"/><ellipse cx="160" cy="157" rx="52" ry="14" fill="#1c1f20"/>',
  sidewalk:
    '<rect x="20" y="105" width="280" height="30" fill="#b9bdc0"/><path d="M120 105l20 15-15 15M200 105l-10 30" stroke="#3a3f42" stroke-width="4" fill="none"/>',
  ramp: '<rect x="20" y="110" width="280" height="25" fill="#b9bdc0"/><path d="M110 135l40-25h60" fill="#a3a8ab"/><rect x="140" y="85" width="40" height="40" fill="#5b4a3a"/>',
  street_light:
    '<rect x="150" y="20" width="10" height="150" fill="#3b4246"/><rect x="150" y="20" width="60" height="8" fill="#3b4246"/><ellipse cx="208" cy="34" rx="16" ry="8" fill="#555"/>',
  drain_cover: '<ellipse cx="160" cy="160" rx="45" ry="18" fill="#111"/><ellipse cx="160" cy="160" rx="36" ry="12" fill="#000"/>',
  signage:
    '<rect x="155" y="40" width="8" height="130" fill="#3b4246" transform="rotate(12 159 105)"/><polygon points="130,40 190,40 160,90" fill="#c9a227" transform="rotate(12 159 105)"/>',
};

const FIXED = {
  pothole: '<ellipse cx="160" cy="160" rx="70" ry="22" fill="#5d6468"/>',
  sidewalk: '<rect x="20" y="105" width="280" height="30" fill="#c9cdd0"/>',
  ramp: '<rect x="20" y="110" width="280" height="25" fill="#c9cdd0"/><path d="M110 135l40-25h60" fill="#b5babd"/>',
  street_light:
    '<rect x="150" y="20" width="10" height="150" fill="#3b4246"/><rect x="150" y="20" width="60" height="8" fill="#3b4246"/><ellipse cx="208" cy="34" rx="16" ry="8" fill="#ffe27a"/><circle cx="208" cy="40" r="30" fill="#ffe27a" opacity=".35"/>',
  drain_cover: '<ellipse cx="160" cy="160" rx="45" ry="18" fill="#4a4f52"/><path d="M125 160h70M160 145v30" stroke="#2f3335" stroke-width="3"/>',
  signage:
    '<rect x="155" y="40" width="8" height="130" fill="#3b4246"/><polygon points="130,40 190,40 160,90" fill="#e8c033"/>',
};

export function syntheticPhoto(category, { after = false } = {}) {
  const body = (after ? FIXED : BROKEN)[category] ?? BROKEN.pothole;
  return frame(body, after ? "después" : "antes");
}
