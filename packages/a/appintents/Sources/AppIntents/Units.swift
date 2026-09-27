// The units a measurement parameter is asked in, the control styles it is asked with, and the kind
// of a date it takes: the framework's own lists, in the framework's own order, each case the unit
// the release's own `Measurement` writes it as.

import Foundation

extension IntentParameter {
// generated from the SDK 26.2 header's own case lists; the framework's cases, in the framework's order
    /// The units of a length a parameter takes, the framework's own list.
    public enum Acceleration: Hashable {
        case gravity
        case metersPerSecondSquared
        public static func == (a: Acceleration, b: Acceleration) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Acceleration: CaseIterable {
        public typealias AllCases = [Acceleration]
        public static var allCases: [Acceleration] { return [gravity, metersPerSecondSquared] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Angle: Hashable {
        case arcMinutes
        case arcSeconds
        case degrees
        case gradians
        case radians
        case revolutions
        public static func == (a: Angle, b: Angle) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Angle: CaseIterable {
        public typealias AllCases = [Angle]
        public static var allCases: [Angle] { return [arcMinutes, arcSeconds, degrees, gradians, radians, revolutions] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Area: Hashable {
        case acres
        case ares
        case hectares
        case squareCentimeters
        case squareFeet
        case squareInches
        case squareKilometers
        case squareMegameters
        case squareMeters
        case squareMicrometers
        case squareMiles
        case squareMillimeters
        case squareNanometers
        case squareYards
        public static func == (a: Area, b: Area) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Area: CaseIterable {
        public typealias AllCases = [Area]
        public static var allCases: [Area] { return [acres, ares, hectares, squareCentimeters, squareFeet, squareInches, squareKilometers, squareMegameters, squareMeters, squareMicrometers, squareMiles, squareMillimeters, squareNanometers, squareYards] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum ConcentrationMass: Hashable {
        case gramsPerLiter
        case milligramsPerDeciliter
        public static func == (a: ConcentrationMass, b: ConcentrationMass) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension ConcentrationMass: CaseIterable {
        public typealias AllCases = [ConcentrationMass]
        public static var allCases: [ConcentrationMass] { return [gramsPerLiter, milligramsPerDeciliter] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Dispersion: Hashable {
        case partsPerMillion
        public static func == (a: Dispersion, b: Dispersion) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Dispersion: CaseIterable {
        public typealias AllCases = [Dispersion]
        public static var allCases: [Dispersion] { return [partsPerMillion] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Duration: Hashable {
        case hours
        case microseconds
        case milliseconds
        case minutes
        case nanoseconds
        case picoseconds
        case seconds
        public static func == (a: Duration, b: Duration) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Duration: CaseIterable {
        public typealias AllCases = [Duration]
        public static var allCases: [Duration] { return [hours, microseconds, milliseconds, minutes, nanoseconds, picoseconds, seconds] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum ElectricCharge: Hashable {
        case ampereHours
        case coulombs
        case kiloampereHours
        case megaampereHours
        case microampereHours
        case milliampereHours
        public static func == (a: ElectricCharge, b: ElectricCharge) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension ElectricCharge: CaseIterable {
        public typealias AllCases = [ElectricCharge]
        public static var allCases: [ElectricCharge] { return [ampereHours, coulombs, kiloampereHours, megaampereHours, microampereHours, milliampereHours] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum ElectricCurrent: Hashable {
        case amperes
        case kiloamperes
        case megaamperes
        case microamperes
        case milliamperes
        public static func == (a: ElectricCurrent, b: ElectricCurrent) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension ElectricCurrent: CaseIterable {
        public typealias AllCases = [ElectricCurrent]
        public static var allCases: [ElectricCurrent] { return [amperes, kiloamperes, megaamperes, microamperes, milliamperes] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum ElectricPotentialDifference: Hashable {
        case kilovolts
        case megavolts
        case microvolts
        case millivolts
        case volts
        public static func == (a: ElectricPotentialDifference, b: ElectricPotentialDifference) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension ElectricPotentialDifference: CaseIterable {
        public typealias AllCases = [ElectricPotentialDifference]
        public static var allCases: [ElectricPotentialDifference] { return [kilovolts, megavolts, microvolts, millivolts, volts] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum ElectricResistance: Hashable {
        case kiloohms
        case megaohms
        case microohms
        case milliohms
        case ohms
        public static func == (a: ElectricResistance, b: ElectricResistance) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension ElectricResistance: CaseIterable {
        public typealias AllCases = [ElectricResistance]
        public static var allCases: [ElectricResistance] { return [kiloohms, megaohms, microohms, milliohms, ohms] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Energy: Hashable {
        case calories
        case joules
        case kilocalories
        case kilojoules
        case kilowattHours
        public static func == (a: Energy, b: Energy) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Energy: CaseIterable {
        public typealias AllCases = [Energy]
        public static var allCases: [Energy] { return [calories, joules, kilocalories, kilojoules, kilowattHours] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Frequency: Hashable {
        case framesPerSecond
        case gigahertz
        case hertz
        case kilohertz
        case megahertz
        case microhertz
        case millihertz
        case nanohertz
        case terahertz
        public static func == (a: Frequency, b: Frequency) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Frequency: CaseIterable {
        public typealias AllCases = [Frequency]
        public static var allCases: [Frequency] { return [framesPerSecond, gigahertz, hertz, kilohertz, megahertz, microhertz, millihertz, nanohertz, terahertz] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum FuelEfficiency: Hashable {
        case litersPer100Kilometers
        case milesPerGallon
        case milesPerImperialGallon
        public static func == (a: FuelEfficiency, b: FuelEfficiency) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension FuelEfficiency: CaseIterable {
        public typealias AllCases = [FuelEfficiency]
        public static var allCases: [FuelEfficiency] { return [litersPer100Kilometers, milesPerGallon, milesPerImperialGallon] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Illuminance: Hashable {
        case lux
        public static func == (a: Illuminance, b: Illuminance) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Illuminance: CaseIterable {
        public typealias AllCases = [Illuminance]
        public static var allCases: [Illuminance] { return [lux] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum InformationStorage: Hashable {
        case bits
        case bytes
        case exabits
        case exabytes
        case exbibits
        case exbibytes
        case gibibits
        case gibibytes
        case gigabits
        case gigabytes
        case kibibits
        case kibibytes
        case kilobits
        case kilobytes
        case mebibits
        case mebibytes
        case megabits
        case megabytes
        case nibbles
        case pebibits
        case pebibytes
        case petabits
        case petabytes
        case tebibits
        case tebibytes
        case terabits
        case terabytes
        case yobibits
        case yobibytes
        case yottabits
        case yottabytes
        case zebibits
        case zebibytes
        case zettabits
        case zettabytes
        public static func == (a: InformationStorage, b: InformationStorage) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension InformationStorage: CaseIterable {
        public typealias AllCases = [InformationStorage]
        public static var allCases: [InformationStorage] { return [bits, bytes, exabits, exabytes, exbibits, exbibytes, gibibits, gibibytes, gigabits, gigabytes, kibibits, kibibytes, kilobits, kilobytes, mebibits, mebibytes, megabits, megabytes, nibbles, pebibits, pebibytes, petabits, petabytes, tebibits, tebibytes, terabits, terabytes, yobibits, yobibytes, yottabits, yottabytes, zebibits, zebibytes, zettabits, zettabytes] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Length: Hashable {
        case astronomicalUnits
        case centimeters
        case decameters
        case decimeters
        case fathoms
        case feet
        case furlongs
        case hectometers
        case inches
        case kilometers
        case lightyears
        case megameters
        case meters
        case micrometers
        case miles
        case millimeters
        case nanometers
        case nauticalMiles
        case parsecs
        case picometers
        case scandinavianMiles
        case yards
        public static func == (a: Length, b: Length) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Length: CaseIterable {
        public typealias AllCases = [Length]
        public static var allCases: [Length] { return [astronomicalUnits, centimeters, decameters, decimeters, fathoms, feet, furlongs, hectometers, inches, kilometers, lightyears, megameters, meters, micrometers, miles, millimeters, nanometers, nauticalMiles, parsecs, picometers, scandinavianMiles, yards] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Mass: Hashable {
        case carats
        case centigrams
        case decigrams
        case grams
        case kilograms
        case metricTons
        case micrograms
        case milligrams
        case nanograms
        case ounces
        case ouncesTroy
        case picograms
        case pounds
        case shortTons
        case slugs
        case stones
        public static func == (a: Mass, b: Mass) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Mass: CaseIterable {
        public typealias AllCases = [Mass]
        public static var allCases: [Mass] { return [carats, centigrams, decigrams, grams, kilograms, metricTons, micrograms, milligrams, nanograms, ounces, ouncesTroy, picograms, pounds, shortTons, slugs, stones] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Power: Hashable {
        case femtowatts
        case gigawatts
        case horsepower
        case kilowatts
        case megawatts
        case microwatts
        case milliwatts
        case nanowatts
        case picowatts
        case terawatts
        case watts
        public static func == (a: Power, b: Power) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Power: CaseIterable {
        public typealias AllCases = [Power]
        public static var allCases: [Power] { return [femtowatts, gigawatts, horsepower, kilowatts, megawatts, microwatts, milliwatts, nanowatts, picowatts, terawatts, watts] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Pressure: Hashable {
        case bars
        case gigapascals
        case hectopascals
        case inchesOfMercury
        case kilopascals
        case megapascals
        case millibars
        case millimetersOfMercury
        case newtonsPerMetersSquared
        case poundsForcePerSquareInch
        public static func == (a: Pressure, b: Pressure) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Pressure: CaseIterable {
        public typealias AllCases = [Pressure]
        public static var allCases: [Pressure] { return [bars, gigapascals, hectopascals, inchesOfMercury, kilopascals, megapascals, millibars, millimetersOfMercury, newtonsPerMetersSquared, poundsForcePerSquareInch] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Speed: Hashable {
        case kilometersPerHour
        case knots
        case metersPerSecond
        case milesPerHour
        public static func == (a: Speed, b: Speed) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Speed: CaseIterable {
        public typealias AllCases = [Speed]
        public static var allCases: [Speed] { return [kilometersPerHour, knots, metersPerSecond, milesPerHour] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Temperature: Hashable {
        case celsius
        case fahrenheit
        case kelvin
        public static func == (a: Temperature, b: Temperature) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Temperature: CaseIterable {
        public typealias AllCases = [Temperature]
        public static var allCases: [Temperature] { return [celsius, fahrenheit, kelvin] }
    }

    /// The units of a length a parameter takes, the framework's own list.
    public enum Volume: Hashable {
        case acreFeet
        case bushels
        case centiliters
        case cubicCentimeters
        case cubicDecimeters
        case cubicFeet
        case cubicInches
        case cubicKilometers
        case cubicMeters
        case cubicMiles
        case cubicMillimeters
        case cubicYards
        case cups
        case deciliters
        case fluidOunces
        case gallons
        case imperialFluidOunces
        case imperialGallons
        case imperialPints
        case imperialQuarts
        case imperialTablespoons
        case imperialTeaspoons
        case kiloliters
        case liters
        case megaliters
        case metricCups
        case milliliters
        case pints
        case quarts
        case tablespoons
        case teaspoons
        public static func == (a: Volume, b: Volume) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
    extension Volume: CaseIterable {
        public typealias AllCases = [Volume]
        public static var allCases: [Volume] { return [acreFeet, bushels, centiliters, cubicCentimeters, cubicDecimeters, cubicFeet, cubicInches, cubicKilometers, cubicMeters, cubicMiles, cubicMillimeters, cubicYards, cups, deciliters, fluidOunces, gallons, imperialFluidOunces, imperialGallons, imperialPints, imperialQuarts, imperialTablespoons, imperialTeaspoons, kiloliters, liters, megaliters, metricCups, milliliters, pints, quarts, tablespoons, teaspoons] }
    }

    /// IntControlStyle
    public enum IntControlStyle: Hashable {
        case stepper
        case field
        public static func == (a: IntControlStyle, b: IntControlStyle) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }

    /// PlacemarkDisplayStyle
    public enum PlacemarkDisplayStyle: Hashable {
        case name
        case address
        case city
        public static func == (a: PlacemarkDisplayStyle, b: PlacemarkDisplayStyle) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }

    /// DoubleControlStyle
    public enum DoubleControlStyle: Hashable {
        case stepper
        case field
        case slider
        public static func == (a: DoubleControlStyle, b: DoubleControlStyle) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }

    /// DateKind
    public enum DateKind: Hashable {
        case date
        case time
        case dateTime
        public static func == (a: DateKind, b: DateKind) -> Bool { true }
        public func hash(into hasher: inout Hasher) { hasher.combine(Self.allCases.firstIndex(of: self) ?? 0) }
        public var hashValue: Int { hasherValue(self) }
    }
}
