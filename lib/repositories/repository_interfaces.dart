import '../models/models.dart';

abstract class MapRepository {
  Future<List<PinMap>> getAll();
  Future<PinMap?> getById(String id);
  Future<PinMap> create(PinMap map);
  Future<PinMap> update(PinMap map);
  Future<void> delete(String id);
}

abstract class PlaceRepository {
  Future<List<Place>> getAll();
  Future<Place?> getById(String id);
  Future<List<Place>> getByMapId(String mapId);
  Future<Place> create(
    Place place, {
    List<String> mapIds = const [],
    bool allowDuplicate = false,
  });
  Future<Place> update(Place place);
  Future<void> delete(String id);
  Future<void> addToMap({required String placeId, required String mapId});
  Future<void> removeFromMap({required String placeId, required String mapId});
  Future<List<PinMap>> mapsForPlace(String placeId);
  Future<Place> markVisited(String placeId);
  Future<List<Place>> search({
    String query = '',
    PlaceFilterOption filter = PlaceFilterOption.all,
    PlaceSortOption sort = PlaceSortOption.registeredDesc,
    String? mapId,
  });
}

abstract class SourcePostRepository {
  Future<List<SourcePost>> getAll();
  Future<SourcePost?> getById(String id);
  Future<SourcePost> create(SourcePost post);
  Future<SourcePost> update(SourcePost post);
  Future<void> delete(String id);
  Future<List<SourcePost>> postsForPlace(String placeId);
  Future<void> linkPlace({
    required String placeId,
    required String sourcePostId,
  });
}

abstract class AnalysisRepository {
  Future<List<AnalysisJob>> getAll();
  Future<AnalysisJob?> getBySourcePostId(String sourcePostId);
  Future<AnalysisJob> enqueue(String sourcePostId);
  Future<AnalysisJob> update(AnalysisJob job);
  Future<void> cancel(String jobId);
  Future<void> retry(String jobId);
}

abstract class VisitRepository {
  Future<Place> markVisited(String placeId);
  Future<Place> setStatus(String placeId, VisitStatus status);
}

abstract class TagRepository {
  Future<List<Tag>> getAll();
  Future<List<Tag>> tagsForPlace(String placeId);
  Future<Tag> ensureTag(String name);
  Future<void> setPlaceTags({
    required String placeId,
    required List<String> tagNames,
  });
  Future<void> removeTagFromPlace({
    required String placeId,
    required String tagId,
  });
}

abstract class PlanRepository {
  Future<List<TripPlan>> getAll();
  Future<TripPlan?> getById(String id);
  Future<TripPlan> create(TripPlan plan);
  Future<TripPlan> update(TripPlan plan);
  Future<void> delete(String id);

  Future<List<PlanStop>> stopsForPlan(String planId);
  Future<PlanStop> addStop(PlanStop stop);
  Future<PlanStop> updateStop(PlanStop stop);
  Future<void> removeStop(String stopId);
  Future<void> reorderStops({
    required String planId,
    DateTime? dayDate,
    required List<String> orderedStopIds,
  });
}
