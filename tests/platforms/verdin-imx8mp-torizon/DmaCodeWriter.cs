// SPDX-License-Identifier: MIT
// Test fixture: emulate DMA writing to a page another CPU is executing.
using Antmicro.Renode.Core;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.Bus;
namespace Antmicro.Renode.Peripherals.TestMocks
{
    public class DmaCodeWriter : IDoubleWordPeripheral, IKnownSize
    {
        public DmaCodeWriter(IMachine machine) { this.machine = machine; }
        public void WriteDoubleWord(long offset, uint value) { machine.SystemBus.WriteDoubleWord(0x40001004, value); }
        public uint ReadDoubleWord(long offset) { return 0; }
        public void Reset() { }
        public long Size => 4;
        private readonly IMachine machine;
    }
}
