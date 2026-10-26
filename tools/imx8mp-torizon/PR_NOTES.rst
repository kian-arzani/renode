Review and publication
=======================

This integration spans three repositories. Each local checkout has branch
``fix/verdin-imx8mp-torizon``:

* antmicro/tlib: TLBI state preservation, SIMD temporary lifetime and opt-in
  native SMC restrictions.
* renode/renode-infrastructure: safe code invalidation, watchdog deadlines,
  secondary CPU startup, optional storage DMA capability, counter/PLL models
  and the managed SMC controls.
* renode/renode: board description, native firmware boot script, entropy helper,
  portable regressions and image preparation/run tools.

The integration branch points dependency URLs at kian-arzani's forks so a fresh
clone can retrieve the new submodule commits. Publish tlib first, infrastructure
second, and Renode last. When upstreaming, submit the dependency fixes to their
own repositories and update the parent pointers/URLs after those changes merge.
The fork URL changes are integration plumbing, not proposed hardware behavior.

Review the opt-in compatibility modes separately from correctness fixes. DDR
switching returns SMC_UNK; CPU_SUSPEND powerdown waits for an interrupt and
returns INVALID_PARAMETERS. Neither reports a successful unsupported hardware
transition. Firmware binaries are not modified. Full DDR/power-controller
emulation remains out of scope.

Follow the repository's CONTRIBUTING.md for issue reports, commit conventions
and the CLA. No issue, pull request or remote publication was created by the
assistant; the user is handling pushes.
