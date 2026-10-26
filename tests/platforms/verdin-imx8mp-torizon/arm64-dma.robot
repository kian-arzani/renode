*** Test Cases ***
DMA Code Invalidation Does Not Corrupt Another CPU Active Block
    Execute Command    include @${CURDIR}/DmaCodeWriter.cs
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/arm64.repl
    Execute Command    machine LoadPlatformDescriptionFromString "cpu2: CPU.ARMv8A @ sysbus { cpuType: \\"cortex-a53\\"; genericInterruptController: gic; cpuId: 1 }"
    Execute Command    machine LoadPlatformDescriptionFromString "dma: TestMocks.DmaCodeWriter @ sysbus 0x20000000"
    Execute Command    cpu SetAvailableExceptionLevels false false
    Execute Command    cpu2 SetAvailableExceptionLevels false false
    Execute Command    cpu AssembleBlock 0x40000000 "movz w0, #0x205f; movk w0, #0xd503, lsl #16; mov x1, #0x20000000; again: str w0, [x1]; add x6, x6, #1; b again" triple="arm64"
    Execute Command    cpu2 AssembleBlock 0x40001000 "add x7, x7, #1; wfe; b .-8" triple="arm64"
    Execute Command    cpu PC 0x40000000
    Execute Command    cpu2 PC 0x40001000
    Execute Command    emulation RunFor "0.05"
    ${value}=    Execute Command    cpu GetRegister 6
    Should Be True    int($value.strip(), 16) > 0
    ${value}=    Execute Command    cpu2 GetRegister 7
    Should Be True    int($value.strip(), 16) > 0
