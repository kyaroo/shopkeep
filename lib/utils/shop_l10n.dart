import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

/// Localized strings for the shop-info / shop-search surfaces.
///
/// The canonical `assets/lang/*.json` catalog is owned by another worker, so
/// these strings live in Dart rather than being added to that asset tree. They
/// follow the same three locales the app already ships (`fr`, `ar`, `en`) and
/// fall back to English for any missing key. `namedArgs` uses the same
/// `{name}` placeholders as easy_localization.
const Map<String, Map<String, String>> _strings = {
  'en': {
    'settings': 'Settings',
    'shopInfo': 'Shop info',
    'shopInfoTitle': 'Shop info',
    'shopInfoBusinessName': 'Business name',
    'shopInfoShopKey': 'Shop key',
    'shopInfoShopKeyHint': 'e.g. hanouti',
    'shopInfoLoad': 'Load info',
    'shopInfoLoading': 'Loading shop info…',
    'shopInfoProvisioner': 'Provisioned by',
    'shopInfoSignerId': 'Signer ID',
    'shopInfoSignerName': 'Name',
    'shopInfoSignerRole': 'Role',
    'shopInfoReadOnlyHint': 'Provisioning data is read-only.',
    'shopInfoAddress': 'Address',
    'shopInfoCity': 'City',
    'shopInfoOwnerName': 'Owner name',
    'shopInfoPhone': 'Phone',
    'shopInfoSave': 'Save changes',
    'shopInfoSaved': 'Shop info saved.',
    'shopInfoNoChanges': 'Nothing to save — edit a contact field first.',
    'shopInfoNotFound': 'Shop “{key}” was not found on the server.',
    'shopInfoForbidden': 'You are not allowed to view or edit this shop '
        '(server returned {status}).',
    'shopInfoBadRequest': 'The server rejected the change: {detail}',
    'shopInfoConflict': 'Conflict: {detail}',
    'shopInfoAuthFailed': 'Authentication failed ({status}) — check the '
        'server token in Sync settings.',
    'shopInfoLoadFailed': 'Could not load shop info: {detail}',
    'shopInfoSaveFailed': 'Could not save shop info: {detail}',
    'shopInfoNotConfigured': 'Server not configured — set the URL and token '
        'in Sync settings first.',
    'shopInfoCatalogVersion': 'Catalog version',
    'catalogPushSearchHint': 'Search shops by name or key…',
    'catalogPushAllVersions': 'All versions',
    'catalogPushVersionNever': 'Never reported (v0)',
    'catalogPushVersionOne': 'v1',
    'catalogPushVersionTwoPlus': 'v2 and later',
    'catalogPushLoadMore': 'Load more',
    'catalogPushShowing': 'Showing {count} of {total} shops',
    'catalogPushGroupVersion': 'Catalog version {version}',
    'catalogPushNoSearchResults': 'No shops match this search.',
    'catalogPushShopInfo': 'Shop info',
    'catalogPushUpToDate': 'Shop "{key}" is already at version {version}.',
    'catalogPushConfirmAction': 'Distribute',
    'catalogPushConfirmSummary':
        'Shop "{key}": version {base} -> {target} ({diff} generation(s)).',
    'catalogPushConfirmCounts': '{total} change(s): {additions} addition(s), '
        '{updates} update(s), {deletes} delete(s).',
    'catalogPushVersionsLine': 'Shop version {shop} - admin version {admin}',
    'catalogPushDifferenceLine': 'Difference: {diff} generation(s)',
    'updateCatalog': 'Update catalog',
    'updateCatalogHint': 'Pull the latest catalog from the server',
    'updateCatalogConfirmTitle': 'Update catalog?',
    'updateCatalogConfirmBody': 'Local version {local} -> latest {latest} '
        '({diff} generation(s)). {total} change(s): {upserts} update(s), '
        '{deletes} delete(s).',
    'updateCatalogDone': 'Catalog updated to version {version}.',
    'updateCatalogFailed': 'Update failed: {error}',
    'catalogUpToDate': 'Catalog is already up to date (version {version}).',
    'publishChanges': 'Publish changes',
    'publishChangesHint': 'Push local catalog changes to the server',
    'publishDoneTitle': 'Changes published',
    'publishDoneBody': 'Catalog version {old} -> {new}.',
    'publishFailed': 'Publish failed: {error}',
    'syncSettings': 'Sync settings',
    'syncParameters': 'Sync parameters',
    'syncStatusChecking': 'Checking…',
    'syncStatusMissing': 'Token missing',
    'syncStatusUnconfigured': 'Not configured',
    'syncStatusOk': 'Token · Server OK',
    'syncStatusRejected': 'Token rejected',
    'syncStatusDown': 'Server unreachable',
    'catalogDistribute': 'Distribute catalog',
    'catalogAddProduct': 'Add product',
    'shopMenuExportListing': 'Export listing',
    'shopMenuExportHistory': 'Export history',
    'shopNotRegistered': 'Not registered on server',
    'shopNotRegisteredHint': 'The shop works offline. Set the server URL and '
        'token in Sync settings, then create it again.',
    'shopRegistered': 'Registered on server',
    'catalogDeleteRowTitle': 'Delete product?',
    'catalogDeleteRowBody': 'Remove "{name}" from the catalog?',
    'shopCreatedRegistered': 'Shop "{key}" was created and registered on the '
        'server.',
    'shopCreatedNotRegistered': 'Shop "{key}" was created — not registered on '
        'server. It works offline.',
    'listingPushTarget': 'Target shop: {key}',
  },
  'fr': {
    'settings': 'Paramètres',
    'shopInfo': 'Infos boutique',
    'shopInfoTitle': 'Infos boutique',
    'shopInfoBusinessName': 'Nom de l’entreprise',
    'shopInfoShopKey': 'Clé boutique',
    'shopInfoShopKeyHint': 'ex. hanouti',
    'shopInfoLoad': 'Charger les infos',
    'shopInfoLoading': 'Chargement des infos…',
    'shopInfoProvisioner': 'Créée par',
    'shopInfoSignerId': 'ID du signataire',
    'shopInfoSignerName': 'Nom',
    'shopInfoSignerRole': 'Rôle',
    'shopInfoReadOnlyHint': 'Les données de création sont en lecture seule.',
    'shopInfoAddress': 'Adresse',
    'shopInfoCity': 'Ville',
    'shopInfoOwnerName': 'Nom du propriétaire',
    'shopInfoPhone': 'Téléphone',
    'shopInfoSave': 'Enregistrer',
    'shopInfoSaved': 'Infos boutique enregistrées.',
    'shopInfoNoChanges': 'Rien à enregistrer — modifiez d’abord un champ de contact.',
    'shopInfoNotFound': 'Boutique « {key} » introuvable sur le serveur.',
    'shopInfoForbidden': 'Vous n’êtes pas autorisé à voir ou modifier cette '
        'boutique (serveur : {status}).',
    'shopInfoBadRequest': 'Le serveur a refusé la modification : {detail}',
    'shopInfoConflict': 'Conflit : {detail}',
    'shopInfoAuthFailed': 'Échec de l’authentification ({status}) — vérifiez le '
        'jeton serveur dans les paramètres de synchronisation.',
    'shopInfoLoadFailed': 'Impossible de charger les infos : {detail}',
    'shopInfoSaveFailed': 'Impossible d’enregistrer les infos : {detail}',
    'shopInfoNotConfigured': 'Serveur non configuré — définissez d’abord '
        'l’URL et le jeton dans les paramètres de synchronisation.',
    'shopInfoCatalogVersion': 'Version du catalogue',
    'catalogPushSearchHint': 'Rechercher une boutique par nom ou clé…',
    'catalogPushAllVersions': 'Toutes les versions',
    'catalogPushVersionNever': 'Jamais signalée (v0)',
    'catalogPushVersionOne': 'v1',
    'catalogPushVersionTwoPlus': 'v2 et plus',
    'catalogPushLoadMore': 'Charger plus',
    'catalogPushShowing': '{count} boutiques sur {total}',
    'catalogPushGroupVersion': 'Version du catalogue {version}',
    'catalogPushNoSearchResults': 'Aucune boutique ne correspond à cette recherche.',
    'catalogPushShopInfo': 'Infos boutique',
    'catalogPushUpToDate': 'La boutique « {key} » est déjà à la version '
        '{version}.',
    'catalogPushConfirmAction': 'Distribuer',
    'catalogPushConfirmSummary': 'Boutique « {key} » : version {base} -> '
        '{target} ({diff} génération(s)).',
    'catalogPushConfirmCounts': '{total} modification(s) : {additions} ajout(s), '
        '{updates} mise(s) à jour, {deletes} suppression(s).',
    'catalogPushVersionsLine': 'Version boutique {shop} - version admin {admin}',
    'catalogPushDifferenceLine': 'Écart : {diff} génération(s)',
    'updateCatalog': 'Mettre à jour le catalogue',
    'updateCatalogHint': 'Récupérer le dernier catalogue du serveur',
    'updateCatalogConfirmTitle': 'Mettre à jour le catalogue ?',
    'updateCatalogConfirmBody': 'Version locale {local} -> dernière {latest} '
        '({diff} génération(s)). {total} modification(s) : {upserts} mise(s) à '
        'jour, {deletes} suppression(s).',
    'updateCatalogDone': 'Catalogue mis à jour vers la version {version}.',
    'updateCatalogFailed': 'Échec de la mise à jour : {error}',
    'catalogUpToDate': 'Le catalogue est déjà à jour (version {version}).',
    'publishChanges': 'Publier les modifications',
    'publishChangesHint': 'Envoyer les modifications locales au serveur',
    'publishDoneTitle': 'Modifications publiées',
    'publishDoneBody': 'Version du catalogue {old} -> {new}.',
    'publishFailed': 'Échec de la publication : {error}',
    'syncSettings': 'Paramètres de synchronisation',
    'syncParameters': 'Paramètres de synchronisation',
    'syncStatusChecking': 'Vérification…',
    'syncStatusMissing': 'Jeton manquant',
    'syncStatusUnconfigured': 'Non configuré',
    'syncStatusOk': 'Jeton · Serveur OK',
    'syncStatusRejected': 'Jeton rejeté',
    'syncStatusDown': 'Serveur injoignable',
    'catalogDistribute': 'Distribuer le catalogue',
    'catalogAddProduct': 'Ajouter un produit',
    'shopMenuExportListing': 'Exporter la liste',
    'shopMenuExportHistory': 'Exporter l’historique',
    'shopNotRegistered': 'Non enregistrée sur le serveur',
    'shopNotRegisteredHint': 'La boutique fonctionne hors ligne. Définissez '
        'l’URL et le jeton du serveur dans les paramètres de synchronisation, '
        'puis recréez-la.',
    'shopRegistered': 'Enregistrée sur le serveur',
    'catalogDeleteRowTitle': 'Supprimer le produit ?',
    'catalogDeleteRowBody': 'Retirer « {name} » du catalogue ?',
    'shopCreatedRegistered': 'La boutique « {key} » a été créée et enregistrée '
        'sur le serveur.',
    'shopCreatedNotRegistered': 'La boutique « {key} » a été créée — non '
        'enregistrée sur le serveur. Elle fonctionne hors ligne.',
    'listingPushTarget': 'Boutique cible : {key}',
  },
  'ar': {
    'settings': 'الإعدادات',
    'shopInfo': 'معلومات المتجر',
    'shopInfoTitle': 'معلومات المتجر',
    'shopInfoBusinessName': 'اسم المؤسسة',
    'shopInfoShopKey': 'مفتاح المتجر',
    'shopInfoShopKeyHint': 'مثال: hanouti',
    'shopInfoLoad': 'تحميل المعلومات',
    'shopInfoLoading': 'جارٍ تحميل معلومات المتجر…',
    'shopInfoProvisioner': 'أُنشئ بواسطة',
    'shopInfoSignerId': 'معرّف المُوقِّع',
    'shopInfoSignerName': 'الاسم',
    'shopInfoSignerRole': 'الدور',
    'shopInfoReadOnlyHint': 'بيانات الإنشاء للقراءة فقط.',
    'shopInfoAddress': 'العنوان',
    'shopInfoCity': 'المدينة',
    'shopInfoOwnerName': 'اسم المالك',
    'shopInfoPhone': 'الهاتف',
    'shopInfoSave': 'حفظ التغييرات',
    'shopInfoSaved': 'تم حفظ معلومات المتجر.',
    'shopInfoNoChanges': 'لا شيء للحفظ — عدّل حقل اتصال أولاً.',
    'shopInfoNotFound': 'المتجر « {key} » غير موجود على الخادم.',
    'shopInfoForbidden': 'غير مسموح لك بعرض أو تعديل هذا المتجر '
        '(استجابة الخادم {status}).',
    'shopInfoBadRequest': 'رفض الخادم التغيير: {detail}',
    'shopInfoConflict': 'تعارض: {detail}',
    'shopInfoAuthFailed': 'فشلت المصادقة ({status}) — تحقّق من رمز الخادم '
        'في إعدادات المزامنة.',
    'shopInfoLoadFailed': 'تعذّر تحميل معلومات المتجر: {detail}',
    'shopInfoSaveFailed': 'تعذّر حفظ معلومات المتجر: {detail}',
    'shopInfoNotConfigured': 'الخادم غير مُعدّ — اضبط العنوان والرمز في '
        'إعدادات المزامنة أولاً.',
    'shopInfoCatalogVersion': 'إصدار الكتالوج',
    'catalogPushSearchHint': 'ابحث عن متجر بالاسم أو المفتاح…',
    'catalogPushAllVersions': 'كل الإصدارات',
    'catalogPushVersionNever': 'لم يُبلَّغ (v0)',
    'catalogPushVersionOne': 'v1',
    'catalogPushVersionTwoPlus': 'v2 وما بعده',
    'catalogPushLoadMore': 'تحميل المزيد',
    'catalogPushShowing': 'عرض {count} من {total} متجر',
    'catalogPushGroupVersion': 'إصدار الكتالوج {version}',
    'catalogPushNoSearchResults': 'لا توجد متاجر تطابق هذا البحث.',
    'catalogPushShopInfo': 'معلومات المتجر',
    'catalogPushUpToDate': 'المتجر "{key}" موجود بالفعل على الإصدار {version}.',
    'catalogPushConfirmAction': 'توزيع',
    'catalogPushConfirmSummary': 'المتجر "{key}": الإصدار {base} -> {target} '
        '({diff} إصدار).',
    'catalogPushConfirmCounts': '{total} تغيير: {additions} إضافة، '
        '{updates} تحديث، {deletes} حذف.',
    'catalogPushVersionsLine': 'إصدار المتجر {shop} - إصدار المسؤول {admin}',
    'catalogPushDifferenceLine': 'الفرق: {diff} إصدار',
    'updateCatalog': 'تحديث الكتالوج',
    'updateCatalogHint': 'جلب أحدث كتالوج من الخادم',
    'updateCatalogConfirmTitle': 'تحديث الكتالوج؟',
    'updateCatalogConfirmBody': 'الإصدار المحلي {local} -> الأحدث {latest} '
        '({diff} إصدار). {total} تغيير: {upserts} تحديث، {deletes} حذف.',
    'updateCatalogDone': 'تم تحديث الكتالوج إلى الإصدار {version}.',
    'updateCatalogFailed': 'فشل التحديث: {error}',
    'catalogUpToDate': 'الكتالوج محدث بالفعل (الإصدار {version}).',
    'publishChanges': 'نشر التغييرات',
    'publishChangesHint': 'إرسال تغييرات الكتالوج المحلية إلى الخادم',
    'publishDoneTitle': 'تم نشر التغييرات',
    'publishDoneBody': 'إصدار الكتالوج {old} -> {new}.',
    'publishFailed': 'فشل النشر: {error}',
    'syncSettings': 'إعدادات المزامنة',
    'syncParameters': 'إعدادات المزامنة',
    'syncStatusChecking': 'جارٍ التحقق…',
    'syncStatusMissing': 'الرمز مفقود',
    'syncStatusUnconfigured': 'غير مهيّأ',
    'syncStatusOk': 'الرمز · الخادم يعمل',
    'syncStatusRejected': 'الرمز مرفوض',
    'syncStatusDown': 'الخادم غير متاح',
    'catalogDistribute': 'توزيع الكتالوج',
    'catalogAddProduct': 'إضافة منتج',
    'shopMenuExportListing': 'تصدير القائمة',
    'shopMenuExportHistory': 'تصدير السجل',
    'shopNotRegistered': 'غير مسجّل على الخادم',
    'shopNotRegisteredHint': 'المتجر يعمل دون اتصال. اضبط عنوان الخادم والرمز '
        'في إعدادات المزامنة ثم أعد إنشاءه.',
    'shopRegistered': 'مسجّل على الخادم',
    'catalogDeleteRowTitle': 'حذف المنتج؟',
    'catalogDeleteRowBody': 'إزالة « {name} » من الكتالوج؟',
    'shopCreatedRegistered': 'تم إنشاء المتجر "{key}" وتسجيله على الخادم.',
    'shopCreatedNotRegistered': 'تم إنشاء المتجر "{key}" — غير مسجّل على '
        'الخادم. يعمل دون اتصال.',
    'listingPushTarget': 'المتجر المستهدف: {key}',
  },
};

/// Resolve [key] for the current locale, substituting `{namedArgs}`.
String shopInfoTr(BuildContext context, String key,
    {Map<String, String>? namedArgs}) {
  final lang = context.locale.languageCode;
  final map = _strings[lang] ?? _strings['en']!;
  var value = map[key] ?? _strings['en']![key] ?? key;
  if (namedArgs != null) {
    namedArgs.forEach((name, arg) {
      value = value.replaceAll('{$name}', arg);
    });
  }
  return value;
}
