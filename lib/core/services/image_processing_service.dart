// lib/core/services/image_processing_service.dart
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class ImageProcessingService {
  /// Processes an image from assets to be used in the puzzle.
  ///
  /// This function performs three key operations:
  /// 1. Loads the image from the specified asset path.
  /// 2. Checks the image brightness and increases it if it's too dark.
  /// 3. Crops the image to perfectly fit the target size's aspect ratio,
  /// simulating BoxFit.cover to prevent any black borders.
  Future<ui.Image> processImageForPuzzle({
    required String imagePath,
    required Size targetSize,
    double brightnessThreshold = 0.35, // Adjust this value based on testing (0.0=black, 1.0=white)
  }) async {
    log("🖼️ PROCESSING IMAGE: $imagePath", name: "ImageProcessing");
    log("   Target Size: ${targetSize.width.toStringAsFixed(1)} x ${targetSize.height.toStringAsFixed(1)}", name: "ImageProcessing");
    log("   Brightness Threshold: $brightnessThreshold", name: "ImageProcessing");

    // 1. Load image bytes from assets
    log("📥 Loading image bytes from assets...", name: "ImageProcessing.Loading");
    final ByteData data = await rootBundle.load(imagePath);
    final Uint8List bytes = data.buffer.asUint8List();
    log("   Loaded ${bytes.length} bytes", name: "ImageProcessing.Loading");

    // 2. Decode, check brightness, and adjust if necessary using the 'image' package
    log("🔍 Decoding and analyzing image...", name: "ImageProcessing.Analysis");
    img.Image? originalImage = img.decodeImage(bytes);
    if (originalImage == null) {
      log("❌ FAILED to decode image: $imagePath", name: "ImageProcessing.Error");
      throw Exception('Could not decode image: $imagePath');
    }
    
    log("   Original Image Dimensions: ${originalImage.width} x ${originalImage.height}", name: "ImageProcessing.Analysis");
    log("   Original Image Format: ${originalImage.format}", name: "ImageProcessing.Analysis");
    log("   Original Image Channels: ${originalImage.numChannels}", name: "ImageProcessing.Analysis");

    bool wasBrightnessAdjusted = false;
    if (_isTooDark(originalImage, brightnessThreshold)) {
      log("🌞 Image is too dark. Adjusting brightness...", name: "ImageProcessing.Enhancement");
      originalImage = img.adjustColor(originalImage, brightness: 1.5); // Increase brightness by 50%
      wasBrightnessAdjusted = true;
      log("   ✅ Brightness increased by 50%", name: "ImageProcessing.Enhancement");
    } else {
      log("✅ Image brightness is acceptable", name: "ImageProcessing.Enhancement");
    }

    // Encode back to Uint8List to be decoded by Flutter's engine
    log("📦 Re-encoding image...", name: "ImageProcessing.Encoding");
    final Uint8List processedBytes = Uint8List.fromList(img.encodePng(originalImage));
    log("   Processed image size: ${processedBytes.length} bytes", name: "ImageProcessing.Encoding");

    // 3. Decode for Flutter and crop to fit the target aspect ratio
    log("🎭 Converting to Flutter UI Image...", name: "ImageProcessing.FlutterConversion");
    final ui.Image flutterImage = await _decodeImageFromList(processedBytes);
    log("   Flutter Image Dimensions: ${flutterImage.width} x ${flutterImage.height}", name: "ImageProcessing.FlutterConversion");

    log("✂️ Cropping image to fit target aspect ratio...", name: "ImageProcessing.Cropping");
    final ui.Image finalImage = await _cropImageToFit(flutterImage, targetSize);
    log("   Final Image Dimensions: ${finalImage.width} x ${finalImage.height}", name: "ImageProcessing.Cropping");
    
    log("🎯 IMAGE PROCESSING COMPLETE:", name: "ImageProcessing.Summary");
    log("   Input: $imagePath (${originalImage.width}x${originalImage.height})", name: "ImageProcessing.Summary");
    log("   Output: ${finalImage.width}x${finalImage.height}", name: "ImageProcessing.Summary");
    log("   Brightness Adjusted: ${wasBrightnessAdjusted ? 'YES' : 'NO'}", name: "ImageProcessing.Summary");
    log("   Processing Steps: Load → Decode → ${wasBrightnessAdjusted ? 'Enhance → ' : ''}Encode → FlutterConvert → Crop", name: "ImageProcessing.Summary");

    return finalImage;
  }

  /// Checks if an image's average brightness is below a threshold.
  bool _isTooDark(img.Image image, double threshold) {
    log("🔬 Analyzing image brightness...", name: "ImageProcessing.BrightnessCheck");
    
    double totalLuminance = 0;
    int pixelCount = image.width * image.height;
    
    // Using a smaller sample for performance on large images
    int step = (pixelCount > 100000) ? 10 : 1;
    int samples = 0;
    
    log("   Total pixels: $pixelCount", name: "ImageProcessing.BrightnessCheck");
    log("   Sampling step: $step", name: "ImageProcessing.BrightnessCheck");

    final stopwatch = Stopwatch()..start();
    
    for (int y = 0; y < image.height; y += step) {
      for (int x = 0; x < image.width; x += step) {
        img.Pixel pixel = image.getPixel(x, y);
        // Using standard luminance formula
        totalLuminance += (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255.0;
        samples++;
      }
    }
    
    stopwatch.stop();
    double avgLuminance = totalLuminance / samples;
    bool isToDark = avgLuminance < threshold;
    
    log("   Samples analyzed: $samples", name: "ImageProcessing.BrightnessCheck");
    log("   Analysis time: ${stopwatch.elapsedMilliseconds}ms", name: "ImageProcessing.BrightnessCheck");
    log("   Average luminance: ${avgLuminance.toStringAsFixed(3)} (0.0=black, 1.0=white)", name: "ImageProcessing.BrightnessCheck");
    log("   Threshold: ${threshold.toStringAsFixed(3)}", name: "ImageProcessing.BrightnessCheck");
    log("   Result: ${isToDark ? 'TOO DARK' : 'ACCEPTABLE'}", name: "ImageProcessing.BrightnessCheck");
    
    return isToDark;
  }

  /// Crops the [ui.Image] to match the [targetSize] aspect ratio (BoxFit.cover).
  Future<ui.Image> _cropImageToFit(ui.Image image, Size targetSize) async {
    log("✂️ Cropping image with BoxFit.cover logic...", name: "ImageProcessing.Cropping");
    
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final srcSize = Size(image.width.toDouble(), image.height.toDouble());
    
    log("   Source size: ${srcSize.width.toStringAsFixed(1)} x ${srcSize.height.toStringAsFixed(1)}", name: "ImageProcessing.Cropping");
    log("   Target size: ${targetSize.width.toStringAsFixed(1)} x ${targetSize.height.toStringAsFixed(1)}", name: "ImageProcessing.Cropping");
    
    // Apply BoxFit.cover logic
    final FittedSizes fittedSizes = applyBoxFit(BoxFit.cover, srcSize, targetSize);
    final Rect sourceRect = Alignment.center.inscribe(fittedSizes.source, Offset.zero & srcSize);
    final Rect destRect = Alignment.center.inscribe(fittedSizes.destination, Offset.zero & targetSize);
    
    log("   Source rect: ${sourceRect.left.toStringAsFixed(1)}, ${sourceRect.top.toStringAsFixed(1)}, ${sourceRect.width.toStringAsFixed(1)}x${sourceRect.height.toStringAsFixed(1)}", name: "ImageProcessing.Cropping");
    log("   Dest rect: ${destRect.left.toStringAsFixed(1)}, ${destRect.top.toStringAsFixed(1)}, ${destRect.width.toStringAsFixed(1)}x${destRect.height.toStringAsFixed(1)}", name: "ImageProcessing.Cropping");
    log("   Fitted source size: ${fittedSizes.source.width.toStringAsFixed(1)}x${fittedSizes.source.height.toStringAsFixed(1)}", name: "ImageProcessing.Cropping");
    log("   Fitted destination size: ${fittedSizes.destination.width.toStringAsFixed(1)}x${fittedSizes.destination.height.toStringAsFixed(1)}", name: "ImageProcessing.Cropping");

    canvas.drawImageRect(image, sourceRect, destRect, Paint());
    
    final stopwatch = Stopwatch()..start();
    final croppedImage = await recorder.endRecording().toImage(
      targetSize.width.toInt(),
      targetSize.height.toInt(),
    );
    stopwatch.stop();
    
    log("   Cropping completed in ${stopwatch.elapsedMilliseconds}ms", name: "ImageProcessing.Cropping");
    log("   Final cropped size: ${croppedImage.width}x${croppedImage.height}", name: "ImageProcessing.Cropping");
    
    return croppedImage;
  }

  /// Helper to decode Uint8List into a ui.Image.
  Future<ui.Image> _decodeImageFromList(Uint8List list) {
    log("🔄 Decoding bytes to UI Image (${list.length} bytes)...", name: "ImageProcessing.Decode");
    final completer = Completer<ui.Image>();
    final stopwatch = Stopwatch()..start();
    
    ui.decodeImageFromList(list, (ui.Image img) {
      stopwatch.stop();
      log("   ✅ UI Image decoded in ${stopwatch.elapsedMilliseconds}ms: ${img.width}x${img.height}", name: "ImageProcessing.Decode");
      completer.complete(img);
    });
    
    return completer.future;
  }
}