import 'package:flutter/material.dart';

import '../domain/markbook.dart';
import 'widgets.dart';

Future<void> showRoster(BuildContext context, CourseGroup group) =>
    showDialog<void>(
      context: context,
      builder: (_) => RosterDialog(group: group),
    );

class RosterDialog extends StatefulWidget {
  const RosterDialog({super.key, required this.group});
  final CourseGroup group;
  @override
  State<RosterDialog> createState() => _RosterDialogState();
}

class _RosterDialogState extends State<RosterDialog> {
  String _search = '';
  final _horizontal = ScrollController();
  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final students = group.students
        .where(
          (student) =>
              '${student.rollNumber} ${student.fullName} ${student.email} ${student.memberCode}'
                  .toLowerCase()
                  .contains(_search),
        )
        .toList();
    return Dialog(
      child: SizedBox(
        width: 1060,
        height: 720,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      group.label,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Đóng',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Tag('FA26'),
                  Tag('${group.students.length} sinh viên'),
                  Tag('${group.daysLabel} · Slot ${group.slotNumber}'),
                  Tag(group.slot.label),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Buổi đầu: ${dateLabel(group.firstMeeting(Markbook.termStart))} · Chưa xác định tổng số buổi',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              TextField(
                onChanged: (value) =>
                    setState(() => _search = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Tìm MSSV, họ tên, email hoặc MemberCode',
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: students.isEmpty
                    ? const EmptyState(
                        title: 'Không tìm thấy sinh viên',
                        message: 'Thử tìm bằng MSSV hoặc một phần họ tên.',
                        icon: Icons.person_search_outlined,
                      )
                    : Scrollbar(
                        controller: _horizontal,
                        thumbVisibility: true,
                        notificationPredicate: (notification) =>
                            notification.depth == 1,
                        child: SingleChildScrollView(
                          child: SingleChildScrollView(
                            controller: _horizontal,
                            scrollDirection: Axis.horizontal,
                            child: DataTable(
                              headingRowColor: WidgetStateProperty.all(
                                const Color(0xfff3f7f6),
                              ),
                              columnSpacing: 28,
                              columns: const [
                                DataColumn(label: Text('STT')),
                                DataColumn(label: Text('MSSV')),
                                DataColumn(label: Text('Họ tên')),
                                DataColumn(label: Text('Email')),
                                DataColumn(label: Text('MemberCode')),
                                DataColumn(label: Text('Lớp')),
                              ],
                              rows: [
                                for (
                                  var index = 0;
                                  index < students.length;
                                  index++
                                )
                                  DataRow(
                                    cells: [
                                      DataCell(Text('${index + 1}')),
                                      DataCell(
                                        SelectableText(
                                          students[index].rollNumber,
                                        ),
                                      ),
                                      DataCell(Text(students[index].fullName)),
                                      DataCell(
                                        SelectableText(students[index].email),
                                      ),
                                      DataCell(
                                        Text(students[index].memberCode),
                                      ),
                                      DataCell(Text(students[index].classCode)),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              Text(
                '${students.length} / ${group.students.length} sinh viên · Nguồn: ${group.sheetName}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
