defmodule MdexMultilineCells.ASTTest do
  use ExUnit.Case, async: true

  alias MdexMultilineCells.AST

  describe "AST.transform/2 with :line_break mode" do
    test "replaces html <br> tags with MDEx.LineBreak" do
      md = "| Header |\n| --- |\n| Cell<br>Next |"
      doc = MDEx.new(markdown: md, extension: [table: true]) |> MDEx.Document.run()
      transformed = AST.transform(doc, render_as: :line_break)
      html = MDEx.to_html!(transformed)

      assert html =~ "Cell<br />\nNext"
    end

    test "preserves non-br html inline tags" do
      md = "| Header |\n| --- |\n| <span>custom</span> |"
      doc = MDEx.new(markdown: md, extension: [table: true]) |> MDEx.Document.run()
      transformed = AST.transform(doc, render_as: :line_break)
      html = MDEx.to_html!(transformed, render: [unsafe: true])

      assert html =~ "<span>custom</span>"
    end

    test "transforms text linebreaks when present in AST" do
      md = "| Header |\n| --- |\n| Part 1\\\\Part 2 |"
      doc = MdexMultilineCells.parse!(md, render_as: :line_break)
      transformed = AST.transform(doc, render_as: :line_break)
      html = MDEx.to_html!(transformed)

      assert html =~ "Part 1<br />\nPart 2"
    end
  end

  describe "AST.transform/2 with :html_br mode" do
    test "replaces <br> and LineBreak nodes with HtmlInline <br />" do
      md = "| Header |\n| --- |\n| Line 1<br>Line 2 |"
      doc = MDEx.new(markdown: md, extension: [table: true]) |> MDEx.Document.run()
      transformed = AST.transform(doc, render_as: :html_br)
      html = MDEx.to_html!(transformed, render: [unsafe: true])

      assert html =~ "Line 1<br />Line 2"
    end

    test "preserves non-br inline tags in html_br mode" do
      md = "| Header |\n| --- |\n| <span>tag</span> |"
      doc = MDEx.new(markdown: md, extension: [table: true]) |> MDEx.Document.run()
      transformed = AST.transform(doc, render_as: :html_br)
      html = MDEx.to_html!(transformed, render: [unsafe: true])

      assert html =~ "<span>tag</span>"
    end

    test "replaces LineBreak AST node with HtmlInline <br />" do
      md = "| Header |\n| --- |\n| Line 1 \\\nLine 2 |"
      doc = MdexMultilineCells.parse!(md, render_as: :line_break)
      transformed = AST.transform(doc, render_as: :html_br)
      html = MDEx.to_html!(transformed, render: [unsafe: true])

      assert html =~ "Line 1 <br />Line 2"
    end
  end

  describe "AST.transform/2 with :paragraph mode" do
    test "wraps formatted nodes into paragraphs" do
      md = "| Header |\n| --- |\n| **Bold 1**<br>*Italic 2* |"
      doc = MDEx.new(markdown: md, extension: [table: true]) |> MDEx.Document.run()
      transformed = AST.transform(doc, render_as: :paragraph)
      html = MDEx.to_html!(transformed)

      assert html =~ "<p><strong>Bold 1</strong></p>"
      assert html =~ "<p><em>Italic 2</em></p>"
    end

    test "handles non-br html inline tags inside paragraph mode chunks" do
      md = "| Header |\n| --- |\n| <span>tag 1</span><br><span>tag 2</span> |"
      doc = MDEx.new(markdown: md, extension: [table: true]) |> MDEx.Document.run()
      transformed = AST.transform(doc, render_as: :paragraph)
      html = MDEx.to_html!(transformed, render: [unsafe: true])

      assert html =~ "<p><span>tag 1</span></p>"
      assert html =~ "<p><span>tag 2</span></p>"
    end

    test "splits text segments in paragraph mode" do
      md = "| Header |\n| --- |\n| Para 1 \\ \nPara 2 |"
      doc = MdexMultilineCells.parse!(md, render_as: :paragraph)
      html = MDEx.to_html!(doc)

      assert html =~ "<p>Para 1</p>"
      assert html =~ "<p>Para 2</p>"
    end
  end
end
