import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:pingit/providers/device_provider.dart';
import 'package:pingit/screens/home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigated = false;

  @override
  Widget build(BuildContext context) {
    // Watch loading state inside build, where context.select is allowed
    final isLoading = context.select<DeviceProvider, bool>((p) => p.isLoading);

    if (!isLoading && !_navigated) {
      _navigated = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, animation, __, child) {
              return FadeTransition(opacity: animation, child: child);
            },
            transitionDuration: const Duration(milliseconds: 800),
          ),
        );
      });
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.shield_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scaleXY(end: 1.1, duration: 1.5.seconds)
            .then()
            .shimmer(duration: 2.seconds),
            
            const SizedBox(height: 32),
            
            Text(
              'PingIT',
              style: GoogleFonts.inter(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -1.0,
              ),
            ).animate().fadeIn(duration: 600.ms).slideY(begin: 0.2, end: 0),
            
            const SizedBox(height: 8),
            
            Text(
              'Infrastructure Monitoring',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                letterSpacing: 0.5,
              ),
            ).animate().fadeIn(delay: 200.ms, duration: 600.ms),

            const SizedBox(height: 48),

            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ).animate().fadeIn(delay: 500.ms),
          ],
        ),
      ),
    );
  }
}
