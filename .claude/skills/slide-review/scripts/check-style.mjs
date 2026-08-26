#!/usr/bin/env bun
/**
 * 装飾に逃げた表現を検出する。
 *
 * 生成 AI が作った資料にありがちな見た目（グラデーション塗り、光彩、
 * すりガラス、絵文字アイコン、色の直書き）を機械で潰すための検査。
 * これらは情報を1つも足さないのに、資料を安っぽく見せる。
 *
 * 使い方:
 *   bun check-style.mjs                 # visual.css / style.css / slides.md / pages/*.md
 *   bun check-style.mjs --json
 *
 * 終了コード: 0 = 指摘なし / 1 = 指摘あり / 2 = 実行エラー
 */

const AS_JSON = process.argv.includes('--json')

const files = []
for (const f of ['visual.css', 'style.css', 'slides.md', 'global-bottom.vue']) {
  if (await Bun.file(f).exists()) files.push(f)
}
const glob = new Bun.Glob('pages/*.md')
for await (const f of glob.scan('.')) files.push(f)
if (files.length === 0) {
  console.error('✗ 対象ファイルがない。デッキのディレクトリで実行する。')
  process.exit(2)
}

/** 機能として必要な例外。ここに載るセレクタでだけ使ってよい */
const ALLOW = {
  gradient: [
    '.v-cover::after',      // 画像の上に文字を載せるための減光
    '.v-end::after',
    '.v-image-slide::after',
    '.v-fragment-lines',    // 破線パターン
  ],
  textShadow: ['.v-image-copy', '.v-cover-copy', '.v-end-copy'], // 画像上の文字の可読性
}

const findings = []
const add = (file, line, rule, text, hint) => findings.push({ file, line, rule, text: text.trim().slice(0, 90), hint })

for (const file of files) {
  const src = await Bun.file(file).text()
  const lines = src.split('\n')
  let selector = ''

  lines.forEach((raw, i) => {
    const line = raw.trim()
    const no = i + 1
    if (file.endsWith('.css') || file.endsWith('.vue')) {
      if (line.endsWith('{')) selector = line.slice(0, -1).trim()

      const allowed = (list) => list.some((a) => selector.includes(a))

      if (/\b(linear|radial|conic)-gradient\(/.test(line) && !allowed(ALLOW.gradient)) {
        add(file, no, 'グラデーション塗り', line,
          '面は単色で塗る。区切りが要るなら罫線か余白を使う')
      }
      if (/backdrop-filter\s*:/.test(line)) {
        add(file, no, 'すりガラス', line, 'backdrop-filter は使わない。単色の面にする')
      }
      if (/text-shadow\s*:/.test(line) && !allowed(ALLOW.textShadow)) {
        add(file, no, '文字の影', line,
          '文字を影で浮かせない。読めないなら背景側を暗くする')
      }
      if (/box-shadow\s*:/.test(line) && !/var\(--v-card-shadow/.test(line) && !/box-shadow\s*:\s*none/.test(line)) {
        add(file, no, '影の直書き', line,
          '--v-card-shadow / --v-card-shadow-raised を使う')
      }
      if (/filter\s*:\s*(blur|drop-shadow)/.test(line)) {
        add(file, no, 'ぼかし・グロー', line, '光らせない。色と余白で階層を作る')
      }
      if (/animation\s*:|@keyframes/.test(line)) {
        add(file, no, 'アニメーション', line,
          'ページ内で動かさない。切り替えは Slidev の transition に任せる')
      }
      // :root の外に置かれた色リテラル
      if (/#[0-9a-fA-F]{6}\b/.test(line) && !selector.includes(':root') && !line.startsWith('/*') && !line.startsWith('*')) {
        add(file, no, '色の直書き', line, ':root の配色トークンに寄せる')
      }
    } else {
      // Markdown（スライド本文）
      const emoji = raw.match(/\p{Extended_Pictographic}/gu)
      if (emoji) {
        add(file, no, '絵文字', line,
          `絵文字（${[...new Set(emoji)].join('')}）をアイコン代わりに使わない。番号か語で示す`)
      }
      if (/style\s*=\s*"/.test(raw)) {
        add(file, no, 'インラインスタイル', line, 'visual.css のクラスで表現する')
      }
      if (/#[0-9a-fA-F]{6}\b/.test(raw) && !/^\s*[-|]/.test(raw)) {
        add(file, no, '色の直書き', line, 'visual.css の :root に寄せる')
      }
    }
  })
}

if (AS_JSON) {
  console.log(JSON.stringify({ files, findings }, null, 2))
} else {
  console.log(`装飾検査: ${files.join(', ')}`)
  if (findings.length === 0) {
    console.log('✓ 装飾に逃げた表現はない')
  } else {
    const byRule = {}
    for (const f of findings) (byRule[f.rule] ||= []).push(f)
    for (const [rule, list] of Object.entries(byRule)) {
      console.log(`\n✗ ${rule}（${list.length}件） — ${list[0].hint}`)
      for (const f of list.slice(0, 6)) console.log(`   ${f.file}:${f.line}  ${f.text}`)
      if (list.length > 6) console.log(`   … 他 ${list.length - 6} 件`)
    }
  }
}
process.exit(findings.length ? 1 : 0)
