# フロントエンドチェック項目

| チェック項目 | 基準 |
|------------|------|
| **Atomic Design** | 下記ルールに準拠しているか |
| **Composables 分離** | ロジックが composables（hooks）に切り出されているか。コンポーネントにビジネスロジックが混在していないか |
| **命名規則** | コンポーネント名、props、emits、変数名が一貫しているか |
| **責務分担** | 各コンポーネントが単一責任か。肥大化したコンポーネントがないか |
| **状態管理** | グローバル状態とローカル状態が適切に使い分けられているか |
| **型定義** | 適切に行われているか。`any` の乱用がないか |
| **アクセシビリティ (a11y)** | alt 属性、aria ラベル、キーボード操作対応が適切か |
| **バンドルサイズ** | 不要な依存や tree-shaking できていない箇所がないか |

## Atomic Design ルール

下位レイヤーのみインポート可能。上位レイヤーをインポートしてはならない。

| レイヤー | Prefix | インポート可能 | 役割 |
|---------|--------|---------------|------|
| Atoms | A | types のみ | 最小単位の UI コンポーネント |
| Molecules | M | Atoms | 汎用的な複合コンポーネント（ドメイン知識なし） |
| Organisms | O | Molecules, Atoms | ドメイン固有のコンポーネント |
| Templates | T | Organisms, Molecules, Atoms | ページの骨格 |
| Pages | - | Templates のみ | ルーティングとデータ取得 |
| Layouts | - | Organisms のみ | 共通レイアウト |

**命名規則:**
- Atoms: `A` + PascalCase（例: `AButton`, `AInput`）
- Molecules: `M` + PascalCase（例: `MModal`, `MCard`）
- Organisms: `O` + PascalCase（例: `OTaskCard`, `ODocumentTree`）
- Templates: `T` + PascalCase + `Page`（例: `TLoginPage`, `TTasksPage`）

**HTML の atoms 化:**
- すべての HTML 要素を Atoms コンポーネントとして定義する
- 素の HTML タグを直接使わず、対応する Atoms を使用する

**許容される例外:**
- 再帰コンポーネント（例: `ODocumentTree` → `ODocumentTreeItem`）
- Organisms 内の Toolbar 系（例: `ODocumentEditor` → `ODocumentToolbar`）
