// usbreset [vid] [pid] : 对指定USB设备执行软件拔插(重新枚举)
// 无参数时读取环境变量 USB_VID/USB_PID
#include <stdio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdlib.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/usb/IOUSBLib.h>
#include <IOKit/IOCFPlugIn.h>

int main(int argc, char **argv) {
    long vid = 0, pid = 0;
    if (argc >= 3) { vid = strtol(argv[1], NULL, 16); pid = strtol(argv[2], NULL, 16); }
    else {
        const char *v = getenv("USB_VID"), *p = getenv("USB_PID");
        if (v && p) { vid = strtol(v, NULL, 16); pid = strtol(p, NULL, 16); }
    }
    if (!vid || !pid) { fprintf(stderr, "usage: usbreset <vid-hex> <pid-hex>  (e.g. usbreset 2c7c 0125)\n"); return 2; }

    CFMutableDictionaryRef match = IOServiceMatching(kIOUSBDeviceClassName);
    CFNumberRef nv = CFNumberCreate(NULL, kCFNumberLongType, &vid);
    CFNumberRef np = CFNumberCreate(NULL, kCFNumberLongType, &pid);
    CFDictionarySetValue(match, CFSTR(kUSBVendorID), nv);
    CFDictionarySetValue(match, CFSTR(kUSBProductID), np);

    io_iterator_t it;
    if (IOServiceGetMatchingServices(kIOMainPortDefault, match, &it) != KERN_SUCCESS) {
        fprintf(stderr, "matching failed\n"); return 1;
    }
    io_service_t dev; int found = 0;
    while ((dev = IOIteratorNext(it))) {
        found = 1;
        IOCFPlugInInterface **plug = NULL; SInt32 score;
        IOUSBDeviceInterface **usb = NULL;
        kern_return_t kr = IOCreatePlugInInterfaceForService(dev, kIOUSBDeviceUserClientTypeID,
                kIOCFPlugInInterfaceID, &plug, &score);
        IOObjectRelease(dev);
        if (kr != KERN_SUCCESS || !plug) { fprintf(stderr, "plugin failed: 0x%x\n", kr); continue; }
        (*plug)->QueryInterface(plug, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), (LPVOID *)&usb);
        IODestroyPlugInInterface(plug);
        if (!usb) continue;
        kr = (*usb)->USBDeviceOpen(usb);
        if (kr == KERN_SUCCESS) {
            kr = (*usb)->USBDeviceReEnumerate(usb, 0);
            printf("reenumerate 0x%04lx:0x%04lx -> %s (0x%x)\n", vid, pid, kr ? "FAIL" : "OK", kr);
            (*usb)->USBDeviceClose(usb);
        } else {
            fprintf(stderr, "open failed: 0x%x (try sudo)\n", kr);
        }
        (*usb)->Release(usb);
    }
    IOObjectRelease(it);
    if (!found) { fprintf(stderr, "device 0x%04lx:0x%04lx not found\n", vid, pid); return 1; }
    return 0;
}
