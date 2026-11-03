import 'package:flutter/material.dart';

import '../../core/app_config.dart';

/// Ảnh nằm trên chính server của app: /uploads/... (bài cộng đồng tải lên)
/// và /images/... (ảnh minh họa công thức hệ thống đi kèm server). Không tải ảnh từ trang ngoài.
String? uploadedImageUrl(String? imageUrl) =>
    imageUrl != null && (imageUrl.startsWith('/uploads/') || imageUrl.startsWith('/images/'))
        ? AppConfig.fileUrl(imageUrl)
        : null;

/// Ảnh món: ảnh tải lên nếu có, không thì biểu tượng mặc định. [width] null = giãn hết chiều ngang.
class RecipeImage extends StatelessWidget {
  const RecipeImage({super.key, required this.size, this.imageUrl, this.width});

  /// Chiều cao (và chiều rộng nếu [width] null)
  final double size;
  final double? width;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      color: scheme.primaryContainer,
      alignment: Alignment.center,
      child: Icon(Icons.ramen_dining, size: size * 0.5, color: scheme.onPrimaryContainer),
    );
    final url = uploadedImageUrl(imageUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: width ?? size,
        height: size,
        child: url == null
            ? placeholder
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : placeholder,
              ),
      ),
    );
  }
}
