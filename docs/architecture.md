---
type: architecture
links:
  - rel: part-of
    to: CLAUDE.md
    note: CLAUDE.md points here before changing the viewer, the print bar or the print path
  - rel: covers
    to: Sources
---

# Architecture

roneo is a PDF viewer whose print controls sit in the window, so printing single- or
double-sided at 100% scale is one click, not a trip through the system print dialog. It prints
the file itself, so 100% is exact.

## Targets

- `RoneoCore` — Foundation only. Print-job decisions: settings and their defaults, preflight,
  the `lp` arguments (double-sided binding included), page ranges, CUPS queries and job state,
  and the bar's display choices (`BarChoices`).
- `RoneoPDF` — Foundation and PDFKit. Document facts the print path needs: first-page
  orientation, print permission, and the file `lp` receives (`PrintableFile`).
- `Roneo` — the AppKit executable: document, window, viewer and print bar. `PrinterDirectory`
  reads the printer list for every window; `PrintController` drives one window's bar (controls,
  Print, job polling); `PrintBarView` is layout only. It holds no decision the unit tests should cover; those live in the two libraries.

## Viewer

An AppKit document-based app (`NSDocument`, read-only) hosts PDFKit's `PDFView`: continuous
vertical scroll, a page-thumbnail sidebar (⌥⌘2), zoom (actual size ⌘0, fit width, ⌘+ and ⌘−),
Find (⌘F, ⌘G), page up and down, and go-to-page (⌥⌘G).

- One window per document. Automatic window tabbing is off. A launch that opens and restores
  nothing shows the Open panel.
- Window restoration reopens what was open at quit at the same page and zoom (viewing state, not
  print state); Open Recent reopens a file at its first page.
- PDF is declared as a Default-rank document type. "Make roneo the default PDF viewer" calls
  `NSWorkspace.setDefaultApplication(at:toOpen:)`; once roneo is the default the item
  is disabled with "roneo is the default PDF viewer".
- The view reloads when the file changes on disk, keeping page and zoom, so a regenerated sheet
  reprints without reopening. A deleted file stays on screen as last read.

## Print bar

A strip across the top of each document window, above the page, always visible:

```
Printer [name ▾]  Sides [Single|Double]  Scale [100%|Fit]  Pages [All|Current|Range: ___]  Copies [1 ⌃⌄]
Paper [ ▾]  Type [ ▾]  Tray [ ▾]  Colour [Colour|Grey]                              [ Print ]
```

Every control shows a setting the job will use; a job never carries a setting the bar did not
show. Defaults, identical for every new window:

| Control | Default |
|---|---|
| Printer | the system default printer |
| Sides | the printer's default |
| Scale | 100% |
| Pages | All |
| Copies | 1 |
| Paper, Type, Tray, Colour | the printer's defaults |

- The second row is built from the selected printer's own options. A control whose option the
  printer lacks stays in place, disabled, with a tooltip naming why ("This printer can't print
  double-sided").
- Double binds on the long edge: `two-sided-long-edge` when the first page is portrait,
  `two-sided-short-edge` when it is landscape; mixed documents follow the first page. Short-edge
  is not a separate choice.
- The bar's state lives with its window: it keeps what was chosen until the window closes, and a
  new window starts from the defaults. Changing printer resets Paper, Type, Tray and Colour to
  the new printer's defaults and keeps Sides, Scale, Pages and Copies where the new printer
  supports them. Nothing is persisted across windows, documents or launches.
- Fit shrinks or grows each page to the printable area. Current is the page shown in the view,
  named in its segment ("Current (4)").
- ⌘P (File → Print) and the Print button send the job immediately with the bar's settings. "Print with System Dialog…"
  (⌥⌘P) in the File menu covers anything the bar does not.
- After sending, the right end of the bar shows the job's state from CUPS (`JobState.text`:
  "Sent · 3 pages", "Sent · page 4", "Printing", "Done", "Didn't print: …", "Couldn't find the
  job (…)") until the next print.

## Print path

The bytes the window shows go to CUPS (from a scratch copy, deleted once `lp` returns),
equivalent to `lp -d <printer> -n <copies> -o sides=… -o print-scaling=none|fit
-o page-ranges=… -o PageSize=… -o MediaType=… -o InputSlot=… -o ColorModel=…`. Pages are never
re-rendered by the app, so 100% is byte-exact; page ranges go ascending and merged. The printer
list and each printer's options come from CUPS (destinations and the printer's PPD or IPP
attributes); every CUPS command is cut off after `ProcessRunner.timeout`. The app is not
sandboxed.

- Every job carries the bar's options plus explicit neutral values for each layout-changing
  option: `number-up=1`, no fit-to-page, all sides of `page-set`, no mirror.
- User-saved defaults never apply: the CUPS client runs with `HOME` pointed at an empty
  directory, so `~/.cups/lpoptions` cannot change size or layout. The driver's own quality
  defaults (resolution, toner save) pass through untouched.

## Locked and no-print PDFs

A password-protected PDF prompts for the password to view. Printing sends an unlocked copy,
which stays vector and exact at 100%. A PDF encrypted only for permissions prints from its own
bytes. A PDF whose
permissions forbid printing keeps Print disabled with the tooltip "This PDF doesn't allow
printing".
