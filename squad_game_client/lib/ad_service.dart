import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';

class AdService {
  static RewardedAd? _rewardedAd;
  static bool _isAdLoaded = false;

  // Test Ad Unit ID (use this while testing)
  static const String _testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  // TODO: Replace this with your real Ad Unit ID later
  static const String _realRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917'; // ← Change later

  static void loadRewardedAd() {
    RewardedAd.load(
      adUnitId: _testRewardedAdUnitId, // Using test ID for now
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _rewardedAd = ad;
          _isAdLoaded = true;
          print('✅ Rewarded Ad loaded successfully');
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('❌ Rewarded Ad failed to load: $error');
          _isAdLoaded = false;
        },
      ),
    );
  }

  static void showRewardedAd({
    required BuildContext context,
    required Function onAdWatched, // This runs only if user watches the full ad
    required Function onAdFailed,
  }) {
    if (_rewardedAd == null || !_isAdLoaded) {
      print('Ad not ready yet');
      onAdFailed();
      loadRewardedAd(); // Try loading again
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        loadRewardedAd(); // Preload next ad
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        print('Ad failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        onAdFailed();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        print('User watched the ad and earned reward');
        onAdWatched(); // ← This is where we will call the server
      },
    );
  }
}