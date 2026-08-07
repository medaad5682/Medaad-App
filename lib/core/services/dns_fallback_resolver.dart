import 'dart:io';
import 'dart:convert';

/// ✅ DNS Fallback مشترك لكل التطبيق
///
/// المشكلة: بعض مزودي الإنترنت/الراوترات بترفض حل بعض النطاقات الفرعية
/// المجانية (زي dpdns.org) بسبب سمعة النطاق الأساسي المشترك، حتى لو
/// الدومين الفرعي نفسه سليم 100%.
///
/// الحل: نجمع كل عناوين IP الممكنة للدومين من مصدرين — DNS العادي
/// بتاع الجهاز/الشبكة، و DNS-over-HTTPS (طلب HTTPS عادي، مش بروتوكول
/// DNS تقليدي) لسؤال Cloudflare ثم Google عن الـ IP الصحيح — وبعدين
/// نجرب الاتصال الفعلي بكل عنوان بالترتيب لحد ما واحد ينجح.
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
  /// الخطوة 1 (الأساسية): بالظبط زي الإصدار القديم 100% — بنمرر اسم
  /// الدومين كـ String عادي لـ Socket.startConnect، فـ Dart/نظام
  /// التشغيل هو اللي بيعمل الـ DNS lookup والاتصال زي ما كان بيحصل
  /// قبل أي تعديل، من غير أي استدعاء DoH ولا أي تأخير إضافي. لو
  /// الشبكة سليمة هيا دي اللي هتشتغل دايمًا.
  ///
  /// الخطوة 2 (الاحتياطية): تتفعّل بس لو الخطوة 1 فشلت (فشل فك رابط
  /// الدومين). بتجمع عناوين من DNS العادي + DoH وتجرب الاتصال الفعلي
  /// بكل عنوان بالترتيب لحد ما واحد ينجح فعلاً.
  static Future<ConnectionTask<Socket>> connectionFactory(
      Uri uri, String? proxyHost, int? proxyPort) async {
    // ✅ الخطوة 1: المحاولة الافتراضية بالظبط زي القديم.
    try {
      return await Socket.startConnect(uri.host, uri.port);
    } catch (e) {
      // ignore: avoid_print
      print('🚨 الاتصال الافتراضي (DNS العادي) فشل لـ ${uri.host}: $e — الانتقال للاحتياطي');
    }

    // ✅ الخطوة 2: لو وبس لو الطريقة العادية فشلت، ننتقل للاحتياطي.
    final candidates = await _collectCandidates(uri.host);

    if (candidates.isEmpty) {
      throw SocketException('تعذّر حل الدومين (DNS): ${uri.host}');
    }

    Object? lastError;
    for (final address in candidates) {
      try {
        // ⚠️ لازم نستنى .socket فعليًا هنا مش بس startConnect، لأن
        // startConnect بيرجع الـ task بمجرد ما يبدأ المحاولة، مش لما
        // الاتصال ينجح. لو ما استنيناش .socket، عنوان فاشل هيتحسب
        // "نجح" غلط ومش هنعدي للعنوان التالي.
        final task = await Socket.startConnect(address, uri.port);
        await task.socket.timeout(const Duration(seconds: 6));
        // ✅ الـ task.socket بقى متحلّ (resolved) خلاص بعد الـ await
        // فوق، فلما الـ HttpClient الداخلي يعمل await عليه تاني
        // (زي ما بيعمل عادي) هياخده فورًا من غير أي تكرار حقيقي للاتصال.
        return task;
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
