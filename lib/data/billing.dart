import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Um plano à venda na loja (mensal básico ou Premium).
class StorePlan {
  final String title;
  final String price;
  final bool premium;
  final Package _package;
  StorePlan._(this._package)
    : title = _package.storeProduct.title,
      price = _package.storeProduct.priceString,
      premium = _package.storeProduct.identifier.contains('premium');
}

/// Compras nas lojas (App Store / Google Play) pelo RevenueCat. O comprador
/// é identificado pelo id do usuário; o servidor confere a assinatura em
/// `billing/refresh`. Na web, ou num build sem a chave da loja, fica
/// indisponível.
abstract final class Billing {
  static const _androidKey = String.fromEnvironment('RC_ANDROID_KEY');
  static const _iosKey = String.fromEnvironment('RC_IOS_KEY');

  static String get _key {
    if (kIsWeb) return '';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidKey,
      TargetPlatform.iOS => _iosKey,
      _ => '',
    };
  }

  static bool get available => _key.isNotEmpty;

  static bool get isIOS =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Onde o usuário cancela ou troca a assinatura.
  static Uri get manageUrl => isIOS
      ? Uri.parse('https://apps.apple.com/account/subscriptions')
      : Uri.parse('https://play.google.com/store/account/subscriptions');

  static String? _user;

  static Future<void> _ensure(String userId) async {
    if (_user == userId) return;
    if (_user == null) {
      await Purchases.configure(
        PurchasesConfiguration(_key)..appUserID = userId,
      );
    } else {
      await Purchases.logIn(userId);
    }
    _user = userId;
  }

  static Future<List<StorePlan>> plans(String userId) async {
    await _ensure(userId);
    final offering = (await Purchases.getOfferings()).current;
    return [...?offering?.availablePackages.map(StorePlan._)];
  }

  /// `false` quando o usuário desiste na tela da loja.
  static Future<bool> buy(String userId, StorePlan plan) async {
    await _ensure(userId);
    try {
      await Purchases.purchase(PurchaseParams.package(plan._package));
      return true;
    } on PlatformException catch (e) {
      if (PurchasesErrorHelper.getErrorCode(e) ==
          PurchasesErrorCode.purchaseCancelledError) {
        return false;
      }
      rethrow;
    }
  }

  static Future<void> restore(String userId) async {
    await _ensure(userId);
    await Purchases.restorePurchases();
  }
}
