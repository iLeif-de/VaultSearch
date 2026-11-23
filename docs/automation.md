# Automating VaultSearch

*Deutsch: [Automatisierung](automatisierung.md)*

VaultSearch can be used without its window: from **Siri**, **Spotlight**, the **Shortcuts** app and **AppleScript**. All of them search the same index as the window and use the same export settings (Pandoc, templates, export folder).

- [Before you start](#before-you-start)
- [Siri and Spotlight](#siri-and-spotlight)
  - [Siri with your own shortcuts (recommended)](#siri-with-your-own-shortcuts-recommended)
  - [Spotlight](#spotlight)
  - [Built-in Siri phrases](#built-in-siri-phrases)
- [Shortcuts](#shortcuts)
  - [Actions](#actions)
  - [Find Notes](#find-notes)
  - [Filter Notes](#filter-notes)
  - [Shortcut examples](#shortcut-examples)
  - [Interactive shortcuts](#interactive-shortcuts)
- [AppleScript](#applescript)
  - [Dictionary](#dictionary)
  - [AppleScript examples](#applescript-examples)
- [Troubleshooting](#troubleshooting)

## Before you start

- VaultSearch needs macOS 27 and a chosen vault.
- If VaultSearch is not running, macOS starts it. The first request waits until the vault has been read; with a large vault that can take a few seconds.
- The actions only **read** the vault. The one exception is **Save Note List to Vault** (AppleScript: `save to vault`), which adds a list note to the export folder, like **File ▸ Save Results to Vault**.

## Siri and Spotlight

**In short:** VaultSearch is most reliably reached with **your own shortcuts**, started by Siri by their name, and with **Spotlight**. Siri on the Mac does not always recognise the built-in phrases.

### Siri with your own shortcuts (recommended)

Siri runs every shortcut by its name. A shortcut called “Show household book” starts with “Hey Siri, show household book”. This works whether or not Siri knows VaultSearch's own phrases.

- Choose names Siri understands well. In German, **avoid the word “Notiz”**: Siri hands every sentence with it to Apple Notes.
- A shortcut can also **ask**, see [Interactive shortcuts](#interactive-shortcuts). Then one shortcut covers many searches.

### Spotlight

Spotlight lists the notes of your vault after the first index run:

1. Press ⌘ Space, type “va”, select VaultSearch and press **Tab**. A grey “VaultSearch” token appears on the left: Spotlight now searches only VaultSearch.
2. Type what you look for, e.g. “budget”. The list shows the matching notes with their folders.
3. **Return** opens the selected note in Obsidian.

Titles, text, tags and dates are added to the Spotlight index of your Mac for this.

### Built-in Siri phrases

VaultSearch comes with these phrases. Whether Siri recognises them is up to macOS; on the Mac they often end up with other Siri commands (web search, for example). If a phrase does not work for you, use your own shortcut.

| You say | VaultSearch |
|---|---|
| “Search in VaultSearch” – Siri asks “What should I search for?” | shows the results in the window |
| “Show notes tagged *idea* in VaultSearch” | shows the notes with the tag (nested tags too) |
| “Show folder *Projects* in VaultSearch” | shows the notes of the folder and its subfolders |
| “Open *Budget 2026* with VaultSearch” | opens the note in Obsidian |
| “Export *Budget 2026* with VaultSearch” | exports the note (as PDF) |

Say nested tags by their last part (“haushaltsbuch” for `project/haushaltsbuch`), folders likewise. Siri recognises notes only by their exact title. While a note is shown in the preview, Siri knows which note “this” means. The German phrases are listed in [Automatisierung](automatisierung.md#eingebaute-siri-sätze).

## Shortcuts

### Actions

In the Shortcuts app, search for “VaultSearch”:

| Action | Input | Result |
|---|---|---|
| **Find Notes** | filter rows | notes |
| **Filter Notes** | notes (optional) and one criterion | notes |
| **Show in VaultSearch** | search text | – (shows the results in the window) |
| **Show Tag in VaultSearch** | a tag | – (shows its notes in the window) |
| **Show Folder in VaultSearch** | a folder | – (shows its notes in the window) |
| **Open Note in Obsidian** | a note | – |
| **Export Note** | a note, format | file |
| **Export Note List** | notes, format, title (optional) | file |
| **Save Note List to Vault** | notes, title (optional) | the new list note |

Formats are PDF, Word, OpenDocument, Rich Text, HTML, EPUB (needs Pandoc) and Markdown. Export actions write to a temporary file; pass it on to **Save File**, **Share**, **Mail** and so on.

### Find Notes

**Find Notes** works like Apple's “Find Notes” or “Find Reminders”: add filter rows and choose whether **all** or **any** of them must match.

| Filter | Comparisons |
|---|---|
| Name | contains, is, begins with |
| Text | contains |
| Tags | contains – also finds nested tags (`idea` finds `project/idea`) |
| Properties | contains – `status: active` checks one property, `active` alone checks all |
| Folder Path | is, begins with (= folder and subfolders), contains |
| Creation Date, Modification Date | is, is before, is after, is between, and Shortcuts' relative ranges such as “in the last 7 days” |

Below the filters you can sort by name, creation date or modification date and set a limit.

### Filter Notes

**Filter Notes** reads like a sentence. Choose the criterion in the first menu; the rest of the sentence follows, and the menus are filled from your vault:

- Filter *Notes* by **Text** *budget* in *Title Only*
- Filter *Notes* by **Tag** *project/haushaltsbuch*
- Filter *Notes* by **Tag in Text** *todo* – `#todo` or `[[todo]]` in the text
- Filter *Notes* by **Property** *status* with *active* – without a value: every note that has the property
- Filter *Notes* by **Folder** *02 Projects* – including subfolders
- Filter *Notes* by **Modification Date** *In the Last 7 Days* – or *On*, *Since*, *Before*, *Between* with dates

Without input notes, the whole vault is searched. Several **Filter Notes** one after another combine their criteria with AND, because each one keeps only the notes of the previous one that also match. For OR, use **Find Notes** with *Any*.

### Shortcut examples

**Weekly review as PDF**

1. **Find Notes** – *Modification Date* is in the last *7 days*; sort by *Modification Date*, latest first.
2. **Export Note List** – *Notes* from step 1, *PDF*, title “Weekly review”.
3. **Save File** – e.g. to *Documents/Reviews*.

**Active project notes as a list note in the vault**

1. **Filter Notes** – by *Tag* `project`.
2. **Filter Notes** – *Notes* from step 1 by *Property* `status` with `active`.
3. **Save Note List to Vault** – title “Active projects”.

The list note appears in the export folder of the vault and opens in Obsidian like any other note.

**Send a note as Word document**

1. **Find Notes** – *Name* is `Budget 2026`; limit 1.
2. **Export Note** – *Word*.
3. **Send Email** – with the file as attachment.

**Today's notes in the window**

1. **Show in VaultSearch** – `modified:today` (German: `geändert:heute`).

Add it to the menu bar or give it a keyboard shortcut in the details of the shortcut.

**A tag by Siri**

1. **Show Tag in VaultSearch** – *Tag* `project/haushaltsbuch`.
2. Name the shortcut “Show household book”.

“Hey Siri, show household book” opens VaultSearch with all notes of the tag.

### Interactive shortcuts

A shortcut can ask when it starts instead of using fixed values. Then one shortcut covers many searches, and Siri only has to know its name.

**“Ask Each Time”:** Click a field in an action, e.g. *Tag* in **Show Tag in VaultSearch**, and choose **Ask Each Time**. When the shortcut runs, it offers the tags of your vault. The same works for *Folder*, for *Note* and *Format* of **Export Note**, and for the menus of **Filter Notes**.

**Search assistant with a menu**

1. **Choose from Menu** – prompt “What are you looking for?”, options *Text*, *Tag*, *Folder*.
2. Under *Text*:
   - **Ask for Input** – “What should I search for?”
   - **Show in VaultSearch** – *Search Text* = *Provided Input*.
3. Under *Tag*: **Show Tag in VaultSearch** – *Tag* = *Ask Each Time*.
4. Under *Folder*: **Show Folder in VaultSearch** – *Folder* = *Ask Each Time*.
5. Name the shortcut, e.g. “Search my archive”.

“Hey Siri, search my archive” asks what you are looking for and shows the results in VaultSearch. You can speak or type the search; the search syntax such as `tag:idea modified:last 7 days` works too.

**A tag by dictation**

1. **Dictate Text**.
2. **Replace Text** – spaces in *Dictated Text* with `-`, so “PV Anlage” becomes `PV-Anlage`.
3. **Show Tag in VaultSearch** – *Tag* = *Updated Text*.

You say a tag, and VaultSearch shows all notes with it. A tag that exists on several levels (`pv-anlage`, `energy/pv-anlage` …) needs no question: all levels are shown. Only a full path (`energy/pv-anlage`) is searched exactly. Folders work the same with **Show Folder in VaultSearch**; if a folder name exists more than once, the shortcut asks which one is meant.

**Export a note with questions**

1. **Export Note** – *Note* = *Ask Each Time*, *Format* = *Ask Each Time*.
2. **Save File** – *Ask Where to Save*.

The shortcut asks for the note, the format and the destination.

**Review with a choice of period**

1. **Choose from Menu** – *This Week*, *This Month*.
2. In each option **Filter Notes** – by *Modification Date* *This Week* or *This Month*.
3. After the menu: **Export Note List** – *Notes* = *Result of Choose from Menu*, *PDF*, title “Review”.
4. **Save File** or **Share**.

## AppleScript

Open the dictionary in Script Editor with **File ▸ Open Dictionary… ▸ VaultSearch**. The examples below can be run in Script Editor or in Terminal with `osascript`.

### Dictionary

**Application**

| Term | Meaning |
|---|---|
| `notes` | all notes of the vault (`every note`, `note "Plan"`, `note id "/…/Plan.md"`, `every note whose …`) |
| `vault path` | POSIX path of the vault folder |
| `indexing` | `true` while the vault is being read |

**note** – all properties are read-only

| Property | Meaning |
|---|---|
| `name` | title (file name without `.md`) |
| `id`, `path` | POSIX path of the file |
| `folder` | folder inside the vault, e.g. `Projects/2026` |
| `tags` | list of tags from the frontmatter |
| `frontmatter` | the other frontmatter properties as a record; read keys with bars: `|status| of fm` |
| `creation date`, `modification date` | frontmatter date if there is one, otherwise the file date |
| `content` | Markdown text without frontmatter |
| `Obsidian URL` | `obsidian://` link to the note |

**Commands**

| Command | Result |
|---|---|
| `search` *text* [`limit` *n*] | notes, best matches first; the syntax of the search field; waits for the index |
| `show search` *text* | shows the results in the window |
| `open in Obsidian` *note(s)* | – |
| `export` *note* [`as` *format*] [`to` *file*] | the document of one note |
| `export` *list of notes* [`as` *format*] [`to` *file*] [`titled` *text*] | one list document |
| `save to vault` *list of notes* [`titled` *text*] | the new list note in the export folder |
| `reindex` | reads the vault again and waits until it is done |

*format* is `PDF` (default), `Word`, `OpenDocument`, `rich text`, `HTML`, `EPUB` or `Markdown`. Without `to`, the file is written to the temporary folder and returned.

`search` waits until the vault has been read. `every note` returns what has been read so far; check `indexing` or run `search` first if your script starts VaultSearch.

### AppleScript examples

**Search and list**

```applescript
tell application "VaultSearch"
    set hits to search "tag:idea modified:last 30 days" limit 10
    set titles to {}
    repeat with n in hits
        set end of titles to (name of n) & " – " & (folder of n)
    end repeat
end tell
set AppleScript's text item delimiters to linefeed
return titles as text
```

**Weekly review as PDF on the Desktop**

```applescript
set target to (POSIX path of (path to desktop)) & "Weekly review.pdf"
tell application "VaultSearch"
    set hits to search "modified:last 7 days"
    export hits as PDF to POSIX file target titled "Weekly review"
end tell
```

**Every note of a folder, exported one by one as Word**

```applescript
set outFolder to (POSIX path of (path to documents folder)) & "Export/"
do shell script "mkdir -p " & quoted form of outFolder
tell application "VaultSearch"
    repeat with n in (every note whose folder starts with "Projects/2026")
        export n as Word to POSIX file (outFolder & (name of n) & ".docx")
    end repeat
end tell
```

**Read frontmatter**

```applescript
tell application "VaultSearch"
    set fm to frontmatter of note "Budget 2026"
end tell
try
    return |status| of fm
on error
    return "no status"
end try
```

**Save a list note to the vault and open it**

```applescript
tell application "VaultSearch"
    set hits to search "tag:project status:active"
    set listNote to save to vault hits titled "Active projects"
end tell
-- The list note is a Markdown file in the vault; Obsidian shows it like any note.
tell application "Finder" to reveal listNote
```

**Open the three most recently changed notes in Obsidian**

```applescript
tell application "VaultSearch"
    open in Obsidian (search "" limit 3)
end tell
```

**From Terminal**

```sh
osascript -e 'tell application "VaultSearch" to name of every note whose name contains "Budget"'
```

## Troubleshooting

**The actions don't appear in Shortcuts.**
Quit Shortcuts (⌘Q) and open it again. If you build VaultSearch yourself: macOS reads the actions again only when the build number changes, and older copies of VaultSearch with the same version can hide the new actions; delete old copies and empty the Trash.

**A shortcut runs forever or fails with “internal error”.**
VaultSearch must be signed with a development team; see the [Developer Guide](development.md#siri-shortcuts-and-spotlight).

**“There are no notes to save or export.”**
The search or filter found nothing, or a note named in the script doesn't exist (check the spelling of `note "…"`).

**AppleScript says the terms are unknown.**
Terms like `folder` or `frontmatter` only work inside `tell application "VaultSearch"`. Read fields of a record you got from VaultSearch after `set`, as in the frontmatter example.
