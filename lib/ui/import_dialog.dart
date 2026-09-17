import 'package:flutter/material.dart';

import '../data/excel_importer.dart';
import 'roster_dialog.dart';
import 'widgets.dart';

class ImportDialog extends StatelessWidget {
  const ImportDialog({
    super.key,
    required this.preview,
    required this.replacing,
  });
  final ImportPreview preview;
  final bool replacing;

  @override
  Widget build(BuildContext context) {
    final book = preview.markbook;
    return Dialog(
      child: SizedBox(
        width: 1050,
        height: 750,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kiểm tra trước khi import',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    tooltip: 'Đóng',
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(book.sourceName, style: const TextStyle(color: muted)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  const Tag('FA26 · FALL 2026'),
                  Tag('${book.groups.length} lớp học phần'),
                  Tag('${book.subjects.length} môn'),
                  Tag('${book.enrollmentCount} lượt đăng ký hợp lệ'),
                  Tag('${book.studentCount} sinh viên'),
                ],
              ),
              const SizedBox(height: 16),
              Notice(
                preview.canSave
                    ? (replacing
                          ? 'Khi xác nhận, danh sách lớp FA26 được cập nhật từ file này. Điểm danh, lịch sử và cấu hình đã lưu được giữ nguyên; không cho xóa lớp, đổi lịch hoặc thêm/bớt MSSV của lớp đã có dữ liệu điểm danh. Bản dữ liệu trước được sao lưu.'
                          : 'Lịch bắt đầu từ 07/09/2026. Tổng số buổi và ngày kết thúc chưa xác định. Chọn một lớp bên dưới để xem danh sách sinh viên.')
                    : 'Có ${preview.errorCount} lỗi cần sửa. Chưa thể lưu; dữ liệu hiện tại được giữ nguyên. Các số liệu trên chỉ tính những dòng đọc hợp lệ.',
                error: !preview.canSave,
              ),
              const SizedBox(height: 12),
              Expanded(
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        tabs: [
                          const Tab(text: 'Lớp học phần'),
                          Tab(
                            text: 'Kiểm tra dữ liệu (${preview.issues.length})',
                          ),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            ListView.separated(
                              itemCount: book.groups.length,
                              separatorBuilder: (_, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final group = book.groups[index];
                                return ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                    horizontal: 4,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: paleTeal,
                                    child: Text(
                                      '${group.slotNumber}',
                                      style: const TextStyle(color: teal),
                                    ),
                                  ),
                                  title: Text(
                                    group.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${group.sheetName}\n${group.daysLabel} · Slot ${group.slotNumber} · ${group.slot.label}',
                                  ),
                                  isThreeLine: true,
                                  trailing: Text('${group.students.length} SV'),
                                  onTap: () => showRoster(context, group),
                                );
                              },
                            ),
                            preview.issues.isEmpty
                                ? const EmptyState(
                                    title: 'Dữ liệu hợp lệ',
                                    message: 'Đã kiểm tra cấu trúc sheet, các trường bắt buộc, lớp, MSSV và email.',
                                    icon: Icons.task_alt,
                                  )
                                : ListView.builder(
                                    itemCount: preview.issues.length,
                                    itemBuilder: (_, index) {
                                      final issue = preview.issues[index];
                                      return ListTile(
                                        leading: Icon(
                                          issue.isError
                                              ? Icons.error_outline
                                              : Icons.info_outline,
                                          color: issue.isError
                                              ? Colors.red.shade700
                                              : Colors.orange.shade800,
                                        ),
                                        title: Text(issue.message),
                                        subtitle: issue.location.isEmpty
                                            ? null
                                            : Text(issue.location),
                                      );
                                    },
                                  ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Hủy'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: preview.canSave
                        ? () => Navigator.pop(context, true)
                        : null,
                    icon: const Icon(Icons.check),
                    label: Text(
                      replacing
                          ? 'Thay dữ liệu FA26 và lưu'
                          : 'Xác nhận import',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
