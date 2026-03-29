// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $OfflineTracksTable extends OfflineTracks
    with TableInfo<$OfflineTracksTable, OfflineTrack> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflineTracksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackKeyMeta = const VerificationMeta(
    'trackKey',
  );
  @override
  late final GeneratedColumn<String> trackKey = GeneratedColumn<String>(
    'track_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artworkUrlMeta = const VerificationMeta(
    'artworkUrl',
  );
  @override
  late final GeneratedColumn<String> artworkUrl = GeneratedColumn<String>(
    'artwork_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _progressMeta = const VerificationMeta(
    'progress',
  );
  @override
  late final GeneratedColumn<double> progress = GeneratedColumn<double>(
    'progress',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    trackKey,
    title,
    artist,
    album,
    artworkUrl,
    filePath,
    status,
    progress,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_tracks';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflineTrack> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_key')) {
      context.handle(
        _trackKeyMeta,
        trackKey.isAcceptableOrUnknown(data['track_key']!, _trackKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_trackKeyMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('artwork_url')) {
      context.handle(
        _artworkUrlMeta,
        artworkUrl.isAcceptableOrUnknown(data['artwork_url']!, _artworkUrlMeta),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    } else if (isInserting) {
      context.missing(_filePathMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('progress')) {
      context.handle(
        _progressMeta,
        progress.isAcceptableOrUnknown(data['progress']!, _progressMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackKey};
  @override
  OfflineTrack map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflineTrack(
      trackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_key'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      artworkUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_url'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      progress: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}progress'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $OfflineTracksTable createAlias(String alias) {
    return $OfflineTracksTable(attachedDatabase, alias);
  }
}

class OfflineTrack extends DataClass implements Insertable<OfflineTrack> {
  final String trackKey;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final String filePath;
  final String status;
  final double progress;
  final DateTime createdAt;
  final DateTime updatedAt;
  const OfflineTrack({
    required this.trackKey,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    required this.filePath,
    required this.status,
    required this.progress,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_key'] = Variable<String>(trackKey);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || artworkUrl != null) {
      map['artwork_url'] = Variable<String>(artworkUrl);
    }
    map['file_path'] = Variable<String>(filePath);
    map['status'] = Variable<String>(status);
    map['progress'] = Variable<double>(progress);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OfflineTracksCompanion toCompanion(bool nullToAbsent) {
    return OfflineTracksCompanion(
      trackKey: Value(trackKey),
      title: Value(title),
      artist: Value(artist),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      artworkUrl: artworkUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkUrl),
      filePath: Value(filePath),
      status: Value(status),
      progress: Value(progress),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory OfflineTrack.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflineTrack(
      trackKey: serializer.fromJson<String>(json['trackKey']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      artworkUrl: serializer.fromJson<String?>(json['artworkUrl']),
      filePath: serializer.fromJson<String>(json['filePath']),
      status: serializer.fromJson<String>(json['status']),
      progress: serializer.fromJson<double>(json['progress']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackKey': serializer.toJson<String>(trackKey),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String?>(album),
      'artworkUrl': serializer.toJson<String?>(artworkUrl),
      'filePath': serializer.toJson<String>(filePath),
      'status': serializer.toJson<String>(status),
      'progress': serializer.toJson<double>(progress),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  OfflineTrack copyWith({
    String? trackKey,
    String? title,
    String? artist,
    Value<String?> album = const Value.absent(),
    Value<String?> artworkUrl = const Value.absent(),
    String? filePath,
    String? status,
    double? progress,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => OfflineTrack(
    trackKey: trackKey ?? this.trackKey,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album.present ? album.value : this.album,
    artworkUrl: artworkUrl.present ? artworkUrl.value : this.artworkUrl,
    filePath: filePath ?? this.filePath,
    status: status ?? this.status,
    progress: progress ?? this.progress,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  OfflineTrack copyWithCompanion(OfflineTracksCompanion data) {
    return OfflineTrack(
      trackKey: data.trackKey.present ? data.trackKey.value : this.trackKey,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      artworkUrl: data.artworkUrl.present
          ? data.artworkUrl.value
          : this.artworkUrl,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      status: data.status.present ? data.status.value : this.status,
      progress: data.progress.present ? data.progress.value : this.progress,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflineTrack(')
          ..write('trackKey: $trackKey, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('artworkUrl: $artworkUrl, ')
          ..write('filePath: $filePath, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    trackKey,
    title,
    artist,
    album,
    artworkUrl,
    filePath,
    status,
    progress,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflineTrack &&
          other.trackKey == this.trackKey &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.artworkUrl == this.artworkUrl &&
          other.filePath == this.filePath &&
          other.status == this.status &&
          other.progress == this.progress &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OfflineTracksCompanion extends UpdateCompanion<OfflineTrack> {
  final Value<String> trackKey;
  final Value<String> title;
  final Value<String> artist;
  final Value<String?> album;
  final Value<String?> artworkUrl;
  final Value<String> filePath;
  final Value<String> status;
  final Value<double> progress;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const OfflineTracksCompanion({
    this.trackKey = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.artworkUrl = const Value.absent(),
    this.filePath = const Value.absent(),
    this.status = const Value.absent(),
    this.progress = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflineTracksCompanion.insert({
    required String trackKey,
    required String title,
    required String artist,
    this.album = const Value.absent(),
    this.artworkUrl = const Value.absent(),
    required String filePath,
    required String status,
    this.progress = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : trackKey = Value(trackKey),
       title = Value(title),
       artist = Value(artist),
       filePath = Value(filePath),
       status = Value(status),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<OfflineTrack> custom({
    Expression<String>? trackKey,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? artworkUrl,
    Expression<String>? filePath,
    Expression<String>? status,
    Expression<double>? progress,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackKey != null) 'track_key': trackKey,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (artworkUrl != null) 'artwork_url': artworkUrl,
      if (filePath != null) 'file_path': filePath,
      if (status != null) 'status': status,
      if (progress != null) 'progress': progress,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflineTracksCompanion copyWith({
    Value<String>? trackKey,
    Value<String>? title,
    Value<String>? artist,
    Value<String?>? album,
    Value<String?>? artworkUrl,
    Value<String>? filePath,
    Value<String>? status,
    Value<double>? progress,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return OfflineTracksCompanion(
      trackKey: trackKey ?? this.trackKey,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      filePath: filePath ?? this.filePath,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackKey.present) {
      map['track_key'] = Variable<String>(trackKey.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (artworkUrl.present) {
      map['artwork_url'] = Variable<String>(artworkUrl.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (progress.present) {
      map['progress'] = Variable<double>(progress.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflineTracksCompanion(')
          ..write('trackKey: $trackKey, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('artworkUrl: $artworkUrl, ')
          ..write('filePath: $filePath, ')
          ..write('status: $status, ')
          ..write('progress: $progress, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OfflinePlaylistsTable extends OfflinePlaylists
    with TableInfo<$OfflinePlaylistsTable, OfflinePlaylist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OfflinePlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<String> playlistId = GeneratedColumn<String>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _artworkUrlMeta = const VerificationMeta(
    'artworkUrl',
  );
  @override
  late final GeneratedColumn<String> artworkUrl = GeneratedColumn<String>(
    'artwork_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _autoDownloadNewTracksMeta =
      const VerificationMeta('autoDownloadNewTracks');
  @override
  late final GeneratedColumn<bool> autoDownloadNewTracks =
      GeneratedColumn<bool>(
        'auto_download_new_tracks',
        aliasedName,
        false,
        type: DriftSqlType.bool,
        requiredDuringInsert: false,
        defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("auto_download_new_tracks" IN (0, 1))',
        ),
        defaultValue: const Constant(true),
      );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    playlistId,
    name,
    description,
    artworkUrl,
    autoDownloadNewTracks,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'offline_playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<OfflinePlaylist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    }
    if (data.containsKey('artwork_url')) {
      context.handle(
        _artworkUrlMeta,
        artworkUrl.isAcceptableOrUnknown(data['artwork_url']!, _artworkUrlMeta),
      );
    }
    if (data.containsKey('auto_download_new_tracks')) {
      context.handle(
        _autoDownloadNewTracksMeta,
        autoDownloadNewTracks.isAcceptableOrUnknown(
          data['auto_download_new_tracks']!,
          _autoDownloadNewTracksMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {playlistId};
  @override
  OfflinePlaylist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OfflinePlaylist(
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}playlist_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      ),
      artworkUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artwork_url'],
      ),
      autoDownloadNewTracks: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}auto_download_new_tracks'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $OfflinePlaylistsTable createAlias(String alias) {
    return $OfflinePlaylistsTable(attachedDatabase, alias);
  }
}

class OfflinePlaylist extends DataClass implements Insertable<OfflinePlaylist> {
  final String playlistId;
  final String name;
  final String? description;
  final String? artworkUrl;
  final bool autoDownloadNewTracks;
  final DateTime createdAt;
  final DateTime updatedAt;
  const OfflinePlaylist({
    required this.playlistId,
    required this.name,
    this.description,
    this.artworkUrl,
    required this.autoDownloadNewTracks,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['playlist_id'] = Variable<String>(playlistId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || description != null) {
      map['description'] = Variable<String>(description);
    }
    if (!nullToAbsent || artworkUrl != null) {
      map['artwork_url'] = Variable<String>(artworkUrl);
    }
    map['auto_download_new_tracks'] = Variable<bool>(autoDownloadNewTracks);
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OfflinePlaylistsCompanion toCompanion(bool nullToAbsent) {
    return OfflinePlaylistsCompanion(
      playlistId: Value(playlistId),
      name: Value(name),
      description: description == null && nullToAbsent
          ? const Value.absent()
          : Value(description),
      artworkUrl: artworkUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(artworkUrl),
      autoDownloadNewTracks: Value(autoDownloadNewTracks),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory OfflinePlaylist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OfflinePlaylist(
      playlistId: serializer.fromJson<String>(json['playlistId']),
      name: serializer.fromJson<String>(json['name']),
      description: serializer.fromJson<String?>(json['description']),
      artworkUrl: serializer.fromJson<String?>(json['artworkUrl']),
      autoDownloadNewTracks: serializer.fromJson<bool>(
        json['autoDownloadNewTracks'],
      ),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'playlistId': serializer.toJson<String>(playlistId),
      'name': serializer.toJson<String>(name),
      'description': serializer.toJson<String?>(description),
      'artworkUrl': serializer.toJson<String?>(artworkUrl),
      'autoDownloadNewTracks': serializer.toJson<bool>(autoDownloadNewTracks),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  OfflinePlaylist copyWith({
    String? playlistId,
    String? name,
    Value<String?> description = const Value.absent(),
    Value<String?> artworkUrl = const Value.absent(),
    bool? autoDownloadNewTracks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => OfflinePlaylist(
    playlistId: playlistId ?? this.playlistId,
    name: name ?? this.name,
    description: description.present ? description.value : this.description,
    artworkUrl: artworkUrl.present ? artworkUrl.value : this.artworkUrl,
    autoDownloadNewTracks: autoDownloadNewTracks ?? this.autoDownloadNewTracks,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  OfflinePlaylist copyWithCompanion(OfflinePlaylistsCompanion data) {
    return OfflinePlaylist(
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      name: data.name.present ? data.name.value : this.name,
      description: data.description.present
          ? data.description.value
          : this.description,
      artworkUrl: data.artworkUrl.present
          ? data.artworkUrl.value
          : this.artworkUrl,
      autoDownloadNewTracks: data.autoDownloadNewTracks.present
          ? data.autoDownloadNewTracks.value
          : this.autoDownloadNewTracks,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OfflinePlaylist(')
          ..write('playlistId: $playlistId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('artworkUrl: $artworkUrl, ')
          ..write('autoDownloadNewTracks: $autoDownloadNewTracks, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    playlistId,
    name,
    description,
    artworkUrl,
    autoDownloadNewTracks,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OfflinePlaylist &&
          other.playlistId == this.playlistId &&
          other.name == this.name &&
          other.description == this.description &&
          other.artworkUrl == this.artworkUrl &&
          other.autoDownloadNewTracks == this.autoDownloadNewTracks &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class OfflinePlaylistsCompanion extends UpdateCompanion<OfflinePlaylist> {
  final Value<String> playlistId;
  final Value<String> name;
  final Value<String?> description;
  final Value<String?> artworkUrl;
  final Value<bool> autoDownloadNewTracks;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const OfflinePlaylistsCompanion({
    this.playlistId = const Value.absent(),
    this.name = const Value.absent(),
    this.description = const Value.absent(),
    this.artworkUrl = const Value.absent(),
    this.autoDownloadNewTracks = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OfflinePlaylistsCompanion.insert({
    required String playlistId,
    required String name,
    this.description = const Value.absent(),
    this.artworkUrl = const Value.absent(),
    this.autoDownloadNewTracks = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : playlistId = Value(playlistId),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<OfflinePlaylist> custom({
    Expression<String>? playlistId,
    Expression<String>? name,
    Expression<String>? description,
    Expression<String>? artworkUrl,
    Expression<bool>? autoDownloadNewTracks,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (playlistId != null) 'playlist_id': playlistId,
      if (name != null) 'name': name,
      if (description != null) 'description': description,
      if (artworkUrl != null) 'artwork_url': artworkUrl,
      if (autoDownloadNewTracks != null)
        'auto_download_new_tracks': autoDownloadNewTracks,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OfflinePlaylistsCompanion copyWith({
    Value<String>? playlistId,
    Value<String>? name,
    Value<String?>? description,
    Value<String?>? artworkUrl,
    Value<bool>? autoDownloadNewTracks,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return OfflinePlaylistsCompanion(
      playlistId: playlistId ?? this.playlistId,
      name: name ?? this.name,
      description: description ?? this.description,
      artworkUrl: artworkUrl ?? this.artworkUrl,
      autoDownloadNewTracks:
          autoDownloadNewTracks ?? this.autoDownloadNewTracks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (playlistId.present) {
      map['playlist_id'] = Variable<String>(playlistId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (artworkUrl.present) {
      map['artwork_url'] = Variable<String>(artworkUrl.value);
    }
    if (autoDownloadNewTracks.present) {
      map['auto_download_new_tracks'] = Variable<bool>(
        autoDownloadNewTracks.value,
      );
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OfflinePlaylistsCompanion(')
          ..write('playlistId: $playlistId, ')
          ..write('name: $name, ')
          ..write('description: $description, ')
          ..write('artworkUrl: $artworkUrl, ')
          ..write('autoDownloadNewTracks: $autoDownloadNewTracks, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $OfflineTracksTable offlineTracks = $OfflineTracksTable(this);
  late final $OfflinePlaylistsTable offlinePlaylists = $OfflinePlaylistsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    offlineTracks,
    offlinePlaylists,
  ];
}

typedef $$OfflineTracksTableCreateCompanionBuilder =
    OfflineTracksCompanion Function({
      required String trackKey,
      required String title,
      required String artist,
      Value<String?> album,
      Value<String?> artworkUrl,
      required String filePath,
      required String status,
      Value<double> progress,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$OfflineTracksTableUpdateCompanionBuilder =
    OfflineTracksCompanion Function({
      Value<String> trackKey,
      Value<String> title,
      Value<String> artist,
      Value<String?> album,
      Value<String?> artworkUrl,
      Value<String> filePath,
      Value<String> status,
      Value<double> progress,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$OfflineTracksTableFilterComposer
    extends Composer<_$AppDatabase, $OfflineTracksTable> {
  $$OfflineTracksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackKey => $composableBuilder(
    column: $table.trackKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflineTracksTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflineTracksTable> {
  $$OfflineTracksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackKey => $composableBuilder(
    column: $table.trackKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get progress => $composableBuilder(
    column: $table.progress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflineTracksTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflineTracksTable> {
  $$OfflineTracksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackKey =>
      $composableBuilder(column: $table.trackKey, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<double> get progress =>
      $composableBuilder(column: $table.progress, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OfflineTracksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflineTracksTable,
          OfflineTrack,
          $$OfflineTracksTableFilterComposer,
          $$OfflineTracksTableOrderingComposer,
          $$OfflineTracksTableAnnotationComposer,
          $$OfflineTracksTableCreateCompanionBuilder,
          $$OfflineTracksTableUpdateCompanionBuilder,
          (
            OfflineTrack,
            BaseReferences<_$AppDatabase, $OfflineTracksTable, OfflineTrack>,
          ),
          OfflineTrack,
          PrefetchHooks Function()
        > {
  $$OfflineTracksTableTableManager(_$AppDatabase db, $OfflineTracksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflineTracksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflineTracksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflineTracksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> trackKey = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<String?> artworkUrl = const Value.absent(),
                Value<String> filePath = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<double> progress = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflineTracksCompanion(
                trackKey: trackKey,
                title: title,
                artist: artist,
                album: album,
                artworkUrl: artworkUrl,
                filePath: filePath,
                status: status,
                progress: progress,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackKey,
                required String title,
                required String artist,
                Value<String?> album = const Value.absent(),
                Value<String?> artworkUrl = const Value.absent(),
                required String filePath,
                required String status,
                Value<double> progress = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => OfflineTracksCompanion.insert(
                trackKey: trackKey,
                title: title,
                artist: artist,
                album: album,
                artworkUrl: artworkUrl,
                filePath: filePath,
                status: status,
                progress: progress,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflineTracksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflineTracksTable,
      OfflineTrack,
      $$OfflineTracksTableFilterComposer,
      $$OfflineTracksTableOrderingComposer,
      $$OfflineTracksTableAnnotationComposer,
      $$OfflineTracksTableCreateCompanionBuilder,
      $$OfflineTracksTableUpdateCompanionBuilder,
      (
        OfflineTrack,
        BaseReferences<_$AppDatabase, $OfflineTracksTable, OfflineTrack>,
      ),
      OfflineTrack,
      PrefetchHooks Function()
    >;
typedef $$OfflinePlaylistsTableCreateCompanionBuilder =
    OfflinePlaylistsCompanion Function({
      required String playlistId,
      required String name,
      Value<String?> description,
      Value<String?> artworkUrl,
      Value<bool> autoDownloadNewTracks,
      required DateTime createdAt,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$OfflinePlaylistsTableUpdateCompanionBuilder =
    OfflinePlaylistsCompanion Function({
      Value<String> playlistId,
      Value<String> name,
      Value<String?> description,
      Value<String?> artworkUrl,
      Value<bool> autoDownloadNewTracks,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$OfflinePlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $OfflinePlaylistsTable> {
  $$OfflinePlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get autoDownloadNewTracks => $composableBuilder(
    column: $table.autoDownloadNewTracks,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OfflinePlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $OfflinePlaylistsTable> {
  $$OfflinePlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get autoDownloadNewTracks => $composableBuilder(
    column: $table.autoDownloadNewTracks,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OfflinePlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OfflinePlaylistsTable> {
  $$OfflinePlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get playlistId => $composableBuilder(
    column: $table.playlistId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<String> get artworkUrl => $composableBuilder(
    column: $table.artworkUrl,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get autoDownloadNewTracks => $composableBuilder(
    column: $table.autoDownloadNewTracks,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OfflinePlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OfflinePlaylistsTable,
          OfflinePlaylist,
          $$OfflinePlaylistsTableFilterComposer,
          $$OfflinePlaylistsTableOrderingComposer,
          $$OfflinePlaylistsTableAnnotationComposer,
          $$OfflinePlaylistsTableCreateCompanionBuilder,
          $$OfflinePlaylistsTableUpdateCompanionBuilder,
          (
            OfflinePlaylist,
            BaseReferences<
              _$AppDatabase,
              $OfflinePlaylistsTable,
              OfflinePlaylist
            >,
          ),
          OfflinePlaylist,
          PrefetchHooks Function()
        > {
  $$OfflinePlaylistsTableTableManager(
    _$AppDatabase db,
    $OfflinePlaylistsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OfflinePlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OfflinePlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OfflinePlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> playlistId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> description = const Value.absent(),
                Value<String?> artworkUrl = const Value.absent(),
                Value<bool> autoDownloadNewTracks = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OfflinePlaylistsCompanion(
                playlistId: playlistId,
                name: name,
                description: description,
                artworkUrl: artworkUrl,
                autoDownloadNewTracks: autoDownloadNewTracks,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String playlistId,
                required String name,
                Value<String?> description = const Value.absent(),
                Value<String?> artworkUrl = const Value.absent(),
                Value<bool> autoDownloadNewTracks = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => OfflinePlaylistsCompanion.insert(
                playlistId: playlistId,
                name: name,
                description: description,
                artworkUrl: artworkUrl,
                autoDownloadNewTracks: autoDownloadNewTracks,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OfflinePlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OfflinePlaylistsTable,
      OfflinePlaylist,
      $$OfflinePlaylistsTableFilterComposer,
      $$OfflinePlaylistsTableOrderingComposer,
      $$OfflinePlaylistsTableAnnotationComposer,
      $$OfflinePlaylistsTableCreateCompanionBuilder,
      $$OfflinePlaylistsTableUpdateCompanionBuilder,
      (
        OfflinePlaylist,
        BaseReferences<_$AppDatabase, $OfflinePlaylistsTable, OfflinePlaylist>,
      ),
      OfflinePlaylist,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$OfflineTracksTableTableManager get offlineTracks =>
      $$OfflineTracksTableTableManager(_db, _db.offlineTracks);
  $$OfflinePlaylistsTableTableManager get offlinePlaylists =>
      $$OfflinePlaylistsTableTableManager(_db, _db.offlinePlaylists);
}
