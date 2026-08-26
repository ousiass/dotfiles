#!/usr/bin/env bun
/**
 * スライドが枠からはみ出していないかを機械的に検査する。
 *
 * 使い方:
 *   cd slide && bun run build:site && bun <skill>/scripts/check-overflow.mjs
 *   オプション: --dist dist  --width 1280  --json
 *
 * 仕組み:
 *   dist/ を一時サーバで配信し、/1 から順に実寸で開く。
 *   Slidev は前後ページも DOM に持つため、display が none でない「可視ページ」だけを測る。
 *   要求した番号と可視ページの番号がずれたら、そこが終端。
 *   visual.css は overflow:hidden なので、はみ出しは画面上では「切れて」見える。
 *
 * 終了コード: 0 = はみ出しなし / 1 = はみ出しあり / 2 = 実行エラー
 */
import { chromium } from 'playwright-chromium'

const args = process.argv.slice(2)
const opt = (n, d) => { const i = args.indexOf(`--${n}`); return i >= 0 && args[i + 1] ? args[i + 1] : d }
const DIST = opt('dist', 'dist')
const WIDTH = parseInt(opt('width', '1280'), 10)
const HEIGHT = Math.round((WIDTH / 16) * 9)
const AS_JSON = args.includes('--json')
const TOLERANCE = 2 // px。丸め誤差を無視する
const MAX_PAGES = 500

if (!(await Bun.file(`${DIST}/index.html`).exists())) {
  console.error(`✗ ${DIST}/index.html がない。先に \`bun run build:site\` を実行する。`)
  process.exit(2)
}

const server = Bun.serve({
  port: 0,
  async fetch(req) {
    const url = new URL(req.url)
    const path = url.pathname === '/' ? '/index.html' : url.pathname
    let file = Bun.file(DIST + path)
    if (!(await file.exists())) file = Bun.file(`${DIST}/index.html`)
    return new Response(file)
  },
})
const base = `http://localhost:${server.port}`
const browser = await chromium.launch()

/** ブラウザ側で走る。可視ページを特定し、その layout のはみ出しを測る。 */
const measure = (tol) => {
  const holder = [...document.querySelectorAll('[class*="slidev-page-"]')].find((el) => {
    return getComputedStyle(el).display !== 'none' && el.getBoundingClientRect().width > 0
  })
  if (!holder) return null
  const m = holder.className.match(/slidev-page-(\d+)/)
  const layout = holder.querySelector('.slidev-layout')
  if (!layout) return null

  const lr = layout.getBoundingClientRect()
  const scale = lr.height / (layout.clientHeight || 1) // Slidev はスライドを拡大表示するので実寸へ戻す
  const culprits = []
  layout.querySelectorAll('*').forEach((el) => {
    const r = el.getBoundingClientRect()
    if (r.width === 0 || r.height === 0) return
    if (getComputedStyle(el).position === 'absolute') return // 全面配置の背景画像など
    const bottom = (r.bottom - lr.bottom) / (scale || 1)
    const right = (r.right - lr.right) / (scale || 1)
    if (bottom > tol || right > tol) {
      culprits.push({
        cls: el.className && el.className.toString().trim()
          ? '.' + el.className.toString().trim().split(/\s+/).join('.')
          : '<' + el.tagName.toLowerCase() + '>',
        bottom: Math.round(bottom),
        right: Math.round(right),
        text: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 32),
      })
    }
  })
  // 子は親と一緒にはみ出すので、最も外側だけ残す
  const outer = culprits.filter((c, i) => !culprits.slice(0, i).some((p) => c.text.startsWith(p.text.slice(0, 12))))

  return {
    actual: m ? parseInt(m[1], 10) : null,
    title: (layout.querySelector('h2, .v-cover-title, .line, h1')?.textContent || '').trim().slice(0, 40),
    overflowY: layout.scrollHeight - layout.clientHeight,
    overflowX: layout.scrollWidth - layout.clientWidth,
    culprits: outer.slice(0, 3),
  }
}

try {
  const page = await browser.newPage({ viewport: { width: WIDTH, height: HEIGHT } })
  const results = []
  for (let n = 1; n <= MAX_PAGES; n++) {
    await page.goto(`${base}/${n}`, { waitUntil: 'networkidle' })
    await page.waitForTimeout(350)
    const r = await page.evaluate(measure, TOLERANCE)
    if (!r || r.actual !== n) break // 範囲外は1ページ目にフォールバックする＝終端
    results.push({ page: n, ...r })
  }
  if (results.length === 0) throw new Error('スライドを1枚も検出できなかった')

  const bad = results.filter((r) => r.overflowY > TOLERANCE || r.overflowX > TOLERANCE || r.culprits.length)

  if (AS_JSON) {
    console.log(JSON.stringify({ total: results.length, overflow: bad }, null, 2))
  } else {
    console.log(`検査: ${results.length} ページ / はみ出し: ${bad.length} ページ`)
    if (bad.length === 0) {
      console.log('✓ 全ページが枠に収まっている')
    } else {
      for (const r of bad) {
        const dirs = []
        if (r.overflowY > TOLERANCE) dirs.push(`縦 +${r.overflowY}px`)
        if (r.overflowX > TOLERANCE) dirs.push(`横 +${r.overflowX}px`)
        console.log(`\n✗ p${r.page} ${r.title}`)
        if (dirs.length) console.log(`   ${dirs.join(' / ')}`)
        for (const c of r.culprits) {
          const d = [c.bottom > TOLERANCE ? `下に ${c.bottom}px` : null, c.right > TOLERANCE ? `右に ${c.right}px` : null].filter(Boolean).join(' / ')
          console.log(`   - ${c.cls} が ${d}  「${c.text}」`)
        }
      }
      console.log('\n対処は references/structure.md「収まらないときの対処」を参照。')
    }
  }
  await browser.close(); server.stop()
  process.exit(bad.length ? 1 : 0)
} catch (e) {
  console.error('✗ 検査に失敗:', e.message)
  await browser.close(); server.stop()
  process.exit(2)
}
