/// Facts about owning an item: what it cost, and how much use it has had.
///
/// [UsageStats] is a *cached projection*, not a source of truth. The event log
/// is authoritative; these counters exist so a wardrobe grid can render without
/// replaying thousands of events per item. `UsageProjection` rebuilds them, and
/// a test asserts a replay reproduces them exactly.
library;

/// What an item cost and where it came from.
///
/// Money is held in minor units (cents, pence) as an [int]. Storing currency as
/// a double invites rounding drift in cost-per-wear once it is divided and
/// summed across a wardrobe.
final class PurchaseInfo {
  const PurchaseInfo({
    required this.priceMinorUnits,
    required this.currencyCode,
    this.purchasedAt,
    this.retailer,
  });

  /// Price in the currency's smallest unit — 4999 for 49.99.
  final int priceMinorUnits;

  /// ISO 4217 code, e.g. `'USD'`.
  final String currencyCode;

  final DateTime? purchasedAt;
  final String? retailer;

  /// The price as a decimal amount, for display and per-wear arithmetic.
  double get price => priceMinorUnits / 100.0;

  /// How long the item has been owned, as of [asOf].
  Duration? ageAt(DateTime asOf) =>
      purchasedAt == null ? null : asOf.difference(purchasedAt!);

  Map<String, Object?> toJson() => {
        'priceMinorUnits': priceMinorUnits,
        'currencyCode': currencyCode,
        if (purchasedAt != null) 'purchasedAt': purchasedAt!.toIso8601String(),
        if (retailer != null) 'retailer': retailer,
      };

  static PurchaseInfo fromJson(Map<String, Object?> json) => PurchaseInfo(
        priceMinorUnits: (json['priceMinorUnits']! as num).toInt(),
        currencyCode: json['currencyCode']! as String,
        purchasedAt: json['purchasedAt'] == null
            ? null
            : DateTime.parse(json['purchasedAt']! as String),
        retailer: json['retailer'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PurchaseInfo &&
          other.priceMinorUnits == priceMinorUnits &&
          other.currencyCode == currencyCode &&
          other.purchasedAt == purchasedAt &&
          other.retailer == retailer;

  @override
  int get hashCode =>
      Object.hash(priceMinorUnits, currencyCode, purchasedAt, retailer);

  @override
  String toString() =>
      'PurchaseInfo(${price.toStringAsFixed(2)} $currencyCode)';
}

/// How much an item has been used. Derived from the event log.
final class UsageStats {
  const UsageStats({
    this.timesWorn = 0,
    this.timesWashed = 0,
    this.wearsSinceWash = 0,
    this.lastWornAt,
    this.lastWashedAt,
    this.firstWornAt,
  });

  const UsageStats.none() : this();

  final int timesWorn;
  final int timesWashed;

  /// Wears since the last wash — the signal for whether something in the
  /// wardrobe actually needs washing.
  ///
  /// Cannot be derived from the other counters, because a wash resets it, so
  /// `UsageProjection` tracks it as it folds the event log.
  final int wearsSinceWash;

  final DateTime? lastWornAt;
  final DateTime? lastWashedAt;
  final DateTime? firstWornAt;

  bool get hasNeverBeenWorn => timesWorn == 0;

  /// How long since the item was last worn, as of [asOf].
  Duration? idleFor(DateTime asOf) =>
      lastWornAt == null ? null : asOf.difference(lastWornAt!);

  /// Cost per wear, or null when the item has no recorded price or no wears.
  ///
  /// The headline wardrobe statistic: a 200-unit coat worn 100 times is better
  /// value than a 20-unit shirt worn twice.
  double? costPerWear(PurchaseInfo? purchase) {
    if (purchase == null || timesWorn == 0) return null;
    return purchase.price / timesWorn;
  }

  UsageStats copyWith({
    int? timesWorn,
    int? timesWashed,
    int? wearsSinceWash,
    DateTime? lastWornAt,
    DateTime? lastWashedAt,
    DateTime? firstWornAt,
  }) =>
      UsageStats(
        timesWorn: timesWorn ?? this.timesWorn,
        timesWashed: timesWashed ?? this.timesWashed,
        wearsSinceWash: wearsSinceWash ?? this.wearsSinceWash,
        lastWornAt: lastWornAt ?? this.lastWornAt,
        lastWashedAt: lastWashedAt ?? this.lastWashedAt,
        firstWornAt: firstWornAt ?? this.firstWornAt,
      );

  Map<String, Object?> toJson() => {
        'timesWorn': timesWorn,
        'timesWashed': timesWashed,
        'wearsSinceWash': wearsSinceWash,
        if (lastWornAt != null) 'lastWornAt': lastWornAt!.toIso8601String(),
        if (lastWashedAt != null)
          'lastWashedAt': lastWashedAt!.toIso8601String(),
        if (firstWornAt != null) 'firstWornAt': firstWornAt!.toIso8601String(),
      };

  static UsageStats fromJson(Map<String, Object?> json) => UsageStats(
        timesWorn: (json['timesWorn'] as num?)?.toInt() ?? 0,
        timesWashed: (json['timesWashed'] as num?)?.toInt() ?? 0,
        wearsSinceWash: (json['wearsSinceWash'] as num?)?.toInt() ?? 0,
        lastWornAt: json['lastWornAt'] == null
            ? null
            : DateTime.parse(json['lastWornAt']! as String),
        lastWashedAt: json['lastWashedAt'] == null
            ? null
            : DateTime.parse(json['lastWashedAt']! as String),
        firstWornAt: json['firstWornAt'] == null
            ? null
            : DateTime.parse(json['firstWornAt']! as String),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UsageStats &&
          other.timesWorn == timesWorn &&
          other.timesWashed == timesWashed &&
          other.wearsSinceWash == wearsSinceWash &&
          other.lastWornAt == lastWornAt &&
          other.lastWashedAt == lastWashedAt &&
          other.firstWornAt == firstWornAt;

  @override
  int get hashCode => Object.hash(
        timesWorn,
        timesWashed,
        wearsSinceWash,
        lastWornAt,
        lastWashedAt,
        firstWornAt,
      );

  @override
  String toString() => 'UsageStats(worn $timesWorn, washed $timesWashed)';
}
