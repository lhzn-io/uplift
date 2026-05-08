# Contributing to Uplift Core

**Status:** Stub. Will expand as the project grows.

Thanks for your interest. Uplift Core is an operational AI-agent stack
for sovereign edge deployment, with a strong methodological commitment
to *causal* evaluation of how much the stack levers up real human
operators in the field. Before contributing, please skim:

- [`README.md`](README.md) — what the stack is and how to run it
- [`docs/methodology.md`](docs/methodology.md) — the methodological backbone (why we evaluate causally, what the trace schema must support, and what the anchor-deployment Key Metrics will be)
- [`docs/planning/roadmap.md`](docs/planning/roadmap.md) — what's shipped, what's next, and the one-year success bar

## What we welcome

- **Bug reports and reproductions** for the Jetson Orin stack, zeroclaw / zeroclaw / zeroclaw integration, inference provider routing, and the verification harness.
- **Operational improvements** to the recovery, verification, and observability scripts.
- **Methodology contributions** — issues or PRs against `docs/methodology.md`, the trace schema, or the (forthcoming) `uplift/` module. If you work in causal ML, uplift modeling, or human–AI teaming evaluation, we especially want to hear from you.
- **Field deployment experience reports** from anyone running similar stacks in low-resource, high-stakes operational settings.

## Developing with the ZeroClaw Submodule (Fork)

Because we require specific modifications for the Jetson Orin edge environment (faster build profiles, custom Docker configurations, and specific routing bug fixes like #5815), we use a **hard fork** of the upstream `zeroclaw` daemon. The submodule in `stack/zeroclaw` points to the `uplift-core` branch of our fork (`lhzn-io/zeroclaw`).

### Pulling in new upstream ZeroClaw releases

When the upstream `zeroclaw-labs/zeroclaw` repository releases a new version, you must carefully merge it into our custom `uplift-core` branch to ensure we don't drop our Jetson-specific fixes.

```bash
# 1. Enter the submodule
cd stack/zeroclaw

# 2. Add the upstream remote (if you haven't already)
git remote add upstream https://github.com/zeroclaw-labs/zeroclaw.git

# 3. Fetch the latest upstream changes and tags
git fetch upstream

# 4. Ensure you are on our custom branch
git checkout uplift-core

# 5. Merge the new upstream release tag (e.g., v0.8.0)
git merge v0.8.0

# 6. Resolve any conflicts in our modified files. Pay special attention to:
#    - Dockerfile (we use `release-fast` instead of `release`)
#    - .dockerignore (we whitelist `!target/release-fast/zeroclaw`)
#    - crates/zeroclaw-config/src/schema.rs (we have a bypass for the fallback override)

# 7. Push the updated fork back to our organization
git push origin uplift-core

# 8. Return to the root uplift repository and commit the submodule pointer bump
cd ../..
git add stack/zeroclaw
git commit -m "chore: bump zeroclaw submodule to v0.8.0"
```

## What to do before opening a PR

1. Open an issue first for anything non-trivial. We would rather align on direction than receive a polished PR we cannot merge.
2. For changes to the agent trace schema or the `uplift/` module, include a short note on the methodological implications — how does this change preserve (or improve) our ability to do causal evaluation downstream.
3. Run `./scripts/verify_stack.sh` if your change touches the runtime path, and include the result.
4. Keep commits focused. Match the style of recent commits (`git log`).

## What we are not looking for (yet)

- New agent framework features that do not connect to the operator-uplift mission.
- Refactors for their own sake.
- Benchmark scores on synthetic agent benchmarks. We care about causal effects on real operators, not aggregate win-rates.

## Code of conduct

Be kind, be specific, assume good faith, and remember that the people on the other end of this project are trying to deploy AI to help operators on offshore platforms and food bank volunteers. Keep that audience in mind.

## License

By contributing, you agree that your contributions will be licensed under the Apache License, Version 2.0 (see [`LICENSE`](LICENSE) and [`NOTICE`](NOTICE)). Uplift Core is a project of Long Horizon Observatory.
