*** Test Cases ***
Entropy Fdt Editor Preserves Properties And Rejects Unsafe Input
    Load Handoff Fixture
    ${result}=    Execute Command    cpu CheckEntropyFdtEditing
    Should Contain    ${result}    rejected 5 invalid FDTs

Kernel Entry Gets Fresh Entropy Again After Reset
    Load Handoff Fixture
    Execute Command    cpu InstallLinuxEntropyHandoff 0x40001000
    Execute Command    cpu InstallLinuxEntropyHandoff 0x40001000
    Execute Command    cpu PrepareEntropyFixture
    Execute Command    emulation RunFor "0.00001"
    ${result}=    Execute Command    cpu CheckEntropyFixture
    Should Contain    ${result}    fresh entropy, valid FDT
    Execute Command    machine Reset
    Execute Command    cpu PrepareEntropyFixture
    Execute Command    emulation RunFor "0.00001"
    ${result}=    Execute Command    cpu CheckEntropyFixture
    Should Contain    ${result}    fresh entropy, valid FDT

*** Keywords ***
Load Handoff Fixture
    Execute Command    include @scripts/helpers/linux-boot-handoff.cs
    Execute Command    include @${CURDIR}/LinuxBootHandoffChecks.cs
    Execute Command    mach create
    Execute Command    machine LoadPlatformDescription @${CURDIR}/arm64.repl
