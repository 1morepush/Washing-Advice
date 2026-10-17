/// What a garment already in the wardrobe can honestly say to a buyer.
///
/// Internal to `selling/`, and deliberately not exported: these are the few
/// places where "what the wardrobe knows" has to be turned into something a
/// listing or a request can carry, and more than one file needs the same
/// answer. A copy in each would eventually disagree about, say, whether a
/// guessed fabric is worth printing in front of a buyer.
library;

/// How many times something was worn, as a phrase: `once`, `12 times`.
///
/// Zero is not handled here — "worn 0 times" is not a thing anyone says, and
/// what to say about a garment never worn depends on who is being told.
String timesWornPhrase(int times) => times == 1 ? 'once' : '$times times';
