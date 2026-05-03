# Detection Criteria and Severity

## Detection Categories

| Category | What to Detect | Search Method |
|----------|---------------|---------------|
| **Spec vs Implementation** | Features/endpoints/behaviors defined in spec but missing in code | Explore / Grep / Glob |
| **TODO/FIXME** | `TODO`, `FIXME`, `HACK`, `XXX`, `TEMP` comments | Grep |
| **Skipped Tests** | Tests disabled via skip/pending/xit etc. | Grep |
| **API Schema** | OpenAPI/Swagger-defined endpoints without handlers | Grep / Glob |
| **Config/Env Vars** | Config items documented in spec but unused in code | Grep |
| **Data Models** | ER diagrams/table definitions not matching migrations/models | Grep / Read |
| **CLI Arguments** | Commands/flags documented in spec but missing in code | Grep |

## Skipped Test Patterns

| Language | Patterns |
|----------|----------|
| JS/TS | `it.skip`, `describe.skip`, `test.skip`, `xit`, `xdescribe`, `xtest` |
| Go | `t.Skip` |
| Python | `@pytest.mark.skip`, `@unittest.skip`, `self.skipTest`, `pytest.skip()` |
| Ruby | `skip`, `pending` |
| Java | `@Disabled`, `@Ignore` |
| Rust | `#[ignore]` |

## TODO Marker Patterns

`TODO`, `FIXME`, `HACK`, `XXX`, `TEMP`, `WORKAROUND`

## Severity Levels

| Severity | Criteria | Issue Creation |
|----------|----------|----------------|
| 🔴 Critical | Feature defined in spec is not implemented, or schema-defined endpoint has no handler | Required |
| 🟠 High | Spec partially implemented, FIXME/HACK with temporary implementation, tests disabled via skip | Required |
| 🟡 Medium | TODO comments remaining, minor spec-implementation differences | Recommended |
| 🟢 Low | Default value differences, naming inconsistencies | Optional |
