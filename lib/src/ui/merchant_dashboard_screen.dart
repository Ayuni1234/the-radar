import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market.dart';
import '../models/market_sales.dart';
import '../state/market_providers.dart';
import 'radar_theme.dart';
import 'sheet_scaffold.dart';
import 'shell.dart';

/// Merchant Dashboard — register a shop, publish gear with Pi pricing and
/// track inventory. Sellers are paid via A2U to the `pi_uid` on file; the
/// platform captures its maintenance fee automatically at checkout.
class MerchantDashboardScreen extends ConsumerWidget {
  const MerchantDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shopAsync = ref.watch(myMarketShopProvider);
    final shop = shopAsync.value;

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.store_mall_directory_outlined,
              color: RadarTheme.pi, size: 21),
          const SizedBox(width: 8),
          // Expanded: the middle toolbar slot can be well under 340px on
          // narrow screens — the title ellipsizes instead of overflowing.
          const Expanded(
            child: Text('Merchant dashboard',
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ]),
      ),
      body: shopAsync.isLoading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.4))
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (shop == null) ...[
                    const _RegisterShopCard(),
                    const SizedBox(height: 20),
                    const _SellWithUsCard(),
                  ]                  else ...[
                    _ShopHeader(shop: shop),
                    const SizedBox(height: 16),
                    const _SalesSummaryCard(),
                    const SizedBox(height: 16),
                    SectionHeader(
                      'Inventory',
                      trailing: IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () =>
                            ref.read(myListingsProvider.notifier).refresh(),
                      ),
                    ),
                    _InventoryList(shopId: shop.id),
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
    );
  }
}

// --------------------------------------------------------- register shop

class _RegisterShopCard extends ConsumerStatefulWidget {
  const _RegisterShopCard();

  @override
  ConsumerState<_RegisterShopCard> createState() => _RegisterShopCardState();
}

class _RegisterShopCardState extends ConsumerState<_RegisterShopCard> {
  final _nameCtrl = TextEditingController();
  final _uidCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _uidCtrl.dispose();
    _areaCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await ref.read(myMarketShopProvider.notifier).saveShop(
          shopName: _nameCtrl.text,
          piUid: _uidCtrl.text,
          locationArea: _areaCtrl.text,
          description: _descCtrl.text,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.panelHigh,
        content: Text('Shop registered — you can publish gear now.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.pi.withValues(alpha: 0.4)),
      ),
      child: Form(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Icon(Icons.storefront, color: RadarTheme.pi, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Register your shop',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
              ),
            ]),
            const SizedBox(height: 6),
            const Text(
              'Open a storefront on The PitchMarket. Payouts go straight to '
              'the Pi wallet you register here.',
              style: TextStyle(color: RadarTheme.textDim, fontSize: 12.5,
                  height: 1.45),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Shop name',
                hintText: 'e.g. “Accra Creator Depot”',
                prefixIcon: Icon(Icons.badge_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _uidCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Your verified Pi uid (payout destination)',
                hintText: 'Pi username-uid from your Pi profile',
                prefixIcon: Icon(Icons.currency_bitcoin, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _areaCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Pickup / delivery area',
                hintText: 'e.g. “Accra — Osu”',
                prefixIcon: Icon(Icons.place_outlined, size: 20),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              maxLines: 3,
              minLines: 2,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'About your shop (optional)',
                hintText: 'What you sell, delivery promise, testing policy…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: RadarTheme.alert, fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: RadarTheme.pi,
                foregroundColor: Colors.white,
              ),
              onPressed: _busy ? null : _submit,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: const Text('Register shop'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellWithUsCard extends StatelessWidget {
  const _SellWithUsCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.call_split, size: 16, color: RadarTheme.info),
          const SizedBox(width: 8),
          const Text('How payouts work',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
        ]),
        const SizedBox(height: 8),
        const Text(
          '1 · A buyer pays your full asking price with Pi.\n'
          '2 · The platform routes the core amount to your verified pi_uid '
          'as an instant App-to-User payout.\n'
          '3 · A small maintenance fee is captured for the platform treasury '
          '— no invoices, no chasing payments.',
          style: TextStyle(color: RadarTheme.textDim, fontSize: 12,
              height: 1.55),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------- sales summary

class _SalesSummaryCard extends ConsumerStatefulWidget {
  const _SalesSummaryCard();

  @override
  ConsumerState<_SalesSummaryCard> createState() => _SalesSummaryCardState();
}

class _SalesSummaryCardState extends ConsumerState<_SalesSummaryCard> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
        () => ref.read(mySalesSummaryProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(mySalesSummaryProvider);
    final s = summary.value ??
        MarketSalesSummary.of(const <MarketSale>[]);
    final pct = (s.effectiveFeeRate * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.point_of_sale, size: 17, color: RadarTheme.radar),
          const SizedBox(width: 8),
          const Expanded(
            child: Text('Sales summary',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
          ),
          if (summary.isLoading)
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton(
              tooltip: 'Refresh',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.refresh, size: 17),
              onPressed: () =>
                  ref.read(mySalesSummaryProvider.notifier).refresh(),
            ),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Rebuilt from your settled A2U payout receipts — gross is what '
          'buyers paid, fees are the platform maintenance cut.',
          style: TextStyle(fontSize: 12, color: RadarTheme.textDim, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: _SalesStat(
                value: '${s.unitsSold}',
                label: 'unit${s.unitsSold == 1 ? '' : 's'} sold'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SalesStat(
                value: '${s.grossPi.toStringAsFixed(2)} π',
                label: 'gross earned',
                accent: RadarTheme.gold),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SalesStat(
                value: '${s.feesPi.toStringAsFixed(2)} π',
                label: 'fees paid ($pct%)'),
          ),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: RadarTheme.panelHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: RadarTheme.stroke),
          ),
          child: Row(children: [
            const Icon(Icons.account_balance_wallet,
                size: 15, color: RadarTheme.pi),
            const SizedBox(width: 8),
            Text('Net to wallet: ${s.netPi.toStringAsFixed(2)} π',
                style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: RadarTheme.pi)),
            const Spacer(),
            Text(
              s.sales.isEmpty
                  ? 'No sales yet'
                  : 'from ${s.sales.length} payout receipt${s.sales.length == 1 ? '' : 's'}',
              style: const TextStyle(
                  fontSize: 10.5, color: RadarTheme.textDim),
            ),
          ]),
        ),
        if (s.sales.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final sale in s.sales.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                const Icon(Icons.sell_outlined,
                    size: 14, color: RadarTheme.radar),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${sale.listingTitle}  ·  '
                    '${sale.netAmountPi.toStringAsFixed(2)} π net',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5, color: RadarTheme.textDim),
                  ),
                ),
              ]),
            ),
          if (s.sales.length > 3)
            Text('+${s.sales.length - 3} more in the full payout ledger',
                style: const TextStyle(
                    fontSize: 10.5, color: RadarTheme.textDim,
                    fontStyle: FontStyle.italic)),
        ],
      ]),
    );
  }
}

class _SalesStat extends StatelessWidget {
  const _SalesStat({
    required this.value,
    required this.label,
    this.accent = RadarTheme.pi,
  });

  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 14.5, color: accent)),
        const SizedBox(height: 2),
        Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                const TextStyle(fontSize: 10, color: RadarTheme.textDim)),
      ]),
    );
  }
}

// ------------------------------------------------------------ shop header

class _ShopHeader extends ConsumerWidget {
  const _ShopHeader({required this.shop});

  final MarketShop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(myListingsProvider).value ?? const [];
    final active = listings.where((l) => l.isActive).length;
    final units =
        listings.fold<int>(0, (sum, l) => sum + l.stockQuantity);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
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
                            fontWeight: FontWeight.w800, fontSize: 15.5)),
                  ),
                  if (shop.isVerified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified,
                        size: 16, color: RadarTheme.radar),
                  ],
                ]),
                Text('Payouts → ${shop.piUid} · ${shop.locationArea}',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: RadarTheme.textDim, fontSize: 11.5)),
              ],
            ),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          _stat('${listings.length}', 'listings'),
          const SizedBox(width: 10),
          _stat('$active', 'active'),
          const SizedBox(width: 10),
          _stat('$units', 'units in stock'),
          const Spacer(),
          Text('Fee 5%',
              style: TextStyle(
                  fontSize: 11.5,
                  color: RadarTheme.textDim,
                  fontStyle: FontStyle.italic)),
        ]),
      ]),
    );
  }

  Widget _stat(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: RadarTheme.panelHigh,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: RadarTheme.stroke),
        ),
        child: Column(children: [
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: RadarTheme.pi)),
          Text(label,
              style: const TextStyle(fontSize: 10.5, color: RadarTheme.textDim)),
        ]),
      );
}

// ------------------------------------------------------------- inventory

class _InventoryList extends ConsumerWidget {
  const _InventoryList({required this.shopId});

  final String shopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listings = ref.watch(myListingsProvider).value ?? const [];
    if (listings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: RadarTheme.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: RadarTheme.stroke),
        ),
        child: Column(children: [
          const Icon(Icons.inventory_2_outlined,
              size: 40, color: RadarTheme.textDim),
          const SizedBox(height: 10),
          const Text('No gear listed yet',
              style: TextStyle(color: RadarTheme.textDim)),
          const SizedBox(height: 14),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: RadarTheme.pi,
              foregroundColor: Colors.white,
            ),
            onPressed: () => _openAddSheet(context),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add your first item'),
          ),
        ]),
      );
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: RadarTheme.pi,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: () => _openAddSheet(context),
            icon: const Icon(Icons.add, size: 17),
            label: const Text('Add new equipment',
                style: TextStyle(fontSize: 12.5)),
          ),
        ),
      ),
      for (final l in listings)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _InventoryTile(listing: l),
        ),
    ]);
  }

  Future<void> _openAddSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddListingSheet(),
    );
  }
}

class _InventoryTile extends ConsumerWidget {
  const _InventoryTile({required this.listing});

  final MarketListing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: RadarTheme.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: listing.isActive
              ? RadarTheme.stroke
              : RadarTheme.alert.withValues(alpha: 0.4),
        ),
      ),
      child: Row(children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: RadarTheme.panelHigh,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: RadarTheme.stroke),
          ),
          child: listing.mediaUrls.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(
                    listing.mediaUrls.first,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                        Icons.category_outlined,
                        color: RadarTheme.textDim),
                  ),
                )
              : const Icon(Icons.category_outlined,
                  color: RadarTheme.textDim),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(listing.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13.5)),
              const SizedBox(height: 2),
              Text(
                '${marketCategoryLabel(listing.category)} · '
                '${marketConditionLabel(listing.condition)}',
                style: const TextStyle(
                    color: RadarTheme.textDim, fontSize: 11.5),
              ),
              const SizedBox(height: 6),
              Row(children: [
                Text('${_fmt(listing.pricePi)} π',
                    style: const TextStyle(
                        color: RadarTheme.pi,
                        fontWeight: FontWeight.w800,
                        fontSize: 13.5)),
                const SizedBox(width: 10),
                _stockStepper(ref),
              ]),
            ],
          ),
        ),
        Column(children: [
          Switch(
            value: listing.isActive,
            activeThumbColor: RadarTheme.radar,
            onChanged: (v) => ref
                .read(myListingsProvider.notifier)
                .setListingActive(listing.id, v),
          ),
          IconButton(
            tooltip: 'Delete listing',
            icon: const Icon(Icons.delete_outline,
                size: 18, color: RadarTheme.textDim),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: RadarTheme.panelHigh,
                  title: const Text('Delete listing?'),
                  content: Text(
                      'Remove “${listing.title}” from your shop permanently?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Keep')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete')),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref
                    .read(myListingsProvider.notifier)
                    .deleteListing(listing.id);
              }
            },
          ),
        ]),
      ]),
    );
  }

  Widget _stockStepper(WidgetRef ref) {
    final controller = ref.read(myListingsProvider.notifier);
    return Container(
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        _stepButton(Icons.remove, () => controller.adjustStock(listing.id, -1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('${listing.stockQuantity}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 12.5)),
        ),
        _stepButton(Icons.add, () => controller.adjustStock(listing.id, 1)),
      ]),
    );
  }

  Widget _stepButton(IconData icon, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 14, color: RadarTheme.textDim),
        ),
      );

  String _fmt(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
}

// -------------------------------------------------------- add listing sheet

class _AddListingSheet extends ConsumerStatefulWidget {
  const _AddListingSheet();

  @override
  ConsumerState<_AddListingSheet> createState() => _AddListingSheetState();
}

class _AddListingSheetState extends ConsumerState<_AddListingSheet> {
  final _titleCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '1');
  final _mediaCtrl = TextEditingController();
  String _category = kMarketCategories.first;
  String _condition = 'brand_new';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _mediaCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.'));
    final stock = int.tryParse(_stockCtrl.text) ?? 0;
    final media = _mediaCtrl.text
        .split(RegExp(r'[\n,]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final err = await ref.read(myListingsProvider.notifier).addListing(
          title: _titleCtrl.text,
          category: _category,
          pricePi: price ?? 0,
          condition: _condition,
          stockQuantity: stock,
          mediaUrls: media,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: RadarTheme.panelHigh,
        content: Text('Gear published — it is live on the market now.'),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SheetScaffold(
      title: 'Add new equipment',
      icon: Icons.add_business,
      iconColor: RadarTheme.pi,
      showClose: false,
      footer: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: RadarTheme.pi,
          foregroundColor: Colors.white,
        ),
        onPressed: _busy ? null : _submit,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.publish, size: 18),
        label: const Text('Publish listing'),
      ),
      children: [
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'e.g. “DJI Osmo Mobile 6 Gimbal”',
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _category,
              style: const TextStyle(color: RadarTheme.textPrimary),
              dropdownColor: RadarTheme.panelHigh,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                for (final c in kMarketCategories)
                  DropdownMenuItem(value: c, child: Text(marketCategoryLabel(c))),
              ],
              onChanged: (v) => setState(() => _category = v ?? _category),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _condition,
              style: const TextStyle(color: RadarTheme.textPrimary),
              dropdownColor: RadarTheme.panelHigh,
              decoration: const InputDecoration(labelText: 'Condition'),
              items: [
                for (final c in kMarketConditions)
                  DropdownMenuItem(value: c, child: Text(marketConditionLabel(c))),
              ],
              onChanged: (v) => setState(() => _condition = v ?? _condition),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: RadarTheme.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Price (π)',
                    hintText: '45',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _stockCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: RadarTheme.textPrimary),
                  decoration: const InputDecoration(labelText: 'Stock'),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _mediaCtrl,
              maxLines: 2,
              minLines: 1,
              style: const TextStyle(color: RadarTheme.textPrimary),
              decoration: const InputDecoration(
                labelText: 'Photo URLs (comma or newline separated)',
                hintText: 'https://…',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style:
                      const TextStyle(color: RadarTheme.alert, fontSize: 12.5)),
            ],
      ],
    );
  }
}
