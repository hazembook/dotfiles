<!-- SEMBLE_START -->
## Semble Code Search

Semantic and code search is powered by `semble` via CLI and the `@semble-search` subagent. No persistent MCP daemon is needed.

### Usage

Delegate exploratory codebase searches to the `@semble-search` subagent, or invoke `semble` directly via Bash:

```bash
semble search "authentication flow" . --max-snippet-lines 10
semble search "deployment guide" . --content docs
semble search "database host port" . --content config
semble find-related src/auth.py 42 .
semble search "save model to disk" . --top-k 10
```

`semble` is available on `$PATH` (`~/.local/bin/semble`). The index is built on first run and cached automatically.

### Workflow

1. Delegate to `@semble-search` or run `semble search "<query>" .` to locate where functionality or symbols are defined.
2. Review the returned file and line number with context.
3. Navigate directly to that file and line. Read only the relevant function/class. Do not grep for the same content again.
4. Pass `--content docs` for documentation, `--content config` for config files, or `--content all` for everything.
5. Optionally use `semble find-related <file> <line> .` to find related implementations.
6. Use Grep only when you need every occurrence of an exact literal string across the entire repository (e.g., all call sites of a renamed function).
<!-- SEMBLE_END -->
