/// Feature flags.
///
/// Several capabilities in this product are modelled long before they are
/// implemented — embeddings, condition detection, the offline vision pipeline.
/// Flags let that half-built surface exist in the codebase without reaching
/// users, and let risky features be switched off in production without a
/// rollback.
library;

/// A togglable capability.
enum Feature {
  /// Detecting several garments in a single photograph of a laundry pile.
  pileScanning,

  /// Vector-embedding item re-identification, alongside attribute matching.
  embeddingMatching,

  /// On-device OCR and symbol detection before escalating to a cloud model.
  offlineVisionPipeline,

  /// Automatic assessment of fading, pilling, holes and stretching.
  conditionDetection,

  /// Wardrobe statistics and dashboards.
  analytics,

  /// Trip packing recommendations.
  packingAssistant,

  /// Outfit generation.
  outfitRecommendations,

  /// Syncing the wardrobe to the cloud.
  cloudSync,
}

/// Resolves whether a [Feature] is currently on.
abstract interface class FeatureFlags {
  bool isEnabled(Feature feature);
}

/// A fixed set of flags, resolved once at construction.
///
/// The default state reflects what is genuinely built and safe to expose;
/// everything still modelled-but-unimplemented is off.
final class StaticFeatureFlags implements FeatureFlags {
  const StaticFeatureFlags(this._enabled);

  /// Everything that actually works today.
  const StaticFeatureFlags.defaults() : _enabled = const {Feature.analytics};

  /// Turns everything on. Intended for tests that exercise gated paths.
  StaticFeatureFlags.all() : _enabled = Feature.values.toSet();

  final Set<Feature> _enabled;

  @override
  bool isEnabled(Feature feature) => _enabled.contains(feature);
}
