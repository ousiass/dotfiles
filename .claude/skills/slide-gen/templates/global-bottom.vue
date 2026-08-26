<template>
  <footer class="deck-footer">
    <div class="name">{{ORG_NAME}}</div>
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
  color: #98a2b3;
  font-family: 'Inter', 'Noto Sans JP', system-ui, sans-serif;
  font-size: 0.6rem;
  font-weight: 500;
  letter-spacing: 0.2em;
  pointer-events: none;
}

/* ページ番号は中央のクレジットに影響させず右端へ置く */
.deck-footer .page {
  position: absolute;
  right: 2rem;
  font-variant-numeric: tabular-nums;
}

:global(.slidev-layout.visual-deck.v-dark) .deck-footer {
  color: #8b93b8;
}
</style>
