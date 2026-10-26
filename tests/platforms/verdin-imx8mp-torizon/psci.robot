*** Test Cases ***
Powerdown Can Be Rejected While Other SMCs Reach Firmware
    Execute Command    include @scripts/helpers/imx8mp-power-state-compatibility.cs
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/arm64.repl
    Execute Command    cpu EnableUbootMode
    Execute Command    cpu RejectUnmodeledPowerDown
    # Enter nonsecure AArch64 EL1h through EL3, as the real BL31 does.
    Execute Command    cpu AssembleBlock 0x40001000 "mov x0, #0x40000000; msr vbar_el3, x0; mov x0, #0x80000000; msr hcr_el2, x0; mov x0, #0x501; msr scr_el3, x0; mov x0, #0x3c5; msr spsr_el3, x0; movz x0, #0x100; movk x0, #0x4000, lsl #16; msr elr_el3, x0; eret" triple="arm64"
    Execute Command    cpu AssembleBlock 0x40000100 "movz x0, #1; movk x0, #0xc400, lsl #16; movz x1, #0x33; movk x1, #1, lsl #16; smc #0; mov x5, x0; movz x0, #0x8200, lsl #16; smc #0; b ." triple="arm64"
    # Stand-in secure monitor records that an unrelated vendor call arrived.
    Execute Command    cpu AssembleBlock 0x40000400 "mov x6, #0x55; mov x0, #0; eret" triple="arm64"
    Execute Command    cpu PC 0x40001000
    Execute Command    emulation RunFor "0.001"
    ${result}=    Execute Command    cpu GetRegister 5
    Should Contain    ${result.lower()}    fffffffffffffffe
    ${result}=    Execute Command    cpu GetRegister 6
    Should Contain    ${result}    55

Powerdown Rejection Can Wait Without Claiming Resume
    Execute Command    include @scripts/helpers/imx8mp-power-state-compatibility.cs
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/arm64.repl
    Execute Command    cpu EnableUbootMode
    Execute Command    cpu RejectUnmodeledPowerDown true true
    Execute Command    cpu AssembleBlock 0x40001000 "mov x0, #0x40000000; msr vbar_el3, x0; mov x0, #0x80000000; msr hcr_el2, x0; mov x0, #0x501; msr scr_el3, x0; mov x0, #0x3c5; msr spsr_el3, x0; movz x0, #0x100; movk x0, #0x4000, lsl #16; msr elr_el3, x0; eret" triple="arm64"
    Execute Command    cpu AssembleBlock 0x40000100 "movz x0, #1; movk x0, #0xc400, lsl #16; movz x1, #0x33; movk x1, #1, lsl #16; smc #0; mov x5, x0; movz x0, #0x8200, lsl #16; smc #0; b ." triple="arm64"
    Execute Command    cpu AssembleBlock 0x40000400 "mov x6, #0x55; mov x0, #0; eret" triple="arm64"
    Execute Command    cpu PC 0x40001000
    Execute Command    emulation RunFor "0.001"
    # The unsupported request has not returned to the guest yet.
    ${pc}=    Execute Command    cpu PC
    Should Contain    ${pc.lower()}    40000114
    ${result}=    Execute Command    cpu GetRegister 5
    Should Be Equal As Strings    ${result.strip()}    0x0
    # A pending IRQ wakes WFI despite the guest masking exception delivery.
    Execute Command    cpu OnGPIO 0 true
    Execute Command    emulation RunFor "0.001"
    ${result}=    Execute Command    cpu GetRegister 5
    Should Contain    ${result.lower()}    fffffffffffffffe
    ${result}=    Execute Command    cpu GetRegister 6
    Should Contain    ${result}    55

Standby Suspend Still Reaches Native Firmware For Both Calling Conventions
    Execute Command    include @scripts/helpers/imx8mp-power-state-compatibility.cs
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/arm64.repl
    Execute Command    cpu EnableUbootMode
    Execute Command    cpu RejectUnmodeledPowerDown true true
    Execute Command    cpu AssembleBlock 0x40001000 "mov x0, #0x40000000; msr vbar_el3, x0; mov x0, #0x80000000; msr hcr_el2, x0; mov x0, #0x501; msr scr_el3, x0; mov x0, #0x3c5; msr spsr_el3, x0; movz x0, #0x100; movk x0, #0x4000, lsl #16; msr elr_el3, x0; eret" triple="arm64"
    # Both calls have the original-format POWERDOWN bit clear.
    Execute Command    cpu AssembleBlock 0x40000100 "movz x0, #1; movk x0, #0x8400, lsl #16; mov x1, #0x33; smc #0; mov x5, x0; movz x0, #1; movk x0, #0xc400, lsl #16; mov x1, #0x33; smc #0; mov x7, x0; b ." triple="arm64"
    Execute Command    cpu AssembleBlock 0x40000400 "mov x0, #0x55; eret" triple="arm64"
    Execute Command    cpu PC 0x40001000
    Execute Command    emulation RunFor "0.001"
    ${result}=    Execute Command    cpu GetRegister 5
    Should Contain    ${result}    55
    ${result}=    Execute Command    cpu GetRegister 7
    Should Contain    ${result}    55
