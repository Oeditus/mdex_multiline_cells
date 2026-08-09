defmodule MdexMultilineCellsTest do
  use ExUnit.Case, async: true

  alias MdexMultilineCells

  @fixture_path "priv/fixtures/multiline-cell.md"

  describe "to_html!/2 integration with empty key column guessing" do
    test "correctly parses multiline table from priv/fixtures/multiline-cell.md fixture" do
      markdown = File.read!(@fixture_path)
      html = MdexMultilineCells.to_html!(markdown)

      # Check row B1
      assert html =~ "<td>B1</td>"
      assert html =~ "<td>Synchronous DB writes in hot path</td>"
      assert html =~ "<td>orchestrator.ex:890, 425</td>"

      assert html =~
               "<td>Wrap StepMetrics.record_metric in Task.start<br />\nor use a GenServer/Agent collector that batches<br />\nwrites. At minimum, use Task.Supervisor.start_child<br />\nwith a dedicated supervisor.</td>"

      # Check row B2
      assert html =~ "<td>B2</td>"

      assert html =~
               "<td>toggle_debug_panel latch bug —<br />\ndebug_log_enabled? never resets<br />\nto false after first open</td>"

      assert html =~ "<td>blah.ex:100</td>"

      assert html =~
               "<td>Change to assign(:debug_log_enabled?, new_panel) or<br />\nintroduce a separate debug_panel_ever_opened? flag.</td>"

      # Check row B3
      assert html =~ "<td>B3</td>"
      assert html =~ "<td>Mix.env() compile-time divergence</td>"

      # Check row B4
      assert html =~ "<td>B4</td>"

      assert html =~
               "<td>progress_reassurance/4 can crash<br />\non nil stats</td>"

      # Check row B5
      assert html =~ "<td>B5</td>"
      assert html =~ "<td>Flag rename leaves orphaned</td>"
    end

    test "allows disabling empty key column guessing with guess_multiline: false" do
      markdown = """
      | # | Details |
      | --- | --- |
      | 1 | Row 1 |
      |   | Separate empty row |
      """

      html = MdexMultilineCells.to_html!(markdown, guess_multiline: false)

      # Should have two distinct table rows <tr>
      assert Enum.count(Regex.scan(~r/<tr>/, html)) == 3
    end
  end

  describe "parse!/2 convenience function" do
    test "parses markdown into MDEx.Document struct with AST nodes" do
      markdown = """
      | Header |
      | --- |
      | Cell 1 \\
      Cell 2 |
      """

      doc = MdexMultilineCells.parse!(markdown)

      assert %MDEx.Document{} = doc
      assert doc.nodes != []
    end
  end

  describe "attach/2 direct invocation" do
    test "handles document without buffer" do
      doc = %MDEx.Document{}
      attached = MdexMultilineCells.attach(doc)

      assert %MDEx.Document{} = attached
    end
  end

  describe "to_html!/2 integration with explicit line breaks" do
    test "renders multiline cells with inline backslash continuation" do
      markdown = """
      | Title | Content |
      | --- | --- |
      | **Task 1** | First line \\
      Second line with `code` |
      """

      html = MdexMultilineCells.to_html!(markdown)

      assert html =~ "<th>Title</th>"
      assert html =~ "<th>Content</th>"
      assert html =~ "<td><strong>Task 1</strong></td>"
      assert html =~ "<td>First line <br />\nSecond line with <code>code</code></td>"
    end

    test "renders multiline cells with double backslash (\\\\) inside text" do
      markdown = """
      | Title | Content |
      | --- | --- |
      | Item | Line 1\\\\Line 2 |
      """

      html = MdexMultilineCells.to_html!(markdown)

      assert html =~ "<td>Line 1<br />\nLine 2</td>"
    end

    test "renders multiline cells with explicit <br> tags while preserving rich formatting" do
      markdown = """
      | Item | Details |
      | --- | --- |
      | *Alpha* | **Bold Line 1**<br>[Elixir Link](https://elixir-lang.org) |
      """

      html = MdexMultilineCells.to_html!(markdown)

      assert html =~ "<td><em>Alpha</em></td>"

      assert html =~
               "<td><strong>Bold Line 1</strong><br />\n<a href=\"https://elixir-lang.org\">Elixir Link</a></td>"
    end

    test "supports table alignment options" do
      markdown = """
      | Left | Center | Right |
      | :--- | :---: | ---: |
      | L1 \\
      L2 | C1 | R1 |
      """

      html = MdexMultilineCells.to_html!(markdown)

      assert html =~ "align=\"left\""
      assert html =~ "align=\"center\""
      assert html =~ "align=\"right\""
      assert html =~ "L1 <br />\nL2"
    end

    test "supports render_as: :paragraph option" do
      markdown = """
      | Col 1 |
      | --- |
      | **Line 1**<br>*Line 2* |
      """

      html = MdexMultilineCells.to_html!(markdown, render_as: :paragraph)

      assert html =~ "<p><strong>Line 1</strong></p>"
      assert html =~ "<p><em>Line 2</em></p>"
    end

    test "supports render_as: :html_br option" do
      markdown = """
      | Col 1 |
      | --- |
      | Line 1 \\
      Line 2 |
      """

      html = MdexMultilineCells.to_html!(markdown, render_as: :html_br)

      assert html =~ "Line 1 <br />Line 2"
    end

    test "works attached via MDEx.new/1 plugins list" do
      markdown = """
      | Header |
      | --- |
      | Part 1 \\
      Part 2 |
      """

      html =
        MDEx.new(markdown: markdown, plugins: [MdexMultilineCells])
        |> MDEx.to_html!()

      assert html =~ "<td>Part 1 <br />\nPart 2</td>"
    end

    test "works attached with options tuple in MDEx.new/1" do
      markdown = """
      | Header |
      | --- |
      | Part 1 \\
      Part 2 |
      """

      html =
        MDEx.new(markdown: markdown, plugins: [{MdexMultilineCells, render_as: :paragraph}])
        |> MDEx.to_html!()

      assert html =~ "<p>Part 1</p>"
      assert html =~ "<p>Part 2</p>"
    end

    test "attaches via MDEx.Document.put_plugins/2" do
      markdown = """
      | Header |
      | --- |
      | Part 1 \\
      Part 2 |
      """

      html =
        MDEx.new(markdown: markdown)
        |> MDEx.Document.put_plugins([MdexMultilineCells])
        |> MDEx.to_html!()

      assert html =~ "<td>Part 1 <br />\nPart 2</td>"
    end

    test "handles multiple tables and text outside tables cleanly" do
      markdown = """
      # Introduction

      Table 1:

      | A | B |
      | --- | --- |
      | A1 \\
      A2 | B1 |

      Text in between.

      Table 2:

      | C | D |
      | --- | --- |
      | C1 | D1 <br> D2 |
      """

      html = MdexMultilineCells.to_html!(markdown)

      assert html =~ "<h1>Introduction</h1>"
      assert html =~ "<td>A1 <br />\nA2</td>"
      assert html =~ "<td>D1 <br />\n D2</td>"
      assert html =~ "<p>Text in between.</p>"
    end
  end
end
