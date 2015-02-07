Pod::Spec.new do |s|
  s.name         = "GCDMulticastDelegate"
  s.version      = "1.0.0"
  s.summary      = "GCDMulticastDelegate extracted from XMPPFramework."
  s.homepage     = "https://github.com/robbiehanson/XMPPFramework/tree/master/Utilities"
  s.license      = { :type => 'BCD', :file => 'LICENSE' }
  s.author       = { "Euan Lau" => "euanlau@gmail.com" }
  s.source       = { :git => "https://github.com/euanlau/GCDMulticastDelegate.git", :tag => "1.0.0" }
  s.source_files = '*.{h,m}'
  s.requires_arc = true
end
