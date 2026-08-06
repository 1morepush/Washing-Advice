// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $ItemsTable extends Items with TableInfo<$ItemsTable, Item> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
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
  static const VerificationMeta _itemTypeMeta = const VerificationMeta(
    'itemType',
  );
  @override
  late final GeneratedColumn<String> itemType = GeneratedColumn<String>(
    'item_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _colorClassMeta = const VerificationMeta(
    'colorClass',
  );
  @override
  late final GeneratedColumn<String> colorClass = GeneratedColumn<String>(
    'color_class',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lifecycleMeta = const VerificationMeta(
    'lifecycle',
  );
  @override
  late final GeneratedColumn<String> lifecycle = GeneratedColumn<String>(
    'lifecycle',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandLowerMeta = const VerificationMeta(
    'brandLower',
  );
  @override
  late final GeneratedColumn<String> brandLower = GeneratedColumn<String>(
    'brand_lower',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _seasonsMeta = const VerificationMeta(
    'seasons',
  );
  @override
  late final GeneratedColumn<String> seasons = GeneratedColumn<String>(
    'seasons',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fibersMeta = const VerificationMeta('fibers');
  @override
  late final GeneratedColumn<String> fibers = GeneratedColumn<String>(
    'fibers',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsMeta = const VerificationMeta('tags');
  @override
  late final GeneratedColumn<String> tags = GeneratedColumn<String>(
    'tags',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _searchTextMeta = const VerificationMeta(
    'searchText',
  );
  @override
  late final GeneratedColumn<String> searchText = GeneratedColumn<String>(
    'search_text',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
  );
  static const VerificationMeta _needsCareTagScanMeta = const VerificationMeta(
    'needsCareTagScan',
  );
  @override
  late final GeneratedColumn<bool> needsCareTagScan = GeneratedColumn<bool>(
    'needs_care_tag_scan',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("needs_care_tag_scan" IN (0, 1))',
    ),
  );
  static const VerificationMeta _timesWornMeta = const VerificationMeta(
    'timesWorn',
  );
  @override
  late final GeneratedColumn<int> timesWorn = GeneratedColumn<int>(
    'times_worn',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastWornAtMeta = const VerificationMeta(
    'lastWornAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastWornAt = GeneratedColumn<DateTime>(
    'last_worn_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _costPerWearMinorMeta = const VerificationMeta(
    'costPerWearMinor',
  );
  @override
  late final GeneratedColumn<int> costPerWearMinor = GeneratedColumn<int>(
    'cost_per_wear_minor',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    payload,
    name,
    itemType,
    category,
    kind,
    colorClass,
    lifecycle,
    brandLower,
    seasons,
    fibers,
    tags,
    searchText,
    isFavorite,
    needsCareTagScan,
    timesWorn,
    lastWornAt,
    addedAt,
    costPerWearMinor,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'items';
  @override
  VerificationContext validateIntegrity(
    Insertable<Item> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('item_type')) {
      context.handle(
        _itemTypeMeta,
        itemType.isAcceptableOrUnknown(data['item_type']!, _itemTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_itemTypeMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('color_class')) {
      context.handle(
        _colorClassMeta,
        colorClass.isAcceptableOrUnknown(data['color_class']!, _colorClassMeta),
      );
    } else if (isInserting) {
      context.missing(_colorClassMeta);
    }
    if (data.containsKey('lifecycle')) {
      context.handle(
        _lifecycleMeta,
        lifecycle.isAcceptableOrUnknown(data['lifecycle']!, _lifecycleMeta),
      );
    } else if (isInserting) {
      context.missing(_lifecycleMeta);
    }
    if (data.containsKey('brand_lower')) {
      context.handle(
        _brandLowerMeta,
        brandLower.isAcceptableOrUnknown(data['brand_lower']!, _brandLowerMeta),
      );
    }
    if (data.containsKey('seasons')) {
      context.handle(
        _seasonsMeta,
        seasons.isAcceptableOrUnknown(data['seasons']!, _seasonsMeta),
      );
    } else if (isInserting) {
      context.missing(_seasonsMeta);
    }
    if (data.containsKey('fibers')) {
      context.handle(
        _fibersMeta,
        fibers.isAcceptableOrUnknown(data['fibers']!, _fibersMeta),
      );
    } else if (isInserting) {
      context.missing(_fibersMeta);
    }
    if (data.containsKey('tags')) {
      context.handle(
        _tagsMeta,
        tags.isAcceptableOrUnknown(data['tags']!, _tagsMeta),
      );
    } else if (isInserting) {
      context.missing(_tagsMeta);
    }
    if (data.containsKey('search_text')) {
      context.handle(
        _searchTextMeta,
        searchText.isAcceptableOrUnknown(data['search_text']!, _searchTextMeta),
      );
    } else if (isInserting) {
      context.missing(_searchTextMeta);
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    } else if (isInserting) {
      context.missing(_isFavoriteMeta);
    }
    if (data.containsKey('needs_care_tag_scan')) {
      context.handle(
        _needsCareTagScanMeta,
        needsCareTagScan.isAcceptableOrUnknown(
          data['needs_care_tag_scan']!,
          _needsCareTagScanMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_needsCareTagScanMeta);
    }
    if (data.containsKey('times_worn')) {
      context.handle(
        _timesWornMeta,
        timesWorn.isAcceptableOrUnknown(data['times_worn']!, _timesWornMeta),
      );
    } else if (isInserting) {
      context.missing(_timesWornMeta);
    }
    if (data.containsKey('last_worn_at')) {
      context.handle(
        _lastWornAtMeta,
        lastWornAt.isAcceptableOrUnknown(
          data['last_worn_at']!,
          _lastWornAtMeta,
        ),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    if (data.containsKey('cost_per_wear_minor')) {
      context.handle(
        _costPerWearMinorMeta,
        costPerWearMinor.isAcceptableOrUnknown(
          data['cost_per_wear_minor']!,
          _costPerWearMinorMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Item map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Item(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      itemType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_type'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      colorClass: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}color_class'],
      )!,
      lifecycle: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lifecycle'],
      )!,
      brandLower: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand_lower'],
      ),
      seasons: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}seasons'],
      )!,
      fibers: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fibers'],
      )!,
      tags: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags'],
      )!,
      searchText: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}search_text'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      needsCareTagScan: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}needs_care_tag_scan'],
      )!,
      timesWorn: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}times_worn'],
      )!,
      lastWornAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_worn_at'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      costPerWearMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cost_per_wear_minor'],
      ),
    );
  }

  @override
  $ItemsTable createAlias(String alias) {
    return $ItemsTable(attachedDatabase, alias);
  }
}

class Item extends DataClass implements Insertable<Item> {
  final String id;

  /// The full `WardrobeItem`, as the core serialises it.
  final String payload;
  final String name;
  final String itemType;
  final String category;
  final String kind;
  final String colorClass;
  final String lifecycle;

  /// Lower-cased, so brand filtering is case-insensitive without a scan.
  final String? brandLower;
  final String seasons;
  final String fibers;
  final String tags;

  /// Name, brand, type label, notes and any printed text, lower-cased, for
  /// free-text search without decoding every payload.
  final String searchText;
  final bool isFavorite;
  final bool needsCareTagScan;
  final int timesWorn;
  final DateTime? lastWornAt;
  final DateTime addedAt;

  /// Cost per wear in minor units, precomputed so sorting does not need to
  /// decode. Null when unpriced or unworn, which sorts last.
  final int? costPerWearMinor;
  const Item({
    required this.id,
    required this.payload,
    required this.name,
    required this.itemType,
    required this.category,
    required this.kind,
    required this.colorClass,
    required this.lifecycle,
    this.brandLower,
    required this.seasons,
    required this.fibers,
    required this.tags,
    required this.searchText,
    required this.isFavorite,
    required this.needsCareTagScan,
    required this.timesWorn,
    this.lastWornAt,
    required this.addedAt,
    this.costPerWearMinor,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    map['name'] = Variable<String>(name);
    map['item_type'] = Variable<String>(itemType);
    map['category'] = Variable<String>(category);
    map['kind'] = Variable<String>(kind);
    map['color_class'] = Variable<String>(colorClass);
    map['lifecycle'] = Variable<String>(lifecycle);
    if (!nullToAbsent || brandLower != null) {
      map['brand_lower'] = Variable<String>(brandLower);
    }
    map['seasons'] = Variable<String>(seasons);
    map['fibers'] = Variable<String>(fibers);
    map['tags'] = Variable<String>(tags);
    map['search_text'] = Variable<String>(searchText);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['needs_care_tag_scan'] = Variable<bool>(needsCareTagScan);
    map['times_worn'] = Variable<int>(timesWorn);
    if (!nullToAbsent || lastWornAt != null) {
      map['last_worn_at'] = Variable<DateTime>(lastWornAt);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    if (!nullToAbsent || costPerWearMinor != null) {
      map['cost_per_wear_minor'] = Variable<int>(costPerWearMinor);
    }
    return map;
  }

  ItemsCompanion toCompanion(bool nullToAbsent) {
    return ItemsCompanion(
      id: Value(id),
      payload: Value(payload),
      name: Value(name),
      itemType: Value(itemType),
      category: Value(category),
      kind: Value(kind),
      colorClass: Value(colorClass),
      lifecycle: Value(lifecycle),
      brandLower: brandLower == null && nullToAbsent
          ? const Value.absent()
          : Value(brandLower),
      seasons: Value(seasons),
      fibers: Value(fibers),
      tags: Value(tags),
      searchText: Value(searchText),
      isFavorite: Value(isFavorite),
      needsCareTagScan: Value(needsCareTagScan),
      timesWorn: Value(timesWorn),
      lastWornAt: lastWornAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastWornAt),
      addedAt: Value(addedAt),
      costPerWearMinor: costPerWearMinor == null && nullToAbsent
          ? const Value.absent()
          : Value(costPerWearMinor),
    );
  }

  factory Item.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Item(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
      name: serializer.fromJson<String>(json['name']),
      itemType: serializer.fromJson<String>(json['itemType']),
      category: serializer.fromJson<String>(json['category']),
      kind: serializer.fromJson<String>(json['kind']),
      colorClass: serializer.fromJson<String>(json['colorClass']),
      lifecycle: serializer.fromJson<String>(json['lifecycle']),
      brandLower: serializer.fromJson<String?>(json['brandLower']),
      seasons: serializer.fromJson<String>(json['seasons']),
      fibers: serializer.fromJson<String>(json['fibers']),
      tags: serializer.fromJson<String>(json['tags']),
      searchText: serializer.fromJson<String>(json['searchText']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      needsCareTagScan: serializer.fromJson<bool>(json['needsCareTagScan']),
      timesWorn: serializer.fromJson<int>(json['timesWorn']),
      lastWornAt: serializer.fromJson<DateTime?>(json['lastWornAt']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      costPerWearMinor: serializer.fromJson<int?>(json['costPerWearMinor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
      'name': serializer.toJson<String>(name),
      'itemType': serializer.toJson<String>(itemType),
      'category': serializer.toJson<String>(category),
      'kind': serializer.toJson<String>(kind),
      'colorClass': serializer.toJson<String>(colorClass),
      'lifecycle': serializer.toJson<String>(lifecycle),
      'brandLower': serializer.toJson<String?>(brandLower),
      'seasons': serializer.toJson<String>(seasons),
      'fibers': serializer.toJson<String>(fibers),
      'tags': serializer.toJson<String>(tags),
      'searchText': serializer.toJson<String>(searchText),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'needsCareTagScan': serializer.toJson<bool>(needsCareTagScan),
      'timesWorn': serializer.toJson<int>(timesWorn),
      'lastWornAt': serializer.toJson<DateTime?>(lastWornAt),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'costPerWearMinor': serializer.toJson<int?>(costPerWearMinor),
    };
  }

  Item copyWith({
    String? id,
    String? payload,
    String? name,
    String? itemType,
    String? category,
    String? kind,
    String? colorClass,
    String? lifecycle,
    Value<String?> brandLower = const Value.absent(),
    String? seasons,
    String? fibers,
    String? tags,
    String? searchText,
    bool? isFavorite,
    bool? needsCareTagScan,
    int? timesWorn,
    Value<DateTime?> lastWornAt = const Value.absent(),
    DateTime? addedAt,
    Value<int?> costPerWearMinor = const Value.absent(),
  }) => Item(
    id: id ?? this.id,
    payload: payload ?? this.payload,
    name: name ?? this.name,
    itemType: itemType ?? this.itemType,
    category: category ?? this.category,
    kind: kind ?? this.kind,
    colorClass: colorClass ?? this.colorClass,
    lifecycle: lifecycle ?? this.lifecycle,
    brandLower: brandLower.present ? brandLower.value : this.brandLower,
    seasons: seasons ?? this.seasons,
    fibers: fibers ?? this.fibers,
    tags: tags ?? this.tags,
    searchText: searchText ?? this.searchText,
    isFavorite: isFavorite ?? this.isFavorite,
    needsCareTagScan: needsCareTagScan ?? this.needsCareTagScan,
    timesWorn: timesWorn ?? this.timesWorn,
    lastWornAt: lastWornAt.present ? lastWornAt.value : this.lastWornAt,
    addedAt: addedAt ?? this.addedAt,
    costPerWearMinor: costPerWearMinor.present
        ? costPerWearMinor.value
        : this.costPerWearMinor,
  );
  Item copyWithCompanion(ItemsCompanion data) {
    return Item(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
      name: data.name.present ? data.name.value : this.name,
      itemType: data.itemType.present ? data.itemType.value : this.itemType,
      category: data.category.present ? data.category.value : this.category,
      kind: data.kind.present ? data.kind.value : this.kind,
      colorClass: data.colorClass.present
          ? data.colorClass.value
          : this.colorClass,
      lifecycle: data.lifecycle.present ? data.lifecycle.value : this.lifecycle,
      brandLower: data.brandLower.present
          ? data.brandLower.value
          : this.brandLower,
      seasons: data.seasons.present ? data.seasons.value : this.seasons,
      fibers: data.fibers.present ? data.fibers.value : this.fibers,
      tags: data.tags.present ? data.tags.value : this.tags,
      searchText: data.searchText.present
          ? data.searchText.value
          : this.searchText,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      needsCareTagScan: data.needsCareTagScan.present
          ? data.needsCareTagScan.value
          : this.needsCareTagScan,
      timesWorn: data.timesWorn.present ? data.timesWorn.value : this.timesWorn,
      lastWornAt: data.lastWornAt.present
          ? data.lastWornAt.value
          : this.lastWornAt,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      costPerWearMinor: data.costPerWearMinor.present
          ? data.costPerWearMinor.value
          : this.costPerWearMinor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Item(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('name: $name, ')
          ..write('itemType: $itemType, ')
          ..write('category: $category, ')
          ..write('kind: $kind, ')
          ..write('colorClass: $colorClass, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('brandLower: $brandLower, ')
          ..write('seasons: $seasons, ')
          ..write('fibers: $fibers, ')
          ..write('tags: $tags, ')
          ..write('searchText: $searchText, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('needsCareTagScan: $needsCareTagScan, ')
          ..write('timesWorn: $timesWorn, ')
          ..write('lastWornAt: $lastWornAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('costPerWearMinor: $costPerWearMinor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    payload,
    name,
    itemType,
    category,
    kind,
    colorClass,
    lifecycle,
    brandLower,
    seasons,
    fibers,
    tags,
    searchText,
    isFavorite,
    needsCareTagScan,
    timesWorn,
    lastWornAt,
    addedAt,
    costPerWearMinor,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Item &&
          other.id == this.id &&
          other.payload == this.payload &&
          other.name == this.name &&
          other.itemType == this.itemType &&
          other.category == this.category &&
          other.kind == this.kind &&
          other.colorClass == this.colorClass &&
          other.lifecycle == this.lifecycle &&
          other.brandLower == this.brandLower &&
          other.seasons == this.seasons &&
          other.fibers == this.fibers &&
          other.tags == this.tags &&
          other.searchText == this.searchText &&
          other.isFavorite == this.isFavorite &&
          other.needsCareTagScan == this.needsCareTagScan &&
          other.timesWorn == this.timesWorn &&
          other.lastWornAt == this.lastWornAt &&
          other.addedAt == this.addedAt &&
          other.costPerWearMinor == this.costPerWearMinor);
}

class ItemsCompanion extends UpdateCompanion<Item> {
  final Value<String> id;
  final Value<String> payload;
  final Value<String> name;
  final Value<String> itemType;
  final Value<String> category;
  final Value<String> kind;
  final Value<String> colorClass;
  final Value<String> lifecycle;
  final Value<String?> brandLower;
  final Value<String> seasons;
  final Value<String> fibers;
  final Value<String> tags;
  final Value<String> searchText;
  final Value<bool> isFavorite;
  final Value<bool> needsCareTagScan;
  final Value<int> timesWorn;
  final Value<DateTime?> lastWornAt;
  final Value<DateTime> addedAt;
  final Value<int?> costPerWearMinor;
  final Value<int> rowid;
  const ItemsCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.name = const Value.absent(),
    this.itemType = const Value.absent(),
    this.category = const Value.absent(),
    this.kind = const Value.absent(),
    this.colorClass = const Value.absent(),
    this.lifecycle = const Value.absent(),
    this.brandLower = const Value.absent(),
    this.seasons = const Value.absent(),
    this.fibers = const Value.absent(),
    this.tags = const Value.absent(),
    this.searchText = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.needsCareTagScan = const Value.absent(),
    this.timesWorn = const Value.absent(),
    this.lastWornAt = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.costPerWearMinor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ItemsCompanion.insert({
    required String id,
    required String payload,
    required String name,
    required String itemType,
    required String category,
    required String kind,
    required String colorClass,
    required String lifecycle,
    this.brandLower = const Value.absent(),
    required String seasons,
    required String fibers,
    required String tags,
    required String searchText,
    required bool isFavorite,
    required bool needsCareTagScan,
    required int timesWorn,
    this.lastWornAt = const Value.absent(),
    required DateTime addedAt,
    this.costPerWearMinor = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payload = Value(payload),
       name = Value(name),
       itemType = Value(itemType),
       category = Value(category),
       kind = Value(kind),
       colorClass = Value(colorClass),
       lifecycle = Value(lifecycle),
       seasons = Value(seasons),
       fibers = Value(fibers),
       tags = Value(tags),
       searchText = Value(searchText),
       isFavorite = Value(isFavorite),
       needsCareTagScan = Value(needsCareTagScan),
       timesWorn = Value(timesWorn),
       addedAt = Value(addedAt);
  static Insertable<Item> custom({
    Expression<String>? id,
    Expression<String>? payload,
    Expression<String>? name,
    Expression<String>? itemType,
    Expression<String>? category,
    Expression<String>? kind,
    Expression<String>? colorClass,
    Expression<String>? lifecycle,
    Expression<String>? brandLower,
    Expression<String>? seasons,
    Expression<String>? fibers,
    Expression<String>? tags,
    Expression<String>? searchText,
    Expression<bool>? isFavorite,
    Expression<bool>? needsCareTagScan,
    Expression<int>? timesWorn,
    Expression<DateTime>? lastWornAt,
    Expression<DateTime>? addedAt,
    Expression<int>? costPerWearMinor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (name != null) 'name': name,
      if (itemType != null) 'item_type': itemType,
      if (category != null) 'category': category,
      if (kind != null) 'kind': kind,
      if (colorClass != null) 'color_class': colorClass,
      if (lifecycle != null) 'lifecycle': lifecycle,
      if (brandLower != null) 'brand_lower': brandLower,
      if (seasons != null) 'seasons': seasons,
      if (fibers != null) 'fibers': fibers,
      if (tags != null) 'tags': tags,
      if (searchText != null) 'search_text': searchText,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (needsCareTagScan != null) 'needs_care_tag_scan': needsCareTagScan,
      if (timesWorn != null) 'times_worn': timesWorn,
      if (lastWornAt != null) 'last_worn_at': lastWornAt,
      if (addedAt != null) 'added_at': addedAt,
      if (costPerWearMinor != null) 'cost_per_wear_minor': costPerWearMinor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ItemsCompanion copyWith({
    Value<String>? id,
    Value<String>? payload,
    Value<String>? name,
    Value<String>? itemType,
    Value<String>? category,
    Value<String>? kind,
    Value<String>? colorClass,
    Value<String>? lifecycle,
    Value<String?>? brandLower,
    Value<String>? seasons,
    Value<String>? fibers,
    Value<String>? tags,
    Value<String>? searchText,
    Value<bool>? isFavorite,
    Value<bool>? needsCareTagScan,
    Value<int>? timesWorn,
    Value<DateTime?>? lastWornAt,
    Value<DateTime>? addedAt,
    Value<int?>? costPerWearMinor,
    Value<int>? rowid,
  }) {
    return ItemsCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      name: name ?? this.name,
      itemType: itemType ?? this.itemType,
      category: category ?? this.category,
      kind: kind ?? this.kind,
      colorClass: colorClass ?? this.colorClass,
      lifecycle: lifecycle ?? this.lifecycle,
      brandLower: brandLower ?? this.brandLower,
      seasons: seasons ?? this.seasons,
      fibers: fibers ?? this.fibers,
      tags: tags ?? this.tags,
      searchText: searchText ?? this.searchText,
      isFavorite: isFavorite ?? this.isFavorite,
      needsCareTagScan: needsCareTagScan ?? this.needsCareTagScan,
      timesWorn: timesWorn ?? this.timesWorn,
      lastWornAt: lastWornAt ?? this.lastWornAt,
      addedAt: addedAt ?? this.addedAt,
      costPerWearMinor: costPerWearMinor ?? this.costPerWearMinor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (itemType.present) {
      map['item_type'] = Variable<String>(itemType.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (colorClass.present) {
      map['color_class'] = Variable<String>(colorClass.value);
    }
    if (lifecycle.present) {
      map['lifecycle'] = Variable<String>(lifecycle.value);
    }
    if (brandLower.present) {
      map['brand_lower'] = Variable<String>(brandLower.value);
    }
    if (seasons.present) {
      map['seasons'] = Variable<String>(seasons.value);
    }
    if (fibers.present) {
      map['fibers'] = Variable<String>(fibers.value);
    }
    if (tags.present) {
      map['tags'] = Variable<String>(tags.value);
    }
    if (searchText.present) {
      map['search_text'] = Variable<String>(searchText.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
    }
    if (needsCareTagScan.present) {
      map['needs_care_tag_scan'] = Variable<bool>(needsCareTagScan.value);
    }
    if (timesWorn.present) {
      map['times_worn'] = Variable<int>(timesWorn.value);
    }
    if (lastWornAt.present) {
      map['last_worn_at'] = Variable<DateTime>(lastWornAt.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (costPerWearMinor.present) {
      map['cost_per_wear_minor'] = Variable<int>(costPerWearMinor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ItemsCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('name: $name, ')
          ..write('itemType: $itemType, ')
          ..write('category: $category, ')
          ..write('kind: $kind, ')
          ..write('colorClass: $colorClass, ')
          ..write('lifecycle: $lifecycle, ')
          ..write('brandLower: $brandLower, ')
          ..write('seasons: $seasons, ')
          ..write('fibers: $fibers, ')
          ..write('tags: $tags, ')
          ..write('searchText: $searchText, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('needsCareTagScan: $needsCareTagScan, ')
          ..write('timesWorn: $timesWorn, ')
          ..write('lastWornAt: $lastWornAt, ')
          ..write('addedAt: $addedAt, ')
          ..write('costPerWearMinor: $costPerWearMinor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EventsTable extends Events with TableInfo<$EventsTable, Event> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EventsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdMeta = const VerificationMeta('itemId');
  @override
  late final GeneratedColumn<String> itemId = GeneratedColumn<String>(
    'item_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _occurredAtMeta = const VerificationMeta(
    'occurredAt',
  );
  @override
  late final GeneratedColumn<DateTime> occurredAt = GeneratedColumn<DateTime>(
    'occurred_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, itemId, occurredAt, payload];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'events';
  @override
  VerificationContext validateIntegrity(
    Insertable<Event> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('item_id')) {
      context.handle(
        _itemIdMeta,
        itemId.isAcceptableOrUnknown(data['item_id']!, _itemIdMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdMeta);
    }
    if (data.containsKey('occurred_at')) {
      context.handle(
        _occurredAtMeta,
        occurredAt.isAcceptableOrUnknown(data['occurred_at']!, _occurredAtMeta),
      );
    } else if (isInserting) {
      context.missing(_occurredAtMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Event map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Event(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      itemId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_id'],
      )!,
      occurredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}occurred_at'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
    );
  }

  @override
  $EventsTable createAlias(String alias) {
    return $EventsTable(attachedDatabase, alias);
  }
}

class Event extends DataClass implements Insertable<Event> {
  final String id;
  final String itemId;
  final DateTime occurredAt;
  final String payload;
  const Event({
    required this.id,
    required this.itemId,
    required this.occurredAt,
    required this.payload,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['item_id'] = Variable<String>(itemId);
    map['occurred_at'] = Variable<DateTime>(occurredAt);
    map['payload'] = Variable<String>(payload);
    return map;
  }

  EventsCompanion toCompanion(bool nullToAbsent) {
    return EventsCompanion(
      id: Value(id),
      itemId: Value(itemId),
      occurredAt: Value(occurredAt),
      payload: Value(payload),
    );
  }

  factory Event.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Event(
      id: serializer.fromJson<String>(json['id']),
      itemId: serializer.fromJson<String>(json['itemId']),
      occurredAt: serializer.fromJson<DateTime>(json['occurredAt']),
      payload: serializer.fromJson<String>(json['payload']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'itemId': serializer.toJson<String>(itemId),
      'occurredAt': serializer.toJson<DateTime>(occurredAt),
      'payload': serializer.toJson<String>(payload),
    };
  }

  Event copyWith({
    String? id,
    String? itemId,
    DateTime? occurredAt,
    String? payload,
  }) => Event(
    id: id ?? this.id,
    itemId: itemId ?? this.itemId,
    occurredAt: occurredAt ?? this.occurredAt,
    payload: payload ?? this.payload,
  );
  Event copyWithCompanion(EventsCompanion data) {
    return Event(
      id: data.id.present ? data.id.value : this.id,
      itemId: data.itemId.present ? data.itemId.value : this.itemId,
      occurredAt: data.occurredAt.present
          ? data.occurredAt.value
          : this.occurredAt,
      payload: data.payload.present ? data.payload.value : this.payload,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Event(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('payload: $payload')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, itemId, occurredAt, payload);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Event &&
          other.id == this.id &&
          other.itemId == this.itemId &&
          other.occurredAt == this.occurredAt &&
          other.payload == this.payload);
}

class EventsCompanion extends UpdateCompanion<Event> {
  final Value<String> id;
  final Value<String> itemId;
  final Value<DateTime> occurredAt;
  final Value<String> payload;
  final Value<int> rowid;
  const EventsCompanion({
    this.id = const Value.absent(),
    this.itemId = const Value.absent(),
    this.occurredAt = const Value.absent(),
    this.payload = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EventsCompanion.insert({
    required String id,
    required String itemId,
    required DateTime occurredAt,
    required String payload,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       itemId = Value(itemId),
       occurredAt = Value(occurredAt),
       payload = Value(payload);
  static Insertable<Event> custom({
    Expression<String>? id,
    Expression<String>? itemId,
    Expression<DateTime>? occurredAt,
    Expression<String>? payload,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (itemId != null) 'item_id': itemId,
      if (occurredAt != null) 'occurred_at': occurredAt,
      if (payload != null) 'payload': payload,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EventsCompanion copyWith({
    Value<String>? id,
    Value<String>? itemId,
    Value<DateTime>? occurredAt,
    Value<String>? payload,
    Value<int>? rowid,
  }) {
    return EventsCompanion(
      id: id ?? this.id,
      itemId: itemId ?? this.itemId,
      occurredAt: occurredAt ?? this.occurredAt,
      payload: payload ?? this.payload,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (itemId.present) {
      map['item_id'] = Variable<String>(itemId.value);
    }
    if (occurredAt.present) {
      map['occurred_at'] = Variable<DateTime>(occurredAt.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EventsCompanion(')
          ..write('id: $id, ')
          ..write('itemId: $itemId, ')
          ..write('occurredAt: $occurredAt, ')
          ..write('payload: $payload, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $OutfitsTable extends Outfits with TableInfo<$OutfitsTable, OutfitRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OutfitsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
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
  static const VerificationMeta _occasionMeta = const VerificationMeta(
    'occasion',
  );
  @override
  late final GeneratedColumn<String> occasion = GeneratedColumn<String>(
    'occasion',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _itemIdsMeta = const VerificationMeta(
    'itemIds',
  );
  @override
  late final GeneratedColumn<String> itemIds = GeneratedColumn<String>(
    'item_ids',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isFavoriteMeta = const VerificationMeta(
    'isFavorite',
  );
  @override
  late final GeneratedColumn<bool> isFavorite = GeneratedColumn<bool>(
    'is_favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_favorite" IN (0, 1))',
    ),
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
    id,
    payload,
    name,
    occasion,
    itemIds,
    isFavorite,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'outfits';
  @override
  VerificationContext validateIntegrity(
    Insertable<OutfitRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('occasion')) {
      context.handle(
        _occasionMeta,
        occasion.isAcceptableOrUnknown(data['occasion']!, _occasionMeta),
      );
    } else if (isInserting) {
      context.missing(_occasionMeta);
    }
    if (data.containsKey('item_ids')) {
      context.handle(
        _itemIdsMeta,
        itemIds.isAcceptableOrUnknown(data['item_ids']!, _itemIdsMeta),
      );
    } else if (isInserting) {
      context.missing(_itemIdsMeta);
    }
    if (data.containsKey('is_favorite')) {
      context.handle(
        _isFavoriteMeta,
        isFavorite.isAcceptableOrUnknown(data['is_favorite']!, _isFavoriteMeta),
      );
    } else if (isInserting) {
      context.missing(_isFavoriteMeta);
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
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OutfitRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OutfitRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      occasion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occasion'],
      )!,
      itemIds: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}item_ids'],
      )!,
      isFavorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_favorite'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $OutfitsTable createAlias(String alias) {
    return $OutfitsTable(attachedDatabase, alias);
  }
}

class OutfitRow extends DataClass implements Insertable<OutfitRow> {
  final String id;

  /// The full `Outfit`, as the core serialises it.
  final String payload;
  final String name;
  final String occasion;

  /// `|id|id|` — see the note above about the delimiters.
  final String itemIds;
  final bool isFavorite;
  final DateTime updatedAt;
  const OutfitRow({
    required this.id,
    required this.payload,
    required this.name,
    required this.occasion,
    required this.itemIds,
    required this.isFavorite,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['payload'] = Variable<String>(payload);
    map['name'] = Variable<String>(name);
    map['occasion'] = Variable<String>(occasion);
    map['item_ids'] = Variable<String>(itemIds);
    map['is_favorite'] = Variable<bool>(isFavorite);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  OutfitsCompanion toCompanion(bool nullToAbsent) {
    return OutfitsCompanion(
      id: Value(id),
      payload: Value(payload),
      name: Value(name),
      occasion: Value(occasion),
      itemIds: Value(itemIds),
      isFavorite: Value(isFavorite),
      updatedAt: Value(updatedAt),
    );
  }

  factory OutfitRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OutfitRow(
      id: serializer.fromJson<String>(json['id']),
      payload: serializer.fromJson<String>(json['payload']),
      name: serializer.fromJson<String>(json['name']),
      occasion: serializer.fromJson<String>(json['occasion']),
      itemIds: serializer.fromJson<String>(json['itemIds']),
      isFavorite: serializer.fromJson<bool>(json['isFavorite']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'payload': serializer.toJson<String>(payload),
      'name': serializer.toJson<String>(name),
      'occasion': serializer.toJson<String>(occasion),
      'itemIds': serializer.toJson<String>(itemIds),
      'isFavorite': serializer.toJson<bool>(isFavorite),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  OutfitRow copyWith({
    String? id,
    String? payload,
    String? name,
    String? occasion,
    String? itemIds,
    bool? isFavorite,
    DateTime? updatedAt,
  }) => OutfitRow(
    id: id ?? this.id,
    payload: payload ?? this.payload,
    name: name ?? this.name,
    occasion: occasion ?? this.occasion,
    itemIds: itemIds ?? this.itemIds,
    isFavorite: isFavorite ?? this.isFavorite,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  OutfitRow copyWithCompanion(OutfitsCompanion data) {
    return OutfitRow(
      id: data.id.present ? data.id.value : this.id,
      payload: data.payload.present ? data.payload.value : this.payload,
      name: data.name.present ? data.name.value : this.name,
      occasion: data.occasion.present ? data.occasion.value : this.occasion,
      itemIds: data.itemIds.present ? data.itemIds.value : this.itemIds,
      isFavorite: data.isFavorite.present
          ? data.isFavorite.value
          : this.isFavorite,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OutfitRow(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('name: $name, ')
          ..write('occasion: $occasion, ')
          ..write('itemIds: $itemIds, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, payload, name, occasion, itemIds, isFavorite, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OutfitRow &&
          other.id == this.id &&
          other.payload == this.payload &&
          other.name == this.name &&
          other.occasion == this.occasion &&
          other.itemIds == this.itemIds &&
          other.isFavorite == this.isFavorite &&
          other.updatedAt == this.updatedAt);
}

class OutfitsCompanion extends UpdateCompanion<OutfitRow> {
  final Value<String> id;
  final Value<String> payload;
  final Value<String> name;
  final Value<String> occasion;
  final Value<String> itemIds;
  final Value<bool> isFavorite;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const OutfitsCompanion({
    this.id = const Value.absent(),
    this.payload = const Value.absent(),
    this.name = const Value.absent(),
    this.occasion = const Value.absent(),
    this.itemIds = const Value.absent(),
    this.isFavorite = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  OutfitsCompanion.insert({
    required String id,
    required String payload,
    required String name,
    required String occasion,
    required String itemIds,
    required bool isFavorite,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       payload = Value(payload),
       name = Value(name),
       occasion = Value(occasion),
       itemIds = Value(itemIds),
       isFavorite = Value(isFavorite),
       updatedAt = Value(updatedAt);
  static Insertable<OutfitRow> custom({
    Expression<String>? id,
    Expression<String>? payload,
    Expression<String>? name,
    Expression<String>? occasion,
    Expression<String>? itemIds,
    Expression<bool>? isFavorite,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (payload != null) 'payload': payload,
      if (name != null) 'name': name,
      if (occasion != null) 'occasion': occasion,
      if (itemIds != null) 'item_ids': itemIds,
      if (isFavorite != null) 'is_favorite': isFavorite,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  OutfitsCompanion copyWith({
    Value<String>? id,
    Value<String>? payload,
    Value<String>? name,
    Value<String>? occasion,
    Value<String>? itemIds,
    Value<bool>? isFavorite,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return OutfitsCompanion(
      id: id ?? this.id,
      payload: payload ?? this.payload,
      name: name ?? this.name,
      occasion: occasion ?? this.occasion,
      itemIds: itemIds ?? this.itemIds,
      isFavorite: isFavorite ?? this.isFavorite,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (occasion.present) {
      map['occasion'] = Variable<String>(occasion.value);
    }
    if (itemIds.present) {
      map['item_ids'] = Variable<String>(itemIds.value);
    }
    if (isFavorite.present) {
      map['is_favorite'] = Variable<bool>(isFavorite.value);
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
    return (StringBuffer('OutfitsCompanion(')
          ..write('id: $id, ')
          ..write('payload: $payload, ')
          ..write('name: $name, ')
          ..write('occasion: $occasion, ')
          ..write('itemIds: $itemIds, ')
          ..write('isFavorite: $isFavorite, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ItemsTable items = $ItemsTable(this);
  late final $EventsTable events = $EventsTable(this);
  late final $OutfitsTable outfits = $OutfitsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [items, events, outfits];
}

typedef $$ItemsTableCreateCompanionBuilder =
    ItemsCompanion Function({
      required String id,
      required String payload,
      required String name,
      required String itemType,
      required String category,
      required String kind,
      required String colorClass,
      required String lifecycle,
      Value<String?> brandLower,
      required String seasons,
      required String fibers,
      required String tags,
      required String searchText,
      required bool isFavorite,
      required bool needsCareTagScan,
      required int timesWorn,
      Value<DateTime?> lastWornAt,
      required DateTime addedAt,
      Value<int?> costPerWearMinor,
      Value<int> rowid,
    });
typedef $$ItemsTableUpdateCompanionBuilder =
    ItemsCompanion Function({
      Value<String> id,
      Value<String> payload,
      Value<String> name,
      Value<String> itemType,
      Value<String> category,
      Value<String> kind,
      Value<String> colorClass,
      Value<String> lifecycle,
      Value<String?> brandLower,
      Value<String> seasons,
      Value<String> fibers,
      Value<String> tags,
      Value<String> searchText,
      Value<bool> isFavorite,
      Value<bool> needsCareTagScan,
      Value<int> timesWorn,
      Value<DateTime?> lastWornAt,
      Value<DateTime> addedAt,
      Value<int?> costPerWearMinor,
      Value<int> rowid,
    });

class $$ItemsTableFilterComposer extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get colorClass => $composableBuilder(
    column: $table.colorClass,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brandLower => $composableBuilder(
    column: $table.brandLower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get seasons => $composableBuilder(
    column: $table.seasons,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fibers => $composableBuilder(
    column: $table.fibers,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get needsCareTagScan => $composableBuilder(
    column: $table.needsCareTagScan,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get timesWorn => $composableBuilder(
    column: $table.timesWorn,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastWornAt => $composableBuilder(
    column: $table.lastWornAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get costPerWearMinor => $composableBuilder(
    column: $table.costPerWearMinor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemType => $composableBuilder(
    column: $table.itemType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get colorClass => $composableBuilder(
    column: $table.colorClass,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lifecycle => $composableBuilder(
    column: $table.lifecycle,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brandLower => $composableBuilder(
    column: $table.brandLower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get seasons => $composableBuilder(
    column: $table.seasons,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fibers => $composableBuilder(
    column: $table.fibers,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tags => $composableBuilder(
    column: $table.tags,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get needsCareTagScan => $composableBuilder(
    column: $table.needsCareTagScan,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get timesWorn => $composableBuilder(
    column: $table.timesWorn,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastWornAt => $composableBuilder(
    column: $table.lastWornAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get costPerWearMinor => $composableBuilder(
    column: $table.costPerWearMinor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ItemsTable> {
  $$ItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get itemType =>
      $composableBuilder(column: $table.itemType, builder: (column) => column);

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get colorClass => $composableBuilder(
    column: $table.colorClass,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lifecycle =>
      $composableBuilder(column: $table.lifecycle, builder: (column) => column);

  GeneratedColumn<String> get brandLower => $composableBuilder(
    column: $table.brandLower,
    builder: (column) => column,
  );

  GeneratedColumn<String> get seasons =>
      $composableBuilder(column: $table.seasons, builder: (column) => column);

  GeneratedColumn<String> get fibers =>
      $composableBuilder(column: $table.fibers, builder: (column) => column);

  GeneratedColumn<String> get tags =>
      $composableBuilder(column: $table.tags, builder: (column) => column);

  GeneratedColumn<String> get searchText => $composableBuilder(
    column: $table.searchText,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get needsCareTagScan => $composableBuilder(
    column: $table.needsCareTagScan,
    builder: (column) => column,
  );

  GeneratedColumn<int> get timesWorn =>
      $composableBuilder(column: $table.timesWorn, builder: (column) => column);

  GeneratedColumn<DateTime> get lastWornAt => $composableBuilder(
    column: $table.lastWornAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<int> get costPerWearMinor => $composableBuilder(
    column: $table.costPerWearMinor,
    builder: (column) => column,
  );
}

class $$ItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ItemsTable,
          Item,
          $$ItemsTableFilterComposer,
          $$ItemsTableOrderingComposer,
          $$ItemsTableAnnotationComposer,
          $$ItemsTableCreateCompanionBuilder,
          $$ItemsTableUpdateCompanionBuilder,
          (Item, BaseReferences<_$AppDatabase, $ItemsTable, Item>),
          Item,
          PrefetchHooks Function()
        > {
  $$ItemsTableTableManager(_$AppDatabase db, $ItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> itemType = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> colorClass = const Value.absent(),
                Value<String> lifecycle = const Value.absent(),
                Value<String?> brandLower = const Value.absent(),
                Value<String> seasons = const Value.absent(),
                Value<String> fibers = const Value.absent(),
                Value<String> tags = const Value.absent(),
                Value<String> searchText = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<bool> needsCareTagScan = const Value.absent(),
                Value<int> timesWorn = const Value.absent(),
                Value<DateTime?> lastWornAt = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int?> costPerWearMinor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemsCompanion(
                id: id,
                payload: payload,
                name: name,
                itemType: itemType,
                category: category,
                kind: kind,
                colorClass: colorClass,
                lifecycle: lifecycle,
                brandLower: brandLower,
                seasons: seasons,
                fibers: fibers,
                tags: tags,
                searchText: searchText,
                isFavorite: isFavorite,
                needsCareTagScan: needsCareTagScan,
                timesWorn: timesWorn,
                lastWornAt: lastWornAt,
                addedAt: addedAt,
                costPerWearMinor: costPerWearMinor,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String payload,
                required String name,
                required String itemType,
                required String category,
                required String kind,
                required String colorClass,
                required String lifecycle,
                Value<String?> brandLower = const Value.absent(),
                required String seasons,
                required String fibers,
                required String tags,
                required String searchText,
                required bool isFavorite,
                required bool needsCareTagScan,
                required int timesWorn,
                Value<DateTime?> lastWornAt = const Value.absent(),
                required DateTime addedAt,
                Value<int?> costPerWearMinor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ItemsCompanion.insert(
                id: id,
                payload: payload,
                name: name,
                itemType: itemType,
                category: category,
                kind: kind,
                colorClass: colorClass,
                lifecycle: lifecycle,
                brandLower: brandLower,
                seasons: seasons,
                fibers: fibers,
                tags: tags,
                searchText: searchText,
                isFavorite: isFavorite,
                needsCareTagScan: needsCareTagScan,
                timesWorn: timesWorn,
                lastWornAt: lastWornAt,
                addedAt: addedAt,
                costPerWearMinor: costPerWearMinor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ItemsTable,
      Item,
      $$ItemsTableFilterComposer,
      $$ItemsTableOrderingComposer,
      $$ItemsTableAnnotationComposer,
      $$ItemsTableCreateCompanionBuilder,
      $$ItemsTableUpdateCompanionBuilder,
      (Item, BaseReferences<_$AppDatabase, $ItemsTable, Item>),
      Item,
      PrefetchHooks Function()
    >;
typedef $$EventsTableCreateCompanionBuilder =
    EventsCompanion Function({
      required String id,
      required String itemId,
      required DateTime occurredAt,
      required String payload,
      Value<int> rowid,
    });
typedef $$EventsTableUpdateCompanionBuilder =
    EventsCompanion Function({
      Value<String> id,
      Value<String> itemId,
      Value<DateTime> occurredAt,
      Value<String> payload,
      Value<int> rowid,
    });

class $$EventsTableFilterComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EventsTableOrderingComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemId => $composableBuilder(
    column: $table.itemId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EventsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EventsTable> {
  $$EventsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get itemId =>
      $composableBuilder(column: $table.itemId, builder: (column) => column);

  GeneratedColumn<DateTime> get occurredAt => $composableBuilder(
    column: $table.occurredAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);
}

class $$EventsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EventsTable,
          Event,
          $$EventsTableFilterComposer,
          $$EventsTableOrderingComposer,
          $$EventsTableAnnotationComposer,
          $$EventsTableCreateCompanionBuilder,
          $$EventsTableUpdateCompanionBuilder,
          (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
          Event,
          PrefetchHooks Function()
        > {
  $$EventsTableTableManager(_$AppDatabase db, $EventsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EventsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EventsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EventsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> itemId = const Value.absent(),
                Value<DateTime> occurredAt = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion(
                id: id,
                itemId: itemId,
                occurredAt: occurredAt,
                payload: payload,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String itemId,
                required DateTime occurredAt,
                required String payload,
                Value<int> rowid = const Value.absent(),
              }) => EventsCompanion.insert(
                id: id,
                itemId: itemId,
                occurredAt: occurredAt,
                payload: payload,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EventsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EventsTable,
      Event,
      $$EventsTableFilterComposer,
      $$EventsTableOrderingComposer,
      $$EventsTableAnnotationComposer,
      $$EventsTableCreateCompanionBuilder,
      $$EventsTableUpdateCompanionBuilder,
      (Event, BaseReferences<_$AppDatabase, $EventsTable, Event>),
      Event,
      PrefetchHooks Function()
    >;
typedef $$OutfitsTableCreateCompanionBuilder =
    OutfitsCompanion Function({
      required String id,
      required String payload,
      required String name,
      required String occasion,
      required String itemIds,
      required bool isFavorite,
      required DateTime updatedAt,
      Value<int> rowid,
    });
typedef $$OutfitsTableUpdateCompanionBuilder =
    OutfitsCompanion Function({
      Value<String> id,
      Value<String> payload,
      Value<String> name,
      Value<String> occasion,
      Value<String> itemIds,
      Value<bool> isFavorite,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$OutfitsTableFilterComposer
    extends Composer<_$AppDatabase, $OutfitsTable> {
  $$OutfitsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occasion => $composableBuilder(
    column: $table.occasion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get itemIds => $composableBuilder(
    column: $table.itemIds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OutfitsTableOrderingComposer
    extends Composer<_$AppDatabase, $OutfitsTable> {
  $$OutfitsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occasion => $composableBuilder(
    column: $table.occasion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get itemIds => $composableBuilder(
    column: $table.itemIds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OutfitsTableAnnotationComposer
    extends Composer<_$AppDatabase, $OutfitsTable> {
  $$OutfitsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get occasion =>
      $composableBuilder(column: $table.occasion, builder: (column) => column);

  GeneratedColumn<String> get itemIds =>
      $composableBuilder(column: $table.itemIds, builder: (column) => column);

  GeneratedColumn<bool> get isFavorite => $composableBuilder(
    column: $table.isFavorite,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$OutfitsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OutfitsTable,
          OutfitRow,
          $$OutfitsTableFilterComposer,
          $$OutfitsTableOrderingComposer,
          $$OutfitsTableAnnotationComposer,
          $$OutfitsTableCreateCompanionBuilder,
          $$OutfitsTableUpdateCompanionBuilder,
          (OutfitRow, BaseReferences<_$AppDatabase, $OutfitsTable, OutfitRow>),
          OutfitRow,
          PrefetchHooks Function()
        > {
  $$OutfitsTableTableManager(_$AppDatabase db, $OutfitsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OutfitsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OutfitsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OutfitsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> occasion = const Value.absent(),
                Value<String> itemIds = const Value.absent(),
                Value<bool> isFavorite = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => OutfitsCompanion(
                id: id,
                payload: payload,
                name: name,
                occasion: occasion,
                itemIds: itemIds,
                isFavorite: isFavorite,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String payload,
                required String name,
                required String occasion,
                required String itemIds,
                required bool isFavorite,
                required DateTime updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => OutfitsCompanion.insert(
                id: id,
                payload: payload,
                name: name,
                occasion: occasion,
                itemIds: itemIds,
                isFavorite: isFavorite,
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

typedef $$OutfitsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OutfitsTable,
      OutfitRow,
      $$OutfitsTableFilterComposer,
      $$OutfitsTableOrderingComposer,
      $$OutfitsTableAnnotationComposer,
      $$OutfitsTableCreateCompanionBuilder,
      $$OutfitsTableUpdateCompanionBuilder,
      (OutfitRow, BaseReferences<_$AppDatabase, $OutfitsTable, OutfitRow>),
      OutfitRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ItemsTableTableManager get items =>
      $$ItemsTableTableManager(_db, _db.items);
  $$EventsTableTableManager get events =>
      $$EventsTableTableManager(_db, _db.events);
  $$OutfitsTableTableManager get outfits =>
      $$OutfitsTableTableManager(_db, _db.outfits);
}
