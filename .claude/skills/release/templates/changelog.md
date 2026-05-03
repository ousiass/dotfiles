# Changelog テンプレート

## 変更カテゴリ

| カテゴリ / Category | コミットの type | 説明 |
|---------|---------------|------|
| ✨ New Features / 新機能 | `feat` | 新しい機能の追加 |
| 🐛 Bug Fixes / バグ修正 | `fix` | バグの修正 |
| 🔧 Improvements / 改善 | `update`, `refactor` | 既存機能の改善・リファクタリング |
| 📝 Documentation / ドキュメント | `docs` | ドキュメントの更新 |
| 🧪 Tests / テスト | `test` | テストの追加・修正 |
| 🏗️ Infrastructure / インフラ | `ci`, `build` | CI/CD、ビルド設定の変更 |
| ⚠️ Breaking Changes / 破壊的変更 | `BREAKING` を含む | 後方互換性のない変更 |

## エントリ形式

```markdown
## [v1.2.0] - YYYY-MM-DD

### ✨ New Features / 新機能
- <英語の説明 / 日本語の説明> (#PR番号)

### 🐛 Bug Fixes / バグ修正
- <英語の説明 / 日本語の説明> (#PR番号)

### 🔧 Improvements / 改善
- <英語の説明 / 日本語の説明> (#PR番号)

### 📝 Documentation / ドキュメント
- <英語の説明 / 日本語の説明> (#PR番号)

### 🧪 Tests / テスト
- <英語の説明 / 日本語の説明> (#PR番号)

### 🏗️ Infrastructure / インフラ
- <英語の説明 / 日本語の説明> (#PR番号)

### ⚠️ Breaking Changes / 破壊的変更
- <英語の説明 / 日本語の説明> (#PR番号)
```

## ルール

- 該当する変更がないカテゴリは省略する
- PR 番号がある場合はリンク付きで記載する
- 各エントリは `英語 / 日本語` の形式で日英併記する
