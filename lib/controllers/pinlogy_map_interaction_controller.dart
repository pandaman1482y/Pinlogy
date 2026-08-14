import 'package:flutter/foundation.dart';

/// 地図本体を再構築せず、操作に応じて必要なオーバーレイだけを更新する状態。
class PinlogyMapInteractionController {
  PinlogyMapInteractionController({required double initialZoom})
    : settledZoom = ValueNotifier(initialZoom);

  final ValueNotifier<String?> selectedPlaceId = ValueNotifier(null);
  final ValueNotifier<double> settledZoom;
  final ValueNotifier<bool> areaSearchAvailable = ValueNotifier(false);
  final ValueNotifier<bool> mapLoading = ValueNotifier(true);
  final ValueNotifier<int> tileErrors = ValueNotifier(0);

  void selectPlace(String? placeId) {
    if (selectedPlaceId.value != placeId) selectedPlaceId.value = placeId;
  }

  void settleCamera({required double zoom, required bool userGesture}) {
    if ((settledZoom.value - zoom).abs() >= .05) settledZoom.value = zoom;
    if (userGesture) areaSearchAvailable.value = true;
  }

  void consumeAreaSearch() => areaSearchAvailable.value = false;

  void dispose() {
    selectedPlaceId.dispose();
    settledZoom.dispose();
    areaSearchAvailable.dispose();
    mapLoading.dispose();
    tileErrors.dispose();
  }
}
