import 'package:flutter/material.dart';
import '../../../core/monitoring.dart';
import '../../widgets/auth/auth_common.dart';
import '../../widgets/visitor_invite.dart';
import 'profile_screen.dart';

/// Aba Perfil no modo visitante: o que a conta libera, com Criar conta /
/// Entrar, e a chave de dados de uso — que vale também para quem visita.
class VisitorProfileScreen extends StatelessWidget {
  const VisitorProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [kAuthPurple, kAuthPink],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_rounded, color: Colors.white, size: 30),
              ),
              const SizedBox(height: 14),
              const Text(
                'Você está visitando o MusiConnect',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: kAuthTextDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Com uma conta cadastrada, você também tem:',
                style: TextStyle(fontSize: 14, color: Colors.grey[600], height: 1.4),
              ),
              const SizedBox(height: 14),
              const _Benefit(
                icon: Icons.auto_awesome_rounded,
                title: 'Match',
                text: 'O quanto cada oportunidade combina com o seu perfil, e a '
                    'lista das que mais combinam com você.',
              ),
              const _Benefit(
                icon: Icons.favorite_rounded,
                title: 'Favoritos',
                text: 'Salve oportunidades e instituições para acompanhar mais de perto.',
              ),
              const _Benefit(
                icon: Icons.access_time_rounded,
                title: 'Prazos',
                text: 'O Início avisa quando uma oportunidade salva está para '
                    'fechar.',
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: AuthPrimaryButton(
                  label: 'Criar conta',
                  onPressed: () => openSignup(context),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: AuthOutlineButton(
                  label: 'Entrar',
                  onPressed: () => openLogin(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ValueListenableBuilder<bool>(
          valueListenable: Monitoring.usageDataEnabled,
          builder: (context, enabled, _) => UsageDataCard(
            enabled: enabled,
            onChanged: Monitoring.setUsageDataEnabled,
          ),
        ),
      ],
    );
  }
}

class _Benefit extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;

  const _Benefit({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: kAuthPink.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 18, color: kAuthPink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title: ',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: kAuthTextDark),
                  ),
                  TextSpan(text: text),
                ],
              ),
              style: TextStyle(fontSize: 13.5, color: Colors.grey[700], height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
