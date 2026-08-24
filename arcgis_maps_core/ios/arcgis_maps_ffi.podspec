Pod::Spec::new do |spec|
  spec.name                   = 'arcgis_maps_ffi'
  spec.version                = '300.0.0.4935'
  spec.ios.deployment_target  = '16.0'
  spec.summary                = 'FFI plugin for the ArcGIS Maps SDK for Flutter'
  spec.homepage               = 'https://developers.arcgis.com'
  spec.author                 = { 'Esri' => 'https://www.esri.com/' }

  spec.source                 = { :http => 'file:' + __dir__ + '/arcgis_maps_ffi.xcframework.zip' }
  spec.vendored_frameworks    = 'arcgis_maps_ffi.xcframework'
end
