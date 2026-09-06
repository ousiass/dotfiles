# impact-map — 変更ファイルから影響 spec を絞る

PR では全量を回さず、変更に影響される spec だけを実行する。フェーズ0 で採用と回答した場合のみ実施する。

**採用の目安**: 全量が 10 分を超え、かつ spec と機能ドメインの対応が明確に取れる場合。spec 数が少ないうちは全量実行のほうが安全で運用も楽。

## ルール表

```json
// e2e/impact-map.json
{
  "rules": [
    { "pattern": "src/features/document/approval/**", "specs": ["specs/document/approve.spec.ts"] },
    { "pattern": "src/features/document/**",          "specs": ["specs/document/**"] },
    { "pattern": "src/components/ui/**",              "specs": ["**"] },
    { "pattern": "supabase/migrations/**",            "specs": ["**"] }
  ]
}
```

## 評価戦略

| 戦略 | 内容 |
|---|---|
| **first-match** | 具体的なルールを先に、広いルールを後に並べ、最初に一致したものを採用する |
| **fail-open** | どのルールにも一致しないファイルが1つでもあれば**全量実行**にフォールバックする |
| **API 上限時も fail-open** | GitHub API の変更ファイル取得が上限（3000件）に達したら全量実行 |

絞り込みのミスは「リグレッションの見逃し」に直結する。迷ったら広く実行する側に倒す。

## resolver とそのテスト

```ts
// e2e/impact/resolve.ts
export function resolveSpecs(changed: string[], rules: Rule[]): string[] | "all" {
  const specs = new Set<string>();
  for (const file of changed) {
    const rule = rules.find((r) => minimatch(file, r.pattern));
    if (!rule) return "all";                    // fail-open
    if (rule.specs.includes("**")) return "all";
    rule.specs.forEach((s) => specs.add(s));
  }
  return [...specs];
}
```

**resolver のユニットテストを必ず書き、毎回実行する。** 判定ロジックが退行すると、テストが「静かに実行されなくなる」という最悪の壊れ方をする。

## CI への組み込み

```yaml
      - name: 影響 spec の解決
        id: impact
        run: echo "specs=$(bun run e2e:impact --base=${{ github.event.pull_request.base.sha }})" >> $GITHUB_OUTPUT

      - run: bunx playwright test --project=${{ matrix.project }} ${{ steps.impact.outputs.specs }}
```

## 可視化

判定の透明性が無いと誰も信用しない。以下を必ず出す。

- **Job Summary**: どの変更ファイルがどのルールに当たり、どの spec を実行したか（`$GITHUB_STEP_SUMMARY` に書く）
- **全量フォールバックした場合はその理由を明示**（非該当ファイル名 / API 上限）
- main へのマージ時は impact-map を使わず**必ず全量実行**する
