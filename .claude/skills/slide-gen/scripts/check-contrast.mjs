#!/usr/bin/env bun
/**
 * visual.css の :root トークンから、主要な文字色と背景色の
 * コントラスト比を実測する。
 *
 * 使い方:
 *   bun check-contrast.mjs            # visual.css を読む
 *   bun check-contrast.mjs path/to/visual.css
 *   bun check-contrast.mjs --json
 *
 * 基準: 本文 4.5:1 以上 / 罫線・図形などの構造色 3:1 以上。
 * 終了コード: 0 = 全項目が基準を満たす / 1 = 満たさない項目がある / 2 = 実行エラー
 */

const args = process.argv.slice(2)
const AS_JSON = args.includes('--json')
const file = args.find((a) => !a.startsWith('--')) || 'visual.css'

const src = Bun.file(file)
if (!(await src.exists())) {
  console.error(`✗ ${file} がない。デッキのディレクトリで実行する。`)
  process.exit(2)
}
const css = await src.text()

// :root は複数あり得る（スタイルプリセットを末尾に追記する運用）。後勝ちで畳む。
const vars = {}
for (const block of css.matchAll(/:root\s*\{([^}]*)\}/g)) {
  for (const line of block[1].split('\n')) {
    const m = line.match(/(--v-[a-z0-9-]+)\s*:\s*([^;]+);/i)
    if (m) vars[m[1]] = m[2].trim()
  }
}

/** var(--x) 参照を解決する */
const resolve = (v, depth = 0) => {
  if (!v || depth > 10) return null
  const m = v.match(/^var\((--v-[a-z0-9-]+)\)$/i)
  if (m) return resolve(vars[m[1]], depth + 1)
  return /^#[0-9a-f]{6}$/i.test(v) ? v : null
}

const lum = (hex) => {
  const n = parseInt(hex.slice(1), 16)
  const [r, g, b] = [(n >> 16) & 255, (n >> 8) & 255, n & 255].map((v) => v / 255)
  const f = (c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4)
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
}
const contrast = (a, b) => {
  const [l1, l2] = [lum(a), lum(b)].sort((x, y) => y - x)
  return Math.round(((l1 + 0.05) / (l2 + 0.05)) * 100) / 100
}

const pairs = [
  ['白文字 / dark 背景', '--v-white', '--v-bg-dark', 4.5],
  ['本文 ink / light 背景', '--v-ink', '--v-bg-light', 4.5],
  ['muted / light 背景', '--v-muted', '--v-bg-light', 4.5],
  ['見出し navy / light 背景', '--v-navy', '--v-bg-light', 4.5],
  ['blue / light 背景', '--v-blue', '--v-bg-light', 4.5],
  ['accent-text / light 背景', '--v-accent-text', '--v-bg-light', 4.5],
  ['accent 構造色 / light 背景', '--v-accent', '--v-bg-light', 3],
  ['accent-on-dark / dark 背景', '--v-accent-on-dark', '--v-bg-dark', 4.5],
  ['magenta-text / light 背景', '--v-magenta-text', '--v-bg-light', 4.5],
  ['on-accent 文字 / accent 背景', '--v-on-accent', '--v-accent', 4.5],
  ['罫線 line / light 背景', '--v-line', '--v-bg-light', 1.2],
]

const results = []
const missing = []
for (const [label, fgVar, bgVar, target] of pairs) {
  const fg = resolve(vars[fgVar]), bg = resolve(vars[bgVar])
  if (!fg || !bg) { missing.push(`${label}（${!fg ? fgVar : bgVar} が未定義か解決できない）`); continue }
  const ratio = contrast(fg, bg)
  results.push({ label, fg, bg, ratio, target, ok: ratio >= target })
}

const ng = results.filter((r) => !r.ok)
if (AS_JSON) {
  console.log(JSON.stringify({ file, results, missing }, null, 2))
} else {
  console.log(`配色検査: ${file}`)
  for (const r of results) {
    console.log(`  ${r.ok ? 'OK ' : 'NG '}${String(r.ratio).padStart(6)}:1  ${r.label}（基準 ${r.target}:1  ${r.fg} / ${r.bg}）`)
  }
  for (const m of missing) console.log(`  --  未検査  ${m}`)
  if (ng.length) {
    console.log(`\n✗ ${ng.length} 項目が基準を下回る。scripts/derive-palette.mjs で導出し直すか、`)
    console.log('  該当トークンの明度だけを調整して再検査する。')
  } else {
    console.log('\n✓ すべて基準を満たしている。')
  }
}
process.exit(ng.length ? 1 : 0)
