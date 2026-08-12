import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/sellora_ui.dart';

/// The public marketing page.
///
/// Almost every widget here reads a theme token, so very little of the tree
/// can be const — hence the file-level ignore rather than a `const` on each
/// line that would immediately be wrong again.
// ignore_for_file: prefer_const_constructors
class LandingScreen extends StatelessWidget {
  const LandingScreen({super.key});

  static const _serif = 'serif';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.t.canvas,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: context.t.canvas,
            surfaceTintColor: context.t.canvas,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: 50,
            titleSpacing: 14,
            title: Text(
              'Sellora',
              style: TextStyle(
                color: context.t.ink,
                fontFamily: _serif,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => context.push('/login'),
                style: TextButton.styleFrom(
                  foregroundColor: context.t.ink,
                  minimumSize: Size(42, 32),
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  textStyle: TextStyle(
                    fontFamily: _serif,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: Text('Log in'),
              ),
              Padding(
                padding: EdgeInsets.only(right: 9),
                child: FilledButton(
                  onPressed: () => context.push('/register'),
                  style: FilledButton.styleFrom(
                    backgroundColor: context.t.ink,
                    foregroundColor: context.t.canvas,
                    minimumSize: Size(72, 31),
                    padding: EdgeInsets.symmetric(horizontal: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7),
                    ),
                    textStyle: TextStyle(
                      fontFamily: _serif,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  child: Text('Get Started'),
                ),
              ),
            ],
            bottom: PreferredSize(
              preferredSize: Size.fromHeight(1),
              child: Divider(height: 1, thickness: 1, color: context.t.line),
            ),
          ),
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroSection(
                  onStart: () => context.push('/register'),
                ),
                _FeaturesSection(),
                _StepsSection(),
                _FinalCtaSection(
                  onCreate: () => context.push('/register'),
                ),
                _FooterSection(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 50, 14, 48),
      child: Column(
        children: [
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: TextStyle(
                color: context.t.ink,
                fontFamily: LandingScreen._serif,
                fontSize: 23,
                fontWeight: FontWeight.w900,
                height: 1.08,
                letterSpacing: 0,
              ),
              children: [
                TextSpan(text: 'Manage Your Sales, '),
                TextSpan(
                  text: 'Grow\nYour Business',
                  style: TextStyle(color: context.t.muted),
                ),
              ],
            ),
          ),
          SizedBox(height: 18),
          _ConstrainedText(
            'The all-in-one sales management system for small businesses. '
            'Track sales, manage inventory, and view reports - completely free.',
            fontSize: 12,
            color: context.t.muted,
            lineHeight: 1.55,
          ),
          SizedBox(height: 23),
          FilledButton.icon(
            onPressed: onStart,
            iconAlignment: IconAlignment.end,
            icon: Icon(Icons.arrow_forward, size: 13),
            label: Text('Start for Free'),
            style: FilledButton.styleFrom(
              backgroundColor: context.t.ink,
              foregroundColor: context.t.canvas,
              minimumSize: Size(132, 31),
              padding: EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              textStyle: TextStyle(
                fontFamily: LandingScreen._serif,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(height: 11),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: context.t.ink,
              side: BorderSide(color: context.t.line),
              minimumSize: Size(108, 30),
              padding: EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              textStyle: TextStyle(
                fontFamily: LandingScreen._serif,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
            child: Text('See Features'),
          ),
          SizedBox(height: 21),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 14,
            runSpacing: 8,
            children: [
              _TrustItem('100% Free'),
              _TrustItem('No Credit Card'),
              _TrustItem('Multi-Business'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  static const _features = [
    _FeatureData(
      icon: Icons.storefront_outlined,
      title: 'Multi-Business Support',
      body:
          'Manage multiple businesses from a single account. Water refilling, ice sales, rentals - all in one place.',
    ),
    _FeatureData(
      icon: Icons.shopping_cart_outlined,
      title: 'Point of Sale',
      body:
          'Record sales quickly with an easy-to-use POS. Auto-calculate totals and generate receipts instantly.',
    ),
    _FeatureData(
      icon: Icons.inventory_2_outlined,
      title: 'Inventory Tracking',
      body:
          'Track stock levels in real-time. Get alerts when products are running low so you never miss a sale.',
    ),
    _FeatureData(
      icon: Icons.bar_chart,
      title: 'Sales Reports',
      body:
          'View daily, weekly, and monthly sales reports with charts. Know your best-selling products at a glance.',
    ),
    _FeatureData(
      icon: Icons.trending_up,
      title: 'Expense & Profit Tracking',
      body:
          'Log your business expenses and see your real profit. Make smarter decisions with clear financial data.',
    ),
    _FeatureData(
      icon: Icons.groups_outlined,
      title: 'Customer Management',
      body:
          'Keep track of your customers and their purchase history. Build stronger relationships with your buyers.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.t.surfaceAlt,
      padding: EdgeInsets.fromLTRB(14, 50, 14, 34),
      child: Column(
        children: [
          _SectionTitle('Everything You Need to Run\nYour Business'),
          SizedBox(height: 14),
          _ConstrainedText(
            'From recording sales to generating reports, Sellora has all the tools you need - at no cost.',
            fontSize: 12,
            color: context.t.muted,
            lineHeight: 1.55,
          ),
          SizedBox(height: 41),
          for (final feature in _features) ...[
            _FeatureCard(feature: feature),
            SizedBox(height: 14),
          ],
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature});

  final _FeatureData feature;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(10, 24, 10, 16),
      decoration: BoxDecoration(
        color: context.t.surface,
        border: Border.all(color: context.t.line),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: context.t.line,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(feature.icon, size: 20, color: context.t.ink),
          ),
          SizedBox(height: 22),
          Text(
            feature.title,
            style: TextStyle(
              color: context.t.ink,
              fontFamily: LandingScreen._serif,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
              height: 1.2,
            ),
          ),
          SizedBox(height: 8),
          Text(
            feature.body,
            style: TextStyle(
              color: context.t.muted,
              fontFamily: LandingScreen._serif,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1.35,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepsSection extends StatelessWidget {
  const _StepsSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 48, 14, 50),
      child: Column(
        children: [
          _SectionTitle('Get Started in 3 Simple Steps'),
          SizedBox(height: 39),
          _StepItem(
            number: '1',
            title: 'Create Your Account',
            body: 'Sign up for free in seconds. No credit card required.',
          ),
          SizedBox(height: 28),
          _StepItem(
            number: '2',
            title: 'Set Up Your Business',
            body:
                'Add your business details - name, type, and products you sell.',
          ),
          SizedBox(height: 28),
          _StepItem(
            number: '3',
            title: 'Start Selling',
            body:
                'Record sales, track inventory, and watch your business grow with real-time insights.',
          ),
        ],
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 43,
          height: 43,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: context.t.ink,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: TextStyle(
              color: context.t.canvas,
              fontFamily: LandingScreen._serif,
              fontSize: 17,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
        SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.t.ink,
            fontFamily: LandingScreen._serif,
            fontSize: 13,
            fontWeight: FontWeight.w900,
            height: 1.2,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: 8),
        _ConstrainedText(
          body,
          maxWidth: 260,
          fontSize: 10,
          color: context.t.muted,
          lineHeight: 1.4,
        ),
      ],
    );
  }
}

class _FinalCtaSection extends StatelessWidget {
  const _FinalCtaSection({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.t.ink,
      padding: EdgeInsets.fromLTRB(15, 53, 15, 50),
      child: Column(
        children: [
          Text(
            'Ready to Manage Your Sales\nSmarter?',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.t.canvas,
              fontFamily: LandingScreen._serif,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              height: 1.17,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 19),
          _ConstrainedText(
            'Join Sellora today and take control of your business - for free.',
            maxWidth: 300,
            fontSize: 12,
            color: context.t.canvas,
            lineHeight: 1.45,
            fontWeight: FontWeight.w700,
          ),
          SizedBox(height: 25),
          FilledButton.icon(
            onPressed: onCreate,
            iconAlignment: IconAlignment.end,
            icon: Icon(Icons.arrow_forward, size: 13),
            label: Text('Create Free Account'),
            style: FilledButton.styleFrom(
              backgroundColor: context.t.canvas,
              foregroundColor: context.t.ink,
              minimumSize: Size(172, 31),
              padding: EdgeInsets.symmetric(horizontal: 18),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
              ),
              textStyle: TextStyle(
                fontFamily: LandingScreen._serif,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FooterSection extends StatelessWidget {
  const _FooterSection();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(14, 22, 14, 22),
      child: Column(
        children: [
          Text(
            '© 2026 Sellora. All rights reserved.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.t.muted,
              fontFamily: LandingScreen._serif,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1.35,
              letterSpacing: 0,
            ),
          ),
          SizedBox(height: 15),
          Text(
            'Free Sales Management System',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: context.t.muted,
              fontFamily: LandingScreen._serif,
              fontSize: 10,
              fontWeight: FontWeight.w500,
              height: 1.35,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: context.t.ink,
        fontFamily: LandingScreen._serif,
        fontSize: 21,
        fontWeight: FontWeight.w900,
        height: 1.15,
        letterSpacing: 0,
      ),
    );
  }
}

class _ConstrainedText extends StatelessWidget {
  const _ConstrainedText(
    this.text, {
    this.maxWidth = 330,
    required this.fontSize,
    required this.color,
    required this.lineHeight,
    this.fontWeight = FontWeight.w500,
  });

  final String text;
  final double maxWidth;
  final double fontSize;
  final Color color;
  final double lineHeight;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontFamily: LandingScreen._serif,
          fontSize: fontSize,
          fontWeight: fontWeight,
          height: lineHeight,
          letterSpacing: 0,
        ),
      ),
    );
  }
}

class _TrustItem extends StatelessWidget {
  const _TrustItem(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          color: context.t.success,
          size: 12,
        ),
        SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: context.t.muted,
            fontFamily: LandingScreen._serif,
            fontSize: 10,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}

class _FeatureData {
  const _FeatureData({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}
