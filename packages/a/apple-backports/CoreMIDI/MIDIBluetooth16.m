// MIDIBluetoothDriverActivateAllConnections and MIDIBluetoothDriverDisconnect, of iOS 16: the calls that bring up and
// take down the connections of Bluetooth LE MIDI devices. The release has no Bluetooth MIDI driver, so this file is the
// central: CoreBluetooth (on 6.1.3 since iOS 5) scans for the MIDI service, connects to the devices it finds, reads the
// MIDI I/O characteristic, and turns each BLE MIDI packet into MIDI 1.0 bytes (CharonBLEMIDIParse, CharonCoreMIDI.c).
//
// The bytes go to a virtual source the central makes through the release's MIDISourceCreate, one per device. Whether the
// release lets a process make a virtual source is the open question in facts/CoreMIDI/CoreMIDI.md: when it refuses
// (kMIDINotPermitted, -10844, as the emulated 4S does), the device stays connected and its bytes are dropped, and the
// refusal is written to the log once. Nothing here is measured against a real BLE device; the emulator has no Bluetooth.
#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreMIDI/CoreMIDI.h>

#include <dispatch/dispatch.h>
#include <stdlib.h>

#import "CharonCoreMIDI.h"

// The BLE MIDI service and its I/O characteristic (the MIDI 1.0 over BLE specification's UUIDs).
static NSString *const charon_service = @"03B80E5A-EDE8-4B33-A751-6CE34EC4C700";
static NSString *const charon_characteristic = @"7772E5DB-3868-4112-A1A9-F2669D106BF3";

// The release's peripheral before iOS 7 has the UUID as a CFUUIDRef, and the 26.2 SDK no longer declares it. It is declared
// here, without an implementation, so that the one call to it is typed; it is only sent where identifier is not answered.
@interface CBPeripheral (CharonUUID)
- (CFUUIDRef)UUID;
@end

// The key of a peripheral in the central's table: its identifier as a UUID string, the form MIDIBluetoothDriverDisconnect
// is given. From iOS 7 the identifier is an NSUUID; on 6.1.3 the CFUUIDRef of the release is formatted the same way.
static NSString *charon_peripheral_key(CBPeripheral *peripheral)
{
    if ([peripheral respondsToSelector:@selector(identifier)])
        return peripheral.identifier.UUIDString;
    return (__bridge_transfer NSString *)CFUUIDCreateString(kCFAllocatorDefault, [peripheral UUID]);
}

@interface CharonBLEDevice : NSObject <CBPeripheralDelegate> {
    CharonBLEParser _parser;
}
@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, assign) MIDIEndpointRef source;
@property (nonatomic, assign) BOOL refusedOnce;
@end

@implementation CharonBLEDevice

@synthesize peripheral = _peripheral;
@synthesize source = _source;
@synthesize refusedOnce = _refusedOnce;

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    for (CBService *service in peripheral.services) {
        if ([service.UUID isEqual:[CBUUID UUIDWithString:charon_service]])
            [peripheral discoverCharacteristics:@[[CBUUID UUIDWithString:charon_characteristic]] forService:service];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    for (CBCharacteristic *characteristic in service.characteristics) {
        if ([characteristic.UUID isEqual:[CBUUID UUIDWithString:charon_characteristic]])
            [peripheral setNotifyValue:YES forCharacteristic:characteristic];
    }
}

// The bytes of one notification become MIDI 1.0 bytes in a packet of the release's own list. The parser's state (a SysEx
// open across notifications, the running status) belongs to the device, and the buffers are sized from the notification.
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSData *value = characteristic.value;
    if (value.length == 0 || self.source == 0)
        return;
    // CharonBLEMIDIParse writes at most twice the notification's length (a running status is sent again with its data).
    uint8_t *midi = malloc(2 * value.length);
    if (!midi)
        return;
    size_t count = CharonBLEMIDIParse(&_parser, value.bytes, value.length, midi);
    if (count > 0) {
        // The list holds one packet of count bytes: its header is inside sizeof(MIDIPacketList), and the packet's own
        // rounding to four bytes fits in the four bytes added.
        size_t listSize = sizeof(MIDIPacketList) + count + 4;
        Byte *buffer = malloc(listSize);
        if (buffer) {
            MIDIPacketList *list = (MIDIPacketList *)buffer;
            MIDIPacketListAdd(list, listSize, MIDIPacketListInit(list), 0, count, midi);
            OSStatus status = MIDIReceived(self.source, list);
            if (status != noErr && !self.refusedOnce) {
                self.refusedOnce = YES;
                NSLog(@"charon: a Bluetooth MIDI device's bytes were not received by the release (status %d); facts/CoreMIDI/CoreMIDI.md", (int)status);
            }
            free(buffer);
        }
    }
    free(midi);
}

@end

@interface CharonBLECentral : NSObject <CBCentralManagerDelegate>
@property (nonatomic, strong) CBCentralManager *manager;
@property (nonatomic, strong) NSMutableDictionary *devices;
@property (nonatomic, assign) BOOL activated;
@property (nonatomic, assign) MIDIClientRef client;
- (void)forgetDevice:(NSString *)key;
@end

@implementation CharonBLECentral

@synthesize manager = _manager;
@synthesize devices = _devices;
@synthesize activated = _activated;
@synthesize client = _client;

- (instancetype)init
{
    self = [super init];
    if (self) {
        _devices = [NSMutableDictionary dictionary];
        _manager = [[CBCentralManager alloc] initWithDelegate:self queue:dispatch_get_main_queue()];
    }
    return self;
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state == CBManagerStatePoweredOn && self.activated)
        [central scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:charon_service]] options:nil];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    NSString *key = charon_peripheral_key(peripheral);
    if (self.devices[key])
        return;
    CharonBLEDevice *device = [[CharonBLEDevice alloc] init];
    device.peripheral = peripheral;
    peripheral.delegate = device;
    self.devices[key] = device;
    [central connectPeripheral:peripheral options:nil];
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    CharonBLEDevice *device = self.devices[charon_peripheral_key(peripheral)];
    if (!device)
        return;
    if (!self.client) {
        if (MIDIClientCreate(CFSTR("charon-bluetooth"), NULL, NULL, &_client) != noErr)
            NSLog(@"charon: the release would not make a MIDI client for a Bluetooth device");
    }
    NSString *name = peripheral.name ? peripheral.name : @"Bluetooth MIDI";
    MIDIEndpointRef source = 0;
    OSStatus status = self.client ? MIDISourceCreate(self.client, (__bridge CFStringRef)name, &source) : -1;
    if (status == noErr) {
        device.source = source;
    } else {
        NSLog(@"charon: the release refused a virtual source for a Bluetooth MIDI device (status %d); its bytes are dropped (facts/CoreMIDI/CoreMIDI.md)", (int)status);
    }
    [peripheral discoverServices:@[[CBUUID UUIDWithString:charon_service]]];
}

// A connect that fails leaves no device: the entry goes, so that the next advertisement connects again.
- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"charon: a Bluetooth MIDI device did not connect (%@)", error);
    [self forgetDevice:charon_peripheral_key(peripheral)];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    [self forgetDevice:charon_peripheral_key(peripheral)];
}

// Drops a device and disposes its virtual source, so a reconnect makes one source and not a second of the same name.
- (void)forgetDevice:(NSString *)key
{
    CharonBLEDevice *device = self.devices[key];
    if (device.source != 0) {
        MIDIEndpointDispose(device.source);
        device.source = 0;
    }
    [self.devices removeObjectForKey:key];
}

@end

static CharonBLECentral *charon_central(void)
{
    static CharonBLECentral *central;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        central = [[CharonBLECentral alloc] init];
    });
    return central;
}

OSStatus MIDIBluetoothDriverActivateAllConnections(void)
{
    CharonBLECentral *central = charon_central();
    dispatch_async(dispatch_get_main_queue(), ^{
        central.activated = YES;
        if (central.manager.state == CBManagerStatePoweredOn)
            [central.manager scanForPeripheralsWithServices:@[[CBUUID UUIDWithString:charon_service]] options:nil];
    });
    return noErr;
}

OSStatus MIDIBluetoothDriverDisconnect(CFStringRef uuid)
{
    CharonBLECentral *central = charon_central();
    NSString *key = (__bridge NSString *)uuid;
    dispatch_async(dispatch_get_main_queue(), ^{
        CharonBLEDevice *device = central.devices[key];
        if (device) {
            [central.manager cancelPeripheralConnection:device.peripheral];
            [central forgetDevice:key];
        }
    });
    return noErr;
}
