# TriRoute

Гра про логістичну компанію: біржа вантажів, маршрути, хаби, ліцензії. Переноситься з HTML на **Godot 4.4** (GDScript).

- `godot/` — проєкт Godot. Відкрити: Godot 4.4 → Import → `godot/project.godot`.
- `legacy/` — поточна HTML-версія, еталон для переносу (`bash legacy/build.sh` → `legacy/dist/triroute.html`).
- `docs/MODULES.md` — карта модулів, порядок переносу й критерії готовності.

## Запуск

Відкрий `godot/project.godot` у Godot 4.7 і натисни F5: генерується світ і з'являється мапа (колесо — зум, перетягування — рух).
Кнопка «Перевірки» показує, що генерація збігається з HTML-версією.

Скріншот без вікна (для порівняння з HTML):

```bash
godot --path godot -- --seed=777 --wfx=0 --cam=2,1,3 --shot=/tmp/godot.png
node legacy/tests/mapshot.js 777 /tmp/html.png 2,1,3
```

## Тести

```bash
godot --headless --path godot -s res://tests/run_tests.gd
```
