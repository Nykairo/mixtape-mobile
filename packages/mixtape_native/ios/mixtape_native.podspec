Pod::Spec.new do |s|
  s.name             = 'mixtape_native'
  s.version          = '0.1.0'
  s.summary          = 'The parts of Mixtape that live on the iPhone side.'
  s.description      = 'Sharing, picking pictures, and what the home screen widgets show.'
  s.homepage         = 'https://github.com/Nykairo/mixtape-mobile'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = 'Mixtape'
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.weak_frameworks  = 'WidgetKit', 'PhotosUI'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
