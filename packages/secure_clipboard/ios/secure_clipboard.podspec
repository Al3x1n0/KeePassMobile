#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint secure_clipboard.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'secure_clipboard'
  s.version          = '0.0.1'
  s.summary          = 'Copia negli appunti con scadenza nativa per KeePassMobile.'
  s.description      = <<-DESC
Copia negli appunti con expirationDate e localOnly.
                       DESC
  s.homepage         = 'https://github.com/Al3x1n0/KeePassMobile'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Alex' => 'alexdev479@gmail.com' }
  s.source           = { :path => '.' }
  s.source_files = 'secure_clipboard/Sources/secure_clipboard/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'secure_clipboard_privacy' => ['secure_clipboard/Sources/secure_clipboard/PrivacyInfo.xcprivacy']}
end
