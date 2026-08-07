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
  /// يجمع كل العناوين المتاحة من DNS العادي + DoH (مش عنوان واحد بس)،
  /// عشان لو الاتصال بأول عنوان فشل، يكون فيه بدائل جاهزة نجرّبها.
  static Future<List<InternetAddress>> _collectCandidates(String host) async {
    final List<InternetAddress> candidates = [];

    // المحاولة 1: DNS العادي بتاع الجهاز/الشبكة (كل العناوين، مش أول واحد)
    try {
      final addresses =
          await InternetAddress.lookup(host).timeout(const Duration(seconds: 3));
      candidates.addAll(addresses);
    } catch (e) {
      // ignore: avoid_print
      print('🚨 DNS العادي فشل لـ $host: $e');
    }

    // المحاولة 2: DNS-over-HTTPS — دايمًا نضيفها كبدائل احتياطية، حتى لو
    // نجح DNS العادي، عشان نضمن وجود مرشحين تانيين لو أول عنوان فشل اتصاله
    try {
      final dohAddresses = await _resolveViaDoH(host);
      for (final addr in dohAddresses) {
        if (!candidates.any((c) => c.address == addr.address)) {
          candidates.add(addr);
        }
      }
    } catch (_) {
      // تجاهل - عندنا بالفعل نتائج DNS العادي (لو نجحت)
    }

    return candidates;
  }

  static Future<List<InternetAddress>> _resolveViaDoH(String host) async {
    final dohClient = HttpClient();
    dohClient.connectionTimeout = const Duration(seconds: 4);

    Future<List<InternetAddress>> query(String dohUrl) async {
      final List<InternetAddress> found = [];
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
              found.add(InternetAddress(a['data'] as String));
            }
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('🚨 DoH query فشل ($dohUrl) لـ $host: $e');
      }
      return found;
    }

    try {
      // 1) Cloudflare أولاً
      var results = await query('https://cloudflare-dns.com/dns-query');
      // 2) Google كخط دفاع ثاني لو Cloudflare نفسه محجوب على شبكة المستخدم
      if (results.isEmpty) {
        results = await query('https://dns.google/resolve');
      }
      return results;
    } finally {
      dohClient.close(force: true);
    }
  }

  /// خطاف جاهز للاستخدام مباشرة كـ HttpClient.connectionFactory:
  ///   client.connectionFactory = DnsFallbackResolver.connectionFactory;
  ///
  /// الفرق الجوهري عن النسخة القديمة: بيجرّب **كل** العناوين المتاحة
  /// (من DNS العادي و DoH) بالترتيب، والاتصال الفعلي نفسه (مش بس
  /// الـ DNS lookup) ملفوف بـ try/catch. لو عنوان معين رفض الاتصال
  /// (IPv6 معطّل، فايروول، إلخ)، ننتقل للعنوان التالي تلقائيًا بدل
  /// ما نفشل فورًا.
  static Future<ConnectionTask<Socket>> connectionFactory(
      Uri uri, String? proxyHost, int? proxyPort) async {
    // ✅ الخطوة 1: المحاولة الافتراضية بالظبط زي الإصدار القديم —
    // بنمرر اسم الدومين كـ String عادي، فـ Dart/نظام التشغيل هو اللي
    // بيعمل الـ DNS lookup والاتصال زي ما كان بيحصل قبل أي تعديل.
    // لو الشبكة سليمة (زي شبكتك) هيا دي اللي هتشتغل دايمًا، ومفيش أي
    // استدعاء إضافي لـ DoH أو تأخير زيادة.
    try {
      return await Socket.startConnect(uri.host, uri.port);
    } catch (e) {
      // ignore: avoid_print
      print('🚨 الاتصال الافتراضي (DNS العادي) فشل لـ ${uri.host}: $e — الانتقال للاحتياطي');
    }

    // ✅ الخطوة 2: لو وبس لو الطريقة العادية فشلت (فشل فك الرابط لـ IP)،
    // ننتقل للمنطق الاحتياطي: DNS يدوي + DNS-over-HTTPS.
    final candidates = await _collectCandidates(uri.host);

    if (candidates.isEmpty) {
      throw SocketException('تعذّر حل الدومين (DNS): ${uri.host}');
    }

    Object? lastError;
    for (final address in candidates) {
      try {
        return await Socket.startConnect(address, uri.port)
            .timeout(const Duration(seconds: 6));
      } catch (e) {
        lastError = e;
        // ignore: avoid_print
        print('🚨 فشل الاتصال بـ ${address.address} لـ ${uri.host}: $e — تجربة التالي');
        continue;
      }
    }

    throw SocketException(
        'تعذّر الاتصال بأي عنوان متاح لـ ${uri.host}: $lastError');
  }
}
