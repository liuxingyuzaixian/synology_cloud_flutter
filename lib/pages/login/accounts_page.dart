import 'package:flutter/material.dart';
import '../../utils/app_preferences.dart';
import '../../models/server_model.dart';
import 'login_page.dart';

class AccountsPage extends StatelessWidget {
  final List<ServerModel> servers;
  const AccountsPage({super.key, required this.servers});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('历史账号')),
      body: servers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_off_outlined,
                      size: 64, color: theme.hintColor),
                  const SizedBox(height: 16),
                  Text('暂无保存的账号', style: TextStyle(color: theme.hintColor)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: servers.length,
              itemBuilder: (context, index) {
                final server = servers[index];
                return _buildServerCard(context, server, index);
              },
            ),
    );
  }

  Widget _buildServerCard(
      BuildContext context, ServerModel server, int index) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => LoginPage(server: server, type: 'login'),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.dns,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.account,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${server.https ? "https" : "http"}://${server.host}:${server.port}',
                      style: TextStyle(fontSize: 13, color: theme.hintColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (server.note.isNotEmpty)
                      Text(
                        server.note,
                        style: TextStyle(
                            fontSize: 12, color: theme.hintColor),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: theme.colorScheme.error),
                onPressed: () => _deleteServer(context, index),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _deleteServer(BuildContext context, int index) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: const Text('确定要删除这个账号记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final updated = List<ServerModel>.from(servers)..removeAt(index);
      AppPreferences.putString('servers', ServerModel.listToJson(updated));
      if (context.mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AccountsPage(servers: updated),
          ),
        );
      }
    }
  }
}
