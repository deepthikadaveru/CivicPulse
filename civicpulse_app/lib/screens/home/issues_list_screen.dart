import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/constants/app_constants.dart';
import '../../providers/issues_provider.dart';
import '../issue_detail/issue_detail_screen.dart';

class IssuesListScreen extends StatefulWidget {
  const IssuesListScreen({super.key});

  @override
  State<IssuesListScreen> createState() => _IssuesListScreenState();
}

class _IssuesListScreenState extends State<IssuesListScreen> {
  final _scrollController = ScrollController();
  String? _selectedStatus;

  final _statusFilters = [
    {'label': 'All', 'value': null},
    {'label': 'Pending', 'value': 'pending'},
    {'label': 'In Progress', 'value': 'in_progress'},
    {'label': 'Resolved', 'value': 'resolved'},
  ];

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      context.read<IssuesProvider>().loadIssues(status: _selectedStatus);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<IssuesProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('CivicPulse'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.loadIssues(refresh: true, status: _selectedStatus),
          ),
        ],
      ),
      body: Column(
        children: [
          // Status filter chips
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _statusFilters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _statusFilters[i];
                final selected = _selectedStatus == f['value'];
                return FilterChip(
                  label: Text(f['label'] as String),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _selectedStatus = f['value']);
                    provider.loadIssues(refresh: true, status: _selectedStatus);
                  },
                  selectedColor: AppColors.primaryLight,
                  checkmarkColor: AppColors.primary,
                );
              },
            ),
          ),
          Expanded(
            child: provider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : provider.issues.isEmpty
                ? const Center(child: Text('No issues found', style: TextStyle(color: AppColors.textSecondary)))
                : RefreshIndicator(
                    onRefresh: () => provider.loadIssues(refresh: true, status: _selectedStatus),
                    child: ListView.separated(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.issues.length + (provider.isLoadingMore ? 1 : 0),
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) {
                        if (i == provider.issues.length) {
                          return const Center(child: Padding(
                            padding: EdgeInsets.all(16),
                            child: CircularProgressIndicator(),
                          ));
                        }
                        return _IssueCard(issue: provider.issues[i]);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _IssueCard extends StatelessWidget {
  final Map<String, dynamic> issue;
  const _IssueCard({required this.issue});

  @override
  Widget build(BuildContext context) {
    final severity = issue['severity'] ?? 'low';
    final status = issue['status'] ?? 'pending';
    final createdAt = issue['created_at'] != null
      ? DateTime.tryParse(issue['created_at']) ?? DateTime.now()
      : DateTime.now();

    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(
        builder: (_) => IssueDetailScreen(issueId: issue['id']),
      )),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Severity indicator
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.severityColor(severity),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(issue['title'] ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusBadge(status: status),
                ],
              ),
              if (issue['address'] != null && issue['address'].toString().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Expanded(child: Text(issue['address'],
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  )),
                ]),
              ],
              const SizedBox(height: 10),
              Row(children: [
                if (issue['category_name'] != null)
                  _Pill(issue['category_name'], AppColors.primaryLight, AppColors.primary),
                const Spacer(),
                const Icon(Icons.thumb_up_outlined, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('${issue['upvote_count'] ?? 0}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(width: 12),
                const Icon(Icons.people_outline, size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text('${issue['report_count'] ?? 1}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(width: 12),
                Text(timeago.format(createdAt),
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  String get _label => status.replaceAll('_', ' ');

  @override
  Widget build(BuildContext context) {
    final color = AppColors.statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(_label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;
  const _Pill(this.label, this.bg, this.fg);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg)),
    );
  }
}
