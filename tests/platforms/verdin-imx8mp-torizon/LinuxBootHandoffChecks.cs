// SPDX-License-Identifier: MIT
using System;
using System.Linq;
using System.Text;
using Antmicro.Renode.Core;
using Antmicro.Renode.Extensions;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.CPU;

namespace Antmicro.Renode.Testing
{
    public static class LinuxBootHandoffChecks
    {
        public static void PrepareEntropyFixture(this ARMv8A cpu)
        {
            var bus = cpu.GetMachine().SystemBus;
            bus.WriteBytes(Fixture(), 0x40008000);
            bus.WriteDoubleWord(0x40001000, 0x14000001); // b entry+4
            bus.WriteDoubleWord(0x40001004, 0x14000000); // b .
            bus.WriteDoubleWord(0x40001038, 0x644d5241);
            cpu.SetRegister(0, 0x40008000);
            cpu.PC = 0x40001000;
        }

        public static string CheckEntropyFixture(this ARMv8A cpu)
        {
            var blob = cpu.GetMachine().SystemBus.ReadBytes(0x40008000, 1024);
            int structure = Read(blob, 8), strings = Read(blob, 12);
            if(!Encoding.ASCII.GetString(blob, strings, Read(blob, 32)).Contains("bootargs\0rng-seed\0")) { throw new Exception("Missing seed property name"); }
            // New properties precede any child nodes.
            int prop = structure + 8 + 12;
            if(Read(blob, prop) != 3 || Read(blob, prop + 4) != 64) { throw new Exception("Invalid seed property"); }
            var seed = blob.Skip(prop + 12).Take(64).ToArray();
            if(seed.All(x => x == 0) || (lastSeed != null && seed.SequenceEqual(lastSeed))) { throw new Exception("Missing or repeated entropy"); }
            lastSeed = seed;
            return "fresh entropy, valid FDT";
        }

        public static string CheckEntropyFdtEditing(this ARMv8A cpu)
        {
            var input = Fixture(); var saved = input.ToArray();
            var seed = Enumerable.Range(1, 64).Select(x => (byte)x).ToArray();
            var first = LinuxBootHandoff.WithSeed(input, seed);
            if(!input.SequenceEqual(saved)) { throw new Exception("Input mutated"); }
            var second = LinuxBootHandoff.WithSeed(first, seed.Reverse().ToArray());
            if(Read(first, 36) != Read(second, 36)) { throw new Exception("Duplicated property"); }
            if(!Encoding.ASCII.GetString(second).Contains("keep=1\0")) { throw new Exception("Lost bootargs"); }
            var withChild = LinuxBootHandoff.WithSeed(Fixture(true), seed);
            if(Read(withChild, 84) != 3 || Read(withChild, 180) != 1 || Read(withChild, 192) != 2
                || Read(second, 32) != Read(first, 32)) { throw new Exception("Invalid node ordering or growing string table"); }
            int rejected = 0;
            var badMagic = saved.ToArray(); badMagic[0] = 0;
            var badOffset = saved.ToArray(); Write(badOffset, 8, 0x7fffffff);
            var truncated = saved.Take(60).ToArray();
            var noSpace = saved.Take(Read(saved, 12) + Read(saved, 32)).ToArray(); Write(noSpace, 4, noSpace.Length);
            var noChosen = saved.ToArray(); noChosen[76] = (byte)'x';
            foreach(var bad in new[] { badMagic, badOffset, truncated, noSpace, noChosen })
            {
                try { LinuxBootHandoff.WithSeed(bad, seed); }
                catch(Antmicro.Renode.Exceptions.RecoverableException) { rejected++; }
            }
            if(rejected != 5) { throw new Exception("Accepted malformed or undersized FDT"); }
            return "preserved bootargs; replaced seed; rejected 5 invalid FDTs";
        }

        private static byte[] Fixture(bool child = false)
        {
            var b = new byte[1024];
            Write(b, 0, unchecked((int)0xd00dfeed)); Write(b, 4, b.Length);
            Write(b, 8, 64); Write(b, 12, 116); Write(b, 16, 40);
            Write(b, 20, 17); Write(b, 24, 16); Write(b, 32, 9); Write(b, 36, 52);
            Write(b, 64, 1); // root, padded empty name
            Write(b, 72, 1); Encoding.ASCII.GetBytes("chosen\0").CopyTo(b, 76);
            Write(b, 84, 3); Write(b, 88, 7); Write(b, 92, 0);
            Encoding.ASCII.GetBytes("keep=1\0").CopyTo(b, 96);
            Write(b, 104, 2); Write(b, 108, 2); Write(b, 112, 9);
            Encoding.ASCII.GetBytes("bootargs\0").CopyTo(b, 116);
            if(child)
            {
                Write(b, 12, 132); Write(b, 36, 68);
                Array.Clear(b, 104, 40);
                Write(b, 104, 1); Encoding.ASCII.GetBytes("child\0").CopyTo(b, 108);
                Write(b, 116, 2); Write(b, 120, 2); Write(b, 124, 2); Write(b, 128, 9);
                Encoding.ASCII.GetBytes("bootargs\0").CopyTo(b, 132);
            }
            return b;
        }
        private static int Read(byte[] b, int p) { return (b[p] << 24) | (b[p+1] << 16) | (b[p+2] << 8) | b[p+3]; }
        private static void Write(byte[] b, int p, int n) { b[p]=(byte)(n>>24); b[p+1]=(byte)(n>>16); b[p+2]=(byte)(n>>8); b[p+3]=(byte)n; }
        private static byte[] lastSeed;
    }
}
