*** Keywords ***
Send Card Command
    [Arguments]    ${argument}    ${command}
    Execute Command    sysbus.sdhc WriteDoubleWord 0x8 ${argument}
    Execute Command    sysbus.sdhc WriteDoubleWord 0xc ${command}

Assert Transfer Complete
    ${status}=    Execute Command    sysbus.sdhc ReadDoubleWord 0x30
    Should Contain    ${status}    0000000B
    ${irq}=    Execute Command    python "print(monitor.Machine['sysbus.sdhc'].IRQ.IsSet)"
    Should Be Equal As Strings    ${irq.strip()}    True
    Execute Command    sysbus.sdhc WriteDoubleWord 0x30 0xffffffff
    ${irq}=    Execute Command    python "print(monitor.Machine['sysbus.sdhc'].IRQ.IsSet)"
    Should Be Equal As Strings    ${irq.strip()}    False

*** Test Cases ***
Optional Simple DMA Preserves Data And Signals Completion
    ${tmp}=    Evaluate    __import__('tempfile').mkdtemp(prefix='usdhc-dma-')
    Evaluate    __import__('pathlib').Path($tmp + '/disk.bin').write_bytes(bytes((i // 512 + i) % 251 for i in range(1048576)))
    Evaluate    __import__('pathlib').Path($tmp + '/payload.bin').write_bytes(bytes((i * 37 + 13) % 256 for i in range(2560)))
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/sdhc.repl
    ${caps}=    Execute Command    legacy ReadDoubleWord 0x40
    Should Contain    ${caps}    03200000
    ${caps}=    Execute Command    sysbus.sdhc ReadDoubleWord 0x40
    Should Contain    ${caps}    03600000
    Execute Command    machine SdCardFromFile @${tmp}/disk.bin sysbus.sdhc size=0xc0000000 emmc=true
    Send Card Command    0    0
    Send Card Command    0x40ff8080    0x01020000
    Send Card Command    0    0x02010000
    Send Card Command    0x10000    0x03020000
    Send Card Command    0x10000    0x07030000
    Send Card Command    512    0x10020000
    Execute Command    sysbus.sdhc WriteDoubleWord 0x34 0xb
    Execute Command    sysbus.sdhc WriteDoubleWord 0x38 0xb
    Execute Command    sysbus.sdhc WriteDoubleWord 0x30 0xffffffff
    # Match the target 3 GiB high-capacity eMMC: command addresses are sectors.
    # Five blocks cross a 512 KiB physical-address boundary.
    Execute Command    sysbus.sdhc WriteDoubleWord 0x0 0x4007ff00
    Execute Command    sysbus.sdhc WriteDoubleWord 0x4 0x50200
    Execute Command    sysbus.sdhc WriteDoubleWord 0x48 0x31
    Send Card Command    0x80    0x12220000
    Assert Transfer Complete
    Execute Command    python "from System.IO import File; File.WriteAllBytes('${tmp}/read.bin', monitor.Machine['sysbus'].ReadBytes(0x4007ff00, 2560))"
    ${expected}=    Evaluate    __import__('hashlib').sha256(__import__('pathlib').Path($tmp + '/disk.bin').read_bytes()[65536:68096]).hexdigest()
    ${actual}=    Evaluate    __import__('hashlib').sha256(__import__('pathlib').Path($tmp + '/read.bin').read_bytes()).hexdigest()
    Should Be Equal    ${actual}    ${expected}
    Send Card Command    0    0x0c030000
    Execute Command    sysbus LoadBinary @${tmp}/payload.bin 0x4007ff00
    Execute Command    sysbus.sdhc WriteDoubleWord 0x30 0xffffffff
    Execute Command    sysbus.sdhc WriteDoubleWord 0x0 0x4007ff00
    Execute Command    sysbus.sdhc WriteDoubleWord 0x48 0x21
    Send Card Command    0x100    0x19220000
    Assert Transfer Complete
    Send Card Command    0    0x0c030000
    # Read back payload plus its neighboring blocks to detect overwrites.
    Execute Command    sysbus.sdhc WriteDoubleWord 0x30 0xffffffff
    Execute Command    sysbus.sdhc WriteDoubleWord 0x0 0x40090000
    Execute Command    sysbus.sdhc WriteDoubleWord 0x4 0x70200
    Execute Command    sysbus.sdhc WriteDoubleWord 0x48 0x31
    Send Card Command    0xff    0x12220000
    Assert Transfer Complete
    Execute Command    python "from System.IO import File; File.WriteAllBytes('${tmp}/roundtrip.bin', monitor.Machine['sysbus'].ReadBytes(0x40090000, 3584))"
    ${expected}=    Evaluate    __import__('hashlib').sha256(__import__('pathlib').Path($tmp + '/disk.bin').read_bytes()[130560:131072] + __import__('pathlib').Path($tmp + '/payload.bin').read_bytes() + __import__('pathlib').Path($tmp + '/disk.bin').read_bytes()[133632:134144]).hexdigest()
    ${actual}=    Evaluate    __import__('hashlib').sha256(__import__('pathlib').Path($tmp + '/roundtrip.bin').read_bytes()).hexdigest()
    Should Be Equal    ${actual}    ${expected}
