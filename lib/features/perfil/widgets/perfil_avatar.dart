import 'dart:convert';
import 'package:flutter/material.dart';

import '../../../app/theme.dart';

/// Avatar do perfil. Prioridade da imagem:
/// 1. [fotoUrl] — foto enviada pelo usuário (Storage);
/// 2. [googlePhotoUrl] — foto da conta Google;
/// 3. iniciais do nome (fallback).
///
/// Se [onEditar] for fornecido, mostra o botão de câmera sobreposto.
class PerfilAvatar extends StatelessWidget {
  final String? fotoUrl;
  final String? googlePhotoUrl;
  final String nome;
  final double raio;
  final VoidCallback? onEditar;
  final bool enviando;

  const PerfilAvatar({
    super.key,
    required this.fotoUrl,
    required this.googlePhotoUrl,
    required this.nome,
    this.raio = 52,
    this.onEditar,
    this.enviando = false,
  });

  String? get _url {
    if (fotoUrl != null && fotoUrl!.isNotEmpty) return fotoUrl;
    if (googlePhotoUrl != null && googlePhotoUrl!.isNotEmpty) {
      return googlePhotoUrl;
    }
    return null;
  }

  String get _iniciais {
    final partes =
        nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '?';
    if (partes.length == 1) return partes.first[0].toUpperCase();
    return (partes.first[0] + partes.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    return SizedBox(
      width: raio * 2,
      height: raio * 2,
      child: Stack(
        children: [
          Container(
            width: raio * 2,
            height: raio * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            clipBehavior: Clip.antiAlias,
            child: url == null
                ? _fallbackIniciais()
                : Image(
                    image: url.startsWith('data:')
                        ? MemoryImage(base64Decode(url.split(',').last))
                        : NetworkImage(url) as ImageProvider,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _fallbackIniciais(),
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
          ),
          if (enviando)
            Container(
              width: raio * 2,
              height: raio * 2,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black38,
              ),
              child: const Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                ),
              ),
            ),
          if (onEditar != null)
            Positioned(
              right: 0,
              bottom: 0,
              child: Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: enviando ? null : onEditar,
                  child: const Padding(
                    padding: EdgeInsets.all(7),
                    child:
                        Icon(Icons.photo_camera, size: 16, color: Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fallbackIniciais() => Center(
        child: Text(
          _iniciais,
          style: TextStyle(
            fontSize: raio * 0.7,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      );
}
