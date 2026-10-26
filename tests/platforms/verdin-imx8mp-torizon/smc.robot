*** Test Cases ***
DDR Switch Selectors Return Unsupported Without Entering Firmware
    FOR    ${selector}    IN    0x0    0x1    0x2
        Create Native Monitor
        Execute Command    cpu SetSMCRejection 0xc2000004 2
        Call Secure Monitor    0xc200    4    ${selector}
        Assert Register    5    0xffffffffffffffff
        Assert Register    6    0x0
        # The filter preserves arguments and the remaining general registers.
        Assert Register    1    ${selector}
        Assert Register    7    0x77
        Execute Command    mach clear
    END

Queries And Unrelated Calls Still Enter Firmware
    FOR    ${selector}    IN    3    0x10    0x11    0xffff
        Create Native Monitor
        Execute Command    cpu SetSMCRejection 0xc2000004 2
        Call Secure Monitor    0xc200    4    ${selector}
        Assert Register    5    0x55
        Assert Register    6    0x1
        Execute Command    mach clear
    END
    # The 32-bit convention and adjacent function IDs must not match.
    FOR    ${high}    ${low}    IN    0x8200    4    0xc200    5    0xc400    3
        Create Native Monitor
        Execute Command    cpu SetSMCRejection 0xc2000004 2
        Call Secure Monitor    ${high}    ${low}    0
        Assert Register    5    0x55
        Assert Register    6    0x1
        Execute Command    mach clear
    END

Rejection Is Opt In And Can Be Disabled After Translation
    Create Native Monitor
    Call Secure Monitor    0xc200    4    0
    Assert Register    5    0x55
    Execute Command    cpu SetSMCRejection 0xc2000004 2
    Call Secure Monitor    0xc200    4    0
    Assert Register    5    0xffffffffffffffff
    Execute Command    cpu SetSMCRejection 0 0
    Call Secure Monitor    0xc200    4    0
    Assert Register    5    0x55

*** Keywords ***
Create Native Monitor
    Set Test Variable    ${ENTRY}    0x40001000
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/arm64.repl
    Execute Command    cpu EnableUbootMode
    Execute Command    cpu AssembleBlock 0x40001000 "mov x0, #0x40000000; msr vbar_el3, x0; mov x0, #0x80000000; msr hcr_el2, x0; mov x0, #0x501; msr scr_el3, x0; mov x0, #0x3c5; msr spsr_el3, x0; movz x0, #0x100; movk x0, #0x4000, lsl #16; msr elr_el3, x0; eret" triple="arm64"
    Execute Command    cpu AssembleBlock 0x40000400 "add x6, x6, #1; mov x0, #0x55; eret" triple="arm64"

Call Secure Monitor
    [Arguments]    ${high}    ${low}    ${selector}
    Execute Command    cpu AssembleBlock 0x40000100 "movz x0, #${low}; movk x0, #${high}, lsl #16; mov x1, #${selector}; mov x6, #0; mov x7, #0x77; smc #0; mov x5, x0; b ." triple="arm64"
    Execute Command    cpu PC ${ENTRY}
    Execute Command    emulation RunFor "0.001"
    Set Test Variable    ${ENTRY}    0x40000100

Assert Register
    [Arguments]    ${register}    ${expected}
    ${actual}=    Execute Command    cpu GetRegister ${register}
    Should Be Equal As Integers    ${actual.strip()}    ${expected}
