import Flutter
import MapKit
import UIKit

final class PinlogyMapKitViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger

  init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    PinlogyMapKitView(
      frame: frame,
      viewIdentifier: viewId,
      arguments: args,
      messenger: messenger
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

private final class PinlogyPlaceAnnotation: NSObject, MKAnnotation {
  let placeId: String
  let title: String?
  let category: String?
  dynamic var coordinate: CLLocationCoordinate2D

  init(
    placeId: String,
    title: String,
    category: String?,
    coordinate: CLLocationCoordinate2D
  ) {
    self.placeId = placeId
    self.title = title
    self.category = category
    self.coordinate = coordinate
  }
}

final class PinlogyMapKitView: NSObject, FlutterPlatformView, MKMapViewDelegate {
  private let mapView: MKMapView
  private let channel: FlutterMethodChannel

  init(
    frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?,
    messenger: FlutterBinaryMessenger
  ) {
    mapView = MKMapView(frame: frame)
    channel = FlutterMethodChannel(
      name: "com.pinlogy/mapkit_\(viewId)",
      binaryMessenger: messenger
    )
    super.init()

    mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    mapView.delegate = self
    mapView.showsCompass = true
    mapView.showsScale = false
    mapView.pointOfInterestFilter = .excludingAll
    mapView.register(
      MKMarkerAnnotationView.self,
      forAnnotationViewWithReuseIdentifier: "pinlogy-place"
    )
    mapView.register(
      MKMarkerAnnotationView.self,
      forAnnotationViewWithReuseIdentifier: "pinlogy-cluster"
    )

    updatePlaces(arguments: args, fit: true)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(nil)
        return
      }
      switch call.method {
      case "updatePlaces":
        self.updatePlaces(arguments: call.arguments, fit: false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func view() -> UIView { mapView }

  private func updatePlaces(arguments: Any?, fit: Bool) {
    let values = arguments as? [String: Any]
    let places = values?["places"] as? [[String: Any]] ?? []
    let annotations: [PinlogyPlaceAnnotation] = places.compactMap { place in
      guard
        let id = place["id"] as? String,
        let name = place["name"] as? String,
        let latitude = (place["latitude"] as? NSNumber)?.doubleValue,
        let longitude = (place["longitude"] as? NSNumber)?.doubleValue,
        CLLocationCoordinate2DIsValid(
          CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        )
      else { return nil }
      return PinlogyPlaceAnnotation(
        placeId: id,
        title: name,
        category: place["category"] as? String,
        coordinate: CLLocationCoordinate2D(
          latitude: latitude,
          longitude: longitude
        )
      )
    }

    mapView.removeAnnotations(
      mapView.annotations.filter { !($0 is MKUserLocation) }
    )
    mapView.addAnnotations(annotations)
    if fit && !annotations.isEmpty {
      mapView.showAnnotations(annotations, animated: false)
    }
  }

  func mapView(
    _ mapView: MKMapView,
    viewFor annotation: MKAnnotation
  ) -> MKAnnotationView? {
    if annotation is MKUserLocation { return nil }
    if annotation is MKClusterAnnotation {
      let view = mapView.dequeueReusableAnnotationView(
        withIdentifier: "pinlogy-cluster",
        for: annotation
      ) as! MKMarkerAnnotationView
      view.markerTintColor = UIColor(red: 0.14, green: 0.30, blue: 0.22, alpha: 1)
      view.glyphText = "\((annotation as? MKClusterAnnotation)?.memberAnnotations.count ?? 0)"
      view.glyphTintColor = .white
      view.displayPriority = .required
      return view
    }

    guard let place = annotation as? PinlogyPlaceAnnotation else { return nil }
    let view = mapView.dequeueReusableAnnotationView(
      withIdentifier: "pinlogy-place",
      for: place
    ) as! MKMarkerAnnotationView
    view.clusteringIdentifier = "pinlogy-places"
    view.canShowCallout = true
    view.markerTintColor = color(for: place.category)
    view.glyphImage = UIImage(systemName: symbol(for: place.category))
    view.glyphTintColor = .white
    view.displayPriority = .defaultHigh
    return view
  }

  func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
    guard let place = view.annotation as? PinlogyPlaceAnnotation else { return }
    channel.invokeMethod("placeSelected", arguments: ["id": place.placeId])
  }

  func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
    let region = mapView.region
    channel.invokeMethod(
      "cameraIdle",
      arguments: [
        "latitude": region.center.latitude,
        "longitude": region.center.longitude,
        "latitudeDelta": region.span.latitudeDelta,
        "longitudeDelta": region.span.longitudeDelta,
      ]
    )
  }

  private func symbol(for category: String?) -> String {
    switch category {
    case "飲食店": return "fork.knife"
    case "宿泊": return "bed.double.fill"
    case "観光・レジャー": return "camera.fill"
    case "買い物": return "bag.fill"
    default: return "mappin"
    }
  }

  private func color(for category: String?) -> UIColor {
    switch category {
    case "飲食店": return UIColor(red: 0.93, green: 0.40, blue: 0.31, alpha: 1)
    case "宿泊": return UIColor(red: 0.35, green: 0.45, blue: 0.78, alpha: 1)
    case "観光・レジャー": return UIColor(red: 0.28, green: 0.65, blue: 0.48, alpha: 1)
    case "買い物": return UIColor(red: 0.82, green: 0.49, blue: 0.72, alpha: 1)
    default: return UIColor(red: 0.38, green: 0.55, blue: 0.47, alpha: 1)
    }
  }
}
