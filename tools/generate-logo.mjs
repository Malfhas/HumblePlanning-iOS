// Draws the Humble Planning mark from the shapes of the logo (same coordinates as tools/generate-logo.mjs
// of the Android app): the Liquid Glass app icon (Icon Composer format, one glass layer per link) and the
// vector mark used in the app. `node tools/generate-logo.mjs`
import { mkdirSync, writeFileSync } from 'node:fs';

// Outline of the two interlocked links, in the coordinates of the logo bitmap
const LINK_RIGHT = [[1504,67],[1755,0],[1755,417],[1385,516],[1385,277],[1285,304],[1285,757],[1216,775],[1216,251],[1454,188],[1454,426],[1686,364],[1686,90],[1573,120],[1573,573],[1504,591]];
const LINK_LEFT = [[820,464],[1165,372],[1165,610],[1504,521],[1504,591],[1096,700],[1096,462],[889,517],[889,792],[1216,705],[1216,775],[820,881]];
// Where one strand passes under the other: a soft shadow gives the interlocking
const SHADOWS = [
  { points: [[1216,490],[1285,472],[1285,579],[1216,597]], from: [1250,490], to: [1250,590] },
  { points: [[1504,306],[1573,288],[1573,394],[1504,412]], from: [1538,306], to: [1538,405] },
  { points: [[1216,668],[1285,650],[1285,700],[1216,705]], from: [1250,700], to: [1250,650] },
  { points: [[1504,484],[1573,465],[1573,520],[1504,521]], from: [1538,520], to: [1538,465] },
];
const BOUNDS = { x: 820, y: 0, width: 935, height: 881 };
const VIOLET_DEEP = '#5A17FF';
const VIOLET_LIGHT = '#CF9BFF';

const place = (size, inner) => {
  const scale = inner / Math.max(BOUNDS.width, BOUNDS.height);
  const dx = (size - BOUNDS.width * scale) / 2;
  const dy = (size - BOUNDS.height * scale) / 2;
  return ([x, y]) => [+(dx + (x - BOUNDS.x) * scale).toFixed(2), +(dy + (y - BOUNDS.y) * scale).toFixed(2)];
};
const path = (points, at) => 'M' + points.map(at).map(([x, y]) => `${x},${y}`).join('L') + 'Z';

function svg(size, inner, links, { shadows = false } = {}) {
  const at = place(size, inner);
  const [sx, sy] = at([BOUNDS.x, BOUNDS.y + BOUNDS.height]);
  const [ex, ey] = at([BOUNDS.x + BOUNDS.width, BOUNDS.y]);
  let defs = `<linearGradient id="brand" gradientUnits="userSpaceOnUse" x1="${sx}" y1="${sy}" x2="${ex}" y2="${ey}"><stop offset="0" stop-color="${VIOLET_DEEP}"/><stop offset="1" stop-color="${VIOLET_LIGHT}"/></linearGradient>`;
  let body = links.map((link) => `<path fill="url(#brand)" d="${path(link, at)}"/>`).join('');
  if (shadows) {
    SHADOWS.forEach((shadow, i) => {
      const [x1, y1] = at(shadow.from);
      const [x2, y2] = at(shadow.to);
      defs += `<linearGradient id="s${i}" gradientUnits="userSpaceOnUse" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"><stop offset="0" stop-color="#230A6E" stop-opacity="0"/><stop offset="1" stop-color="#230A6E" stop-opacity="0.6"/></linearGradient>`;
      body += `<path fill="url(#s${i})" d="${path(shadow.points, at)}"/>`;
    });
  }
  return `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 ${size} ${size}"><defs>${defs}</defs>${body}</svg>\n`;
}

const resources = new URL('../HumblePlanning/Resources/', import.meta.url);

// App icon: 1024 pt canvas, white like the Android launcher; the system derives the dark, clear and tinted looks
const icon = new URL('AppIcon.icon/', resources);
mkdirSync(new URL('Assets/', icon), { recursive: true });
writeFileSync(new URL('Assets/link-right.svg', icon), svg(1024, 600, [LINK_RIGHT]));
writeFileSync(new URL('Assets/link-left.svg', icon), svg(1024, 600, [LINK_LEFT]));
const json = {
  fill: { solid: 'srgb:1.00000,1.00000,1.00000,1.00000' },
  groups: [
    {
      layers: [
        { glass: true, 'image-name': 'link-right.svg', name: 'link-right' },
        { glass: true, 'image-name': 'link-left.svg', name: 'link-left' },
      ],
      shadow: { kind: 'layer-color', opacity: 0.5 },
      translucency: { enabled: true, value: 0.3 },
    },
  ],
  'supported-platforms': { squares: 'shared' },
};
writeFileSync(new URL('icon.json', icon), JSON.stringify(json, null, 2).replace(/^(\s*"[^"]*"):/gm, '$1 :') + '\n');

// The mark shown in the app (sign-in, about), as a vector image
const mark = new URL('Assets.xcassets/LogoMark.imageset/', resources);
mkdirSync(mark, { recursive: true });
writeFileSync(new URL('LogoMark.svg', mark), svg(96, 96, [LINK_RIGHT, LINK_LEFT], { shadows: true }));
writeFileSync(new URL('Contents.json', mark), JSON.stringify({
  images: [{ filename: 'LogoMark.svg', idiom: 'universal' }],
  info: { author: 'xcode', version: 1 },
  properties: { 'preserves-vector-representation': true },
}, null, 2) + '\n');
console.log('logo written');
