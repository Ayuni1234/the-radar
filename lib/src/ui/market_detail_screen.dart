import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market.dart';
import '../pi/pi_service.dart' show PiPaymentPhase;
import '../state/market_providers.dart';
import 'radar_theme.dart';

String _fmtPi(double v) =>
    v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

/// Gear detail view: photos, specs, condition and the merchant shop —
/// with the native Pi checkout button driving the fee-split flow.
class MarketDetailScreen extends ConsumerStatefulWidget {
  const MarketDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  ConsumerState<MarketDetailScreen> createState() =>
      _MarketDetailScreenState();
}

class _MarketDetailScreenState extends ConsumerState<MarketDetailScreen> {
  int _photoIndex = 0;

  @override
  Widget build(BuildContext context) {
    final listings = ref.watch(marketListingsProvider).value ?? const [];
    final shops = ref.watch(marketShopsProvider).value ?? const [];
    MarketListing? listing;
    for (final l in listings) {
      if (l.id == widget.listingId) listing = l;
    }
    final shop = listing == null
        ? null
        : shops.where((s) => s.id == listing!.shopId).firstOrNull;
    final checkout = ref.watch(marketCheckoutProvider);

    // Removed from the feed (sold out / deactivated) while viewing.
    if (listing == null) {
      return Scaffold(
        backgroundColor: RadarTheme.ink,
        appBar: AppBar(title: const Text('Gear detail')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inventory_2_outlined,
                  size: 44, color: RadarTheme.textDim),
              const SizedBox(height: 12),
              const Text('This listing is no longer available',
                  style: TextStyle(color: RadarTheme.textDim)),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Back to the market'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(title: Text(shop?.shopName ?? 'Gear detail')),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Gallery(
                    listing: listing,
                    index: _photoIndex,
                    onIndex: (i) => setState(() => _photoIndex = i)),
                const SizedBox(height: 16),
                _SpecsCard(listing: listing),
                const SizedBox(height: 14),
                if (shop != null) _ShopCard(shop: shop),
                const SizedBox(height: 14),
                const _FeeSplitExplainer(),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: _CheckoutBar(listing: listing, checkout: checkout),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- gallery

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.listing,
    required this.index,
    required this.onIndex,
  });

  final MarketListing listing;
  final int index;
  final ValueChanged<int> onIndex;

  @override
  Widget build(BuildContext context) {
    final urls = listing.mediaUrls;
    return Column(children: [
      Container(
        height: 220,
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: RadarTheme.stroke),
        ),
        child: urls.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.photo_camera_outlined,
                        size: 40, color: RadarTheme.textDim),
                    const SizedBox(height: 8),
                    Text(marketCategoryLabel(listing.category),
                        style: const TextStyle(color: RadarTheme.textDim)),
                  ],
                ),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: PageView.builder(
                  itemCount: urls.length,
                  onPageChanged: onIndex,
                  itemBuilder: (context, i) => Image.network(
                    urls[i],
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Center(
                      child: Icon(Icons.broken_image_outlined,
                          size: 40, color: RadarTheme.textDim),
                    ),
                  ),
                ),
              ),
      ),
      if (urls.length > 1) ...[
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < urls.length; i++)
              Container(
                width: i == index ? 18 : 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: i == index
                      ? RadarTheme.pi
                      : RadarTheme.stroke,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
          ],
        ),
      ],
    ]);
  }
}

// ------------------------------------------------------------------ specs

class _SpecsCard extends StatelessWidget {
  const _SpecsCard({required this.listing});

  final MarketListing listing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(listing.title,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: RadarTheme.textPrimary)),
            ),
            Text('${_fmtPi(listing.pricePi)} π',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: RadarTheme.pi)),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _pill(Icons.category_outlined,
                marketCategoryLabel(listing.category), RadarTheme.info),
            _pill(Icons.grade_outlined, marketConditionLabel(listing.condition),
                RadarTheme.radar),
            _pill(
                Icons.inventory_outlined,
                listing.inStock
                    ? (listing.stockQuantity > 1
                        ? '${listing.stockQuantity} units available'
                        : 'Last unit available')
                    : 'Out of stock',
                listing.inStock
                    ? (listing.stockQuantity > 1
                        ? RadarTheme.textDim
                        : RadarTheme.gold)
                    : RadarTheme.alert),
          ]),
        ],
      ),
    );
  }

  Widget _pill(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

// --------------------------------------------------------------- shop card

class _ShopCard extends StatelessWidget {
  const _ShopCard({required this.shop});

  final MarketShop shop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: RadarTheme.pi.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.storefront, color: RadarTheme.pi, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(shop.shopName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                if (shop.isVerified) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.verified, size: 15, color: RadarTheme.radar),
                ],
              ]),
              const SizedBox(height: 2),
              Text('Pickup area: ${shop.locationArea}',
                  style:
                      const TextStyle(color: RadarTheme.textDim, fontSize: 12)),
              if (shop.description != null) ...[
                const SizedBox(height: 4),
                Text(shop.description!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: RadarTheme.textDim,
                        fontSize: 11.5,
                        height: 1.4)),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------ fee split explainer

class _FeeSplitExplainer extends StatelessWidget {
  const _FeeSplitExplainer();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.call_split, size: 16, color: RadarTheme.info),
          const SizedBox(width: 8),
          const Text('How your Pi is routed',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Your payment goes to the merchant\u2019s verified Pi wallet in a '
          'single transaction — the platform automatically captures a small '
          'maintenance fee to cover hosting, escrow reviews and support. '
          'The split is executed server-side on the Pi Platform API; the '
          'app never touches your passphrase.',
          style: TextStyle(
              color: RadarTheme.textDim, fontSize: 12, height: 1.5),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------ checkout bar

class _CheckoutBar extends ConsumerWidget {
  const _CheckoutBar({required this.listing, required this.checkout});

  final MarketListing listing;
  final MarketCheckoutState checkout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canBuy = listing.inStock && !checkout.busy;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: BoxDecoration(
        color: RadarTheme.ink.withValues(alpha: 0.97),
        border: const Border(top: BorderSide(color: RadarTheme.stroke)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (checkout.message != null &&
                (checkout.phase == PiPaymentPhase.completed ||
                    checkout.phase == PiPaymentPhase.error ||
                    checkout.phase == PiPaymentPhase.cancelled))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Icon(
                    checkout.phase == PiPaymentPhase.completed
                        ? Icons.check_circle
                        : Icons.error_outline,
                    size: 16,
                    color: checkout.phase == PiPaymentPhase.completed
                        ? RadarTheme.radar
                        : RadarTheme.alert,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(checkout.message!,
                        style: const TextStyle(fontSize: 12, height: 1.35)),
                  ),
                ]),
              ),
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_fmtPi(listing.pricePi)} π',
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: RadarTheme.pi)),
                    Text(
                      checkout.busy
                          ? _busyLabel(checkout.phase)
                          : listing.inStock
                              ? 'Paid to the merchant via Pi'
                              : 'Out of stock',
                      style: const TextStyle(
                          fontSize: 11, color: RadarTheme.textDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: RadarTheme.pi,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                ),
                onPressed: canBuy
                    ? () =>
                        ref.read(marketCheckoutProvider.notifier).buy(listing)
                    : null,
                icon: checkout.busy
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.currency_exchange, size: 17),
                label: Text(
                  checkout.busy ? 'Processing…' : 'Buy with Pi',
                  style: const TextStyle(fontSize: 13.5),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String _busyLabel(PiPaymentPhase phase) => switch (phase) {
        PiPaymentPhase.awaitingUser => 'Confirm in your Pi wallet',
        PiPaymentPhase.readyForApproval => 'Verifying payment…',
        PiPaymentPhase.readyForCompletion => 'Waiting for blockchain…',
        PiPaymentPhase.completing => 'Splitting fee & paying merchant…',
        _ => 'Processing…',
      };
}
