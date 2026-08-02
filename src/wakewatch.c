// wakewatch: 系统唤醒时执行 ~/.lte-guard.sh（sleepwatcher 的极简替代）
#include <stdio.h>
#include <stdlib.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOMessage.h>
#include <IOKit/pwr_mgt/IOPMLib.h>

static io_connect_t rootPort;

static void cb(void *ref, io_service_t svc, natural_t msg, void *arg) {
    switch (msg) {
        case kIOMessageCanSystemSleep:
        case kIOMessageSystemWillSleep:
            IOAllowPowerChange(rootPort, (long)arg);  // 不阻塞睡眠
            break;
        case kIOMessageSystemHasPoweredOn: {
            // 唤醒后延迟5秒再检测，等接口稳定
            system("(sleep 5; /bin/sh $HOME/.lte-guard.sh) >/dev/null 2>&1 &");
            break;
        }
    }
}

int main(void) {
    IONotificationPortRef port; io_object_t notifier;
    rootPort = IORegisterForSystemPower(NULL, &port, cb, &notifier);
    if (!rootPort) { fprintf(stderr, "IORegisterForSystemPower failed\n"); return 1; }
    CFRunLoopAddSource(CFRunLoopGetCurrent(),
        IONotificationPortGetRunLoopSource(port), kCFRunLoopCommonModes);
    CFRunLoopRun();
    return 0;
}
