*** Test Cases ***
PLL Lock And Rate Follow Reference Reset And Dividers
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescriptionFromString "anatop: Miscellaneous.IMX8MP_AnalogClockControl @ sysbus 0x30360000"
    ${rate}=    Execute Command    anatop GetFrequency "SYS1"
    Should Be True    int($rate.strip(), 16) == 800000000
    ${rate}=    Execute Command    anatop GetFrequency "SYS2"
    Should Be True    int($rate.strip(), 16) == 1000000000
    Execute Command    anatop WriteDoubleWord 0x94 0x80000800
    ${status}=    Execute Command    anatop ReadDoubleWord 0x94
    Should Contain    ${status}    00000800
    Execute Command    anatop WriteDoubleWord 0x94 0xA03
    ${status}=    Execute Command    anatop ReadDoubleWord 0x94
    Should Contain    ${status}    00000A03
    Execute Command    anatop WriteDoubleWord 0x94 0xA00
    Execute Command    anatop WriteDoubleWord 0x98 0
    ${rate}=    Execute Command    anatop GetFrequency "SYS1"
    Should Be True    int($rate.strip(), 16) == 0
    ${status}=    Execute Command    anatop ReadDoubleWord 0x94
    Should Contain    ${status}    00000A00
    Execute Command    anatop WriteDoubleWord 0x98 0x12c032
    ${rate}=    Execute Command    anatop GetFrequency "SYS1"
    Should Be True    int($rate.strip(), 16) == 600000000
    ${status}=    Execute Command    anatop ReadDoubleWord 0x94
    Should Contain    ${status}    80000A00

Linux Can Prepare Auxiliary PLLs And Change Fractional Rates
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescriptionFromString "anatop: Miscellaneous.IMX8MP_AnalogClockControl @ sysbus 0x30360000"
    ${rate}=    Execute Command    anatop GetFrequency "GPU"
    Should Be True    int($rate.strip(), 16) == 0
    Execute Command    anatop WriteDoubleWord 0x64 0xA00
    ${rate}=    Execute Command    anatop GetFrequency "GPU"
    Should Be True    int($rate.strip(), 16) == 600000000
    Execute Command    anatop WriteDoubleWord 0x28 0x2200
    ${rate}=    Execute Command    anatop GetFrequency "VIDEO1"
    Should Be True    int($rate.strip(), 16) == 594000000
    # Signed KDIV=-16384, MDIV=100, PDIV=2, SDIV=1 => 598.5 MHz.
    Execute Command    anatop WriteDoubleWord 0x2c 0x64021
    Execute Command    anatop WriteDoubleWord 0x30 0xc000
    ${rate}=    Execute Command    anatop GetFrequency "VIDEO1"
    Should Be True    int($rate.strip(), 16) == 598500000
    Execute Command    anatop WriteDoubleWord 0x28 0x2000
    ${rate}=    Execute Command    anatop GetFrequency "VIDEO1"
    Should Be True    int($rate.strip(), 16) == 0
