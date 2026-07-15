---                                                                                                                                                                                                                  
description: Rewrite unpushed commit messages into German                                                                                                                                                            
---
# Ungepushte Commits: Commit-Messages auf Deutsch umschreiben

Für alle lokalen Git-Commits, die noch nicht nach `origin` gepusht wurden: analysiere die Änderungen jedes Commits und ersetze die Commit-Message durch eine präzise deutsche Message, die den Inhalt des Commits zusammenfasst.

## Vorgehen

### 1. Ungepushte Commits ermitteln

Führe parallel aus:

- `git status`
- `git rev-parse --abbrev-ref @{upstream}` (falls kein Upstream: `origin/$(git branch --show-current)` verwenden und prüfen, ob der Branch existiert)
- `git log --reverse --format='%H %s' @{upstream}..HEAD` (ältester Commit zuerst)
- `git log -10 --format='%s'` (für Stil-Orientierung)

Wenn keine ungepushten Commits vorhanden sind: kurz mitteilen und stoppen.

### 2. Jeden Commit analysieren

Für jeden ungepushten Commit (von alt nach neu):

- `git show --stat <sha>`
- `git show <sha>` (vollständiger Diff)

Verstehe, **was** geändert wurde und **warum** — nicht nur welche Dateien betroffen sind.

### 3. Deutsche Commit-Messages formulieren

Schreibe für jeden Commit eine neue Message auf **Deutsch**:

- Kurz und prägnant (typisch 1 Zeile Betreff, optional kurzer Body bei komplexen Änderungen)
- Beschreibt die **Absicht** der Änderung, nicht nur die Dateiliste
- Orientiere dich am Stil der letzten Commits im Repository (z. B. `Radar-Live: …`, `Radar-Empfindlichkeit: …`)
- Imperativ oder beschreibend — konsistent mit dem Repo-Stil
- Kein Präfix wie `fix:`/`feat:` unless das Repo das bereits so macht

Zeige dem Nutzer vor dem Umschreiben eine Übersicht:

| Commit (kurz) | Alte Message | Neue Message (DE) |
|---|---|---|

### 4. Commit-Messages umschreiben

**Wichtig:** Keine interaktiven Git-Befehle (`-i`). Nutze nicht-interaktive Methoden.

#### Ein ungepushten Commit

```bash
git commit --amend -m "$(cat <<'EOF'
Neue deutsche Commit-Message
EOF
)"
```

#### Mehrere ungepushte Commits

Nutze einen nicht-interaktiven Rebase mit `GIT_SEQUENCE_EDITOR` und `GIT_EDITOR`:

1. Erstelle ein temporäres Shell-Skript als `GIT_EDITOR`, das anhand eines Zählers die vorbereiteten Messages nacheinander in die Commit-Message-Datei schreibt (Commits werden während des Rebase in chronologischer Reihenfolge bearbeitet).
2. Setze `GIT_SEQUENCE_EDITOR` so, dass alle `pick`-Zeilen in `reword` geändert werden (z. B. via `sed`).
3. Führe aus:

```bash
GIT_SEQUENCE_EDITOR="..." GIT_EDITOR="..." git rebase -i @{upstream}
```

4. Lösche temporäre Skripte nach erfolgreichem Rebase.

Falls der Rebase fehlschlägt: `git rebase --abort` ausführen, Fehler erklären und nicht weiter forcieren.

### 5. Verifizieren

- `git log --format='%h %s' @{upstream}..HEAD` — alle Messages sollten auf Deutsch und sinnvoll sein
- `git status` — Branch sollte weiterhin ahead of upstream sein (gleiche Anzahl Commits)

## Sicherheitsregeln

- **Nur** Commits umschreiben, die noch nicht gepusht sind (`@{upstream}..HEAD`)
- **Nicht** pushen, es sei denn, der Nutzer bittet explizit darum
- **Nicht** `git config` ändern
- **Nicht** `--force` oder `--no-verify` verwenden
- Bei Unsicherheit über den Upstream-Branch: den Nutzer fragen, bevor Messages geändert werden
