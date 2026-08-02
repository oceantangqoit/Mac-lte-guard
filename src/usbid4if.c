// usbid4if <bsdname> : 查找网络接口(enX)对应USB设备的 VID PID (十六进制输出)
// 非USB接口输出 NOT_USB
#include <stdio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <string.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/network/IONetworkInterface.h>

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: usbid4if en2\n"); return 2; }
    CFMutableDictionaryRef match = IOServiceMatching("IONetworkInterface");
    CFDictionarySetValue(match, CFSTR("BSD Name"),
        CFStringCreateWithCString(NULL, argv[1], kCFStringEncodingUTF8));
    io_service_t svc = IOServiceGetMatchingService(kIOMainPortDefault, match);
    if (!svc) { fprintf(stderr, "interface not found\n"); return 1; }
    io_registry_entry_t cur = svc;
    for (int i = 0; i < 12; i++) {
        CFNumberRef v = IORegistryEntryCreateCFProperty(cur, CFSTR("idVendor"), NULL, 0);
        CFNumberRef p = IORegistryEntryCreateCFProperty(cur, CFSTR("idProduct"), NULL, 0);
        if (v && p) {
            int vid, pid;
            CFNumberGetValue(v, kCFNumberIntType, &vid);
            CFNumberGetValue(p, kCFNumberIntType, &pid);
            printf("%04x %04x\n", vid, pid);
            return 0;
        }
        io_registry_entry_t parent;
        if (IORegistryEntryGetParentEntry(cur, kIOServicePlane, &parent) != KERN_SUCCESS) break;
        cur = parent;
    }
    printf("NOT_USB\n");
    return 0;
}
