# VaultSearch automatisieren

*English: [Automating VaultSearch](automation.md)*

VaultSearch lässt sich auch ohne Fenster nutzen: mit **Siri**, **Spotlight**, der **Kurzbefehle**-App und **AppleScript**. Alle durchsuchen denselben Index wie das Fenster und verwenden dieselben Export-Einstellungen (Pandoc, Vorlagen, Exportordner).

- [Vorab](#vorab)
- [Siri und Spotlight](#siri-und-spotlight)
- [Kurzbefehle](#kurzbefehle)
  - [Aktionen](#aktionen)
  - [Notizen finden](#notizen-finden)
  - [Notizen filtern](#notizen-filtern)
  - [Beispiele für Kurzbefehle](#beispiele-für-kurzbefehle)
- [AppleScript](#applescript)
  - [Verzeichnis](#verzeichnis)
  - [Beispiele für AppleScript](#beispiele-für-applescript)
- [Fehlerbehebung](#fehlerbehebung)

## Vorab

- VaultSearch braucht macOS 27 und einen ausgewählten Vault.
- Läuft VaultSearch nicht, startet macOS die App. Die erste Anfrage wartet, bis der Vault eingelesen ist; bei einem großen Vault kann das ein paar Sekunden dauern.
- Die Aktionen **lesen** den Vault nur. Einzige Ausnahme ist **Notizliste im Vault sichern** (AppleScript: `save to vault`). Sie legt eine Listen-Notiz im Exportordner an, wie **Ablage ▸ Treffer im Vault sichern**.

## Siri und Spotlight

**Siri** versteht Anfragen in deinen eigenen Worten, zum Beispiel:

- „Notizen in VaultSearch finden“
- „Zeig mir meine Notizen zum Budget-Meeting in VaultSearch“
- „Exportier diese Notiz als PDF“ – solange eine Notiz in der Vorschau zu sehen ist, weiß Siri, welche mit „diese“ gemeint ist.
- „Öffne das in Obsidian“

**Spotlight** zeigt nach dem ersten Einlesen die Notizen deines Vaults. Wählst du eine aus, öffnet sie sich in Obsidian. Titel, Text, Tags und Daten landen dafür im Spotlight-Index deines Macs.

## Kurzbefehle

### Aktionen

Such in der Kurzbefehle-App nach „VaultSearch“:

| Aktion | Eingabe | Ergebnis |
|---|---|---|
| **Notizen finden** | Filterzeilen | Notizen |
| **Notizen filtern** | Notizen (optional) und ein Kriterium | Notizen |
| **In VaultSearch anzeigen** | Suchbegriff | – (zeigt die Treffer im Fenster) |
| **Notiz in Obsidian öffnen** | eine Notiz | – |
| **Notiz exportieren** | eine Notiz, Format | Datei |
| **Notizliste exportieren** | Notizen, Format, Titel (optional) | Datei |
| **Notizliste im Vault sichern** | Notizen, Titel (optional) | die neue Listen-Notiz |

Formate sind PDF, Word, OpenDocument, Rich Text, HTML, EPUB (braucht Pandoc) und Markdown. Die Export-Aktionen schreiben eine vorläufige Datei; gib sie an **Datei sichern**, **Teilen**, **Mail** usw. weiter.

### Notizen finden

**Notizen finden** funktioniert wie „Notizen finden“ bei Apples Notizen oder „Erinnerungen finden“: Du fügst Filterzeilen hinzu und wählst, ob **alle** oder **beliebige** davon zutreffen müssen.

| Filter | Vergleiche |
|---|---|
| Name | enthält, ist, beginnt mit |
| Text | enthält |
| Tags | enthält – findet auch verschachtelte Tags (`idee` findet `projekt/idee`) |
| Eigenschaften | enthält – `status: aktiv` prüft eine Eigenschaft, `aktiv` allein alle |
| Ordnerpfad | ist, beginnt mit (= Ordner und Unterordner), enthält |
| Erstellungsdatum, Änderungsdatum | ist, ist vor, ist nach, ist zwischen sowie die relativen Zeiträume der Kurzbefehle-App wie „in den letzten 7 Tagen“ |

Unter den Filtern stellst du die Sortierung (Name, Erstellungs- oder Änderungsdatum) und eine Höchstzahl ein.

### Notizen filtern

**Notizen filtern** liest sich wie ein Satz. Im ersten Menü wählst du das Kriterium, der Rest des Satzes passt sich an, und die Menüs werden aus deinem Vault gefüllt:

- *Notizen* nach **Text** *budget* in *Nur Titel* filtern
- *Notizen* nach **Tag** *project/haushaltsbuch* filtern
- *Notizen* nach **Tag im Text** *todo* filtern – `#todo` oder `[[todo]]` im Text
- *Notizen* nach **Eigenschaft** *status* mit *aktiv* filtern – ohne Wert: alle Notizen mit dieser Eigenschaft
- *Notizen* nach **Ordner** *02 Projekte* filtern – mit Unterordnern
- *Notizen* nach **Änderungsdatum** *In den letzten 7 Tagen* filtern – oder *Am*, *Seit*, *Vor dem*, *Zwischen* mit Datum

Ohne Notizen als Eingabe wird der ganze Vault durchsucht. Mehrere **Notizen filtern** hintereinander verbinden ihre Kriterien mit UND, weil jede nur die Notizen der vorherigen behält, die auch passen. Für ODER nimm **Notizen finden** mit *Beliebige*.

### Beispiele für Kurzbefehle

**Wochenrückblick als PDF**

1. **Notizen finden** – *Änderungsdatum* ist in den letzten *7 Tagen*; sortiert nach *Änderungsdatum*, neueste zuerst.
2. **Notizliste exportieren** – *Notizen* aus Schritt 1, *PDF*, Titel „Wochenrückblick“.
3. **Datei sichern** – z. B. in *Dokumente/Rückblicke*.

**Aktive Projekt-Notizen als Listen-Notiz im Vault**

1. **Notizen filtern** – nach *Tag* `projekt`.
2. **Notizen filtern** – *Notizen* aus Schritt 1 nach *Eigenschaft* `status` mit `aktiv`.
3. **Notizliste im Vault sichern** – Titel „Aktive Projekte“.

Die Listen-Notiz erscheint im Exportordner des Vaults und öffnet sich in Obsidian wie jede andere Notiz.

**Eine Notiz als Word-Dokument verschicken**

1. **Notizen finden** – *Name* ist `Budget 2026`; Höchstzahl 1.
2. **Notiz exportieren** – *Word*.
3. **E-Mail senden** – mit der Datei als Anhang.

**Die Notizen von heute im Fenster**

1. **In VaultSearch anzeigen** – `geändert:heute`.

In den Details des Kurzbefehls kannst du ihn in die Menüleiste legen oder ihm einen Tastaturkurzbefehl geben.

## AppleScript

Das Verzeichnis öffnest du im Skripteditor mit **Ablage ▸ Verzeichnis öffnen … ▸ VaultSearch**. Die Beispiele unten laufen im Skripteditor oder im Terminal mit `osascript`. Die Befehle und Eigenschaften sind, wie bei AppleScript üblich, englisch.

### Verzeichnis

**Programm (application)**

| Begriff | Bedeutung |
|---|---|
| `notes` | alle Notizen des Vaults (`every note`, `note "Plan"`, `note id "/…/Plan.md"`, `every note whose …`) |
| `vault path` | POSIX-Pfad des Vault-Ordners |
| `indexing` | `true`, solange der Vault eingelesen wird |

**note** – alle Eigenschaften sind nur lesbar

| Eigenschaft | Bedeutung |
|---|---|
| `name` | Titel (Dateiname ohne `.md`) |
| `id`, `path` | POSIX-Pfad der Datei |
| `folder` | Ordner im Vault, z. B. `Projekte/2026` |
| `tags` | Liste der Tags aus dem Frontmatter |
| `frontmatter` | die übrigen Frontmatter-Eigenschaften als Record; Schlüssel mit Strichen lesen: `|status| of fm` |
| `creation date`, `modification date` | Datum aus dem Frontmatter, falls vorhanden, sonst Datum der Datei |
| `content` | Markdown-Text ohne Frontmatter |
| `Obsidian URL` | `obsidian://`-Link zur Notiz |

**Befehle**

| Befehl | Ergebnis |
|---|---|
| `search` *Text* [`limit` *n*] | Notizen, beste Treffer zuerst; Syntax des Suchfelds; wartet auf den Index |
| `show search` *Text* | zeigt die Treffer im Fenster |
| `open in Obsidian` *Notiz(en)* | – |
| `export` *Notiz* [`as` *Format*] [`to` *Datei*] | das Dokument einer Notiz |
| `export` *Liste von Notizen* [`as` *Format*] [`to` *Datei*] [`titled` *Text*] | ein Listendokument |
| `save to vault` *Liste von Notizen* [`titled` *Text*] | die neue Listen-Notiz im Exportordner |
| `reindex` | liest den Vault neu ein und wartet, bis er fertig ist |

*Format* ist `PDF` (Standard), `Word`, `OpenDocument`, `rich text`, `HTML`, `EPUB` oder `Markdown`. Ohne `to` landet die Datei im vorläufigen Ordner, und der Befehl gibt sie zurück.

`search` wartet, bis der Vault eingelesen ist. `every note` liefert, was bis dahin gelesen wurde. Startet dein Skript VaultSearch, frag erst `indexing` ab oder beginne mit `search`.

Die Suchsyntax ist dieselbe wie im Suchfeld, auf Deutsch wie auf Englisch: `search "tag:idee geändert:letzte 30 Tage"` funktioniert genauso wie `search "tag:idea modified:last 30 days"`.

### Beispiele für AppleScript

**Suchen und auflisten**

```applescript
tell application "VaultSearch"
    set treffer to search "tag:idee geändert:letzte 30 Tage" limit 10
    set titel to {}
    repeat with n in treffer
        set end of titel to (name of n) & " – " & (folder of n)
    end repeat
end tell
set AppleScript's text item delimiters to linefeed
return titel as text
```

**Wochenrückblick als PDF auf dem Schreibtisch**

```applescript
set ziel to (POSIX path of (path to desktop)) & "Wochenrückblick.pdf"
tell application "VaultSearch"
    set treffer to search "geändert:letzte 7 Tage"
    export treffer as PDF to POSIX file ziel titled "Wochenrückblick"
end tell
```

**Alle Notizen eines Ordners einzeln als Word exportieren**

```applescript
set zielordner to (POSIX path of (path to documents folder)) & "Export/"
do shell script "mkdir -p " & quoted form of zielordner
tell application "VaultSearch"
    repeat with n in (every note whose folder starts with "Projekte/2026")
        export n as Word to POSIX file (zielordner & (name of n) & ".docx")
    end repeat
end tell
```

**Frontmatter lesen**

```applescript
tell application "VaultSearch"
    set fm to frontmatter of note "Budget 2026"
end tell
try
    return |status| of fm
on error
    return "kein Status"
end try
```

**Listen-Notiz im Vault sichern und zeigen**

```applescript
tell application "VaultSearch"
    set treffer to search "tag:projekt status:aktiv"
    set liste to save to vault treffer titled "Aktive Projekte"
end tell
-- Die Listen-Notiz ist eine Markdown-Datei im Vault; Obsidian zeigt sie wie jede Notiz.
tell application "Finder" to reveal liste
```

**Die drei zuletzt geänderten Notizen in Obsidian öffnen**

```applescript
tell application "VaultSearch"
    open in Obsidian (search "" limit 3)
end tell
```

**Aus dem Terminal**

```sh
osascript -e 'tell application "VaultSearch" to name of every note whose name contains "Budget"'
```

## Fehlerbehebung

**Die Aktionen erscheinen nicht in der Kurzbefehle-App.**
Beende die Kurzbefehle-App (⌘Q) und öffne sie neu. Wenn du VaultSearch selbst baust: macOS liest die Aktionen nur neu ein, wenn sich die Build-Nummer ändert, und ältere Kopien von VaultSearch mit derselben Version können die neuen Aktionen verdecken. Lösch alte Kopien und leere den Papierkorb.

**Ein Kurzbefehl läuft endlos oder meldet „interner Fehler“.**
VaultSearch muss mit einem Entwickler-Team signiert sein; siehe [Developer Guide](development.md#siri-shortcuts-and-spotlight).

**„Es gibt keine Notizen zum Sichern oder Exportieren.“**
Die Suche oder der Filter hat nichts gefunden, oder eine im Skript genannte Notiz gibt es nicht (Schreibweise von `note "…"` prüfen).

**AppleScript kennt die Begriffe nicht.**
Begriffe wie `folder` oder `frontmatter` funktionieren nur innerhalb von `tell application "VaultSearch"`. Felder eines Records, den du von VaultSearch bekommen hast, liest du nach `set`, wie im Frontmatter-Beispiel.
