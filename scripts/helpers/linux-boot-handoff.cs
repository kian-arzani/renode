// SPDX-License-Identifier: MIT
using System;
using System.Collections.Generic;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text;
using Antmicro.Renode.Core;
using Antmicro.Renode.Exceptions;
using Antmicro.Renode.Peripherals;
using Antmicro.Renode.Peripherals.CPU;

namespace Antmicro.Renode.Extensions
{
    // Firmware-service boundary: run after U-Boot's final FDT fixups, before
    // the first Linux instruction. No guest binary or persistent FDT is edited.
    public static class LinuxBootHandoff
    {
        public static void InstallLinuxEntropyHandoff(this ARMv8A cpu, ulong entry = 0x48200000)
        {
            if(installed.TryGetValue(cpu, out var previous))
            {
                if(previous.Value != entry) { throw new RecoverableException("Entropy handoff already installed at another entry"); }
                return;
            }
            installed.Add(cpu, new Entry(entry));
            cpu.AddHook(entry, (ignored, address) =>
            {
                var bus = cpu.GetMachine().SystemBus;
                var fdt = (ulong)cpu.GetRegister(0);
                // AArch64 Image magic, and x0 = physical, 8-byte-aligned FDT.
                if(bus.ReadDoubleWord(entry + 56) != 0x644d5241 || (fdt & 7) != 0
                    || fdt > ulong.MaxValue - 40 || !bus.IsMemory(fdt, cpu) || !bus.IsMemory(fdt + 39, cpu))
                {
                    throw new RecoverableException("Invalid ARM64 Linux entropy handoff");
                }
                var header = bus.ReadBytes(fdt, 40);
                var size = ReadBe(header, 4);
                if(ReadBe(header, 0) != 0xd00dfeed || size < 40 || size > 2 * 1024 * 1024
                    || fdt > ulong.MaxValue - size || !bus.IsMemory(fdt + size - 1, cpu))
                {
                    throw new RecoverableException("Invalid Linux handoff FDT bounds");
                }
                for(ulong offset = 0; offset < size; offset += 4096)
                {
                    if(!bus.IsMemory(fdt + offset, cpu)) { throw new RecoverableException("FDT crosses unmapped memory"); }
                }
                var blob = bus.ReadBytes(fdt, (int)size);
                var seed = new byte[64];
                try
                {
                    using(var rng = RandomNumberGenerator.Create()) { rng.GetBytes(seed); }
                    var result = WithSeed(blob, seed);
                    try { bus.WriteBytes(result, fdt); }
                    finally { Array.Clear(result, 0, result.Length); }
                }
                finally { Array.Clear(seed, 0, seed.Length); Array.Clear(blob, 0, blob.Length); }
            });
        }

        // Repack within the FDT's declared capacity. Never assume that memory
        // beyond totalsize is available; U-Boot reserves FDT fixup padding.
        public static byte[] WithSeed(byte[] blob, byte[] seed)
        {
            if(blob == null || blob.Length < 40 || seed == null || seed.Length != 64) { throw BadFdt(); }
            int total = Number(blob, 4), structure = Number(blob, 8), strings = Number(blob, 12);
            int reserve = Number(blob, 16), stringSize = Number(blob, 32), structureSize = Number(blob, 36);
            if(ReadBe(blob, 0) != 0xd00dfeed || total != blob.Length || ReadBe(blob, 20) < 17
                || ReadBe(blob, 24) > 17 || reserve < 40 || (reserve & 7) != 0
                || structure < reserve + 16 || (structure & 3) != 0
                || structureSize > total - structure || strings < structure + structureSize
                || stringSize > total - strings) { throw BadFdt(); }
            // The terminated memory reservation table must fit before structure.
            int r = reserve;
            while(r <= structure - 16 && (ReadBe(blob, r) != 0 || ReadBe(blob, r + 4) != 0
                || ReadBe(blob, r + 8) != 0 || ReadBe(blob, r + 12) != 0)) { r += 16; }
            if(r > structure - 16) { throw BadFdt(); }
            var names = new List<string>();
            int end = structure + structureSize, pos = structure, insert = -1, oldStart = -1, oldEnd = -1;
            bool finished = false;
            while(pos < end)
            {
                int start = pos, token = Number(blob, pos); pos += 4;
                if(token == 1)
                {
                    int zero = Array.IndexOf(blob, (byte)0, pos, end - pos);
                    if(zero < 0) { throw BadFdt(); }
                    names.Add(Encoding.ASCII.GetString(blob, pos, zero - pos));
                    if(names.Count == 1 && names[0] != "") { throw BadFdt(); }
                    pos = Align(zero + 1);
                    if(names.Count == 2 && names[1] == "chosen")
                    {
                        if(insert != -1) { throw BadFdt(); }
                        // FDT properties must precede child nodes.
                        insert = pos;
                    }
                }
                else if(token == 2)
                {
                    if(names.Count == 0) { throw BadFdt(); }
                    names.RemoveAt(names.Count - 1);
                }
                else if(token == 3)
                {
                    if(names.Count == 0 || pos > end - 8) { throw BadFdt(); }
                    int length = Number(blob, pos), name = Number(blob, pos + 4); pos += 8;
                    if(length > end - pos || name >= stringSize) { throw BadFdt(); }
                    int zero = Array.IndexOf(blob, (byte)0, strings + name, stringSize - name);
                    if(zero < 0) { throw BadFdt(); }
                    if(names.Count == 2 && names[1] == "chosen"
                        && Encoding.ASCII.GetString(blob, strings + name, zero - strings - name) == "rng-seed")
                    {
                        if(oldStart != -1) { throw BadFdt(); }
                        oldStart = start; oldEnd = Align(pos + length);
                    }
                    pos = Align(pos + length);
                }
                else if(token == 9)
                {
                    if(names.Count != 0) { throw BadFdt(); }
                    finished = true; break;
                }
                else if(token != 4) { throw BadFdt(); }
                if(pos > end) { throw BadFdt(); }
            }
            if(!finished || insert == -1) { throw BadFdt(); }
            // Reuse an existing string-table entry when refreshing a seed.
            var propertyName = Encoding.ASCII.GetBytes("rng-seed\0");
            int nameOffset = -1;
            for(int n = 0; n <= stringSize - propertyName.Length; n++)
            {
                bool matches = true;
                for(int c = 0; c < propertyName.Length; c++) { if(blob[strings + n + c] != propertyName[c]) { matches = false; break; } }
                if(matches) { nameOffset = n; break; }
            }
            int addedStrings = nameOffset == -1 ? propertyName.Length : 0;
            if(nameOffset == -1) { nameOffset = stringSize; }
            int cutStart = oldStart == -1 ? insert : oldStart, cutEnd = oldStart == -1 ? insert : oldEnd;
            int newSize = structureSize + 76 - (cutEnd - cutStart);
            int newStrings = structure + newSize;
            if(newSize < 0 || newStrings > total - stringSize - addedStrings)
            { throw new RecoverableException("FDT has no padding for Linux entropy handoff"); }
            var property = new byte[76];
            WriteBe(property, 0, 3); WriteBe(property, 4, 64); WriteBe(property, 8, (uint)nameOffset);
            Buffer.BlockCopy(seed, 0, property, 12, 64);
            var output = new byte[total];
            Buffer.BlockCopy(blob, 0, output, 0, structure);
            Buffer.BlockCopy(blob, structure, output, structure, cutStart - structure);
            Buffer.BlockCopy(property, 0, output, cutStart, property.Length);
            Buffer.BlockCopy(blob, cutEnd, output, cutStart + property.Length, end - cutEnd);
            Buffer.BlockCopy(blob, strings, output, newStrings, stringSize);
            if(addedStrings != 0) { Buffer.BlockCopy(propertyName, 0, output, newStrings + stringSize, addedStrings); }
            WriteBe(output, 12, (uint)newStrings); WriteBe(output, 32, (uint)(stringSize + addedStrings));
            WriteBe(output, 36, (uint)newSize);
            Array.Clear(property, 0, property.Length);
            return output;
        }

        private static int Align(int n) { return checked((n + 3) & ~3); }
        private static int Number(byte[] b, int p)
        {
            uint n = ReadBe(b, p); if(n > int.MaxValue) { throw BadFdt(); } return (int)n;
        }
        private static uint ReadBe(byte[] b, int p)
        {
            if(p < 0 || p > b.Length - 4) { throw BadFdt(); }
            return ((uint)b[p] << 24) | ((uint)b[p + 1] << 16) | ((uint)b[p + 2] << 8) | b[p + 3];
        }
        private static void WriteBe(byte[] b, int p, uint n)
        { b[p] = (byte)(n >> 24); b[p + 1] = (byte)(n >> 16); b[p + 2] = (byte)(n >> 8); b[p + 3] = (byte)n; }
        private static RecoverableException BadFdt() { return new RecoverableException("Malformed or unsupported Linux handoff FDT"); }
        private static readonly ConditionalWeakTable<ARMv8A, Entry> installed = new ConditionalWeakTable<ARMv8A, Entry>();
        private sealed class Entry
        {
            public Entry(ulong value) { Value = value; }
            public readonly ulong Value;
        }
    }
}
