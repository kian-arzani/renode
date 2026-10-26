*** Keywords ***
Create Watchdog
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescriptionFromString "wdog: Timers.NXP_IMX_Watchdog @ sysbus 0x30280000"
    Execute Command    wdog WriteWord 0x8 0

Service Watchdog
    Execute Command    wdog WriteWord 0x2 0x5555
    Execute Command    wdog WriteWord 0x2 0xaaaa

Assert GPIO
    [Arguments]    ${path}    ${value}
    ${actual}=    Execute Command    python "print(monitor.Machine['sysbus.${{ $path.split('.')[0] }}'].${{ $path.split('.')[1] }}.IsSet)"
    Should Be Equal As Strings    ${actual.strip()}    ${value}

*** Test Cases ***
Linux Refresh Sequence Extends Reset Deadline
    Create Watchdog
    # WT=59 => 30 virtual seconds, WDE=1, SRS=WDA=1.
    Execute Command    wdog WriteWord 0x0 0x3b34
    Service Watchdog
    Execute Command    emulation RunFor "20"
    Service Watchdog
    Execute Command    emulation RunFor "20"
    Assert GPIO    wdog.WDOG_RESET_B    False
    Execute Command    emulation RunFor "11"
    Assert GPIO    wdog.WDOG_RESET_B    True

Short Watchdog Timeout Does Not Underflow
    Create Watchdog
    # WT=0 => 0.5 seconds; reset WICT=4 => already reached threshold.
    Execute Command    wdog WriteWord 0x0 0x34
    Service Watchdog
    Execute Command    emulation RunFor "0.4"
    Assert GPIO    wdog.WDOG_RESET_B    False
    Execute Command    emulation RunFor "0.2"
    Assert GPIO    wdog.WDOG_RESET_B    True

Equal Pretimeout And Timeout Does Not Create Zero Limit
    Create Watchdog
    Execute Command    wdog WriteWord 0x0 0x334
    Service Watchdog
    Execute Command    emulation RunFor "1.9"
    Assert GPIO    wdog.WDOG_RESET_B    False
    Execute Command    emulation RunFor "0.2"
    Assert GPIO    wdog.WDOG_RESET_B    True

System Comparator Signals Masks And Acknowledges Interrupt
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescriptionFromString "sysctr: Timers.IMX8MP_SystemCounter @ sysbus 0x306a0000 { frequency: 1000 }"
    Execute Command    sysctr WriteDoubleWord 0x10020 100
    Execute Command    sysctr WriteDoubleWord 0x1002c 3
    Execute Command    emulation RunFor "0.11"
    ${status}=    Execute Command    sysctr ReadDoubleWord 0x1002c
    Should Contain    ${status}    00000007
    Assert GPIO    sysctr.IRQ    False
    Execute Command    sysctr WriteDoubleWord 0x1002c 1
    Assert GPIO    sysctr.IRQ    True
    Execute Command    sysctr WriteDoubleWord 0x1002c 0
    Assert GPIO    sysctr.IRQ    False
    ${status}=    Execute Command    sysctr ReadDoubleWord 0x1002c
    Should Contain    ${status}    00000000

Enabling Watchdog Uses The Timeout From The Same Write
    Create Watchdog
    Execute Command    wdog WriteWord 0x0 0x3b34
    Execute Command    emulation RunFor "1"
    Assert GPIO    wdog.WDOG_RESET_B    False
