Pod::Spec.new do |s|
  s.name             = 'ZTAPI'
  s.version          = '1.0.0'
  s.summary          = 'ZTAPI'
  s.description      = <<-DESC
ZTAPI
                       DESC

  s.homepage         = 'https://github.com/willonboy/ZTAPI.git'
  s.license          = { :type => 'AGPL-3.0', :file => 'LICENSE' }
  s.author           = { 'zt' => '' }
  s.source           = { :git => 'https://github.com/willonboy/ZTAPI.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'

  s.source_files = 'Sources/ZTAPICore/*'
end
