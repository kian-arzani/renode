// SPDX-License-Identifier: MIT
using Antmicro.Renode.Peripherals.CPU;

namespace Antmicro.Renode.Extensions
{
    public static class PowerStateCompatibility
    {
        // Post-SPL startup lacks SPL's DDR timing table. Reject only the
        // three frequency-switch selectors; count/info queries stay native.
        public static void RejectUnmodeledDDRFrequencySwitch(this ARMv8A cpu, bool enabled = true)
        {
            cpu.SetSMCRejection(enabled ? 0xc2000004u : 0u, 2);
        }

        // Requires the accompanying tlib and infrastructure compatibility patches.
        public static void RejectUnmodeledPowerDown(this ARMv8A cpu, bool enabled = true, bool waitForInterrupt = false)
        {
            cpu.PSCIEmulationMethod = (BaseARMv8.PSCIConduitEmulationMethod)(enabled ? (waitForInterrupt ? 4 : 3) : 0);
        }
    }
}
