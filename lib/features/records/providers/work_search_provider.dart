import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:recolle/features/records/data/work_search_client.dart';

final workSearchClientProvider = Provider<WorkSearchClient>(
  (ref) => WorkSearchClient(),
);
