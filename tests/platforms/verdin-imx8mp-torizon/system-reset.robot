*** Test Cases ***
Core Enable Starts At RVBAR Without Rewinding Other Cores
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @platforms/cpus/nxp-mimx8ml.repl
    Execute Command    sysbus.ca53Cluster ForEach IsHalted true
    # RVBAR>>2 split into high16/low22, as programmed by supplied BL31.
    Execute Command    sysbus WriteDoubleWord 0x3039007c 0x40
    Execute Command    sysbus WriteDoubleWord 0x30390080 0x400
    Execute Command    sysbus WriteDoubleWord 0x30390008 3
    ${pc}=    Execute Command    sysbus.ca53Cluster.cpu1 PC
    Should Be True    int($pc.strip(), 16) == 0x40001000
    ${halted}=    Execute Command    sysbus.ca53Cluster.cpu1 IsHalted
    Should Contain    ${halted}    False
    # CPU1 has advanced when a later CPU_ON deasserts CPU2's reset.
    Execute Command    sysbus.ca53Cluster.cpu1 PC 0x40001040
    Execute Command    sysbus WriteDoubleWord 0x30390084 0x40
    Execute Command    sysbus WriteDoubleWord 0x30390088 0x800
    Execute Command    sysbus WriteDoubleWord 0x30390008 7
    ${pc}=    Execute Command    sysbus.ca53Cluster.cpu2 PC
    Should Be True    int($pc.strip(), 16) == 0x40002000
    ${pc}=    Execute Command    sysbus.ca53Cluster.cpu1 PC
    Should Be True    int($pc.strip(), 16) == 0x40001040
