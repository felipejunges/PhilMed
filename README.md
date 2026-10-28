# PhilMed

Lembrete de horário de medicamentos em Flutter. Feito principalmente para Android, com suporte opcional a Linux.

## Funcionalidades

- **Medicamentos**: nome, princípio ativo, dosagem (mg, mcg, UI…), forma (comprimido, cápsula, gota, ml…), observações, cor, ativo/inativo.
- **Horários (posologia)**: um medicamento pode ter vários agendamentos, cada um com:
  - frequência: diariamente, a cada N dias, em dias da semana ou a cada N horas;
  - um ou mais horários no dia, quantidade por dose (aceita frações), data de início e de término (opcional).
- **Avisos no Android** com os botões **Tomei**, **Adiar 15 min** e **Adiar…** (5, 15, 30 ou 60 min). Tocar no aviso abre o app com todas as opções.
- **Registro de dose**: em cada dose você informa a data e hora reais e a proporção tomada (inteira, 1/2, 1/3, 1/4, 3/4, ou qualquer valor como "1 1/2"). Também dá para marcar a dose como *pulada*. Os registros podem ser editados e excluídos na Agenda, no Histórico ou na tela do medicamento.
- **Dose avulsa**: registra uma dose fora dos horários previstos.
- **Estoque (opcional)**: cada dose tomada é descontada do estoque. Editar ou excluir uma dose devolve a quantidade. Você pode **reinformar** o estoque atual, **adicionar** uma compra e definir um limite para o alerta de estoque baixo.
- **Backup**: em Configurações você pode exportar e importar o arquivo SQLite do banco.
- **Backup automático** (ligado por padrão): grava `philmed-auto-AAAAMMDD.db` em `Download/PhilMed` (no Linux, `~/Downloads/PhilMed`). Ele é atualizado poucos segundos depois de cada alteração e guarda os últimos 7 dias. Por ficar fora da pasta do app, **sobrevive à desinstalação**. Antes de cada importação, o app também salva uma cópia `philmed-antes-importar-…db`.

> Terminologia: o app usa **"registro de dose"** no lugar de "lançamento". A lista desses registros é o **"histórico de doses"**.

## Executar

```bash
flutter pub get
flutter run                 # Android conectado
flutter run -d linux        # Linux
flutter build apk --release # gera build/app/outputs/flutter-apk/app-release.apk
adb install -r build/app/outputs/flutter-apk/app-release.apk  # atualiza mantendo os dados
flutter test
```

> ⚠️ Não use `flutter install` para atualizar o app: ele desinstala a versão anterior antes e **apaga os dados**. Use `flutter run` ou `adb install -r`.

No Linux é preciso ter `libsqlite3` instalado (`sudo apt install libsqlite3-0`).

## Observações sobre os avisos

- **Android**: os avisos usam alarmes exatos (`USE_EXACT_ALARM`) e ficam agendados para os próximos 14 dias. O agendamento é refeito sempre que o app abre ou que algum dado muda, e também após reiniciar o aparelho. Se o app ficar mais de 14 dias sem ser aberto, os avisos param. Em aparelhos com economia de bateria agressiva (Xiaomi, Samsung etc.), desative a otimização de bateria para o PhilMed.
- **Linux**: não há agendamento pelo sistema, então os avisos só aparecem enquanto o app estiver aberto.
- O release ainda é assinado com a chave de debug (`android/app/build.gradle.kts`). Configure uma chave própria antes de distribuir.

## Estrutura

| Arquivo | Conteúdo |
|---|---|
| `lib/models.dart` | Medicamento, agendamento, registro de dose, adiamento e formatação |
| `lib/db.dart` | Banco SQLite (sqflite / sqflite_ffi no Linux), estoque, exportação e importação |
| `lib/scheduler.dart` | Cálculo dos horários previstos e montagem da agenda |
| `lib/notifications.dart` | Avisos, ações dos botões (inclusive com o app fechado) e adiamentos |
| `lib/screens/` | Agenda, Medicamentos, Histórico, formulários e Configurações |
