import HealthKit
import Foundation
import SwiftDate
import SwiftyBeaver

public enum CircadianEvent {
    case Meal
    case Fast
    case Sleep
    case Exercise
}

/*
 * A protocol for unifying common metadata across HKSample and HKStatistic
 */
public protocol MCSample {
    var startDate    : NSDate        { get }
    var endDate      : NSDate        { get }
    var numeralValue : Double?       { get }
    var defaultUnit  : HKUnit?       { get }
    var hkType       : HKSampleType? { get }
}

public struct MCStatisticSample : MCSample {
    public var statistic    : HKStatistics
    public var numeralValue : Double?
    
    public var startDate    : NSDate        { return statistic.startDate   }
    public var endDate      : NSDate        { return statistic.endDate     }
    public var defaultUnit  : HKUnit?       { return statistic.defaultUnit }
    public var hkType       : HKSampleType? { return statistic.hkType      }
    
    public init(statistic: HKStatistics, statsOption: HKStatisticsOptions) {
        self.statistic = statistic
        self.numeralValue = nil
        if ( statsOption.contains(.DiscreteAverage) ) {
            self.numeralValue = statistic.averageQuantity()?.doubleValueForUnit(defaultUnit!)
        }
        if ( statsOption.contains(.DiscreteMin) ) {
            self.numeralValue = statistic.minimumQuantity()?.doubleValueForUnit(defaultUnit!)
        }
        if ( statsOption.contains(.DiscreteMax) ) {
            self.numeralValue = statistic.maximumQuantity()?.doubleValueForUnit(defaultUnit!)
        }
        if ( statsOption.contains(.CumulativeSum) ) {
            self.numeralValue = statistic.sumQuantity()?.doubleValueForUnit(defaultUnit!)
        }
    }
}

/*
 * Generalized aggregation, irrespective of HKSampleType.
 *
 * This relies on the numeralValue field provided by the MCSample protocol to provide
 * a valid numeric representation for all HKSampleTypes.
 *
 * The increment operation provided within can only be applied to samples of a matching type.
 */
public struct MCAggregateSample : MCSample {
    public var startDate    : NSDate
    public var endDate      : NSDate
    public var numeralValue : Double?
    public var defaultUnit  : HKUnit?
    public var hkType       : HKSampleType?
    public var aggOp        : HKStatisticsOptions
    
    var runningAgg: [Double] = [0.0, 0.0, 0.0]
    var runningCnt: Int = 0
    
    public init(sample: MCSample, op: HKStatisticsOptions) {
        startDate = sample.startDate
        endDate = sample.endDate
        numeralValue = nil
        defaultUnit = nil
        hkType = sample.hkType
        aggOp = op
        self.incr(sample)
    }
    
    public init(startDate: NSDate = NSDate(), endDate: NSDate = NSDate(), value: Double?, sampleType: HKSampleType?, op: HKStatisticsOptions) {
        self.startDate = startDate
        self.endDate = endDate
        numeralValue = value
        defaultUnit = sampleType?.defaultUnit
        hkType = sampleType
        aggOp = op
    }
    
    public init(statistic: HKStatistics, op: HKStatisticsOptions) {
        startDate = statistic.startDate
        endDate = statistic.endDate
        numeralValue = statistic.numeralValue
        defaultUnit = statistic.defaultUnit
        hkType = statistic.hkType
        aggOp = op
        
        // Initialize internal statistics.
        if let sumQ = statistic.sumQuantity() {
            runningAgg[0] = sumQ.doubleValueForUnit(statistic.defaultUnit!)
        } else if let avgQ = statistic.averageQuantity() {
            runningAgg[0] = avgQ.doubleValueForUnit(statistic.defaultUnit!)
            runningCnt = 1
        }
        if let minQ = statistic.minimumQuantity() {
            runningAgg[1] = minQ.doubleValueForUnit(statistic.defaultUnit!)
        }
        if let maxQ = statistic.maximumQuantity() {
            runningAgg[2] = maxQ.doubleValueForUnit(statistic.defaultUnit!)
        }
    }
    
    public init(startDate: NSDate, endDate: NSDate, numeralValue: Double?, defaultUnit: HKUnit?,
                hkType: HKSampleType?, aggOp: HKStatisticsOptions, runningAgg: [Double], runningCnt: Int)
    {
        self.startDate = startDate
        self.endDate = endDate
        self.numeralValue = numeralValue
        self.defaultUnit = defaultUnit
        self.hkType = hkType
        self.aggOp = aggOp
        self.runningAgg = runningAgg
        self.runningCnt = runningCnt
    }
    
    public mutating func rsum(sample: MCSample) {
        runningAgg[0] += sample.numeralValue!
        runningCnt += 1
    }
    
    public mutating func rmin(sample: MCSample) {
        runningAgg[1] = min(runningAgg[1], sample.numeralValue!)
        runningCnt += 1
    }
    
    public mutating func rmax(sample: MCSample) {
        runningAgg[2] = max(runningAgg[2], sample.numeralValue!)
        runningCnt += 1
    }
    
    public mutating func incrOp(sample: MCSample) {
        if aggOp.contains(.DiscreteAverage) || aggOp.contains(.CumulativeSum) {
            rsum(sample)
        }
        if aggOp.contains(.DiscreteMin) {
            rmin(sample)
        }
        if aggOp.contains(.DiscreteMax) {
            rmax(sample)
        }
    }
    
    public mutating func incr(sample: MCSample) {
        if hkType == sample.hkType {
            startDate = min(sample.startDate, startDate)
            endDate = max(sample.endDate, endDate)
            
            switch hkType! {
            case is HKCategoryType:
                switch hkType!.identifier {
                case HKCategoryTypeIdentifierSleepAnalysis:
                    incrOp(sample)
                    
                default:
                    log.error("Cannot aggregate \(hkType)")
                }
                
            case is HKCorrelationType:
                switch hkType!.identifier {
                case HKCorrelationTypeIdentifierBloodPressure:
                    incrOp(sample)
                    
                default:
                    AppDelegate.log.error("Cannot aggregate \(hkType)")
                }
                
            case is HKWorkoutType:
                incrOp(sample)
                
            case is HKQuantityType:
                incrOp(sample)
                
            default:
                AppDelegate.log.error("Cannot aggregate \(hkType)")
            }
            
        } else {
//            log.error("Invalid sample aggregation between \(hkType) and \(sample.hkType)")
        }
    }
    
    public mutating func final() {
        if aggOp.contains(.CumulativeSum) {
            numeralValue = runningAgg[0]
        } else if aggOp.contains(.DiscreteAverage) {
            numeralValue = runningAgg[0] / Double(runningCnt)
        } else if aggOp.contains(.DiscreteMin) {
            numeralValue = runningAgg[1]
        } else if aggOp.contains(.DiscreteMax) {
            numeralValue = runningAgg[2]
        }
    }
    
    public mutating func finalAggregate(finalOp: HKStatisticsOptions) {
        if aggOp.contains(.CumulativeSum) && finalOp.contains(.CumulativeSum) {
            numeralValue = runningAgg[0]
        } else if aggOp.contains(.DiscreteAverage) && finalOp.contains(.DiscreteAverage) {
            numeralValue = runningAgg[0] / Double(runningCnt)
        } else if aggOp.contains(.DiscreteMin) && finalOp.contains(.DiscreteMin) {
            numeralValue = runningAgg[1]
        } else if aggOp.contains(.DiscreteMax) && finalOp.contains(.DiscreteMax) {
            numeralValue = runningAgg[2]
        }
    }
    
    public func query(stats: HKStatisticsOptions) -> Double? {
        if ( stats.contains(.CumulativeSum) && aggOp.contains(.CumulativeSum) ) {
            return runningAgg[0]
        }
        if ( stats.contains(.DiscreteAverage) && aggOp.contains(.DiscreteAverage) ) {
            return runningAgg[0] / Double(runningCnt)
        }
        if ( stats.contains(.DiscreteMin) && aggOp.contains(.DiscreteMin) ) {
            return runningAgg[1]
        }
        if ( stats.contains(.DiscreteMax) && aggOp.contains(.DiscreteMax) ) {
            return runningAgg[2]
        }
        return nil
    }
    
    public func count() -> Int { return runningCnt }
    
    // Encoding/decoding.
    public static func encode(aggregate: MCAggregateSample) -> MCAggregateSampleCoding {
        return MCAggregateSampleCoding(aggregate: aggregate)
    }
    
    public static func decode(aggregateEncoding: MCAggregateSampleCoding) -> MCAggregateSample? {
        return aggregateEncoding.aggregate
    }
}

public extension MCAggregateSample {
    public class MCAggregateSampleCoding: NSObject, NSCoding {
        var aggregate: MCAggregateSample?
        
        init(aggregate: MCAggregateSample) {
            self.aggregate = aggregate
            super.init()
        }
        
        required public init?(coder aDecoder: NSCoder) {
            guard let startDate    = aDecoder.decodeObjectForKey("startDate")    as? NSDate         else { LOG.error("Failed to rebuild MCAggregateSample startDate"); aggregate = nil; super.init(); return nil }
            guard let endDate      = aDecoder.decodeObjectForKey("endDate")      as? NSDate         else { LOG.error("Failed to rebuild MCAggregateSample endDate"); aggregate = nil; super.init(); return nil }
            guard let numeralValue = aDecoder.decodeObjectForKey("numeralValue") as? Double?        else { log.error("Failed to rebuild MCAggregateSample numeralValue"); aggregate = nil; super.init(); return nil }
            guard let defaultUnit  = aDecoder.decodeObjectForKey("defaultUnit")  as? HKUnit?        else { log.error("Failed to rebuild MCAggregateSample defaultUnit"); aggregate = nil; super.init(); return nil }
            guard let hkType       = aDecoder.decodeObjectForKey("hkType")       as? HKSampleType?  else { log.error("Failed to rebuild MCAggregateSample hkType"); aggregate = nil; super.init(); return nil }
            guard let aggOp        = aDecoder.decodeObjectForKey("aggOp")        as? UInt           else { log.error("Failed to rebuild MCAggregateSample aggOp"); aggregate = nil; super.init(); return nil }
            guard let runningAgg   = aDecoder.decodeObjectForKey("runningAgg")   as? [Double]       else { log.error("Failed to rebuild MCAggregateSample runningAgg"); aggregate = nil; super.init(); return nil }
            guard let runningCnt   = aDecoder.decodeObjectForKey("runningCnt")   as? Int            else { log.error("Failed to rebuild MCAggregateSample runningCnt"); aggregate = nil; super.init(); return nil }
            
            aggregate = MCAggregateSample(startDate: startDate, endDate: endDate, numeralValue: numeralValue, defaultUnit: defaultUnit,
                                          hkType: hkType, aggOp: HKStatisticsOptions(rawValue: aggOp), runningAgg: runningAgg, runningCnt: runningCnt)
            
            super.init()
        }
        
        public func encodeWithCoder(aCoder: NSCoder) {
            aCoder.encodeObject(aggregate!.startDate,      forKey: "startDate")
            aCoder.encodeObject(aggregate!.endDate,        forKey: "endDate")
            aCoder.encodeObject(aggregate!.numeralValue,   forKey: "numeralValue")
            aCoder.encodeObject(aggregate!.defaultUnit,    forKey: "defaultUnit")
            aCoder.encodeObject(aggregate!.hkType,         forKey: "hkType")
            aCoder.encodeObject(aggregate!.aggOp.rawValue, forKey: "aggOp")
            aCoder.encodeObject(aggregate!.runningAgg,     forKey: "runningAgg")
            aCoder.encodeObject(aggregate!.runningCnt,     forKey: "runningCnt")
        }
    }
}

public class MCAggregateArray: NSObject, NSCoding {
    public var aggregates : [MCAggregateSample]
    
    init(aggregates: [MCAggregateSample]) {
        self.aggregates = aggregates
    }
    
    required public convenience init?(coder aDecoder: NSCoder) {
        guard let aggs = aDecoder.decodeObjectForKey("aggregates") as? [MCAggregateSample.MCAggregateSampleCoding] else { return nil }
        self.init(aggregates: aggs.flatMap({ return MCAggregateSample.decode($0) }))
    }
    
    public func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeObject(aggregates.map { return MCAggregateSample.encode($0) }, forKey: "aggregates")
    }
}


// MARK: - Categories & Extensions

// Default aggregation for all subtypes of HKSampleType.

public extension HKSampleType {
    var aggregationOptions: HKStatisticsOptions {
        switch self {
        case is HKCategoryType:
            return (self as! HKCategoryType).aggregationOptions
            
        case is HKCorrelationType:
            return (self as! HKCorrelationType).aggregationOptions
            
        case is HKWorkoutType:
            return (self as! HKWorkoutType).aggregationOptions
            
        case is HKQuantityType:
            return (self as! HKQuantityType).aggregationOptions
            
        default:
            fatalError("Invalid aggregation overy \(self.identifier)")
        }
    }
}

public extension HKCategoryType {
    override var aggregationOptions: HKStatisticsOptions { return .DiscreteAverage }
}

public extension HKCorrelationType {
    override var aggregationOptions: HKStatisticsOptions { return .DiscreteAverage }
}

public extension HKWorkoutType {
    override var aggregationOptions: HKStatisticsOptions { return .CumulativeSum }
}

public extension HKQuantityType {
    override var aggregationOptions: HKStatisticsOptions {
        switch aggregationStyle {
        case .Discrete:
            return .DiscreteAverage
        case .Cumulative:
            return .CumulativeSum
        }
    }
}

// Duration aggregate for HKSample arrays.
public extension Array where Element: HKSample {
    public var sleepDuration: NSTimeInterval? {
        return filter { (sample) -> Bool in
            let categorySample = sample as! HKCategorySample
            return categorySample.sampleType.identifier == HKCategoryTypeIdentifierSleepAnalysis
                && categorySample.value == HKCategoryValueSleepAnalysis.Asleep.rawValue
            }.map { (sample) -> NSTimeInterval in
                return sample.endDate.timeIntervalSinceDate(sample.startDate)
            }.reduce(0) { $0 + $1 }
    }
    
    public var workoutDuration: NSTimeInterval? {
        return filter { (sample) -> Bool in
            let categorySample = sample as! HKWorkout
            return categorySample.sampleType.identifier == HKWorkoutTypeIdentifier
            }.map { (sample) -> NSTimeInterval in
                return sample.endDate.timeIntervalSinceDate(sample.startDate)
            }.reduce(0) { $0 + $1 }
    }
}

/*
 * MCSample extensions for HKStatistics.
 */
extension HKStatistics: MCSample { }

public extension HKStatistics {
    var quantity: HKQuantity? {
        switch quantityType.aggregationStyle {
        case .Discrete:
            return averageQuantity()
        case .Cumulative:
            return sumQuantity()
        }
    }
    
    public var numeralValue: Double? {
        guard defaultUnit != nil && quantity != nil else {
            return nil
        }
        return quantity!.doubleValueForUnit(defaultUnit!)
    }
    
    public var defaultUnit: HKUnit? { return quantityType.defaultUnit }
    
    public var hkType: HKSampleType? { return quantityType }
}

/*
 * MCSample extensions for HKSample.
 */

extension HKSample: MCSample { }

public extension HKSampleType {
    public var defaultUnit: HKUnit? {
        let isMetric: Bool = NSLocale.currentLocale().objectForKey(NSLocaleUsesMetricSystem)!.boolValue
        switch identifier {
        case HKCategoryTypeIdentifierSleepAnalysis:
            return HKUnit.hourUnit()
            
        case HKCorrelationTypeIdentifierBloodPressure:
            return HKUnit.millimeterOfMercuryUnit()
            
        case HKQuantityTypeIdentifierActiveEnergyBurned:
            return HKUnit.kilocalorieUnit()
            
        case HKQuantityTypeIdentifierBasalEnergyBurned:
            return HKUnit.kilocalorieUnit()
            
        case HKQuantityTypeIdentifierBloodGlucose:
            return HKUnit.gramUnitWithMetricPrefix(.Milli).unitDividedByUnit(HKUnit.literUnitWithMetricPrefix(.Deci))
            
        case HKQuantityTypeIdentifierBloodPressureDiastolic:
            return HKUnit.millimeterOfMercuryUnit()
            
        case HKQuantityTypeIdentifierBloodPressureSystolic:
            return HKUnit.millimeterOfMercuryUnit()
            
        case HKQuantityTypeIdentifierBodyMass:
            return isMetric ? HKUnit.gramUnitWithMetricPrefix(.Kilo) : HKUnit.poundUnit()
            
        case HKQuantityTypeIdentifierBodyMassIndex:
            return HKUnit.countUnit()
            
        case HKQuantityTypeIdentifierDietaryCaffeine:
            return HKUnit.gramUnitWithMetricPrefix(HKMetricPrefix.Milli)
            
        case HKQuantityTypeIdentifierDietaryCarbohydrates:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryCholesterol:
            return HKUnit.gramUnitWithMetricPrefix(HKMetricPrefix.Milli)
            
        case HKQuantityTypeIdentifierDietaryEnergyConsumed:
            return HKUnit.kilocalorieUnit()
            
        case HKQuantityTypeIdentifierDietaryFatMonounsaturated:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryFatPolyunsaturated:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryFatSaturated:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryFatTotal:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryProtein:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietarySodium:
            return HKUnit.gramUnitWithMetricPrefix(HKMetricPrefix.Milli)
            
        case HKQuantityTypeIdentifierDietarySugar:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryWater:
            return HKUnit.literUnitWithMetricPrefix(HKMetricPrefix.Milli)
            
        case HKQuantityTypeIdentifierDistanceWalkingRunning:
            return HKUnit.mileUnit()
            
        case HKQuantityTypeIdentifierFlightsClimbed:
            return HKUnit.countUnit()
            
        case HKQuantityTypeIdentifierHeartRate:
            return HKUnit.countUnit().unitDividedByUnit(HKUnit.minuteUnit())
            
        case HKQuantityTypeIdentifierStepCount:
            return HKUnit.countUnit()
            
        case HKQuantityTypeIdentifierUVExposure:
            return HKUnit.countUnit()
            
        case HKWorkoutTypeIdentifier:
            return HKUnit.hourUnit()
            
        case HKQuantityTypeIdentifierDietaryFiber:
            return HKUnit.gramUnit()
        default:
            return nil
        }
    }
}

public extension HKSample {
    public var numeralValue: Double? {
        guard defaultUnit != nil else {
            return nil
        }
        switch sampleType {
        case is HKCategoryType:
            switch sampleType.identifier {
            case HKCategoryTypeIdentifierSleepAnalysis:
                let sample = (self as! HKCategorySample)
                let secs = HKQuantity(unit: HKUnit.secondUnit(), doubleValue: sample.endDate.timeIntervalSinceDate(sample.startDate))
                return secs.doubleValueForUnit(defaultUnit!)
            default:
                return nil
            }
            
        case is HKCorrelationType:
            switch sampleType.identifier {
            case HKCorrelationTypeIdentifierBloodPressure:
                return ((self as! HKCorrelation).objects.first as! HKQuantitySample).quantity.doubleValueForUnit(defaultUnit!)
            default:
                return nil
            }
            
        case is HKWorkoutType:
            let sample = (self as! HKWorkout)
            let secs = HKQuantity(unit: HKUnit.secondUnit(), doubleValue: sample.duration)
            return secs.doubleValueForUnit(defaultUnit!)
            
        case is HKQuantityType:
            return (self as! HKQuantitySample).quantity.doubleValueForUnit(defaultUnit!)
            
        default:
            return nil
        }
    }
    
    public var defaultUnit: HKUnit? { return sampleType.defaultUnit }
    
    public var hkType: HKSampleType? { return sampleType }
}

// Readable type description.
public extension HKSampleType {
    public var displayText: String? {
        switch identifier {
        case HKCategoryTypeIdentifierSleepAnalysis:
            return NSLocalizedString("Sleep", comment: "HealthKit data type")
            
        case HKCategoryTypeIdentifierAppleStandHour:
            return NSLocalizedString("Hours Standing", comment: "HealthKit data type")
            
        case HKCharacteristicTypeIdentifierBloodType:
            return NSLocalizedString("Blood Type", comment: "HealthKit data type")
            
        case HKCharacteristicTypeIdentifierBiologicalSex:
            return NSLocalizedString("Gender", comment: "HealthKit data type")
            
        case HKCharacteristicTypeIdentifierFitzpatrickSkinType:
            return NSLocalizedString("Skin Type", comment: "HealthKit data type")
            
        case HKCorrelationTypeIdentifierBloodPressure:
            return NSLocalizedString("Blood Pressure", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierActiveEnergyBurned:
            return NSLocalizedString("Active Energy Burned", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBasalEnergyBurned:
            return NSLocalizedString("Basal Energy Burned", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBloodGlucose:
            return NSLocalizedString("Blood Glucose", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBloodPressureDiastolic:
            return NSLocalizedString("Blood Pressure Diastolic", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBloodPressureSystolic:
            return NSLocalizedString("Blood Pressure Systolic", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBodyMass:
            return NSLocalizedString("Weight", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBodyMassIndex:
            return NSLocalizedString("Body Mass Index", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryCaffeine:
            return NSLocalizedString("Caffeine", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryCarbohydrates:
            return NSLocalizedString("Carbohydrates", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryCholesterol:
            return NSLocalizedString("Cholesterol", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryEnergyConsumed:
            return NSLocalizedString("Food calories", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFatMonounsaturated:
            return NSLocalizedString("Monounsaturated Fat", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFatPolyunsaturated:
            return NSLocalizedString("Polyunsaturated Fat", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFatSaturated:
            return NSLocalizedString("Saturated Fat", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFatTotal:
            return NSLocalizedString("Fat", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryProtein:
            return NSLocalizedString("Protein", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietarySodium:
            return NSLocalizedString("Salt", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietarySugar:
            return NSLocalizedString("Sugar", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryWater:
            return NSLocalizedString("Water", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDistanceWalkingRunning:
            return NSLocalizedString("Walking and Running Distance", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierFlightsClimbed:
            return NSLocalizedString("Flights Climbed", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierHeartRate:
            return NSLocalizedString("Heart Rate", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierStepCount:
            return NSLocalizedString("Step Count", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierUVExposure:
            return NSLocalizedString("UV Exposure", comment: "HealthKit data type")
            
        case HKWorkoutTypeIdentifier:
            return NSLocalizedString("Workouts/Meals", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBasalBodyTemperature:
            return NSLocalizedString("Basal Body Temperature", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBloodAlcoholContent:
            return NSLocalizedString("Blood Alcohol", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBodyFatPercentage:
            return NSLocalizedString("", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBodyTemperature:
            return NSLocalizedString("Body Temperature", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryBiotin:
            return NSLocalizedString("Biotin", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryCalcium:
            return NSLocalizedString("Calcium", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryChloride:
            return NSLocalizedString("Chloride", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryChromium:
            return NSLocalizedString("Chromium", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryCopper:
            return NSLocalizedString("Copper", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFiber:
            return NSLocalizedString("Fiber", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFolate:
            return NSLocalizedString("Folate", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryIodine:
            return NSLocalizedString("Iodine", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryIron:
            return NSLocalizedString("Iron", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryMagnesium:
            return NSLocalizedString("Magnesium", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryManganese:
            return NSLocalizedString("Manganese", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryMolybdenum:
            return NSLocalizedString("Molybdenum", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryNiacin:
            return NSLocalizedString("Niacin", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryPantothenicAcid:
            return NSLocalizedString("Pantothenic Acid", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryPhosphorus:
            return NSLocalizedString("Phosphorus", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryPotassium:
            return NSLocalizedString("Potassium", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryRiboflavin:
            return NSLocalizedString("Riboflavin", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietarySelenium:
            return NSLocalizedString("Selenium", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryThiamin:
            return NSLocalizedString("Thiamin", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryVitaminA:
            return NSLocalizedString("Vitamin A", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryVitaminB12:
            return NSLocalizedString("Vitamin B12", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryVitaminB6:
            return NSLocalizedString("Vitamin B6", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryVitaminC:
            return NSLocalizedString("Vitamin C", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryVitaminD:
            return NSLocalizedString("Vitamin D", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryVitaminE:
            return NSLocalizedString("Vitamin E", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryVitaminK:
            return NSLocalizedString("Vitamin K", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryZinc:
            return NSLocalizedString("Zinc", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierElectrodermalActivity:
            return NSLocalizedString("Electrodermal Activity", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierForcedExpiratoryVolume1:
            return NSLocalizedString("FEV1", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierForcedVitalCapacity:
            return NSLocalizedString("FVC", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierHeight:
            return NSLocalizedString("Height", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierInhalerUsage:
            return NSLocalizedString("Inhaler Usage", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierLeanBodyMass:
            return NSLocalizedString("Lean Body Mass", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierNikeFuel:
            return NSLocalizedString("Nike Fuel", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierNumberOfTimesFallen:
            return NSLocalizedString("Times Fallen", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierOxygenSaturation:
            return NSLocalizedString("Blood Oxygen Saturation", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierPeakExpiratoryFlowRate:
            return NSLocalizedString("PEF", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierPeripheralPerfusionIndex:
            return NSLocalizedString("PPI", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierRespiratoryRate:
            return NSLocalizedString("RR", comment: "HealthKit data type")
            
        default:
            return nil
        }
    }
}

private let refDate  = NSDate(timeIntervalSinceReferenceDate: 0)
private let noLimit  = Int(HKObjectQueryNoLimit)
@available(iOS 9.0, *)
private let noAnchor = HKQueryAnchor(fromValue: Int(HKAnchoredObjectQueryNoAnchor))
private let dateAsc  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
private let dateDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
private let lastChartsDataCacheKey = "lastChartsDataCacheKey"


/*
protocol MCSample {
    var startDate    : NSDate        { get }
    var endDate      : NSDate        { get }
    var numeralValue : Double?       { get }
    var defaultUnit  : HKUnit?       { get }
    var hkType       : HKSampleType? { get }
}

private let refDate  = NSDate(timeIntervalSinceReferenceDate: 0)
private let noLimit  = Int(HKObjectQueryNoLimit)
@available(iOS 9.0, *)
private let noAnchor = HKQueryAnchor(fromValue: Int(HKAnchoredObjectQueryNoAnchor))
private let dateAsc  = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
private let dateDesc = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
private let lastChartsDataCacheKey = "lastChartsDataCacheKey"

// Enums
public enum HealthManagerStatisticsRangeType : Int {
    case Week = 0
    case Month
    case Year
}

public enum AggregateQueryResult {
    case AggregatedSamples([MCAggregateSample])
    case Statistics([HKStatistics])
    case None
}

public struct MCAggregateSample : MCSample {
    public var startDate    : NSDate
    public var endDate      : NSDate
    public var numeralValue : Double?
    public var defaultUnit  : HKUnit?
    public var hkType       : HKSampleType?
    
    var avgTotal: Double = 0.0
    var avgCount: Int = 0
    
    init(sample: MCSample) {
        startDate = sample.startDate
        endDate = sample.endDate
        numeralValue = nil
        defaultUnit = nil
        hkType = sample.hkType
        if #available(iOS 9.0, *) {
            self.incr(sample)
        } else {
            // Fallback on earlier versions
        }
    }
    
    init(value: Double?, sampleType: HKSampleType?) {
        startDate = NSDate()
        endDate = NSDate()
        numeralValue = value
        if #available(iOS 9.0, *) {
            defaultUnit = sampleType?.defaultUnit
        } else {
            // Fallback on earlier versions
        }
        hkType = sampleType
    }
    
    @available(iOS 9.0, *)
    mutating func incr(sample: MCSample) {
        if hkType == sample.hkType {
            startDate = min(sample.startDate, startDate)
            endDate = max(sample.endDate, endDate)
            
            switch hkType!.identifier {
            case HKCategoryTypeIdentifierSleepAnalysis:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKCorrelationTypeIdentifierBloodPressure:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKQuantityTypeIdentifierActiveEnergyBurned:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierBasalEnergyBurned:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKQuantityTypeIdentifierBloodGlucose:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKQuantityTypeIdentifierBloodPressureSystolic:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKQuantityTypeIdentifierBloodPressureDiastolic:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKQuantityTypeIdentifierBodyMass:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKQuantityTypeIdentifierBodyMassIndex:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKQuantityTypeIdentifierDietaryCaffeine:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryCarbohydrates:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryCholesterol:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryEnergyConsumed:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryFatMonounsaturated:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryFatPolyunsaturated:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryFatSaturated:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryFatTotal:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryProtein:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietarySodium:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietarySugar:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDietaryWater:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierDistanceWalkingRunning:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierFlightsClimbed:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierHeartRate:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKQuantityTypeIdentifierStepCount:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            case HKQuantityTypeIdentifierUVExposure:
                avgTotal += sample.numeralValue!
                avgCount += 1
                
            case HKWorkoutTypeIdentifier:
                numeralValue = (numeralValue ?? 0.0) + sample.numeralValue!
                
            default:
                print("Cannot aggregate \(hkType)")
            }
            
        } else {
            print("Invalid sample aggregation between \(hkType) and \(sample.hkType)")
        }
    }
    
    @available(iOS 9.0, *)
    mutating func final() {
        switch hkType!.identifier {
        case HKCategoryTypeIdentifierSleepAnalysis:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKCorrelationTypeIdentifierBloodPressure:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKQuantityTypeIdentifierBasalEnergyBurned:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKQuantityTypeIdentifierBloodGlucose:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKQuantityTypeIdentifierBloodPressureSystolic:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKQuantityTypeIdentifierBloodPressureDiastolic:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKQuantityTypeIdentifierBodyMass:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKQuantityTypeIdentifierBodyMassIndex:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKQuantityTypeIdentifierHeartRate:
            numeralValue = avgTotal / Double(avgCount)
            
        case HKQuantityTypeIdentifierUVExposure:
            numeralValue = avgTotal / Double(avgCount)
            
        default:
            ()
        }
    }
}
extension HKStatistics: MCSample { }
extension HKSample: MCSample { }

public extension HKStatistics {
    @available(iOS 9.0, *)
    var quantity: HKQuantity? {
        switch quantityType.identifier {
            
        case HKCategoryTypeIdentifierSleepAnalysis:
            return averageQuantity()
            
        case HKCorrelationTypeIdentifierBloodPressure:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierActiveEnergyBurned:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierBasalEnergyBurned:
            return averageQuantity()
            
        case HKQuantityTypeIdentifierBodyMass:
            return averageQuantity()
            
        case HKQuantityTypeIdentifierBodyMassIndex:
            return averageQuantity()
            
        case HKQuantityTypeIdentifierBloodGlucose:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierBloodPressureSystolic:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierBloodPressureDiastolic:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryCaffeine:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryCarbohydrates:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryCholesterol:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryEnergyConsumed:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryFatMonounsaturated:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryFatPolyunsaturated:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryFatSaturated:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryFatTotal:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryProtein:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietarySodium:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietarySugar:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDietaryWater:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierDistanceWalkingRunning:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierFlightsClimbed:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierHeartRate:
            return averageQuantity()
            
        case HKQuantityTypeIdentifierStepCount:
            return sumQuantity()
            
        case HKQuantityTypeIdentifierUVExposure:
            return sumQuantity()
            
        case HKWorkoutTypeIdentifier:
            return sumQuantity()
            
        default:
            print("Invalid quantity type \(quantityType.identifier) for HKStatistics")
            return sumQuantity()
        }
    }
    
//    @available(iOS 9.0, *)
    public var numeralValue: Double? {
        if #available(iOS 9.0, *) {
            guard defaultUnit != nil && quantity != nil else {
                return nil
            }
        } else {
            // Fallback on earlier versions
        }
        if #available(iOS 9.0, *) {
            switch quantityType.identifier {
            case HKCategoryTypeIdentifierSleepAnalysis:
                fallthrough
            case HKCorrelationTypeIdentifierBloodPressure:
                fallthrough
            case HKQuantityTypeIdentifierActiveEnergyBurned:
                fallthrough
            case HKQuantityTypeIdentifierBasalEnergyBurned:
                fallthrough
            case HKQuantityTypeIdentifierBloodGlucose:
                fallthrough
            case HKQuantityTypeIdentifierBloodPressureDiastolic:
                fallthrough
            case HKQuantityTypeIdentifierBloodPressureSystolic:
                fallthrough
            case HKQuantityTypeIdentifierBodyMass:
                fallthrough
            case HKQuantityTypeIdentifierBodyMassIndex:
                fallthrough
            case HKQuantityTypeIdentifierDietaryCaffeine:
                fallthrough
            case HKQuantityTypeIdentifierDietaryCarbohydrates:
                fallthrough
            case HKQuantityTypeIdentifierDietaryCholesterol:
                fallthrough
            case HKQuantityTypeIdentifierDietaryEnergyConsumed:
                fallthrough
            case HKQuantityTypeIdentifierDietaryFatMonounsaturated:
                fallthrough
            case HKQuantityTypeIdentifierDietaryFatPolyunsaturated:
                fallthrough
            case HKQuantityTypeIdentifierDietaryFatSaturated:
                fallthrough
            case HKQuantityTypeIdentifierDietaryFatTotal:
                fallthrough
            case HKQuantityTypeIdentifierDietaryProtein:
                fallthrough
            case HKQuantityTypeIdentifierDietarySodium:
                fallthrough
            case HKQuantityTypeIdentifierDietarySugar:
                fallthrough
            case HKQuantityTypeIdentifierDietaryWater:
                fallthrough
            case HKQuantityTypeIdentifierDistanceWalkingRunning:
                fallthrough
            case HKQuantityTypeIdentifierFlightsClimbed:
                fallthrough
            case HKQuantityTypeIdentifierHeartRate:
                fallthrough
            case HKQuantityTypeIdentifierStepCount:
                fallthrough
            case HKQuantityTypeIdentifierUVExposure:
                fallthrough
            case HKWorkoutTypeIdentifier:
                return quantity!.doubleValueForUnit(defaultUnit!)
            default:
                return nil
            }
        } else {
            return nil
        }
    }
    
    public var defaultUnit: HKUnit? { if #available(iOS 9.0, *) {
        return quantityType.defaultUnit
    } else {
        return HKUnit.gramUnit()
        }
    }
    
    public var hkType: HKSampleType? { return quantityType }
}

public extension HKSample {
//    @available(iOS 9.0, *)
    public var numeralValue: Double? {
        guard defaultUnit != nil else {
            return nil
        }
        if #available(iOS 9.0, *) {
            switch sampleType.identifier {
            case HKCategoryTypeIdentifierSleepAnalysis:
                let sample = (self as! HKCategorySample)
                let secs = HKQuantity(unit: HKUnit.secondUnit(), doubleValue: sample.endDate.timeIntervalSinceDate(sample.startDate))
                return secs.doubleValueForUnit(defaultUnit!)
                
            case HKCorrelationTypeIdentifierBloodPressure:
                return ((self as! HKCorrelation).objects.first as! HKQuantitySample).quantity.doubleValueForUnit(defaultUnit!)
                
            case HKQuantityTypeIdentifierActiveEnergyBurned:
                fallthrough
                
            case HKQuantityTypeIdentifierBasalEnergyBurned:
                fallthrough
                
            case HKQuantityTypeIdentifierBloodGlucose:
                fallthrough
                
            case HKQuantityTypeIdentifierBloodPressureSystolic:
                fallthrough
                
            case HKQuantityTypeIdentifierBloodPressureDiastolic:
                fallthrough
                
            case HKQuantityTypeIdentifierBodyMass:
                fallthrough
                
            case HKQuantityTypeIdentifierBodyMassIndex:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryCarbohydrates:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryEnergyConsumed:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryProtein:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryFatMonounsaturated:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryFatPolyunsaturated:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryFatSaturated:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryFatTotal:
                fallthrough
                
            case HKQuantityTypeIdentifierDietarySugar:
                fallthrough
                
            case HKQuantityTypeIdentifierDietarySodium:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryCaffeine:
                fallthrough
                
            case HKQuantityTypeIdentifierDietaryWater:
                fallthrough
                
            case HKQuantityTypeIdentifierDistanceWalkingRunning:
                fallthrough
                
            case HKQuantityTypeIdentifierFlightsClimbed:
                fallthrough
                
            case HKQuantityTypeIdentifierHeartRate:
                fallthrough
                
            case HKQuantityTypeIdentifierStepCount:
                fallthrough
                
            case HKQuantityTypeIdentifierUVExposure:
                return (self as! HKQuantitySample).quantity.doubleValueForUnit(defaultUnit!)
                
            case HKWorkoutTypeIdentifier:
                let sample = (self as! HKWorkout)
                let secs = HKQuantity(unit: HKUnit.secondUnit(), doubleValue: sample.duration)
                return secs.doubleValueForUnit(defaultUnit!)
                
            default:
                return nil
            }
        } else {
            return nil
        }
    }
    
    public var allNumeralValues: [Double]? {
        if #available(iOS 9.0, *) {
            return numeralValue != nil ? [numeralValue!] : nil
        } else {
            return [2.0]
        }
    }
    
    public var defaultUnit: HKUnit? { if #available(iOS 9.0, *) {
        return sampleType.defaultUnit
    } else {
            return HKUnit.gramUnit()
        }
    }
    
    public var hkType: HKSampleType? { return sampleType }
}

/*public extension HKSampleType {
    @available(iOS 9.0, *)
    public var displayText: String? {
        switch identifier {
        case HKCategoryTypeIdentifierSleepAnalysis:
            return NSLocalizedString("Sleep", comment: "HealthKit data type")
            
        case HKCorrelationTypeIdentifierBloodPressure:
            return NSLocalizedString("Blood pressure", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierActiveEnergyBurned:
            return NSLocalizedString("Active Energy Burned", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBasalEnergyBurned:
            return NSLocalizedString("Basal Energy Burned", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBloodGlucose:
            return NSLocalizedString("Blood Glucose", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBloodPressureDiastolic:
            return NSLocalizedString("Blood Pressure Diastolic", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBloodPressureSystolic:
            return NSLocalizedString("Blood Pressure Systolic", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBodyMass:
            return NSLocalizedString("Weight", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierBodyMassIndex:
            return NSLocalizedString("Body Mass Index", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryCaffeine:
            return NSLocalizedString("Caffeine", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryCarbohydrates:
            return NSLocalizedString("Carbohydrates", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryCholesterol:
            return NSLocalizedString("Cholesterol", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryEnergyConsumed:
            return NSLocalizedString("Food calories", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFatMonounsaturated:
            return NSLocalizedString("Monounsaturated Fat", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFatPolyunsaturated:
            return NSLocalizedString("Polyunsaturated Fat", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFatSaturated:
            return NSLocalizedString("Saturated Fat", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryFatTotal:
            return NSLocalizedString("Fat", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryProtein:
            return NSLocalizedString("Protein", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietarySodium:
            return NSLocalizedString("Salt", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietarySugar:
            return NSLocalizedString("Sugar", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDietaryWater:
            return NSLocalizedString("Water", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierDistanceWalkingRunning:
            return NSLocalizedString("Walking and Running Distance", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierFlightsClimbed:
            return NSLocalizedString("Flights Climbed", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierHeartRate:
            return NSLocalizedString("Heartrate", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierStepCount:
            return NSLocalizedString("Step Count", comment: "HealthKit data type")
            
        case HKQuantityTypeIdentifierUVExposure:
            return NSLocalizedString("UV Exposure", comment: "HealthKit data type")
            
        case HKWorkoutTypeIdentifier:
            return NSLocalizedString("Workouts/Meals", comment: "HealthKit data type")
            
        default:
            return nil
        }
    }
    
    @available(iOS 9.0, *)
    public var defaultUnit: HKUnit? {
        let isMetric: Bool = NSLocale.currentLocale().objectForKey(NSLocaleUsesMetricSystem)!.boolValue
        switch identifier {
        case HKCategoryTypeIdentifierSleepAnalysis:
            return HKUnit.hourUnit()
            
        case HKCorrelationTypeIdentifierBloodPressure:
            return HKUnit.millimeterOfMercuryUnit()
            
        case HKQuantityTypeIdentifierActiveEnergyBurned:
            return HKUnit.kilocalorieUnit()
            
        case HKQuantityTypeIdentifierBasalEnergyBurned:
            return HKUnit.kilocalorieUnit()
            
        case HKQuantityTypeIdentifierBloodGlucose:
            return HKUnit.gramUnitWithMetricPrefix(.Milli).unitDividedByUnit(HKUnit.literUnitWithMetricPrefix(.Deci))
            
        case HKQuantityTypeIdentifierBloodPressureDiastolic:
            return HKUnit.millimeterOfMercuryUnit()
            
        case HKQuantityTypeIdentifierBloodPressureSystolic:
            return HKUnit.millimeterOfMercuryUnit()
            
        case HKQuantityTypeIdentifierBodyMass:
            return isMetric ? HKUnit.gramUnitWithMetricPrefix(.Kilo) : HKUnit.poundUnit()
            
        case HKQuantityTypeIdentifierBodyMassIndex:
            return HKUnit.countUnit()
            
        case HKQuantityTypeIdentifierDietaryCaffeine:
            return HKUnit.gramUnitWithMetricPrefix(HKMetricPrefix.Milli)
            
        case HKQuantityTypeIdentifierDietaryCarbohydrates:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryCholesterol:
            return HKUnit.gramUnitWithMetricPrefix(HKMetricPrefix.Milli)
            
        case HKQuantityTypeIdentifierDietaryEnergyConsumed:
            return HKUnit.kilocalorieUnit()
            
        case HKQuantityTypeIdentifierDietaryFatMonounsaturated:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryFatPolyunsaturated:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryFatSaturated:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryFatTotal:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryProtein:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietarySodium:
            return HKUnit.gramUnitWithMetricPrefix(HKMetricPrefix.Milli)
            
        case HKQuantityTypeIdentifierDietarySugar:
            return HKUnit.gramUnit()
            
        case HKQuantityTypeIdentifierDietaryWater:
            return HKUnit.literUnitWithMetricPrefix(HKMetricPrefix.Milli)
            
        case HKQuantityTypeIdentifierDistanceWalkingRunning:
            return HKUnit.mileUnit()
            
        case HKQuantityTypeIdentifierFlightsClimbed:
            return HKUnit.countUnit()
            
        case HKQuantityTypeIdentifierHeartRate:
            return HKUnit.countUnit().unitDividedByUnit(HKUnit.minuteUnit())
            
        case HKQuantityTypeIdentifierStepCount:
            return HKUnit.countUnit()
            
        case HKQuantityTypeIdentifierUVExposure:
            return HKUnit.countUnit()
            
        case HKWorkoutTypeIdentifier:
            return HKUnit.hourUnit()
            
        default:
            return nil
        }
    }
} */
*/

let stWorkout = 0.0
let stSleep = 0.33
let stFast = 0.66
let stEat = 1.0


public class QueryHK: NSObject {

    let healthKitStore: HKHealthStore = HKHealthStore()
    var heightHK:HKQuantitySample?
    var weightHK:HKQuantitySample?
    var weightLocalizedString:String = "151 lb"
    var heightLocalizedString:String = "5 ft"
    let HMErrorDomain                = "HMErrorDomain"
    
    private override init() {
        super.init()
    }
    
/*    var proteinHK:HKQuantitySample
    var bmiHK:Double = 22.1
    let kUnknownString   = "Unknown"
    let HMErrorDomain                        = "HMErrorDomain"
    
    var HKBMIString:String = "24.3"
    var weightLocalizedString:String = "151 lb"
    var heightLocalizedString:String = "5 ft"
    var proteinLocalizedString:String = "50 gms"
    typealias HMTypedSampleBlock    = (samples: [HKSampleType: [MCSample]], error: NSError?) -> Void
    typealias HMCircadianBlock          = (intervals: [(NSDate, CircadianEvent)], error: NSError?) -> Void
    typealias HMCircadianAggregateBlock = (aggregates: [(NSDate, Double)], error: NSError?) -> Void
    typealias HMFastingCorrelationBlock = ([(NSDate, Double, MCSample)], NSError?) -> Void
    typealias HMSampleBlock         = (samples: [MCSample], error: NSError?) -> Void
    enum CircadianEvent {
        case Meal
        case Fast
        case Sleep
        case Exercise */
    
    typealias HMTypedSampleBlock    = (samples: [HKSampleType: [MCSample]], error: NSError?) -> Void
    typealias HMCircadianBlock          = (intervals: [(NSDate, CircadianEvent)], error: NSError?) -> Void
    typealias HMCircadianAggregateBlock = (aggregates: [(NSDate, Double)], error: NSError?) -> Void
    typealias HMFastingCorrelationBlock = ([(NSDate, Double, MCSample)], NSError?) -> Void
    typealias HMSampleBlock         = (samples: [MCSample], error: NSError?) -> Void

    enum CircadianEvent {
        case Meal
        case Fast
        case Sleep
        case Exercise
    }
    public static let sharedManager = QueryHK()

    public func saveWorkout(startDate: NSDate, endDate: NSDate, activityType: HKWorkoutActivityType, distance: Double, distanceUnit: HKUnit, kiloCalories: Double, metadata:NSDictionary, completion: ( (Bool, NSError!) -> Void)!)
    {
//        log.debug("Saving workout \(startDate) \(endDate)")

        let distanceQuantity = HKQuantity(unit: distanceUnit, doubleValue: distance)
        let caloriesQuantity = HKQuantity(unit: HKUnit.kilocalorieUnit(), doubleValue: kiloCalories)

        let workout = HKWorkout(activityType: activityType, startDate: startDate, endDate: endDate, duration: abs(endDate.timeIntervalSinceDate(startDate)), totalEnergyBurned: caloriesQuantity, totalDistance: distanceQuantity, metadata: metadata  as! [String:String])

        healthKitStore.saveObject(workout, withCompletion: { (success, error) -> Void in
            if( error != nil  ) { completion(success,error) }
            else { completion(success,nil) }
        })
    }

    public func saveRunningWorkout(startDate: NSDate, endDate: NSDate, distance:Double, distanceUnit: HKUnit, kiloCalories: Double, metadata: NSDictionary, completion: ( (Bool, NSError!) -> Void)!)
    {
        saveWorkout(startDate, endDate: endDate, activityType: HKWorkoutActivityType.Running, distance: distance, distanceUnit: distanceUnit, kiloCalories: kiloCalories, metadata: metadata, completion: completion)
    }

    public func saveCyclingWorkout(startDate: NSDate, endDate: NSDate, distance:Double, distanceUnit: HKUnit, kiloCalories: Double, metadata: NSDictionary, completion: ( (Bool, NSError!) -> Void)!)
    {
        saveWorkout(startDate, endDate: endDate, activityType: HKWorkoutActivityType.Cycling, distance: distance, distanceUnit: distanceUnit, kiloCalories: kiloCalories, metadata: metadata, completion: completion)
    }

    public func saveSwimmingWorkout(startDate: NSDate, endDate: NSDate, distance:Double, distanceUnit: HKUnit, kiloCalories: Double, metadata: NSDictionary, completion: ( (Bool, NSError!) -> Void)!)
    {
        saveWorkout(startDate, endDate: endDate, activityType: HKWorkoutActivityType.Swimming, distance: distance, distanceUnit: distanceUnit, kiloCalories: kiloCalories, metadata: metadata, completion: completion)
    }

    public func savePreparationAndRecoveryWorkout(startDate: NSDate, endDate: NSDate, distance:Double, distanceUnit: HKUnit, kiloCalories: Double, metadata: NSDictionary, completion: ( (Bool, NSError!) -> Void)!)
    {
        saveWorkout(startDate, endDate: endDate, activityType: HKWorkoutActivityType.PreparationAndRecovery, distance: distance, distanceUnit: distanceUnit, kiloCalories: kiloCalories, metadata: metadata, completion: completion)
    }

    public func updateWeight()
        {
            let sampleType = HKSampleType.quantityTypeForIdentifier (HKQuantityTypeIdentifierBodyMass)
            
            readMostRecentSample(sampleType!, completion: { (mostRecentWeight, error) -> Void in
                
                if( error != nil )
                {
                    print("Error reading weight from HealthKit Store: \(error.localizedDescription)")
                    return;
                }
                
                //                var weightLocalizedString = self.kUnknownString;
                self.weightHK = (mostRecentWeight as? HKQuantitySample)!;
                let kilograms = self.weightHK!.quantity.doubleValueForUnit(HKUnit.gramUnitWithMetricPrefix(.Kilo))
//                {
//                    let weightFormatter = NSMassFormatter()
//                    weightFormatter.forPersonMassUse = true;
//                    weightLocalizedString = weightFormatter.stringFromKilograms(kilograms)
 //               }
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.updateBMI()
//                    print("in weight update of interface controller: \(weightLocalizedString)")
                });
            });
        }

    public func updateHeight()
        {
            let sampleType = HKSampleType.quantityTypeForIdentifier(HKQuantityTypeIdentifierHeight)
            readMostRecentSample(sampleType!, completion: { (mostRecentHeight, error) -> Void in
                
                if( error != nil )
                {
                    print("Error reading height from HealthKit Store: \(error.localizedDescription)")
                    return;
                }
                
//         var heightLocalizedString = self.kUnknownString;
                self.heightHK = (mostRecentHeight as? HKQuantitySample)!;
                let meters = self.heightHK!.quantity.doubleValueForUnit(HKUnit.meterUnit())
//                {
//                    let heightFormatter = NSLengthFormatter()
//                    heightFormatter.forPersonHeightUse = true;
//         self.heightLocalizedString = heightFormatter.stringFromMeters(meters);
//                }
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
//                    print("in height update of interface controller: \(self.heightLocalizedString)")
                    self.updateBMI()
                });
            })
        }

    public func readMostRecentSample(sampleType:HKSampleType , completion:     ((HKSample!, NSError!) -> Void)!)
        {
            let past = NSDate.distantPast()
            let now   = NSDate()
            let mostRecentPredicate = HKQuery.predicateForSamplesWithStartDate(past, endDate:now, options: .None)
            let sortDescriptor = NSSortDescriptor(key:HKSampleSortIdentifierStartDate, ascending: false)
            let limit = 1
            let sampleQuery = HKSampleQuery(sampleType: sampleType, predicate: mostRecentPredicate, limit: limit, sortDescriptors: [sortDescriptor])
            { (sampleQuery, results, error ) -> Void in
                if let queryError = error {
                    completion(nil,error)
                    return;
                }
                let mostRecentSample = results!.first as? HKQuantitySample
                if completion != nil {
                    completion(mostRecentSample,nil)
                }
            }
            healthKitStore.executeQuery(sampleQuery)
        }
    
    public func updateBMI()
    {
       //  {
            let weightInKilograms = weightHK!.quantity.doubleValueForUnit(HKUnit.gramUnitWithMetricPrefix(.Kilo))
            let heightInMeters = heightHK!.quantity.doubleValueForUnit(HKUnit.meterUnit())
//            bmiHK = calculateBMIWithWeightInKilograms(weightInKilograms, heightInMeters: heightInMeters)!
      //  }
        //            print("new bmi in IntroInterfaceController: \(bmiHK)")
//        HKBMIString = String(format: "%.1f", bmiHK)
    }
    
    
    public func calculateBMIWithWeightInKilograms(weightInKilograms:Double, heightInMeters:Double) -> Double?
    {
        if heightInMeters == 0 {
            return nil;
        }
        return (weightInKilograms/(heightInMeters*heightInMeters));
    }
    
/*    func updateProtein()
    {
        let sampleType = HKSampleType.quantityTypeForIdentifier (HKQuantityTypeIdentifierDietaryProtein)
        
        readMostRecentSample(sampleType!, completion: { (mostRecentProtein, error) -> Void in
            
            if( error != nil )
            {
                print("Error reading dietary protein from HealthKit Store: \(error.localizedDescription)")
                return;
            }
            
            proteinHK = mostRecentProtein as? HKQuantitySample;
            if let grams = proteinHK?.quantity.doubleValueForUnit(HKUnit.gramUnit()) {
                //                    let weightFormatter = NSMassFormatter()
                //                    self.proteinLocalizedString = weightFormatter.unitStringFromValue(grams, unit: HKUnit.gramUnit)
            }
            
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    print("in protein update of interface controller: \(proteinLocalizedString)")
                });
            });
        }
    
    public func updateHealthInfo() {
        updateWeight();
        print("updated weight info")
        updateHeight();
        print("updated height info")
        updateBMI();
        print("updated bmi info")
    } */

    
    public func reloadDataTake2() {
        typealias Event = (NSDate, Double)
        typealias IEvent = (Double, Double)?
        
        let yesterday = 1.days.ago
        let startDate = yesterday
        
        fetchCircadianEventIntervals(startDate) { (intervals, error) -> Void in
            dispatch_async(dispatch_get_main_queue(), {
                guard error == nil else {
                    print("Failed to fetch circadian events: \(error)")
                    return
                }
                
                if intervals.isEmpty {
                    print("series is Empty")
                    
                } else {
                    
                    let vals : [(x: Double, y: Double)] = intervals.map { event in
                        let startTimeInFractionalHours = event.0.timeIntervalSinceDate(startDate) / 3600.0
                        let metabolicStateAsDouble = self.valueOfCircadianEvent(event.1)
                        return (x: startTimeInFractionalHours, y: metabolicStateAsDouble)
                    }
                    
                    let initialAccumulator : (Double, Double, Double, IEvent, Bool, Double, Bool) =
                        (0.0, 0.0, 0.0, nil, true, 0.0, false)
                    
                    let stats = vals.filter { $0.0 >= yesterday.timeIntervalSinceDate(startDate) }
                        .reduce(initialAccumulator, combine:
                            { (acc, event) in
                                // Named accumulator components
                                var newEatingTime = acc.0
                                let lastEatingTime = acc.1
                                var maxFastingWindow = acc.2
                                var currentFastingWindow = acc.5
                                
                                // Named components from the current event.
                                let eventEndpointDate = event.0
                                let eventMetabolicState = event.1
                                
                                let prevEvent = acc.3
                                let prevEndpointWasIntervalStart = acc.4
                                let prevEndpointWasIntervalEnd = !acc.4
                                var prevStateWasFasting = acc.6
                                let isFasting = eventMetabolicState != stEat
                                if prevEndpointWasIntervalEnd {
                                    let prevEventEndpointDate = prevEvent!.0
                                    let duration = eventEndpointDate - prevEventEndpointDate
                                    
                                    if prevStateWasFasting && isFasting {
                                        currentFastingWindow += duration
                                        maxFastingWindow = maxFastingWindow > currentFastingWindow ? maxFastingWindow : currentFastingWindow
                                        
                                    } else if isFasting {
                                        currentFastingWindow = duration
                                        maxFastingWindow = maxFastingWindow > currentFastingWindow ? maxFastingWindow : currentFastingWindow
                                        
                                    } else if eventMetabolicState == stEat {
                                        newEatingTime += duration
                                    }
                                } else {
                                    prevStateWasFasting = prevEvent == nil ? false : prevEvent!.1 != stEat
                                }
                                
                                let newLastEatingTime = eventMetabolicState == stEat ? eventEndpointDate : lastEatingTime
                                
                                // Return a new accumulator.
                                return (
                                    newEatingTime,
                                    newLastEatingTime,
                                    maxFastingWindow,
                                    event,
                                    prevEndpointWasIntervalEnd,
                                    currentFastingWindow,
                                    prevStateWasFasting
                                )
                        })
                    
                    let today = NSDate().startOf(.Day, inRegion: Region())
                    let lastAte : NSDate? = stats.1 == 0 ? nil : ( startDate + Int(round(stats.1 * 3600.0)).seconds )
                    print("stored lastAteAsNSDate \(lastAte)")
//                    MetricsStore.sharedInstance.lastAteAsNSDate = lastAte!
                    
                    let fastingHrs = Int(floor(stats.2))
                    let fastingMins = (today + Int(round((stats.2 % 1.0) * 60.0)).minutes).toString(DateFormat.Custom("mm"))!
                    //                        self.fastingLabel.text = "\(fastingHrs):\(fastingMins)"
                    print("in IntroInterfaceController, fasting hours: \(fastingHrs)")
                    print("   and fasting minutes: \(fastingMins)")
//                    MetricsStore.sharedInstance.fastingTime = "\(fastingHrs):\(fastingMins)"
                    
                    let currentFastingHrs = Int(floor(stats.5))
                    let currentFastingMins = (today + Int(round((stats.5 % 1.0) * 60.0)).minutes).toString(DateFormat.Custom("mm"))!

                    print("current fasting hours: \(currentFastingHrs)")
                    print("   and current fasting minutes: \(currentFastingMins)")
//                    MetricsStore.sharedInstance.currentFastingTime = "\(currentFastingHrs):\(currentFastingMins)"
                    
                    let newLastEatingTimeHrs = Int(floor(stats.1))
                    let newLastEatingTimeMins = (today + Int(round((stats.1 % 1.0) * 60.0)).minutes).toString(DateFormat.Custom("mm"))!
                    
                    print("last eating time: \(newLastEatingTimeHrs)")
                    print("   and last eating time minutes: \(newLastEatingTimeMins)")
//                    MetricsStore.sharedInstance.lastEatingTime = "\(newLastEatingTimeHrs):\(newLastEatingTimeMins)"
                    
                    
                    //                        self.eatingLabel.text  = (today + Int(stats.0 * 3600.0).seconds).toString(DateFormat.Custom("HH:mm"))!
                    //                        self.lastAteLabel.text = lastAte == nil ? "N/A" : lastAte!.toString(DateFormat.Custom("HH:mm"))!
                }
                //                    self.mealChart.setNeedsDisplay()
                
            })
        }
    }
    
    func fetchCircadianEventIntervals(startDate: NSDate = 1.days.ago,
                                      endDate: NSDate = NSDate(),
                                      completion: HMCircadianBlock)
    {
        typealias Event = (NSDate, CircadianEvent)
        typealias IEvent = (Double, CircadianEvent)
        
        let sleepTy = HKObjectType.categoryTypeForIdentifier(HKCategoryTypeIdentifierSleepAnalysis)!
        let workoutTy = HKWorkoutType.workoutType()
        let datePredicate = HKQuery.predicateForSamplesWithStartDate(startDate, endDate: endDate, options: .None)
        let typesAndPredicates = [sleepTy: datePredicate, workoutTy: datePredicate]
        
        fetchSamples(typesAndPredicates) { (events, error) -> Void in
            guard error == nil && !events.isEmpty else {
                completion(intervals: [], error: error)
                return
            }
            let extendedEvents = events.flatMap { (ty,vals) -> [Event]? in
                switch ty {
                case is HKWorkoutType:
                    return vals.flatMap { s -> [Event] in
                        let st = s.startDate < startDate ? startDate : s.startDate
                        let en = s.endDate
                        guard let v = s as? HKWorkout else { return [] }
                        switch v.workoutActivityType {
                        case HKWorkoutActivityType.PreparationAndRecovery:
                            return [(st, .Meal), (en, .Meal)]
                        default:
                            return [(st, .Exercise), (en, .Exercise)]
//                            MetricsStore.sharedInstance.Exercise = en
                        }
                    }
                    
                case is HKCategoryType:
                    guard ty.identifier == HKCategoryTypeIdentifierSleepAnalysis else {
                        return nil
                    }
                    return vals.flatMap { s -> [Event] in
                        let st = s.startDate < startDate ? startDate : s.startDate
                        let en = s.endDate
                        return [(st, .Sleep), (en, .Sleep)]
//                        MetricsStore.sharedInstance.Sleep = en
                    }
                    
                default:
                    print("Unexpected type \(ty.identifier) while fetching circadian event intervals")
                    return nil
                }
            }
            
            let sortedEvents = extendedEvents.flatten().sort { (a,b) in return a.0 < b.0 }
            let epsilon = 1.seconds
            let lastev = sortedEvents.last ?? sortedEvents.first!
            let lst = lastev.0 == endDate ? [] : [(lastev.0, CircadianEvent.Fast), (endDate, CircadianEvent.Fast)]
            
            
            let initialAccumulator : ([Event], Bool, Event!) = ([], true, nil)
            let endpointArray = sortedEvents.reduce(initialAccumulator, combine:
                { (acc, event) in
                    let eventEndpointDate = event.0
                    let eventMetabolicState = event.1
                    
                    let resultArray = acc.0
                    let eventIsIntervalStart = acc.1
                    let prevEvent = acc.2
                    
                    let nextEventAsIntervalStart = !acc.1
                    
                    guard prevEvent != nil else {
                        // Skip prefix indicates whether we should add a fasting interval before the first event.
                        let skipPrefix = eventEndpointDate == startDate || startDate == NSDate.distantPast()
                        let newResultArray = (skipPrefix ? [event] : [(startDate, CircadianEvent.Fast), (eventEndpointDate, CircadianEvent.Fast), event])
                        return (newResultArray, nextEventAsIntervalStart, event)
                    }
                    
                    let prevEventEndpointDate = prevEvent.0
                    
                    if (eventIsIntervalStart && prevEventEndpointDate == eventEndpointDate) {
                        
                        let newResult = resultArray + [(eventEndpointDate + epsilon, eventMetabolicState)]
                        return (newResult, nextEventAsIntervalStart, event)
                    } else if eventIsIntervalStart {
                        
                        let fastEventStart = prevEventEndpointDate + epsilon
                        let modifiedEventEndpoint = eventEndpointDate - epsilon
                        let fastEventEnd = modifiedEventEndpoint - 1.days > fastEventStart ? fastEventStart + 1.days : modifiedEventEndpoint
                        let newResult = resultArray + [(fastEventStart, .Fast), (fastEventEnd, .Fast), event]
                        return (newResult, nextEventAsIntervalStart, event)
                    } else {
                        
                        return (resultArray + [event], nextEventAsIntervalStart, event)
                    }
            }).0 + lst  // Add the final fasting event to the event endpoint array.
            
            completion(intervals: endpointArray, error: error)
        }
    }
    
    func fetchSamples(typesAndPredicates: [HKSampleType: NSPredicate?], completion: HMTypedSampleBlock)
    {
        let group = dispatch_group_create()
        var samplesByType = [HKSampleType: [MCSample]]()
        
        typesAndPredicates.forEach { (type, predicate) -> () in
            dispatch_group_enter(group)
            fetchSamplesOfType(type, predicate: predicate, limit: noLimit) { (samples, error) in
                guard error == nil else {
                    //                        print("Could not fetch recent samples for \(type.displayText): \(error)")
                    dispatch_group_leave(group)
                    return
                }
                guard samples.isEmpty == false else {
                    //                        print("No recent samples available for \(type.displayText)")
                    dispatch_group_leave(group)
                    return
                }
                samplesByType[type] = samples
                dispatch_group_leave(group)
            }
        }
        
        dispatch_group_notify(group, dispatch_get_main_queue()) {
            // TODO: partial error handling, i.e., when a subset of the desired types fail in their queries.
            completion(samples: samplesByType, error: nil)
        }
    }
    
    func valueOfCircadianEvent(e: CircadianEvent) -> Double {
        switch e {
        case .Meal:
            return stEat
            
        case .Fast:
            return stFast
            
        case .Exercise:
            return stWorkout
            
        case .Sleep:
            return stSleep
        }
    }
    
    
    func fetchSamplesOfType(sampleType: HKSampleType, predicate: NSPredicate? = nil, limit: Int = noLimit,
                            sortDescriptors: [NSSortDescriptor]? = [dateAsc], completion: HMSampleBlock)
    {
        let query = HKSampleQuery(sampleType: sampleType, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) {
            (query, samples, error) -> Void in
            guard error == nil else {
                completion(samples: [], error: error)
                return
            }
            completion(samples: samples?.map { $0 as! MCSample } ?? [], error: nil)
        }
        HKHealthStore().executeQuery(query)
    }
    
    // Query food diary events stored as prep and recovery workouts in HealthKit
    func fetchPreparationAndRecoveryWorkout(oldestFirst: Bool, beginDate: NSDate? = nil, completion: HMSampleBlock)
    {
        let predicate = mealsSincePredicate(beginDate)
        let sortDescriptor = NSSortDescriptor(key:HKSampleSortIdentifierStartDate, ascending: oldestFirst)
        fetchSamplesOfType(HKWorkoutType.workoutType(), predicate: predicate, limit: noLimit, sortDescriptors: [sortDescriptor], completion: completion)
    }
    
    func fetchAggregatedCircadianEvents<T>(predicate: ((NSDate, CircadianEvent) -> Bool)? = nil,
                                               aggregator: ((T, (NSDate, CircadianEvent)) -> T), initial: T, final: (T -> [(NSDate, Double)]),
                                               completion: HMCircadianAggregateBlock)
    {
        fetchCircadianEventIntervals(NSDate.distantPast()) { (intervals, error) in
            guard error == nil else {
                completion(aggregates: [], error: error)
                return
            }
            
            let filtered = predicate == nil ? intervals : intervals.filter(predicate!)
            let accum = filtered.reduce(initial, combine: aggregator)
            completion(aggregates: final(accum), error: nil)
        }
    }
    
    func fetchEatingTimes(completion: HMCircadianAggregateBlock) {
        typealias Accum = (Bool, NSDate!, [NSDate: Double])
        let aggregator : (Accum, (NSDate, CircadianEvent)) -> Accum = { (acc, e) in
            if !acc.0 && acc.1 != nil {
                switch e.1 {
                case .Meal:
                    let day = acc.1.startOf(.Day, inRegion: Region())
                    var nacc = acc.2
                    nacc.updateValue((acc.2[day] ?? 0.0) + e.0.timeIntervalSinceDate(acc.1!), forKey: day)
                    return (!acc.0, e.0, nacc)
                default:
                    return (!acc.0, e.0, acc.2)
                }
            }
            return (!acc.0, e.0, acc.2)
        }
        let initial : Accum = (true, nil, [:])
        let final : (Accum -> [(NSDate, Double)]) = { acc in
            return acc.2.map { return ($0.0, $0.1 / 3600.0) }.sort { (a,b) in return a.0 < b.0 }
        }
        
        fetchAggregatedCircadianEvents(nil, aggregator: aggregator, initial: initial, final: final, completion: completion)
    }
    
    func fetchMaxFastingTimes(completion: HMCircadianAggregateBlock)
    {
        // Accumulator:
        // i. boolean indicating event start.
        // ii. start of this fasting event.
        // iii. the previous event.
        // iv. a dictionary of accumulated fasting intervals.
        typealias Accum = (Bool, NSDate!, NSDate!, [NSDate: Double])
        
        let predicate : (NSDate, CircadianEvent) -> Bool = {
            switch $0.1 {
            case .Exercise, .Fast, .Sleep:
                return true
            default:
                return false
            }
        }
        
        let aggregator : (Accum, (NSDate, CircadianEvent)) -> Accum = { (acc, e) in
            var byDay = acc.3
            let (iStart, prevFast, prevEvt) = (acc.0, acc.1, acc.2)
            var nextFast = prevFast
            if iStart && prevFast != nil && prevEvt != nil && e.0 != prevEvt {
                let fastStartDay = prevFast.startOf(.Day, inRegion: Region())
                let duration = prevEvt.timeIntervalSinceDate(prevFast)
                let currentMax = byDay[fastStartDay] ?? duration
                byDay.updateValue(currentMax >= duration ? currentMax : duration, forKey: fastStartDay)
                nextFast = e.0
            } else if iStart && prevFast == nil {
                nextFast = e.0
            }
            return (!acc.0, nextFast, e.0, byDay)
        }
        
        let initial : Accum = (true, nil, nil, [:])
        let final : Accum -> [(NSDate, Double)] = { acc in
            var byDay = acc.3
            if let finalFast = acc.1, finalEvt = acc.2 {
                if finalFast != finalEvt {
                    let fastStartDay = finalFast.startOf(.Day, inRegion: Region())
                    let duration = finalEvt.timeIntervalSinceDate(finalFast)
                    let currentMax = byDay[fastStartDay] ?? duration
                    byDay.updateValue(currentMax >= duration ? currentMax : duration, forKey: fastStartDay)
                }
            }
            return byDay.map { return ($0.0, $0.1 / 3600.0) }.sort { (a,b) in return a.0 < b.0 }
        }
        
        fetchAggregatedCircadianEvents(predicate, aggregator: aggregator, initial: initial, final: final, completion: completion)
    }
    
    func mealsSincePredicate(startDate: NSDate? = nil, endDate: NSDate = NSDate()) -> NSPredicate? {
        var predicate : NSPredicate? = nil
        if let st = startDate {
            let conjuncts = [
                HKQuery.predicateForSamplesWithStartDate(st, endDate: endDate, options: .None),
                HKQuery.predicateForWorkoutsWithWorkoutActivityType(HKWorkoutActivityType.PreparationAndRecovery)
            ]
            predicate = NSCompoundPredicate(andPredicateWithSubpredicates: conjuncts)
        } else {
            predicate = HKQuery.predicateForWorkoutsWithWorkoutActivityType(HKWorkoutActivityType.PreparationAndRecovery)
        }
        return predicate
    }
    
/*    func fetchStatisticsOfType(sampleType: HKSampleType, predicate: NSPredicate? = nil, completion: HMSampleBlock) {
        switch sampleType {
        case is HKCategoryType:
            fallthrough
            
        case is HKCorrelationType:
            fallthrough
            
        case is HKWorkoutType:
            fetchAggregatedSamplesOfType(sampleType, predicate: predicate, completion: completion)
            
        case is HKQuantityType:
            let interval = NSDateComponents()
            interval.day = 1
            
            // Set the anchor date to midnight today.
            let anchorDate = NSDate().startOf(.Day, inRegion: Region())
            let quantityType = HKObjectType.quantityTypeForIdentifier(sampleType.identifier)!
            
            // Create the query
            let query = HKStatisticsCollectionQuery(quantityType: quantityType,
                                                    quantitySamplePredicate: predicate,
//                                                    options: quantityType.aggregationOptions,
                                                    anchorDate: anchorDate,
                                                    intervalComponents: interval)
            
            // Set the results handler
            query.initialResultsHandler = { query, results, error in
                guard error == nil else {
                    print("Failed to fetch \(sampleType.displayText) statistics: \(error!)")
                    completion(samples: [], error: error)
                    return
                }
                completion(samples: results?.statistics().map { $0 as MCSample } ?? [], error: nil)
            }
            healthKitStore.executeQuery(query)
            
        default:
            let err = NSError(domain: HMErrorDomain, code: 1048576, userInfo: [NSLocalizedDescriptionKey: "Not implemented"])
            completion(samples: [], error: err)
        }
    } */
    
    func fetchAggregatedSamplesOfType(sampleType: HKSampleType, aggregateUnit: NSCalendarUnit = .Day, predicate: NSPredicate? = nil,
                                             limit: Int = noLimit, sortDescriptors: [NSSortDescriptor]? = [dateAsc], completion: HMSampleBlock)
    {
        fetchSamplesOfType(sampleType, predicate: predicate, limit: limit, sortDescriptors: sortDescriptors) { samples, error in
            guard error == nil else {
                completion(samples: [], error: error)
                return
            }
            var byDay: [NSDate: MCAggregateSample] = [:]
            samples.forEach { sample in
                let day = sample.startDate.startOf(aggregateUnit, inRegion: Region())
                if var agg = byDay[day] {
                    if #available(iOS 9.0, *) {
                        agg.incr(sample)
                    } else {
                        // Fallback on earlier versions
                    }
                    byDay[day] = agg
                } else {
                    byDay[day] = MCAggregateSample(sample: sample)
                }
            }
            
            let doFinal: ((NSDate, MCAggregateSample) -> MCSample) = { (_,var agg) in if #available(iOS 9.0, *) {
                agg.final()
            } else {
                // Fallback on earlier versions
                }; return agg as MCSample }
            completion(samples: byDay.sort({ (a,b) in return a.0 < b.0 }).map(doFinal), error: nil)
        }
    }
    
    // Helper struct for iterating over date ranges.
    struct DateRange : SequenceType {
        
        var calendar: NSCalendar = NSCalendar(calendarIdentifier: NSCalendarIdentifierGregorian)!
        
        var startDate: NSDate
        var endDate: NSDate
        var stepUnits: NSCalendarUnit
        var stepValue: Int
        
        var currentStep: Int = 0
        
        init(startDate: NSDate, endDate: NSDate, stepUnits: NSCalendarUnit, stepValue: Int = 1) {
            self.startDate = startDate
            self.endDate = endDate
            self.stepUnits = stepUnits
            self.stepValue = stepValue
        }
        
        func generate() -> Generator {
            return Generator(range: self)
        }
        
        struct Generator: GeneratorType {
            
            var range: DateRange
            
            mutating func next() -> NSDate? {
                if range.currentStep == 0 { range.currentStep += 1; return range.startDate }
                else {
                    if let nextDate = range.calendar.dateByAddingUnit(range.stepUnits, value: range.stepValue, toDate: range.startDate, options: NSCalendarOptions(rawValue: 0)) {
                        range.currentStep += 1
                        if range.endDate <= nextDate {
                            return nil
                        } else {
                            range.startDate = nextDate
                            return nextDate
                        }
                    }
                    return nil
                }
            }
        }
    }
}
