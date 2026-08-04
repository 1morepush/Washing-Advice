/// Photographs attached to an item.
///
/// One picture per garment is not enough. Recognition works far better with a
/// front and a back; the care label needs its own close-up so instructions can
/// be re-read without re-scanning; logo shots pin down the brand. Photos are
/// therefore a list with declared roles, not a single image field.
library;

/// What a photo is *of*, which determines what the system can learn from it.
enum PhotoRole {
  /// The item laid flat or hung, front on. The primary recognition image.
  front('Front'),

  /// The reverse side. Distinguishes otherwise identical garments.
  back('Back'),

  /// A close-up of the care label.
  careTag('Care label'),

  /// A close-up of the brand or size label.
  brandTag('Brand label'),

  /// A logo, badge or print.
  logo('Logo'),

  /// Fabric texture or a construction detail, for material identification.
  detail('Detail'),

  /// Evidence of wear: a stain, hole, fading or pilling.
  condition('Condition'),

  /// The item being worn, for outfit inspiration.
  worn('Worn');

  const PhotoRole(this.label);

  final String label;

  /// Whether this role is worth prompting the user to capture when adding an
  /// item. Condition and worn shots are captured incidentally, not on a
  /// checklist.
  bool get isRequestedAtCapture =>
      this == front || this == back || this == careTag;
}

/// A single stored photograph.
///
/// [uri] is deliberately opaque: the core does not care whether the bytes live
/// in the app's documents directory, a cache, or object storage. Resolving it
/// is the storage layer's job.
final class ItemPhoto {
  const ItemPhoto({
    required this.uri,
    required this.role,
    required this.capturedAt,
    this.width,
    this.height,
    this.isPrimary = false,
  });

  final String uri;
  final PhotoRole role;
  final DateTime capturedAt;
  final int? width;
  final int? height;

  /// Whether this is the image shown for the item in lists and grids.
  final bool isPrimary;

  ItemPhoto copyWith({PhotoRole? role, bool? isPrimary}) => ItemPhoto(
        uri: uri,
        role: role ?? this.role,
        capturedAt: capturedAt,
        width: width,
        height: height,
        isPrimary: isPrimary ?? this.isPrimary,
      );

  Map<String, Object?> toJson() => {
        'uri': uri,
        'role': role.name,
        'capturedAt': capturedAt.toIso8601String(),
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        'isPrimary': isPrimary,
      };

  static ItemPhoto fromJson(Map<String, Object?> json) => ItemPhoto(
        uri: json['uri']! as String,
        role: PhotoRole.values.byName(json['role']! as String),
        capturedAt: DateTime.parse(json['capturedAt']! as String),
        width: (json['width'] as num?)?.toInt(),
        height: (json['height'] as num?)?.toInt(),
        isPrimary: json['isPrimary'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ItemPhoto &&
          other.uri == uri &&
          other.role == role &&
          other.capturedAt == capturedAt &&
          other.width == width &&
          other.height == height &&
          other.isPrimary == isPrimary;

  @override
  int get hashCode =>
      Object.hash(uri, role, capturedAt, width, height, isPrimary);

  @override
  String toString() => 'ItemPhoto(${role.name}, $uri)';
}

/// The photos belonging to one item.
final class PhotoSet {
  PhotoSet(List<ItemPhoto> photos) : _photos = List.unmodifiable(photos);

  /// Private const path, so [empty] can be used as a default argument.
  const PhotoSet._const(this._photos);

  /// The shared empty set.
  static const PhotoSet empty = PhotoSet._const([]);

  final List<ItemPhoto> _photos;

  List<ItemPhoto> get photos => _photos;

  bool get isEmpty => _photos.isEmpty;

  int get length => _photos.length;

  /// The image to show in a list. Prefers an explicit primary, then a front
  /// shot, then whatever exists.
  ItemPhoto? get displayPhoto {
    if (_photos.isEmpty) return null;
    for (final photo in _photos) {
      if (photo.isPrimary) return photo;
    }
    for (final photo in _photos) {
      if (photo.role == PhotoRole.front) return photo;
    }
    return _photos.first;
  }

  Iterable<ItemPhoto> withRole(PhotoRole role) =>
      _photos.where((p) => p.role == role);

  /// The most recent care-label shot, so instructions can be re-read without
  /// digging the garment back out of the wardrobe.
  ItemPhoto? get careTagPhoto {
    final tags = withRole(PhotoRole.careTag).toList()
      ..sort((x, y) => y.capturedAt.compareTo(x.capturedAt));
    return tags.isEmpty ? null : tags.first;
  }

  /// Roles worth capturing that are still missing, to drive a "complete this
  /// item" prompt.
  Set<PhotoRole> get missingRequestedRoles => {
        for (final role in PhotoRole.values)
          if (role.isRequestedAtCapture && withRole(role).isEmpty) role,
      };

  PhotoSet add(ItemPhoto photo) => PhotoSet([..._photos, photo]);

  List<Object?> toJson() => _photos.map((p) => p.toJson()).toList();

  static PhotoSet fromJson(List<Object?> json) => PhotoSet([
        for (final entry in json)
          ItemPhoto.fromJson(entry! as Map<String, Object?>),
      ]);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoSet &&
          other._photos.length == _photos.length &&
          Iterable<int>.generate(_photos.length)
              .every((i) => _photos[i] == other._photos[i]);

  @override
  int get hashCode => Object.hashAll(_photos);

  @override
  String toString() => 'PhotoSet(${_photos.length} photos)';
}
