// Conditional export: uses arcgis_maps_web on web platforms and arcgis_maps_native on native platforms.
export 'arcgis_maps_native.dart'
    if (dart.library.js_interop) 'arcgis_maps_web.dart';
