# TriRoute

Гра про логістичну компанію: біржа вантажів, маршрути, хаби, ліцензії. Переноситься з HTML на **Godot 4.4** (GDScript).

- `godot/` — проєкт Godot. Відкрити: Godot 4.4 → Import → `godot/project.godot`.
- `legacy/` — поточна HTML-версія, еталон для переносу (`bash legacy/build.sh` → `legacy/dist/triroute.html`).
- `docs/MODULES.md` — карта модулів, порядок переносу й критерії готовності.

## Тести

```bash
godot --headless --path godot -s res://tests/run_tests.gd
```
