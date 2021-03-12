Pod::Spec.new do |spec|

  spec.name         = "SCSoftKycSolutionSdk"
  spec.version      = "0.0.3"
  spec.summary      = "SCSoftKycSolutionSdk summary"

  spec.homepage     = "https://github.com/samiozakyol/SCSoftKycSolutionSdk"
  spec.license      = "MIT"
  spec.author       = { "Sami Ozakyol" => "samiozakyol@gmail.com" }
  spec.platform = :ios
  spec.ios.deployment_target = "13.0"

  spec.source      = { 
        :http => 'https://github.com/samiozakyol/SCSoftKycSolutionSdk/archive/0.0.3.tar.gz'
  }

  spec.ios.vendored_frameworks = 'SCSoftKycSolutionSdk.xcframework'
  spec.swift_version = "5.0"

  spec.dependency "QKMRZParser", '1.0.1'
  spec.dependency "NFCPassportReader" , '1.1.1'
  spec.dependency "SwiftyTesseract", '3.1.3'
  spec.dependency "JitsiMeetSDK"
  spec.xcconfig          = { 'OTHER_LDFLAGS' => '-weak_framework CryptoKit -weak_framework CoreNFC',
                             'ENABLE_BITCODE' => '"NO' }

  spec.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64'
  }
  spec.user_target_xcconfig = { 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'arm64' }

end
