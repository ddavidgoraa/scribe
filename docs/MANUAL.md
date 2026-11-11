# Scribe — User Manual

Scribe is a minimal Markdown editor for macOS with LaTeX math, inspired by iA Writer.
You write in plain `.md` files. Scribe never adds anything to them, and formatting shows up as you type.

New to Scribe? The short, illustrated [Getting started](GETTING-STARTED.md) guide covers the basics.

Version: 0.1 · Requires macOS 14 Sonoma or later on a Mac with Apple silicon (M1 or newer).

---

## Contents

1. [Installation](#1-installation)
2. [Getting started: your library](#2-getting-started-your-library)
3. [Notes: creating, naming, saving](#3-notes-creating-naming-saving)
4. [Writing: live preview](#4-writing-live-preview)
5. [Math](#5-math)
6. [Images](#6-images)
7. [Formatting shortcuts](#7-formatting-shortcuts)
8. [Finding things: Quick Open and library search](#8-finding-things-quick-open-and-library-search)
9. [Writing modes: focus and typewriter](#9-writing-modes-focus-and-typewriter)
10. [Appearance and settings](#10-appearance-and-settings)
11. [Copy as HTML](#11-copy-as-html)
12. [Changes made outside Scribe](#12-changes-made-outside-scribe)
13. [Keyboard shortcuts](#13-keyboard-shortcuts)
14. [Limitations in version 0.1](#14-limitations-in-version-01)

---

## 1. Installation

1. Open `Scribe-0.1.0-arm64.dmg`.
2. Drag **Scribe** into the **Applications** folder.
3. Launch Scribe from Launchpad or the Applications folder.

Scribe isn't notarized by Apple yet, so macOS blocks it the first time you open it. To allow it, do one of the following:

- open **System Settings → Privacy & Security**, scroll down and click **Open Anyway**, **or**
- run this in Terminal:
  ```sh
  xattr -dr com.apple.quarantine /Applications/Scribe.app
  ```

You only need to do this once.

## 2. Getting started: your library

Your **library** is an ordinary folder that holds your notes, for example `~/Documents/Notes`, a folder in iCloud Drive or a git repository.

- On first launch, click **Choose a folder for your notes** or press **⌘O** and choose a folder.
- Scribe remembers the folder and reopens it next time, together with the note you had open.
- To switch to another folder, press **⌘O** again. One library is open at a time.

### The library panel

The window is just your text. The library is a panel that floats over the left side of the window: press **⌘⇧L** to show or hide it. It starts hidden, and the text column moves aside while it's open.

- At the top: the search field (see [Library search](#library-search-f)).
- **Recent** lists the five notes you changed last.
- **Library** shows a tree of subfolders and notes, with the date each note was changed (the time for today, then "Yesterday", the weekday, the date).
- At the bottom: the library folder, the number of notes and a **+** button for a new note. Right-click it to open another library.
- The panel lists Only `.md` and `.markdown` files are listed; other files, such as images, are not.
- Hidden files and folders (starting with a dot, like `.git`) are skipped.
- On macOS 26 and later, the panel uses the system's Liquid Glass material.
- Click a note to open it. Clicking a folder expands it.
- **Sorting:** **View → Sort Notes By** offers:
  - **Name**: alphabetical, with natural number order ("Note 2" before "Note 10");
  - **Date Modified**: newest first.

  Folders are always listed first, alphabetically.
- **Context menus** (right-click):
  - on a folder: **New Note** (creates a note in that folder) and **Show in Finder**;
  - on a note: **Rename…** and **Show in Finder**;
- The folder of the open note is expanded automatically.

## 3. Notes: creating, naming, saving

### New note

**⌘N** (or **+** at the bottom of the library panel) creates `Untitled.md` in the folder of the note that's currently open. If no note is open, the file goes in the library's top folder. Further empty notes are named `Untitled 2.md`, `Untitled 3.md` and so on.

### Names from the first line

You don't have to name notes yourself: Scribe names each note after its **first line**.

- Type `# Shopping list` and, once the note saves, the file becomes `Shopping list.md`.
- If you later change the first line, the file name follows.

This keeps working after you restart the app. It applies to notes that:

- are called `Untitled` or `Untitled N`, or
- have a name that matches their first line (including a ` 2`, ` 3` suffix added because the name was taken).

**Renaming a note by hand to anything other than its first line stops this for that note.**

Details:

- leading `#` characters are left out;
- characters that aren't allowed in file names (`/`, `\`, `:`) become `-`;
- names are at most 80 characters long;
- if a name is taken, Scribe adds ` 2`, ` 3` and so on.

You can turn this off in **Settings (⌘,) → Name notes after their first line**.

### Renaming by hand

Right-click the note in the library panel, choose **Rename…**, type the new name (without `.md`) and confirm.

### Saving

**There is no Save command.** Scribe saves on its own:

- about 1 second after you stop typing,
- when you switch to another note,
- when you switch to another app,
- when you quit Scribe.

Saves are atomic, so a file is never left half-written, even after a crash. **⌘Z** undoes changes as in any editor.

## 4. Writing: live preview

Scribe shows formatted text right in the editor; there is no separate preview window. Markdown markers (`**`, `#`, `[]()` and so on) are **hidden** until your cursor touches them:

| Element | Markers show when |
|---|---|
| **bold**, *italic*, ~~strikethrough~~, `code`, links, footnote references, `$math$` | the cursor touches the element (including right before or right after it) |
| headings `#` | the cursor is on the heading line |
| blocks: `$$ … $$`, code blocks ```` ``` ````, quotes `>` | the cursor is inside the block |

- **Selecting text with the mouse** doesn't reveal markers, so the text doesn't jump under the pointer.
- **Always visible** (dimmed): list markers (`-`, `1.`), task boxes (`[ ]`, `[x]`), tables, horizontal rules (`---`), footnote definitions and HTML.
- The file on disk always contains the full Markdown. Hiding markers only affects what you see.

### Supported syntax

CommonMark and GitHub Flavored Markdown, plus these extensions:

| Syntax | Example |
|---|---|
| Headings | `# H1` … `###### H6`, or an underline of `===` / `---` |
| Bold / italic | `**bold**`, `*italic*`, `***both***` |
| Strikethrough | `~~text~~` |
| Inline code / code blocks | `` `code` ``, ```` ```swift … ``` ```` |
| Links | `[text](https://example.com)`, `<https://example.com>` |
| Images | `![description](assets/photo.png)` |
| Quotes | `> quote` |
| Lists, task lists | `- item`, `1. item`, `- [ ] task`, `- [x] done` |
| Tables | `\| a \| b \|` with a `\|---\|---\|` row |
| Footnotes | `text[^1]` and `[^1]: footnote text` |
| Math | `$…$`, `$$…$$`, see [Math](#5-math) |

Tables are shown as aligned fixed-width text. There is no cell editor.

## 5. Math

### Inline math

Wrap a formula in single dollar signs: `$E = mc^2$`.

When the cursor is elsewhere, the formula is rendered inline with your text. When the cursor touches it, you see the LaTeX source.

### Block math

Put the formula on its own lines between `$$`:

```
$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$
```

- When the cursor is outside the block, you see the formula rendered as a large block.
- While you edit the block, you see the source with a **live preview below it** that updates as you type.

### Errors

If a formula contains an error, such as an unknown command, Scribe shows its **source in red**. Hover over it to see the error message.

### What's supported

Formulas are rendered by the SwiftMath library. It supports a large subset of LaTeX: fractions, roots, sub- and superscripts, integrals, sums, Greek letters, matrices and most symbols. Some rarer commands and AMS environments may not work.

**Tip:** braces `{ }` in a formula must be balanced, or the formula isn't recognized as math.

**⌘⇧M** wraps the selection in `$`. If the selection spans several lines, it creates a `$$` block.

## 6. Images

### Adding images

There are three ways to add an image:

- **Paste** an image with **⌘V**: a screenshot (for example taken with ⌘⇧⌃4), an image copied from Preview or a browser, or an image file copied in Finder.
- **Drag** image files from Finder (or images from other apps) into the editor. The image goes where you drop it.
- **Type** the Markdown yourself: `![description](path/to/image.png)`.

When you paste or drag, Scribe handles the image like this:

| Source | What Scribe does |
|---|---|
| Image data (screenshots, images copied from apps) | Saves it as a PNG in an `assets` folder next to the note |
| Image file **outside** your library | Copies it into the `assets` folder next to the note |
| Image file **inside** your library | Links to it where it is, without copying |

Copied images are named after the note plus the date and time, for example `assets/Shopping-list-20261109-143005.png`. Supported file types are PNG, JPEG, GIF, HEIC, TIFF, WebP, BMP and SVG.

Scribe inserts each image as `![…](…)` on a line of its own, so it shows up as a preview straight away. **⌘Z** removes the inserted text, but a file that was already copied into `assets` stays there.

Pasted text that happens to include a picture (for example rich text from a web page) is pasted as text.

### How images are shown

An image on **its own line**:

```
![Chart](assets/chart.png)
```

is shown as a preview that fits the width of the text column. When the cursor touches that line, you see the source.

- Paths are relative to **the note's folder**. Absolute paths (`/…`), paths starting with `~/…` and paths with spaces also work: `![x](<my photo.png>)` or `![x](my%20photo.png)`.
- Images from the internet (`https://…`) are **not downloaded**; only the description is shown.
- An image in the middle of a sentence isn't shown as a preview; only its description is.
- If you replace an image file on disk, the new preview appears the next time you edit around the image or reopen the note.

## 7. Formatting shortcuts

All of these are in the **Format** menu and work as toggles: using one again removes the formatting.

| Shortcut | Action |
|---|---|
| **⌘B** | bold `**…**` |
| **⌘I** | italic `*…*` |
| **⌘⇧X** | strikethrough `~~…~~` |
| **⌘⇧C** | code `` `…` `` |
| **⌘⇧M** | math `$…$` (several lines: a `$$` block) |
| **⌘K** | link `[selection](url)`, with `url` selected so you can type over it. If the selection is a web address, you get `[](address)` |
| **⌘1** … **⌘6** | heading level 1–6. The same level again removes the heading |

- With nothing selected, **⌘B**, **⌘I** and the others insert an empty pair of markers with the cursor between them.
- A trailing space in the selection is left outside the markers.
- **⌘Z** undoes any of these changes.

## 8. Finding things: Quick Open and library search

### Quick Open: ⌘P

Open a note by its name:

1. Press **⌘P** and start typing part of a name or path, for example `plan` or `proj sc`. The palette opens over the text, like Spotlight.
2. Matching is fuzzy: the letters don't have to be next to each other, and case and accents don't matter (`ges` finds `Gęś`).
3. **↑ / ↓** choose a result, **Return** opens it, **Esc** (or a click outside) closes the palette.
4. **⌘Return** creates a new note titled with what you typed. Return does the same when nothing matches.

### Library search: ⌘⇧F

Search the contents of every note:

1. Press **⌘⇧F**. The library panel opens and the cursor moves to its search field.
2. Type one or more words. Results appear as you type.
3. Each matching note is a card showing its name, folder, number of matches and the matching lines, with matches highlighted like a marker pen.
4. Click a line: the note opens with the match selected and scrolled into view.
5. Click a note's name to open it without jumping to a match.
6. Clear the search field (or press **Esc** in it) to get back to the note tree.

How search works:

- **case and accents are ignored**: `lukasz` finds "Łukasz", `zolc` finds "żółć";
- with several words, a note must contain **all** of them (in its text or its name);
- notes whose **name** matches are listed first; the rest are ordered by number of matching lines;
- each note shows up to 5 matching lines.

The search index updates by itself, including when files change outside Scribe.

### Find in the current note: ⌘F

The standard macOS find bar:

- **⌘F** opens it, **⌘G** / **⌘⇧G** go to the next and previous match;
- **⌘E** uses the selection as the search text;
- **⌥⌘F** opens find and replace.

## 9. Writing modes: focus and typewriter

Turn both modes on or off in the **View** menu. Scribe remembers the setting.

### Focus mode: ⌘D

Everything except the **current paragraph** fades, so you only see what you're working on.

A paragraph is a block of text between blank lines, so text you broke into several lines by hand is highlighted as a whole. Math, images and code blocks outside the paragraph fade too.

### Typewriter mode: ⌘T

The line with the cursor stays in **the middle of the screen**, and the text moves underneath it. There is extra space at the start and end of the document so even the first and last lines can sit in the middle.

You can use both modes at once.

## 10. Appearance and settings

- There is **no toolbar**: just the window buttons and the note's name, dimmed, at the top.
- The **status bar** in the bottom-right corner appears when you move the pointer and hides while you type. It shows the word count and reading time, whether the note is saved, and which writing modes are on.
- The **text column** is 64, 72 or 80 characters wide (see Settings) and centered, as in iA Writer.
- Colors are a neutral white with dark grey text and one blue accent (cursor, selection, the open note).
- **Light and dark mode** follow your macOS setting automatically.
- **Text size:**
  - **⌘+** makes text bigger,
  - **⌘−** makes it smaller,
  - **⌘0** resets it to 16 pt.

  The range is 12–26 pt.

### Settings window: ⌘,

| Setting | Description |
|---|---|
| **Font** | iA Writer **Duo** (default), **Mono** or **Quattro**. Code always uses Mono |
| **Size** | text size (12–26 pt) |
| **Line length** | text column width: 64, 72 or 80 characters |
| **Name notes after their first line** | automatic note names, see [Names from the first line](#names-from-the-first-line) |

## 11. Copy as HTML

**Edit → Copy as HTML** (**⌥⌘C**) copies the selection, or the whole note if nothing is selected, as HTML:

- pasted into an app that supports formatting (Mail, Pages, website editors), it comes out formatted;
- pasted into a plain text editor, you get the HTML code.

In this version, math is copied as LaTeX source (inside `<span class="math">`).

## 12. Changes made outside Scribe

Notes are ordinary files, so you can edit them in other apps, sync them (iCloud, Dropbox) or keep them in git. Scribe watches the library folder:

- **new, deleted and renamed files** appear in the library panel automatically;
- if the file of the **open note** changes on disk and you have no unsaved changes, the note reloads quietly and the cursor stays where it was;
- if you **do** have unsaved changes, a dark message appears at the bottom of the window:
  - **Reload** takes the version on disk (your changes are lost),
  - **Keep Mine** keeps your version and overwrites the file;
- if the open note's file is **deleted**:
  - with no unsaved changes, the note closes,
  - with unsaved changes, a **Close / Keep Mine** message appears, and **Keep Mine** recreates the file.

While the message is showing, autosave is paused, so nothing is overwritten until you decide.

## 13. Keyboard shortcuts

| Shortcut | Action |
|---|---|
| **⌘O** | open a library (folder) |
| **⌘N** | new note |
| **⌘P** | Quick Open: open a note by name |
| **⌘⇧F** | search the whole library |
| **⌘F** | find in the note |
| **⌘V** | paste (images are saved to `assets`) |
| **⌘B / ⌘I** | bold / italic |
| **⌘⇧X** | strikethrough |
| **⌘⇧C** | code |
| **⌘⇧M** | math |
| **⌘K** | link |
| **⌘1 … ⌘6** | heading 1–6 |
| **⌥⌘C** | copy as HTML |
| **⌘D** | focus mode |
| **⌘T** | typewriter mode |
| **⌘⇧L** | show/hide the library panel |
| **⌘+ / ⌘− / ⌘0** | bigger / smaller / default text size |
| **⌘,** | settings |
| **⌘Z / ⌘⇧Z** | undo / redo |

## 14. Limitations in version 0.1

- **No export** to HTML or PDF; only "Copy as HTML". Export is planned for version 0.2.
- **One library and one window** at a time.
- **Tables** are shown as text, without a cell editor.
- **Sentence focus** (rather than paragraph focus) is planned for version 0.2.
- The arrow keys also move through hidden markers. When the cursor touches an element, its markers appear.
- The interface is in English. A Polish version is planned for 0.2.
- Scribe runs only on Macs with Apple silicon and isn't notarized (see [Installation](#1-installation)).

### Where Scribe keeps your data

- Your notes: only in the folder you chose, as plain `.md` files, with pasted or dropped images in `assets` folders next to the notes.
- App settings (library location, sorting, font, modes): in macOS preferences under the identifier `dev.dawidgora.scribe`.

Scribe doesn't send anything over the internet.
