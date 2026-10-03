import 'package:flutter/material.dart';
import '../../../data/models/providers/auth_service.dart';
import '../../../data/models/providers/favorites_service.dart';
import '../../../data/models/providers/match_count_service.dart';
import '../../widgets/auth/auth_common.dart';
import '../../widgets/auth/logout_flow.dart';
import '../auth/welcome_screen.dart';
import 'change_password_screen.dart';
import 'edit_profile_screen.dart';

// Cor dos chips de "Ramo de atuação" — diferencia visualmente de
// "Instrumentos" (rosa) sem sair da paleta Tailwind já usada no app.
const _kRamoBlue = Color(0xFF2563EB);

/// Aba Perfil: dados do usuário logado, com acesso a editar perfil, trocar
/// senha, sair ou excluir a conta.
///
/// Mantém seu próprio estado de [AuthUser] (inicializado com o valor
/// recebido no login/boot) — como esta tela fica viva dentro do
/// `IndexedStack` de [MainNavigation], atualizar esse estado localmente
/// após uma edição já é suficiente para refletir os dados novos, sem
/// precisar de um gerenciador de estado global.
class ProfileScreen extends StatefulWidget {
  final AuthUser user;

  // Atalhos dos números do card de estatísticas (recebidos do
  // MainNavigation): Matches → Matcher em "Minhas oportunidades"; salvas e
  // favoritas → as mesmas telas do menu lateral.
  final VoidCallback? onOpenMatches;
  final VoidCallback? onOpenSavedOpportunities;
  final VoidCallback? onOpenFavoriteInstitutions;

  // Avisa o MainNavigation depois de editar o perfil (ex: o cabeçalho do
  // menu lateral mostra o nome atualizado).
  final ValueChanged<AuthUser>? onUserChanged;

  const ProfileScreen({
    super.key,
    required this.user,
    this.onOpenMatches,
    this.onOpenSavedOpportunities,
    this.onOpenFavoriteInstitutions,
    this.onUserChanged,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  late AuthUser _user = widget.user;

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Perfil editado fora daqui (ex: "Complete seu perfil" do Início).
    if (oldWidget.user != widget.user) _user = widget.user;
  }

  String get _initial => _user.name.isNotEmpty ? _user.name[0].toUpperCase() : '?';

  List<String> get _ramoLabels => [
        if (_user.isProfessional) 'Profissional',
        if (_user.isStudent) 'Estudante',
      ];

  String get _location {
    final parts = [_user.city, _user.state, _user.country]
        .where((p) => p != null && p.isNotEmpty)
        .toList();
    return parts.isEmpty ? 'Não informada' : parts.join(', ');
  }

  Future<void> _editProfile() async {
    final updated = await Navigator.of(context).push<AuthUser>(
      MaterialPageRoute(builder: (_) => EditProfileScreen(user: _user)),
    );
    if (updated == null) return;
    setState(() => _user = updated);
    widget.onUserChanged?.call(updated);
    // Instrumentos/ramo/localização mudam o match de cada oportunidade.
    MatchCountService.instance.refresh();
  }

  void _changePassword() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
    );
  }

  // Mesmo fluxo do "Sair" do menu lateral.
  Future<void> _logout() => confirmAndLogout(context);

  Future<void> _deleteAccount() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null || password.isEmpty) return;
    try {
      await _authService.deleteAccount(password);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Center(
          child: Container(
            width: 104,
            height: 104,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kAuthPurple, kAuthPink],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                _user.name,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: kAuthTextDark,
                ),
              ),
            ),
            const SizedBox(width: 5),
            // Chegar nesta tela já exige e-mail confirmado (login recusa
            // contas pendentes) — o selo é sempre verdadeiro aqui, sem
            // precisar consultar nada além do fato de estar logado.
            const Tooltip(
              message: 'E-mail verificado',
              child: Icon(Icons.verified_rounded, size: 17, color: kAuthPink),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _user.email,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
        const SizedBox(height: 22),
        _StatsCard(
          onOpenMatches: widget.onOpenMatches,
          onOpenSavedOpportunities: widget.onOpenSavedOpportunities,
          onOpenFavoriteInstitutions: widget.onOpenFavoriteInstitutions,
        ),
        const SizedBox(height: 16),
        _InfoCard(
          instruments: _user.instruments,
          ramoLabels: _ramoLabels,
          location: _location,
          onEdit: _editProfile,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 15, color: Colors.red[800]),
            const SizedBox(width: 6),
            Text(
              'ZONA DE ATENÇÃO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.red[800],
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _DangerCard(
          onChangePassword: _changePassword,
          onLogout: _logout,
          onDeleteAccount: _deleteAccount,
        ),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'MusiConnect v1.0.0 · Build 1',
            style: TextStyle(fontSize: 11, color: Colors.grey[400]),
          ),
        ),
      ],
    );
  }
}

class _StatsCard extends StatelessWidget {
  final VoidCallback? onOpenMatches;
  final VoidCallback? onOpenSavedOpportunities;
  final VoidCallback? onOpenFavoriteInstitutions;

  const _StatsCard({
    this.onOpenMatches,
    this.onOpenSavedOpportunities,
    this.onOpenFavoriteInstitutions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      // Padding menor que antes (16 → 8): o resto vem da área de toque de
      // cada número, pra o efeito do toque ocupar a altura toda do card.
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          // Oportunidades abertas com match alto (= total de "Minhas
          // oportunidades"); "–" enquanto carrega ou se a consulta falhar.
          Expanded(
            child: ListenableBuilder(
              listenable: MatchCountService.instance,
              builder: (context, _) => _StatItem(
                value: '${MatchCountService.instance.count ?? '–'}',
                label: 'Matches',
                onTap: onOpenMatches,
              ),
            ),
          ),
          Container(width: 1, height: 30, color: Colors.grey[200]),
          // Oportunidades salvas / instituições favoritas — atualizam na
          // hora quando um coração é marcado em qualquer tela.
          Expanded(
            child: ListenableBuilder(
              listenable: FavoritesService.instance,
              builder: (context, _) => _StatItem(
                value: '${FavoritesService.instance.opportunityCount}',
                label: 'Oport. salvas',
                onTap: onOpenSavedOpportunities,
              ),
            ),
          ),
          Container(width: 1, height: 30, color: Colors.grey[200]),
          Expanded(
            child: ListenableBuilder(
              listenable: FavoritesService.instance,
              builder: (context, _) => _StatItem(
                value: '${FavoritesService.instance.institutionCount}',
                label: 'Inst. favoritas',
                onTap: onOpenFavoriteInstitutions,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String value;
  final String label;
  // Leva à lista correspondente — efeito do toque em rosa, igual ao coração.
  final VoidCallback? onTap;
  const _StatItem({required this.value, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: kAuthPink.withOpacity(0.18),
        highlightColor: kAuthPink.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kAuthTextDark),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[500]),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<String> instruments;
  final List<String> ramoLabels;
  final String location;
  final VoidCallback onEdit;

  const _InfoCard({
    required this.instruments,
    required this.ramoLabels,
    required this.location,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _InfoSection(
            icon: Icons.music_note_rounded,
            title: 'Instrumentos',
            child: instruments.isEmpty
                ? Text('Não informado', style: TextStyle(fontSize: 13, color: Colors.grey[500]))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: instruments.map((i) => _InfoChip(label: i)).toList(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Colors.grey[200]),
          ),
          _InfoSection(
            icon: Icons.work_outline_rounded,
            title: 'Ramo de atuação',
            child: ramoLabels.isEmpty
                ? Text('Não informado', style: TextStyle(fontSize: 13, color: Colors.grey[500]))
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children:
                        ramoLabels.map((r) => _InfoChip(label: r)).toList(),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Divider(height: 1, color: Colors.grey[200]),
          ),
          _InfoSection(
            icon: Icons.location_on_outlined,
            title: 'Localização',
            child: Text(location, style: const TextStyle(fontSize: 13.5, color: kAuthTextDark)),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: AuthOutlineButton(
              label: 'Editar perfil',
              leadingIcon: Icons.edit_outlined,
              onPressed: onEdit,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoSection extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final Widget child;

  const _InfoSection({
    required this.icon,
    this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: iconColor ?? Colors.grey[500]),
            const SizedBox(width: 6),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: kAuthTextDark,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final Color color;
  const _InfoChip({required this.label, this.color = kAuthPink});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

class _DangerCard extends StatelessWidget {
  final VoidCallback onChangePassword;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const _DangerCard({
    required this.onChangePassword,
    required this.onLogout,
    required this.onDeleteAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          _DangerRow(
            icon: Icons.lock_outline_rounded,
            title: 'Alterar senha',
            subtitle: 'Atualizar credenciais de acesso',
            onTap: onChangePassword,
          ),
          Divider(height: 1, indent: 20, endIndent: 20, color: Colors.grey[200]),
          _DangerRow(
            icon: Icons.logout_rounded,
            title: 'Sair da conta',
            subtitle: 'Desconectar deste dispositivo',
            onTap: onLogout,
          ),
          Divider(height: 1, indent: 20, endIndent: 20, color: Colors.grey[200]),
          _DangerRow(
            icon: Icons.delete_outline_rounded,
            title: 'Excluir conta',
            subtitle: 'Ação irreversível e permanente',
            onTap: onDeleteAccount,
            destructive: true,
          ),
        ],
      ),
    );
  }
}

class _DangerRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  const _DangerRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    // Destrutivo ("Excluir conta") no mesmo vermelho escuro do título
    // "ZONA DE ATENÇÃO".
    final titleColor = destructive ? Colors.red[800] : kAuthTextDark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: destructive ? Colors.red[800] : Colors.grey[600]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: titleColor)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: destructive ? Colors.red[800] : Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: Colors.grey[300], size: 20),
          ],
        ),
      ),
    );
  }
}

/// Diálogo que pede a senha atual para confirmar a exclusão da conta —
/// ação irreversível, não basta ter chegado até aqui com uma sessão válida.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AuthDialog(
      title: 'Excluir conta',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Essa ação é irreversível e permanente! Digite sua senha para confirmar a deleção da sua conta no MusiConnect.',
            style: TextStyle(fontSize: 13.5, color: Colors.grey[600], height: 1.4),
          ),
          const SizedBox(height: 16),
          AuthTextField(
            label: 'Senha',
            hint: 'Digite sua senha',
            controller: _passwordController,
            isPassword: true,
          ),
        ],
      ),
      primaryLabel: 'Excluir',
      onPrimary: () => Navigator.of(context).pop(_passwordController.text),
      secondaryLabel: 'Cancelar',
      onSecondary: () => Navigator.of(context).pop(),
      destructive: true,
    );
  }
}
