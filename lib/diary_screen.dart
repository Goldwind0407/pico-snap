import 'package:flutter/material.dart';

import 'gallery_screen.dart';
import 'services/my_works.dart';
import 'theme.dart';

/// 「日記」：月曆上看每天做了哪些作品，每天可以寫一句話。
class DiaryScreen extends StatefulWidget {
  const DiaryScreen({super.key});

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  late DateTime _day = _today();
  late DateTime _month = DateTime(_day.year, _day.month);

  void _shiftMonth(int by) => setState(() => _month = DateTime(_month.year, _month.month + by));

  void _goToday() => setState(() {
    _day = _today();
    _month = DateTime(_day.year, _day.month);
  });

  Future<void> _editNote() async {
    final ctrl = TextEditingController(text: MyWorks.noteOn(_day));
    final day = _day;
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(22, 20, 22, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(dayLabel(day), style: const TextStyle(fontSize: 19, color: ink, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text('寫一句這天的心情 ♡', style: TextStyle(fontSize: 12, color: muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLength: 60,
            maxLines: 3,
            minLines: 2,
            style: hand(26),
            decoration: InputDecoration(
              filled: true, fillColor: cream, hintText: '今天好開心！', hintStyle: hand(26, color: muted),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: coral, width: 1.5)),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            style: FilledButton.styleFrom(
              backgroundColor: coral, padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('寫好了', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          )),
        ]),
      ),
    );
    // The sheet's text field may still be animating out; let it go first.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (text == null) return;
    if (!await MyWorks.setNote(day, text) && mounted) {
      showMessage(context, '日記沒有存進手機（空間可能不夠），關掉 App 後會不見', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: cream,
    body: SafeArea(child: ValueListenableBuilder<int>(
      valueListenable: MyWorks.changes,
      builder: (context, _, __) {
        final byDay = <String, List<Work>>{};
        for (final w in MyWorks.works) {
          byDay.putIfAbsent(MyWorks.dayKey(w.created), () => []).add(w);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 130), children: [
          Row(children: [
            const SizedBox(height: 48),
            const Expanded(child: Text('日記', style: TextStyle(fontSize: 22, color: ink, fontWeight: FontWeight.w900))),
            if (MyWorks.dayKey(_day) != MyWorks.dayKey(_today()) || _month != DateTime(_day.year, _day.month))
              TextButton(
                onPressed: _goToday,
                style: TextButton.styleFrom(foregroundColor: coral),
                child: const Text('回到今天', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
          ]),
          const SizedBox(height: 8),
          _MonthCard(
            month: _month, selected: _day, today: _today(), byDay: byDay,
            onShift: _shiftMonth, onPick: (d) => setState(() => _day = d),
          ),
          const SizedBox(height: 16),
          _DayCard(day: _day, works: byDay[MyWorks.dayKey(_day)] ?? const [], note: MyWorks.noteOn(_day), onEditNote: _editNote),
        ]);
      },
    )),
  );
}

class _MonthCard extends StatelessWidget {
  final DateTime month, selected, today;
  final Map<String, List<Work>> byDay;
  final ValueChanged<int> onShift;
  final ValueChanged<DateTime> onPick;
  const _MonthCard({required this.month, required this.selected, required this.today, required this.byDay, required this.onShift, required this.onPick});

  @override
  Widget build(BuildContext context) {
    // Sunday first, like most calendars here.
    final lead = month.weekday % 7;
    final days = DateTime(month.year, month.month + 1, 0).day;
    final count = [for (var d = 1; d <= days; d++) ...?byDay[MyWorks.dayKey(DateTime(month.year, month.month, d))]].length;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 12),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(24), border: Border.all(color: line),
        boxShadow: [BoxShadow(color: ink.withValues(alpha: .05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(children: [
        Row(children: [
          IconButton(onPressed: () => onShift(-1), tooltip: '上個月', icon: const Icon(Icons.chevron_left_rounded, color: ink)),
          Expanded(child: Column(children: [
            Text('${month.year}年${month.month}月', style: const TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w900)),
            Text(count == 0 ? '這個月還沒有作品' : '這個月 $count 件作品',
              style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w700)),
          ])),
          IconButton(onPressed: () => onShift(1), tooltip: '下個月', icon: const Icon(Icons.chevron_right_rounded, color: ink)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          for (final (i, w) in const ['日', '一', '二', '三', '四', '五', '六'].indexed)
            Expanded(child: Text(w, textAlign: TextAlign.center, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: i == 0 ? coral : muted,
            ))),
        ]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: .8, mainAxisSpacing: 4, crossAxisSpacing: 4,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox(),
            for (var d = 1; d <= days; d++)
              _DayCell(
                day: DateTime(month.year, month.month, d),
                works: byDay[MyWorks.dayKey(DateTime(month.year, month.month, d))] ?? const [],
                selected: selected == DateTime(month.year, month.month, d),
                today: today == DateTime(month.year, month.month, d),
                onTap: () => onPick(DateTime(month.year, month.month, d)),
              ),
          ],
        ),
      ]),
    );
  }
}

class _DayCell extends StatelessWidget {
  final DateTime day;
  final List<Work> works;
  final bool selected, today;
  final VoidCallback onTap;
  const _DayCell({required this.day, required this.works, required this.selected, required this.today, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hasNote = MyWorks.noteOn(day).isNotEmpty;
    final number = Text('${day.day}', style: TextStyle(
      fontSize: 13, height: 1, color: today ? coral : ink, fontWeight: today || selected ? FontWeight.w900 : FontWeight.w600,
    ));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? blush : Colors.transparent, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? coral : Colors.transparent, width: 1.6),
        ),
        padding: const EdgeInsets.all(2),
        child: works.isEmpty
          ? Stack(children: [
              Center(child: number),
              if (hasNote) const Positioned(left: 0, right: 0, bottom: 3, child: Icon(Icons.favorite_rounded, size: 8, color: blushLine)),
            ])
          : Stack(fit: StackFit.expand, children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: ColoredBox(color: paperCard, child: Image(
                  image: ResizeImage(works.first.image, height: 140, policy: ResizeImagePolicy.fit),
                  fit: BoxFit.cover, gaplessPlayback: true,
                )),
              ),
              Positioned(left: 2, top: 2, child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .9), borderRadius: BorderRadius.circular(6)),
                child: number,
              )),
              if (hasNote) const Positioned(right: 2, bottom: 2, child: Icon(Icons.favorite_rounded, size: 11, color: coral)),
            ]),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  final DateTime day;
  final List<Work> works;
  final String note;
  final VoidCallback onEditNote;
  const _DayCard({required this.day, required this.works, required this.note, required this.onEditNote});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    decoration: BoxDecoration(color: paperCard, borderRadius: BorderRadius.circular(24), border: Border.all(color: line)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(dayLabel(day), style: const TextStyle(fontSize: 17, color: ink, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      GestureDetector(
        onTap: onEditNote,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: note.isEmpty ? blushLine : line)),
          child: Row(children: [
            Expanded(child: note.isEmpty
              ? const Text('＋ 寫一句這天的心情', style: TextStyle(fontSize: 14, color: coral, fontWeight: FontWeight.w800))
              : Text(note, style: hand(24))),
            if (note.isNotEmpty) const Icon(Icons.edit_outlined, size: 18, color: muted),
          ]),
        ),
      ),
      const SizedBox(height: 14),
      if (works.isEmpty)
        const Text('這天沒有作品', style: TextStyle(fontSize: 13, color: muted, fontWeight: FontWeight.w700))
      else ...[
        Text('${works.length} 件作品', style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        SizedBox(height: 150, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: works.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(width: 108, child: WorkTile(work: works[i], onTap: () => WorkViewer.open(context, works, i))),
        )),
      ],
    ]),
  );
}
