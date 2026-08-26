<template>
  <footer class="deck-footer">
    <!-- ロゴ画像を使う場合は下の <div class="name"> を消し、これを有効化する。
         dark 背景のページでも読めるよう、白抜き版を用意して切り替えるか、
         どちらの背景でも成立する単色ロゴを使う。
    <img class="logo" src="/img/logo.svg" alt="___ORG_NAME___" />
    -->
    <div class="name">___ORG_NAME___</div>
    <div v-if="$slidev.nav.currentPage > 1" class="page">
      {{ $slidev.nav.currentPage }} / {{ $slidev.nav.total }}
    </div>
  </footer>
</template>

<style scoped>
.deck-footer {
  position: absolute;
  right: 0;
  bottom: 0;
  left: 0;
  z-index: 20;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 0 2rem 0.9rem;
  color: var(--v-muted);
  font-family: var(--v-sans);
  font-size: 0.6rem;
  font-weight: 500;
  letter-spacing: 0.2em;
  pointer-events: none;
}

/* フッターのロゴは主張させない。高さだけ揃える */
.deck-footer .logo {
  height: 0.85rem;
  opacity: 0.7;
  object-fit: contain;
}

/* ページ番号は中央のクレジットに影響させず右端へ置く */
.deck-footer .page {
  position: absolute;
  right: 2rem;
  font-variant-numeric: tabular-nums;
}

:global(.slidev-layout.visual-deck.v-dark) .deck-footer {
  color: var(--v-on-dark-muted);
}
</style>
