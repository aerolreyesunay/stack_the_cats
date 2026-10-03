import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/connectivity_service.dart';
import 'ad_service.dart';

/// A banner ad across the bottom of the screen, sized to fit the screen's
/// width. Takes no space at all until an ad has loaded, and none while
/// offline (even if one loaded earlier). Never overlaps the game: it sits
/// below it.
class BannerSlot extends StatefulWidget {
  const BannerSlot({super.key});

  @override
  State<BannerSlot> createState() => _BannerSlotState();
}

class _BannerSlotState extends State<BannerSlot> {
  BannerAd? _ad;
  bool _loaded = false;
  int? _loadedForWidth;

  final _ready = AdService.instance.ready;
  final _online = ConnectivityService.instance.online;

  @override
  void initState() {
    super.initState();
    _ready.addListener(_retry);
    _online.addListener(_onlineChanged);
  }

  /// Hides the banner while offline, and loads one when back online.
  void _onlineChanged() {
    if (mounted) setState(() {});
    _retry();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  void _retry() {
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    if (!_ready.value || !_online.value) return;
    final width = MediaQuery.sizeOf(context).width.truncate();
    if (_loadedForWidth == width) return;
    _loadedForWidth = width;
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) return;
    await _ad?.dispose();
    _ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('Banner failed: $error');
          ad.dispose();
          _ad = null;
          _loadedForWidth = null; // allow another try later
          if (mounted) setState(() => _loaded = false);
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ready.removeListener(_retry);
    _online.removeListener(_onlineChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null || !_online.value) {
      return const SizedBox.shrink();
    }
    return SafeArea(
      top: false,
      child: SizedBox(
        width: ad.size.width.toDouble(),
        height: ad.size.height.toDouble(),
        child: AdWidget(ad: ad),
      ),
    );
  }
}
