import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:flutter/material.dart';

class AdService {
  static RewardedAd? _rewardedAd;
  static bool _isAdLoaded = false;
  static final ValueNotifier<bool> adReadyNotifier = ValueNotifier(false);

  static const String _testRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917';

  static int _retryCount = 0;
  static const int _maxRetries = 5;

  static void loadRewardedAd() {
    print('🔄 Attempting to load Rewarded Ad... (Attempt ${_retryCount + 1})');

    RewardedAd.load(
      adUnitId: _testRewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          print('✅✅✅ Rewarded Ad loaded successfully!');
          _rewardedAd = ad;
          _isAdLoaded = true;
          adReadyNotifier.value = true;
          _retryCount = 0;
        },
        onAdFailedToLoad: (LoadAdError error) {
          print('❌❌❌ Rewarded Ad FAILED to load');
          print('Error Code: ${error.code}');
          print('Error Message: ${error.message}');
          print('Error Domain: ${error.domain}');
          print('Response Info: ${error.responseInfo}');

          _isAdLoaded = false;
          adReadyNotifier.value = false;
          _retryCount++;

          if (_retryCount < _maxRetries) {
            final delay = Duration(seconds: 3 + _retryCount); // Increasing delay
            print('🔁 Retrying in ${delay.inSeconds} seconds...');
            Future.delayed(delay, loadRewardedAd);
          } else {
            print('🛑 Max retries reached. Ad will not load automatically.');
          }
        },
      ),
    );
  }

  static bool get isAdReady => _rewardedAd != null && _isAdLoaded;

  static void showRewardedAd({
    required BuildContext context,
    required Function onAdWatched,
    required Function onAdFailed,
  }) {
    if (_rewardedAd == null || !_isAdLoaded) {
      print('Ad not ready yet');
      onAdFailed();
      loadRewardedAd();
      return;
    }

    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        adReadyNotifier.value = false;
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        print('Ad failed to show: $error');
        ad.dispose();
        _rewardedAd = null;
        _isAdLoaded = false;
        adReadyNotifier.value = false;
        onAdFailed();
      },
    );

    _rewardedAd!.show(
      onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
        print('User watched the ad and earned reward');
        onAdWatched();
      },
    );
  }
}