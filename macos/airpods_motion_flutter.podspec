Pod::Spec.new do |s|
  s.name             = 'airpods_motion_flutter'
  s.version          = '0.1.0'
  s.summary          = 'Calibrated 6-DoF AirPods & Beats head-motion telemetry for Flutter.'
  s.description      = <<-DESC
Calibrated 6-DoF AirPods & Beats head-motion telemetry (CMHeadphoneMotionManager)
for Flutter with live route detection, 1-Euro/EMA smoothing, and simulator replay.
                       DESC
  s.homepage         = 'https://github.com/samderlust/airpods_motion_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'samderlust' => 'dev@samderlust.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '14.0'
  s.frameworks       = 'CoreMotion'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
