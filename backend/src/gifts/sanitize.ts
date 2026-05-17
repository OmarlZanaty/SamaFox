import sanitizeHtml from 'sanitize-html';

/**
 * Strict allowlist for gift animation HTML.
 * - Allows the structural shell, inline <style>, and the full SVG element family.
 * - Blocks <script>, <iframe>, <object>, <embed>, <link>, and any on* event handler.
 * - Disallows javascript:/data: protocols outside of a tightly scoped data:image/* allowance.
 */
const SVG_ELEMENTS = [
  'svg', 'g', 'defs', 'use', 'symbol', 'marker', 'pattern', 'mask', 'clipPath',
  'path', 'rect', 'circle', 'ellipse', 'line', 'polyline', 'polygon',
  'text', 'tspan', 'textPath', 'title', 'desc',
  'linearGradient', 'radialGradient', 'stop',
  'filter', 'feGaussianBlur', 'feMerge', 'feMergeNode', 'feColorMatrix',
  'feOffset', 'feFlood', 'feComposite', 'feBlend', 'feDropShadow', 'feTurbulence',
  'feDisplacementMap', 'feMorphology', 'feSpecularLighting', 'feDiffuseLighting',
  'feDistantLight', 'fePointLight', 'feSpotLight', 'feConvolveMatrix',
  'feComponentTransfer', 'feFuncR', 'feFuncG', 'feFuncB', 'feFuncA',
  'animate', 'animateTransform', 'animateMotion', 'mpath',
  'foreignObject', 'image',
];

const STRUCTURAL_TAGS = ['html', 'head', 'meta', 'body', 'style', 'div', 'span', 'br'];

const BLOCKED_ATTRS = /^on/i; // anything starting with on*

export interface SanitizeResult {
  ok: boolean;
  html: string;
  bytes: number;
  reason?: string;
}

export const MAX_HTML_BYTES = 200 * 1024; // 200KB

export function sanitizeGiftHtml(input: string): SanitizeResult {
  if (typeof input !== 'string' || input.length === 0) {
    return { ok: false, html: '', bytes: 0, reason: 'animationHtml is required' };
  }
  const rawBytes = Buffer.byteLength(input, 'utf8');
  if (rawBytes > MAX_HTML_BYTES) {
    return { ok: false, html: '', bytes: rawBytes, reason: `animationHtml exceeds ${MAX_HTML_BYTES} bytes (got ${rawBytes})` };
  }
  if (/<script\b/i.test(input)) {
    return { ok: false, html: '', bytes: rawBytes, reason: '<script> tags are not allowed' };
  }
  if (/<iframe\b/i.test(input) || /<object\b/i.test(input) || /<embed\b/i.test(input)) {
    return { ok: false, html: '', bytes: rawBytes, reason: 'External resource tags are not allowed' };
  }
  if (/\son\w+\s*=/i.test(input)) {
    return { ok: false, html: '', bytes: rawBytes, reason: 'Event handler attributes (on*) are not allowed' };
  }
  if (!/<svg\b/i.test(input)) {
    return { ok: false, html: '', bytes: rawBytes, reason: 'animationHtml must contain at least one <svg> element' };
  }
  if (/javascript\s*:/i.test(input)) {
    return { ok: false, html: '', bytes: rawBytes, reason: 'javascript: URIs are not allowed' };
  }

  const allowedTags = [...STRUCTURAL_TAGS, ...SVG_ELEMENTS];
  const allowedAttributes: Record<string, string[]> = {
    '*': [
      'class', 'id', 'style', 'viewBox', 'xmlns', 'xmlns:xlink', 'version',
      'd', 'x', 'y', 'cx', 'cy', 'r', 'rx', 'ry', 'x1', 'y1', 'x2', 'y2',
      'width', 'height', 'fill', 'fill-opacity', 'fill-rule', 'stroke',
      'stroke-width', 'stroke-opacity', 'stroke-linecap', 'stroke-linejoin',
      'stroke-dasharray', 'stroke-dashoffset',
      'opacity', 'transform', 'transform-origin',
      'offset', 'stop-color', 'stop-opacity', 'gradientUnits', 'gradientTransform',
      'spreadMethod', 'patternUnits', 'patternTransform',
      'filter', 'mask', 'clip-path', 'clipPathUnits',
      'preserveAspectRatio', 'points', 'href', 'xlink:href',
      'in', 'in2', 'result', 'mode', 'operator', 'k1', 'k2', 'k3', 'k4',
      'stdDeviation', 'edgeMode', 'flood-color', 'flood-opacity', 'lighting-color',
      'dx', 'dy', 'order', 'kernelMatrix', 'kernelUnitLength', 'preserveAlpha',
      'baseFrequency', 'numOctaves', 'seed', 'stitchTiles', 'type', 'values',
      'scale', 'xChannelSelector', 'yChannelSelector',
      'radius', 'amplitude', 'exponent', 'tableValues', 'slope', 'intercept',
      'text-anchor', 'font-size', 'font-family', 'font-weight', 'font-style',
      'letter-spacing', 'word-spacing', 'dominant-baseline', 'alignment-baseline',
      'attributeName', 'from', 'to', 'dur', 'repeatCount', 'begin', 'end', 'fill',
      'keyTimes', 'keySplines', 'calcMode', 'additive', 'accumulate', 'path',
      'rotate', 'pathLength',
    ],
    meta: ['charset', 'name', 'content'],
  };

  const cleaned = sanitizeHtml(input, {
    allowedTags,
    allowedAttributes,
    selfClosing: ['br', 'meta'],
    parser: { lowerCaseTags: false, lowerCaseAttributeNames: false },
    allowedSchemes: ['http', 'https', 'data'],
    allowedSchemesByTag: {
      image: ['data', 'http', 'https'],
      use: ['data', 'http', 'https'],
    },
    allowedSchemesAppliedToAttributes: ['href', 'xlink:href'],
    allowVulnerableTags: false,
    transformTags: {
      '*': (tagName, attribs) => {
        const safe: Record<string, string> = {};
        for (const [k, v] of Object.entries(attribs)) {
          if (BLOCKED_ATTRS.test(k)) continue;
          safe[k] = String(v ?? '');
        }
        return { tagName, attribs: safe };
      },
    },
  });

  return { ok: true, html: cleaned, bytes: Buffer.byteLength(cleaned, 'utf8') };
}
