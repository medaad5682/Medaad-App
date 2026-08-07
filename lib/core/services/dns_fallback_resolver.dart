import 'dart:io';
import 'dart:convert';

/// ✅ DNS Fallback مشترك لكل التطبيق
///
/// المشكلة: بعض مزودي الإنترنت/الراوترات بترفض حل بعض النطاقات الفرعية
/// المجانية (زي dpdns.org) بسبب سمعة النطاق الأساسي المشترك، حتى لو
/// الدومين الفرعي نفسه سليم 100%.
///
/// الحل: لو فشل DNS العادي بتاع الجهاز/الشبكة، نستخدم DNS-over-HTTPS
/// (طلب HTTPS عادي، مش بروتوكول DNS تقليدي) لنسأل Cloudflare ثم Google
/// عن الـ IP الصحيح. طلب HTTPS العادي ده بيعدي من أي فلترة بتستهدف
/// بروتوكول DNS بس.
///
/// ملاحظة أمان: الدالة دي بترجع IP فقط لغرض فتح الـ Socket. اسم الدومين
/// الأصلي (uri.host) بيفضل هو المستخدم في TLS SNI والتحقق من الشهادة
/// (بما فيها Certificate Pinning لو مفعّل)، فمفيش أي تأثير على الأمان.
class DnsFallbackResolver {
  /// يحاول DNS العادي أولاً، ولو فشل يستخدم DoH (Cloudflare ثم Google).
  static Future<InternetAddress?> resolve(String host) async {
    // المحاولة 1: DNS العادي بتاع الجهاز/الشبكة
    try {
      final addresses = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      if (addresses.isNotEmpty) return addresses.first;
    } catch (_) {
      // فشل - ننتقل لـ DoH تحت
    }

    // المحاولة 2: DNS-over-HTTPS
    return _resolveViaDoH(host);
  }

  static Future<InternetAddress?> _resolveViaDoH(String host) async {
    final dohClient = HttpClient();
    dohClient.connectionTimeout = const Duration(seconds: 4);

    Future<InternetAddress?> query(String dohUrl) async {
      try {
        final uri = Uri.parse('$dohUrl?name=$host&type=A');
        final request = await dohClient.getUrl(uri);
        request.headers.set('Accept', 'application/dns-json');
        final response =
            await request.close().timeout(const Duration(seconds: 4));
        final body = await response.transform(utf8.decoder).join();
        final Map<String, dynamic> data = jsonDecode(body);
        final answers = data['Answer'] as List?;
        if (answers != null) {
          for (final a in answers) {
            if (a['type'] == 1) {
              // A record = IPv4
              return InternetAddress(a['data'] as String);
            }
          }
        }
      } catch (_) {
        // فشل هذا المزود، جرّب التالي
      }
      return null;
    }

    try {
      // 1) Cloudflare أولاً
      var result = await query('https://cloudflare-dns.com/dns-query');
      // 2) Google كخط دفاع ثاني لو Cloudflare نفسه محجوب على شبكة المستخدم
      result ??= await query('https://dns.google/resolve');
      return result;
    } finally {
      dohClient.close(force: true);
    }
  }

  /// خطاف جاهز للاستخدام مباشرة كـ HttpClient.connectionFactory:
  ///   client.connectionFactory = DnsFallbackResolver.connectionFactory;
  static Future<ConnectionTask<Socket>> connectionFactory(
      Uri uri, String? proxyHost, int? proxyPort) async {
    final target = await resolve(uri.host);
    if (target == null) {
      throw SocketException('تعذّر حل الدومين (DNS): ${uri.host}');
    }
    return Socket.startConnect(target, uri.port);
  }
}
