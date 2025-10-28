// Color conversion from OKLCH to HEX
// Using culori library for accurate color space conversion

const colors = {
  "base-100": "oklch(13% 0.028 261.692)",
  "base-200": "oklch(21% 0.034 264.665)",
  "base-300": "oklch(27% 0.033 256.848)",
  "base-content": "oklch(96% 0.003 264.542)",
  "primary": "oklch(76% 0.177 163.223)",
  "primary-content": "oklch(26% 0.051 172.552)",
  "secondary": "oklch(60% 0.126 221.723)",
  "secondary-content": "oklch(13.955% 0.027 168.327)",
  "accent": "oklch(70% 0.183 293.541)",
  "accent-content": "oklch(14.125% 0.023 185.713)",
  "neutral": "oklch(37% 0.034 259.733)",
  "neutral-content": "oklch(96% 0.003 264.542)",
  "info": "oklch(72.06% 0.191 231.6)",
  "info-content": "oklch(0% 0 0)",
  "success": "oklch(84% 0.238 128.85)",
  "success-content": "oklch(0% 0 0)",
  "warning": "oklch(84.71% 0.199 83.87)",
  "warning-content": "oklch(0% 0 0)",
  "error": "oklch(71.76% 0.221 22.18)",
  "error-content": "oklch(0% 0 0)",
};

// Manual OKLCH to RGB conversion
function oklchToRgb(l, c, h) {
  // Convert OKLCH to OKLAB
  const aLab = c * Math.cos((h * Math.PI) / 180);
  const bLab = c * Math.sin((h * Math.PI) / 180);

  // Convert OKLAB to linear RGB
  const l_ = l + 0.3963377774 * aLab + 0.2158037573 * bLab;
  const m_ = l - 0.1055613458 * aLab - 0.0638541728 * bLab;
  const s_ = l - 0.0894841775 * aLab - 1.2914855480 * bLab;

  const l3 = l_ * l_ * l_;
  const m3 = m_ * m_ * m_;
  const s3 = s_ * s_ * s_;

  const r_linear = +4.0767416621 * l3 - 3.3077115913 * m3 + 0.2309699292 * s3;
  const g_linear = -1.2684380046 * l3 + 2.6097574011 * m3 - 0.3413193965 * s3;
  const b_linear = -0.0041960863 * l3 - 0.7034186147 * m3 + 1.7076147010 * s3;

  // Apply gamma correction (sRGB)
  const gammaCorrect = (val) => {
    if (val <= 0.0031308) {
      return 12.92 * val;
    }
    return 1.055 * Math.pow(val, 1 / 2.4) - 0.055;
  };

  let r = gammaCorrect(r_linear);
  let g = gammaCorrect(g_linear);
  let b = gammaCorrect(b_linear);

  // Clamp to [0, 1]
  r = Math.max(0, Math.min(1, r));
  g = Math.max(0, Math.min(1, g));
  b = Math.max(0, Math.min(1, b));

  // Convert to 0-255 range
  return {
    r: Math.round(r * 255),
    g: Math.round(g * 255),
    b: Math.round(b * 255),
  };
}

function rgbToHex(r, g, b) {
  return "#" + [r, g, b].map(x => x.toString(16).padStart(2, '0')).join('');
}

function parseOklch(oklchString) {
  const match = oklchString.match(/oklch\(([\d.]+)%\s+([\d.]+)\s+([\d.]+)\)/);
  if (match) {
    return {
      l: parseFloat(match[1]) / 100,
      c: parseFloat(match[2]),
      h: parseFloat(match[3]),
    };
  }
  return null;
}

console.log("Social Pomodoro Color Palette\n");
console.log("================================\n");

for (const [name, oklchValue] of Object.entries(colors)) {
  const parsed = parseOklch(oklchValue);
  if (parsed) {
    const { r, g, b } = oklchToRgb(parsed.l, parsed.c, parsed.h);
    const hex = rgbToHex(r, g, b);
    console.log(`${name.padEnd(20)} ${hex.toUpperCase()}  ${oklchValue}`);
  }
}
