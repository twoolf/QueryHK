Pod::Spec.new do |s|
  s.name        = "QueryHK"
  s.version     = "0.1.11"
  s.summary     = "To enable code sharing between iOS App and WatchKit Extension for HealthKit queries"
  s.homepage    = "https://github.com/twoolf/QueryHK"
  s.license     = { :type => "MIT" }
  s.authors     = { "twoolf" => "twoolf@jhu.edu" }

  s.dependency 'SwiftDate'
  s.dependency 'CocoaLumberjack'
  s.dependency 'AwesomeCache'
  s.osx.deployment_target = "10.10"
  s.ios.deployment_target = "8.0"
  s.tvos.deployment_target = "9.0"
  s.watchos.deployment_target = "2.0"
  s.source   = { :git => "https://github.com/twoolf/QueryHK.git", :tag => "0.1.11"}
  s.source_files = "QueryHK/Classes/*.swift"
  s.requires_arc = true
  s.module_name = 'QueryHK'
end
