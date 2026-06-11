import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_models.dart';
import 'providers.dart';

final browseCategoriesProvider = FutureProvider<List<BrowseCategory>>((ref) {
  return ref.watch(apiProvider).fetchBrowseCategories();
});

final browseCategoryProvider =
    FutureProvider.family<BrowseCategoryResult, String>((ref, categoryId) {
      return ref.watch(apiProvider).fetchBrowseCategory(categoryId);
    });

final podcastDetailsProvider = FutureProvider.family<PodcastDetails, String>((
  ref,
  podcastKey,
) {
  return ref.watch(apiProvider).fetchPodcastDetails(podcastKey);
});
