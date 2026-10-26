Toradex Verdin i.MX8MP / Torizon OS
==================================

This development profile boots supplied Torizon firmware and OS files unchanged
from a post-SPL entry. It skips ROM/SPL/DDR training. Optional CPU compatibility
controls reject unsupported DDR frequency-switch requests and deep powerdown;
other secure calls, including CPU_ON, continue into the original BL31.

Build Renode normally from the repository root, including its patched
infrastructure and tlib submodules. Then prepare and run a package::

    ./tools/imx8mp-torizon/prepare.sh torizon-Tezi.tar -o tools/imx8mp-torizon/artifacts/torizon-stock
    ./tools/imx8mp-torizon/run.sh tools/imx8mp-torizon/artifacts/torizon-stock

Preparation requires Docker and Python 3.11+ on Linux. It does not build firmware.
The supplied Verdin i.MX8MP Torizon 7.7 build 40 archive is the verified input.
Unknown firmware/layouts/hooks are rejected; arbitrary raw images and actual
preprovisioned images are not verified. Outputs must not already exist.

Connect to UART3 with ``telnet 127.0.0.1 12345``. The evaluation image uses
torizon/torizon and requires a password change. The emulated disk is opened
nonpersistently. No OS images are included in this repository.

The package contains a 3 GiB eMMC disk, boot0 and original extracted U-Boot/BL31
components, plus manifests recording their paths and SHA-256 hashes. U-Boot's
control DTB is appended as SPL would load it. A prepared environment selects the
board DTB, MMC device and console, retaining the supplied distro boot command.
``RENODE_KERNEL_ARGS`` adds optional tdxargs during preparation; by default no
cpuidle.off or maxcpus flags are added. ``RENODE_BOARD_SERIAL`` selects an explicit
virtual identity; otherwise a generated serial is recorded in boot0 metadata.
No Toradex factory config block is fabricated.

The native profile inserts fresh host entropy into the final in-memory
/chosen/rng-seed after U-Boot's FDT fixups and before Linux executes. The hook
survives reset and never changes persistent firmware or DTB files.

Counter/PLL models implement only the tested behavior. Deep suspend, DDR DVFS,
full clock propagation, graphics and guest networking are not complete. The
250 MIPS setting calibrates guest instruction progress; host boot takes minutes.
Other platforms retain their default CPU and storage capability settings.

Tests
------

Focused regressions and full OS acceptance are under
``tests/platforms/verdin-imx8mp-torizon/``. Run individual focused Robot suites
with ``renode-test``. ``torizon.robot`` boots the prepared default package,
handles the password change, verifies CPUs 0–3 and the normal OSTree root,
checks the active 30-second watchdog, then survives 65 guest seconds.
Environment variables RENODE_EMMC_IMAGE, RENODE_FIRMWARE_DIR and RENODE_BOOT0
can select another matching prepared package. Graphics/network/application
functionality is outside that acceptance gate.

The SIMD store and cross-thread invalidation tests have before/after
reproducers. The focused TLBI test also passes without its patch; stronger
fault-restoration coverage is still needed before treating it as a proven
reproducer for that change.

Validation in the development workspace:

* Pinned runtime: all 20 focused checks and full original-firmware acceptance
  passed, including virtual serial/hostname and 65 guest seconds of watchdog
  endurance. Full acceptance took about 10m27s.
* Current-upstream CPU backend, Infrastructure.dll and matching Renode.dll
  compiled successfully and passed the same 20 portable focused checks.
  These managed components were built against pinned runtime dependencies;
  this is not a clean build of every upstream dependency from source.

See ``PR_NOTES.rst`` for the dependency branches and publication order.
