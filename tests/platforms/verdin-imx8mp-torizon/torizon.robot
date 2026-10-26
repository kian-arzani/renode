*** Variables ***
${LOGIN}         torizon
${PASSWORD}      torizon
${BOOT_ENTROPY}  %{RENODE_BOOT_ENTROPY=0}
${BOOT_SCRIPT}   %{RENODE_BOOT_SCRIPT=scripts/single-node/toradex-verdin-imx8mp-torizon.resc}
${BOOT0}         %{RENODE_BOOT0=tools/imx8mp-torizon/artifacts/torizon-stock/emmc.boot/boot0.img}
${FIRMWARE}      %{RENODE_FIRMWARE_DIR=tools/imx8mp-torizon/artifacts/torizon-stock/emmc.boot}
${EMMC}          %{RENODE_EMMC_IMAGE=tools/imx8mp-torizon/artifacts/torizon-stock/emmc.img}
${LOG_PREFIX}    %{RENODE_LOG_PREFIX=/tmp/verdin-imx8mp-torizon}
${BL31}          %{RENODE_BL31=}
${CPU_MIPS}      %{RENODE_CPU_MIPS=}
${SERIAL}        %{RENODE_BOARD_SERIAL=}

*** Test Cases ***
Torizon Boots Automatically With Watchdog And Four CPUs
    IF    $CPU_MIPS != ""
        Execute Command    $cpu_mips=${CPU_MIPS}
    END
    Execute Command    $boot0_image=@${BOOT0}
    Execute Command    $uboot_binary=@${FIRMWARE}/u-boot-with-dtb.bin
    Execute Command    $bl31_binary=@${FIRMWARE}/bl31.bin
    IF    $BL31 != ""
        Execute Command    $bl31_binary=@${BL31}
    END
    Execute Command    $emmc_image=@${EMMC}
    Execute Command    include @${BOOT_SCRIPT}
    IF    $BOOT_ENTROPY == "1"
        Execute Command    include @scripts/helpers/linux-boot-handoff.cs
        Execute Command    cpu0 InstallLinuxEntropyHandoff
    END
    # Keep the UART boot report. Repeated known register warnings otherwise
    # dominate host time during rejected deep-idle attempts.
    Execute Command    logFile @${LOG_PREFIX}-test.log
    Execute Command    logLevel 3
    Execute Command    logLevel 0 sysbus.wdog1
    Execute Command    uart2 CreateFileBackend @${LOG_PREFIX}-uart2.log true
    Execute Command    uart3 CreateFileBackend @${LOG_PREFIX}-uart3.log true
    Create Terminal Tester    sysbus.uart3    timeout=600
    Wait For Prompt On Uart    login:
    Write Line To Uart    ${LOGIN}    waitForEcho=false
    Wait For Prompt On Uart    Password:
    Write Line To Uart    ${PASSWORD}    waitForEcho=false
    # Evaluation images expire their initial password. The disk is opened
    # nonpersistently, so this change exists only for this test invocation.
    ${login_result}=    Wait For Prompt On Uart    Current password:|\\$     treatAsRegex=true
    IF    "Current password:" in str($login_result)
        ${new_password}=    Evaluate    "Renode-" + __import__("secrets").token_hex(12)
        Write Line To Uart    ${PASSWORD}    waitForEcho=false
        Wait For Prompt On Uart    New password:
        Write Line To Uart    ${new_password}    waitForEcho=false
        Wait For Prompt On Uart    Retype new password:
        Write Line To Uart    ${new_password}    waitForEcho=false
    ELSE
        Write Line To Uart    ${EMPTY}    waitForEcho=false
    END
    Wait For Prompt On Uart    $${SPACE}
    Write Line To Uart    cat /sys/devices/system/cpu/online    waitForEcho=false
    Wait For Line On Uart    0-3
    Wait For Prompt On Uart    $${SPACE}
    Write Line To Uart    cat /sys/class/watchdog/watchdog0/state    waitForEcho=false
    Wait For Line On Uart    active
    Wait For Prompt On Uart    $${SPACE}
    Write Line To Uart    cat /sys/class/watchdog/watchdog0/timeout    waitForEcho=false
    Wait For Line On Uart    30
    Wait For Prompt On Uart    $${SPACE}
    # SOURCE can be a label symlink; compare the canonical block device.
    Write Line To Uart    readlink -f $(findmnt -n -o SOURCE /sysroot)    waitForEcho=false
    Wait For Line On Uart    /dev/mmcblk2p1
    Wait For Prompt On Uart    $${SPACE}
    Write Line To Uart    findmnt -n -o FSROOT /    waitForEcho=false
    Wait For Line On Uart    ^/ostree/deploy/torizon/deploy/[0-9a-f]+[.]0$    treatAsRegex=true
    Wait For Prompt On Uart    $${SPACE}
    Write Line To Uart    systemctl get-default    waitForEcho=false
    Wait For Line On Uart    multi-user.target
    Wait For Prompt On Uart    $${SPACE}
    IF    $SERIAL != ""
        # Verify the supplied hostname service's standard serial-number path.
        Write Line To Uart    tr -d '\\0' </proc/device-tree/serial-number; echo    waitForEcho=false
        Wait For Line On Uart    ${SERIAL}
        Wait For Prompt On Uart    $${SPACE}
        Write Line To Uart    hostname    waitForEcho=false
        Wait For Line On Uart    verdin-imx8mp-${SERIAL}
        Wait For Prompt On Uart    $${SPACE}
    END
    # More than twice the configured watchdog timeout, in guest virtual time.
    Write Line To Uart    sleep 65; printf '\\nRENODE_WATCHDOG_SURVIVED\\n'    waitForEcho=false
    Wait For Line On Uart    ^RENODE_WATCHDOG_SURVIVED$    timeout=120    treatAsRegex=true
    Wait For Prompt On Uart    $${SPACE}
    Write Line To Uart    test -r /etc/os-release && printf '\\nRENODE_CONSOLE_OK\\n'    waitForEcho=false
    Wait For Line On Uart    ^RENODE_CONSOLE_OK$    treatAsRegex=true
