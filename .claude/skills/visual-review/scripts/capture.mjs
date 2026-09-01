#!/usr/bin/env node
/**
 * visual-review: Playwright によるスクリーンショット撮影
 *
 * Usage:
 *   node capture.mjs <config.json>              全ターゲットを撮影（モック指定があればモックも撮影）
 *   node capture.mjs <config.json> --auth       ログインして storageState を保存（初回のみ）
 *   node capture.mjs <config.json> --only a,b   指定 id のみ撮影
 *
 * 出力:
 *   <outDir>/shots/<id>__<viewport>__<theme>[__sN].png       実装
 *   <outDir>/shots/<id>__mock__<viewport>[__sN].png          モック（HTML モック時）
 *   <outDir>/manifest.json
 *
 * 設定スキーマは references/setup.md を参照。
 */

import { mkdir, writeFile, readFile, rm, access } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRequire } from 'node:module';

const DEFAULTS = {
  outDir: '.visual-review',
  viewports: [
    { name: 'desktop', width: 1440, height: 900 },
    { name: 'tablet', width: 834, height: 1112 },
    { name: 'mobile', width: 390, height: 844 },
  ],
  themes: [{ name: 'light', colorScheme: 'light' }],
  fullPage: true,
  maxSliceHeight: 2000,
  navigationTimeout: 30000,
  actionTimeout: 10000,
  stabilizeDelay: 300,
  waitForFrontend: true, // HTMX のスワップ完了と Web Components の描画完了を待つ
  // フラグメント（HTMX が返す部分 HTML）を単体で撮るためのラッパー
  fragmentWrapper: '<!doctype html><html><head><base href="{{baseUrl}}"><link rel="stylesheet" href="/static/dist/css/app.css"></head><body>{{content}}</body></html>',
};

const IMAGE_EXT = new Set(['.png', '.jpg', '.jpeg', '.webp', '.gif', '.avif']);

// アニメーション・キャレット・スムーススクロールを止めて撮影を決定的にする
const STABILIZE_CSS = `
*, *::before, *::after {
  animation-duration: 0s !important;
  animation-delay: 0s !important;
  transition-duration: 0s !important;
  transition-delay: 0s !important;
  caret-color: transparent !important;
}
html { scroll-behavior: auto !important; }
`;

function parseArgs(argv) {
  const [configPath, ...rest] = argv;
  if (!configPath) {
    console.error('Usage: node capture.mjs <config.json> [--auth] [--only id1,id2]');
    process.exit(1);
  }
  const onlyIdx = rest.indexOf('--only');
  return {
    configPath,
    authMode: rest.includes('--auth'),
    only: onlyIdx >= 0 && rest[onlyIdx + 1] ? rest[onlyIdx + 1].split(',').map((s) => s.trim()) : null,
  };
}

/** actions / login.steps の簡易 DSL を実行する */
async function runSteps(page, steps = []) {
  for (const step of steps) {
    if (step.goto) await page.goto(step.goto, { waitUntil: 'domcontentloaded' });
    else if (step.click) await page.click(step.click);
    else if (step.fill) await page.fill(step.fill[0], step.fill[1]);
    else if (step.press) await page.press(step.press[0], step.press[1]);
    else if (step.waitFor) await page.waitForSelector(step.waitFor);
    else if (step.waitForUrl) await page.waitForURL(step.waitForUrl);
    else if (step.wait) await page.waitForTimeout(step.wait);
    else if (step.scrollTo) await page.evaluate((y) => window.scrollTo(0, y), step.scrollTo);
    else throw new Error(`未知のステップ: ${JSON.stringify(step)}`);
  }
}

/** テーマを適用するための init script を組み立てる（DOM 構築前に反映させる） */
function themeInitScript(theme) {
  const { rootAttribute, rootClass, localStorage: ls } = theme;
  if (!rootAttribute && !rootClass && !ls) return null;
  return ({ rootAttribute, rootClass, ls }) => {
    if (ls) {
      for (const [k, v] of Object.entries(ls)) {
        try { window.localStorage.setItem(k, v); } catch { /* 無効化されている場合は無視 */ }
      }
    }
    const apply = () => {
      const el = document.documentElement;
      if (rootAttribute) el.setAttribute(rootAttribute[0], rootAttribute[1]);
      if (rootClass) el.classList.add(rootClass);
    };
    if (document.documentElement) apply();
    document.addEventListener('DOMContentLoaded', apply);
  };
}

/**
 * HTMX のスワップ完了と Web Components（Lit 等）の描画完了を待つ。
 * どちらも未使用のページでは即座に抜けるため、常に呼んで差し支えない。
 */
async function waitForFrontend(page, timeout) {
  // HTMX: リクエスト中・スワップ中・settle 中のクラスが消えるまで
  await page
    .waitForFunction(
      () => !window.htmx || document.querySelectorAll('.htmx-request, .htmx-swapping, .htmx-settling').length === 0,
      null,
      { timeout },
    )
    .catch(() => {}); // 待てなくても撮影は続ける（レビュー側で判断する）

  // Web Components: カスタム要素の定義と最初のレンダリングを待つ
  await page
    .evaluate(async () => {
      if (!window.customElements) return;
      const tags = new Set(
        [...document.querySelectorAll('*')].map((el) => el.tagName.toLowerCase()).filter((t) => t.includes('-')),
      );
      await Promise.all(
        [...tags].map((t) => Promise.race([customElements.whenDefined(t), new Promise((r) => setTimeout(r, 3000))])),
      );
      const els = [...document.querySelectorAll('*')].filter((el) => el.tagName.includes('-'));
      await Promise.all(
        els.map((el) => (el.updateComplete ? Promise.resolve(el.updateComplete).catch(() => {}) : Promise.resolve())),
      );
    })
    .catch(() => {});
}

/**
 * 撮影前に描画を安定させる。
 * shadow DOM には外側の CSS が届かないため、各 shadowRoot にも style を注入する。
 */
async function stabilize(page, hideSelectors, cfg) {
  if (cfg.waitForFrontend) await waitForFrontend(page, cfg.actionTimeout);

  const hideCss = hideSelectors.map((s) => `${s} { visibility: hidden !important; }`).join('\n');
  const css = `${STABILIZE_CSS}\n${hideCss}`;

  await page.addStyleTag({ content: css }).catch(() => {});
  await page
    .evaluate((cssText) => {
      const inject = (root) => {
        const style = document.createElement('style');
        style.textContent = cssText;
        root.appendChild(style);
      };
      const walk = (root) => {
        for (const el of root.querySelectorAll('*')) {
          if (el.shadowRoot) {
            inject(el.shadowRoot);
            walk(el.shadowRoot);
          }
        }
      };
      walk(document);
    }, css)
    .catch(() => {});

  await page.evaluate(() => document.fonts?.ready).catch(() => {});
  await page.waitForTimeout(cfg.stabilizeDelay);
}

/**
 * ページを撮影する。縦長ページはビューポート単位にスライスして
 * 1 枚が巨大画像にならないようにする（レビュー時の画像トークン対策）。
 */
async function shoot(page, { baseName, shotsDir, viewportHeight, viewportWidth, fullPage, maxSliceHeight }) {
  const pageHeight = fullPage
    ? await page.evaluate(() => document.documentElement.scrollHeight)
    : viewportHeight;
  const sliceCount = fullPage ? Math.max(1, Math.ceil(pageHeight / maxSliceHeight)) : 1;
  const opts = { animations: 'disabled', scale: 'css', type: 'png' };
  const results = [];

  for (let i = 0; i < sliceCount; i++) {
    const suffix = sliceCount > 1 ? `__s${i + 1}` : '';
    const file = path.join(shotsDir, `${baseName}${suffix}.png`);
    const clip = sliceCount > 1
      ? {
          x: 0,
          y: i * maxSliceHeight,
          width: viewportWidth,
          height: Math.min(maxSliceHeight, pageHeight - i * maxSliceHeight),
        }
      : undefined;
    await page.screenshot({ ...opts, path: file, fullPage, clip });
    results.push({
      slice: sliceCount > 1 ? i + 1 : null,
      sliceCount,
      path: path.relative(process.cwd(), file),
    });
  }
  return results;
}

/**
 * フラグメント（HTMX が返す部分 HTML）を単体で描画する。
 * 部分 HTML には head が無く、そのまま開くと CSS が当たらないためラッパーに埋め込む。
 */
async function loadFragment(ctx, page, url, cfg) {
  const res = await ctx.request.get(url, { headers: { 'HX-Request': 'true', 'HX-Boosted': 'false' } });
  if (!res.ok()) throw new Error(`フラグメント取得に失敗: ${res.status()} ${url}`);
  const html = await res.text();
  const wrapper = cfg.fragmentWrapper
    .replace('{{baseUrl}}', cfg.baseUrl.endsWith('/') ? cfg.baseUrl : `${cfg.baseUrl}/`)
    .replace('{{content}}', html);
  await page.setContent(wrapper, { waitUntil: 'networkidle' });
}

/** モック指定を種別ごとに解決する（画像 / HTML / URL / Markdown） */
async function resolveMock(mock, configDir) {
  if (!mock) return null;
  const spec = typeof mock === 'string' ? { path: mock } : mock;
  if (spec.url) return { kind: 'html', target: spec.url, source: spec.url };

  const abs = path.resolve(configDir, spec.path);
  try {
    await access(abs);
  } catch {
    return { kind: 'missing', source: spec.path };
  }
  const ext = path.extname(abs).toLowerCase();
  if (IMAGE_EXT.has(ext)) {
    // 画像モック（デザインカンプ）は撮影不要。レビュー時に直接読み込む
    return { kind: 'image', target: abs, source: path.relative(process.cwd(), abs) };
  }
  if (ext === '.md' || ext === '.markdown') {
    // Markdown モックは画像化せず、レビュー時に本文を読んで実描画と照合する
    return { kind: 'markdown', target: abs, source: path.relative(process.cwd(), abs) };
  }
  return { kind: 'html', target: pathToFileURL(abs).href, source: path.relative(process.cwd(), abs) };
}

/**
 * playwright を解決する。本スクリプトはスキルディレクトリに置かれるため、
 * 対象プロジェクト側の node_modules を優先して探す。
 */
async function loadChromium(configDir) {
  // playwright は CJS のため named export を拾えない場合がある（default 経由でも取る）
  const pick = (mod) => mod?.chromium ?? mod?.default?.chromium ?? null;

  for (const base of [process.cwd(), configDir, path.join(process.env.HOME ?? '', '.cache/visual-review')]) {
    try {
      const req = createRequire(path.join(base, 'package.json'));
      const url = pathToFileURL(req.resolve('playwright')).href;
      const chromium = pick(await import(url));
      if (chromium) return chromium;
    } catch { /* 次の候補へ */ }
  }
  try {
    // スクリプト位置基準（グローバル導入やスキル同梱時）
    return pick(await import('playwright'));
  } catch {
    return null;
  }
}

async function main() {
  const { configPath, authMode, only } = parseArgs(process.argv.slice(2));
  const configDir = path.dirname(path.resolve(configPath));
  const raw = JSON.parse(await readFile(configPath, 'utf8'));
  const cfg = { ...DEFAULTS, ...raw };

  if (!cfg.baseUrl) throw new Error('config.baseUrl が未設定です');
  if (!Array.isArray(cfg.targets) || cfg.targets.length === 0) throw new Error('config.targets が空です');

  const chromium = await loadChromium(configDir);
  if (!chromium) {
    console.error('playwright が見つかりません。対象プロジェクトで `bun add -d playwright && bunx playwright install chromium` を実行してください。');
    process.exit(1);
  }

  const outDir = path.resolve(configDir, cfg.outDir);
  const shotsDir = path.join(outDir, 'shots');
  const browser = await chromium.launch();

  try {
    // --auth: ログイン導線を実行して storageState を保存する
    if (authMode) {
      if (!cfg.auth?.login?.steps) throw new Error('config.auth.login.steps が未設定です');
      const statePath = path.resolve(outDir, cfg.auth.storageState ?? 'auth.json');
      await mkdir(path.dirname(statePath), { recursive: true });
      const ctx = await browser.newContext({ baseURL: cfg.baseUrl });
      const page = await ctx.newPage();
      await runSteps(page, cfg.auth.login.steps);
      await ctx.storageState({ path: statePath });
      await ctx.close();
      console.log(`認証状態を保存しました: ${statePath}`);
      return;
    }

    await rm(shotsDir, { recursive: true, force: true });
    await mkdir(shotsDir, { recursive: true });

    const targets = only ? cfg.targets.filter((t) => only.includes(t.id)) : cfg.targets;
    if (targets.length === 0) throw new Error('--only に一致するターゲットがありません');

    const storageState = cfg.auth?.storageState ? path.resolve(outDir, cfg.auth.storageState) : undefined;
    const globalHide = cfg.hide ?? [];

    // モック指定を先に解決しておく（欠落もレポート対象になる）
    const mocks = new Map();
    for (const t of targets) {
      const resolved = await resolveMock(t.mock, configDir);
      if (resolved) mocks.set(t.id, resolved);
    }

    const shots = [];
    const mockShots = [];
    const failures = [];

    for (const vp of cfg.viewports) {
      for (const theme of cfg.themes) {
        const ctx = await browser.newContext({
          baseURL: cfg.baseUrl,
          viewport: { width: vp.width, height: vp.height },
          colorScheme: theme.colorScheme ?? 'light',
          deviceScaleFactor: 1, // 画像サイズを抑える
          storageState,
        });
        ctx.setDefaultNavigationTimeout(cfg.navigationTimeout);
        ctx.setDefaultTimeout(cfg.actionTimeout); // waitFor 等が長時間ぶら下がるのを防ぐ

        const initFn = themeInitScript(theme);
        if (initFn) {
          await ctx.addInitScript(initFn, {
            rootAttribute: theme.rootAttribute,
            rootClass: theme.rootClass,
            ls: theme.localStorage,
          });
        }

        const isFirstTheme = theme === cfg.themes[0];

        for (const target of targets) {
          const shootOpts = {
            shotsDir,
            viewportWidth: vp.width,
            viewportHeight: vp.height,
            fullPage: target.fullPage ?? cfg.fullPage,
            maxSliceHeight: cfg.maxSliceHeight,
          };

          // --- 実装側 ---
          const base = `${target.id}__${vp.name}__${theme.name}`;
          const page = await ctx.newPage();
          try {
            if (target.fragment) {
              await loadFragment(ctx, page, target.url, cfg);
            } else {
              await page.goto(target.url, { waitUntil: target.waitUntil ?? 'networkidle' });
            }
            if (target.waitFor) await page.waitForSelector(target.waitFor);
            if (target.actions) await runSteps(page, target.actions);
            await stabilize(page, target.hide ?? globalHide, cfg);

            const files = await shoot(page, { ...shootOpts, baseName: base });
            for (const f of files) {
              shots.push({
                id: target.id,
                name: target.name ?? target.id,
                url: target.url,
                fragment: !!target.fragment,
                viewport: vp.name,
                theme: theme.name,
                ...f,
              });
            }
            console.log(`ok   ${base} (${files.length} 枚)`);
          } catch (err) {
            failures.push({ kind: 'impl', id: target.id, url: target.url, viewport: vp.name, theme: theme.name, error: String(err?.message ?? err) });
            console.error(`FAIL ${base}: ${err?.message ?? err}`);
          } finally {
            await page.close();
          }

          // --- モック側（HTML モックのみ撮影。テーマ非依存なので先頭テーマでのみ実行） ---
          const mock = mocks.get(target.id);
          if (mock?.kind === 'html' && isFirstTheme) {
            const mockBase = `${target.id}__mock__${vp.name}`;
            const mockPage = await ctx.newPage();
            try {
              await mockPage.goto(mock.target, { waitUntil: 'networkidle' });
              await stabilize(mockPage, target.hide ?? globalHide, cfg);
              const files = await shoot(mockPage, { ...shootOpts, baseName: mockBase });
              for (const f of files) {
                mockShots.push({ id: target.id, viewport: vp.name, source: mock.source, kind: 'html', ...f });
              }
              console.log(`ok   ${mockBase} (mock, ${files.length} 枚)`);
            } catch (err) {
              failures.push({ kind: 'mock', id: target.id, source: mock.source, viewport: vp.name, error: String(err?.message ?? err) });
              console.error(`FAIL ${mockBase}: ${err?.message ?? err}`);
            } finally {
              await mockPage.close();
            }
          }
        }
        await ctx.close();
      }
    }

    // 撮影不要なモック（画像 / Markdown）と欠落モックを manifest に載せる
    for (const [id, mock] of mocks) {
      if (mock.kind === 'image' || mock.kind === 'markdown') {
        mockShots.push({ id, viewport: null, source: mock.source, kind: mock.kind, path: mock.source, slice: null, sliceCount: 1 });
      } else if (mock.kind === 'missing') {
        failures.push({ kind: 'mock', id, source: mock.source, error: 'モックファイルが見つかりません' });
      }
    }

    const manifest = {
      generatedAt: new Date().toISOString(),
      baseUrl: cfg.baseUrl,
      viewports: cfg.viewports.map((v) => v.name),
      themes: cfg.themes.map((t) => t.name),
      targetCount: targets.length,
      shotCount: shots.length,
      mockShotCount: mockShots.length,
      targets: targets.map((t) => ({
        id: t.id,
        name: t.name ?? t.id,
        url: t.url,
        fragment: !!t.fragment,
        mock: mocks.get(t.id) ? { kind: mocks.get(t.id).kind, source: mocks.get(t.id).source } : null,
        origin: t.origin ?? null,
      })),
      shots,
      mockShots,
      failures,
    };
    const manifestPath = path.join(outDir, 'manifest.json');
    await writeFile(manifestPath, JSON.stringify(manifest, null, 2));
    console.log(`\n実装 ${shots.length} 枚 / モック ${mockShots.length} 件 / 失敗 ${failures.length} 件`);
    console.log(`manifest: ${path.relative(process.cwd(), manifestPath)}`);
  } finally {
    await browser.close();
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
