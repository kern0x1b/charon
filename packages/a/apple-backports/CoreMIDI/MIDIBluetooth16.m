// MIDIBluetoothDriverActivateAllConnections and MIDIBluetoothDriverDisconnect, of iOS 16: the calls that bring up and
// take down the connections of Bluetooth LE MIDI devices. The release has no Bluetooth MIDI driver, so this file is the
// central: CoreBluetooth (on 6.1.3 since iOS 5) scans for the MIDI service, connects to the devices it finds, reads the
// MIDI I/O characteristic, and turns each BLE MIDI packet into MIDI 1.0 bytes.
//
// The bytes go to a virtual source the central makes through the release's MIDISourceCreate, one per device. Whether the
// release lets a process make a virtual source is the open question in facts/CoreMIDI/CoreMIDI.md: when it refuses
// (kMIDINotPermitted, -10844, as the emulated 4S does), the device stays connected and its bytes are dropped, and the
// refusal is written to the log once. Nothing here is measured against a real BLE device; the emulator has no Bluetooth.
#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
#import <CoreMIDI/CoreMIDI.h>

#include <dispatch/dispatch.h>

// The BLE MIDI service and its I/O characteristic (the MIDI 1.0 over BLE specification's UUIDs).
static NSString *const charon_service = @"03B80E5A-EDE8-4B33-A751-6CE34EC4C700";
static NSString *const charon_characteristic = @"7772E5DB-3868-4112-A1A9-F2669D106BF3";

@interface CharonBLEDevice : NSObject <CBPeripheralDelegate>
@property (nonatomic, strong) CBPeripheral *peripheral;
@property (nonatomic, assign) MIDIEndpointRef source;
@property (nonatomic, assign) BOOL refusedOnce;
@end

@implementation CharonBLEDevice

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

// A BLE MIDI packet: a header byte with bit 7 set, then messages, each preceded by a timestamp byte (bit 7 set) when a
// status byte follows. The timestamp is dropped; the MIDI bytes go to the device's virtual source at the time of arrival.
// A timestamp is told from a status by what follows it, so a real-time byte (F8 to FF) followed by a timestamp is read as
// a timestamp: the one case this rule gets wrong, not measured on a device.
- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    NSData *value = characteristic.value;
    if (value.length < 2 || self.source == 0)
        return;
    const UInt8 *bytes = value.bytes;
    UInt8 midi[256];
    NSUInteger count = 0;
    for (NSUInteger i = 1; i < value.length && count < sizeof(midi); i++) {
        UInt8 byte = bytes[i];
        if ((byte & 0x80) && i + 1 < value.length && (bytes[i + 1] & 0x80))
            continue;
        midi[count++] = byte;
    }
    if (count == 0)
        return;
    Byte buffer[512];
    MIDIPacketList *list = (MIDIPacketList *)buffer;
    MIDIPacketListAdd(list, sizeof(buffer), MIDIPacketListInit(list), 0, (ByteCount)count, midi);
    OSStatus status = MIDIReceived(self.source, list);
    if (status != noErr && !self.refusedOnce) {
        self.refusedOnce = YES;
        NSLog(@"charon: a Bluetooth MIDI device's bytes were not received by the release (status %d); facts/CoreMIDI/CoreMIDI.md", (int)status);
    }
}

@end

@interface CharonBLECentral : NSObject <CBCentralManagerDelegate>
@property (nonatomic, strong) CBCentralManager *manager;
@property (nonatomic, strong) NSMutableDictionary *devices;
@property (nonatomic, assign) BOOL activated;
@property (nonatomic, assign) MIDIClientRef client;
@end

@implementation CharonBLECentral

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
    NSString *key = peripheral.identifier.UUIDString;
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
    CharonBLEDevice *device = self.devices[peripheral.identifier.UUIDString];
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

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    [self.devices removeObjectForKey:peripheral.identifier.UUIDString];
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
            [central.devices removeObjectForKey:key];
        }
    });
    return noErr;
}
