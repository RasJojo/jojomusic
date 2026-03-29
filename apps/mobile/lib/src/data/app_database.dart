import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class OfflineTracks extends Table {
  TextColumn get trackKey => text()();
  TextColumn get title => text()();
  TextColumn get artist => text()();
  TextColumn get album => text().nullable()();
  TextColumn get artworkUrl => text().nullable()();
  TextColumn get filePath => text()();
  TextColumn get status => text()();
  RealColumn get progress => real().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {trackKey};
}

class OfflinePlaylists extends Table {
  TextColumn get playlistId => text()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get artworkUrl => text().nullable()();
  BoolColumn get autoDownloadNewTracks =>
      boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {playlistId};
}

@DriftDatabase(tables: [OfflineTracks, OfflinePlaylists])
class AppDatabase extends _$AppDatabase {
  AppDatabase({QueryExecutor? executor})
    : super(executor ?? _openConnection());

  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'jojomusic.sqlite',
      web: DriftWebOptions(
        sqlite3Wasm: Uri.parse('sqlite3.wasm'),
        driftWorker: Uri.parse('drift_worker.js'),
      ),
      native: const DriftNativeOptions(),
    );
  }

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (migrator) async => migrator.createAll(),
    onUpgrade: (migrator, from, to) async {
      if (from < 2) {
        await migrator.createTable(offlinePlaylists);
      }
    },
  );

  Stream<List<OfflineTrack>> watchOfflineTracks() => (select(
    offlineTracks,
  )..orderBy([(table) => OrderingTerm.desc(table.updatedAt)])).watch();

  Future<List<OfflineTrack>> getOfflineTracks() => select(offlineTracks).get();

  Future<OfflineTrack?> findOfflineTrack(String trackKey) => (select(
    offlineTracks,
  )..where((table) => table.trackKey.equals(trackKey))).getSingleOrNull();

  Future<void> upsertOfflineTrack(OfflineTracksCompanion companion) async {
    await into(offlineTracks).insertOnConflictUpdate(companion);
  }

  Future<void> deleteOfflineTrack(String trackKey) async {
    await (delete(
      offlineTracks,
    )..where((table) => table.trackKey.equals(trackKey))).go();
  }

  Stream<Set<String>> watchDownloadedPlaylistIds() {
    return select(
      offlinePlaylists,
    ).watch().map((rows) => rows.map((row) => row.playlistId).toSet());
  }

  Future<Set<String>> getDownloadedPlaylistIds() async {
    final rows = await select(offlinePlaylists).get();
    return rows.map((row) => row.playlistId).toSet();
  }

  Future<bool> isPlaylistDownloaded(String playlistId) async {
    final row = await (select(
      offlinePlaylists,
    )..where((table) => table.playlistId.equals(playlistId))).getSingleOrNull();
    return row != null;
  }

  Future<void> upsertOfflinePlaylist(
    OfflinePlaylistsCompanion companion,
  ) async {
    await into(offlinePlaylists).insertOnConflictUpdate(companion);
  }

  Future<void> deleteOfflinePlaylist(String playlistId) async {
    await (delete(
      offlinePlaylists,
    )..where((table) => table.playlistId.equals(playlistId))).go();
  }

  Future<void> pruneOfflinePlaylists(Set<String> validPlaylistIds) async {
    if (validPlaylistIds.isEmpty) {
      await delete(offlinePlaylists).go();
      return;
    }
    await (delete(
      offlinePlaylists,
    )..where((table) => table.playlistId.isNotIn(validPlaylistIds))).go();
  }
}
