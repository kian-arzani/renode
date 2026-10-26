*** Test Cases ***
ARM64 Delivers A Translation Fault After TLBI
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/arm64.repl
    Execute Command    cpu SetAvailableExceptionLevels false false
    Execute Command    cpu AssembleBlock 0x40000000 "mov x0, #0x80000000; tlbi vmalle1; ldr x1, [x0]; b ." triple="arm64"
    Execute Command    cpu AssembleBlock 0x40000a00 "mov x3, #0x1234; b ." triple="arm64"
    Execute Command    cpu AssembleBlock 0x40000800 "mov x3, #0x1234; b ." triple="arm64"
    Execute Command    sysbus WriteQuadWord 0x40010008 0x40000401
    Execute Command    cpu SetSystemRegisterValue "ttbr0_el1" 0x40010000
    Execute Command    cpu SetSystemRegisterValue "tcr_el1" 0x19
    Execute Command    cpu SetSystemRegisterValue "mair_el1" 0xff
    Execute Command    cpu SetSystemRegisterValue "vbar_el1" 0x40000800
    Execute Command    cpu PC 0x40000000
    Execute Command    cpu SetSystemRegisterValue "sctlr_el1" 0x30d00801
    Execute Command    emulation RunFor "0.001"
    ${value}=    Execute Command    cpu GetRegister 3
    Should Contain    ${value}    1234
