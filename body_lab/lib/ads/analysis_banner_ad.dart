import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// 分析頁底部的橫幅廣告單元 ID。
///
/// 目前是 Google 官方的測試 ID；上架前換成 AdMob 後台建立的正式 ID，
/// 也可以在建置時用 `--dart-define=ADMOB_BANNER_IOS=...` 覆蓋。
/// iOS Info.plist 的 GADApplicationIdentifier 與 Android manifest 的
/// APPLICATION_ID 也要一起換成正式的 App ID。
const _bannerUnitIos = String.fromEnvironment(
  'ADMOB_BANNER_IOS',
  defaultValue: 'ca-app-pub-3940256099942544/2934735716',
);
const _bannerUnitAndroid = String.fromEnvironment(
  'ADMOB_BANNER_ANDROID',
  defaultValue: 'ca-app-pub-3940256099942544/6300978111',
);

/// 分析頁底部固定的橫幅廣告。
///
/// 健康資料不能用在廣告（App Store 5.1.3 / Health Connect 政策），
/// 所以只請求非個人化廣告，也不帶任何關鍵字或內容網址。
/// 頁籤在 IndexedStack 裡隱藏時 TickerMode 會關閉，第一次真的切到分析頁才載入，
/// 避免在看不到的地方產生曝光。
class AnalysisBannerAd extends StatefulWidget {
  const AnalysisBannerAd({super.key});

  @override
  State<AnalysisBannerAd> createState() => _AnalysisBannerAdState();
}

class _AnalysisBannerAdState extends State<AnalysisBannerAd> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested && TickerMode.valuesOf(context).enabled) {
      _requested = true;
      _load();
    }
  }

  Future<void> _load() async {
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (!mounted || size == null) return;

    _ad = BannerAd(
      adUnitId: Platform.isIOS ? _bannerUnitIos : _bannerUnitAndroid,
      size: size,
      request: const AdRequest(nonPersonalizedAds: true),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('分析頁橫幅廣告載入失敗：$error');
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    // 沒載入成功就不佔空間。
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Padding(
      // 和上方內容、下方主導覽列都隔開，避免誤點。
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        heightFactor: 1,
        child: SizedBox(
          width: ad.size.width.toDouble(),
          height: ad.size.height.toDouble(),
          child: AdWidget(ad: ad),
        ),
      ),
    );
  }
}
