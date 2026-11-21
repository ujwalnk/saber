import 'package:flutter/material.dart';
import 'package:saber/components/settings/settings_subtitle.dart';
import 'package:saber/data/prefs.dart';
import 'package:saber/data/webdav/webdav_sync.dart';

/// Settings for syncing notes with any WebDAV server: the location of the
/// folder, a username and a password.
class WebDavSettings extends StatefulWidget {
  const WebDavSettings({super.key});

  @override
  State<WebDavSettings> createState() => _WebDavSettingsState();
}

class _WebDavSettingsState extends State<WebDavSettings> {
  final _url = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loaded = false;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await Future.wait([
      stows.webdavEnabled.waitUntilRead(),
      stows.webdavUrl.waitUntilRead(),
      stows.webdavUsername.waitUntilRead(),
      stows.webdavPassword.waitUntilRead(),
    ]);
    if (!mounted) return;
    setState(() {
      _url.text = stows.webdavUrl.value;
      _username.text = stows.webdavUsername.value;
      _password.text = stows.webdavPassword.value;
      _loaded = true;
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _canSync =>
      _url.text.trim().isNotEmpty && _username.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.of(context);
    if (!_loaded) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSubtitle(subtitle: 'WebDAV sync'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  hintText: 'https://example.com/remote.php/dav/files/me/Saber',
                  helperText: 'The WebDAV folder to keep your notes in',
                ),
                onChanged: (value) {
                  stows.webdavUrl.value = value.trim();
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _username,
                autocorrect: false,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(labelText: 'Username'),
                onChanged: (value) {
                  stows.webdavUsername.value = value.trim();
                  setState(() {});
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Hide password' : 'Show password',
                    icon: Icon(
                      _showPassword ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () =>
                        setState(() => _showPassword = !_showPassword),
                  ),
                ),
                onChanged: (value) => stows.webdavPassword.value = value,
              ),
            ],
          ),
        ),
        ValueListenableBuilder(
          valueListenable: stows.webdavEnabled,
          builder: (context, enabled, _) => SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            title: const Text('Sync with WebDAV'),
            subtitle: const Text(
              'Notes are stored on the server as they are, not encrypted',
            ),
            value: enabled && _canSync,
            onChanged: _canSync
                ? (value) => stows.webdavEnabled.value = value
                : null,
          ),
        ),
        ValueListenableBuilder(
          valueListenable: WebDavSync.instance.status,
          builder: (context, status, _) {
            final syncing = status.state == WebDavSyncState.syncing;
            final isError = status.state == WebDavSyncState.error;
            final time = status.time;
            final timeText = time == null
                ? ''
                : ' (${TimeOfDay.fromDateTime(time).format(context)})';
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      status.state == WebDavSyncState.idle
                          ? ''
                          : '${status.message}$timeText',
                      style: TextStyle(
                        fontSize: 13,
                        color: isError
                            ? colorScheme.error
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: syncing || !_canSync
                        ? null
                        : () {
                            // syncing now also switches syncing on
                            stows.webdavEnabled.value = true;
                            WebDavSync.instance.syncNow();
                          },
                    icon: const Icon(Icons.sync),
                    label: const Text('Sync now'),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
