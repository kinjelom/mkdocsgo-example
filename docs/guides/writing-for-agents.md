# Writing for humans and agents

The same Markdown serves both. There is no separate agent format, no metadata
to maintain and no second copy of anything. But a handful of habits make the
difference between an assistant that answers from your documentation and one
that quotes the wrong paragraph confidently.

## What an agent actually receives

mkdocsgo does not hand a page to a model. It cuts every page at its ATX
headings and treats each **section** as the unit:

```
docs/reference/cli.md
|-- # Command line                  -> section 1
|-- ## Modes                        -> section 2
|-- ## Flags                        -> section 3
\-- ## Ports                        -> section 4
```

A search returns ranked sections, each with its navigation breadcrumb, its
heading anchor, a snippet and a score. The agent picks one and asks for it.
That is two round trips and a few hundred bytes, instead of a four-thousand-line
page.

Everything below follows from that.

## Headings are the retrieval unit

**Give a section the heading someone would search for.** Heading terms are
weighted more heavily than body terms, so `## Rolling deployments` is found by
"rolling deployment" and `## Notes` is found by nothing.

**Keep sections self-contained.** A section that starts with "As mentioned
above, this is why it fails" is useless on its own, because on its own is
exactly how it will arrive. Repeat the subject in the first sentence - it reads
fine to a human and it rescues the section for everyone else.

**Do not nest six levels deep.** Every heading is a retrievable unit, and a
`###### Note` containing one sentence is noise in the ranking.

## The navigation is the breadcrumb

`nav:` in `mkdocs.yml` becomes the trail shown beside every hit:

```
Deployment > Cloud Foundry > Binary buildpack
```

That is often all the context an agent needs to decide a hit is relevant. A
flat navigation of thirty top-level pages provides none of it. Pages missing
from `nav:` are still indexed, but they are flagged `in_nav: false` and carry no
trail - so a page worth finding is a page worth listing.

## Write the identifiers out

Search preserves the things that look like noise to a tokeniser:

- `IMAGE_VERSION` keeps its underscore - it does not become `imageversion`
- `1.0.0` stays one token, rather than three digits an index would discard
- a section containing the query verbatim gets a scoring bonus

So write the real flag, the real field name and the real version. "the version
setting" is unfindable; `MKDOCSGO_VERSION` is found on the first try.

## Snippets are indexed literally

This is the one place where what a reader sees and what an agent sees differ.
mkdocsgo does not run MkDocs, so a snippet include is indexed as the line
itself:

```markdown
--8<-- "deploy/cf/manifest-docker.yml"
```

The reader gets the manifest, expanded by MkDocs at build time. The index gets
that one line. Nothing is broken - but a value that exists *only* inside an
included file will not be found by a search.

The rule that follows: **include files for the things a reader needs verbatim,
and say in prose what the thing is for.** This page's own deployment pages do
that - the manifest is included so it cannot drift from the deployed one, and
the surrounding text explains what it does, which is the part worth finding.

## Tables and admonitions survive

Both are plain Markdown in the source, so both arrive intact. A specification
table is one of the better things an agent can receive: dense, unambiguous, and
small.

!!! note "Admonitions read fine as Markdown"

    An `!!! note` block is indented text in the source. It arrives as indented
    text, which is readable. Use them for emphasis rather than bolding a whole
    paragraph.

## What not to bother with

- **Front matter for retrieval.** It is stripped before sectioning. Keep it for
  MkDocs' own purposes.
- **Keyword stuffing.** BM25 already down-weights terms that appear everywhere
  in the corpus. A paragraph of synonyms makes the section rank *worse* for the
  query it was aimed at, by diluting it.
- **A separate `llms.txt` or agent copy.** The sources are already the agent's
  copy. A second one is a second thing to keep true.

## Checking your work

Run the server and ask it what an agent would ask:

```bash
scripts/run.sh
```

Then point a client at `http://127.0.0.1:8000/mcp`, or register
`scripts/mcp.sh` over stdio, and try the question you expect a reader to bring.
If the right section does not come back first, the heading is usually the
reason.
