import 'package:axon_dart/axon.dart';
import 'package:flutter/material.dart';

/// 显示 binding 滤波器 enum 的本地化文案。
extension FilterKindX on FilterKind {
  String get label => switch (this) {
        FilterKind.lowPass => 'Low-Pass',
        FilterKind.highPass => 'High-Pass',
        FilterKind.bandPass => 'Band-Pass',
        FilterKind.bandStop => 'Band-Stop',
        FilterKind.notch => 'Notch',
      };

  /// 显示在单行摘要里的短标签。
  String get shortLabel => switch (this) {
        FilterKind.lowPass => 'LP',
        FilterKind.highPass => 'HP',
        FilterKind.bandPass => 'BP',
        FilterKind.bandStop => 'BS',
        FilterKind.notch => 'Notch',
      };
}

/// 滤波器配置（纯 Dart 侧数据模型）。
class FilterEntry {
  FilterKind kind;
  double cutoffHz;
  double cutoff2Hz; // 仅 BandPass / BandStop
  int order;
  double q; // 仅 BandPass / BandStop / Notch

  FilterEntry({
    this.kind = FilterKind.lowPass,
    this.cutoffHz = 40,
    this.cutoff2Hz = 60,
    this.order = 4,
    this.q = 0.7,
  });

  bool get needsCutoff2 =>
      kind == FilterKind.bandPass || kind == FilterKind.bandStop;

  bool get needsQ =>
      kind == FilterKind.bandPass ||
      kind == FilterKind.bandStop ||
      kind == FilterKind.notch;

  /// 转为 FFI 结构。
  AxonFilterStage toStage(double sampleRateHz) => AxonFilterStage(
        filterType: FilterType.iir,
        kind: kind,
        cutoffHz: cutoffHz,
        cutoff2Hz: cutoff2Hz,
        order: order,
        q: q,
        sampleRateHz: sampleRateHz,
      );
}

/// 底部弹出面板：滤波器链管理。
///
/// 调用方传入当前滤波链副本与回调，面板内所有修改通过
/// [onApply] 回写给调用方，由调用方决定是否重建 native pipeline。
Future<void> showFilterSheet(
  BuildContext context, {
  required List<FilterEntry> filters,
  required void Function(List<FilterEntry>) onApply,
  required double sampleRateHz,
}) async {
  final result = await showModalBottomSheet<List<FilterEntry>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FilterSheetBody(
      initial: filters,
      sampleRateHz: sampleRateHz,
    ),
  );
  if (result != null) onApply(result);
}

// ---------------------------------------------------------------------------
// 内部实现
// ---------------------------------------------------------------------------

class _FilterSheetBody extends StatefulWidget {
  const _FilterSheetBody({required this.initial, required this.sampleRateHz});
  final List<FilterEntry> initial;
  final double sampleRateHz;

  @override
  State<_FilterSheetBody> createState() => _FilterSheetBodyState();
}

class _FilterSheetBodyState extends State<_FilterSheetBody> {
  late List<FilterEntry> _filters;
  int? _editingIdx;

  @override
  void initState() {
    super.initState();
    _filters = widget.initial.map((e) => FilterEntry(
      kind: e.kind,
      cutoffHz: e.cutoffHz,
      cutoff2Hz: e.cutoff2Hz,
      order: e.order,
      q: e.q,
    )).toList();
  }

  void _add() {
    setState(() {
      _filters.add(FilterEntry());
      _editingIdx = _filters.length - 1;
    });
  }

  void _remove(int idx) {
    setState(() {
      _filters.removeAt(idx);
      if (_editingIdx == idx) {
        _editingIdx = null;
      } else if (_editingIdx != null && _editingIdx! > idx) {
        _editingIdx = _editingIdx! - 1;
      }
    });
  }

  void _apply() {
    Navigator.of(context).pop(List.of(_filters));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // ── drag handle ──
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // ── header ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text('Filters', style: theme.textTheme.titleMedium),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // ── filter list ──
          Expanded(
            child: _filters.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No filters.\nTap + Add to insert one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _filters.length,
                    itemBuilder: (_, idx) => _FilterTile(
                      key: ValueKey(idx),
                      entry: _filters[idx],
                      index: idx,
                      expanded: _editingIdx == idx,
                      onToggleExpand: () => setState(() =>
                          _editingIdx = _editingIdx == idx ? null : idx),
                      onRemove: () => _remove(idx),
                      sampleRateHz: widget.sampleRateHz,
                      onChanged: (updated) => setState(() {
                        _filters[idx] = updated;
                      }),
                    ),
                  ),
          ),
          const Divider(height: 1),
          // ── apply button ──
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _apply,
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    _filters.isEmpty ? 'Apply (clear all)' : 'Apply',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 单个滤波器条目
// ---------------------------------------------------------------------------

class _FilterTile extends StatelessWidget {
  const _FilterTile({
    super.key,
    required this.entry,
    required this.index,
    required this.expanded,
    required this.onToggleExpand,
    required this.onRemove,
    required this.sampleRateHz,
    required this.onChanged,
  });

  final FilterEntry entry;
  final int index;
  final bool expanded;
  final VoidCallback onToggleExpand;
  final VoidCallback onRemove;
  final double sampleRateHz;
  final ValueChanged<FilterEntry> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nyquist = sampleRateHz / 2;
    final maxCutoff = nyquist * 0.95;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Column(
        children: [
          // ── header row: index + type + delete ──
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<FilterKind>(
                      value: entry.kind,
                      isDense: true,
                      items: FilterKind.values
                          .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                          .toList(),
                      onChanged: (k) {
                        if (k != null) {
                          onChanged(FilterEntry(
                            kind: k,
                            cutoffHz: entry.cutoffHz,
                            cutoff2Hz: entry.cutoff2Hz,
                            order: entry.order,
                            q: entry.q,
                          ));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    entry.needsCutoff2
                        ? '${entry.cutoffHz.round()}–${entry.cutoff2Hz.round()} Hz'
                        : '${entry.cutoffHz.round()} Hz',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    visualDensity: VisualDensity.compact,
                    onPressed: onRemove,
                    tooltip: 'Remove',
                  ),
                ],
              ),
            ),
          ),
          // ── expanded parameters ──
          if (expanded) _buildParams(maxCutoff),
        ],
      ),
    );
  }

  Widget _buildParams(double maxCutoff) {
    // 滑块标签：LP/HP 用 "Cutoff"，BP/BS 用 "From / To"，Notch 用 "Center"
    final (label1, label2) = switch (entry.kind) {
      FilterKind.lowPass || FilterKind.highPass => ('Cutoff', ''),
      FilterKind.bandPass || FilterKind.bandStop => ('From', 'To'),
      FilterKind.notch => ('Center', ''),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          // 第一个频率滑块
          _SliderRow(
            label: label1,
            value: entry.cutoffHz,
            min: 1,
            max: maxCutoff,
            decimals: 0,
            suffix: ' Hz',
            onChanged: (v) => onChanged(FilterEntry(
              kind: entry.kind,
              cutoffHz: v,
              cutoff2Hz: entry.cutoff2Hz,
              order: entry.order,
              q: entry.q,
            )),
          ),
          // 第二个频率滑块（仅 BP / BS）
          if (entry.needsCutoff2)
            _SliderRow(
              label: label2,
              value: entry.cutoff2Hz.clamp(entry.cutoffHz + 1, maxCutoff),
              min: entry.cutoffHz + 1,
              max: maxCutoff,
              decimals: 0,
              suffix: ' Hz',
              onChanged: (v) => onChanged(FilterEntry(
                kind: entry.kind,
                cutoffHz: entry.cutoffHz,
                cutoff2Hz: v,
                order: entry.order,
                q: entry.q,
              )),
            ),
          // Order
          Row(
            children: [
              const SizedBox(
                width: 40,
                child: Text('Order', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  value: entry.order,
                  isDense: true,
                  items: [2, 4, 6, 8, 10, 12]
                      .map((n) => DropdownMenuItem(value: n, child: Text('$n')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      onChanged(FilterEntry(
                        kind: entry.kind,
                        cutoffHz: entry.cutoffHz,
                        cutoff2Hz: entry.cutoff2Hz,
                        order: v,
                        q: entry.q,
                      ));
                    }
                  },
                ),
              ),
            ],
          ),
          // Q factor for band / notch filters
          if (entry.needsQ)
            _SliderRow(
              label: 'Q',
              value: entry.q.clamp(0.1, 20.0),
              min: 0.1,
              max: 20.0,
              decimals: 1,
              divisions: 199,
              onChanged: (v) => onChanged(FilterEntry(
                kind: entry.kind,
                cutoffHz: entry.cutoffHz,
                cutoff2Hz: entry.cutoff2Hz,
                order: entry.order,
                q: v,
              )),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 滑块行组件
// ---------------------------------------------------------------------------

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.decimals,
    this.suffix = '',
    this.divisions,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int decimals;
  final String suffix;
  final int? divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final display = decimals == 0
        ? '${value.round()}$suffix'
        : '${value.toStringAsFixed(decimals)}$suffix';
    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(label, style: const TextStyle(fontSize: 12)),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions ?? (max - min).round().clamp(10, 500),
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 56,
          child: Text(
            display,
            style: const TextStyle(fontSize: 12),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}
