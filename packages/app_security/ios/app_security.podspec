#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint app_security.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'app_security'
  s.version          = '0.0.1'
  s.summary          = 'Eventi di sicurezza della sessione per KeePassMobile.'
  s.description      = <<-DESC
Notifica di blocco del dispositivo (protectedDataWillBecomeUnavailable).
                       DESC
  s.homepage         = 'https://github.com/Al3x1n0/KeePassMobile'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Alex' => 'alexdev479@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'app_security/Sources/app_security/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'app_security_privacy' => ['app_security/Sources/app_security/PrivacyInfo.xcprivacy']}
end
