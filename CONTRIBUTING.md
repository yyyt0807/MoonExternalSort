# Contributing

Keep the stable-order, resource-budget and manifest-commit invariants explicit in every change. New key types require ordering tests in ascending and descending modes. Storage changes require failure-boundary tests. Parser changes require malformed, oversized and boundary-split inputs.

Run before submitting:

```sh
moon check --target all --deny-warn
moon test --target all --deny-warn
moon fmt --check
moon info
```

Do not add copied implementations, fixtures or datasets without documenting their origin, license and exact use in `THIRD_PARTY_NOTICES.md`.
