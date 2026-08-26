#!/usr/bin/env bun
/**
 * プライマリカラー1色から visual.css の :root 配色トークンを導出する。
 *
 * 使い方:
 *   bun derive-palette.mjs "#2b6cb0"
 *   bun derive-palette.mjs "#2b6cb0" --accent "#d6339b"   # 強調色も指定する
 *   bun derive-palette.mjs "#2b6cb0" --json
 *
 * 導出の方針:
 *   - プライマリを --v-accent（構造色）に据える
 *   - light 背景で 4.5:1 を満たすまで暗くしたものを --v-accent-text（本文用）
 *   - dark 背景で 4.5:1 を満たすまで明るくしたものを --v-accent-on-dark
 *   - プライマリの色相を保ったまま明度を落としたものを --v-navy / --v-bg-dark
 *   - 強調色は指定がなければ色相を +150° 回した色から同じ手順で作る
 *
 * 出力した :root を visual.css の既存 :root と差し替える。
 * コントラスト比は WCAG の相対輝度比。本文 4.5:1 以上、構造色 3:1 以上が基準。
 */

const args = process.argv.slice(2)
const primary = args.find((a) => a.startsWith('#'))
const accentIdx = args.indexOf('--accent')
const accentArg = accentIdx >= 0 ? args[accentIdx + 1] : null
const AS_JSON = args.includes('--json')

if (!primary || !/^#[0-9a-fA-F]{6}$/.test(primary)) {
  console.error('使い方: bun derive-palette.mjs "#2b6cb0" [--accent "#d6339b"] [--json]')
  process.exit(2)
}

const hex2rgb = (h) => {
  const n = parseInt(h.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}
const rgb2hex = ([r, g, b]) =>
  '#' + [r, g, b].map((v) => Math.round(Math.min(255, Math.max(0, v))).toString(16).padStart(2, '0')).join('')

const rgb2hsl = ([r, g, b]) => {
  r /= 255; g /= 255; b /= 255
  const max = Math.max(r, g, b), min = Math.min(r, g, b)
  const l = (max + min) / 2
  if (max === min) return [0, 0, l]
  const d = max - min
  const s = l > 0.5 ? d / (2 - max - min) : d / (max + min)
  let h
  if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) / 6
  else if (max === g) h = ((b - r) / d + 2) / 6
  else h = ((r - g) / d + 4) / 6
  return [h, s, l]
}
const hsl2rgb = ([h, s, l]) => {
  if (s === 0) return [l * 255, l * 255, l * 255]
  const q = l < 0.5 ? l * (1 + s) : l + s - l * s
  const p = 2 * l - q
  const f = (t) => {
    if (t < 0) t += 1
    if (t > 1) t -= 1
    if (t < 1 / 6) return p + (q - p) * 6 * t
    if (t < 1 / 2) return q
    if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
    return p
  }
  return [f(h + 1 / 3) * 255, f(h) * 255, f(h - 1 / 3) * 255]
}

const lum = (hex) => {
  const [r, g, b] = hex2rgb(hex).map((v) => v / 255)
  const f = (c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}
const contrast = (a, b) => {
  const [l1, l2] = [lum(a), lum(b)].sort((x, y) => y - x)
  return (l1 + 0.05) / (l2 + 0.05)
}
const withL = (hex, l) => {
  const [h, s] = rgb2hsl(hex2rgb(hex))
  return rgb2hex(hsl2rgb([h, s, l]))
}
const rotate = (hex, deg) => {
  const [h, s, l] = rgb2hsl(hex2rgb(hex))
  return rgb2hex(hsl2rgb([(h + deg / 360 + 1) % 1, s, l]))
}
/** target 以上のコントラストになるまで明度を step ずつ動かす */
const adjustUntil = (hex, bg, target, dir) => {
  let [h, s, l] = rgb2hsl(hex2rgb(hex))
  for (let i = 0; i < 100; i++) {
    const c = rgb2hex(hsl2rgb([h, s, l]))
    if (contrast(c, bg) >= target) return c
    l = Math.min(1, Math.max(0, l + dir * 0.01))
    if (l === 0 || l === 1) return rgb2hex(hsl2rgb([h, s, l]))
  }
  return rgb2hex(hsl2rgb([h, s, l]))
}

const [ph, ps] = rgb2hsl(hex2rgb(primary))
const bgLight = rgb2hex(hsl2rgb([ph, Math.min(ps, 0.18), 0.972]))   // ほのかに色相を含む白
const bgDark = rgb2hex(hsl2rgb([ph, Math.max(ps * 0.75, 0.35), 0.11]))
const navy = bgDark
const blue = adjustUntil(withL(primary, 0.33), bgLight, 7, -1)
// 構造色（罫線・大きな数字）は light 背景で 3:1 を満たすまで暗くする。
// 指定色が明るいとそのままでは線が見えないため。
const accent = adjustUntil(primary, bgLight, 3, -1)
const accentAdjusted = accent.toLowerCase() !== primary.toLowerCase()
// accent をベタ塗りした上の文字は、白と navy のうちコントラストが高い方を使う
const accentText = adjustUntil(primary, bgLight, 4.5, -1)
const accentOnDark = adjustUntil(primary, bgDark, 4.5, +1)
const magentaBase = accentArg && /^#[0-9a-fA-F]{6}$/.test(accentArg) ? accentArg : rotate(primary, 150)
const magenta = magentaBase
const magentaText = adjustUntil(magentaBase, bgLight, 4.5, -1)
const ink = rgb2hex(hsl2rgb([ph, 0.22, 0.11]))
const muted = adjustUntil(rgb2hex(hsl2rgb([ph, 0.09, 0.45])), bgLight, 4.5, -1)
const line = rgb2hex(hsl2rgb([ph, 0.14, 0.88]))
const onAccent = contrast('#ffffff', accent) >= contrast(navy, accent) ? '#ffffff' : navy

const root = `:root {
  --v-bg-light: ${bgLight};
  --v-bg-dark: ${bgDark};
  --v-navy: ${navy};
  --v-blue: ${blue};
  --v-accent: ${accent};
  --v-accent-text: ${accentText};
  --v-accent-on-dark: ${accentOnDark};
  --v-magenta: ${magenta};
  --v-magenta-text: ${magentaText};
  --v-white: #ffffff;
  --v-ink: ${ink};
  --v-muted: ${muted};
  --v-line: ${line};
  --v-line-dark: rgba(255, 255, 255, 0.16);
  --v-mono: 'JetBrains Mono', ui-monospace, monospace;
  --v-sans: 'Inter', 'Hiragino Kaku Gothic ProN', 'Noto Sans JP', system-ui, sans-serif;
  --v-on-accent: ${onAccent};
}`

const checks = [
  ['白文字 / dark 背景', '#ffffff', bgDark, 4.5],
  ['本文 ink / light 背景', ink, bgLight, 4.5],
  ['muted / light 背景', muted, bgLight, 4.5],
  ['accent-text / light 背景', accentText, bgLight, 4.5],
  ['accent 構造色 / light 背景', accent, bgLight, 3],
  ['accent-on-dark / dark 背景', accentOnDark, bgDark, 4.5],
  ['magenta-text / light 背景', magentaText, bgLight, 4.5],
  ['on-accent 文字 / accent 背景', onAccent, accent, 4.5],
  ['blue 見出し / light 背景', blue, bgLight, 4.5],
]
const results = checks.map(([label, fg, bg, target]) => {
  const ratio = Math.round(contrast(fg, bg) * 100) / 100
  return { label, fg, bg, ratio, target, ok: ratio >= target }
})

if (AS_JSON) {
  console.log(JSON.stringify({ primary, root, checks: results }, null, 2))
} else {
  console.log(root)
  if (accentAdjusted) {
    console.log(`\n※ 指定色 ${primary} は light 背景で ${Math.round(contrast(primary, bgLight) * 100) / 100}:1 と薄いため、`)
    console.log(`   罫線や数字が見えるよう --v-accent を ${accent} に調整した。`)
    console.log(`   ブランド色をそのまま使いたい場合は --v-accent を ${primary} に戻し、`)
    console.log('   細い罫線に使わない運用にする。')
  }
  console.log('\n--- コントラスト比 ---')
  for (const r of results) {
    console.log(`  ${r.ok ? 'OK ' : 'NG '}${String(r.ratio).padStart(5)}:1  ${r.label}（基準 ${r.target}:1）`)
  }
  const ng = results.filter((r) => !r.ok)
  if (ng.length) {
    console.log('\n✗ 基準を満たさない組み合わせがある。プライマリの明度を変えて再実行するか、')
    console.log('  該当トークンだけ手で調整して再検証する。')
  } else {
    console.log('\n✓ すべて基準を満たしている。この :root を visual.css の :root と差し替える。')
  }
}
process.exit(results.every((r) => r.ok) ? 0 : 1)
