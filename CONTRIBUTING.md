# Contributing to Uplift

Uplift is an operational AI-agent stack for sovereign edge deployment, with a focus on **causal measurement** of how much AI actually assists human operators in the field.

Before contributing, please review:
- [README.md](README.md) — Stack architecture and setup.
- [docs/methodology.md](docs/methodology.md) — The core measurement philosophy.
- [docs/planning/roadmap.md](docs/planning/roadmap.md) — Project milestones.

## How to Help

We prioritize contributions that improve the reliability and measurability of the stack:

- **Operational improvements**: Better recovery, health checks, and observability scripts for the Jetson Orin.
- **Methodology & Trace Schema**: Enhancements to the `trace` format or the `uplift/` analysis module.
- **Bug reports**: Specifically for the Jetson stack, routing bugs, or the verification harness.
- **Experience reports**: Data or observations from running similar high-stakes deployments.

## Developing with the ZeroClaw Submodule

Uplift uses a fork of the `zeroclaw` daemon in `stack/zeroclaw` to maintain specific Jetson-compatible build profiles and routing fixes.

### Updating ZeroClaw
To pull in new upstream releases from `zeroclaw-labs/zeroclaw`:

```bash
cd stack/zeroclaw
git checkout uplift-core
git fetch upstream
git merge <version-tag>
# Resolve conflicts in Dockerfiles or build scripts
git push origin uplift-core
```

## Pull Request Guidelines

1. **Start with an Issue**: Open a discussion for any non-trivial changes first.
2. **Focus on Measurement**: If you're changing the agent or tool schema, explain how it affects (or enables) downstream causal analysis.
3. **Verify Changes**: Run `./scripts/verify_stack.sh` if your changes affect the runtime path.
4. **Conventional Commits**: Use `feat:`, `fix:`, `docs:`, etc. Match the style of the existing `git log`.

## Scope

We are **not** currently looking for:
- Framework features unrelated to the operator-uplift mission.
- Purely synthetic benchmark integrations.
- Large-scale refactors without a clear functional win.

## Code of Conduct

Be specific, assume good faith, and keep the end users (field operators and volunteers) in mind.

## License

Updates and contributions are licensed under the Apache License, Version 2.0.

