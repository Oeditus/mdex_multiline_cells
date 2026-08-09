defmodule MdexMultilineCells.AST do
  @moduledoc """
  AST node transformation functions for MDEx multiline table cells.
  """

  @doc """
  Transforms AST nodes in a document to process line break markers within table cells according to options.
  """
  def transform(doc, opts \\ []) do
    render_as = Keyword.get(opts, :render_as, :line_break)

    MDEx.traverse_and_update(doc, fn
      %MDEx.TableCell{nodes: nodes} = cell ->
        new_nodes = transform_cell_nodes(nodes, render_as)
        %{cell | nodes: new_nodes}

      node ->
        node
    end)
  end

  defp transform_cell_nodes(nodes, :line_break) do
    Enum.flat_map(nodes, fn
      %MDEx.HtmlInline{literal: lit} = node ->
        if br_tag?(lit) do
          [%MDEx.LineBreak{sourcepos: node.sourcepos}]
        else
          [node]
        end

      %MDEx.Text{literal: text} = node ->
        split_text_linebreaks(node, text, %MDEx.LineBreak{sourcepos: node.sourcepos})

      %{nodes: sub_nodes} = node when is_list(sub_nodes) ->
        [%{node | nodes: transform_cell_nodes(sub_nodes, :line_break)}]

      node ->
        [node]
    end)
  end

  defp transform_cell_nodes(nodes, :paragraph) do
    nodes
    |> Enum.chunk_by(&br_node?/1)
    |> Enum.flat_map(&transform_paragraph_chunk/1)
  end

  defp transform_cell_nodes(nodes, :html_br) do
    Enum.flat_map(nodes, fn
      %MDEx.HtmlInline{literal: lit} = node ->
        if br_tag?(lit) do
          [%MDEx.HtmlInline{node | literal: "<br />"}]
        else
          [node]
        end

      %MDEx.LineBreak{} = node ->
        [%MDEx.HtmlInline{sourcepos: node.sourcepos, literal: "<br />"}]

      %MDEx.Text{literal: text} = node ->
        split_text_linebreaks(node, text, %MDEx.HtmlInline{
          sourcepos: node.sourcepos,
          literal: "<br />"
        })

      %{nodes: sub_nodes} = node when is_list(sub_nodes) ->
        [%{node | nodes: transform_cell_nodes(sub_nodes, :html_br)}]

      node ->
        [node]
    end)
  end

  defp br_node?(%MDEx.HtmlInline{literal: lit}), do: br_tag?(lit)
  defp br_node?(%MDEx.LineBreak{}), do: true
  defp br_node?(_), do: false

  defp transform_paragraph_chunk([%MDEx.HtmlInline{literal: lit}] = chunk) do
    if br_tag?(lit), do: [], else: [%MDEx.Paragraph{nodes: chunk}]
  end

  defp transform_paragraph_chunk([%MDEx.LineBreak{}]) do
    []
  end

  defp transform_paragraph_chunk(sub_nodes) do
    trimmed_nodes = clean_paragraph_nodes(sub_nodes)
    [%MDEx.Paragraph{nodes: trimmed_nodes}]
  end

  defp br_tag?(literal) when is_binary(literal) do
    String.match?(String.trim(literal), ~r/^<br\s*\/?>$/i)
  end

  defp br_tag?(_), do: false

  defp clean_paragraph_nodes(nodes) do
    Enum.map(nodes, fn
      %MDEx.Text{literal: text} = node ->
        %MDEx.Text{node | literal: String.trim(text)}

      node ->
        node
    end)
  end

  defp split_text_linebreaks(%MDEx.Text{} = node, text, break_node) do
    if String.contains?(text, "<br") or String.contains?(text, "\\\\") do
      parts = String.split(text, ~r/\\{2}|<br\s*\/?>/i)

      parts
      |> Enum.intersperse(:linebreak)
      |> Enum.map(fn
        :linebreak -> break_node
        str -> %MDEx.Text{node | literal: String.trim_trailing(str)}
      end)
    else
      [node]
    end
  end
end
