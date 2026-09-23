import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/market.dart';
import '../state/auth_controller.dart';
import '../state/market_providers.dart';
import 'market_detail_screen.dart';
import 'merchant_dashboard_screen.dart';
import 'radar_theme.dart';
import 'sheet_scaffold.dart';
import 'shell.dart';

/// The PitchMarket — P2P marketplace for pro streaming gear, paid in Pi.
///
/// Feed of active listings with category / search / price filtering; taps
/// open the gear detail view with the Pi checkout button.
class MarketFeedScreen extends ConsumerWidget {
  const MarketFeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingsAsync = ref.watch(marketListingsProvider);
    final filter = ref.watch(marketFilterProvider);
    final filtered = ref.watch(filteredMarketListingsProvider);
    final shops = ref.watch(marketShopsProvider).value ?? const <MarketShop>[];
    final session = ref.watch(sessionProvider);

    return Scaffold(
      backgroundColor: RadarTheme.ink,
      body: SafeArea(
        child: RefreshIndicator(
          color: RadarTheme.pi,
          backgroundColor: RadarTheme.panel,
          onRefresh: () async {
            await ref.read(marketListingsProvider.notifier).refresh();
            await ref.read(marketShopsProvider.notifier).refresh();
          },
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: RadarTheme.ink.withValues(alpha: 0.96),
                title: Row(children: [
                  const Icon(Icons.storefront, color: RadarTheme.pi, size: 22),
                  const SizedBox(width: 8),
                  const Text('The PitchMarket',
                      style: TextStyle(
                          color: RadarTheme.textPrimary,
                          fontWeight: FontWeight.w700)),
                ]),
                actions: [
                  IconButton(
                    tooltip: 'Merchant dashboard',
                    icon: const Icon(Icons.store_mall_directory_outlined,
                        size: 20),
                    onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const MerchantDashboardScreen())),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: _HeaderCard(
                    signedIn: session != null,
                    listingCount: filtered.length,
                    shopCount: shops.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _SearchBar(
                    query: filter.query,
                    onChanged: (q) =>
                        ref.read(marketFilterProvider.notifier).setQuery(q),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _CategoryChips(
                    selected: filter.category,
                    onSelect: (c) =>
                        ref.read(marketFilterProvider.notifier).setCategory(c),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: _FilterRow(filter: filter),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: SectionHeader(
                    'Gear for sale',
                    trailing: Text(
                        '${filtered.length} of '
                        '${(listingsAsync.value ?? const []).length} listings',
                        style: const TextStyle(
                            color: RadarTheme.textDim, fontSize: 12)),
                  ),
                ),
              ),
              if (listingsAsync.isLoading && filtered.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2.4)),
                  ),
                )
              else if (filtered.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 30),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.inventory_2_outlined,
                              size: 42, color: RadarTheme.textDim),
                          SizedBox(height: 10),
                          Text('No gear matches those filters',
                              style: TextStyle(color: RadarTheme.textDim)),
                        ],
                      ),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                  sliver: SliverList.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final listing = filtered[i];
                      final shop = shops
                          .where((s) => s.id == listing.shopId)
                          .firstOrNull;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ListingCard(
                          listing: listing,
                          shop: shop,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => MarketDetailScreen(
                                  listingId: listing.id),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------- header

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.signedIn,
    required this.listingCount,
    required this.shopCount,
  });

  final bool signedIn;
  final int listingCount;
  final int shopCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            RadarTheme.pi.withValues(alpha: 0.12),
            RadarTheme.panel,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: RadarTheme.pi.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Local streaming gear, paid in Pi',
                  style: TextStyle(
                      color: RadarTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5)),
              const SizedBox(height: 4),
              Text(
                '$listingCount items from $shopCount local merchant '
                'shops. Sellers are paid directly to their verified Pi '
                'wallet; a small fee keeps the platform running.',
                style: const TextStyle(
                    color: RadarTheme.textDim, fontSize: 12, height: 1.45),
              ),
            ],
          ),
        ),
        if (!signedIn) ...[
          const SizedBox(width: 10),
          const Icon(Icons.lock_outline, color: RadarTheme.textDim, size: 20),
        ],
      ]),
    );
  }
}

// -------------------------------------------------------------- search bar

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.query, required this.onChanged});

  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      controller: TextEditingController(text: query),
      style: const TextStyle(color: RadarTheme.textPrimary, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: 'Search gimbals, mics, tripods…',
        prefixIcon: const Icon(Icons.search, size: 20),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: () => onChanged(''),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------- category chips

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({required this.selected, required this.onSelect});

  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _chip(null, 'All'),
          for (final c in kMarketCategories) _chip(c, marketCategoryLabel(c)),
        ],
      ),
    );
  }

  Widget _chip(String? value, String label) {
    final isSel = selected == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: isSel ? RadarTheme.ink : RadarTheme.textPrimary,
                fontWeight: isSel ? FontWeight.w700 : FontWeight.w500)),
        selected: isSel,
        onSelected: (_) => onSelect(value),
        selectedColor: RadarTheme.pi,
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ------------------------------------------------------------- filter row

class _FilterRow extends ConsumerWidget {
  const _FilterRow({required this.filter});

  final MarketFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Horizontally scrollable so narrow phones never clip the filter strip
    // when the Clear action joins the row (was a Spacer'd Row, overflowed).
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: filter.hasActiveFilters
                ? RadarTheme.pi
                : RadarTheme.textDim,
            side: BorderSide(
                color: filter.hasActiveFilters
                    ? RadarTheme.pi.withValues(alpha: 0.6)
                    : RadarTheme.stroke),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: () => _openPriceSheet(context, ref),
          icon: const Icon(Icons.tune, size: 16),
          label: Text(_priceLabel(), style: const TextStyle(fontSize: 12.5)),
        ),
        const SizedBox(width: 8),
        FilterChip(
          label: const Text('In stock >1', style: TextStyle(fontSize: 12)),
          selected: filter.inStockOnly,
          onSelected: (v) =>
              ref.read(marketFilterProvider.notifier).setInStockOnly(v),
          selectedColor: RadarTheme.pi.withValues(alpha: 0.35),
          showCheckmark: false,
          visualDensity: VisualDensity.compact,
        ),
        if (filter.hasActiveFilters) ...[
          const SizedBox(width: 8),
          TextButton(
            onPressed: () => ref.read(marketFilterProvider.notifier).reset(),
            child: const Text('Clear', style: TextStyle(fontSize: 12)),
          ),
        ],
      ]),
    );
  }

  String _priceLabel() {
    if (filter.minPrice == null && filter.maxPrice == null) {
      return 'Any price · π';
    }
    final min = filter.minPrice?.toStringAsFixed(0) ?? '0';
    final max = filter.maxPrice?.toStringAsFixed(0) ?? '∞';
    return '$min–$max π';
  }

  Future<void> _openPriceSheet(BuildContext context, WidgetRef ref) async {
    double min = filter.minPrice ?? 0;
    double max = filter.maxPrice ?? 500;
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SheetScaffold(
          title: 'Price range (Pi)',
          footer: Row(children: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Reset'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Apply'),
            ),
          ]),
          children: [
            RangeSlider(
              values: RangeValues(min, max),
              min: 0,
              max: 500,
              divisions: 50,
              labels: RangeLabels(
                  '${min.toStringAsFixed(0)} π', '${max.toStringAsFixed(0)} π'),
              activeColor: RadarTheme.pi,
              onChanged: (v) => setSheet(() {
                min = v.start;
                max = v.end;
              }),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (changed == true) {
      ref.read(marketFilterProvider.notifier).setPriceRange(
            min: min > 0 ? min : null,
            max: max < 500 ? max : null,
          );
    } else if (changed == false) {
      ref.read(marketFilterProvider.notifier).setPriceRange();
    }
  }
}

// ------------------------------------------------------------ listing card

class _ListingCard extends StatelessWidget {
  const _ListingCard({
    required this.listing,
    required this.shop,
    required this.onTap,
  });

  final MarketListing listing;
  final MarketShop? shop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: RadarTheme.panel,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: RadarTheme.stroke),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _thumb(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(listing.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: RadarTheme.textPrimary,
                            fontWeight: FontWeight.w700,
                            fontSize: 14.5)),
                    const SizedBox(height: 3),
                    Text(
                      shop != null
                          ? '${shop!.shopName} · ${shop!.locationArea}'
                          : 'Local merchant shop',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: RadarTheme.textDim, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _pill(
                        icon: Icons.category_outlined,
                        label: marketCategoryLabel(listing.category),
                        color: RadarTheme.info,
                      ),
                      _pill(
                        icon: Icons.grade_outlined,
                        label: marketConditionLabel(listing.condition),
                        color: RadarTheme.radar,
                      ),
                      _pill(
                        icon: Icons.inventory_outlined,
                        label: listing.stockQuantity > 1
                            ? '${listing.stockQuantity} in stock'
                            : 'Last one',
                        color: listing.stockQuantity > 1
                            ? RadarTheme.textDim
                            : RadarTheme.gold,
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_fmtPi(listing.pricePi),
                      style: const TextStyle(
                          color: RadarTheme.pi,
                          fontWeight: FontWeight.w800,
                          fontSize: 16)),
                  const Text('π',
                      style: TextStyle(
                          color: RadarTheme.pi,
                          fontWeight: FontWeight.w600,
                          fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _thumb() {
    final url = listing.mediaUrls.isNotEmpty ? listing.mediaUrls.first : null;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: RadarTheme.panelHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: RadarTheme.stroke),
      ),
      child: url == null
          ? Icon(_categoryIcon(listing.category),
              color: RadarTheme.textDim, size: 26)
          : ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    Icon(_categoryIcon(listing.category),
                        color: RadarTheme.textDim, size: 26),
              ),
            ),
    );
  }

  IconData _categoryIcon(String c) => switch (c) {
        'phone' => Icons.smartphone,
        'gimbal' => Icons.screen_rotation,
        'tripod' => Icons.camera_alt_outlined,
        'audio' => Icons.mic,
        'lighting' => Icons.lightbulb_outline,
        _ => Icons.category_outlined,
      };

  String _fmtPi(double v) =>
      v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);

  Widget _pill({
    required IconData icon,
    required String label,
    required Color color,
  }) =>
      Container(
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
