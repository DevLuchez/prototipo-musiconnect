import 'package:flutter/material.dart';
import '../../data/models/providers/favorites_service.dart';

const _pink = Color(0xFFEC4899);

/// Coração de salvar/favoritar — mesmo estado em todas as telas (escuta o
/// [FavoritesService]).
///
/// [circle]: círculo com borda de 52px (rodapé do detalhe da oportunidade e
/// detalhe do pino do mapa). Sem ele, só o ícone (canto do card), vazado
/// cinza quando não está salvo pra não competir com o conteúdo do card.
class FavoriteButton extends StatelessWidget {
  final bool Function(FavoritesService) _isFavorite;
  final Future<bool> Function(FavoritesService) _toggle;
  final bool circle;

  FavoriteButton.opportunity(int id, {super.key, this.circle = false})
      : _isFavorite = ((f) => f.isOpportunitySaved(id)),
        _toggle = ((f) => f.toggleOpportunity(id));

  FavoriteButton.institution(String osmId, {super.key, this.circle = false})
      : _isFavorite = ((f) => f.isInstitutionFavorite(osmId)),
        _toggle = ((f) => f.toggleInstitution(osmId));

  Future<void> _onTap(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _toggle(FavoritesService.instance);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(
        content: Text('Não foi possível atualizar os favoritos. Tente novamente.'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: FavoritesService.instance,
      builder: (context, _) {
        final saved = _isFavorite(FavoritesService.instance);
        final icon = Icon(
          saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: saved || circle ? _pink : Colors.grey[400],
          size: circle ? 22 : 20,
        );
        final tooltip = saved ? 'Remover dos favoritos' : 'Salvar nos favoritos';

        if (circle) {
          return Tooltip(
            message: tooltip,
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(side: BorderSide(color: Color(0xFFE5E7EB))),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _onTap(context),
                splashColor: _pink.withOpacity(0.18),
                highlightColor: _pink.withOpacity(0.08),
                child: SizedBox(width: 52, height: 52, child: Center(child: icon)),
              ),
            ),
          );
        }

        // Área de toque maior que o ícone, sem depender do tamanho da linha
        // em que está (o card do carrossel tem altura fixa).
        return Tooltip(
          message: tooltip,
          child: InkResponse(
            onTap: () => _onTap(context),
            radius: 22,
            // Efeito do toque em rosa, no lugar do cinza padrão do Material.
            splashColor: _pink.withOpacity(0.18),
            highlightColor: _pink.withOpacity(0.08),
            child: Padding(padding: const EdgeInsets.all(6), child: icon),
          ),
        );
      },
    );
  }
}
