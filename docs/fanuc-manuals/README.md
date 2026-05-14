# FANUC Manuals

Keep FANUC manuals, option manuals, controller documentation, and extension
documentation outside this public repository.

The current trusted local manuals project is:

```text
C:\Dev\Fanuc Robot Manuals
```

Do not copy those PDFs into this repo. FANUC manuals are usually licensed or
copyrighted and should not be published with this public repository.

Suggested organization:

```text
C:\Dev\Fanuc Robot Manuals\
  R30iB Mate Plus\
    README.md
    build-manual-index.ps1
    search-manuals.ps1
    tools\
```

When referencing manuals from project notes, cite the manual title, document
number, revision, and section instead of copying large excerpts into the repo.

For controller-specific behavior, especially system variables, UOP/SOP, DCS,
KAREL, SNPX assignment, PCDK, or motion behavior, use
`C:\Dev\Fanuc Robot Manuals` or the actual controller as the source of truth.
Do not use random public PDF mirrors as authority for generated robot code.

Use the manuals project's own search/index scripts when looking up references.
Keep any extracted snippets short and cite the source manual; do not copy manual
content into this repository.
