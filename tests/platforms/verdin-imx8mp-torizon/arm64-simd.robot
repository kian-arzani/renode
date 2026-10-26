*** Test Cases ***
SIMD Single Structure Store Preserves Increment Across Store Locks
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/arm64.repl
    # A registered second CPU enables store-lock branches even when halted.
    Execute Command    machine LoadPlatformDescriptionFromString "cpu2: CPU.ARMv8A @ sysbus { cpuType: \\"cortex-a53\\"; genericInterruptController: gic; cpuId: 1 }"
    Execute Command    cpu2 IsHalted true
    Execute Command    cpu SetAvailableExceptionLevels false false
    Execute Command    cpu AssembleBlock 0x40000000 "mov x2, #0x300000; msr cpacr_el1, x2; isb; movi v2.2s, #0x11; movi v3.2s, #0x22; movi v4.2s, #0x33; movi v5.2s, #0x44; movz x0, #0x2000; movk x0, #0x4000, lsl #16; st4 {v2.s, v3.s, v4.s, v5.s}[0], [x0], #16; mov x3, #0x1234; b ." triple="arm64"
    Execute Command    cpu PC 0x40000000
    Execute Command    emulation RunFor "0.001"
    ${result}=    Execute Command    cpu GetRegister 3
    Should Contain    ${result}    1234
    ${result}=    Execute Command    cpu GetRegister 0
    Should Contain    ${result}    40002010
    ${result}=    Execute Command    sysbus ReadQuadWord 0x40002000
    Should Contain    ${result}    2200000011
    ${result}=    Execute Command    sysbus ReadQuadWord 0x40002008
    Should Contain    ${result}    4400000033
