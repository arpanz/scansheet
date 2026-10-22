library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/ss.dart';
import 'steps/step1_welcome.dart';
import 'steps/step2_usecase.dart';
import 'steps/step3_destination.dart';
import 'steps/step4_signin.dart';
import 'steps/step5_camera.dart';

export 'onboarding_flow.dart' show OnboardingScreen;

enum OnbStep { welcome, usecase, destination, signin, camera }

class OnbState {
  String? selectedTemplateId;
  String destination = 'new';
  String? pickedSpreadsheetId;
  String? pickedSpreadsheetTitle;
  bool signinFromNew = true;
}

class OnbStateScope extends InheritedWidget {
  final OnbState state;
  final _OnboardingFlowState flow;
  const OnbStateScope({
    super.key,
    required this.state,
    required this.flow,
    required super.child,
  });
  static OnbStateScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OnbStateScope>()!;
  void goNext(BuildContext context) => flow.goNext();
  void goBack(BuildContext context) => flow.goBack();
  void goTo(BuildContext context, OnbStep step) => flow.goTo(step);
  void insertSigninAndGo() => flow.insertSigninAndGo();
  void removeSigninAndGoCamera() => flow.removeSigninAndGoCamera();
  @override
  bool updateShouldNotify(OnbStateScope old) => true;
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  static const String _seenKey = 'onboarding_seen';
  static Future<bool> shouldShow() async =>
      !((await SharedPreferences.getInstance()).getBool(_seenKey) ?? false);
  static Future<void> markSeen() async =>
      (await SharedPreferences.getInstance()).setBool(_seenKey, true);
  static Future<void> reset() async =>
      (await SharedPreferences.getInstance()).remove(_seenKey);
  @override
  State<OnboardingScreen> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingScreen> {
  final _controller = PageController();
  final _state = OnbState();
  final List<OnbStep> _steps = [
    OnbStep.welcome,
    OnbStep.usecase,
    OnbStep.destination,
    OnbStep.camera,
  ];
  int _index = 0;
  void _animate(int index) {
    if (index < 0 || index >= _steps.length) return;
    HapticFeedback.selectionClick();
    setState(() => _index = index);
    _controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  void goNext() => _animate(_index + 1);
  void goBack() => _animate(_index - 1);
  void goTo(OnbStep step) => _animate(_steps.indexOf(step));
  void insertSigninAndGo() {
    setState(() {
      if (!_steps.contains(OnbStep.signin)) {
        _steps.insert(_steps.indexOf(OnbStep.camera), OnbStep.signin);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => goTo(OnbStep.signin));
  }

  void removeSigninAndGoCamera() {
    setState(() => _steps.remove(OnbStep.signin));
    WidgetsBinding.instance.addPostFrameCallback((_) => goTo(OnbStep.camera));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Onboarding is designed light-only (camera step is always dark).
    return Theme(data: AppTheme.lightTheme, child: Builder(builder: _build));
  }

  Widget _build(BuildContext context) {
    final active = _steps[_index];
    final dark = active == OnbStep.camera;
    return OnbStateScope(
      state: _state,
      flow: this,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: dark ? SsColors.night : context.ss.paper,
          body: SafeArea(
            child: Column(
              children: [
                if (active != OnbStep.welcome)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 24, 0),
                    child: SizedBox(
                      height: 44,
                      child: Row(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: goBack,
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: Icon(
                                LucideIcons.chevronLeft,
                                size: 22,
                                color: dark ? Colors.white : context.ss.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SsStepBar(
                              step: switch (active) {
                                OnbStep.usecase => 1,
                                OnbStep.destination => 2,
                                OnbStep.signin => 2,
                                OnbStep.camera => 3,
                                _ => 0,
                              },
                              total: 3,
                              dark: dark,
                            ),
                          ),
                          const SizedBox(width: 44),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: PageView.builder(
                    controller: _controller,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _steps.length,
                    itemBuilder: (context, i) => KeyedSubtree(
                      key: ValueKey(_steps[i]),
                      child: switch (_steps[i]) {
                        OnbStep.welcome => OnbWelcomeStep(
                          scope: OnbStateScope.of(context),
                        ),
                        OnbStep.usecase => OnbUsecaseStep(
                          scope: OnbStateScope.of(context),
                        ),
                        OnbStep.destination => OnbDestinationStep(
                          scope: OnbStateScope.of(context),
                        ),
                        OnbStep.signin => OnbSigninStep(
                          scope: OnbStateScope.of(context),
                        ),
                        OnbStep.camera => OnbCameraStep(
                          scope: OnbStateScope.of(context),
                        ),
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
