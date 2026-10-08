import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/cloud_config.dart';
import 'data/auth_service.dart';
import 'data/cloud/api_client.dart';
import 'data/cloud/cloud_auth_service.dart';
import 'data/cloud/cloud_finance_repository.dart';
import 'data/cloud/pluggy_open_finance.dart';
import 'data/finance_repository.dart';
import 'state/auth_controller.dart';
import 'state/finance_controller.dart';
import 'ui/app_shell.dart';
import 'ui/screens/auth/login_screen.dart';
import 'ui/screens/settings/cloud_import.dart';
import 'ui/theme.dart';

/// Preferência de tema compartilhada acima do [MaterialApp].
final themeMode = ValueNotifier<ThemeMode>(ThemeMode.system);

ThemeMode parseThemeMode(String s) => switch (s) {
  'light' => ThemeMode.light,
  'dark' => ThemeMode.dark,
  _ => ThemeMode.system,
};

class FinancasApp extends StatelessWidget {
  const FinancasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) {
        if (!CloudConfig.enabled) {
          return AuthController(LocalAuthService())..init();
        }
        final api = ApiClient(CloudConfig.apiUrl);
        final auth = AuthController(CloudAuthService(api));
        api.onUnauthorized = auth.sessionExpired;
        return auth..init();
      },
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: themeMode,
        builder: (context, mode, _) {
          final user = context.watch<AuthController>().user;
          final app = MaterialApp(
            title: 'Finanças',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            locale: const Locale('pt', 'BR'),
            supportedLocales: const [Locale('pt', 'BR')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AuthGate(),
          );
          if (user == null) return app;
          // O estado financeiro fica acima do Navigator para que todas as
          // rotas o enxerguem; um repositório isolado por usuário.
          return ChangeNotifierProvider(
            key: ValueKey(user.id),
            create: (context) {
              final service = context.read<AuthController>().service;
              final cloud = service is CloudAuthService && !user.isDemo;
              return FinanceController(
                cloud
                    ? CloudFinanceRepository(user.id, ApiDocStore(service.api))
                    : LocalFinanceRepository(user.id),
                isDemo: user.isDemo,
                // Open Finance real só com a conta na nuvem (o servidor
                // guarda as credenciais da Pluggy); senão, sandbox.
                openFinance: cloud
                    ? PluggyOpenFinanceProvider(service.api)
                    : null,
              )..load();
            },
            child: app,
          );
        },
      ),
    );
  }
}

/// Mostra o login ou o app.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    if (auth.initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (auth.user == null) return const LoginScreen();
    return const CloudImportPrompt(child: AppShell());
  }
}
