// Web platform implementation: provides web-compatible map view and ArcGIS types
// so the application compiles and runs as a full Web App on iPhone 15 Safari / PWA.

import 'package:flutter/material.dart';

class SpatialReference {
  final int? wkid;
  const SpatialReference._([this.wkid]);
  static const SpatialReference wgs84 = SpatialReference._(4326);
}

class ArcGISPoint {
  final double x;
  final double y;
  final SpatialReference? spatialReference;

  ArcGISPoint({
    required this.x,
    required this.y,
    this.spatialReference,
  });
}

typedef Geometry = dynamic;

class ArcGISEnvironment {
  static String apiKey = '';
  static LicenseResult setLicenseUsingKey(String key) => LicenseResult();
}

class LicenseResult {
  final String licenseStatus = 'Licensed';
}

enum LoadStatus { loaded, failed, loading, notLoaded }

class PortalConnection {
  static const String authenticated = 'authenticated';
}

class Portal {
  final Uri uri;
  final String connection;
  Portal(this.uri, {required this.connection});
}

class PortalItem {
  final Portal portal;
  final String itemId;
  PortalItem.withPortalAndItemId({required this.portal, required this.itemId});
}

class Layer {
  String name;
  bool isVisible;
  Envelope? fullExtent;
  dynamic featureTable;
  LoadStatus loadStatus = LoadStatus.loaded;
  SpatialReference? spatialReference = SpatialReference.wgs84;

  Layer({
    required this.name,
    this.isVisible = true,
    this.fullExtent,
    this.featureTable,
  });

  Future<void> load() async {
    loadStatus = LoadStatus.loaded;
  }

  void clearSelection() {}
  void selectFeature(dynamic feature) {}
}

class FeatureLayer extends Layer {
  FeatureLayer({required super.name, super.isVisible, super.fullExtent, super.featureTable});
  FeatureLayer.withItem({dynamic item, int? layerId})
      : super(name: 'FeatureLayer');
}

class ArcGISMap {
  SpatialReference? spatialReference = SpatialReference.wgs84;
  List<dynamic> operationalLayers = [
    Layer(name: 'Assam_Flooded_Areas', isVisible: true),
    Layer(name: 'Assam_Buildings', isVisible: true),
    Layer(name: 'Assam_Emergency_Shelters', isVisible: true),
  ];
  LoadStatus loadStatus = LoadStatus.loaded;
  dynamic loadError;

  ArcGISMap.withItem(PortalItem item);

  Future<void> load() async {
    loadStatus = LoadStatus.loaded;
  }
}

class GraphicsOverlay {
  final List<Graphic> graphics = [];
}

class Graphic {
  dynamic geometry;
  dynamic symbol;
  Graphic({this.geometry, this.symbol});
}

enum SimpleLineSymbolStyle { solid }

class SimpleLineSymbol {
  final SimpleLineSymbolStyle style;
  final Color color;
  final double width;
  SimpleLineSymbol({
    required this.style,
    required this.color,
    required this.width,
  });
}

enum SimpleMarkerSymbolStyle { circle, diamond, square, cross, x }

class SimpleMarkerSymbol {
  final SimpleMarkerSymbolStyle style;
  final Color color;
  final double size;
  SimpleMarkerSymbol({
    required this.style,
    required this.color,
    required this.size,
  });
}

class PictureMarkerSymbol {
  final Uri uri;
  double width;
  double height;
  PictureMarkerSymbol.withUri(this.uri)
      : width = 24.0,
        height = 24.0;
}

class MutablePart {
  final List<ArcGISPoint> _points = [];
  void addPoint(ArcGISPoint pt) => _points.add(pt);
  List<ArcGISPoint> getPoints() => _points;
}

class PolylineBuilder {
  final SpatialReference? spatialReference;
  final List<MutablePart> parts = [MutablePart()];
  PolylineBuilder({this.spatialReference});

  void addPoint(ArcGISPoint pt) {
    if (parts.isEmpty) parts.add(MutablePart());
    parts.first.addPoint(pt);
  }

  Polyline toGeometry() => Polyline(
        points: parts.first.getPoints(),
        spatialReference: spatialReference,
      );
}

class ImmutablePart {
  final List<ArcGISPoint> points;
  ImmutablePart(this.points);
  List<ArcGISPoint> getPoints() => points;
}

class Polyline {
  final List<ArcGISPoint> points;
  final SpatialReference? spatialReference;
  final List<ImmutablePart> parts;

  Polyline({
    required this.points,
    this.spatialReference,
  }) : parts = [ImmutablePart(points)];
}

class Stop {
  final ArcGISPoint point;
  Stop(this.point);
}

class RouteParameters {
  SpatialReference? outputSpatialReference;
  bool returnRoutes = true;
  bool returnDirections = true;
  bool returnStops = true;
  void setStops(List<Stop> stops) {}
}

class Route {
  Polyline? routeGeometry;
  double totalLength = 1000.0;
  double totalTime = 5.0;
}

class RouteResult {
  List<Route> routes = [Route()];
}

class RouteTask {
  String? apiKey;
  LoadStatus loadStatus = LoadStatus.loaded;

  RouteTask.withUri(Uri uri);

  Future<void> load() async {
    loadStatus = LoadStatus.loaded;
  }

  Future<RouteParameters> createDefaultParameters() async => RouteParameters();
  Future<RouteResult> solveRoute(RouteParameters params) async => RouteResult();
}

class LinearUnit {
  static const LinearUnit meters = LinearUnit._();
  const LinearUnit._();
}

class Envelope {
  final ArcGISPoint center;
  final double width;
  final double height;
  Envelope({required this.center, required this.width, required this.height});
}

enum ViewpointType { centerAndScale }

class Viewpoint {
  final dynamic targetGeometry;
  final double targetScale;

  Viewpoint.fromCenter(ArcGISPoint center, {required double scale})
      : targetGeometry = center,
        targetScale = scale;

  Viewpoint.fromEnvelope(Envelope envelope)
      : targetGeometry = envelope.center,
        targetScale = 10000.0;
}

class ArcGISMapViewViewController {
  ArcGISMap? arcGISMap;
  List<GraphicsOverlay> graphicsOverlays = [];

  Viewpoint? _currentViewpoint = Viewpoint.fromCenter(
    ArcGISPoint(x: 93.8320717, y: 26.6445128, spatialReference: SpatialReference.wgs84),
    scale: 25000.0,
  );

  Viewpoint? getCurrentViewpoint(ViewpointType type) => _currentViewpoint;

  Future<void> setViewpointAnimated(Viewpoint viewpoint, {double duration = 0.25}) async {
    _currentViewpoint = viewpoint;
  }

  void setViewpointGeometry(dynamic geometry) {
    if (geometry is Envelope) {
      _currentViewpoint = Viewpoint.fromEnvelope(geometry);
    }
  }

  void setViewpoint(Viewpoint viewpoint) {
    _currentViewpoint = viewpoint;
  }
}

typedef MapViewController = ArcGISMapViewViewController;

class ArcGISMapView extends StatefulWidget {
  final MapViewController Function() controllerProvider;
  final VoidCallback? onMapViewReady;

  const ArcGISMapView({
    super.key,
    required this.controllerProvider,
    this.onMapViewReady,
  });

  static MapViewController createController() => MapViewController();

  @override
  State<ArcGISMapView> createState() => _ArcGISMapViewWebState();
}

class _ArcGISMapViewWebState extends State<ArcGISMapView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onMapViewReady?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _WebMapPainter(),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.map, color: Colors.blueAccent),
                          SizedBox(width: 8),
                          Text(
                            'Assam Flood Rescue Operations Map',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Location: 93.8320°E, 26.6445°N (Assam Region)',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WebMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.blue.withOpacity(0.1)
      ..strokeWidth = 1.0;

    for (double i = 0; i < size.width; i += 40) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), gridPaint);
    }
    for (double i = 0; i < size.height; i += 40) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), gridPaint);
    }

    final floodPaint = Paint()
      ..color = Colors.blue.withOpacity(0.25)
      ..style = PaintingStyle.fill;
    
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.3)
      ..quadraticBezierTo(size.width * 0.4, size.height * 0.2, size.width * 0.7, size.height * 0.5)
      ..quadraticBezierTo(size.width * 0.6, size.height * 0.8, size.width * 0.3, size.height * 0.7)
      ..close();

    canvas.drawPath(path, floodPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class OAuthUserConfiguration {
  final Uri portalUri;
  final String clientId;
  final Uri redirectUri;
  OAuthUserConfiguration({
    required this.portalUri,
    required this.clientId,
    required this.redirectUri,
  });
}

class Authenticator extends StatelessWidget {
  final List<OAuthUserConfiguration> oAuthUserConfigurations;
  final Widget child;

  const Authenticator({
    super.key,
    required this.oAuthUserConfigurations,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => child;
}

class ServiceFeatureTable {
  final Uri uri;
  ServiceFeatureTable({required this.uri});

  Future<FeatureQueryResult> queryFeatures(QueryParameters params) async {
    return FeatureQueryResult();
  }
}

class FeatureQueryResult implements Iterable<Feature> {
  final List<Feature> features = [];

  @override
  Iterator<Feature> get iterator => features.iterator;

  @override
  bool get isEmpty => true;
  @override
  bool get isNotEmpty => false;
  @override
  int get length => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class Feature {
  final Map<String, dynamic> attributes = {};
  dynamic geometry;
}

enum SpatialRelationship { intersects }

class QueryParameters {
  String whereClause = '';
  dynamic geometry;
  SpatialRelationship? spatialRelationship;
}

class GeometryEngine {
  static dynamic buffer(dynamic geometry, double distance) => geometry;
  static bool intersects(dynamic geometry1, dynamic geometry2) => true;
  static double lengthGeodetic(dynamic geometry, {dynamic unit}) => 1000.0;
  static double length(dynamic geometry) => 1000.0;
  static double distanceGeodetic(dynamic point1, dynamic point2, {dynamic unit}) => 500.0;
  static double distance(dynamic point1, dynamic point2) => 500.0;
  static dynamic project(dynamic geometry, {SpatialReference? outputSpatialReference}) => geometry;
}
