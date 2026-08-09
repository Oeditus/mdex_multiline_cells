<img src="https://raw.githubusercontent.com/Oeditus/mdex_multiline_cells/v0.1.0/priv/images/logo-128.png" alt="MDEx Multiline Plugin" width="128" align="right">

# MDEx Multiline Cells

An [MDEx](https://hexdocs.pm/mdex) plugin enabling multi-line cells in Markdown tables with full inline/block Markdown rendering and automatic key-column continuation guessing.

<p align="center">
  <a href="https://hex.pm/packages/mdex_multiline_cells"><img src="https://img.shields.io/hexpm/v/mdex_multiline_cells.svg" alt="Hex Version" /></a>
  <a href="https://hexdocs.pm/mdex_multiline_cells"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="Hex Docs" /></a>
  <a href="https://github.com/Oeditus/mdex_multiline_cells/actions"><img src="https://github.com/Oeditus/mdex_multiline_cells/workflows/CI/badge.svg" alt="CI Status" /></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
</p>

---

## Overview

Standard GFM (GitHub Flavored Markdown) pipe tables restrict each table row to a single physical line. **MDEx Multiline Cells** extends [`MDEx`](https://hexdocs.pm/mdex) by adding support for multi-line table rows while preserving rich Markdown syntax (bold, italic, code blocks, links, math, and inline elements).

## Key Features

- **Automatic Continuation Guessing**: Automatically infers multi-line cell continuations when a table row's primary key column (e.g., 1st column) is empty.
- **Multiple Multi-line Syntaxes**:
  - Trailing backslash `\` at line ends inside table rows.
  - Double backslash `\\` in cell text.
  - Unclosed multi-line table cell continuation across physical lines.
  - Explicit `<br>`, `<br/>`, or `<br />` HTML line break tags in cell contents.
- **Rich Markdown Formatting**: Preserves bold (`**`), italics (`*`), inline code (`` ` ``), links (`[text](url)`), images, and AST nodes across cell line segments.
- **Protected Code Fences**: Ignores table-like pipe syntax inside fenced code blocks (`` ``` `` and `~~~`).
- **Configurable Output Modes**:
  - `:line_break` (default) - Renders line breaks inside table cells as `<br />` (`MDEx.LineBreak`) preserving inline formatting.
  - `:paragraph` - Wraps each line segment within table cells in `<p>` paragraph blocks.
  - `:html_br` - Renders line breaks as raw `<br />` HTML inline nodes.

---

## Installation

Add `mdex_multiline_cells` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:mdex_multiline_cells, "~> 0.1"},
    {:mdex, "~> 0.13"}
  ]
end
```

---

## Usage

### 1. Automatic Continuation via Empty Key Column

```elixir
markdown = """
| #  | Issue | Location | Suggested Fix |
|----|-----------------------------------|--------------------------|-----------------------------------------------------|
| B1 | Synchronous DB writes in hot path | orchestrator.ex:890, 425 | Wrap StepMetrics.record_metric in Task.start        |
|    |                                   |                          | or use a GenServer/Agent collector that batches     |
|    |                                   |                          | writes. At minimum, use Task.Supervisor.start_child |  
|    |                                   |                          | with a dedicated supervisor.                        |
| B2 | toggle_debug_panel latch bug —    | blah.ex:100              | Change to assign(:debug_log_enabled?, new_panel) or |
|    | debug_log_enabled? never resets   |                          | introduce a separate debug_panel_ever_opened? flag. |
|    | to false after first open         |                          |                                                     |
"""

html = MDEx.to_html!(markdown, plugins: [MdexMultilineCells])
```

### 2. Explicit Line Continuation (`\`) & `<br>` Tags

```elixir
markdown = """
| Feature | Details | Status |
| :--- | :--- | :---: |
| **Multi-line Cells** | Line 1 of description \\
Line 2 of description with `code` | Active |
| **Rich Formatting** | **Bold Line 1**<br>[Elixir Docs](https://elixir-lang.org) | Done |
"""

html = MDEx.to_html!(markdown, plugins: [MdexMultilineCells])
```

### 3. Via `MDEx.new/1`

Attach the plugin when initializing an `MDEx.Document`:

```elixir
MDEx.new(markdown: markdown, plugins: [MdexMultilineCells])
|> MDEx.to_html!()
```

### 4. Direct Attachment

```elixir
MDEx.new(markdown: markdown)
|> MdexMultilineCells.attach(render_as: :paragraph)
|> MDEx.to_html!()
```

---

## Configuration & Plugin Options

Options can be passed as a keyword list when attaching the plugin:

```elixir
MDEx.to_html!(markdown, plugins: [{MdexMultilineCells, render_as: :paragraph, guess_multiline: true}])
```

| Option | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `:guess_multiline` | `boolean()` | `true` | Infers multi-line cell continuations when a row's key column is empty. |
| `:key_column` | `non_neg_integer()` | `0` | 0-indexed position of the key column used for multi-line continuation guessing. |
| `:render_as` | `:line_break` \| `:paragraph` \| `:html_br` | `:line_break` | Controls how multi-line cell line segments render in HTML/AST output. |
| `:continuation_syntax` | `:all` \| `:backslash` \| `:unclosed` | `:all` | Specifies which multi-line syntax to process in table source. |
| `:strip_indentation` | `boolean()` | `true` | Whether to strip leading indentation on continuation lines. |

---

## Generated HTML Output Examples

### Default (`render_as: :line_break`)

```html
<table>
<thead>
<tr>
<th>#</th>
<th>Issue</th>
<th>Location</th>
<th>Suggested Fix</th>
</tr>
</thead>
<tbody>
<tr>
<td>B1</td>
<td>Synchronous DB writes in hot path</td>
<td>orchestrator.ex:890, 425</td>
<td>Wrap StepMetrics.record_metric in Task.start<br />
or use a GenServer/Agent collector that batches<br />
writes. At minimum, use Task.Supervisor.start_child<br />
with a dedicated supervisor.</td>
</tr>
</tbody>
</table>
```

### Paragraph Mode (`render_as: :paragraph`)

```html
<table>
<thead>
<tr>
<th><p>Item</p></th>
<th><p>Description</p></th>
</tr>
</thead>
<tbody>
<tr>
<td><p>Task 1</p></td>
<td>
<p>Line 1 of description</p>
<p>Line 2 of description</p>
</td>
</tr>
</tbody>
</table>
```

---

## License

This project is licensed under the [MIT License](LICENSE).
