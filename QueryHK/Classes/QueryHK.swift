import HealthKit

public class QueryHK: NSObject {

var healthKitStore: HKHealthStore = HKHealthStore()
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
                self.weightHK = mostRecentWeight as? HKQuantitySample;
                if let kilograms = self.weightHK?.quantity.doubleValueForUnit(HKUnit.gramUnitWithMetricPrefix(.Kilo)) {
                    let weightFormatter = NSMassFormatter()
                    weightFormatter.forPersonMassUse = true;
                    self.weightLocalizedString = weightFormatter.stringFromKilograms(kilograms)
                }
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    updateBMI()
                    print("in weight update of interface controller: \(self.weightLocalizedString)")
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
                
                //                var heightLocalizedString = self.kUnknownString;
                self.heightHK = mostRecentHeight as? HKQuantitySample;
                if let meters = self.heightHK?.quantity.doubleValueForUnit(HKUnit.meterUnit()) {
                    let heightFormatter = NSLengthFormatter()
                    heightFormatter.forPersonHeightUse = true;
                    self.heightLocalizedString = heightFormatter.stringFromMeters(meters);
                }
                
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    print("in height update of interface controller: \(self.heightLocalizedString)")
                    updateBMI()
                });
            })
        }

            func readMostRecentSample(sampleType:HKSampleType , completion:     ((HKSample!, NSError!) -> Void)!)
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
            self.healthKitStore.executeQuery(sampleQuery)
        }
}
