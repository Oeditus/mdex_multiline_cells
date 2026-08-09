defmodule MdexMultilineCells do
  @moduledoc """
  An MDEx plugin that allows multi-line cells in Markdown tables.

  ## Options

  - `:render_as` - How multi-line content within table cells should be rendered in the HTML/AST output.
    - `:line_break` (default) - Renders line breaks inside table cells as `<br />` (`MDEx.LineBreak`) preserving inline formatting.
    - `:paragraph` - Wraps each multi-line cell line segment in `<p>` paragraph blocks.
    - `:html_br` - Renders line breaks as raw `<br />` HTML inline nodes (automatically sets `render: [unsafe: true]`).
  - `:guess_multiline` - Boolean indicating whether to infer multiline cell continuations based on empty key columns (e.g. 1st column empty). Defaults to `true`.
  - `:key_column` - Integer index of the primary key column used for multiline row guessing (0-indexed). Defaults to `0` (1st column).
  - `:continuation_syntax` - Which Markdown continuation syntax to recognize in raw tables.
    - `:all` (default) - Recognizes trailing backslashes (`\\`), empty key column continuations, unclosed table cell lines, and explicit `<br>` tags.
    - `:backslash` - Recognizes only trailing backslash (`\\`) line continuation.
    - `:unclosed` - Recognizes unclosed multi-line source table rows.
  - `:strip_indentation` - Boolean indicating whether to strip leading whitespace on continuation lines. Defaults to `true`.

  ## Usage

  ### With MDEx.new/1

      MDEx.new(markdown: "| Col 1 |\\n| --- |\\n| Line 1 \\\\ \\nLine 2 |", plugins: [MdexMultilineCells])
      |> MDEx.to_html!()

  ### With MDEx.to_html!/2

      MDEx.to_html!(markdown, plugins: [MdexMultilineCells])

  ### With Plugin Options

      MDEx.to_html!(markdown, plugins: [{MdexMultilineCells, render_as: :paragraph, guess_multiline: true}])

  ### Direct Attachment

      doc
      |> MdexMultilineCells.attach(render_as: :line_break)
      |> MDEx.to_html!()

  """

  alias MDEx.Document
  alias MdexMultilineCells.AST
  alias MdexMultilineCells.Preprocessor

  @plugin_options [
    :multiline_cells,
    :render_as,
    :continuation_syntax,
    :strip_indentation,
    :guess_multiline,
    :key_column
  ]

  @doc """
  Attaches the multiline cells plugin to an `MDEx.Document`.
  """
  def attach(%Document{} = document, options \\ []) do
    opts = Keyword.merge(default_options(), options)

    # 1. Preprocess raw markdown buffer if present
    document = preprocess_buffer(document, opts)

    # 2. If render_as: :html_br, set render: [unsafe: true] to allow raw html
    document =
      if opts[:render_as] == :html_br do
        Document.put_render_options(document, unsafe: true)
      else
        document
      end

    # 3. Register options, enable GFM table extension, and append AST transformation step
    document
    |> Document.register_options(@plugin_options)
    |> Document.put_options(opts)
    |> Document.put_extension_options(table: true)
    |> Document.append_steps(transform_multiline_cells: &transform_ast(&1, opts))
  end

  @doc """
  Convenience function to parse and convert markdown to HTML with the multiline cells plugin attached.
  """
  def to_html!(markdown, options \\ []) when is_binary(markdown) do
    {plugin_opts, mdex_opts} = extract_plugin_opts(options)

    MDEx.new(markdown: markdown, plugins: [{__MODULE__, plugin_opts}])
    |> MDEx.to_html!(mdex_opts)
  end

  @doc """
  Convenience function to parse markdown into a document with the multiline cells plugin attached.
  """
  def parse!(markdown, options \\ []) when is_binary(markdown) do
    {plugin_opts, _mdex_opts} = extract_plugin_opts(options)

    MDEx.new(markdown: markdown, plugins: [{__MODULE__, plugin_opts}])
    |> Document.run()
  end

  defp preprocess_buffer(%Document{buffer: [markdown]} = doc, opts) when is_binary(markdown) do
    processed = Preprocessor.preprocess(markdown, opts)
    %{doc | buffer: [processed]}
  end

  defp preprocess_buffer(doc, _opts), do: doc

  defp transform_ast(doc, _opts) do
    plugin_opts = [
      render_as: Document.get_option(doc, :render_as) || :line_break,
      continuation_syntax: Document.get_option(doc, :continuation_syntax) || :all,
      strip_indentation: Document.get_option(doc, :strip_indentation),
      guess_multiline: Document.get_option(doc, :guess_multiline),
      key_column: Document.get_option(doc, :key_column)
    ]

    AST.transform(doc, plugin_opts)
  end

  defp default_options do
    [
      render_as: :line_break,
      continuation_syntax: :all,
      strip_indentation: true,
      guess_multiline: true,
      key_column: 0
    ]
  end

  defp extract_plugin_opts(options) do
    Keyword.split(options, @plugin_options)
  end
end
