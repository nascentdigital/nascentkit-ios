Pod::Spec.new do |s|
  s.name             = "NascentKit"
  s.version          = "0.1.7"
  s.summary          = "An iOS framework that simplifies the creation of beautiful apps."
  s.description      = <<-DESC
This is a framework for building iOS applications using Swift, providing many classes and components that simplify integration with the native platform.

The library follows a Reactive paradigm, leveraging the [RxSwift](https://github.com/ReactiveX/RxSwift) framework for many asynchronous callbacks.

Currently, the library provides intefaces for working with:
   - Camera APIs
                        DESC
  s.homepage         = "https://github.com/nascentdigital/nascentkit-ios"
  s.license          = 'MIT'
  s.author           = { "Simeon de Dios" => "simeon.dedios@gmail.com" }
  s.source           = { :git => "https://github.com/nascentdigital/nascentkit-ios.git", :tag => s.version.to_s }

  s.requires_arc     = true

  s.swift_version    = '4.2'
  s.ios.deployment_target = '11.1'
  s.source_files     = 'NascentKit/**/*.swift'
  #s.exclude_files   = ''

  s.dependency 'RxSwift', '~> 4.0'
  s.dependency 'RxCocoa', '~> 4.0'

end
