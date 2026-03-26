import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_constants.dart';
import '../../providers/issues_provider.dart';
// ignore: unused_import
import '../../providers/auth_provider.dart';

class IssueDetailScreen extends StatefulWidget {
  final String issueId;
  const IssueDetailScreen({super.key, required this.issueId});

  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  Map<String, dynamic>? _issue;
  bool _isLoading = true;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final issue =
          await context.read<IssuesProvider>().getIssueDetail(widget.issueId);
      setState(() {
        _issue = issue;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _upvote() async {
    final success =
        await context.read<IssuesProvider>().toggleUpvote(widget.issueId);
    if (success) _load();
  }

  Future<void> _submitComment() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final success =
        await context.read<IssuesProvider>().addComment(widget.issueId, text);
    if (success) {
      _commentController.clear();
      _load();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_issue == null)
      return const Scaffold(body: Center(child: Text('Issue not found')));

    final issue = _issue!;
    final severity = issue['severity'] ?? 'low';
    final status = issue['status'] ?? 'pending';
    final hasVoted = issue['has_voted'] ?? false;
    final media = issue['media'] as List? ?? [];
    final comments = issue['comments'] as List? ?? [];
    final logs = issue['status_logs'] as List? ?? [];

    return Scaffold(
      appBar: AppBar(title: Text(issue['category_name'] ?? 'Issue Detail')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Photo
          if (media.isNotEmpty && media[0]['file_url'] != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                '${AppConstants.baseUrl.replaceAll('/api/v1', '')}${media[0]['file_url']}',
                height: 220,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  height: 220,
                  color: AppColors.border,
                  child: const Center(
                      child: Icon(Icons.image_not_supported_outlined,
                          size: 40, color: AppColors.textSecondary)),
                ),
              ),
            ),
          const SizedBox(height: 16),

          // Title + severity
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                  color: AppColors.severityColor(severity),
                  shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
                child: Text(issue['title'] ?? '',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w700))),
          ]),
          const SizedBox(height: 8),

          // Status + department
          Row(children: [
            _Badge(status.replaceAll('_', ' '), AppColors.statusColor(status)),
            const SizedBox(width: 8),
            if (issue['department_name'] != null)
              _Badge(issue['department_name'], AppColors.primary),
          ]),
          const SizedBox(height: 12),

          // Stats row
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _Stat('${issue['report_count'] ?? 1}', 'Reports'),
                  _Stat('${issue['upvote_count'] ?? 0}', 'Upvotes'),
                  _Stat('${issue['days_open'] ?? 0}d', 'Open'),
                  _Stat(
                      '${((issue['priority_score'] ?? 0) as num).toStringAsFixed(1)}',
                      'Score'),
                ]),
          ),
          const SizedBox(height: 12),

          // Address
          if (issue['address'] != null &&
              issue['address'].toString().isNotEmpty)
            Row(children: [
              const Icon(Icons.location_on_outlined,
                  size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                  child: Text(issue['address'],
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13))),
            ]),
          const SizedBox(height: 8),

          // Reporter + time
          Row(children: [
            const Icon(Icons.person_outline,
                size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text('Reported by ${issue['reporter_name'] ?? 'Anonymous'}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13)),
            const Spacer(),
            if (issue['created_at'] != null)
              Text(timeago.format(DateTime.parse(issue['created_at'])),
                  style: const TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
          ]),

          // Description
          if (issue['description'] != null &&
              issue['description'].toString().isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('Description',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 6),
            Text(issue['description'],
                style: const TextStyle(fontSize: 14, height: 1.5)),
          ],

          // AI suggestion
          if (issue['ai_suggested_category_name'] != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F0FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFAFA9EC)),
              ),
              child: Row(children: [
                const Icon(Icons.auto_awesome,
                    size: 16, color: Color(0xFF534AB7)),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                  'AI suggested: ${issue['ai_suggested_category_name']} (${((issue['ai_confidence'] ?? 0) * 100).toStringAsFixed(0)}% confidence)',
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFF3C3489)),
                )),
              ]),
            ),
          ],

          // Status timeline
          if (logs.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Status Timeline',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
            const SizedBox(height: 8),
            ...logs.map((log) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(top: 5),
                          decoration: BoxDecoration(
                              color: AppColors.primary, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  '${log['from_status'] ?? 'New'} → ${log['to_status']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              if (log['note'] != null &&
                                  log['note'].toString().isNotEmpty)
                                Text(log['note'],
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                            ])),
                      ]),
                )),
          ],

          // Comments
          const SizedBox(height: 20),
          const Text('Comments',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          const SizedBox(height: 8),
          if (comments.isEmpty)
            const Text('No comments yet.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ...comments.map((c) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(c['author_name'] ?? 'User',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(width: 6),
                          if (c['is_official'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('Official',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w600)),
                            ),
                        ]),
                        const SizedBox(height: 4),
                        Text(c['text'] ?? '',
                            style: const TextStyle(fontSize: 13, height: 1.4)),
                      ]),
                ),
              )),

          // Add comment
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextFormField(
              controller: _commentController,
              decoration: const InputDecoration(
                  hintText: 'Add a comment...', isDense: true),
            )),
            const SizedBox(width: 8),
            IconButton(
              onPressed: _submitComment,
              icon: const Icon(Icons.send_rounded, color: AppColors.primary),
            ),
          ]),
          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        color: Colors.white,
        child: ElevatedButton.icon(
          onPressed: _upvote,
          icon: Icon(hasVoted ? Icons.thumb_up : Icons.thumb_up_outlined),
          label: Text(hasVoted ? 'Upvoted' : 'Upvote this issue'),
          style: ElevatedButton.styleFrom(
            backgroundColor: hasVoted ? AppColors.resolved : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  const _Badge(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      );
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat(this.value, this.label);

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.primary)),
        Text(label,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ]);
}
