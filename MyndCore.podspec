Pod::Spec.new do |spec|
  spec.name         = "MyndCore"
  spec.version      = "1.4.0"
  spec.summary      = "MyndCore Swift SDK"
  spec.description  = "Swift SDK for MyndCore audio streaming and playlist management"
  spec.homepage     = "https://github.com/Mynd-Group/swift-sdk"
  spec.license      = { :type => "MIT", :file => "LICENSE" }
  spec.author       = { "Myndstream" => "tech@myndstream.com" }
  spec.source       = { :git => "https://github.com/Mynd-Group/swift-sdk.git", :tag => "#{spec.version}" }

  spec.ios.deployment_target = "14.0"

  spec.swift_version = "5.0"

  spec.source_files = "Sources/MyndCore/**/*.swift"

  spec.frameworks = "Foundation", "AVFoundation", "MediaPlayer"
end
