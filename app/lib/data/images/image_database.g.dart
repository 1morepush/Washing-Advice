// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'image_database.dart';

// ignore_for_file: type=lint
class $StoredImagesTable extends StoredImages
    with TableInfo<$StoredImagesTable, StoredImage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StoredImagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bytesMeta = const VerificationMeta('bytes');
  @override
  late final GeneratedColumn<Uint8List> bytes = GeneratedColumn<Uint8List>(
    'bytes',
    aliasedName,
    false,
    type: DriftSqlType.blob,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _savedAtMeta = const VerificationMeta(
    'savedAt',
  );
  @override
  late final GeneratedColumn<DateTime> savedAt = GeneratedColumn<DateTime>(
    'saved_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [name, bytes, savedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stored_images';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredImage> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('bytes')) {
      context.handle(
        _bytesMeta,
        bytes.isAcceptableOrUnknown(data['bytes']!, _bytesMeta),
      );
    } else if (isInserting) {
      context.missing(_bytesMeta);
    }
    if (data.containsKey('saved_at')) {
      context.handle(
        _savedAtMeta,
        savedAt.isAcceptableOrUnknown(data['saved_at']!, _savedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_savedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  StoredImage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredImage(
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      bytes: attachedDatabase.typeMapping.read(
        DriftSqlType.blob,
        data['${effectivePrefix}bytes'],
      )!,
      savedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}saved_at'],
      )!,
    );
  }

  @override
  $StoredImagesTable createAlias(String alias) {
    return $StoredImagesTable(attachedDatabase, alias);
  }
}

class StoredImage extends DataClass implements Insertable<StoredImage> {
  /// `imageName(...)` — deterministic, so re-running a cutout replaces its
  /// predecessor instead of leaking a row per attempt.
  final String name;
  final Uint8List bytes;
  final DateTime savedAt;
  const StoredImage({
    required this.name,
    required this.bytes,
    required this.savedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['bytes'] = Variable<Uint8List>(bytes);
    map['saved_at'] = Variable<DateTime>(savedAt);
    return map;
  }

  StoredImagesCompanion toCompanion(bool nullToAbsent) {
    return StoredImagesCompanion(
      name: Value(name),
      bytes: Value(bytes),
      savedAt: Value(savedAt),
    );
  }

  factory StoredImage.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredImage(
      name: serializer.fromJson<String>(json['name']),
      bytes: serializer.fromJson<Uint8List>(json['bytes']),
      savedAt: serializer.fromJson<DateTime>(json['savedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'bytes': serializer.toJson<Uint8List>(bytes),
      'savedAt': serializer.toJson<DateTime>(savedAt),
    };
  }

  StoredImage copyWith({String? name, Uint8List? bytes, DateTime? savedAt}) =>
      StoredImage(
        name: name ?? this.name,
        bytes: bytes ?? this.bytes,
        savedAt: savedAt ?? this.savedAt,
      );
  StoredImage copyWithCompanion(StoredImagesCompanion data) {
    return StoredImage(
      name: data.name.present ? data.name.value : this.name,
      bytes: data.bytes.present ? data.bytes.value : this.bytes,
      savedAt: data.savedAt.present ? data.savedAt.value : this.savedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredImage(')
          ..write('name: $name, ')
          ..write('bytes: $bytes, ')
          ..write('savedAt: $savedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(name, $driftBlobEquality.hash(bytes), savedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredImage &&
          other.name == this.name &&
          $driftBlobEquality.equals(other.bytes, this.bytes) &&
          other.savedAt == this.savedAt);
}

class StoredImagesCompanion extends UpdateCompanion<StoredImage> {
  final Value<String> name;
  final Value<Uint8List> bytes;
  final Value<DateTime> savedAt;
  final Value<int> rowid;
  const StoredImagesCompanion({
    this.name = const Value.absent(),
    this.bytes = const Value.absent(),
    this.savedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StoredImagesCompanion.insert({
    required String name,
    required Uint8List bytes,
    required DateTime savedAt,
    this.rowid = const Value.absent(),
  }) : name = Value(name),
       bytes = Value(bytes),
       savedAt = Value(savedAt);
  static Insertable<StoredImage> custom({
    Expression<String>? name,
    Expression<Uint8List>? bytes,
    Expression<DateTime>? savedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (bytes != null) 'bytes': bytes,
      if (savedAt != null) 'saved_at': savedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StoredImagesCompanion copyWith({
    Value<String>? name,
    Value<Uint8List>? bytes,
    Value<DateTime>? savedAt,
    Value<int>? rowid,
  }) {
    return StoredImagesCompanion(
      name: name ?? this.name,
      bytes: bytes ?? this.bytes,
      savedAt: savedAt ?? this.savedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (bytes.present) {
      map['bytes'] = Variable<Uint8List>(bytes.value);
    }
    if (savedAt.present) {
      map['saved_at'] = Variable<DateTime>(savedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StoredImagesCompanion(')
          ..write('name: $name, ')
          ..write('bytes: $bytes, ')
          ..write('savedAt: $savedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ImageDatabase extends GeneratedDatabase {
  _$ImageDatabase(QueryExecutor e) : super(e);
  $ImageDatabaseManager get managers => $ImageDatabaseManager(this);
  late final $StoredImagesTable storedImages = $StoredImagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [storedImages];
}

typedef $$StoredImagesTableCreateCompanionBuilder =
    StoredImagesCompanion Function({
      required String name,
      required Uint8List bytes,
      required DateTime savedAt,
      Value<int> rowid,
    });
typedef $$StoredImagesTableUpdateCompanionBuilder =
    StoredImagesCompanion Function({
      Value<String> name,
      Value<Uint8List> bytes,
      Value<DateTime> savedAt,
      Value<int> rowid,
    });

class $$StoredImagesTableFilterComposer
    extends Composer<_$ImageDatabase, $StoredImagesTable> {
  $$StoredImagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StoredImagesTableOrderingComposer
    extends Composer<_$ImageDatabase, $StoredImagesTable> {
  $$StoredImagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<Uint8List> get bytes => $composableBuilder(
    column: $table.bytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get savedAt => $composableBuilder(
    column: $table.savedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StoredImagesTableAnnotationComposer
    extends Composer<_$ImageDatabase, $StoredImagesTable> {
  $$StoredImagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<Uint8List> get bytes =>
      $composableBuilder(column: $table.bytes, builder: (column) => column);

  GeneratedColumn<DateTime> get savedAt =>
      $composableBuilder(column: $table.savedAt, builder: (column) => column);
}

class $$StoredImagesTableTableManager
    extends
        RootTableManager<
          _$ImageDatabase,
          $StoredImagesTable,
          StoredImage,
          $$StoredImagesTableFilterComposer,
          $$StoredImagesTableOrderingComposer,
          $$StoredImagesTableAnnotationComposer,
          $$StoredImagesTableCreateCompanionBuilder,
          $$StoredImagesTableUpdateCompanionBuilder,
          (
            StoredImage,
            BaseReferences<_$ImageDatabase, $StoredImagesTable, StoredImage>,
          ),
          StoredImage,
          PrefetchHooks Function()
        > {
  $$StoredImagesTableTableManager(_$ImageDatabase db, $StoredImagesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StoredImagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StoredImagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StoredImagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> name = const Value.absent(),
                Value<Uint8List> bytes = const Value.absent(),
                Value<DateTime> savedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StoredImagesCompanion(
                name: name,
                bytes: bytes,
                savedAt: savedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String name,
                required Uint8List bytes,
                required DateTime savedAt,
                Value<int> rowid = const Value.absent(),
              }) => StoredImagesCompanion.insert(
                name: name,
                bytes: bytes,
                savedAt: savedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StoredImagesTableProcessedTableManager =
    ProcessedTableManager<
      _$ImageDatabase,
      $StoredImagesTable,
      StoredImage,
      $$StoredImagesTableFilterComposer,
      $$StoredImagesTableOrderingComposer,
      $$StoredImagesTableAnnotationComposer,
      $$StoredImagesTableCreateCompanionBuilder,
      $$StoredImagesTableUpdateCompanionBuilder,
      (
        StoredImage,
        BaseReferences<_$ImageDatabase, $StoredImagesTable, StoredImage>,
      ),
      StoredImage,
      PrefetchHooks Function()
    >;

class $ImageDatabaseManager {
  final _$ImageDatabase _db;
  $ImageDatabaseManager(this._db);
  $$StoredImagesTableTableManager get storedImages =>
      $$StoredImagesTableTableManager(_db, _db.storedImages);
}
