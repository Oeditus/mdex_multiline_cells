defmodule MdexMultilineCells.Preprocessor do
  @moduledoc """
  Preprocesses Markdown source text to support multi-line table rows.

  Normalizes multi-line table cell syntax into standard single-line Markdown table rows
  with `<br>` line break markers inside cell contents.
  """

  @doc """
  Preprocesses raw Markdown text before it is parsed into AST by MDEx.
  """
  def preprocess(markdown, opts \\ []) when is_binary(markdown) do
    continuation_syntax = Keyword.get(opts, :continuation_syntax, :all)
    strip_indentation = Keyword.get(opts, :strip_indentation, true)
    guess_multiline = Keyword.get(opts, :guess_multiline, true)
    key_column = Keyword.get(opts, :key_column, 0)

    lines = String.split(markdown, ~r/\r?\n/)

    {processed_lines, _state} =
      Enum.reduce(lines, {[], :out_of_table}, fn line, {acc, state} ->
        process_line(
          line,
          acc,
          state,
          continuation_syntax,
          strip_indentation,
          guess_multiline,
          key_column
        )
      end)

    processed_lines
    |> Enum.reverse()
    |> Enum.join("\n")
  end

  defp process_line(line, acc, {:in_code_block, fence}, _syntax, _strip_indent, _guess, _key_col) do
    trimmed = String.trim(line)

    if String.starts_with?(trimmed, fence) do
      {[line | acc], :out_of_table}
    else
      {[line | acc], {:in_code_block, fence}}
    end
  end

  defp process_line(line, acc, :out_of_table, _syntax, _strip_indent, _guess, _key_col) do
    trimmed = String.trim(line)

    cond do
      fence = code_fence_start(trimmed) ->
        {[line | acc], {:in_code_block, fence}}

      table_row?(trimmed) ->
        pipes = count_pipes(trimmed)
        processed_line = convert_inline_double_backslashes(line)
        {[processed_line | acc], {:in_table, pipes}}

      true ->
        {[line | acc], :out_of_table}
    end
  end

  defp process_line(
         line,
         acc,
         {:in_table, expected_pipes},
         syntax,
         strip_indent,
         guess_multiline,
         key_column
       ) do
    trimmed = String.trim(line)

    cond do
      fence = code_fence_start(trimmed) ->
        {[line | acc], {:in_code_block, fence}}

      trimmed == "" ->
        {[line | acc], :out_of_table}

      empty_key_continuation?(acc, line, guess_multiline, key_column) ->
        join_empty_key_row(line, acc, expected_pipes)

      backslash_continuation?(acc, syntax) ->
        join_backslash_continuation(line, acc, expected_pipes, strip_indent)

      unclosed_continuation?(acc, line, syntax, expected_pipes) ->
        join_unclosed_continuation(line, acc, expected_pipes, strip_indent)

      table_row?(trimmed) ->
        pipes = count_pipes(trimmed)
        processed_line = convert_inline_double_backslashes(line)
        {[processed_line | acc], {:in_table, max(expected_pipes, pipes)}}

      true ->
        {[line | acc], :out_of_table}
    end
  end

  defp empty_key_continuation?(acc, line, true, key_column) when acc != [] do
    empty_key_row?(line, hd(acc), key_column)
  end

  defp empty_key_continuation?(_acc, _line, _guess, _key_col), do: false

  defp backslash_continuation?(acc, syntax) when acc != [] and syntax in [:all, :backslash] do
    has_trailing_backslash?(hd(acc))
  end

  defp backslash_continuation?(_acc, _syntax), do: false

  defp unclosed_continuation?(acc, line, syntax, expected_pipes)
       when acc != [] and syntax in [:all, :unclosed] do
    unclosed_row?(hd(acc), line, expected_pipes)
  end

  defp unclosed_continuation?(_acc, _line, _syntax, _expected), do: false

  defp join_empty_key_row(line, acc, expected_pipes) do
    [prev | rest] = acc
    merged = merge_cell_by_cell(prev, line)
    new_pipes = count_pipes(merged)
    {[merged | rest], {:in_table, max(expected_pipes, new_pipes)}}
  end

  defp join_backslash_continuation(line, acc, expected_pipes, strip_indent) do
    [prev | rest] = acc
    cleaned_prev = String.replace(prev, ~r/\\\s*$/, "")
    next_part = if strip_indent, do: String.trim_leading(line), else: line
    joined = cleaned_prev <> "<br>" <> convert_inline_double_backslashes(next_part)
    new_pipes = count_pipes(joined)
    {[joined | rest], {:in_table, max(expected_pipes, new_pipes)}}
  end

  defp join_unclosed_continuation(line, acc, expected_pipes, strip_indent) do
    [prev | rest] = acc
    next_part = if strip_indent, do: String.trim_leading(line), else: line
    joined = prev <> "<br>" <> convert_inline_double_backslashes(next_part)
    new_pipes = count_pipes(joined)
    {[joined | rest], {:in_table, max(expected_pipes, new_pipes)}}
  end

  defp empty_key_row?(line, prev_line, key_col_idx) do
    trimmed_curr = String.trim(line)
    trimmed_prev = String.trim(prev_line)

    if table_row?(trimmed_curr) and not delimiter_row?(trimmed_curr) and
         not delimiter_row?(trimmed_prev) do
      cells = parse_row_cells(trimmed_curr)
      key_val = Enum.at(cells, key_col_idx, "")
      key_val == "" and cells != []
    else
      false
    end
  end

  defp merge_cell_by_cell(prev_line, curr_line) do
    prev_cells = parse_row_cells(prev_line)
    curr_cells = parse_row_cells(curr_line)
    max_len = max(length(prev_cells), length(curr_cells))

    merged_cells =
      0..(max_len - 1)
      |> Enum.map(fn i ->
        p = Enum.at(prev_cells, i, "")
        c = Enum.at(curr_cells, i, "")
        c_converted = convert_inline_double_backslashes(c)

        cond do
          p != "" and c != "" -> p <> "<br>" <> c_converted
          p != "" -> p
          c != "" -> c_converted
          true -> ""
        end
      end)

    format_row_cells(merged_cells)
  end

  defp parse_row_cells(line) do
    line
    |> String.trim()
    |> String.trim_leading("|")
    |> String.trim_trailing("|")
    |> String.split(~r/(?<!\\)\|/)
    |> Enum.map(&String.trim/1)
  end

  defp format_row_cells(cells) do
    "| " <> Enum.join(cells, " | ") <> " |"
  end

  defp convert_inline_double_backslashes(line) do
    if delimiter_row?(line) do
      line
    else
      String.replace(line, ~r/(?<!\\)\\\\(?!\|)/, "<br>")
    end
  end

  defp delimiter_row?(line) do
    trimmed = String.trim(line)
    String.match?(trimmed, ~r/^\|?[\s:\-]+\|[\s:\-|]*$/)
  end

  defp code_fence_start(line) do
    cond do
      String.starts_with?(line, "```") -> "```"
      String.starts_with?(line, "~~~") -> "~~~"
      true -> nil
    end
  end

  defp table_row?(line) do
    String.starts_with?(line, "|") or
      (String.contains?(line, "|") and not String.starts_with?(line, "#"))
  end

  defp count_pipes(line) do
    line
    |> String.replace("\\|", "")
    |> String.graphemes()
    |> Enum.count(&(&1 == "|"))
  end

  defp has_trailing_backslash?(line) do
    String.match?(line, ~r/\\\s*$/)
  end

  defp unclosed_row?(prev_line, current_line, expected_pipes) do
    prev_pipes = count_pipes(prev_line)
    trimmed_current = String.trim(current_line)
    trimmed_prev = String.trim(prev_line)

    if delimiter_row?(trimmed_prev) do
      false
    else
      (prev_pipes > 0 and prev_pipes < expected_pipes) or
        (!String.starts_with?(trimmed_current, "|") and String.starts_with?(trimmed_prev, "|"))
    end
  end
end
