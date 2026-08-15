import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../providers/app_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nicknameController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _registerAndContinue() async {
    final nickname = _nicknameController.text.trim();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final idToken = await ref
          .read(localIdentityStoreProvider)
          .loadOrCreateRegistrationToken(nickname: nickname);
      final session = await ref.read(gameApiDataSourceProvider).register(
        nickname: nickname,
        idToken: idToken,
      );
      await ref.read(authSessionProvider.notifier).saveSession(session);
      await ref.read(onboardingCompletedProvider.notifier).setEnabled(true);
      ref.read(nicknameProvider.notifier).state = nickname;
      if (!mounted) {
        return;
      }
      context.go(AppRoute.map);
    } on DioException catch (error) {
      _showError(_humanizeRegisterError(error));
    } on FormatException catch (error) {
      _showError(error.message);
    } catch (_) {
      _showError('Registration failed because of a network error.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  String _humanizeRegisterError(DioException error) {
    final statusCode = error.response?.statusCode;
    final message = _extractServerMessage(error.response?.data);

    if (statusCode == 400 &&
        message.toLowerCase().contains('nickname') &&
        message.toLowerCase().contains('use')) {
      return 'Nickname is already taken.';
    }

    if (message.toLowerCase().contains('idtoken')) {
      return 'Missing idToken.';
    }

    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout ||
        error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.unknown) {
      return 'Registration failed because of a network error.';
    }

    return message.isNotEmpty ? message : 'Registration failed.';
  }

  String _extractServerMessage(dynamic data) {
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String) {
        return message;
      }
      if (message is List && message.isNotEmpty) {
        return message.first.toString();
      }
    }
    return data?.toString() ?? '';
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final authSessionAsync = ref.watch(authSessionProvider);
    final nickname = ref.watch(nicknameProvider);

    final existingSession = authSessionAsync.valueOrNull;
    if (existingSession != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.go(AppRoute.map);
        }
      });
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (authSessionAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Text(
                  'Welcome to Terrango',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Choose your nickname and jump straight into the tactical map. Your local sign-in identity will be paired automatically.',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: 'Nickname',
                    hintText: 'Enter your operative name',
                  ),
                  onChanged: (value) =>
                      ref.read(nicknameProvider.notifier).state = value.trim(),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Nickname is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isSubmitting || nickname.isEmpty
                      ? null
                      : _registerAndContinue,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                       : const Icon(Icons.rocket_launch),
                   label: Text(_isSubmitting ? 'Creating account...' : 'Quick registration and start'),
                ),
                const SizedBox(height: 12),
                Text(
                  'You will be taken directly to the Tactical Map after registration.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Spacer(flex: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
