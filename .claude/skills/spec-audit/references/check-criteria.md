# 検知観点と重大度基準

## 検知カテゴリ

| カテゴリ | 検知内容 | 検索手段 |
|---------|---------|---------|
| **仕様 vs 実装** | 仕様書に定義された機能・エンドポイント・振る舞いが実装に存在するか | Explore / Grep / Glob |
| **TODO/FIXME** | `TODO`, `FIXME`, `HACK`, `XXX`, `TEMP` コメント | Grep |
| **スキップテスト** | skip/pending/xit 等でスキップされたテスト | Grep |
| **API スキーマ** | OpenAPI/Swagger 定義に対応するハンドラが存在するか | Grep / Glob |
| **設定・環境変数** | 仕様書記載の設定項目が実装で使われているか | Grep |
| **データモデル** | ER 図・テーブル定義がマイグレーション/モデルと一致するか | Grep / Read |
| **CLI 引数** | 仕様書記載のコマンド・フラグが実装に存在するか | Grep |

## スキップテストの検索パターン

| 言語 | パターン |
|------|---------|
| JS/TS | `it.skip`, `describe.skip`, `test.skip`, `xit`, `xdescribe`, `xtest` |
| Go | `t.Skip` |
| Python | `@pytest.mark.skip`, `@unittest.skip`, `self.skipTest`, `pytest.skip()` |
| Ruby | `skip`, `pending` |
| Java | `@Disabled`, `@Ignore` |
| Rust | `#[ignore]` |

## TODO マーカーパターン

`TODO`, `FIXME`, `HACK`, `XXX`, `TEMP`, `WORKAROUND`

## 重大度基準

| 重大度 | 基準 | Issue 作成 |
|-------|------|-----------|
| 🔴 重大 | 仕様書に定義された機能が未実装、またはスキーマ定義済みのエンドポイントにハンドラがない | 必須 |
| 🟠 重要 | 仕様の一部が不完全に実装、FIXME/HACK で仮実装のまま、テストが skip で無効化 | 必須 |
| 🟡 注意 | TODO コメントが残存、仕様と実装に軽微な差異 | 推奨 |
| 🟢 軽微 | 設定値のデフォルト差異、表記ゆれ | 任意 |
