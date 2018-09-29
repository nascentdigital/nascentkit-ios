Pod::Spec.new do |s|
  s.name             = "NascentKit"
  s.version          = "0.1.0"
  s.summary          = "An iOS framework that simplifies the creation of beautiful apps."
  s.description      = <<-DESC
TBD.
                        DESC
  s.homepage         = "https://github.com/nascent/nascentkit-ios"
  s.license          = 'MIT'
  s.author           = { "Simeon de Dios" => "simeon.dedios@gmail.com" }
  s.source           = { :git => "https://github.com/nascent/nascentkit-ios.git", :tag => s.version.to_s }

  s.requires_arc          = true

  s.ios.deployment_target = '11.1'
  s.source_files          = 'NascentKit/**/*.swift'
  #s.exclude_files         = ''
end
