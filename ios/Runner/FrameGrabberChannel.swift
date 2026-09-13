import AVFoundation
import Flutter
import UIKit

/// ✅ [iOS Screenshot Fix] قناة استخراج الإطار الأصلي لميزة "لقطة الفيديو".
///
/// السياق الكامل موجود في تعليق `_captureCurrentFrame()` بملف
/// `native_video_player_screen.dart`، ملخّصه هنا:
///
/// على iOS يركّب `better_player_plus` الفيديو عبر `UiKitView` — أي
/// `FlutterPlatformView` حقيقي (`AVPlayerLayer` داخل `UIView` أصلي، راجع
/// `BetterPlayer.swift` من الحزمة نفسها: تُطابق `FlutterPlatformView`)
/// خارج شجرة رسم Flutter (Skia) تماماً. على أندرويد بالمقابل يُركَّب
/// الفيديو عبر `Texture` (OpenGL/SurfaceTexture) وهو جزء فعلي من تلك
/// الشجرة. لهذا السبب بالتحديد كانت `RenderRepaintBoundary.toImage()`
/// تلتقط العلامة المائية (ودجت Flutter عادي) بنجاح، بينما يخرج مكان
/// الفيديو أسود بالكامل على iOS فقط — هذا ليس عطلاً في التشفير/فك
/// التشفير، بل قيد معماري في Flutter نفسه (Platform Views غير مرئية
/// إطلاقاً لأي التقاط عبر `toImage()`، بصرف النظر عن محرك الرسم
/// Impeller/Skia).
///
/// لا يوجد أي وصول متاح لنا لمثيل `AVPlayer` الداخلي الذي تديره
/// `better_player_plus` (هو خاص بالكامل داخل البلجن)، لذا بدل تعديل/فرع
/// تلك الحزمة، نبني مصدراً مستقلاً تماماً: `AVURLAsset` جديد من نفس رابط
/// البث الحالي (بما فيها جودته المختارة حالياً) + نفس رؤوس HTTP
/// المستخدمة في Flutter، ثم نستخرج منه الإطار عند نفس لحظة التشغيل
/// الظاهرة على الشاشة عبر `AVAssetImageGenerator`. النتيجة PNG خام (بلا
/// أي علامة مائية) تُعاد لـ Flutter، حيث تُركَّب العلامة المائية عليه في
/// الذاكرة (Canvas) قبل التشفير المعتاد — راجع `_compositeWatermarkOnFrame`
/// و `VideoScreenshotService.saveEncrypted` في الطرف الآخر.
final class FrameGrabberChannel: NSObject {
    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "medaad.app.com/frame_grabber",
            binaryMessenger: messenger
        )
        super.init()

        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard call.method == "grabFrame" else {
            result(FlutterMethodNotImplemented)
            return
        }

        guard
            let args = call.arguments as? [String: Any],
            let urlString = args["url"] as? String,
            let url = URL(string: urlString)
        else {
            result(FlutterError(
                code: "BAD_ARGS",
                message: "Missing or invalid 'url' argument",
                details: nil
            ))
            return
        }

        let headers = (args["headers"] as? [String: Any])?
            .compactMapValues { $0 as? String } ?? [:]
        let positionMs = (args["positionMs"] as? NSNumber)?.int64Value ?? 0

        grabFrame(url: url, headers: headers, positionMs: positionMs, result: result)
    }

    private func grabFrame(
        url: URL,
        headers: [String: String],
        positionMs: Int64,
        result: @escaping FlutterResult
    ) {
        var assetOptions: [String: Any] = [:]
        if !headers.isEmpty {
            // ✅ نفس رؤوس HTTP (مثل User-Agent) التي يستخدمها
            // better_player_plus عبر Flutter، حتى لا يُرفض الطلب من طرف
            // الخادم أو الـ CDN أمام هذا المصدر المستقل.
            assetOptions[AVURLAssetHTTPHeaderFieldsKey] = headers
        }

        // ✅ مصدر مستقل تماماً عن مثيل AVPlayer الداخلي للبلجن — لا يشارك
        // أي حالة معه، فلا يمكن لهذا الاستخراج أن يؤثر على التشغيل الجاري.
        let asset = AVURLAsset(url: url, options: assetOptions)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true

        // ✅ سماحية نصف ثانية بدل صفر تماماً: تدفقات HLS غالباً لا تملك
        // إطاراً مفتاحياً (keyframe) عند كل نقطة زمنية بالضبط، وطلب إطار
        // مضبوط تماماً (tolerance = .zero) قد يبطئ الاستخراج كثيراً أو
        // يفشل بالكامل على بعض التدفقات. الفارق البصري لنصف ثانية على
        // لقطة ثابتة غير ملحوظ عملياً.
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        let time = CMTime(seconds: Double(positionMs) / 1000.0, preferredTimescale: 600)

        generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { _, cgImage, _, status, error in
            DispatchQueue.main.async {
                switch status {
                case .succeeded:
                    guard let cgImage = cgImage else {
                        result(FlutterError(
                            code: "NO_IMAGE",
                            message: "Generator succeeded but produced no image",
                            details: nil
                        ))
                        return
                    }

                    let uiImage = UIImage(cgImage: cgImage)
                    guard let pngData = uiImage.pngData() else {
                        result(FlutterError(
                            code: "ENCODE_FAILED",
                            message: "Failed to encode extracted frame to PNG",
                            details: nil
                        ))
                        return
                    }

                    result(FlutterStandardTypedData(bytes: pngData))

                case .failed, .cancelled:
                    let message = error?.localizedDescription ?? "Frame generation failed"
                    result(FlutterError(
                        code: "GENERATION_FAILED",
                        message: message,
                        details: nil
                    ))

                @unknown default:
                    result(FlutterError(
                        code: "UNKNOWN_STATUS",
                        message: "Unknown AVAssetImageGenerator status",
                        details: nil
                    ))
                }
            }
        }
    }
}
