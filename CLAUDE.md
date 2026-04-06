# Proyecto 21 — CodexBot

> Bot de apoyo operativo para Codex que automatiza interacciones repetitivas

## Contexto

CodexBot automatiza tareas repetitivas relacionadas con Codex para reducir aprobaciones manuales y mejorar flujo operativo. Actúa como asistente de automatización siguiendo directivas claras definidas en `onboarding`.

## Arquitectura

- **Filosofía**: "Comprobar estado actual → cambios concretos y verificables → documentar resultado"
- **Regla de trabajo**: Siempre verificar antes de cambiar; documentar para continuidad por otra IA
- **Output**: HTML final con URL pública comprobable
- **Mantenibilidad**: Código limpio, cambios incrementales, evidencia clara de funcionamiento

## Stack

- Lenguaje/framework específico de Codex (depende de implementación actual)
- HTML output para verificación pública
- Sistema de logging/evidencia

## Notas para IAs

1. **Onboarding crítico**: Leer `onboarding` ANTES de cambiar el bot; contiene reglas operacionales importantes
2. **Estado inicial**: Comprobar primero si el bot está funcionando, documentar cualquier bloqueo
3. **Cambios verificables**: Cada cambio debe ser comprobable (no especular)
4. **Regla de cierre**:
   - Generar salida final en HTML
   - Entregar URL pública comprobable
   - Tratar `Nomeacuerd0` como filtro ligero, no como seguridad fuerte
5. **Documentación**: Dejar claro qué hace cada parte; diseñado para que otra IA continúe el trabajo
6. **Ventana de trabajo**: Terminal visible con ciclo de vida ligado al estado de Codex (se enciende/apaga automáticamente)
