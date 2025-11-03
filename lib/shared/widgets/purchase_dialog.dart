// lib/shared/widgets/purchase_dialog.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/purchase_service.dart';
import '../../core/theme/space_theme.dart';
import '../../generated/l10n.dart';
import '../../shared/utils/app_utilities.dart';

class PurchaseDialog extends StatelessWidget {
  const PurchaseDialog({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch the PurchaseService for real-time updates
    final purchaseService = context.watch<PurchaseService>();
    final s = S.of(context)!;

    return SpaceDialog(
      title: s.purchaseTitle,
      customContent: _buildDialogContent(context, purchaseService, s),
      actions: _buildDialogActions(context, purchaseService, s),
    );
  }

  Widget _buildDialogContent(BuildContext context, PurchaseService service, S s) {
    if (!service.isAvailable) {
      return _buildErrorContent(s.storeUnavailable);
    }
    if (service.errorMessage != null) {
      return _buildErrorContent(service.errorMessage!);
    }
    if (service.product == null) {
      return _buildLoadingContent(s.contactingStore);
    }
    return Text(s.purchaseDescription, style: SpaceTheme.bodyStyle, textAlign: TextAlign.center);
  }
  
  List<Widget> _buildDialogActions(BuildContext context, PurchaseService service, S s) {
    if (!service.isAvailable || service.errorMessage != null) {
      return [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(s.cancel))];
    }
    if (service.product == null || service.purchasePending) {
      return [const CircularProgressIndicator()];
    }

    return [
      TextButton(
        onPressed: service.restorePurchases,
        child: Text(s.restorePurchases, style: const TextStyle(color: SpaceTheme.moonSilver)),
      ),
      ElevatedButton(
        onPressed: service.buyProduct,
        style: SpaceTheme.primaryButtonStyle.copyWith(
          backgroundColor: MaterialStateProperty.all(SpaceTheme.alienGreen),
        ),
        child: Text("${s.purchaseButton} (${service.product!.price})"),
      ),
    ];
  }

  Widget _buildLoadingContent(String message) {
    return Column(children: [
      const CircularProgressIndicator(),
      const SizedBox(height: 16),
      Text(message, style: SpaceTheme.bodyStyle),
    ]);
  }

  Widget _buildErrorContent(String message) {
    return Column(children: [
      const Icon(Icons.error, color: SpaceTheme.rocketRed, size: 48),
      const SizedBox(height: 16),
      Text(message, style: SpaceTheme.bodyStyle, textAlign: TextAlign.center),
    ]);
  }
}